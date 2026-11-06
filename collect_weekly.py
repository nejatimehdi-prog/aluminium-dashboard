"""Weekly data: monthly production (Codal + manual CSV) and foreign trade (UN Comtrade + customs CSV).

    python collect_weekly.py
"""
from collector.common import run_collector
from collector.production import collect_production
from collector.trade import collect_trade


def main() -> None:
    run_collector("production", "تولید — کدال و ورود دستی", collect_production)
    run_collector("trade", "تجارت خارجی — Comtrade و گمرک", collect_trade)


if __name__ == "__main__":
    main()
