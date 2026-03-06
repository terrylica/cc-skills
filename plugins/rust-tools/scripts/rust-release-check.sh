#!/usr/bin/env bash
#MISE description="4-phase Rust release pipeline: fast gates (fmt/clippy/audit/machete/geiger), deep gates (deny/semver-checks/outdated), tests (nextest or cargo test), nightly-only (udeps/hack). Flags: --nightly for Phase 4, --skip-tests to skip Phase 3. Exits non-zero on blocking failures."
set -euo pipefail

# ─── Configuration ───────────────────────────────────────────────────
PASS=0
FAIL=0
WARN=0
NIGHTLY=false
SKIP_TESTS=false

# ─── Parse flags ─────────────────────────────────────────────────────
for arg in "$@"; do
    case "$arg" in
        --nightly) NIGHTLY=true ;;
        --skip-tests) SKIP_TESTS=true ;;
        --help|-h)
            echo "Usage: rust-release-check.sh [--nightly] [--skip-tests]"
            echo ""
            echo "  --nightly      Enable Phase 4 (nightly-only tools: udeps, hack)"
            echo "  --skip-tests   Skip Phase 3 (test suite)"
            exit 0
            ;;
        *)
            echo "Unknown flag: $arg (use --help for usage)"
            exit 1
            ;;
    esac
done

# ─── Helpers ─────────────────────────────────────────────────────────
pass() { ((PASS++)); echo "  ✓ $1"; }
fail() { ((FAIL++)); echo "  ✗ $1"; }
warn() { ((WARN++)); echo "  ⚠ $1 (advisory)"; }
skip() { echo "  - $1 (skipped: not installed)"; }

has_cmd() { command -v "$1" >/dev/null 2>&1; }

is_library_crate() {
    # Check for [lib] section or lib.rs
    if grep -q '^\[lib\]' Cargo.toml 2>/dev/null; then
        return 0
    fi
    if [[ -f src/lib.rs ]]; then
        return 0
    fi
    return 1
}

# ─── Pre-check: Cargo.toml ──────────────────────────────────────────
if [[ ! -f Cargo.toml ]]; then
    echo "✗ No Cargo.toml found in $(pwd) — not a Rust project"
    exit 1
fi

echo ""
echo "═══════════════════════════════════════════════════════════"
echo "  Rust Release Pipeline"
echo "═══════════════════════════════════════════════════════════"
echo ""
echo "  Project: $(pwd)"
echo "  Flags:   nightly=$NIGHTLY skip-tests=$SKIP_TESTS"
echo ""

# ═════════════════════════════════════════════════════════════════════
# Phase 1: FAST GATES (parallel)
# ═════════════════════════════════════════════════════════════════════
echo "═══════════════════════════════════════════════════════════"
echo "  Phase 1: FAST GATES"
echo "═══════════════════════════════════════════════════════════"

TMPDIR_PHASE1=$(mktemp -d)
trap 'rm -rf "$TMPDIR_PHASE1"' EXIT

# → cargo fmt --check
echo "→ Running fmt, clippy, audit, machete in parallel..."

(
    if cargo fmt --check >/dev/null 2>&1; then
        echo "pass:cargo fmt --check" > "$TMPDIR_PHASE1/fmt"
    else
        echo "fail:cargo fmt --check (formatting issues found)" > "$TMPDIR_PHASE1/fmt"
    fi
) &

# → cargo clippy
(
    if cargo clippy --all-targets --quiet -- -D clippy::suspicious -W clippy::all 2>/dev/null; then
        echo "pass:cargo clippy" > "$TMPDIR_PHASE1/clippy"
    else
        echo "fail:cargo clippy (lint violations found)" > "$TMPDIR_PHASE1/clippy"
    fi
) &

# → cargo audit
(
    if has_cmd cargo-audit; then
        if cargo audit --no-fetch -q 2>/dev/null; then
            echo "pass:cargo audit" > "$TMPDIR_PHASE1/audit"
        else
            echo "fail:cargo audit (vulnerabilities found)" > "$TMPDIR_PHASE1/audit"
        fi
    else
        echo "skip:cargo audit" > "$TMPDIR_PHASE1/audit"
    fi
) &

# → cargo machete
(
    if has_cmd cargo-machete; then
        if cargo machete --with-metadata 2>/dev/null; then
            echo "pass:cargo machete (no unused dependencies)" > "$TMPDIR_PHASE1/machete"
        else
            echo "fail:cargo machete (unused dependencies found)" > "$TMPDIR_PHASE1/machete"
        fi
    else
        echo "skip:cargo machete" > "$TMPDIR_PHASE1/machete"
    fi
) &


wait

