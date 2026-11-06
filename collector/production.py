"""Monthly aluminium-ingot production.

Automatic: Iralco (symbol فایرا), the only listed smelter with monthly reports on Codal.
Manual: data/manual/production_national.csv for the national total and other producers.
Output: data/production.json
"""
from __future__ import annotations

import csv
import json
import re
import time

from . import parsers as P
from .common import DATA, MANUAL_DIR, client, iso, now_utc, read_json, request, write_json

CODAL_SEARCH = "https://search.codal.ir/api/search/v2/q"
CODAL_BASE = "https://www.codal.ir"
CODAL_COMPANIES = {"فایرا": "ایرالکو"}
OUT = DATA / "production.json"
MANUAL_FILE = MANUAL_DIR / "production_national.csv"
NATIONAL = "کل کشور"


# ---------------------------------------------------------------- Codal parsing

def codal_datasource(html: str) -> dict:
    m = re.search(r"var datasource = (\{.*?\});\s*\n", html, re.S)
    if not m:
        i = html.find("var datasource = ")
        if i < 0:
            raise P.ParseError("Codal: no datasource in report page (old template?)")
        j = html.find("};", i)
        raw = html[i + 17 : j + 1]
    else:
        raw = m.group(1)
    try:
        return json.loads(raw)
    except json.JSONDecodeError as e:
        raise P.ParseError(f"Codal: datasource is not JSON ({e})") from e


def parse_codal_production(html: str) -> dict:
    """Monthly-activity report → {period_end, month, products: {name: tonnes}, ingot_total, ingot_pure}.

    Uses the column group whose header starts «دوره یک ماهه» and, inside it, the
    «تعداد تولید» column, so the parse does not depend on column positions.
    Products are split by sales destination (e.g. «شمش خالص» and «شمش خالص صادراتی»);
    both count as production.
    """
    ds = codal_datasource(html)
    period_end = P.fa_norm(ds.get("periodEndToDate"))
    if ds.get("period") not in (1, None):
        raise P.ParseError(f"Codal: not a 1-month report (period={ds.get('period')})")
    table = None
    for s in ds.get("sheets", []):
        for tb in s.get("tables", []):
            if tb.get("aliasName") == "ProductionAndSales":
                table = tb
    if table is None:
        raise P.ParseError("Codal: ProductionAndSales table not found")
    rows: dict[int, dict[int, dict]] = {}
    for c in table["cells"]:
        rows.setdefault(c["rowSequence"], {})[c["columnSequence"]] = c
    seqs = sorted(rows)
    head1, head2 = rows[seqs[0]], rows[seqs[1]]
    month_col = None
    for col, c in head1.items():
        if P.fa_norm(c.get("value")).startswith("دوره یک ماهه"):
            span = c.get("colSpan") or 1
            for k in range(col, col + span):
                if P.fa_norm(head2.get(k, {}).get("value")) == "تعداد تولید":
                    month_col = k
                    break
    if month_col is None:
        raise P.ParseError("Codal: one-month production column not found")
    products: dict[str, float] = {}
    for seq in seqs[2:]:
        r = rows[seq]
        name = P.fa_norm(r.get(1, {}).get("value"))
        unit = P.fa_norm(r.get(2, {}).get("value"))
        if not name.startswith("شمش"):
            continue
        if unit not in ("تن", ""):
            raise P.ParseError(f"Codal: unexpected unit {unit!r} for {name}")
        v = P._num(r.get(month_col, {}).get("value"))
        if v is not None:
            products[name] = products.get(name, 0) + v
    if not products:
        raise P.ParseError("Codal: no ingot rows in production table")
    pure = sum(v for k, v in products.items() if "خالص" in k)
    y, m, _ = period_end.split("/")
    return {
        "period_end": period_end,
        "month": f"{y}/{m}",
        "products": products,
        "ingot_total": sum(products.values()),
        "ingot_pure": pure,
    }


def _title_period(title: str) -> str | None:
    t = P.fa_norm(title)
    if "گزارش فعالیت ماهانه" not in t or "1 ماهه" not in t:
        return None
    m = re.search(r"منتهی به\s*(\d{4}/\d{2}/\d{2})", t)
    return m.group(1) if m else None


def fetch_codal(symbol: str, months: int = 15) -> list[dict]:
    """Latest one-month reports for `symbol`; for each period the newest letter wins (اصلاحیه)."""
    seen: dict[str, dict] = {}
    with client(60) as c:
        for page in range(1, 5):
            r = request(c, "GET", CODAL_SEARCH,
                        params={"Symbol": symbol, "LetterCode": "ن-۳۰", "PageNumber": page})
            letters = r.json().get("Letters") or []
            for L in letters:
                per = _title_period(L.get("Title", ""))
                if not per or per in seen:
                    continue  # results are newest first, so the first letter per period is the latest
                seen[per] = L
            if len(seen) >= months or not letters:
                break
            time.sleep(2)
        out = []
        for per, L in sorted(seen.items(), reverse=True)[:months]:
            url = CODAL_BASE + L["Url"]
            html = request(c, "GET", url).text
            try:
                rep = parse_codal_production(html)
            except P.ParseError as e:
                print(f"  Codal {symbol} {per}: skipped ({e})")
                continue
            rep.update(source=f"کدال — گزارش فعالیت ماهانه {symbol}", source_url=url,
                       published_at=P.fa_norm(L.get("PublishDateTime")), tracing_no=L.get("TracingNo"),
                       corrected="اصلاحیه" in L.get("Title", ""))
            out.append(rep)
            time.sleep(2)
    return out


