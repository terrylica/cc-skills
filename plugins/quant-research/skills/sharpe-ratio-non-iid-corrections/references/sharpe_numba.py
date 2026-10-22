"""
sharpe_numba.py
Numba reference implementation: "How to Use the Sharpe Ratio"
López de Prado, Lipton, Zoonekynd (2026, SSRN 5520741)

Architecture: dependency tiers for clean Rust translation.
  Tier 0: erfinv, norm_cdf, norm_ppf
  Tier 1: sr_variance (Eqs 3/58), ar1_variance_coeffs
  Tier 2: psr (Eq 9), min_trl (Eq 11), critical_sr (Eq 8)
  Tier 3: power (Eqs 12-17)

Out of scope, by operator rule (2026-10-15): the paper's Deflated Sharpe Ratio,
its Bayesian/sequential false-discovery rates and FWER, and every other
trial-count correction (Holm, Benjamini-Yekutieli, e-LOND, the minimum
backtest length MinBTL, ...). They were removed from this module and must not
be re-added. Parsimony is judged on the model itself; selection is guarded by
registration before runs and by data no run has seen; each rule reports its
own PSR / MinTRL / power.

Rust translation notes:
  float64 -> f64
  int64   -> i64
  float64[:] -> &[f64] (slice)
  -9999.0 sentinel -> Result::Err or f64::NAN
  math.erf -> libm::erf
  erfinv (custom) -> libm::erfinv (Rust nightly) or statrs::erfinv
  All functions are pure (no global state mutation)

Kurtosis convention: ALL gamma4 values are Pearson kurtosis (gamma4=3 for Gaussian).

Note on erfinv: math.erfinv is NOT available as a Numba @njit intrinsic (the CPython
math module attribute exists in Python 3.12+ but Numba does not expose it as a JIT
intrinsic in numba 0.64). We implement erfinv via the rational approximation of
J.M. Blair, C.A. Edwards, J.H. Johnson (1976) with 2 Halley-Newton refinement steps,
achieving full float64 precision (~15 significant digits). Maps to Rust: libm::erfinv.
"""

import math
import numpy as np
import numba
from numba import njit, float64, int64

# ---------------------------------------------------------------------------
# Tier 0 — Primitives
# ---------------------------------------------------------------------------


@njit(float64(float64), cache=True, fastmath=False)
def erfinv(x: float64) -> float64:
    """Inverse error function: erfinv(x) such that erf(erfinv(x)) = x.

    Domain: x in (-1, 1). Returns +/-inf at boundaries.

    Algorithm: rational approximation by Blair/Edwards/Johnson (1976) with
    2 Halley refinement steps for full float64 precision.

    The initial approximation uses piecewise rational polynomials:
      - Central region |x| < 0.7: Chebyshev-like rational in x^2
      - Tail region 0.7 <= |x| < 1: rational in -log(1-|x|)
    Halley step: y_{n+1} = y_n - u/(u' - u*u''/u') where u = erf(y_n) - x

    Rust translation: libm::erfinv (available in Rust nightly) or statrs crate.
    """
    # Boundary conditions
    if x >= 1.0:
        return math.inf
    if x <= -1.0:
        return -math.inf
    if x == 0.0:
        return 0.0

    ax: float64 = abs(x)

    # -----------------------------------------------------------------------
    # Initial approximation
    # -----------------------------------------------------------------------
    if ax < 0.7:
        # Central region: rational approximation in r = x^2
        # Coefficients from rational Chebyshev minimax approx for erfinv
        # source: based on Abramowitz & Stegun 26.2.16 / Peter Acklam's method
        r: float64 = x * x
        y: float64 = x * ((((-0.140543331 * r + 0.926847002) * r - 1.645349621) * r + 0.886226922)
                         / ((((0.012229801 * r - 0.329097515) * r + 1.442710462) * r - 2.118377725) * r + 1.0))
    else:
        # Tail region: rational approximation in w = sqrt(-log((1-|x|)/2))
        w: float64 = math.sqrt(-math.log((1.0 - ax) * 0.5))
        y_abs: float64 = ((((1.641345311 * w + 3.429567803) * w - 1.624906987) * w - 1.970840454)
                         / ((1.637067800 * w + 3.543889200) * w + 1.0))
        y = math.copysign(y_abs, x)

    # -----------------------------------------------------------------------
    # Two Halley refinement steps for full float64 precision
    # Halley step for f(y) = erf(y) - x = 0:
    #   f'(y)  = (2/sqrt(pi)) * exp(-y^2)
    #   f''(y) = -4y/sqrt(pi) * exp(-y^2)
    # Halley update: y -= f / (f' - f * f'' / (2*f'))
    #              = y - (erf(y)-x) / ((2/sqrt(pi))*exp(-y^2) * (1 + y*(erf(y)-x)))
    # -----------------------------------------------------------------------
    _2_over_sqrt_pi: float64 = 2.0 / math.sqrt(math.pi)

    for _ in range(2):
        err: float64 = math.erf(y) - x
        deriv: float64 = _2_over_sqrt_pi * math.exp(-y * y)
        y -= err / (deriv * (1.0 + y * err))

    return y


