"""Shared helpers: HTTP client, JSON storage, series upsert, collector status."""
from __future__ import annotations

import json
import os
import time
import traceback
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any, Callable

import httpx

ROOT = Path(__file__).resolve().parent.parent
DATA = ROOT / "data"
SERIES_DIR = DATA / "series"
MANUAL_DIR = DATA / "manual"
STATUS_FILE = DATA / "status.json"
LATEST_FILE = DATA / "latest.json"

UA = ("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
      "(KHTML, like Gecko) Chrome/130.0 Safari/537.36")
TEHRAN = timezone(timedelta(hours=3, minutes=30))  # Iran has had no DST since 2022


def now_utc() -> datetime:
    return datetime.now(timezone.utc).replace(microsecond=0)


def iso(dt: datetime) -> str:
    return dt.astimezone(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def parse_iso(s: str | None) -> datetime | None:
    if not s:
        return None
    return datetime.fromisoformat(s.replace("Z", "+00:00"))


def in_actions() -> bool:
    return os.environ.get("GITHUB_ACTIONS") == "true"


def client(timeout: float = 45) -> httpx.Client:
    return httpx.Client(
        headers={"User-Agent": UA, "Accept-Language": "en-US,en;q=0.9,fa;q=0.8"},
        timeout=timeout,
        follow_redirects=True,
    )


def request(c: httpx.Client, method: str, url: str, tries: int = 3, **kw) -> httpx.Response:
    """HTTP with a few retries and backoff; raises the last error."""
    last: Exception | None = None
    for i in range(tries):
        try:
            r = c.request(method, url, **kw)
            if r.status_code in (429, 500, 502, 503, 504):
                raise httpx.HTTPStatusError(f"HTTP {r.status_code}", request=r.request, response=r)
            r.raise_for_status()
            return r
        except httpx.HTTPError as e:
            last = e
            time.sleep(2 * (i + 1))
    assert last is not None
    raise last


# ---------------------------------------------------------------- JSON storage

def dumps(o: Any, level: int = 0) -> str:
    """Pretty JSON with short lists (e.g. one data point) kept on one line: small git diffs."""
    pad = " " * level
    if isinstance(o, dict):
        if not o:
            return "{}"
        # keys are always strings in JSON (json.dumps would quote an int key; do the same)
        items = [f"{pad} {json.dumps(str(k), ensure_ascii=False)}: {dumps(v, level + 1)}" for k, v in o.items()]
        return "{\n" + ",\n".join(items) + "\n" + pad + "}"
    if isinstance(o, list):
        if all(not isinstance(x, (dict, list)) for x in o):
            return json.dumps(o, ensure_ascii=False)
        items = [pad + " " + dumps(x, level + 1) for x in o]
        return "[\n" + ",\n".join(items) + "\n" + pad + "]"
    return json.dumps(o, ensure_ascii=False)


def read_json(path: Path, default: Any = None) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        return default


def write_json(path: Path, obj: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(".tmp")
    tmp.write_text(dumps(obj) + "\n", encoding="utf-8", newline="\n")
    tmp.replace(path)


# ---------------------------------------------------------------- series

def load_series(sid: str) -> dict:
    from .series_meta import SERIES

    s = read_json(SERIES_DIR / f"{sid}.json") or {"id": sid, "points": []}
    s.update({k: v for k, v in SERIES[sid].items()})  # metadata always comes from code
    s["id"] = sid
    return s


def save_series(s: dict) -> None:
    s["points"] = sorted(s.get("points", []), key=lambda p: p[0])
    write_json(SERIES_DIR / f"{s['id']}.json", s)


def upsert(s: dict, points: list, fetched_at: str | None = None) -> int:
    """Merge points ([date, value, ...]) by date; newer values win. Returns number changed."""
    cur = {p[0]: p for p in s.get("points", [])}
    changed = 0
    for p in points:
        p = list(p)
        if cur.get(p[0]) != p:
            cur[p[0]] = p
            changed += 1
    s["points"] = sorted(cur.values(), key=lambda p: p[0])
    s["fetched_at"] = fetched_at or iso(now_utc())
    return changed


def fetched_recently(s: dict, hours: float) -> bool:
    t = parse_iso(s.get("fetched_at"))
    return bool(t and now_utc() - t < timedelta(hours=hours) and s.get("points"))


# ---------------------------------------------------------------- status

def run_collector(name: str, title: str, fn: Callable[[], str | None]) -> bool:
    """Run one collector; never raises. Success/error goes to data/status.json."""
    st = read_json(STATUS_FILE, {}) or {}
    col = st.setdefault("collectors", {}).setdefault(name, {})
    col["title"] = title
    col["last_attempt"] = iso(now_utc())
    try:
        note = fn()
        col.update(ok=True, last_success=col["last_attempt"], error=None, note=note)
        print(f"[ok]   {name}: {note or ''}")
        ok = True
    except Exception as e:  # noqa: BLE001 — a broken source must not stop the others
        col.update(ok=False, error=f"{type(e).__name__}: {e}"[:500])
        print(f"[fail] {name}: {col['error']}")
        traceback.print_exc()
        ok = False
    st["updated_at"] = iso(now_utc())
    write_json(STATUS_FILE, st)
    return ok
