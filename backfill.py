"""One-off history fill. Safe to re-run: points are merged by date.

    python backfill.py              # 5 years of world prices + 12 months of IME
    python backfill.py --years 2 --ime-months 6
    python backfill.py --skip-ime   # e.g. from GitHub Actions if ime.co.ir is unreachable
"""
import argparse
from datetime import date

from collector.common import run_collector
from collector.manual import collect_manual
from collector.sources import backfill_ime, collect_ime_fx, collect_sina, collect_westmetall, collect_yahoo
from collector.summary import build_latest


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--years", type=int, default=5, help="years of LME/COMEX/SHFE history")
    ap.add_argument("--ime-months", type=int, default=12)
    ap.add_argument("--skip-ime", action="store_true")
    a = ap.parse_args()
    y = date.today().year
    run_collector("westmetall", "LME — Westmetall",
                  lambda: collect_westmetall(years=list(range(y - a.years, y + 1))))
    run_collector("yahoo", "COMEX و یوان — Yahoo", lambda: collect_yahoo(range_=f"{a.years + 1}y"))
    run_collector("sina", "شانگهای — Sina", lambda: collect_sina(days=366 * a.years + 30))
    if not a.skip_ime:
        run_collector("ime", "بورس کالا — معاملات شمش", lambda: backfill_ime(a.ime_months))
        run_collector("ime_fx", "بورس کالا — نرخ دلار", collect_ime_fx)
    run_collector("manual", "فایل‌های ورود دستی", collect_manual)
    run_collector("summary", "ساخت latest.json", build_latest)


if __name__ == "__main__":
    main()