@njit(float64(float64), cache=True, fastmath=False)
def norm_cdf(x: float64) -> float64:
    """Phi(x) via erf. Maps to Rust: 0.5 * (1.0 + libm::erf(x / SQRT_2))."""
    return 0.5 * (1.0 + math.erf(x / math.sqrt(2.0)))


@njit(float64(float64), cache=True, fastmath=False)
def norm_ppf(p: float64) -> float64:
    """Phi^-1(p) via erfinv. Maps to Rust: SQRT_2 * libm::erfinv(2p-1).

    Guards:
      p <= 0 -> -inf
      p >= 1 -> +inf
    """
    if p <= 0.0:
        return -math.inf
    if p >= 1.0:
        return math.inf
    return math.sqrt(2.0) * erfinv(2.0 * p - 1.0)


# ---------------------------------------------------------------------------
# Tier 1 — SR Variance (Eqs 3/58)
# ---------------------------------------------------------------------------


@njit(float64(float64, int64, float64, float64, float64), cache=True, fastmath=False)
def sr_variance(
    sr: float64,      # Sharpe ratio at which to evaluate variance
    t: int64,         # number of observations
    gamma3: float64,  # skewness (third standardized moment)
    gamma4: float64,  # Pearson kurtosis (=3 for Gaussian)
    rho: float64,     # AR(1) autocorrelation
) -> float64:
    """Var[SR_hat] per Eq 3 / Eq 58.

    V[SR_hat] = (1/T) * (a - b*gamma3*SR + c*(gamma4-1)/4*SR^2)

    where:
      a = (1+rho)/(1-rho)
      b = (1+rho+rho^2)/(1-rho^2)    [note: rho^2 = rho*rho]
      c = (1+rho^2)/(1-rho^2)

    Guards: rho must be in (-1, 1); t must be >= 2.
    Returns -9999.0 (error sentinel) on invalid input.
    """
    if t < 2:
        return -9999.0
    if rho <= -1.0 or rho >= 1.0:
        return -9999.0

    a: float64 = (1.0 + rho) / (1.0 - rho)
    b: float64 = (1.0 + rho + rho * rho) / (1.0 - rho * rho)
    c: float64 = (1.0 + rho * rho) / (1.0 - rho * rho)

    numerator: float64 = a - b * gamma3 * sr + c * (gamma4 - 1.0) / 4.0 * sr * sr
    return numerator / float64(t)


# ---------------------------------------------------------------------------
# Supporting appendix: AR(1) variance coefficients (Eq 58 restated)
# ---------------------------------------------------------------------------


@njit(numba.types.UniTuple(float64, 3)(float64), cache=True, fastmath=False)
def ar1_variance_coeffs(rho: float64) -> numba.types.UniTuple(float64, 3):
    """Returns (a, b, c) where Var[SR_hat]*T = a - b*gamma3*SR + c*(gamma4-1)/4*SR^2."""
    a: float64 = (1.0 + rho) / (1.0 - rho)
    b: float64 = (1.0 + rho + rho * rho) / (1.0 - rho * rho)
    c: float64 = (1.0 + rho * rho) / (1.0 - rho * rho)
    return a, b, c


# ---------------------------------------------------------------------------
# Tier 2 — PSR, MinTRL, Critical SR (Eqs 9, 11, 8)
# ---------------------------------------------------------------------------


@njit(float64(float64, float64, int64, float64, float64, float64), cache=True, fastmath=False)
def psr(
    sr_hat: float64,
    sr0: float64,
    t: int64,
    gamma3: float64,
    gamma4: float64,
    rho: float64,
) -> float64:
    """Probabilistic Sharpe Ratio (Eq 9).

    PSR = Phi((SR_hat - SR0) / sigma_hat[SR0])

    Variance is evaluated at SR0 (the null), NOT at SR_hat.
    Returns -9999.0 on invalid inputs.
    """
    variance: float64 = sr_variance(sr0, t, gamma3, gamma4, rho)
    if variance <= 0.0:
        return -9999.0
    z: float64 = (sr_hat - sr0) / math.sqrt(variance)
    return norm_cdf(z)


