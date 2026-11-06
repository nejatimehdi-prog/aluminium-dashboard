"""Iran aluminium foreign trade (tonnes, USD) from UN Comtrade + manual customs CSV.

Two Comtrade views:
- reported: what Iran itself reported (reporter 364, partner World). Latest year is often 2–3 years old.
- mirror: what partner countries reported trading with Iran (partner 364). Iran's exports = partners'
  imports from Iran; Iran's imports = partners' exports to Iran. Coverage depends on which countries
  have reported, so recent years are incomplete.
Output: data/trade.json
"""
from __future__ import annotations

import csv
import time
from datetime import date

import httpx

from . import parsers as P
from .common import DATA, MANUAL_DIR, client, iso, now_utc, read_json, write_json

URL = "https://comtradeapi.un.org/public/v1/preview/C/A/HS"
IRAN = 364
OUT = DATA / "trade.json"
CUSTOMS_FILE = MANUAL_DIR / "customs_trade.csv"

CATEGORIES = {
    "ingot": {"title": "شمش (7601)", "codes": ["7601"]},
    "scrap": {"title": "ضایعات (7602)", "codes": ["7602"]},
    "products": {"title": "محصولات (7604 تا 7616)", "codes": [str(c) for c in range(7604, 7617)]},
}
CAT_FA = {"شمش": "ingot", "ضایعات": "scrap", "محصولات": "products"}
FLOW_FA = {"صادرات": "export", "واردات": "import"}
# reporter codes that are aggregates, not countries
AGGREGATE_REPORTERS = {0, 97, 490, 899}

PARTNER_NAMES = {
    4: "افغانستان", 31: "آذربایجان", 51: "ارمنستان", 156: "چین", 268: "گرجستان", 276: "آلمان",
    356: "هند", 368: "عراق", 380: "ایتالیا", 398: "قزاقستان", 417: "قرقیزستان", 458: "مالزی",
    512: "عمان", 586: "پاکستان", 643: "روسیه", 682: "عربستان", 699: "هند", 704: "ویتنام",
    762: "تاجیکستان", 784: "امارات", 792: "ترکیه", 795: "ترکمنستان", 804: "اوکراین", 860: "ازبکستان",
    12: "الجزایر", 48: "بحرین", 410: "کره جنوبی", 392: "ژاپن", 414: "کویت", 634: "قطر",
}


def _get(c: httpx.Client, params: dict) -> list[dict]:
    """One preview call; the keyless endpoint answers 429 when called too fast."""
    for i in range(5):
        r = c.get(URL, params=params)
        if r.status_code == 429:
            time.sleep(15 * (i + 1))
            continue
        r.raise_for_status()
        j = r.json()
        if j.get("error"):
            raise RuntimeError(f"Comtrade: {j['error']}")
        data = j.get("data") or []
        if j.get("count", 0) >= 500:
            raise RuntimeError(f"Comtrade: 500-row limit reached for {params} — split the query")
        time.sleep(6)
        return data
    raise RuntimeError("Comtrade: still rate-limited after 5 tries")


def _totals(rows: list[dict], exclude_aggregates: bool) -> dict:
    """Sum the plain total rows (all transport modes, all customs procedures)."""
    t = {"tonnes": 0.0, "usd": 0.0, "reporters": set(), "weight_missing": 0, "by_partner": {}}
    for r in rows:
        if r.get("motCode") not in (0, None) or r.get("customsCode") not in ("C00", None) or r.get("partner2Code") not in (0, None):
            continue
        rep = r.get("reporterCode")
        if exclude_aggregates and rep in AGGREGATE_REPORTERS:
            continue
        w = r.get("netWgt") or 0
        v = r.get("primaryValue") or 0
        if not w and v:
            t["weight_missing"] += 1
        t["tonnes"] += w / 1000
        t["usd"] += v
        t["reporters"].add(rep)
        if exclude_aggregates:
            p = t["by_partner"].setdefault(rep, {"tonnes": 0.0, "usd": 0.0})
            p["tonnes"] += w / 1000
            p["usd"] += v
    top = sorted(t["by_partner"].items(), key=lambda kv: -kv[1]["tonnes"])[:5]
    return {
        "tonnes": round(t["tonnes"], 1),
        "usd": round(t["usd"]),
        "reporters": len(t["reporters"]),
        "weight_missing": t["weight_missing"],
        "top_partners": [{"code": k, "name": PARTNER_NAMES.get(k, f"کد {k}"), "tonnes": round(v["tonnes"], 1),
                          "usd": round(v["usd"])} for k, v in top] if exclude_aggregates else None,
    }


