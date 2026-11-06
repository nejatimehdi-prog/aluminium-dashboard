"""Pure parsing functions: raw text in, plain Python data out.

Every parser is tested against a saved sample in tests/fixtures/, so a change in a
site's layout shows up as a failing test (and a clear error in data/status.json)
instead of wrong numbers. Parsers also check value ranges, which catches unit
mix-ups (e.g. a price per pound or per ounce instead of per tonne).
"""
from __future__ import annotations

import json
import re
from datetime import date, datetime, timezone

import jdatetime
from bs4 import BeautifulSoup


class ParseError(ValueError):
    """The response did not look like what the parser expects."""


# ---------------------------------------------------------------- helpers

_MONTHS = {
    m: i
    for i, m in enumerate(
        ["January", "February", "March", "April", "May", "June", "July",
         "August", "September", "October", "November", "December"],
        1,
    )
}

_FA_FIX = str.maketrans({"ي": "ی", "ك": "ک", "‌": " ", "ۀ": "ه"})
_FA_DIGITS = str.maketrans("۰۱۲۳۴۵۶۷۸۹٠١٢٣٤٥٦٧٨٩", "01234567890123456789")


def fa_norm(s: str | None) -> str:
    """Normalise Arabic yeh/kaf, ZWNJ, Persian digits and whitespace."""
    return " ".join((s or "").translate(_FA_FIX).translate(_FA_DIGITS).split())


def _num(s: str | None) -> float | None:
    s = (s or "").strip().replace(",", "")
    if not s or s in {"-", "—", "–"}:
        return None
    try:
        return float(s)
    except ValueError:
        return None


def check_range(values, lo: float, hi: float, what: str) -> None:
    """Raise if any value is outside [lo, hi] — almost always a unit or layout change."""
    bad = [v for v in values if v is not None and not (lo <= v <= hi)]
    if bad:
        raise ParseError(f"{what}: value {bad[0]} outside plausible range {lo}..{hi} (unit changed?)")


def jalali_to_iso(s: str) -> str:
    y, m, d = (int(x) for x in fa_norm(s).split("/"))
    return jdatetime.date(y, m, d).togregorian().isoformat()


def iso_to_jalali(s: str) -> str:
    g = date.fromisoformat(s)
    return jdatetime.date.fromgregorian(date=g).strftime("%Y/%m/%d")


# ---------------------------------------------------------------- Westmetall (LME)

def parse_westmetall(html: str) -> list[dict]:
    """LME aluminium table → [{date, cash, three_month, stock}] (USD/t, tonnes), oldest first."""
    soup = BeautifulSoup(html, "html.parser")
    header = " ".join(th.get_text(" ", strip=True) for th in soup.select("table th"))
    if "Aluminium" not in header or "Cash" not in header:
        raise ParseError("Westmetall: aluminium cash-settlement table not found (layout changed?)")
    rows: dict[str, dict] = {}
    for tr in soup.select("table tr"):
        tds = tr.find_all("td")
        if len(tds) < 3:
            continue
        m = re.match(r"(\d{1,2})\.\s*([A-Za-z]+)\s+(\d{4})", tds[0].get_text(strip=True))
        if not m or m.group(2) not in _MONTHS:
            continue
        d = date(int(m.group(3)), _MONTHS[m.group(2)], int(m.group(1))).isoformat()
        cash, m3 = _num(tds[1].get_text()), _num(tds[2].get_text())
        stock = _num(tds[3].get_text()) if len(tds) > 3 else None
        if cash is None and m3 is None:
            continue
        rows[d] = {"date": d, "cash": cash, "three_month": m3, "stock": stock}
    if not rows:
        raise ParseError("Westmetall: no data rows found (layout changed?)")
    out = sorted(rows.values(), key=lambda r: r["date"])
    check_range([r["cash"] for r in out] + [r["three_month"] for r in out], 500, 15000, "Westmetall USD/t")
    return out


# ---------------------------------------------------------------- Yahoo chart API

def parse_yahoo_chart(text: str, lo: float, hi: float) -> dict:
    """Yahoo v8 chart JSON → {symbol, currency, points[(date, close)], latest{value,time,date}}.

    Daily bars are dated in the exchange's local time (gmtoffset), so a bar never
    slips to the previous/next calendar day.
    """
    try:
        j = json.loads(text)
    except json.JSONDecodeError as e:
        raise ParseError(f"Yahoo: not JSON ({e})") from e
    chart = j.get("chart") or {}
    if chart.get("error"):
        raise ParseError(f"Yahoo: {chart['error']}")
    res = (chart.get("result") or [None])[0]
    if not res or "meta" not in res:
        raise ParseError("Yahoo: empty result")
    meta = res["meta"]
    off = int(meta.get("gmtoffset") or 0)

    def local_date(ts: int) -> str:
        return datetime.fromtimestamp(ts + off, tz=timezone.utc).date().isoformat()

    closes = (((res.get("indicators") or {}).get("quote") or [{}])[0]).get("close") or []
    pts: dict[str, float] = {}
    for ts, c in zip(res.get("timestamp") or [], closes):
        if c is not None:
            # daily bars are stamped at local midnight, but gmtoffset is the *current*
            # offset (EST in winter) — a +3h margin keeps DST-period bars on their day
            pts[local_date(ts + 3 * 3600)] = round(float(c), 4)

    latest = None
    if meta.get("regularMarketPrice") is not None and meta.get("regularMarketTime"):
        t = int(meta["regularMarketTime"])
        latest = {
            "value": round(float(meta["regularMarketPrice"]), 4),
            "time": datetime.fromtimestamp(t, tz=timezone.utc).isoformat().replace("+00:00", "Z"),
            "date": local_date(t),
        }
    vals = list(pts.values()) + ([latest["value"]] if latest else [])
    if not vals:
        raise ParseError("Yahoo: no prices in response")
    check_range(vals, lo, hi, f"Yahoo {meta.get('symbol')}")
    return {
        "symbol": meta.get("symbol"),
        "currency": meta.get("currency"),
        "points": sorted(pts.items()),
        "latest": latest,
    }


