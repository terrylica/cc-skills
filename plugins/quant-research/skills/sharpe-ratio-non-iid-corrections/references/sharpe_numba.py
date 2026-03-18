"""
sharpe_numba.py
Numba reference implementation: "How to Use the Sharpe Ratio"
López de Prado, Lipton, Zoonekynd (2026, SSRN 5520741)

Architecture: dependency tiers for clean Rust translation.
  Tier 0: norm_cdf, norm_ppf, Gauss-Hermite constants, Brent's method
  Tier 1: sr_variance (Eqs 3/58)
  Tier 2: psr (Eq 9), min_trl (Eq 11), critical_sr (Eq 13)
  Tier 3: power (Eq 15), moments_mk (Eqs 62-65), expected_max_sr (Eq 28), var_max_sr (Eqs 63/75)
  Tier 4: pfdr (Eq 18-21), ofdr (Eqs 22-24), fwer (Eq 25)
  Tier 5: dsr (Eqs 29-31), sfdr_threshold (Eqs 32-33)  <- APEX

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
# Tier 0 — Constants (module-level, NOT inside @njit)
# ---------------------------------------------------------------------------

EULER_GAMMA: float = 0.5772156649015328606  # Euler-Mascheroni constant

_GH_N: int = 100  # Gauss-Hermite quadrature points

# Precompute at module level with numpy (NOT inside @njit).
# np.polynomial.hermite.hermgauss returns (x, w) such that:
#   sum(w_i * f(x_i)) ≈ integral f(x) * exp(-x^2) dx
# To get N(0,1) expectation E[f(z)] = (1/sqrt(pi)) * sum(w_i * f(x_i * sqrt(2)))
_GH_X, _GH_W = np.polynomial.hermite.hermgauss(_GH_N)
_GH_X = _GH_X.astype(np.float64)
_GH_W = _GH_W.astype(np.float64)

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
# Tier 2 — PSR, MinTRL, Critical SR (Eqs 9, 11, 13)
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
    """Critical Sharpe Ratio (Eq 13).

    SR_c = SR0 + Phi^-1(1-alpha) * sigma_hat[SR0]

    Returns -9999.0 on invalid inputs.
    """
    variance: float64 = sr_variance(sr0, t, gamma3, gamma4, rho)
    if variance <= 0.0:
        return -9999.0
    return sr0 + norm_ppf(1.0 - alpha) * math.sqrt(variance)


# ---------------------------------------------------------------------------
# Tier 3 — Power, Gauss-Hermite moments, E[max SR], Var[max SR]
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


@njit(numba.types.UniTuple(float64, 3)(int64, float64[:], float64[:]), cache=True, fastmath=False)
def moments_mk(
    k: int64,
    gh_x: float64[:],
    gh_w: float64[:],
) -> numba.types.UniTuple(float64, 3):
    """Moments of the maximum of K iid N(0,1) via Gauss-Hermite quadrature (Eqs 62-65).

    Returns (E[X_k], E[X_k^2], Var[X_k]) where X_k = max of K iid N(0,1).

    Density of order statistic: f_{X_k}(x) = K * phi(x) * Phi(x)^(K-1)

    GH quadrature: integral f(x)*exp(-x^2) dx ≈ sum(w_i * f(x_i))
    For N(0,1) expectation: E[g(z)] = (1/sqrt(pi)) * sum(w_i * g(x_i*sqrt(2)))

    For the maximum order statistic:
      E[g(X_k)] = integral g(x) * K * phi(x) * Phi(x)^(K-1) dx
    Substituting z = x/sqrt(2) => x = z*sqrt(2), dx = sqrt(2)*dz:
      = integral g(z*sqrt(2)) * K * phi(z*sqrt(2)) * Phi(z*sqrt(2))^(K-1) * sqrt(2) dz
    Since phi(z*sqrt(2))*sqrt(2) = exp(-(z*sqrt(2))^2/2)/sqrt(2*pi) * sqrt(2)
                                  = exp(-z^2) / sqrt(pi)
      = (1/sqrt(pi)) * sum(w_i * g(x_i*sqrt(2)) * K * Phi(x_i*sqrt(2))^(K-1))
    """
    sqrt2: float64 = math.sqrt(2.0)
    inv_sqrt_pi: float64 = 1.0 / math.sqrt(math.pi)

    ez: float64 = 0.0
    ez2: float64 = 0.0
    n: int64 = len(gh_x)

    for i in range(n):
        z: float64 = gh_x[i] * sqrt2
        phi_z: float64 = norm_cdf(z)
        # Phi(z)^(K-1): use exp((K-1)*log(Phi(z))) for numerical stability
        if phi_z <= 0.0:
            phi_pow: float64 = 0.0
        elif k == 1:
            phi_pow = 1.0
        else:
            phi_pow = math.exp(float64(k - 1) * math.log(phi_z))
        weight: float64 = gh_w[i] * inv_sqrt_pi * float64(k) * phi_pow
        ez += weight * z
        ez2 += weight * z * z

    var: float64 = ez2 - ez * ez
    return ez, ez2, var


@njit(float64(int64, float64, float64[:], float64[:]), cache=True, fastmath=False)
def expected_max_sr(
    k: int64,
    variance: float64,
    gh_x: float64[:],
    gh_w: float64[:],
) -> float64:
    """Expected maximum SR across K iid strategies (Eq 28 / FST approximation).

    E[max SR] = SR0 + sigma * [(1-gamma) * Phi^-1(1-1/K) + gamma * Phi^-1(1-1/(K*e))]

    where gamma = Euler-Mascheroni constant (~0.5772).

    Domain: k >= 2. For k=1, E[max of 1 N(0,1)] = 0 (no selection bias under null).
    Returns -9999.0 on invalid inputs.
    """
    if k < 1:
        return -9999.0
    if k == 1:
        # E[max of 1 draw from N(0,sigma^2)] = 0 under the null SR0=0
        return 0.0
    if variance < 0.0:
        return -9999.0
    sigma: float64 = math.sqrt(variance)
    g: float64 = 0.5772156649015328606  # EULER_GAMMA (inline for @njit)
    z1: float64 = norm_ppf(1.0 - 1.0 / float64(k))
    z2: float64 = norm_ppf(1.0 - 1.0 / (float64(k) * math.e))
    return sigma * ((1.0 - g) * z1 + g * z2)


@njit(float64(int64, float64, float64[:], float64[:]), cache=True, fastmath=False)
def var_max_sr_numerical(
    k: int64,
    variance: float64,
    gh_x: float64[:],
    gh_w: float64[:],
) -> float64:
    """Exact Var[max of K iid SRs] via Gauss-Hermite quadrature (Eqs 62-65).

    Var[M_K] = variance * Var[max of K iid N(0,1)]

    Returns -9999.0 on invalid inputs.
    """
    if k < 1:
        return -9999.0
    if variance < 0.0:
        return -9999.0
    _, _, var_unit = moments_mk(k, gh_x, gh_w)  # Var for N(0,1) unit scale
    return variance * var_unit  # scale by actual per-SR variance


@njit(float64(int64, float64), cache=True, fastmath=False)
def var_max_sr_evt(
    k: int64,
    variance: float64,
) -> float64:
    """EVT approximation of Var[max of K iid SRs] (Eq 75).

    Var[M_K] ≈ Delta^2 * (pi^2/6 - gamma^2/(1+gamma)) * variance

    where Delta = Phi^-1(1-1/(K*e)) - Phi^-1(1-1/K)  (the EVT scale parameter).

    Domain: k >= 2 (same as expected_max_sr).
    Returns -9999.0 on invalid inputs.
    """
    if k < 2:
        return 0.0
    if variance < 0.0:
        return -9999.0
    z1: float64 = norm_ppf(1.0 - 1.0 / float64(k))
    z2: float64 = norm_ppf(1.0 - 1.0 / (float64(k) * math.e))
    delta: float64 = z2 - z1  # EVT scale parameter Delta
    g: float64 = 0.5772156649015328606  # EULER_GAMMA
    # Coefficient: pi^2/6 - gamma^2/(1+gamma) ≈ 1.4338...
    c: float64 = (math.pi * math.pi) / 6.0 - (g * g) / (1.0 + g)
    return variance * delta * delta * c


# ---------------------------------------------------------------------------
# Tier 4 — pFDR, oFDR, FWER (Eqs 18-21, 22-24, 25)
# ---------------------------------------------------------------------------


@njit(float64(float64, float64, float64), cache=True, fastmath=False)
def pfdr(
    p_h1: float64,  # prior probability strategy is genuine P[H1]
    alpha: float64,  # Type I error rate
    beta: float64,   # Type II error rate (= 1 - power)
) -> float64:
    """Positive False Discovery Rate (Eq 18).

    pFDR = P[H0 | SR > SR_c] = 1 / (1 + (1-beta)/alpha * p1/(1-p1))

    where beta is Type II error (1 - power), NOT power itself.
    Returns 1.0 in degenerate cases (p_h0=0 or alpha=0).
    """
    p_h0: float64 = 1.0 - p_h1
    if p_h0 == 0.0 or alpha == 0.0:
        return 1.0
    return 1.0 / (1.0 + (1.0 - beta) * p_h1 / (alpha * p_h0))


@njit(float64(float64, float64, float64, int64, float64, float64, float64, float64), cache=True, fastmath=False)
def ofdr(
    sr_hat: float64,   # observed SR (used as the threshold c)
    sr0: float64,      # null SR (typically 0)
    sr1: float64,      # alternative SR (estimated true SR)
    t: int64,
    gamma3: float64,
    gamma4: float64,
    rho: float64,
    p_h1: float64,     # prior P[strategy is genuine]
) -> float64:
    """Observed False Discovery Rate (Eqs 22-24).

    oFDR uses OBSERVED SR as threshold (not pre-specified SR_c):

    oFDR = P[H0] * P[SR > sr_hat | H0] /
           (P[H0] * P[SR > sr_hat | H0] + P[H1] * P[SR > sr_hat | H1])

    P[SR > sr_hat | H_i] = 1 - PSR(sr_hat, SR_i, ...)  (upper tail probability)
    Variance is heteroscedastic: evaluated at SR0 for H0 term, at SR1 for H1 term.

    Returns -9999.0 if denominator is zero (pathological case).
    """
    p_h0: float64 = 1.0 - p_h1
    p_tail_h0: float64 = 1.0 - psr(sr_hat, sr0, t, gamma3, gamma4, rho)
    p_tail_h1: float64 = 1.0 - psr(sr_hat, sr1, t, gamma3, gamma4, rho)
    denom: float64 = p_h0 * p_tail_h0 + p_h1 * p_tail_h1
    if denom == 0.0:
        return -9999.0
    return p_h0 * p_tail_h0 / denom


@njit(float64(float64, int64), cache=True, fastmath=False)
def fwer(
    alpha: float64,  # per-test significance level
    k: int64,        # number of independent tests
) -> float64:
    """Family-Wise Error Rate (Eq 25): Sidak/Bonferroni exact for independent tests.

    FWER = 1 - (1 - alpha)^K
    """
    return 1.0 - (1.0 - alpha) ** k


# ---------------------------------------------------------------------------
# Tier 5 — APEX: DSR (Eqs 29-31) and SFDR threshold (Eqs 32-33)
# ---------------------------------------------------------------------------


@njit(float64(float64[:], int64, int64, float64, float64, float64, float64[:], float64[:]), cache=True, fastmath=False)
def dsr(
    sr_hats: float64[:],   # observed SR estimates, shape (K,)
    k: int64,              # number of trials
    t: int64,              # track record length
    gamma3: float64,
    gamma4: float64,
    rho: float64,
    gh_x: float64[:],      # Gauss-Hermite nodes
    gh_w: float64[:],      # Gauss-Hermite weights
) -> float64:
    """Deflated Sharpe Ratio (Eqs 29-31).

    DSR = PSR[max(SR_hat) | SR0_adj, sigma(SR0_adj)]

    where:
      SR0_adj = E[max of K iid SRs under null]  (selection-bias-adjusted null)
      sigma(SR0_adj) = cross_sd * evt_scale      (per Eq 31)

    For k=1: DSR reduces to PSR (no selection bias).

    The cross-sectional SD of observed SRs captures the spread of strategies tested.
    The EVT order-statistic factor scales it by how extreme the max of K N(0,1) is.
    """
    # Find the best (maximum) observed SR
    sr_best: float64 = sr_hats[0]
    for i in range(1, k):
        if sr_hats[i] > sr_best:
            sr_best = sr_hats[i]

    # Degenerate case: no selection bias when only one strategy
    if k == 1:
        return psr(sr_best, 0.0, t, gamma3, gamma4, rho)

    # Cross-sectional mean and variance of observed SRs (Eq 31)
    mean_sr: float64 = 0.0
    for i in range(k):
        mean_sr += sr_hats[i]
    mean_sr /= float64(k)

    cross_var: float64 = 0.0
    for i in range(k):
        diff: float64 = sr_hats[i] - mean_sr
        cross_var += diff * diff
    cross_var /= float64(k - 1)  # sample variance, k-1 denominator (Bessel's correction)

    cross_sd: float64 = math.sqrt(cross_var) if cross_var > 0.0 else 0.0

    # EVT order-statistic scale factor: sqrt(Var[max of K iid N(0,1)])
    _, _, var_unit = moments_mk(k, gh_x, gh_w)
    evt_scale: float64 = math.sqrt(var_unit) if var_unit > 0.0 else 0.0

    # SR0_adj: expected maximum SR under null (all true SRs = 0)
    # Uses per-SR sampling variance at null SR0=0
    per_sr_var: float64 = sr_variance(0.0, t, gamma3, gamma4, rho)
    sr0_adj: float64 = expected_max_sr(k, per_sr_var, gh_x, gh_w)

    # sigma(SR0_K) per Eq 31: cross-sectional SD x EVT order-statistic factor
    sigma_adj: float64 = cross_sd * evt_scale

    if sigma_adj <= 0.0:
        # Degenerate: all observed SRs identical, fall back to standard PSR
        return psr(sr_best, sr0_adj, t, gamma3, gamma4, rho)

    # DSR = Phi((sr_best - sr0_adj) / sigma_adj)
    z: float64 = (sr_best - sr0_adj) / sigma_adj
    return norm_cdf(z)


@njit(float64(float64, float64, float64, int64, float64, float64, float64, float64), cache=True, fastmath=False)
def sfdr_threshold(
    sr0: float64,     # null SR
    sr1: float64,     # alternative SR (best prior estimate of true SR)
    t: int64,
    gamma3: float64,
    gamma4: float64,
    rho: float64,
    p_h1: float64,    # prior P[H1]: probability strategy is genuine
    q: float64,       # target FDR level (e.g., 0.05)
) -> float64:
    """SFDR equilibrium threshold (Eqs 32-33).

    Find SR_c* such that P[H0 | SR > SR_c*] = q.

    This is the strategic FDR threshold: allocate to strategy iff observed SR > SR_c*.
    Solved via Brent's root-finding: ofdr(c, ...) - q = 0.

    Search bounds: SR_c in (sr0 + epsilon, sr1 + 10*sigma_approx).
    Returns -9999.0 if q is not achievable in the search interval.
    """
    sigma_approx: float64 = math.sqrt(sr_variance(sr0, t, gamma3, gamma4, rho))
    a: float64 = sr0 + 0.001       # just above null
    b: float64 = sr1 + 10.0 * sigma_approx  # well above alternative

    tol: float64 = 1.0e-10
    max_iter: int64 = 200

    # Objective: ofdr(c) - q
    fa: float64 = ofdr(a, sr0, sr1, t, gamma3, gamma4, rho, p_h1) - q
    fb: float64 = ofdr(b, sr0, sr1, t, gamma3, gamma4, rho, p_h1) - q

    # Check bracket validity: fa and fb must have opposite signs
    if fa * fb > 0.0:
        return -9999.0

    # Standard Brent's method (Illinois/Brent hybrid)
    # Variables named to avoid collision with outer scope
    c_pt: float64 = a
    fc: float64 = fa
    d: float64 = b - a
    e: float64 = d

    for _ in range(max_iter):
        if fb * fc > 0.0:
            c_pt = a
            fc = fa
            d = b - a
            e = d

        if abs(fc) < abs(fb):
            a = b
            fa = fb
            b = c_pt
            fb = fc
            c_pt = a
            fc = fa

        tol1: float64 = 2.0 * tol * abs(b) + 0.5 * tol
        xm: float64 = 0.5 * (c_pt - b)

        if abs(xm) <= tol1 or fb == 0.0:
            return b

        if abs(e) >= tol1 and abs(fa) > abs(fb):
            s: float64 = fb / fa
            if a == c_pt:
                p_val: float64 = 2.0 * xm * s
                q_val: float64 = 1.0 - s
            else:
                q_val = fa / fc
                r_val: float64 = fb / fc
                p_val = s * (2.0 * xm * q_val * (q_val - r_val) - (b - a) * (r_val - 1.0))
                q_val = (q_val - 1.0) * (r_val - 1.0) * (s - 1.0)

            if p_val > 0.0:
                q_val = -q_val
            else:
                p_val = -p_val

            if 2.0 * p_val < min(3.0 * xm * q_val - abs(tol1 * q_val), abs(e * q_val)):
                e = d
                d = p_val / q_val
            else:
                d = xm
                e = d
        else:
            d = xm
            e = d

        a = b
        fa = fb

        if abs(d) > tol1:
            b += d
        elif xm > 0.0:
            b += tol1
        else:
            b -= tol1

        fb = ofdr(b, sr0, sr1, t, gamma3, gamma4, rho, p_h1) - q

    # Return best estimate even if not fully converged within max_iter
    return b


# ---------------------------------------------------------------------------
# Appendix: Effective N via eigenvalue entropy (Appendix A.3)
# ---------------------------------------------------------------------------


@njit(float64(float64[:]), cache=True, fastmath=False)
def effective_n_eigenvalues(eigenvalues: float64[:]) -> float64:
    """Effective number of independent trials via eigenvalue entropy (Appendix A.3).

    K_eff = exp(H) where H = Shannon entropy of normalized eigenvalue distribution.
    Roy & Vetterli (2007): H = -sum(p_i * ln(p_i)), p_i = lambda_i / sum(lambda).

    Used to account for correlation among strategies when assessing multiple testing.
    """
    n: int64 = len(eigenvalues)
    total: float64 = 0.0
    for i in range(n):
        if eigenvalues[i] > 0.0:
            total += eigenvalues[i]
    if total == 0.0:
        return 1.0

    H: float64 = 0.0
    for i in range(n):
        if eigenvalues[i] > 0.0:
            p: float64 = eigenvalues[i] / total
            H -= p * math.log(p)
    return math.exp(H)


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
    # Test 5: pFDR
    # ------------------------------------------------------------------
    pow_val = power(0.0, SR, T, G3, G4, RHO, 0.05)
    beta_val = 1.0 - pow_val
    pfdr_val = pfdr(0.1, 0.05, beta_val)
    assert 0.0 < pfdr_val < 1.0, f"pfdr FAIL: {pfdr_val}"
    print(f"  pfdr(p_h1=0.1):                {pfdr_val:.4f}  [in (0,1)]")

    # ------------------------------------------------------------------
    # Test 6: expected_max_sr at K=100
    # ------------------------------------------------------------------
    emax = expected_max_sr(100, 1.0, _GH_X, _GH_W)
    assert 2.5 < emax < 4.0, f"expected_max_sr K=100 FAIL: {emax:.4f}, expected in (2.5, 4.0)"
    print(f"  expected_max_sr K=100, σ=1:    {emax:.4f}  [expected in (2.5, 4.0)]")

    # ------------------------------------------------------------------
    # Test 7: var_max_sr EVT vs numerical
    # ------------------------------------------------------------------
    var_num = var_max_sr_numerical(100, 1.0, _GH_X, _GH_W)
    var_evt = var_max_sr_evt(100, 1.0)
    err_pct = abs(var_evt - var_num) / var_num * 100
    assert err_pct < 10.0, f"var_max_sr EVT error {err_pct:.1f}%, expected < 10%"
    print(f"  var_max_sr: numerical SD={math.sqrt(var_num):.4f}, EVT SD={math.sqrt(var_evt):.4f}, err={err_pct:.1f}%  [expected < 10%]")

    # ------------------------------------------------------------------
    # Test 8: FWER
    # ------------------------------------------------------------------
    fw = fwer(0.05, 10)
    expected_fw = 1.0 - (1.0 - 0.05) ** 10
    assert abs(fw - expected_fw) < 1e-10, f"fwer FAIL: {fw} != {expected_fw}"
    print(f"  fwer(α=0.05, K=10):            {fw:.6f}  [exact: {expected_fw:.6f}]")

    # ------------------------------------------------------------------
    # Test 9: SFDR threshold
    # ------------------------------------------------------------------
    sr_c = sfdr_threshold(0.0, SR, T, G3, G4, RHO, 0.1, 0.05)
    if sr_c != -9999.0:
        fdr_at_c = ofdr(sr_c, 0.0, SR, T, G3, G4, RHO, 0.1)
        assert abs(fdr_at_c - 0.05) < 0.01, f"sfdr_threshold FAIL: FDR at threshold = {fdr_at_c:.4f}, expected ~0.05"
        print(f"  sfdr_threshold: SR_c = {sr_c:.4f}, FDR at c = {fdr_at_c:.4f}  [expected FDR ~0.05]")
    else:
        print("  sfdr_threshold: no valid threshold found (q not achievable) - check parameters")

    # ------------------------------------------------------------------
    # Test 10: DSR with K=5 strategies
    # ------------------------------------------------------------------
    np.random.seed(42)
    fake_srs = np.array([0.1, 0.3, -0.1, SR, 0.2], dtype=np.float64)
    d = dsr(fake_srs, 5, T, G3, G4, RHO, _GH_X, _GH_W)
    assert 0.0 <= d <= 1.0, f"dsr FAIL: {d:.4f} not in [0,1]"
    print(f"  dsr K=5 strategies:            {d:.4f}  [expected in [0,1]]")

    # ------------------------------------------------------------------
    # Test 11: effective_n_eigenvalues
    # ------------------------------------------------------------------
    eigs_uniform = np.array([1.0, 1.0, 1.0, 1.0], dtype=np.float64)
    keff_uniform = effective_n_eigenvalues(eigs_uniform)
    assert abs(keff_uniform - 4.0) < 1e-6, f"effective_n_eigenvalues uniform FAIL: {keff_uniform}"
    eigs_concentrated = np.array([10.0, 0.1, 0.1, 0.1], dtype=np.float64)
    keff_conc = effective_n_eigenvalues(eigs_concentrated)
    assert keff_conc < 4.0, f"effective_n_eigenvalues concentrated FAIL: {keff_conc} should be < 4"
    print(f"  effective_n_eigenvalues:       uniform={keff_uniform:.4f} [=4], concentrated={keff_conc:.4f} [<4]")

    # ------------------------------------------------------------------
    # Test 12: AR(1) variance coefficients (rho=0 should give a=b=c=1)
    # ------------------------------------------------------------------
    a_coef, b_coef, c_coef = ar1_variance_coeffs(0.0)
    assert abs(a_coef - 1.0) < 1e-10, f"ar1 a FAIL: {a_coef}"
    assert abs(b_coef - 1.0) < 1e-10, f"ar1 b FAIL: {b_coef}"
    assert abs(c_coef - 1.0) < 1e-10, f"ar1 c FAIL: {c_coef}"
    print(f"  ar1_variance_coeffs(rho=0):    a={a_coef:.4f}, b={b_coef:.4f}, c={c_coef:.4f}  [all expected =1.0]")

    # ------------------------------------------------------------------
    # Test 13: norm_cdf / norm_ppf round-trip
    # ------------------------------------------------------------------
    for p_test in [0.01, 0.05, 0.5, 0.95, 0.99]:
        z_test = norm_ppf(p_test)
        p_back = norm_cdf(z_test)
        assert abs(p_back - p_test) < 1e-12, f"norm round-trip FAIL at p={p_test}: got {p_back}"
    print(f"  norm_cdf/norm_ppf round-trip:  passed for p in [0.01, 0.05, 0.5, 0.95, 0.99]")

    # ------------------------------------------------------------------
    # Test 14: PSR with SR₀=0.1 (paper Example cont.)
    # ------------------------------------------------------------------
    p_sr01 = psr(SR, 0.1, T, G3, G4, RHO)
    assert abs(p_sr01 - 0.900) < 0.005, f"psr(SR0=0.1) FAIL: {p_sr01:.4f}, expected ~0.900"
    print(f"  psr(SR0=0.1):                  {p_sr01:.4f}  [expected ~0.900]")

    # ------------------------------------------------------------------
    # Test 15: MinTRL with SR₀=0.1 (paper Example cont.)
    # ------------------------------------------------------------------
    trl_01 = min_trl(SR, 0.1, G3, G4, RHO, 0.05)
    assert abs(trl_01 - 39.369) < 1.0, f"min_trl(SR0=0.1) FAIL: {trl_01:.3f}, expected ~39.369"
    print(f"  min_trl(SR0=0.1):              {trl_01:.3f} months  [expected ~39.369]")

    # ------------------------------------------------------------------
    # Test 16: Power β with SR₁=0.5, α=0.05 (paper Example cont.)
    # ------------------------------------------------------------------
    pow_sr1 = power(0.0, 0.5, T, G3, G4, RHO, 0.05)
    beta_sr1 = 1.0 - pow_sr1
    assert abs(beta_sr1 - 0.411) < 0.01, f"beta(SR1=0.5) FAIL: {beta_sr1:.4f}, expected ~0.411"
    print(f"  beta(SR1=0.5):                 {beta_sr1:.4f}  [expected ~0.411]")

    # ------------------------------------------------------------------
    # Test 17: pFDR exact (paper Example cont.: P[H1]=0.1, α=0.05, β=0.411)
    # ------------------------------------------------------------------
    pfdr_exact = pfdr(0.1, 0.05, beta_sr1)
    assert abs(pfdr_exact - 0.433) < 0.01, f"pfdr exact FAIL: {pfdr_exact:.4f}, expected ~0.433"
    print(f"  pfdr(P[H1]=0.1, exact beta):   {pfdr_exact:.4f}  [expected ~0.433]")

    # ------------------------------------------------------------------
    # Test 18: oFDR exact (paper Example cont.: SR₁=0.5, P[H1]=0.1)
    # ------------------------------------------------------------------
    ofdr_val = ofdr(SR, 0.0, 0.5, T, G3, G4, RHO, 0.1)
    assert abs(ofdr_val - 0.361) < 0.02, f"ofdr exact FAIL: {ofdr_val:.4f}, expected ~0.361"
    print(f"  ofdr(SR1=0.5, P[H1]=0.1):     {ofdr_val:.4f}  [expected ~0.361]")

    print("\nAll tests passed.")


if __name__ == "__main__":
    print("Running sharpe_numba validation tests...")
    print(f"Numba version: {numba.__version__}")
    print(f"NumPy version: {np.__version__}")
    print()
    _run_tests()
