"""Daily forecast: writes data/forecast.json and docs/model.md.

    python run_forecast.py

Needs requirements-model.txt (pandas, numpy, statsmodels).
"""
from collector.common import run_collector
from collector.forecast import run


if __name__ == "__main__":
    run_collector("forecast", "پیش‌بینی و بک‌تست", run)
