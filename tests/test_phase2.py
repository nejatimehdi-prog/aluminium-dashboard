from pathlib import Path

import pytest

from collector.production import build, parse_codal_production, read_production_csv, _title_period
from collector.trade import _totals, read_customs_csv

FX = Path(__file__).parent / "fixtures"


def test_codal_production_month_column():
    r = parse_codal_production((FX / "codal_faira_1405_07.html").read_text(encoding="utf-8-sig"))
    assert r["period_end"] == "1405/07/30" and r["month"] == "1405/07"
    # one-month column («دوره یک ماهه … / تعداد تولید»), not the year-to-date one
    assert r["products"]["شمش خالص صادراتی"] == 5805
    assert r["products"]["شمش بیلت"] == 626
    assert r["ingot_total"] == 6431 and r["ingot_pure"] == 5805


def test_codal_title_filter():
    assert _title_period("گزارش فعالیت ماهانه دوره ۱ ماهه منتهی به  ۱۴۰۵/۰۷/۳۰") == "1405/07/30"
    assert _title_period("گزارش فعالیت ماهانه دوره ۱ ماهه منتهی به  ۱۴۰۵/۰۶/۳۱(اصلاحیه)") == "1405/06/31"
    assert _title_period("گزارش فعالیت ماهانه دوره ۳ ماهه منتهی به ۱۴۰۵/۰۳/۳۱") is None


def test_production_summary_three_months():
    codal = {"فایرا": [
        {"month": m, "ingot_total": t, "ingot_pure": t, "products": {}, "source": "s", "source_url": "u",
         "published_at": "p", "corrected": False}
        for m, t in (("1405/05", 100), ("1405/06", 200), ("1405/07", 300))]}
    manual = read_production_csv("month_jalali,producer,tonnes,source,note\n1405/07,کل کشور,50000,ایمیدرو,\n")
    out = build(codal, manual)
    s = out["summary"]
    assert s["last_month"] == "1405/07" and s["months_3"] == ["1405/05", "1405/06", "1405/07"]
    assert s["producers"]["ایرالکو"] == {"last_month": 300, "sum_3m": 600, "months_with_data": 3}
    assert s["national"]["months_with_data"] == 1  # only one month entered → no fake 3-month total


def test_production_csv_rejects_bad_month():
    with pytest.raises(ValueError, match="month_jalali"):
        read_production_csv("month_jalali,producer,tonnes,source,note\n1405-07,کل کشور,1,x,\n")


def test_comtrade_totals_skip_breakdowns_and_aggregates():
    rows = [
        {"reporterCode": 792, "motCode": 0, "customsCode": "C00", "partner2Code": 0, "netWgt": 1_000_000, "primaryValue": 2_500_000},
        {"reporterCode": 156, "motCode": 0, "customsCode": "C00", "partner2Code": 0, "netWgt": 500_000, "primaryValue": 1_200_000},
        {"reporterCode": 792, "motCode": 2100, "customsCode": "C00", "partner2Code": 0, "netWgt": 999_999, "primaryValue": 1},  # by transport mode
        {"reporterCode": 97, "motCode": 0, "customsCode": "C00", "partner2Code": 0, "netWgt": 999_999, "primaryValue": 1},     # EU aggregate
        {"reporterCode": 12, "motCode": 0, "customsCode": "C00", "partner2Code": 0, "netWgt": None, "primaryValue": 5000},
    ]
    t = _totals(rows, True)
    assert t["tonnes"] == 1500.0 and t["usd"] == 3_705_000
    assert t["reporters"] == 3 and t["weight_missing"] == 1
    assert t["top_partners"][0]["name"] == "ترکیه"


def test_customs_csv():
    rows = read_customs_csv("period_jalali,flow,category,tonnes,value_usd,source,note\n1404,صادرات,شمش,300000,,گمرک,\n")
    assert rows == [{"period": "1404", "flow": "export", "category": "ingot", "tonnes": 300000.0,
                     "usd": None, "source": "گمرک", "note": None}]
