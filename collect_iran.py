"""Iranian sources: IME aluminium-ingot trades and the IME dollar rate.

    python collect_iran.py            # collect, then git pull/commit/push (local Windows run)
    python collect_iran.py --no-push  # collect only (used inside GitHub Actions)

Inside GitHub Actions pushing is always skipped; the workflow commits itself.
"""
import argparse
import shutil
import subprocess
import sys

from collector.common import ROOT, in_actions, run_collector
from collector.gitsync import pull_rebase, sync
from collector.manual import collect_manual
from collector.sources import collect_ime, collect_ime_fx
from collector.summary import build_latest


def git(*args: str, check: bool = True) -> subprocess.CompletedProcess:
    return subprocess.run(["git", *args], cwd=ROOT, check=check, text=True, capture_output=True)


def push() -> None:
    if not shutil.which("git"):
        print("git not found — install Git for Windows (see README). Data was saved but not pushed.")
        return
    try:
        sync("data: Iran prices (local collector)")
    except Exception as e:  # noqa: BLE001
        print(f"push failed; data is saved locally and will go out with the next run:\n{e}")


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--no-push", action="store_true", help="collect only, do not git push")
    args = ap.parse_args()
    local_push = not args.no_push and not in_actions()
    if local_push and shutil.which("git"):
        try:
            pull_rebase()  # start from the latest data
        except Exception as e:  # noqa: BLE001
            print(f"warning: git pull failed (offline?):\n{e}")

    # in Actions (every 30 min) IME is only polled often around Tehran trading hours
    run_collector("ime", "بورس کالا — معاملات شمش", lambda: collect_ime(throttle=in_actions()))
    run_collector("ime_fx", "بورس کالا — نرخ دلار", lambda: collect_ime_fx(throttle=in_actions()))
    run_collector("manual", "فایل‌های ورود دستی", collect_manual)
    run_collector("summary", "ساخت latest.json", build_latest)

    if local_push:
        push()


if __name__ == "__main__":
    sys.exit(main())
