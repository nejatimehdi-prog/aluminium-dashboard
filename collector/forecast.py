"""Scenario forecast for the Iran ingot price, built from its components.

    Iran price ≈ a × (LME × FX / 1000) + b          (toman/kg; LME USD/t; FX toman/USD)

1. LME (daily cash, Westmetall) is forecast with a random walk, damped-trend ETS, ARIMA(1,1,1) and
   their average; the model with the lowest rolling-origin MAPE (mean over 5/22/66 business days) wins.
2. FX is carried forward as a random walk with a wider (×fx_vol_multiplier) bootstrap band.
3. a and b come from an OLS fit on IME trading days. Until there are enough days with a known FX
   rate (`min_fx_matches_for_regression`), the model runs in «implied ratio» mode instead:
   R = Iran price × 1000 / LME (toman per USD, effective) is carried forward like FX.
4. Scenarios = percentiles 10/50/90 of a Monte-Carlo simulation that bootstraps historical
   per-business-day log changes of LME and FX (or R), plus regression residuals.
5. Every horizon gets a rolling-origin backtest (MAPE, and how often the 10–90 band held the actual).

Writes data/forecast.json and docs/model.md. No data is invented: missing inputs → no forecast.
"""
from __future__ import annotations

import json
import warnings
from datetime import date

import numpy as np
import pandas as pd
from pandas.tseries.offsets import BDay

from .common import DATA, MANUAL_DIR, ROOT, iso, now_utc, read_json, write_json

HORIZONS = [(5, "۱ هفته"), (22, "۱ ماه"), (66, "۳ ماه")]
HMAX = 66
MODEL_FA = {
    "rw": "گام تصادفی (آخرین قیمت)",
    "ets": "هموارسازی نمایی ETS با روند میرا",
    "arima": "ARIMA(1,1,1)",
    "ensemble": "میانگین سه مدل",
}
OUT = DATA / "forecast.json"
DOC = ROOT / "docs" / "model.md"


# ---------------------------------------------------------------- data

def load_series(sid: str) -> pd.Series:
    s = read_json(DATA / "series" / f"{sid}.json", {}) or {}
    pts = s.get("points") or []
    if not pts:
        return pd.Series(dtype=float)
    ser = pd.Series({pd.Timestamp(p[0]): float(p[1]) for p in pts}).sort_index()
    return ser[ser > 0]


def bdays_between(a: pd.Timestamp, b: pd.Timestamp) -> int:
    return max(int(np.busday_count(a.date(), b.date())), 0)


def increments(s: pd.Series, window: int) -> np.ndarray:
    """Per-business-day log changes, standardised by sqrt(gap) so irregular series fit too; demeaned."""
    s = s.iloc[-(window + 1):]
    if len(s) < 3:
        return np.array([0.0])
    lv = np.log(s.values)
    gaps = np.array([max(bdays_between(s.index[i - 1], s.index[i]), 1) for i in range(1, len(s))])
    z = np.diff(lv) / np.sqrt(gaps)
    return z - z.mean()


def asof(s: pd.Series, d: pd.Timestamp, tol_days: int = 7) -> float | None:
    sub = s.loc[:d]
    if sub.empty or (d - sub.index[-1]).days > tol_days:
        return None
    return float(sub.iloc[-1])


# ---------------------------------------------------------------- LME models (log space)

def _fc_rw(y: np.ndarray, h: int) -> np.ndarray:
    return np.repeat(y[-1], h)


def _fc_ets(y: np.ndarray, h: int) -> np.ndarray:
    from statsmodels.tsa.holtwinters import ExponentialSmoothing

    m = ExponentialSmoothing(y, trend="add", damped_trend=True, initialization_method="estimated").fit()
    return np.asarray(m.forecast(h))


def _fc_arima(y: np.ndarray, h: int) -> np.ndarray:
    from statsmodels.tsa.arima.model import ARIMA

    m = ARIMA(y, order=(1, 1, 1)).fit()
    return np.asarray(m.forecast(h))


