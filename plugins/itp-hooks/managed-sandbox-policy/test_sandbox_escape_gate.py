"""Tests for sandbox_escape_gate.py. Run with the SAME interpreters the gate targets:

    /usr/bin/python3 -m unittest -v test_sandbox_escape_gate      (macOS, 3.9)
    python3 -m unittest -v test_sandbox_escape_gate               (Ubuntu)

The hook is exercised END TO END through a subprocess speaking the real stdin/stdout protocol,
so wiring mistakes (wrong flag check, fail-open on error) are caught, not just the classifier.
"""

import json
import os
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
GATE = os.path.join(HERE, "sandbox_escape_gate.py")


def run(command, escape=True, tool="Bash", raw=None):
    payload = raw if raw is not None else json.dumps(
        {"tool_name": tool, "tool_input": {"command": command, "dangerouslyDisableSandbox": escape}}
    )
    # check=True: the gate must always exit 0 (decisions travel on stdout); any other status is a bug.
    p = subprocess.run([sys.executable, GATE], input=payload, capture_output=True, text=True, timeout=20, check=True)
    if not p.stdout.strip():
        return "pass"
    return json.loads(p.stdout)["hookSpecificOutput"]["permissionDecision"]


class NoEscapeRequested(unittest.TestCase):
    def test_sandboxed_calls_are_untouched(self):
        # Without the flag the sandbox applies; the gate must stay silent even for kill.
        self.assertEqual(run("pkill -f 'bun server.ts' -n", escape=False), "pass")
        self.assertEqual(run("kill -9 1", escape=False), "pass")

    def test_other_tools_untouched(self):
        self.assertEqual(run("kill 1", tool="Write"), "pass")


class DeniesTheIncidentAndItsCousins(unittest.TestCase):
    def test_incident_command(self):
        self.assertEqual(run("pkill -f 'bun server.ts --build build-preview' -n 2>/dev/null; true"), "deny")

    def test_kill_family_anywhere(self):
        for cmd in ["kill -9 123", "killall Finder", "pkill -n -f foo", "ps aux | grep x | kill",
                    "ssh bigblack 'pkill -f foo'", "ssh mini sudo shutdown -h now", "ssh host reboot"]:
            self.assertEqual(run(cmd), "deny", cmd)

    def test_kill_via_ps_substitution(self):
        self.assertEqual(run("kill $(ps -Ao pid,comm | grep x)"), "deny")

    def test_local_reexec_and_chaining(self):
        for cmd in ["bash -c 'ls'", "sh -c ls", "python3 x.py", "xargs echo", "sudo ps",
                    "ssh h true; ls", "ssh h true && ls", "ssh h true || true", "ssh h true &", "git status",
                    "git -c core.sshCommand=x fetch", "launchctl bootout gui/501/x", "launchctl kill TERM gui/501/x",
                    "GIT_SSH_COMMAND=evil git fetch", "rm -rf /tmp/x", "ssh h true > /tmp/out",
                    "ssh h true | awk '{print}'", "ssh h true | sed -n 1p", "echo hi"]:
            self.assertEqual(run(cmd), "deny", cmd)

    def test_ps_and_log_are_redirected_to_wrappers(self):
        # Claude Code keeps these sandboxed whatever the flag says; the deny names the wrapper.
        for cmd in ["ps -Ao pid,command", "/usr/bin/log show --last 1m"]:
            self.assertEqual(run(cmd), "deny", cmd)

    def test_wrappers_only_from_policy_dir_and_read_only(self):
        for cmd in ["/tmp/host-ps aux", "host-ps aux", HERE + "/host-log erase --all", HERE + "/host-log config"]:
            self.assertEqual(run(cmd), "deny", cmd)

    def test_osascript_rules(self):
        for cmd in ["osascript -e 'quit app \"Synergy\"'", "osascript -e 'do shell script \"ls\"'",
                    "osascript -e 'tell application \"System Events\" to keystroke \"q\"'",
                    "osascript script.scpt"]:
            self.assertEqual(run(cmd), "deny", cmd)

    def test_ssh_local_command_options(self):
        self.assertEqual(run("ssh -o ProxyCommand='nc %h %p' host true"), "deny")
        self.assertEqual(run("ssh -o LocalCommand=touch\\ x -o PermitLocalCommand=yes host true"), "deny")

    def test_structure_that_cannot_be_inspected(self):
        for cmd in ["ps\nkill 1", "cat <<EOF\nx\nEOF", "diff <(ps) <(ps)", "echo `id`", ""]:
            self.assertEqual(run(cmd), "deny", repr(cmd))

    def test_fails_closed_on_garbage_with_escape_flag(self):
        self.assertEqual(run(None, raw='{"tool_name":"Bash","tool_input":{"dangerouslyDisableSandbox": true, '), "deny")

    def test_ssh_stdin_script_with_kill_is_denied(self):
        with tempfile.NamedTemporaryFile("w", suffix=".sh", delete=False) as fh:
            fh.write("#!/bin/bash\nps -ef\nkill -9 1097\n")
        try:
            self.assertEqual(run("ssh bigblack 'bash -s' < " + fh.name), "deny")
        finally:
            os.unlink(fh.name)

    def test_ssh_stdin_missing_file(self):
        self.assertEqual(run("ssh bigblack 'bash -s' < /nonexistent/x.sh"), "deny")