@njit(float64(float64, float64, float64, float64, float64, float64), cache=True, fastmath=False)
def min_trl(
    sr_hat: float64,
    sr0: float64,
    gamma3: float64,
    gamma4: float64,
    rho: float64,
    alpha: float64,
) -> float64:
    """Minimum Track Record Length (Eq 11).

    MinTRL = sr_variance(SR0, T=1) * (Phi^-1(1-alpha) / (SR_hat - SR0))^2

    The T=1 trick extracts the variance formula's non-T part (since V*T = non-T part).
    Returns math.inf if SR_hat == SR0 (infinite track record needed).
    Returns -9999.0 on invalid inputs.
    """
    if sr_hat == sr0:
        return math.inf
    # sr_variance with t=1: returns the full numerator (non-T part) as a single value
    # because numerator / float64(1) = numerator
    # Guard: t=1 is valid here (we use it for the algebraic trick, not statistical estimation)
    # We need to bypass the t<2 guard by using t=2 and multiplying by 2,
    # OR we restructure. The T=1 trick: MinTRL = V[SR]*T evaluated at T=1
    # so we need the unnormalized variance (the numerator).
    # Use t=2 and multiply result by 2 to recover the non-T numerator.
    var_at_2: float64 = sr_variance(sr0, 2, gamma3, gamma4, rho)
    if var_at_2 < 0.0:
        return -9999.0
    # var_at_2 = numerator / 2, so numerator = 2 * var_at_2
    # MinTRL = numerator * (z / delta)^2 where delta = sr_hat - sr0
    non_t_part: float64 = 2.0 * var_at_2
    z_alpha: float64 = norm_ppf(1.0 - alpha)
    ratio: float64 = z_alpha / (sr_hat - sr0)
    return non_t_part * ratio * ratio


@njit(float64(float64, int64, float64, float64, float64, float64), cache=True, fastmath=False)
def critical_sr(
    sr0: float64,
    t: int64,
    gamma3: float64,
    gamma4: float64,
    rho: float64,
    alpha: float64,
) -> float64:
    """Critical Sharpe Ratio (Eq 8, restated as Eq 14).

    SR_c = SR0 + Phi^-1(1-alpha) * sigma_hat[SR0]

    Returns -9999.0 on invalid inputs.
    """
    variance: float64 = sr_variance(sr0, t, gamma3, gamma4, rho)
    if variance <= 0.0:
        return -9999.0
    return sr0 + norm_ppf(1.0 - alpha) * math.sqrt(variance)


# ---------------------------------------------------------------------------
# Tier 3 — Power (Eqs 12-17)
# ---------------------------------------------------------------------------


@njit(float64(float64, float64, int64, float64, float64, float64, float64), cache=True, fastmath=False)
def power(
    sr0: float64,
    sr1: float64,
    t: int64,
    gamma3: float64,
    gamma4: float64,
    rho: float64,
    alpha: float64,
) -> float64:
    """Statistical power (Eq 15 general form).

    power = 1 - beta = 1 - Phi((SR_c - SR1) / sigma_hat[SR1])

    Variance evaluated at SR1 (the alternative), NOT at SR0.
    Returns -9999.0 on invalid inputs.
    """
    sr_c: float64 = critical_sr(sr0, t, gamma3, gamma4, rho, alpha)
    if sr_c == -9999.0:
        return -9999.0
    variance1: float64 = sr_variance(sr1, t, gamma3, gamma4, rho)
    if variance1 <= 0.0:
        return -9999.0
    beta: float64 = norm_cdf((sr_c - sr1) / math.sqrt(variance1))
    return 1.0 - beta


# ---------------------------------------------------------------------------
# Validation tests
# ---------------------------------------------------------------------------