FORECASTERS = {"rw": _fc_rw, "ets": _fc_ets, "arima": _fc_arima}


def forecast_all(y: np.ndarray, h: int) -> dict[str, np.ndarray]:
    out = {}
    with warnings.catch_warnings():
        warnings.simplefilter("ignore")
        for k, f in FORECASTERS.items():
            try:
                out[k] = f(y, h)
            except Exception:  # noqa: BLE001 — a failed fit falls back to the random walk
                out[k] = _fc_rw(y, h)
    out["ensemble"] = np.mean([out["rw"], out["ets"], out["arima"]], axis=0)
    return out


def backtest_lme(lme: pd.Series, window: int = 750, step: int = 10, span: int = 520) -> dict:
    """Rolling-origin MAPE (%) per model and horizon over the last `span` business days."""
    y = np.log(lme.values)
    n = len(y)
    origins = list(range(max(window, n - span - HMAX), n - HMAX, step))
    errs = {m: {h: [] for h, _ in HORIZONS} for m in MODEL_FA}
    for o in origins:
        fc = forecast_all(y[o - window + 1 : o + 1], HMAX)
        for m, f in fc.items():
            for h, _ in HORIZONS:
                actual = np.exp(y[o + h])
                errs[m][h].append(abs(np.exp(f[h - 1]) - actual) / actual)
    mape = {m: {h: round(float(np.mean(v)) * 100, 2) for h, v in hs.items()} for m, hs in errs.items()}
    return {"mape": mape, "origins": len(origins),
            "from": str(lme.index[origins[0]].date()) if origins else None,
            "to": str(lme.index[origins[-1]].date()) if origins else None}


# ---------------------------------------------------------------- simulation

def simulate(start_log: np.ndarray, z: np.ndarray, steps: np.ndarray, n: int, rng, mult: float = 1.0) -> np.ndarray:
    """Paths of shape (n, len(steps)): start_log[k] + sum of steps[k] bootstrapped increments."""
    kmax = int(steps.max()) if len(steps) else 0
    if kmax == 0:
        return np.tile(start_log, (n, 1))
    cum = np.cumsum(rng.choice(z, size=(n, kmax)) * mult, axis=1)
    cum = np.concatenate([np.zeros((n, 1)), cum], axis=1)
    return start_log[None, :] + cum[:, steps]


def pct(a: np.ndarray, q: float, axis=0) -> np.ndarray:
    return np.percentile(a, q, axis=axis)


# ---------------------------------------------------------------- main

