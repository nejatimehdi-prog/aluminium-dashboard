"""Network fetchers. Each `collect_*` function updates its series files and returns a
short note for data/status.json; any exception is caught by `run_collector`."""
from __future__ import annotations

import time
from datetime import date, timedelta

import jdatetime

from . import parsers as P
from .common import client, fetched_recently, iso, load_series, now_utc, request, save_series, upsert, TEHRAN

WESTMETALL_URL = "https://www.westmetall.com/en/markdaten.php?action=table&field=LME_Al_cash"
YAHOO_URL = "https://{host}.finance.yahoo.com/v8/finance/chart/{sym}"
SINA_URL = ("https://stock2.finance.sina.com.cn/futures/api/jsonp.php/var%20_AL0=/"
            "InnerFuturesNewService.getDailyKLine?symbol=AL0")
IME_ASMX = "https://www.ime.co.ir/subsystems/ime/services/home/imedata.asmx"


# ---------------------------------------------------------------- LME via Westmetall

def collect_westmetall(years: list[int] | None = None, min_hours: float = 3) -> str:
    """Current-year table by default (LME publishes once a day, so at most every few hours)."""
    cash, m3 = load_series("lme_cash"), load_series("lme_3m")
    if years is None and fetched_recently(cash, min_hours):
        return f"skipped (fetched < {min_hours}h ago)"
    rows: list[dict] = []
    with client() as c:
        for y in years or [None]:
            url = WESTMETALL_URL + (f"&year={y}" if y else "")
            rows += P.parse_westmetall(request(c, "GET", url).text)
            if years:
                time.sleep(2)
    t = iso(now_utc())
    n = upsert(cash, [[r["date"], r["cash"]] for r in rows if r["cash"]], t)
    upsert(m3, [[r["date"], r["three_month"]] for r in rows if r["three_month"]], t)
    save_series(cash)
    save_series(m3)
    return f"{len(rows)} rows, {n} new/changed, last {rows[-1]['date']} = {rows[-1]['cash']}"


# ---------------------------------------------------------------- Yahoo chart API

def _yahoo(c, sym: str, range_: str, lo: float, hi: float) -> dict:
    err = None
    for host in ("query1", "query2"):
        try:
            r = request(c, "GET", YAHOO_URL.format(host=host, sym=sym),
                        params={"range": range_, "interval": "1d", "includePrePost": "false"})
            return P.parse_yahoo_chart(r.text, lo, hi)
        except Exception as e:  # noqa: BLE001
            err = e
    raise err  # type: ignore[misc]


def collect_yahoo(range_: str = "1mo") -> str:
    """COMEX aluminium (USD/t) and USD/CNY. Today's bar is the delayed live price."""
    t = iso(now_utc())
    notes = []
    with client() as c:
        for sid, sym, lo, hi in (("comex", "ALI=F", 1000, 9000), ("usdcny", "CNY=X", 4, 12)):
            res = _yahoo(c, sym, range_, lo, hi)
            if res["currency"] not in ("USD", "CNY"):
                raise P.ParseError(f"Yahoo {sym}: unexpected currency {res['currency']}")
            s = load_series(sid)
            pts = [[d, v] for d, v in res["points"]]
            if res["latest"]:
                pts.append([res["latest"]["date"], res["latest"]["value"]])
                s["latest"] = res["latest"]
            upsert(s, pts, t)
            save_series(s)
            notes.append(f"{sym}={res['latest']['value'] if res['latest'] else pts[-1][1]}")
    return ", ".join(notes)


# ---------------------------------------------------------------- SHFE via Sina

def _rate_on(points: list, d: str) -> float | None:
    """Last known rate on or up to 7 days before date d."""
    best = None
    lo = (date.fromisoformat(d) - timedelta(days=7)).isoformat()
    for p in points:
        if lo <= p[0] <= d:
            best = p[1]
    return best


def collect_sina(days: int | None = 40) -> str:
    """SHFE main contract (CNY/t) converted to USD/t with Yahoo CNY=X."""
    with client() as c:
        rows = P.parse_sina_daily(request(c, "GET", SINA_URL, headers={"Referer": "https://finance.sina.com.cn/"}).text)
    if days:
        cutoff = (date.today() - timedelta(days=days)).isoformat()
        rows = [r for r in rows if r[0] >= cutoff]
    fx = load_series("usdcny")["points"]
    if not fx:
        raise RuntimeError("usdcny series empty — run the Yahoo collector first")
    pts = []
    for d, cny in rows:
        rate = _rate_on(fx, d)
        if rate:
            pts.append([d, round(cny / rate, 1), cny])
    if not pts:
        raise RuntimeError("no SHFE day had a matching USD/CNY rate")
    s = load_series("shfe")
    n = upsert(s, pts)
    save_series(s)
    return f"{len(pts)} days, {n} new/changed, last {pts[-1][0]} = {pts[-1][2]} CNY/t"


# ---------------------------------------------------------------- Iran Mercantile Exchange

