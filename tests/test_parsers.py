"""Parser tests against saved real responses (tests/fixtures/).

If a site changes its layout, re-download the page into the fixture and these tests
show exactly which assumption broke.
"""
import json
from pathlib import Path

import pytest

from collector import parsers as P
from collector.manual import read_manual
from collector.common import dumps

FX = Path(__file__).parent / "fixtures"


def fixture(name: str) -> str:
    return (FX / name).read_text(encoding="utf-8-sig")


def test_westmetall():
    rows = P.parse_westmetall(fixture("westmetall_lme_al.html"))
    assert len(rows) > 150
    last = rows[-1]
    assert last == {"date": "2026-11-05", "cash": 3160.0, "three_month": 3097.5, "stock": 228475.0}
    assert rows == sorted(rows, key=lambda r: r["date"])  # oldest first


def test_westmetall_layout_change_is_an_error():
    with pytest.raises(P.ParseError):
        P.parse_westmetall("<html><table><tr><th>date</th></tr></table></html>")


def test_yahoo_comex():
    r = P.parse_yahoo_chart(fixture("yahoo_ali.json"), 1000, 9000)
    assert r["symbol"] == "ALI=F" and r["currency"] == "USD"
    assert len(r["points"]) >= 15
    assert r["latest"]["value"] > 1000
    dates = [d for d, _ in r["points"]]
    assert len(dates) == len(set(dates))
    # weekday bars only: a timezone bug would shift bars onto weekends
    from datetime import date
    assert all(date.fromisoformat(d).weekday() < 5 for d in dates)


def test_yahoo_unit_guard():
    # a quote in USD/lb (~1.4) must not be accepted as USD/t
    with pytest.raises(P.ParseError):
        P.parse_yahoo_chart(fixture("yahoo_ali.json"), 0.5, 5)


def test_yahoo_cny():
    r = P.parse_yahoo_chart(fixture("yahoo_cny.json"), 4, 12)
    assert r["currency"] == "CNY" and 5 < r["latest"]["value"] < 9


def test_sina():
    pts = P.parse_sina_daily(fixture("sina_al0.txt"))
    assert len(pts) == 25
    assert pts[-1][0] == "2026-11-06" and 10000 < pts[-1][1] < 40000


def test_ime_aggregate():
    rows = P.parse_ime_d(fixture("ime_trades_al.json"))
    # a subsidiary-hall row must be ignored even if it is a pure ingot
    rows.append({**rows[0], "GoodsName": "شمش 1000p-99.7", "Talar": "تالار فرعی", "Price": 1.0e7, "Quantity": 999})
    agg = P.aggregate_ime_ingot(rows)
    assert "2026-11-01" in agg  # 1405/08/10
    day = agg["2026-11-01"]
    assert all("آلیاژ" not in t["grade"] for t in day["trades"])
    assert all(t["tonnes"] != 999 for t in day["trades"])
    # credit-settled trades (Tasvieh «نقدی / اعتباری») are excluded
    assert all(t["symbol"] != "IALC-AP10201-00" for t in day["trades"])
    assert len(day["trades"]) == 6 and day["tonnes"] == 4000
    # weighted average lies between the cheapest and dearest trade, in toman/kg
    prices = [t["price"] for t in day["trades"]]
    assert min(prices) <= day["value"] <= max(prices)
    assert 300_000 < day["value"] < 2_000_000
    iralco = [t for t in day["trades"] if t["symbol"] == "IAC-AP15351-00"][0]
    assert iralco["price"] == round(7248479 / 10)


def test_ime_fx():
    assert P.parse_ime_fx(fixture("ime_fx.json")) == [("2026-11-03", 187444), ("2026-11-04", 187819)]


def test_jalali():
    assert P.jalali_to_iso("1405/08/14") == "2026-11-05"
    assert P.jalali_to_iso("۱۴۰۵/۰۸/۱۴") == "2026-11-05"
    assert P.iso_to_jalali("2026-11-05") == "1405/08/14"


def test_manual_csv():
    text = (
        "# comment\n"
        "date_jalali,date,value,unit,source,note\n"
        "1405/08/14,,780000,تومان/کیلوگرم,فروشنده الف,\n"
        ",2026-11-06,7900000,ریال/کیلوگرم,فروشنده ب,\n"
    )
    assert read_manual("iran_free_market", text) == [
        ["2026-11-05", 780000, "فروشنده الف"],
        ["2026-11-06", 790000, "فروشنده ب"],
    ]


@pytest.mark.parametrize("line, msg", [
    ("1405/08/14,,780000,تومان/تن,x,", "unknown unit"),
    ("1405/08/14,,78,تومان/کیلوگرم,x,", "outside"),
    ("1405/08/14,,780000,تومان/کیلوگرم,,", "source"),
])
def test_manual_csv_errors(line, msg):
    with pytest.raises(ValueError, match=msg):
        read_manual("iran_free_market", "date_jalali,date,value,unit,source,note\n" + line + "\n")


def test_dumps_roundtrip():
    obj = {"a": [["2026-01-01", 1.5], ["2026-01-02", 2]], "b": {"c": None}}
    assert json.loads(dumps(obj)) == obj
    assert '["2026-01-01", 1.5]' in dumps(obj)
