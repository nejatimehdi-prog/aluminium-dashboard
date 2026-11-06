"""Hand-entered CSVs in data/manual/ → series files.

Columns: date_jalali, date, value, unit, source, note
- Either date_jalali (1405/08/14) or date (2026-11-05) is enough; the other is derived.
- Lines starting with # are comments.
"""
from __future__ import annotations

import csv
import re

from . import parsers as P
from .common import MANUAL_DIR, iso, load_series, now_utc, save_series

# unit as written in the CSV → factor to the normalised unit
UNITS = {
    "iran_free_market": {"تومان/کیلوگرم": 1, "toman/kg": 1, "ریال/کیلوگرم": 0.1, "rial/kg": 0.1},
    "fx_free": {"تومان/دلار": 1, "toman/usd": 1, "ریال/دلار": 0.1, "rial/usd": 0.1},
}
FILES = {"iran_free_market": "iran_free_market.csv", "fx_free": "fx_free_market.csv"}
RANGES = {"iran_free_market": (10_000, 100_000_000), "fx_free": (5_000, 5_000_000)}


def read_manual(sid: str, text: str) -> list[list]:
    """Parse one manual CSV; raises ValueError naming the bad line."""
    lines = [ln for ln in text.splitlines() if ln.strip() and not ln.lstrip().startswith("#")]
    out = []
    for n, row in enumerate(csv.DictReader(lines), start=2):
        row = {k.strip(): (v or "").strip() for k, v in row.items() if k}
        if not row.get("value"):
            continue
        try:
            if row.get("date"):
                d = row["date"]
                if not re.fullmatch(r"\d{4}-\d{2}-\d{2}", d):
                    raise ValueError(f"bad date {d!r}")
            elif row.get("date_jalali"):
                d = P.jalali_to_iso(row["date_jalali"])
            else:
                raise ValueError("date or date_jalali is required")
            unit = P.fa_norm(row.get("unit")).replace(" ", "").lower()
            factors = {k.replace(" ", "").lower(): f for k, f in UNITS[sid].items()}
            if unit not in factors:
                raise ValueError(f"unknown unit {row.get('unit')!r}; use one of {list(UNITS[sid])}")
            v = float(P.fa_norm(row["value"]).replace(",", "").replace("٬", "")) * factors[unit]
            lo, hi = RANGES[sid]
            if not lo <= v <= hi:
                raise ValueError(f"value {v} outside {lo}..{hi} — check the unit")
            if not row.get("source"):
                raise ValueError("source is required")
            out.append([d, round(v), row["source"]])
        except ValueError as e:
            raise ValueError(f"{FILES[sid]} line {n}: {e}") from e
    return out


def collect_manual() -> str:
    notes = []
    for sid, fname in FILES.items():
        path = MANUAL_DIR / fname
        pts = read_manual(sid, path.read_text(encoding="utf-8-sig")) if path.exists() else []
        s = load_series(sid)
        # the CSV is the single source of truth for manual series; a later line wins per date
        s["points"] = list({p[0]: p for p in pts}.values())
        s["fetched_at"] = iso(now_utc())
        save_series(s)
        notes.append(f"{fname}: {len(pts)} rows")
    return ", ".join(notes)