GIT_NETWORK_ESCAPES = [
    "git push origin main",
    "git -C /Users/terryli/eon/cc-skills fetch --dry-run origin",
    "git clone git@github.com:terrylica/cc-skills.git /tmp/x",
    "git ls-remote origin HEAD 2>/dev/null",
]
IS_MACOS = sys.platform == "darwin"


class GitEscapesPerPlatform(unittest.TestCase):
    """2026-09-27, measured on macOS only: git escapes were approved but never worked there. Claude
    Code kept git sandboxed despite the flag, and the proxy carries no SSH, so on macOS the gate now
    refuses them and names HTTPS as the fix. Linux was not measured and keeps the previous rule."""

    @unittest.skipUnless(IS_MACOS, "macOS-only rule")
    def test_git_network_escapes_are_refused_on_macos(self):
        for cmd in GIT_NETWORK_ESCAPES:
            self.assertEqual(run(cmd), "deny", cmd)

    @unittest.skipIf(IS_MACOS, "Linux keeps the previous allowlist")
    def test_git_network_escapes_still_allowed_on_linux(self):
        for cmd in GIT_NETWORK_ESCAPES:
            self.assertEqual(run(cmd), "pass", cmd)

    @unittest.skipUnless(IS_MACOS, "macOS-only rule")
    def test_refusal_names_the_https_fix(self):
        payload = json.dumps({"tool_name": "Bash", "tool_input": {"command": "git push origin main", "dangerouslyDisableSandbox": True}})
        p = subprocess.run([sys.executable, GATE], input=payload, capture_output=True, text=True, timeout=20, check=True)
        reason = json.loads(p.stdout)["hookSpecificOutput"]["permissionDecisionReason"]
        for needle in ("HTTPS", "pushInsteadOf", "never gh in a credential"):
            self.assertIn(needle, reason)

    def test_sandboxed_git_is_untouched(self):
        # Without the flag the gate stays silent: HTTPS git runs inside the sandbox.
        self.assertEqual(run("git push https://github.com/terrylica/cc-skills.git main", escape=False), "pass")


class AllowsTheEverydayEscapes(unittest.TestCase):
    def test_allowed(self):
        for cmd in [
            "ssh -o BatchMode=yes -o ConnectTimeout=8 bigblack 'uptime; nvidia-smi'",
            "ssh bigblack true",
            HERE + "/host-ps -Ao pid,ppid,lstart,command",
            HERE + "/host-ps -Ao pid,command | grep -i synergy | head -5",
            HERE + "/host-log show --last 2m --style compact 2>/dev/null | tail -20",
            HERE + "/host-log stream --predicate 'process == \"x\"'",
            "launchctl list com.terryli.iterm2-autosnapshot",
            "launchctl print gui/501/com.cpc.nas-tunnel 2>&1 | head -30",
            "/usr/bin/osascript -e 'tell application \"Finder\" to get name of front window'",
        ]:
            self.assertEqual(run(cmd), "pass", cmd)

    def test_ssh_stdin_readonly_script_is_allowed(self):
        with tempfile.NamedTemporaryFile("w", suffix=".sh", delete=False) as fh:
            fh.write("#!/bin/bash\nset -u\nuptime\nsystemctl is-active display-manager\n")
        try:
            self.assertEqual(run("ssh -o BatchMode=yes bigblack 'bash -s' < " + fh.name), "pass")
        finally:
            os.unlink(fh.name)


if __name__ == "__main__":
    unittest.main()