# ---------------------------------------------------------------- manual CSV

def read_production_csv(text: str) -> list[dict]:
    """month_jalali,producer,tonnes,source,note"""
    lines = [ln for ln in text.splitlines() if ln.strip() and not ln.lstrip().startswith("#")]
    out = []
    for n, row in enumerate(csv.DictReader(lines), start=2):
        row = {k.strip(): (v or "").strip() for k, v in row.items() if k}
        if not row.get("tonnes"):
            continue
        month = P.fa_norm(row.get("month_jalali"))
        if not re.fullmatch(r"\d{4}/\d{2}", month):
            raise ValueError(f"production_national.csv line {n}: month_jalali must look like 1405/07")
        if not row.get("producer") or not row.get("source"):
            raise ValueError(f"production_national.csv line {n}: producer and source are required")
        t = float(P.fa_norm(row["tonnes"]).replace(",", ""))
        if not 0 <= t <= 2_000_000:
            raise ValueError(f"production_national.csv line {n}: {t} tonnes is not plausible for one month")
        out.append({"month": month, "producer": P.fa_norm(row["producer"]), "tonnes": t,
                    "source": row["source"], "note": row.get("note") or None})
    return out


# ---------------------------------------------------------------- build

def _prev_month(m: str, k: int) -> str:
    y, mm = (int(x) for x in m.split("/"))
    idx = y * 12 + (mm - 1) - k
    return f"{idx // 12}/{idx % 12 + 1:02d}"


def build(codal: dict[str, list[dict]], manual: list[dict]) -> dict:
    months: dict[str, dict] = {}
    for sym, reps in codal.items():
        name = CODAL_COMPANIES.get(sym, sym)
        for r in reps:
            months.setdefault(r["month"], {})[name] = {
                "tonnes": r["ingot_total"], "pure": r["ingot_pure"], "products": r["products"],
                "source": r["source"], "source_url": r["source_url"], "published_at": r["published_at"],
                "corrected": r["corrected"], "auto": True,
            }
    for r in manual:
        months.setdefault(r["month"], {})[r["producer"]] = {
            "tonnes": r["tonnes"], "source": r["source"], "note": r["note"], "auto": False,
        }
    ordered = sorted(months)
    summary = None
    if ordered:
        last = ordered[-1]
        last3 = [_prev_month(last, k) for k in (2, 1, 0)]
        producers = sorted({p for m in last3 for p in months.get(m, {})})
        per = {}
        for p in producers:
            vals = [months.get(m, {}).get(p, {}).get("tonnes") for m in last3]
            per[p] = {
                "last_month": months[last].get(p, {}).get("tonnes"),
                "sum_3m": sum(v for v in vals if v is not None),
                "months_with_data": sum(v is not None for v in vals),
            }
        summary = {"last_month": last, "months_3": last3, "producers": per,
                   "national": per.get(NATIONAL)}
    return {
        "generated_at": iso(now_utc()),
        "unit": "تن",
        "note": ("تولید ماهانهٔ شمش (خالص، آلیاژی، بیلت و اسلب). ایرالکو خودکار از کدال؛ "
                 "کل کشور و سایر تولیدکنندگان از ورود دستی (production_national.csv)."),
        "months": [{"month": m, "producers": months[m]} for m in ordered],
        "summary": summary,
    }


def collect_production() -> str:
    old = read_json(OUT, {}) or {}
    codal: dict[str, list[dict]] = {}
    errors = []
    for sym in CODAL_COMPANIES:
        try:
            codal[sym] = fetch_codal(sym)
        except Exception as e:  # noqa: BLE001 — keep the last good data for this company
            errors.append(f"{sym}: {e}")
            name = CODAL_COMPANIES[sym]
            codal[sym] = [
                {"month": m["month"], "ingot_total": m["producers"][name]["tonnes"],
                 "ingot_pure": m["producers"][name].get("pure"), "products": m["producers"][name].get("products"),
                 "source": m["producers"][name]["source"], "source_url": m["producers"][name].get("source_url"),
                 "published_at": m["producers"][name].get("published_at"),
                 "corrected": m["producers"][name].get("corrected")}
                for m in old.get("months", []) if name in m.get("producers", {})
            ]
    manual = read_production_csv(MANUAL_FILE.read_text(encoding="utf-8-sig")) if MANUAL_FILE.exists() else []
    out = build(codal, manual)
    out["stale"] = bool(errors)
    write_json(OUT, out)
    if errors:
        raise RuntimeError("; ".join(errors) + " (previous data kept)")
    n = sum(len(v) for v in codal.values())
    return f"{n} Codal reports, {len(manual)} manual rows, last month {out['summary']['last_month'] if out['summary'] else '-'}"