def _asmx(c, method: str, **body) -> list[dict]:
    r = request(c, "POST", f"{IME_ASMX}/{method}", json={"Language": 8, **body},
                headers={"Referer": "https://www.ime.co.ir/"}, timeout=120)
    return P.parse_ime_d(r.content.decode("utf-8"))


def _jshift(j: str, days: int) -> str:
    y, m, d = (int(x) for x in j.split("/"))
    return (jdatetime.date(y, m, d) + timedelta(days=days)).strftime("%Y/%m/%d")


def ime_trades(c, j_from: str, j_to: str) -> list[dict]:
    """Main physical-market aluminium trades between two Jalali dates.

    The IME service caches the first answer per date range and may then ignore the
    market flag or return an empty list, so the end of the range is padded with a
    different number of days on each try and rows are cut back to j_from..j_to.
    """
    rows: list[dict] = []
    for i in range(6):
        try:
            rows = _asmx(c, "GetAmareMoamelatList", fari=False, GregorianFromDate=j_from,
                         GregorianToDate=_jshift(j_to, i + 1), MainCat=1, Cat=2, SubCat=0, Producer=0)
        except Exception:  # noqa: BLE001 — the service throws 500s at random; retry with new pad
            rows = []
        main = [r for r in rows if "فرعی" not in P.fa_norm(r.get("Talar"))]
        if main:
            return [r for r in main if j_from <= P.fa_norm(r.get("date")) <= j_to]
        time.sleep(2)
    return []


def ime_due(sid: str) -> bool:
    """Poll every run 08:30–16:00 Tehran (trading + report publication), else every 6 h."""
    t = now_utc().astimezone(TEHRAN)
    return (8, 30) <= (t.hour, t.minute) < (16, 0) or not fetched_recently(load_series(sid), 6)


def collect_ime(days: int = 14, throttle: bool = False) -> str:
    if throttle and not ime_due("ime_ingot"):
        return "skipped (outside Tehran trading hours, fetched < 6h ago)"
    today = jdatetime.date.fromgregorian(date=now_utc().astimezone(TEHRAN).date())
    j_to = today.strftime("%Y/%m/%d")
    j_from = (today - timedelta(days=days)).strftime("%Y/%m/%d")
    with client() as c:
        rows = ime_trades(c, j_from, j_to)
    agg = P.aggregate_ime_ingot(rows)
    s = load_series("ime_ingot")
    if not agg:
        if not rows:
            raise RuntimeError(f"IME returned no trades for {j_from}..{j_to} after 6 tries")
        s["fetched_at"] = iso(now_utc())
        save_series(s)
        return f"{len(rows)} aluminium rows, no pure-ingot trades in {j_from}..{j_to}"
    n = upsert(s, [[d, v["value"], v["tonnes"]] for d, v in agg.items()])
    last = list(agg)[-1]
    s["detail"] = {"date": last, "trades": agg[last]["trades"]}
    save_series(s)
    return f"{len(agg)} trading days, {n} new/changed, last {last} = {agg[last]['value']} toman/kg"


def collect_ime_fx(throttle: bool = False) -> str:
    if throttle and not ime_due("fx_ime"):
        return "skipped (outside Tehran trading hours, fetched < 6h ago)"
    with client() as c:
        r = request(c, "POST", f"{IME_ASMX}/GetHomeExchangeRateData", json={"Language": 8},
                    headers={"Referer": "https://www.ime.co.ir/"})
    pts = P.parse_ime_fx(r.content.decode("utf-8"))
    s = load_series("fx_ime")
    upsert(s, [list(p) for p in pts])
    save_series(s)
    return f"last {pts[-1][0]} = {pts[-1][1]} toman/USD"


def backfill_ime(months: int = 12) -> str:
    """One-off: last `months` of IME trades, fetched in ~2-month chunks."""
    today = jdatetime.date.fromgregorian(date=now_utc().astimezone(TEHRAN).date())
    start = today - timedelta(days=int(months * 30.5))
    s = load_series("ime_ingot")
    total = 0
    with client() as c:
        cur = start
        while cur <= today:
            end = min(cur + timedelta(days=60), today)
            rows = ime_trades(c, cur.strftime("%Y/%m/%d"), end.strftime("%Y/%m/%d"))
            agg = P.aggregate_ime_ingot(rows)
            total += upsert(s, [[d, v["value"], v["tonnes"]] for d, v in agg.items()])
            if agg:
                last = list(agg)[-1]
                if not s.get("detail") or last >= s["detail"]["date"]:
                    s["detail"] = {"date": last, "trades": agg[last]["trades"]}
            print(f"  IME {cur.strftime('%Y/%m/%d')} .. {end.strftime('%Y/%m/%d')}: {len(rows)} rows, {len(agg)} days")
            cur = end + timedelta(days=1)
            time.sleep(3)
    save_series(s)
    return f"{len(s['points'])} trading days stored ({total} new/changed)"