def run() -> str:
    A = read_json(MANUAL_DIR / "scenario_assumptions.json", {})
    P = [A["scenarios"][k]["percentile"] for k in ("pessimistic", "base", "optimistic")]
    rng = np.random.default_rng(A.get("seed", 7))
    n_paths = int(A.get("n_paths", 10000))
    win = int(A.get("bootstrap_window_days", 500))
    fx_mult = float(A.get("fx_vol_multiplier", 1.25))

    lme = load_series("lme_cash")
    ime = load_series("ime_ingot")
    if len(lme) < 800 or len(ime) < 20:
        raise RuntimeError(f"not enough history (LME {len(lme)} days, IME {len(ime)} trades)")

    # FX: free-market CSV if it has history, else the IME settlement rate
    fx_free, fx_ime = load_series("fx_free"), load_series("fx_ime")
    fx, fx_id = (fx_free, "fx_free") if len(fx_free) >= len(fx_ime) and len(fx_free) > 0 else (fx_ime, "fx_ime")

    as_of = lme.index[-1]
    targets = [as_of + BDay(h) for h, _ in HORIZONS]
    fan_dates = pd.bdate_range(as_of + BDay(1), periods=HMAX)

    # ---- LME: backtest, choose, forecast
    bt = backtest_lme(lme)
    mean_mape = {m: float(np.mean(list(v.values()))) for m, v in bt["mape"].items()}
    best = min(mean_mape, key=mean_mape.get)
    y = np.log(lme.values[-750:])
    lme_point = forecast_all(y, HMAX)[best]  # log, steps 1..66
    z_lme = increments(lme, win)
    steps_fan = np.arange(1, HMAX + 1)
    lme_paths = simulate(lme_point, z_lme, steps_fan, n_paths, rng)  # (n, 66) log

    # ---- Iran side: regression (needs FX history) or implied ratio
    pairs = []
    for d, p in ime.items():
        l, f = asof(lme, d), asof(fx, d, 5) if len(fx) else None
        if l and f:
            pairs.append((d, p, l * f / 1000))
    min_pairs = int(A.get("min_fx_matches_for_regression", 30))
    mode = "regression" if len(pairs) >= min_pairs else "implied_ratio"

    ime_last_d, ime_last = ime.index[-1], float(ime.iloc[-1])
    lag = bdays_between(ime_last_d, as_of)  # the Iran side's last observation is older than LME's
    steps_iran = steps_fan + lag
    regression = None
    if mode == "regression":
        X = np.array([q[2] for q in pairs])
        Y = np.array([q[1] for q in pairs])
        a, b = np.linalg.lstsq(np.c_[X, np.ones_like(X)], Y, rcond=None)[0]
        resid = Y - (a * X + b)
        r2 = 1 - resid.var() / Y.var()
        regression = {"a": round(float(a), 4), "b": round(float(b)), "r2": round(float(r2), 3),
                      "n": len(pairs), "resid_std": round(float(resid.std())), "fx_id": fx_id,
                      "from": str(pairs[0][0].date()), "to": str(pairs[-1][0].date())}
        fx_last_d, fx_last = fx.index[-1], float(fx.iloc[-1])
        fx_paths = simulate(np.repeat(np.log(fx_last), HMAX), increments(fx, win), steps_fan + bdays_between(fx_last_d, as_of),
                            n_paths, rng, fx_mult)
        eps = rng.choice(resid, size=(n_paths, 1))
        iran_paths = a * np.exp(lme_paths) * np.exp(fx_paths) / 1000 + b + eps
        side_paths, side_last, side_unit, side_title = np.exp(fx_paths), fx_last, "تومان بر دلار", "نرخ ارز"
    else:
        ratio = pd.Series({d: p * 1000 / asof(lme, d) for d, p in ime.items() if asof(lme, d)})
        r_paths = simulate(np.repeat(np.log(ratio.iloc[-1]), HMAX), increments(ratio, win), steps_iran, n_paths, rng, fx_mult)
        iran_paths = np.exp(lme_paths) / 1000 * np.exp(r_paths)
        side_paths, side_last = np.exp(r_paths), float(ratio.iloc[-1])
        side_unit, side_title = "تومان بر دلار (ضمنی)", "نسبت داخلی به جهانی (نرخ ضمنی)"

    hidx = [h - 1 for h, _ in HORIZONS]

    def table(paths: np.ndarray, digits: int = 0) -> dict:
        q = {k: [round(float(v), digits) for v in pct(paths[:, hidx], p)]
             for k, p in zip(("pessimistic", "base", "optimistic"), P)}
        return q

    def fan(paths: np.ndarray, digits: int = 0) -> list:
        lo, mid, hi = (pct(paths, p) for p in P)
        return [[str(d.date()), round(float(a), digits), round(float(m), digits), round(float(c), digits)]
                for d, a, m, c in zip(fan_dates, lo, mid, hi)]

    # ---- backtest of the Iran composite (same method, only data up to each origin)
    iran_bt = backtest_iran(lme, ime, fx, mode, best, win, fx_mult, P, min_pairs)

    out = {
        "generated_at": iso(now_utc()),
        "as_of": {"lme": str(as_of.date()), "iran": str(ime_last_d.date()),
                  "fx": str(fx.index[-1].date()) if len(fx) else None},
        "mode": mode,
        "mode_fa": ("رگرسیون: قیمت ایران = a × (LME × ارز ÷ ۱۰۰۰) + b" if mode == "regression" else
                    "موقت — نسبت ضمنی: قیمت ایران = LME × R ÷ ۱۰۰۰ (تاریخچهٔ نرخ ارز هنوز کافی نیست)"),
        "fx_points": len(fx), "fx_id": fx_id, "fx_pairs": len(pairs), "min_pairs": min_pairs,
        "horizons": [{"bdays": h, "label": lab, "target": str(t.date())} for (h, lab), t in zip(HORIZONS, targets)],
        "percentiles": P,
        "iran": {"title": "قیمت شمش بورس کالا", "unit": "تومان بر کیلوگرم", "last": ime_last,
                 "last_date": str(ime_last_d.date()), "scenarios": table(iran_paths), "fan": fan(iran_paths),
                 "backtest": iran_bt},
        "lme": {"title": "LME نقدی", "unit": "دلار بر تن", "last": float(lme.iloc[-1]), "last_date": str(as_of.date()),
                "model": best, "model_fa": MODEL_FA[best], "scenarios": table(np.exp(lme_paths), 1),
                "fan": fan(np.exp(lme_paths), 1), "backtest": bt, "mean_mape": {k: round(v, 2) for k, v in mean_mape.items()}},
        "side": {"title": side_title, "unit": side_unit, "last": round(side_last), "scenarios": table(side_paths),
                 "vol_multiplier": fx_mult},
        "regression": regression,
        "assumptions": A,
        "history": {"iran": [[str(d.date()), v] for d, v in ime.items()][-60:],
                    "lme": [[str(d.date()), v] for d, v in lme.items()][-130:]},
    }
    write_json(OUT, out)
    write_doc(out)
    m = out["iran"]["scenarios"]
    return f"mode={mode}, LME model={best}, Iran 1m base={m['base'][1]:,.0f} toman/kg"


