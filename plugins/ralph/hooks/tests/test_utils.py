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
    LOOP_THRESHOLD,
    WINDOW_SIZE,
    allow_stop,
    continue_session,
    detect_loop,
    extract_section,
    get_elapsed_hours,
    hard_stop,
)


def test_elapsed_hours():
    """Test elapsed time calculation from timestamp file."""
    with tempfile.TemporaryDirectory() as tmp:
        tmp_dir = Path(tmp)

        # Create .claude directory with loop-start-timestamp
        claude_dir = tmp_dir / ".claude"
        claude_dir.mkdir()
        timestamp_file = claude_dir / "loop-start-timestamp"

        # Set timestamp to 2 hours ago
        two_hours_ago = int(time.time()) - (2 * 3600)
        timestamp_file.write_text(str(two_hours_ago))

        elapsed = get_elapsed_hours("test-session", str(tmp_dir))
        assert 1.9 <= elapsed <= 2.1, f"Expected ~2 hours, got {elapsed}"
        print(f"✓ Elapsed hours: {elapsed:.2f}")

    # No timestamp file - should return 0
    elapsed_no_file = get_elapsed_hours("nonexistent", "/tmp/nonexistent")
    assert elapsed_no_file == 0.0
    print("✓ Missing timestamp returns 0.0")


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
    """Verify utility constants."""
    assert WINDOW_SIZE == 5
    assert LOOP_THRESHOLD == 0.9
    print(f"✓ Window size: {WINDOW_SIZE}")
    print(f"✓ Loop threshold: {LOOP_THRESHOLD}")


if __name__ == "__main__":
    print("=" * 60)
    print("Running utils.py unit tests")
    print("=" * 60)

    test_elapsed_hours()
    test_loop_detection()
    test_extract_section()
    test_hook_outputs()
    test_constants()

    print("=" * 60)
    print("All utils tests passed!")
    print("=" * 60)