def _run_tests() -> None:
    """Validate against paper Exhibit 1 and companion code."""

    # Exhibit 1 hedge fund: T=24 months, gamma3=-2.448, gamma4=10.164 (Pearson), SR=0.036/0.079, rho=0.2
    SR = 0.036 / 0.079
    T = 24
    G3 = -2.448
    G4 = 10.164   # Pearson kurtosis (NOT excess kurtosis)
    RHO = 0.2

    # ------------------------------------------------------------------
    # Test 1: SR variance
    # ------------------------------------------------------------------
    var = sr_variance(SR, T, G3, G4, RHO)
    sd = math.sqrt(var)
    assert abs(sd - 0.379) < 0.001, f"sr_variance FAIL: SD={sd:.4f}, expected ~0.379"
    print(f"  sr_variance (non-Gaussian): SD = {sd:.4f}  [expected ~0.379]")

    # ------------------------------------------------------------------
    # Test 2: Gaussian baseline (rho=0, gamma3=0, gamma4=3)
    # ------------------------------------------------------------------
    var_gauss = sr_variance(SR, T, 0.0, 3.0, 0.0)
    sd_gauss = math.sqrt(var_gauss)
    assert abs(sd_gauss - 0.214) < 0.001, f"sr_variance Gaussian FAIL: SD={sd_gauss:.4f}, expected ~0.214"
    print(f"  sr_variance (Gaussian):     SD = {sd_gauss:.4f}  [expected ~0.214]")

    # ------------------------------------------------------------------
    # Test 3: PSR
    # ------------------------------------------------------------------
    p = psr(SR, 0.0, T, G3, G4, RHO)
    assert abs(p - 0.966) < 0.001, f"psr FAIL: {p:.4f}, expected ~0.966"
    print(f"  psr:                           {p:.4f}  [expected ~0.966]")

    # ------------------------------------------------------------------
    # Test 4: MinTRL
    # ------------------------------------------------------------------
    trl = min_trl(SR, 0.0, G3, G4, RHO, 0.05)
    assert abs(trl - 19.543) < 0.5, f"min_trl FAIL: {trl:.3f}, expected ~19.543"
    print(f"  min_trl:                       {trl:.3f} months  [expected ~19.543]")

    # ------------------------------------------------------------------
    # Test 5: AR(1) variance coefficients (rho=0 should give a=b=c=1)
    # ------------------------------------------------------------------
    a_coef, b_coef, c_coef = ar1_variance_coeffs(0.0)
    assert abs(a_coef - 1.0) < 1e-10, f"ar1 a FAIL: {a_coef}"
    assert abs(b_coef - 1.0) < 1e-10, f"ar1 b FAIL: {b_coef}"
    assert abs(c_coef - 1.0) < 1e-10, f"ar1 c FAIL: {c_coef}"
    print(f"  ar1_variance_coeffs(rho=0):    a={a_coef:.4f}, b={b_coef:.4f}, c={c_coef:.4f}  [all expected =1.0]")

    # ------------------------------------------------------------------
    # Test 6: norm_cdf / norm_ppf round-trip
    # ------------------------------------------------------------------
    for p_test in [0.01, 0.05, 0.5, 0.95, 0.99]:
        z_test = norm_ppf(p_test)
        p_back = norm_cdf(z_test)
        assert abs(p_back - p_test) < 1e-12, f"norm round-trip FAIL at p={p_test}: got {p_back}"
    print(f"  norm_cdf/norm_ppf round-trip:  passed for p in [0.01, 0.05, 0.5, 0.95, 0.99]")

    # ------------------------------------------------------------------
    # Test 7: PSR with SR₀=0.1 (paper Example cont.)
    # ------------------------------------------------------------------
    p_sr01 = psr(SR, 0.1, T, G3, G4, RHO)
    assert abs(p_sr01 - 0.900) < 0.005, f"psr(SR0=0.1) FAIL: {p_sr01:.4f}, expected ~0.900"
    print(f"  psr(SR0=0.1):                  {p_sr01:.4f}  [expected ~0.900]")

    # ------------------------------------------------------------------
    # Test 8: MinTRL with SR₀=0.1 (paper Example cont.)
    # ------------------------------------------------------------------
    trl_01 = min_trl(SR, 0.1, G3, G4, RHO, 0.05)
    assert abs(trl_01 - 39.369) < 1.0, f"min_trl(SR0=0.1) FAIL: {trl_01:.3f}, expected ~39.369"
    print(f"  min_trl(SR0=0.1):              {trl_01:.3f} months  [expected ~39.369]")

    # ------------------------------------------------------------------
    # Test 9: Power β with SR₁=0.5, α=0.05 (paper Example cont.)
    # ------------------------------------------------------------------
    pow_sr1 = power(0.0, 0.5, T, G3, G4, RHO, 0.05)
    beta_sr1 = 1.0 - pow_sr1
    assert abs(beta_sr1 - 0.411) < 0.01, f"beta(SR1=0.5) FAIL: {beta_sr1:.4f}, expected ~0.411"
    print(f"  beta(SR1=0.5):                 {beta_sr1:.4f}  [expected ~0.411]")

    print("\nAll tests passed.")


if __name__ == "__main__":
    print("Running sharpe_numba validation tests...")
    print(f"Numba version: {numba.__version__}")
    print(f"NumPy version: {np.__version__}")
    print()
    _run_tests()
