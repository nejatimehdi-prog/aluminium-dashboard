"""Commit data/ and push, resolving the predictable conflicts automatically.

Both GitHub Actions and the local Windows collector write to data/. The files that
change on every run (status.json, latest.json) and series files touched by both
sides are merged instead of failing:
  - status.json: per collector, the entry with the newer last_attempt wins
  - series/*.json: points are united by date; on the same date the side fetched later wins
  - latest.json: rebuilt from the merged series after the rebase

    python -m collector.gitsync "commit message"

Prints changed=true|false (and writes it to $GITHUB_OUTPUT inside Actions).
"""
from __future__ import annotations

import json
import os
import subprocess
import sys

from .common import ROOT, dumps
from .summary import build_latest

GIT_ENV = {**os.environ, "GIT_EDITOR": "true"}


def git(*args: str, check: bool = True) -> subprocess.CompletedProcess:
    r = subprocess.run(["git", *args], cwd=ROOT, text=True, capture_output=True, env=GIT_ENV, encoding="utf-8")
    if check and r.returncode != 0:
        raise RuntimeError(f"git {' '.join(args)} failed:\n{r.stdout}\n{r.stderr}")
    return r


def _stage(path: str, n: int) -> dict:
    r = git("show", f":{n}:{path}", check=False)
    return json.loads(r.stdout) if r.returncode == 0 and r.stdout.strip() else {}


def merge_status(a: dict, b: dict) -> dict:
    out = {**a, **b}
    cols = dict(a.get("collectors", {}))
    for k, v in b.get("collectors", {}).items():
        if k not in cols or (v.get("last_attempt") or "") >= (cols[k].get("last_attempt") or ""):
            cols[k] = v
    out["collectors"] = cols
    out["updated_at"] = max(a.get("updated_at") or "", b.get("updated_at") or "")
    return out


def merge_series(a: dict, b: dict) -> dict:
    newer, older = (b, a) if (b.get("fetched_at") or "") >= (a.get("fetched_at") or "") else (a, b)
    pts = {p[0]: p for p in older.get("points", [])}
    pts.update({p[0]: p for p in newer.get("points", [])})
    return {**older, **newer, "points": sorted(pts.values(), key=lambda p: p[0])}


def resolve_conflicts() -> None:
    files = [f for f in git("diff", "--name-only", "--diff-filter=U").stdout.split() if f]
    for f in files:
        if f == "data/status.json":
            merged = merge_status(_stage(f, 2), _stage(f, 3))
        elif f.startswith("data/series/") and f.endswith(".json"):
            merged = merge_series(_stage(f, 2), _stage(f, 3))
        elif f == "data/latest.json":
            merged = _stage(f, 2)  # rebuilt after the rebase
        elif f in ("data/forecast.json", "data/production.json", "data/trade.json", "data/alerts.json"):
            # written by one workflow at a time; keep the newer one
            a, b = _stage(f, 2), _stage(f, 3)
            merged = b if (b.get("generated_at") or "") >= (a.get("generated_at") or "") else a
        else:
            raise RuntimeError(f"conflict in {f} cannot be resolved automatically")
        (ROOT / f).write_text(dumps(merged) + "\n", encoding="utf-8", newline="\n")
        git("add", f)


def pull_rebase() -> None:
    r = git("pull", "--rebase", "--autostash", check=False)
    for _ in range(20):
        if r.returncode == 0:
            return
        if not (ROOT / ".git" / "rebase-merge").exists() and not (ROOT / ".git" / "rebase-apply").exists():
            raise RuntimeError(f"git pull failed:\n{r.stderr}")
        try:
            resolve_conflicts()
        except Exception:
            git("rebase", "--abort", check=False)
            raise
        r = git("rebase", "--continue", check=False)
    git("rebase", "--abort", check=False)
    raise RuntimeError("rebase did not finish")


def sync(message: str) -> bool:
    git("add", *[p for p in ("data", "docs/model.md") if (ROOT / p).exists()])
    if git("diff", "--cached", "--quiet", check=False).returncode == 0:
        print("no data changes")
        return False
    git("commit", "-m", message)
    for attempt in range(3):
        pull_rebase()
        build_latest()  # statuses/series may have been merged: refresh the cards
        git("add", "data/latest.json")
        if git("diff", "--cached", "--quiet", check=False).returncode != 0:
            git("commit", "-m", "data: rebuild latest.json")
        if git("push", check=False).returncode == 0:
            print("pushed")
            return True
        print(f"push rejected (attempt {attempt + 1}), retrying")
    raise RuntimeError("git push failed 3 times")


def main() -> None:
    msg = sys.argv[1] if len(sys.argv) > 1 else "data: update"
    changed = sync(msg)
    print(f"changed={'true' if changed else 'false'}")
    out = os.environ.get("GITHUB_OUTPUT")
    if out:
        with open(out, "a", encoding="utf-8") as fh:
            fh.write(f"changed={'true' if changed else 'false'}\n")


if __name__ == "__main__":
    main()
