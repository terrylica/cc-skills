# /// script
# requires-python = ">=3.11"
# dependencies = ["rapidfuzz>=3.0.0,<4.0.0"]
# ///
"""Unit tests for utils.py - Time tracking, loop detection, hook outputs."""

import io
import json
import sys
import tempfile
import time
from contextlib import redirect_stdout
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent))

from utils import (
    WINDOW_SIZE,
    allow_stop,
    continue_session,
    detect_loop,
    extract_section,
    get_loop_detection_config,
    get_runtime_hours,
    get_wall_clock_hours,
    hard_stop,
    update_runtime,
)


def test_wall_clock_hours():
    """Test wall-clock time calculation from timestamp file."""
    with tempfile.TemporaryDirectory() as tmp:
        tmp_dir = Path(tmp)

        # Create .claude directory with loop-start-timestamp
        claude_dir = tmp_dir / ".claude"
        claude_dir.mkdir()
        timestamp_file = claude_dir / "loop-start-timestamp"

        # Set timestamp to 2 hours ago
        two_hours_ago = int(time.time()) - (2 * 3600)
        timestamp_file.write_text(str(two_hours_ago))

        elapsed = get_wall_clock_hours("test-session", str(tmp_dir))
        assert 1.9 <= elapsed <= 2.1, f"Expected ~2 hours, got {elapsed}"
        print(f"✓ Wall-clock hours: {elapsed:.2f}")

    # No timestamp file - should return 0
    elapsed_no_file = get_wall_clock_hours("nonexistent", "/tmp/nonexistent")
    assert elapsed_no_file == 0.0
    print("✓ Missing timestamp returns 0.0")


def test_update_runtime_normal_iteration():
    """Test runtime accumulation during normal CLI operation."""
    state = {
        "accumulated_runtime_seconds": 0.0,
        "last_hook_timestamp": 0.0,
    }

    # First call - no previous timestamp, should initialize
    t1 = 1000.0
    result = update_runtime(state, t1, gap_threshold=300)
    assert result == 0.0, "First call should return 0 (no previous timestamp)"
    assert state["last_hook_timestamp"] == t1
    assert state["accumulated_runtime_seconds"] == 0.0
    print("✓ First call initializes timestamp, runtime=0")

    # Second call after 60 seconds (normal iteration)
    t2 = t1 + 60  # 60 seconds later
    result = update_runtime(state, t2, gap_threshold=300)
    assert 59.9 <= result <= 60.1, f"Expected ~60s runtime, got {result}"
    assert state["last_hook_timestamp"] == t2
    print(f"✓ Normal 60s iteration: runtime={result:.1f}s")

    # Third call after another 30 seconds
    t3 = t2 + 30
    result = update_runtime(state, t3, gap_threshold=300)
    assert 89.9 <= result <= 90.1, f"Expected ~90s runtime, got {result}"
    print(f"✓ Accumulated runtime: {result:.1f}s")


def test_update_runtime_gap_detection():
    """Test that CLI pause (gap > threshold) is NOT counted as runtime."""
    state = {
        "accumulated_runtime_seconds": 100.0,  # Start with 100s runtime
        "last_hook_timestamp": 1000.0,
    }

    # Gap of 600 seconds (10 minutes) - exceeds 300s threshold
    # This simulates user closing CLI for 10 minutes
    t_after_gap = 1000.0 + 600
    result = update_runtime(state, t_after_gap, gap_threshold=300)

    # Runtime should NOT increase - gap indicates CLI was closed
    assert result == 100.0, f"Expected 100s (gap not counted), got {result}"
    assert state["last_hook_timestamp"] == t_after_gap
    print(f"✓ Gap of 600s detected - runtime unchanged at {result:.1f}s")


def test_update_runtime_edge_cases():
    """Test edge cases for runtime tracking."""
    # Test exactly at threshold boundary
    state = {
        "accumulated_runtime_seconds": 50.0,
        "last_hook_timestamp": 1000.0,
    }

    # Gap exactly at threshold (300s) - should be counted as active
    t_at_threshold = 1000.0 + 299  # Just under threshold
    result = update_runtime(state, t_at_threshold, gap_threshold=300)
    assert 348.9 <= result <= 349.1, f"Expected ~349s, got {result}"
    print(f"✓ Gap at 299s (under threshold): runtime={result:.1f}s")

    # Gap just over threshold - should NOT be counted
    state2 = {
        "accumulated_runtime_seconds": 50.0,
        "last_hook_timestamp": 1000.0,
    }
    t_over_threshold = 1000.0 + 301  # Just over threshold
    result2 = update_runtime(state2, t_over_threshold, gap_threshold=300)
    assert result2 == 50.0, f"Expected 50s (gap not counted), got {result2}"
    print(f"✓ Gap at 301s (over threshold): runtime unchanged at {result2:.1f}s")


def test_get_runtime_hours():
    """Test conversion of accumulated seconds to hours."""
    # Test with 0 seconds
    state_zero = {"accumulated_runtime_seconds": 0.0}
    assert get_runtime_hours(state_zero) == 0.0
    print("✓ Zero seconds = 0.0 hours")

    # Test with 1 hour (3600 seconds)
    state_one_hour = {"accumulated_runtime_seconds": 3600.0}
    assert get_runtime_hours(state_one_hour) == 1.0
    print("✓ 3600 seconds = 1.0 hour")

    # Test with 2.5 hours (9000 seconds)
    state_partial = {"accumulated_runtime_seconds": 9000.0}
    assert get_runtime_hours(state_partial) == 2.5
    print("✓ 9000 seconds = 2.5 hours")

    # Test with missing key (defaults to 0)
    state_missing = {}
    assert get_runtime_hours(state_missing) == 0.0
    print("✓ Missing key defaults to 0.0 hours")