def backtest_iran(lme, ime, fx, mode, model, win, mult, P, min_pairs, max_origins: int = 60) -> dict:
    """Rolling origin over IME trading days: forecast with data up to the origin, compare with the
    first trade 0–5 business days after the target date. Returns MAPE (%) and 10–90 coverage (%)."""
    rng = np.random.default_rng(11)
    res = {h: {"ape": [], "hit": []} for h, _ in HORIZONS}
    origins = [d for d in ime.index if d >= ime.index[0] + pd.Timedelta(days=60)]
    origins = origins[-max_origins:]
    for o in origins:
        lme_o = lme.loc[:o]
        if len(lme_o) < 760:
            continue
        y = np.log(lme_o.values[-750:])
        point = forecast_all(y, HMAX)[model] if model != "rw" else _fc_rw(y, HMAX)
        steps = np.array([h for h, _ in HORIZONS])
        # LME paths: model point forecast × bootstrapped noise, at the three horizons only
        lp = simulate(np.zeros(len(steps)), increments(lme_o, win), steps, 1000, rng) + point[steps - 1][None, :]
        ime_o = ime.loc[:o]
        if mode == "regression":
            pairs = [(p, asof(lme, d) * asof(fx, d, 5) / 1000) for d, p in ime_o.items() if asof(lme, d) and asof(fx, d, 5)]
            fx_o = fx.loc[:o]
            if len(pairs) < min_pairs or fx_o.empty:
                continue
            Y, X = np.array([q[0] for q in pairs]), np.array([q[1] for q in pairs])
            a, b = np.linalg.lstsq(np.c_[X, np.ones_like(X)], Y, rcond=None)[0]
            fp = simulate(np.repeat(np.log(fx_o.iloc[-1]), len(steps)), increments(fx_o, win), steps, 1000, rng, mult)
            paths = a * np.exp(lp) * np.exp(fp) / 1000 + b
        else:
            ratio = pd.Series({d: p * 1000 / asof(lme, d) for d, p in ime_o.items() if asof(lme, d)})
            if len(ratio) < 5:
                continue
            rp = simulate(np.repeat(np.log(ratio.iloc[-1]), len(steps)), increments(ratio, win), steps, 1000, rng, mult)
            paths = np.exp(lp) / 1000 * np.exp(rp)
        for k, (h, _) in enumerate(HORIZONS):
            t = o + BDay(h)
            later = ime.loc[t : t + BDay(5)]
            if later.empty:
                continue
            actual = float(later.iloc[0])
            p50 = float(np.median(paths[:, k]))
            lo, hi = np.percentile(paths[:, k], [P[0], P[2]])
            res[h]["ape"].append(abs(p50 - actual) / actual)
            res[h]["hit"].append(lo <= actual <= hi)
    return {str(h): {"mape": round(float(np.mean(v["ape"])) * 100, 2) if v["ape"] else None,
                     "coverage": round(float(np.mean(v["hit"])) * 100) if v["hit"] else None,
                     "n": len(v["ape"])} for h, v in res.items()}


