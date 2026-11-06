"""Evaluates data/manual/alerts.json against data/latest.json and sends ntfy notifications.

    NTFY_TOPIC=<your secret topic> python check_alerts.py
    python check_alerts.py --test     # send one test notification

Without NTFY_TOPIC the rules are evaluated and data/alerts.json is written, but nothing is sent.
"""
import os
import sys

from collector.alerts import send
from collector.alerts import check_alerts
from collector.common import run_collector

if __name__ == "__main__":
    if "--test" in sys.argv:
        topic = os.environ.get("NTFY_TOPIC", "").strip()
        if not topic:
            sys.exit("set NTFY_TOPIC first")
        send(topic, "هشدار شمش آلومینیوم", "پیام آزمایشی: اتصال ntfy برقرار است.", ["white_check_mark"])
        print("test notification sent")
    else:
        run_collector("alerts", "هشدار قیمت — ntfy", check_alerts)
