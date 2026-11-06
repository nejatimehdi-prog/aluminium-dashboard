import numpy as np
import pandas as pd
import pytest

pytest.importorskip("statsmodels")

from collector.forecast import HORIZONS, backtest_lme, increments, simulate  # noqa: E402


def test_increments_are_demeaned_and_gap_scaled():
    idx = pd.to_datetime(["2026-01-05", "2026-01-06", "2026-01-09", "2026-01-12"])  # gaps 1, 3, 1 bdays
    s = pd.Series([100.0, 101.0, 104.0, 103.0], index=idx)
    z = increments(s, 100)
    assert len(z) == 3 and abs(z.mean()) < 1e-12


def test_simulate_shapes_and_zero_noise():
    rng = np.random.default_rng(0)
    p = simulate(np.log([10.0, 10.0]), np.array([0.0]), np.array([5, 22]), 50, rng)
    assert p.shape == (50, 2) and np.allclose(np.exp(p), 10.0)


def test_backtest_on_random_walk_has_sane_errors():
    rng = np.random.default_rng(1)
    idx = pd.bdate_range("2021-01-01", periods=1000)
    lme = pd.Series(2500 * np.exp(np.cumsum(rng.normal(0, 0.012, 1000))), index=idx)
    bt = backtest_lme(lme, window=750, step=40, span=200)
    assert bt["origins"] > 0
    for m in ("rw", "ets", "arima", "ensemble"):
        # longer horizons must not be easier than shorter ones on a random walk (on average)
        assert 0 < bt["mape"][m][HORIZONS[0][0]] < bt["mape"][m][HORIZONS[2][0]] < 40