# ---------------------------------------------------------------- Sina (SHFE)

def parse_sina_daily(text: str) -> list[tuple[str, float]]:
    """Sina JSONP daily K-line for SHFE aluminium (CNY/t) → [(date, close)]."""
    a, b = text.find("("), text.rfind(")")
    if a < 0 or b <= a:
        raise ParseError("Sina: not a JSONP response")
    try:
        arr = json.loads(text[a + 1 : b])
    except json.JSONDecodeError as e:
        raise ParseError(f"Sina: bad JSON ({e})") from e
    if not isinstance(arr, list) or not arr:
        raise ParseError("Sina: empty series")
    out: dict[str, float] = {}
    for r in arr:
        c = _num(str(r.get("c", "")))
        d = str(r.get("d", ""))[:10]
        if c and re.fullmatch(r"\d{4}-\d{2}-\d{2}", d):
            out[d] = c
    if not out:
        raise ParseError("Sina: no close prices")
    check_range(out.values(), 5000, 80000, "Sina SHFE CNY/t")
    return sorted(out.items())


# ---------------------------------------------------------------- Iran Mercantile Exchange

def parse_ime_d(text: str) -> list[dict]:
    """IME ASMX answers look like {"d": "<json string>"}."""
    try:
        j = json.loads(text)
        d = j["d"]
        return json.loads(d) if isinstance(d, str) else d
    except (json.JSONDecodeError, KeyError, TypeError) as e:
        raise ParseError(f"IME: unexpected answer ({e})") from e


def is_pure_ingot(row: dict) -> bool:
    """Pure (unalloyed) aluminium ingot in a main physical-market hall, priced in rial."""
    name = fa_norm(row.get("GoodsName"))
    if not name.startswith("شمش") or "آلیاژ" in name:
        return False
    if not re.search(r"1000\s*p|99\.\d", name, re.I):
        return False
    if "فرعی" in fa_norm(row.get("Talar")):
        return False
    # spot contracts settled in cash only: credit settlement («نقدی / اعتباری») trades
    # ~9% higher and forward (سلف) contracts price a later delivery
    if not fa_norm(row.get("ContractType")).startswith("نقدی"):
        return False
    if fa_norm(row.get("Tasvieh")) not in ("نقدی", ""):
        return False
    return fa_norm(row.get("Currency")) in ("ریال", "")


def aggregate_ime_ingot(rows: list[dict]) -> dict[str, dict]:
    """Trades → {gregorian date: {value (toman/kg, volume-weighted), tonnes, trades[]}}.

    IME prices (`Price` = weighted average, `MinPrice`, `MaxPrice`) are in rial per kg;
    `Quantity` is in tonnes. Rows with no traded volume are offers that did not trade
    and are skipped.
    """
    by_day: dict[str, list[dict]] = {}
    for r in rows:
        if not is_pure_ingot(r):
            continue
        price, qty = r.get("Price") or 0, r.get("Quantity") or 0
        if price <= 0 or qty <= 0:
            continue
        check_range([price], 100_000, 2_000_000_000, "IME rial/kg")
        d = jalali_to_iso(r["date"])
        by_day.setdefault(d, []).append({
            "producer": fa_norm(r.get("ProducerName")),
            "symbol": r.get("Symbol"),
            "grade": fa_norm(r.get("GoodsName")).replace("شمش", "").strip(),
            "price": round(price / 10),            # toman/kg
            "min": round((r.get("MinPrice") or 0) / 10),
            "max": round((r.get("MaxPrice") or 0) / 10),
            "tonnes": qty,
        })
    out = {}
    for d, trades in by_day.items():
        tonnes = sum(t["tonnes"] for t in trades)
        wavg = sum(t["price"] * t["tonnes"] for t in trades) / tonnes
        out[d] = {"value": round(wavg), "tonnes": tonnes, "trades": trades}
    return dict(sorted(out.items()))


def parse_ime_fx(text: str) -> list[tuple[str, float]]:
    """IME home exchange-rate block → [(date, toman per USD)]."""
    out = []
    for r in parse_ime_d(text):
        if fa_norm(r.get("Sharh")) == "دلار" and r.get("Nerkh"):
            out.append((jalali_to_iso(r["Tarikh"]), round(float(r["Nerkh"]) / 10)))
    if not out:
        raise ParseError("IME FX: no USD row")
    check_range([v for _, v in out], 5_000, 5_000_000, "IME FX toman/USD")
    return sorted(out)
