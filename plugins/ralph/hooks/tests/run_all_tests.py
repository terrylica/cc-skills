# /// script
# requires-python = ">=3.11"
# dependencies = ["rapidfuzz>=3.0.0,<4.0.0", "jinja2>=3.1.0,<4.0.0"]
# ///
"""
Ralph Test Runner

Runs all unit and integration tests for the Ralph hooks.

Usage:
    uv run tests/run_all_tests.py           # Run all tests
    uv run tests/run_all_tests.py --quick   # Skip slow tests
    uv run tests/run_all_tests.py --verbose # Show detailed output
"""

import subprocess
import sys
import time
from pathlib import Path


def run_test_file(test_file: Path, verbose: bool = False) -> tuple[bool, float]:
    """Run a single test file and return (success, duration).

    Uses 'uv run' to properly handle PEP 723 inline script dependencies.
    """
    start = time.time()
    try:
        result = subprocess.run(
            ["uv", "run", str(test_file)],
            capture_output=not verbose,
            text=True,
            cwd=test_file.parent,
            timeout=60,
        )
        duration = time.time() - start
        if result.returncode != 0 and not verbose:
            print(f"\n--- FAILED: {test_file.name} ---")
            print(result.stdout)
            print(result.stderr)
        return result.returncode == 0, duration
    except subprocess.TimeoutExpired:
        return False, 60.0
    except Exception as e:
        print(f"Error running {test_file}: {e}")
        return False, time.time() - start


def main():
    verbose = "--verbose" in sys.argv or "-v" in sys.argv
    quick = "--quick" in sys.argv

    tests_dir = Path(__file__).parent
    test_files = [
        tests_dir / "test_completion.py",
        tests_dir / "test_utils.py",
        tests_dir / "test_integration.py",
    ]

    if quick:
        # Skip integration tests in quick mode
        test_files = [f for f in test_files if "integration" not in f.name]

    print("=" * 70)
    print("RALPH TEST SUITE")
    print("=" * 70)
    print(f"Running {len(test_files)} test files...")
    print()

    results = []
    total_start = time.time()

    for test_file in test_files:
        if not test_file.exists():
            print(f"⚠ SKIP: {test_file.name} (not found)")
            continue

        print(f"▶ Running {test_file.name}...", end=" ", flush=True)
        success, duration = run_test_file(test_file, verbose)

        if success:
            print(f"✓ PASS ({duration:.2f}s)")
        else:
            print(f"✗ FAIL ({duration:.2f}s)")

        results.append((test_file.name, success, duration))

    total_duration = time.time() - total_start

    # Summary
    print()
    print("=" * 70)
    print("SUMMARY")
    print("=" * 70)

    passed = sum(1 for _, s, _ in results if s)
    failed = sum(1 for _, s, _ in results if not s)

    for name, success, duration in results:
        status = "✓ PASS" if success else "✗ FAIL"
        print(f"  {status}: {name} ({duration:.2f}s)")

    print()
    print(f"Total: {passed} passed, {failed} failed in {total_duration:.2f}s")
    print("=" * 70)

    if failed > 0:
        print("\n❌ Some tests failed!")
        sys.exit(1)
    else:
        print("\n✅ All tests passed!")
        sys.exit(0)


if __name__ == "__main__":
    main()