def test_runtime_overnight_scenario():
    """Simulate overnight pause scenario from the plan.

    Scenario:
    - Start at 6 PM, work for 2 hours (7200 seconds)
    - Close CLI at 8 PM
    - Reopen at 8 AM (12 hours later)
    - Runtime should still be ~2 hours, not 14 hours
    """
    state = {
        "accumulated_runtime_seconds": 0.0,
        "last_hook_timestamp": 0.0,
    }

    # Simulate 2 hours of work with 1-minute iterations
    base_time = 1000.0
    for i in range(120):  # 120 iterations of 1 minute each = 2 hours
        current_time = base_time + (i * 60)
        update_runtime(state, current_time, gap_threshold=300)

    runtime_before_pause = get_runtime_hours(state)
    assert 1.9 <= runtime_before_pause <= 2.1, f"Expected ~2h before pause, got {runtime_before_pause}"
    print(f"✓ Before overnight pause: runtime={runtime_before_pause:.2f}h")

    # Simulate 12-hour overnight pause (43200 seconds)
    last_time = base_time + (119 * 60)
    morning_time = last_time + 43200  # 12 hours later

    update_runtime(state, morning_time, gap_threshold=300)
    runtime_after_pause = get_runtime_hours(state)

    # Runtime should still be ~2 hours (overnight gap not counted)
    assert 1.9 <= runtime_after_pause <= 2.1, f"Expected ~2h after pause, got {runtime_after_pause}"
    print(f"✓ After overnight pause: runtime={runtime_after_pause:.2f}h (unchanged)")
    print("✓ Overnight scenario validated - gap correctly excluded")


def test_loop_detection():
    """Test loop detection with similarity threshold."""
    # Similar outputs should trigger loop detection
    # detect_loop(current_output, recent_outputs) -> bool
    recent = [
        "Working on task step 1",
        "Working on task step 1",
        "Working on task step 1",
        "Working on task step 1",
    ]
    current = "Working on task step 1"
    is_loop = detect_loop(current, recent)
    assert is_loop is True, "Similar outputs should be detected as loop"
    print("✓ Loop detected with similar outputs")

    # Different outputs should not trigger
    recent_different = [
        "Working on step 1",
        "Completed step 1, starting step 2",
        "Step 2 done, now step 3",
        "Finishing up step 3",
    ]
    current_new = "All steps complete - moving to next phase"
    is_loop = detect_loop(current_new, recent_different)
    assert is_loop is False, "Different outputs should not be loop"
    print("✓ No loop with different outputs")

    # Empty current output
    is_loop = detect_loop("", recent)
    assert is_loop is False
    print("✓ Empty output returns no loop")


def test_extract_section():
    """Test markdown section extraction."""
    content = """# Main Title

## Section One

Content of section one.

## Section Two

Content of section two.
More content here.

## Section Three

Final section.
"""
    # extract_section expects full header with # symbols
    section = extract_section(content, "## Section Two")
    assert "Content of section two" in section
    assert "More content here" in section
    assert "Section One" not in section
    print("✓ Section extraction works")

    # Non-existent section
    missing = extract_section(content, "## Missing Section")
    assert missing == ""
    print("✓ Missing section returns empty string")


def capture_output(func, *args):
    """Capture stdout from a function that prints."""
    f = io.StringIO()
    with redirect_stdout(f):
        func(*args)
    return f.getvalue()


def test_hook_outputs():
    """Test hook output JSON formatting."""
    # allow_stop - prints empty JSON
    output = capture_output(allow_stop, "Task complete")
    parsed = json.loads(output.strip())
    assert parsed == {}
    print("✓ allow_stop format correct (empty JSON)")

    # continue_session - prints decision: block
    output = capture_output(continue_session, "Keep working on task")
    parsed = json.loads(output.strip())
    assert parsed["decision"] == "block"
    assert "Keep working" in parsed["reason"]
    print("✓ continue_session format correct")

    # hard_stop - prints continue: false
    output = capture_output(hard_stop, "Error occurred")
    parsed = json.loads(output.strip())
    assert parsed["continue"] is False
    assert "Error" in parsed["stopReason"]
    print("✓ hard_stop format correct")


def test_constants():
    """Verify utility constants and config-based thresholds."""
    assert WINDOW_SIZE == 5
    print(f"✓ Window size: {WINDOW_SIZE}")

    # Loop threshold is now config-based
    threshold, window = get_loop_detection_config()
    assert 0.7 <= threshold <= 1.0, f"Threshold {threshold} out of reasonable range"
    assert window >= 1, f"Window {window} must be positive"
    print(f"✓ Loop threshold (from config): {threshold}")
    print(f"✓ Window size (from config): {window}")


if __name__ == "__main__":
    print("=" * 60)
    print("Running utils.py unit tests")
    print("=" * 60)

    # Time tracking tests (v7.9.0 dual time tracking)
    print("\n--- Wall-Clock Time ---")
    test_wall_clock_hours()

    print("\n--- Runtime Tracking (v7.9.0) ---")
    test_update_runtime_normal_iteration()
    test_update_runtime_gap_detection()
    test_update_runtime_edge_cases()
    test_get_runtime_hours()
    test_runtime_overnight_scenario()

    print("\n--- Loop Detection ---")
    test_loop_detection()

    print("\n--- Section Extraction ---")
    test_extract_section()

    print("\n--- Hook Outputs ---")
    test_hook_outputs()

    print("\n--- Constants ---")
    test_constants()

    print("=" * 60)
    print("All utils tests passed!")
    print("=" * 60)