def fetch_year(c: httpx.Client, year: int) -> dict:
    """{view: {flow: {category: totals}}} for one year."""
    out: dict = {"reported": {}, "mirror": {}}
    # Iran's own report: partner = World, one call per flow with every code
    all_codes = ",".join(code for cat in CATEGORIES.values() for code in cat["codes"])
    for flow, fc in (("export", "X"), ("import", "M")):
        rows = _get(c, {"reporterCode": IRAN, "partnerCode": 0, "period": year, "flowCode": fc, "cmdCode": all_codes})
        if rows:
            out["reported"][flow] = {
                cat: _totals([r for r in rows if r.get("cmdCode") in spec["codes"]], False)
                for cat, spec in CATEGORIES.items()
            }
    # mirror: partners' imports from Iran = Iran's exports, and vice versa
    for flow, fc in (("export", "M"), ("import", "X")):
        out["mirror"][flow] = {}
        for cat, spec in CATEGORIES.items():
            rows = _get(c, {"partnerCode": IRAN, "period": year, "flowCode": fc, "cmdCode": ",".join(spec["codes"])})
            out["mirror"][flow][cat] = _totals(rows, True)
    return out


def read_customs_csv(text: str) -> list[dict]:
    """period_jalali,flow,category,tonnes,value_usd,source,note"""
    lines = [ln for ln in text.splitlines() if ln.strip() and not ln.lstrip().startswith("#")]
    out = []
    for n, row in enumerate(csv.DictReader(lines), start=2):
        row = {k.strip(): (v or "").strip() for k, v in row.items() if k}
        if not row.get("tonnes"):
            continue
        flow = FLOW_FA.get(P.fa_norm(row.get("flow")))
        cat = CAT_FA.get(P.fa_norm(row.get("category")))
        if not flow or not cat:
            raise ValueError(f"customs_trade.csv line {n}: flow must be صادرات/واردات and category شمش/ضایعات/محصولات")
        if not row.get("period_jalali") or not row.get("source"):
            raise ValueError(f"customs_trade.csv line {n}: period_jalali and source are required")
        usd = P.fa_norm(row.get("value_usd")).replace(",", "")
        out.append({
            "period": P.fa_norm(row["period_jalali"]), "flow": flow, "category": cat,
            "tonnes": float(P.fa_norm(row["tonnes"]).replace(",", "")),
            "usd": float(usd) if usd else None, "source": row["source"], "note": row.get("note") or None,
        })
    return out


def collect_trade(years_back: int = 5, refresh_recent: int = 2) -> str:
    """Fetch missing years plus the `refresh_recent` latest years (mirror data fills in over time)."""
    old = read_json(OUT, {}) or {}
    years_data: dict[str, dict] = {y["year"]: y for y in old.get("comtrade", [])} if old else {}
    this_year = date.today().year
    years = list(range(this_year - years_back, this_year))
    todo = [y for y in years if str(y) not in years_data or y >= this_year - refresh_recent]
    errors = []
    with client(90) as c:
        for y in todo:
            try:
                d = fetch_year(c, y)
                years_data[str(y)] = {"year": str(y), "fetched_at": iso(now_utc()), **d}
                print(f"  Comtrade {y}: ok")
            except Exception as e:  # noqa: BLE001 — keep the previous numbers for that year
                errors.append(f"{y}: {e}")
                print(f"  Comtrade {y}: {e}")
    customs = read_customs_csv(CUSTOMS_FILE.read_text(encoding="utf-8-sig")) if CUSTOMS_FILE.exists() else []
    out = {
        "generated_at": iso(now_utc()),
        "unit": "تن",
        "categories": {k: v["title"] for k, v in CATEGORIES.items()},
        "source": "UN Comtrade (comtradeapi.un.org، نسخهٔ رایگان preview)",
        "source_url": "https://comtradeplus.un.org/",
        "notes": [
            "«گزارش ایران»: آماری که خود ایران به سازمان ملل داده؛ معمولاً با ۲ تا ۳ سال تأخیر.",
            "«آینه‌ای»: آنچه کشورهای طرف تجاری از تجارت با ایران گزارش کرده‌اند؛ صادرات ایران = واردات آن‌ها از ایران. سال‌های اخیر ناقص است چون همهٔ کشورها گزارش نداده‌اند.",
            "دادهٔ آینه‌ای و گزارش ایران به‌دلیل زمان ثبت، ارزش CIF/FOB و قاچاق/ترانزیت با هم برابر نیستند.",
        ],
        "comtrade": [years_data[k] for k in sorted(years_data)],
        "customs": customs,
        "stale": bool(errors),
    }
    write_json(OUT, out)
    if errors and len(errors) == len(todo):
        raise RuntimeError("; ".join(errors)[:400] + " (previous data kept)")
    return f"{len(todo) - len(errors)}/{len(todo)} years fetched, {len(customs)} customs rows" + (f"; errors: {errors}" if errors else "")
