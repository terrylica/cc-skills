#!/usr/bin/env python3
"""Managed SessionStart check: is the kernel sandbox usable, and is the escape gate intact?

Registered in Claude Code's MANAGED settings by install_managed_sandbox_policy.py, next to
sandbox_escape_gate.py. It never blocks a session; it tells the agent and the operator, at the
start of every session, when the protection the policy promises is not actually there:

  - macOS: sandbox-exec can apply a trivial profile (Seatbelt available);
  - Linux: bubblewrap can create a PID namespace (on Ubuntu 24.04+ this needs the
    /etc/apparmor.d/bwrap userns profile; without it bwrap fails with 'setting up uid map');
  - the gate script exists, is owned by root and is not writable by group or others.

Stdlib-only, Python 3.9 compatible, for the same reason as the gate (OS-owned interpreter).
"""

import json
import os
import platform
import stat
import subprocess
import sys

GATE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "sandbox_escape_gate.py")


def _probe_kernel_sandbox():
    system = platform.system()
    if system == "Darwin":
        cmd = ["/usr/bin/sandbox-exec", "-p", "(version 1)(allow default)", "/usr/bin/true"]
        what = "Seatbelt (sandbox-exec)"
    elif system == "Linux":
        cmd = ["bwrap", "--ro-bind", "/", "/", "--dev", "/dev", "--proc", "/proc",
               "--unshare-pid", "--die-with-parent", "/bin/true"]
        what = "bubblewrap PID namespace"
    else:
        return "unsupported platform " + system
    try:
        p = subprocess.run(cmd, capture_output=True, text=True, timeout=10, check=False)
    except (OSError, subprocess.TimeoutExpired) as exc:
        return what + " unavailable: " + type(exc).__name__
    if p.returncode != 0:
        hint = ""
        if system == "Linux" and "uid map" in p.stderr:
            hint = " (Ubuntu AppArmor userns restriction: install /etc/apparmor.d/bwrap)"
        return what + " failed: " + (p.stderr.strip().splitlines() or ["rc=" + str(p.returncode)])[-1] + hint
    return None


def _check_gate():
    try:
        st = os.stat(GATE)
    except OSError:
        return "escape gate missing at " + GATE
    if st.st_uid != 0:
        return "escape gate is not root-owned: " + GATE
    if st.st_mode & (stat.S_IWGRP | stat.S_IWOTH):
        return "escape gate is group/world-writable: " + GATE
    return None


def _check_broker():
    """macOS only: the read-only diagnostics broker that serves host-ps / host-log must answer."""
    if platform.system() != "Darwin":
        return None
    import urllib.error
    import urllib.request
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
    try:
        with opener.open("http://127.0.0.1:8797/healthz", timeout=3) as r:
            return None if r.status == 200 else "diagnostics broker unhealthy (HTTP " + str(r.status) + ")"
    except (urllib.error.URLError, OSError) as exc:
        return "diagnostics broker not answering on 127.0.0.1:8797 (" + type(exc).__name__ + "); host-ps/host-log unavailable"


def main():
    problems = [p for p in (_probe_kernel_sandbox(), _check_gate(), _check_broker()) if p]
    if not problems:
        sys.exit(0)
    msg = ("SANDBOX POLICY DEGRADED: " + "; ".join(problems) + ". Agent commands may be able to signal "
           "processes outside their own subtree (the 2026-09-27 pkill incident). Tell the operator before "
           "running any kill/pkill/killall. Fix: sudo /usr/bin/python3 install_managed_sandbox_policy.py --apply "
           "(plugins/itp-hooks/managed-sandbox-policy).")
    sys.stdout.write(json.dumps({
        "systemMessage": msg,
        "hookSpecificOutput": {"hookEventName": "SessionStart", "additionalContext": msg},
    }))
    sys.exit(0)


if __name__ == "__main__":
    main()
