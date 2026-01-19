#!/usr/bin/env python3
"""Compute range bar evaluation metrics from predictions and actuals.

Usage:
    python compute_metrics.py --predictions preds.npy --actuals actuals.npy --timestamps ts.npy
    python compute_metrics.py --results folds.jsonl --aggregate

Reference: quant-research:rangebar-eval-metrics skill
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

import numpy as np
import pandas as pd
from scipy import stats
from scipy.stats import norm, spearmanr


# =============================================================================
# Daily Aggregation (Canonical)
# =============================================================================


def _group_by_day(pnl: np.ndarray, timestamps: np.ndarray) -> np.ndarray:
    """Aggregate bar-level PnL to daily."""
    df = pd.DataFrame({"pnl": pnl, "ts": pd.to_datetime(timestamps, utc=True)})
    df["date"] = df["ts"].dt.date
    return df.groupby("date")["pnl"].sum().values


# =============================================================================
# Primary Metrics (Tier 1)
# =============================================================================


def compute_weekly_sharpe(
    pnl: np.ndarray, timestamps: np.ndarray, days_per_week: int = 7
) -> float:
    """Daily-aggregated Sharpe scaled to weekly."""
    daily_pnl = _group_by_day(pnl, timestamps)
    if len(daily_pnl) < 2:
        return 0.0
    std = np.std(daily_pnl, ddof=1)
    if std < 1e-10:
        return 0.0
    return float(np.mean(daily_pnl) / std * np.sqrt(days_per_week))


def compute_hit_rate(predictions: np.ndarray, actuals: np.ndarray) -> float:
    """Directional accuracy."""
    return float(np.mean(np.sign(predictions) == np.sign(actuals)))


def compute_cumulative_pnl(pnl: np.ndarray) -> float:
    """Total PnL."""
    return float(np.sum(pnl))


# =============================================================================
# Secondary Metrics (Tier 2)
# =============================================================================


def compute_max_drawdown(pnl: np.ndarray) -> float:
    """Maximum drawdown from cumulative PnL."""
    cumsum = np.cumsum(pnl)
    peak = np.maximum.accumulate(cumsum)
    drawdown = cumsum - peak
    return float(np.min(drawdown))


def compute_profit_factor(pnl: np.ndarray, timestamps: np.ndarray) -> float:
    """Profit factor with daily aggregation."""
    daily_pnl = _group_by_day(pnl, timestamps)
    gains = daily_pnl[daily_pnl > 0].sum()
    losses = abs(daily_pnl[daily_pnl < 0].sum())
    if losses < 1e-10:
        return float("inf") if gains > 0 else 1.0
    return float(gains / losses)


def compute_ic(predictions: np.ndarray, actuals: np.ndarray) -> float:
    """Spearman rank IC."""
    if len(predictions) < 10:
        return float("nan")
    ic, _ = spearmanr(predictions, actuals)
    return float(ic)


def compute_prediction_autocorr(predictions: np.ndarray) -> float:
    """Lag-1 autocorrelation of predictions."""
    if len(predictions) < 3:
        return float("nan")
    return float(np.corrcoef(predictions[:-1], predictions[1:])[0, 1])


# =============================================================================
# Statistical Validation (Tier 3 - Diagnostic)
# =============================================================================


def compute_sharpe_se(
    sharpe: float, n: int, skewness: float, kurtosis: float
) -> float:
    """Mertens (2002) SE with non-normality adjustment."""
    if n < 2:
        return float("nan")
    excess_kurt = kurtosis - 3.0
    variance_term = 1.0 + 0.5 * sharpe**2 - skewness * sharpe + (excess_kurt / 4.0) * sharpe**2
    if variance_term < 0:
        return float("nan")
    return float(np.sqrt(variance_term / (n - 1)))


def compute_psr(sharpe: float, se: float, benchmark: float = 0.0) -> float:
    """Probabilistic Sharpe Ratio."""
    if se <= 1e-10:
        return float("nan")
    return float(norm.cdf((sharpe - benchmark) / se))


def compute_dsr(sharpe: float, se: float, n_trials: int) -> float:
    """Deflated Sharpe Ratio."""
    if n_trials < 1 or se <= 1e-10:
        return float("nan")
    gamma = 0.5772156649
    if n_trials == 1:
        sr_expected = 0.0
    else:
        q1 = norm.ppf(1.0 - 1.0 / n_trials)
        q2 = norm.ppf(1.0 - 1.0 / (n_trials * np.e))
        sr_expected = se * ((1 - gamma) * q1 + gamma * q2)
    return float(norm.cdf((sharpe - sr_expected) / se))


# =============================================================================
# Full Evaluation
# =============================================================================


def evaluate_fold(
    predictions: np.ndarray,
    actuals: np.ndarray,
    timestamps: np.ndarray,
    n_trials: int = 1,
    days_per_week: int = 7,
) -> dict:
    """Compute all metrics for a single fold."""
    pnl = predictions * actuals
    n_bars = len(pnl)

    if n_bars == 0:
        return {"error": "no_data"}

    # Primary
    weekly_sharpe = compute_weekly_sharpe(pnl, timestamps, days_per_week)
    hit_rate = compute_hit_rate(predictions, actuals)
    cumulative_pnl = compute_cumulative_pnl(pnl)

    # Secondary
    max_drawdown = compute_max_drawdown(pnl)
    profit_factor = compute_profit_factor(pnl, timestamps)
    ic = compute_ic(predictions, actuals)
    autocorr = compute_prediction_autocorr(predictions)
    bar_sharpe = float(np.mean(pnl) / np.std(pnl)) if np.std(pnl) > 0 else 0.0

    # Statistical validation
    daily_pnl = _group_by_day(pnl, timestamps)
    n_days = len(daily_pnl)
    skewness = float(stats.skew(daily_pnl)) if n_days > 2 else 0.0
    kurtosis = float(stats.kurtosis(daily_pnl) + 3) if n_days > 3 else 3.0

    sharpe_se = compute_sharpe_se(weekly_sharpe, n_days, skewness, kurtosis)
    psr = compute_psr(weekly_sharpe, sharpe_se) if not np.isnan(sharpe_se) else None
    dsr = compute_dsr(weekly_sharpe, sharpe_se, n_trials) if not np.isnan(sharpe_se) else None

    return {
        # Primary
        "weekly_sharpe": weekly_sharpe,
        "hit_rate": hit_rate,
        "cumulative_pnl": cumulative_pnl,
        "n_bars": n_bars,
        # Secondary
        "max_drawdown": max_drawdown,
        "bar_sharpe": bar_sharpe,
        "profit_factor": float(min(profit_factor, 1e6)),
        "ic": ic if not np.isnan(ic) else None,
        "prediction_autocorr": autocorr if not np.isnan(autocorr) else None,
        # Statistical validation
        "sharpe_se": sharpe_se if not np.isnan(sharpe_se) else None,
        "psr": psr,
        "dsr": dsr,
        "skewness": skewness,
        "kurtosis": kurtosis,
    }


def compute_aggregate_metrics(fold_metrics: list[dict]) -> dict:
    """Aggregate metrics across folds."""
    sharpes = [f["weekly_sharpe"] for f in fold_metrics if f.get("weekly_sharpe") is not None]

    if not sharpes:
        return {"error": "no_valid_folds"}

    positive_rate = np.mean([s > 0 for s in sharpes])

    # Binomial test
    n_positive = sum(1 for s in sharpes if s > 0)
    n_total = len(sharpes)
    binomial_pvalue = float(1 - stats.binom.cdf(n_positive - 1, n_total, 0.5))

    # Autocorrelation of fold Sharpes
    autocorr_lag1 = float(np.corrcoef(sharpes[:-1], sharpes[1:])[0, 1]) if len(sharpes) > 2 else 0.0

    # Effective N (autocorrelation adjusted)
    rho = max(0, min(autocorr_lag1, 0.99))
    effective_n = n_total * (1 - rho) / (1 + rho)

    return {
        "mean_weekly_sharpe": float(np.mean(sharpes)),
        "std_weekly_sharpe": float(np.std(sharpes)),
        "median_weekly_sharpe": float(np.median(sharpes)),
        "positive_sharpe_rate": float(positive_rate),
        "n_folds": n_total,
        "binomial_pvalue": binomial_pvalue,
        "autocorr_lag1": autocorr_lag1 if not np.isnan(autocorr_lag1) else 0.0,
        "effective_n": float(effective_n),
    }


# =============================================================================
# CLI
# =============================================================================


def main():
    parser = argparse.ArgumentParser(description="Compute range bar metrics")
    parser.add_argument("--predictions", type=Path, help="Path to predictions .npy")
    parser.add_argument("--actuals", type=Path, help="Path to actuals .npy")
    parser.add_argument("--timestamps", type=Path, help="Path to timestamps .npy")
    parser.add_argument("--results", type=Path, help="Path to fold results .jsonl")
    parser.add_argument("--aggregate", action="store_true", help="Compute aggregate metrics")
    parser.add_argument("--output", type=Path, help="Output path (default: stdout)")
    parser.add_argument("--days-per-week", type=int, default=7, help="7 for crypto, 5 for equity")

    args = parser.parse_args()

    if args.results and args.aggregate:
        # Aggregate mode
        fold_metrics = []
        with open(args.results) as f:
            for line in f:
                fold_metrics.append(json.loads(line))
        result = compute_aggregate_metrics(fold_metrics)
    elif args.predictions and args.actuals and args.timestamps:
        # Single fold mode
        predictions = np.load(args.predictions)
        actuals = np.load(args.actuals)
        timestamps = np.load(args.timestamps)
        result = evaluate_fold(predictions, actuals, timestamps, days_per_week=args.days_per_week)
    else:
        parser.print_help()
        sys.exit(1)

    output = json.dumps(result, indent=2)
    if args.output:
        args.output.write_text(output)
    else:
        print(output)


if __name__ == "__main__":
    main()
