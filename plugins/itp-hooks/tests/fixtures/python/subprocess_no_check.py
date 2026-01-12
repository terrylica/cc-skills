# Test fixture: subprocess.run without check=True (PLW1510)
import subprocess

def bad_function():
    # Silent failure - exit code ignored!
    subprocess.run(["ls", "-la"])
    subprocess.run(["rm", "nonexistent"], capture_output=True)
