"""Builds data/latest.json (home-page cards) from the series files and data/status.json."""
from __future__ import annotations

from datetime import date, timedelta

from .common import LATEST_FILE, STATUS_FILE, iso, load_series, now_utc, read_json, write_json
from .series_meta import MAX_AGE_DAYS, SERIES

CARD_ORDER = ["lme_cash", "comex", "shfe", "ime_ingot", "iran_free_market", "fx_free", "fx_ime"]


def card(sid: str, status: dict) -> dict:
    s = load_series(sid)
    pts = s.get("points", [])
    meta = SERIES[sid]
    c = {k: meta[k] for k in ("title", "group", "unit", "unit_fa", "source", "source_url", "freq")}
    c["id"] = sid
    c["fetched_at"] = s.get("fetched_at")
    col = (status.get("collectors") or {}).get(meta["collector"], {})
    if not pts:
        c.update(value=None, stale=True, stale_reason="هنوز داده‌ای ثبت نشده")
        return c
    last = pts[-1]
    c.update(value=last[1], date=last[0])
    if sid == "comex" and s.get("latest"):
        c["time"] = s["latest"]["time"]
    if len(last) > 2 and isinstance(last[2], str):
        c["source"] = f"{meta['source']} — {last[2]}"
    if len(pts) > 1 and pts[-2][1]:
        c["prev_date"], c["prev_value"] = pts[-2][0], pts[-2][1]
        c["change_pct"] = round((last[1] / pts[-2][1] - 1) * 100, 2)
    reasons = []
    if col and not col.get("ok", True):
        reasons.append("آخرین تلاش برای به‌روزرسانی ناموفق بود")
    age = (date.today() - date.fromisoformat(last[0])).days
    if age > MAX_AGE_DAYS[meta["freq"]]:
        reasons.append(f"آخرین داده {age} روز پیش است")
    c["stale"] = bool(reasons)
    c["stale_reason"] = "؛ ".join(reasons) or None
    if sid == "ime_ingot" and s.get("detail"):
        c["detail"] = s["detail"]
    return c


def gap(cards: dict) -> dict | None:
    """Domestic ingot vs LME converted at a dollar rate: (Iran / (LME × FX) − 1) × 100."""
    ime, lme = cards.get("ime_ingot", {}), cards.get("lme_cash", {})
    if not ime.get("value") or not lme.get("value"):
        return None
    fx = None
    for fid in ("fx_free", "fx_ime"):  # free-market rate if entered recently, else IME rate
        f = cards.get(fid, {})
        if f.get("value") and (date.today() - date.fromisoformat(f["date"])).days <= 10:
            fx = f
            break
    if not fx:
        return None
    world_toman_kg = lme["value"] / 1000 * fx["value"]
    return {
        "value_pct": round((ime["value"] / world_toman_kg - 1) * 100, 1),
        "world_toman_per_kg": round(world_toman_kg),
        "iran_toman_per_kg": ime["value"],
        "fx_id": fx["id"], "fx_title": fx["title"], "fx_value": fx["value"],
        "dates": {"iran": ime["date"], "lme": lme["date"], "fx": fx["date"]},
        "source": f"محاسبه: {ime['title']} ÷ (LME نقدی × {fx['title']})",
        "stale": bool(ime.get("stale") or lme.get("stale") or fx.get("stale")),
    }


def build_latest() -> str:
    status = read_json(STATUS_FILE, {}) or {}
    cards = {sid: card(sid, status) for sid in CARD_ORDER}
    out = {"generated_at": iso(now_utc()), "order": CARD_ORDER, "cards": cards, "gap": gap(cards)}
    write_json(LATEST_FILE, out)
    return f"{sum(1 for c in cards.values() if c.get('value') is not None)}/{len(cards)} cards with data"
