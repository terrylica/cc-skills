# Test fixture: bare except (E722)
def bad_function():
    try:
        risky_operation()
    except:
        pass  # Silent failure!
