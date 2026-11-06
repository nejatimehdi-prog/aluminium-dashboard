"""Global prices: LME (Westmetall), COMEX + USD/CNY (Yahoo), SHFE (Sina).

    python collect_global.py

Never exits with an error because a source failed; failures go to data/status.json.
"""
from collector.common import run_collector
from collector.manual import collect_manual
from collector.sources import collect_sina, collect_westmetall, collect_yahoo
from collector.summary import build_latest


def main() -> None:
    run_collector("westmetall", "LME — Westmetall", collect_westmetall)
    run_collector("yahoo", "COMEX و یوان — Yahoo", collect_yahoo)
    run_collector("sina", "شانگهای — Sina", collect_sina)
    run_collector("manual", "فایل‌های ورود دستی", collect_manual)
    run_collector("summary", "ساخت latest.json", build_latest)


if __name__ == "__main__":
    main()
