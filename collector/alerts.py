"""Price alerts via ntfy (https://ntfy.sh — free, no account).

Rules: data/manual/alerts.json. State (public, no topic): data/alerts.json.
The ntfy topic is a secret (whoever knows it can read the messages): it comes only from the
environment variable NTFY_TOPIC (a GitHub Actions secret), never from the repository.
"""
from __future__ import annotations

import os

import httpx

from .common import DATA, LATEST_FILE, MANUAL_DIR, iso, now_utc, read_json, write_json
from .parsers import iso_to_jalali

NTFY_URL = os.environ.get("NTFY_SERVER", "https://ntfy.sh")
APP_URL = "https://nejatimehdi-prog.github.io/aluminium-dashboard/"
RULES_FILE = MANUAL_DIR / "alerts.json"
STATE_FILE = DATA / "alerts.json"
OPS = {"above", "below", "change_above", "stale"}

FA_DIGITS = str.maketrans("0123456789.,", "۰۱۲۳۴۵۶۷۸۹٫٬")


def fa(v: float, digits: int = 0) -> str:
    s = f"{v:,.{digits}f}" if digits else f"{v:,.0f}"
    return s.translate(FA_DIGITS)


def series_view(latest: dict, sid: str) -> dict | None:
    """{title, unit, value, change_pct, date, stale} for a card or the gap."""
    if sid == "gap":
        g = latest.get("gap")
        if not g:
            return None
        return {"title": "شکاف قیمت ایران و جهان", "unit": "٪", "value": g["value_pct"],
                "change_pct": None, "date": g["dates"]["iran"], "stale": g.get("stale", False)}
    c = latest.get("cards", {}).get(sid)
    if not c or c.get("value") is None:
        return None
    return {"title": c["title"], "unit": c["unit_fa"], "value": c["value"], "change_pct": c.get("change_pct"),
            "date": c.get("date"), "stale": c.get("stale", False), "stale_reason": c.get("stale_reason")}


def evaluate(rule: dict, view: dict | None, prev: dict, today: str) -> tuple[str, str | None, str | None]:
    """→ (status, dedupe key or None, message or None). A message is due when the key is new."""
    if view is None:
        return "no_data", None, None
    op, v, t = rule["op"], rule.get("value"), view["title"]
    val = view["value"]
    if op == "above":
        met = val > v
        msg = f"{t} به {fa(val)} {view['unit']} رسید (بالای {fa(v)})"
        # one message per crossing: the key changes only when the condition flips
        return ("met" if met else "not_met"), ("crossed" if met else None), msg if met else None
    if op == "below":
        met = val < v
        msg = f"{t} به {fa(val)} {view['unit']} رسید (پایین‌تر از {fa(v)})"
        return ("met" if met else "not_met"), ("crossed" if met else None), msg if met else None
    if op == "change_above":
        ch = view.get("change_pct")
        if ch is None:
            return "no_data", None, None
        met = abs(ch) >= v
        sign = "افزایش" if ch > 0 else "کاهش"
        jd = iso_to_jalali(view["date"]).translate(FA_DIGITS) if view.get("date") else ""
        msg = f"{t}: {fa(abs(ch), 1)}٪ {sign} — اکنون {fa(val)} {view['unit']} ({jd})"
        return ("met" if met else "not_met"), (f"date:{view['date']}" if met else None), msg if met else None
    if op == "stale":
        met = bool(view.get("stale"))
        msg = f"{t} به‌روز نشده: {view.get('stale_reason') or 'منبع جواب نداد'}"
        return ("met" if met else "not_met"), (f"day:{today}" if met else None), msg if met else None
    raise ValueError(f"unknown op {op!r}")


def send(topic: str, title: str, message: str, tags: list[str]) -> None:
    # JSON publishing keeps the Persian title/message intact (HTTP headers would need encoding)
    r = httpx.post(NTFY_URL, json={"topic": topic, "title": title, "message": message, "tags": tags,
                                   "click": APP_URL, "priority": 4}, timeout=30)
    r.raise_for_status()


def check_alerts() -> str:
    cfg = read_json(RULES_FILE, {}) or {}
    rules = [r for r in cfg.get("rules", []) if r.get("id")]
    for r in rules:
        if r.get("op") not in OPS:
            raise ValueError(f"alerts.json: rule {r['id']} has unknown op {r.get('op')!r}")
    latest = read_json(LATEST_FILE, {}) or {}
    old = {r["id"]: r for r in (read_json(STATE_FILE, {}) or {}).get("rules", [])}
    topic = os.environ.get("NTFY_TOPIC", "").strip()
    today = now_utc().date().isoformat()
    out, sent, errors = [], 0, []
    for r in rules:
        prev = old.get(r["id"], {})
        st = {**{k: r.get(k) for k in ("id", "series", "op", "value", "enabled")},
              "last_key": prev.get("last_key"), "last_sent_at": prev.get("last_sent_at"),
              "last_message": prev.get("last_message")}
        if not r.get("enabled", True):
            st["status"] = "disabled"
            out.append(st)
            continue
        view = series_view(latest, r["series"])
        status, key, msg = evaluate(r, view, prev, today)
        st["status"], st["current"] = status, view["value"] if view else None
        if key is None:
            st["last_key"] = None  # condition cleared: re-arm
        elif key != prev.get("last_key") and msg:
            if topic:
                try:
                    send(topic, "هشدار شمش آلومینیوم", msg, ["bell"])
                    st.update(last_key=key, last_sent_at=iso(now_utc()), last_message=msg)
                    sent += 1
                except Exception as e:  # noqa: BLE001 — retry on the next run (key not stored)
                    errors.append(f"{r['id']}: {e}")
            else:
                # no topic yet: show the message in the app, but keep it due so it goes out once configured
                st["last_message"] = msg
        out.append(st)
    write_json(STATE_FILE, {"generated_at": iso(now_utc()), "configured": bool(topic), "rules": out})
    if errors:
        raise RuntimeError("ntfy: " + "; ".join(errors))
    if not topic:
        return "NTFY_TOPIC not set — alerts evaluated, nothing sent"
    return f"{sent} sent, {sum(1 for s in out if s.get('status') == 'met')} rules met"