# Collect Phase 1 results
for result_file in "$TMPDIR_PHASE1"/*; do
    result=$(cat "$result_file")
    status="${result%%:*}"
    msg="${result#*:}"
    case "$status" in
        pass) pass "$msg" ;;
        fail) fail "$msg" ;;
        skip) skip "$msg" ;;
    esac
done

echo ""

# ═════════════════════════════════════════════════════════════════════
# Phase 2: DEEP GATES (sequential)
# ═════════════════════════════════════════════════════════════════════
echo "═══════════════════════════════════════════════════════════"
echo "  Phase 2: DEEP GATES"
echo "═══════════════════════════════════════════════════════════"

# → cargo deny check
echo "→ cargo deny check..."
if has_cmd cargo-deny; then
    if [[ -f deny.toml ]] || [[ -f .deny.toml ]]; then
        if cargo deny check 2>/dev/null; then
            pass "cargo deny check"
        else
            fail "cargo deny check (policy violations found)"
        fi
    else
        echo "  - cargo deny (skipped: no deny.toml found)"
    fi
else
    skip "cargo deny"
fi

# → cargo semver-checks
echo "→ cargo semver-checks..."
if has_cmd cargo-semver-checks; then
    if is_library_crate; then
        if cargo semver-checks check-release 2>/dev/null; then
            pass "cargo semver-checks check-release"
        else
            fail "cargo semver-checks (breaking API changes detected)"
        fi
    else
        echo "  - cargo semver-checks (skipped: not a library crate)"
    fi
else
    skip "cargo semver-checks"
fi

# → cargo geiger (advisory — can crash on complex dep trees, takes minutes)
echo "→ cargo geiger --forbid-only..."
if has_cmd cargo-geiger; then
    cargo geiger --forbid-only >/dev/null 2>&1 || true
    geiger_exit=$?
    if [[ $geiger_exit -eq 0 ]]; then
        pass "cargo geiger --forbid-only"
    elif [[ $geiger_exit -gt 1 ]]; then
        warn "cargo geiger (crashed — run manually to investigate)"
    else
        warn "cargo geiger (unsafe code detected — run \`cargo geiger\` for details)"
    fi
else
    skip "cargo geiger"
fi

# → cargo outdated (advisory only — never fails the build)
echo "→ cargo outdated..."
if has_cmd cargo-outdated; then
    outdated_output=$(cargo outdated --root-deps-only 2>/dev/null || true)
    if echo "$outdated_output" | grep -q "All dependencies are up to date"; then
        pass "cargo outdated (all root deps up to date)"
    else
        warn "cargo outdated (some root deps have updates available)"
        echo "$outdated_output" | head -20 | sed 's/^/    /'
    fi
else
    skip "cargo outdated"
fi

echo ""

# ═════════════════════════════════════════════════════════════════════
# Phase 3: TESTS
# ═════════════════════════════════════════════════════════════════════
echo "═══════════════════════════════════════════════════════════"
echo "  Phase 3: TESTS"
echo "═══════════════════════════════════════════════════════════"

if [[ "$SKIP_TESTS" == true ]]; then
    echo "  - Tests skipped (--skip-tests flag)"
else
    echo "→ Running tests..."
    if has_cmd cargo-nextest; then
        if cargo nextest run 2>/dev/null; then
            pass "cargo nextest run"
        else
            fail "cargo nextest run (test failures)"
        fi
    else
        echo "  ⚠ cargo-nextest not installed, falling back to cargo test"
        if cargo test 2>/dev/null; then
            pass "cargo test"
        else
            fail "cargo test (test failures)"
        fi
    fi
fi

echo ""

# ═════════════════════════════════════════════════════════════════════
# Phase 4: NIGHTLY-ONLY (opt-in)
# ═════════════════════════════════════════════════════════════════════
echo "═══════════════════════════════════════════════════════════"
echo "  Phase 4: NIGHTLY-ONLY"
echo "═══════════════════════════════════════════════════════════"

if [[ "$NIGHTLY" != true ]]; then
    echo "  - Nightly checks skipped (pass --nightly to enable)"
else
    # → cargo +nightly udeps
    echo "→ cargo +nightly udeps..."
    if cargo +nightly udeps --version >/dev/null 2>&1; then
        if cargo +nightly udeps --all-targets 2>/dev/null; then
            pass "cargo +nightly udeps (no unused dependencies)"
        else
            fail "cargo +nightly udeps (unused dependencies found)"
        fi
    else
        skip "cargo +nightly udeps"
    fi

    # → cargo hack check --each-feature
    echo "→ cargo hack check --each-feature..."
    if has_cmd cargo-hack; then
        if cargo hack check --each-feature 2>/dev/null; then
            pass "cargo hack check --each-feature"
        else
            fail "cargo hack check --each-feature (feature combination failures)"
        fi
    else
        skip "cargo hack"
    fi
fi

echo ""

# ═════════════════════════════════════════════════════════════════════
# Summary
# ═════════════════════════════════════════════════════════════════════
echo "═══════════════════════════════════════════════════════════"
echo "  SUMMARY"
echo "═══════════════════════════════════════════════════════════"
echo ""
echo "  Passed:   $PASS"
echo "  Failed:   $FAIL"
echo "  Warnings: $WARN"
echo ""

if [[ "$FAIL" -gt 0 ]]; then
    echo "✗ Release pipeline FAILED ($FAIL blocking failures)"
    exit 1
else
    if [[ "$WARN" -gt 0 ]]; then
        echo "✓ Release pipeline PASSED ($WARN advisory warnings)"
    else
        echo "✓ Release pipeline PASSED (all gates clear)"
    fi
    exit 0
fi