# ---------------------------------------------------------------- docs/model.md

def write_doc(o: dict) -> None:
    lm, ir, reg = o["lme"], o["iran"], o["regression"]
    hz = o["horizons"]
    rows = "\n".join(
        f"| {MODEL_FA[m]} | " + " | ".join(f"{lm['backtest']['mape'][m][h['bdays']]:.2f}٪" for h in hz) + f" | {lm['mean_mape'][m]:.2f}٪ |"
        for m in MODEL_FA)
    ib = ir["backtest"]
    iran_rows = "\n".join(
        f"| {h['label']} ({h['bdays']} روز کاری) | "
        + (f"{ib[str(h['bdays'])]['mape']:.2f}٪" if ib[str(h['bdays'])]["mape"] is not None else "—") + " | "
        + (f"{ib[str(h['bdays'])]['coverage']}٪" if ib[str(h['bdays'])]["coverage"] is not None else "—")
        + f" | {ib[str(h['bdays'])]['n']} |" for h in hz)
    sc = lambda t, k, i: f"{t[k][i]:,.0f}"  # noqa: E731
    scen = "\n".join(
        f"| {h['label']} ({h['target']}) | {sc(ir['scenarios'], 'pessimistic', i)} | {sc(ir['scenarios'], 'base', i)} | {sc(ir['scenarios'], 'optimistic', i)} |"
        for i, h in enumerate(hz))
    if reg:
        reg_txt = (f"| a (ضریب) | {reg['a']} |\n| b (پرمیوم، تومان/کیلوگرم) | {reg['b']:,} |\n| R² | {reg['r2']} |\n"
                   f"| تعداد روز معاملاتی | {reg['n']} ({reg['from']} تا {reg['to']}) |\n| انحراف معیار باقیمانده | {reg['resid_std']:,} تومان |\n"
                   f"| نرخ ارز | {reg['fx_id']} |")
    else:
        reg_txt = (f"**هنوز تخمین زده نشده.** برای رگرسیون دست‌کم {o['min_pairs']} روز معاملاتی بورس کالا با نرخ ارز معلوم لازم است؛ "
                   f"الان {o['fx_pairs']} روز موجود است (سری {o['fx_id']}، {o['fx_points']} نقطه). منبع خودکار و مجاز برای تاریخچهٔ نرخ ارز پیدا نشد "
                   "(docs/sources.md)؛ نرخ بورس کالا از اولین اجرا روزانه جمع می‌شود و می‌توانید تاریخچهٔ دلار آزاد را در "
                   "`data/manual/fx_free_market.csv` وارد کنید. تا آن موقع مدل در حالت «نسبت ضمنی» کار می‌کند: "
                   "R = قیمت ایران × ۱۰۰۰ ÷ LME که هم ارز و هم ضریب و پرمیوم را با هم دارد، و مثل نرخ ارز با گام تصادفی و باند پهن‌تر شبیه‌سازی می‌شود.")
    text = f"""# مدل پیش‌بینی

> این فایل را `collector/forecast.py` در هر اجرای روزانه بازنویسی می‌کند. آخرین اجرا: {o['generated_at']}

**این تحلیل آماری است و توصیهٔ معاملاتی نیست.**

## ساختار

```
قیمت ایران (تومان/کیلوگرم) ≈ a × (LME نقدی [دلار/تن] × نرخ ارز [تومان/دلار] ÷ ۱۰۰۰) + b
```

حالت فعلی: **{o['mode_fa']}**

1. **LME** با چهار روش پیش‌بینی می‌شود (روی لگاریتم قیمت): گام تصادفی، ETS با روند میرا، ARIMA(1,1,1) و میانگین این سه. مدلی که کمترین میانگین MAPE را در بک‌تست دارد انتخاب می‌شود.
2. **نرخ ارز** (یا در حالت موقت، نسبت ضمنی R) با گام تصادفی ادامه داده می‌شود و باند عدم‌قطعیتش {o['side']['vol_multiplier']} برابر پهن‌تر گرفته می‌شود.
3. **سناریوها:** {o['assumptions']['n_paths']:,} مسیر مونت‌کارلو با بوت‌استرپ تغییرات لگاریتمی روزانهٔ تاریخی (پنجرهٔ {o['assumptions']['bootstrap_window_days']} روز، بدون رانش) — صدک {o['percentiles'][0]} (بدبینانه)، {o['percentiles'][1]} (مبنا) و {o['percentiles'][2]} (خوشبینانه)، برای ۵، ۲۲ و ۶۶ روز کاری.
4. فرض‌ها در `data/manual/scenario_assumptions.json` قابل ویرایش‌اند و در اپ نمایش داده می‌شوند.

## ضریب و پرمیوم (رگرسیون)

{('| پارامتر | مقدار |' + chr(10) + '|---|---|' + chr(10) + reg_txt) if reg else reg_txt}

آخرین نسبت ضمنی R: {o['side']['last']:,} {o['side']['unit']}.

## بک‌تست LME (rolling origin)

{lm['backtest']['origins']} مبدأ از {lm['backtest']['from']} تا {lm['backtest']['to']}، هر ۱۰ روز کاری، با پنجرهٔ آموزشی ۷۵۰ روز. MAPE:

| مدل | ۵ روز | ۲۲ روز | ۶۶ روز | میانگین |
|---|---|---|---|---|
{rows}

مدل منتخب: **{lm['model_fa']}**

## بک‌تست قیمت ایران

همان روش، در هر روز معاملاتی گذشتهٔ بورس کالا فقط با داده‌های تا همان روز؛ مقایسه با اولین معاملهٔ ۰ تا ۵ روز کاری بعد از تاریخ هدف.
«پوشش» یعنی در چند درصد موارد قیمت واقعی بین صدک ۱۰ و ۹۰ افتاد (ایده‌آل حدود ۸۰٪).

| افق | MAPE | پوشش باند ۱۰–۹۰ | تعداد |
|---|---|---|---|
{iran_rows}

## سناریوهای فعلی قیمت ایران (تومان بر کیلوگرم)

آخرین معامله: {ir['last']:,.0f} ({ir['last_date']})

| افق | بدبینانه | مبنا | خوشبینانه |
|---|---|---|---|
{scen}

## محدودیت‌ها
- تاریخچهٔ بورس کالا کوتاه است (شمش هفته‌ای ۱ تا ۲ بار عرضه می‌شود)، پس بک‌تست قیمت ایران نمونهٔ کمی دارد.
- تغییر قیمت پایه، سیاست ارزی و رویدادهای سیاسی در مدل نیست.
- پوشش کمتر از ۸۰٪ یعنی باند واقعی باید پهن‌تر باشد؛ `fx_vol_multiplier` را می‌توانید بیشتر کنید.
"""
    DOC.write_text(text, encoding="utf-8", newline="\n")
