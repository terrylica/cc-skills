# Test fixture: GOOD Python code (should pass)
import subprocess
import logging

logger = logging.getLogger(__name__)

def good_function():
    try:
        risky_operation()
    except ValueError as e:
        logger.error("Operation failed: %s", e)
        raise

def good_subprocess():
    subprocess.run(["ls", "-la"], check=True)
