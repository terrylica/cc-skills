#!/usr/bin/env python3
"""Install the managed Claude Code sandbox policy on this host (macOS or Linux).

    /usr/bin/python3 install_managed_sandbox_policy.py            # preview (default, changes nothing)
    sudo /usr/bin/python3 install_managed_sandbox_policy.py --apply

What --apply does, idempotently:
  1. Copies sandbox_escape_gate.py and sandbox_policy_session_check.py to a ROOT-OWNED directory
     (/usr/local/libexec/claude-code-sandbox-policy), mode 0755, so no agent can edit them.
  2. Writes Claude Code's MANAGED settings (highest precedence; no user/project/session setting can
     override them): the kernel sandbox enabled for every Bash call, a network/filesystem profile that
     keeps everyday work running, and the two hooks above registered on PreToolUse(Bash)/SessionStart.
     macOS: /Library/Application Support/ClaudeCode/managed-settings.json
     Linux: /etc/claude-code/managed-settings.json
  3. Linux only: installs /etc/apparmor.d/bwrap, which grants user namespaces to /usr/bin/bwrap ONLY.
     Ubuntu 24.04+ sets kernel.apparmor_restrict_unprivileged_userns=1, and without this profile bwrap
     fails ('setting up uid map: Permission denied'), so the Linux sandbox cannot start.

Any file it would replace with different content is first copied to <file>.bak-<UTC stamp>.
Policy and rationale: plugins/itp-hooks/docs/managed-sandbox-policy.md
"""

import argparse
import datetime
import json
import os
import platform
import shutil
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
LIBEXEC = "/usr/local/libexec/claude-code-sandbox-policy"
SCRIPTS = ["sandbox_escape_gate.py", "sandbox_policy_session_check.py"]
# macOS only: the read-only diagnostics broker and its sandbox-side clients (on Linux, ps inside
# bubblewrap's PID namespace sees only the sandbox, and there is no unified log to bridge).
DARWIN_SCRIPTS = ["sandbox_diag_broker.py", "host-ps", "host-log"]
BROKER_LABEL = "com.terryli.sandbox-diag-broker"
BROKER_RUNNER = "sandbox-diag-broker-runner"
BROKER_PLIST = "/Library/LaunchAgents/" + BROKER_LABEL + ".plist"


def broker_plist():
    import plistlib
    return plistlib.dumps({
        "Label": BROKER_LABEL,
        "ProgramArguments": [os.path.join(LIBEXEC, BROKER_RUNNER)],
        "RunAtLoad": True,
        "KeepAlive": True,
        "ProcessType": "Background",
        "LowPriorityIO": True,
        # The broker writes its own size-bounded rotating log under ~/Library/Logs/sandbox-diag-broker/.
        "StandardOutPath": "/dev/null",
        "StandardErrorPath": "/dev/null",
    })
MANAGED = {
    "Darwin": "/Library/Application Support/ClaudeCode/managed-settings.json",
    "Linux": "/etc/claude-code/managed-settings.json",
}
APPARMOR_BWRAP = "/etc/apparmor.d/bwrap"
APPARMOR_BWRAP_PROFILE = """\
# Allow bubblewrap (Claude Code's Linux sandbox, sandbox-runtime) to create user namespaces.
# Scoped to /usr/bin/bwrap; the global unprivileged-userns restriction stays on.
# Installed by cc-skills itp-hooks managed-sandbox-policy.
abi <abi/4.0>,
include <tunables/global>

profile bwrap /usr/bin/bwrap flags=(unconfined) {
  userns,

  include if exists <local/bwrap>
}
"""


def python_for_hooks():
    # The hooks must run under an OS-owned interpreter, never a user-writable one.
    for candidate in ("/usr/bin/python3",):
        if os.path.exists(candidate):
            return candidate
    sys.exit("no /usr/bin/python3; refusing to register hooks under a user-writable interpreter")


def managed_settings(system):
    py = python_for_hooks()
    allow_write = [
        "~", "/tmp", "/private/tmp", "/var/folders",
    ] if system == "Darwin" else ["~", "/tmp", "/var/tmp", "/dev/shm"]
    deny_write = [
        "~/.ssh", "~/.gnupg", "~/.config/age", "~/.claude/settings.json",
    ] + (["~/Library/Keychains", "~/Library/LaunchAgents"] if system == "Darwin" else ["~/.config/systemd"])
    network = {
        # All domains, but only through the sandbox's proxy: the point of this policy is signal
        # confinement, not network lockdown, and a tight allowlist broke everyday work in the pilot.
        "allowedDomains": ["*"],
        "allowLocalBinding": True,
    }
    if system == "Darwin":
        # Go/Security.framework TLS verification (gh, many CLIs) needs trustd; measured in the pilot.
        network["allowMachLookup"] = [
            "com.apple.trustd.agent", "com.apple.trustd", "com.apple.SecurityServer", "com.apple.securityd.xpc",
        ]
    return {
        "sandbox": {
            "enabled": True,
            "autoAllowBashIfSandboxed": True,
            # The escape hatch stays open, but ONLY through sandbox_escape_gate.py (below).
            "allowUnsandboxedCommands": True,
            "filesystem": {"allowWrite": allow_write, "denyWrite": deny_write},
            "network": network,
        },
        "hooks": {
            "PreToolUse": [{
                "matcher": "Bash",
                "hooks": [{
                    "type": "command",
                    "command": py + " " + os.path.join(LIBEXEC, "sandbox_escape_gate.py"),
                    "timeout": 10,
                }],
            }],
            "SessionStart": [{
                "hooks": [{
                    "type": "command",
                    "command": py + " " + os.path.join(LIBEXEC, "sandbox_policy_session_check.py"),
                    "timeout": 15,
                }],
            }],
        },
    }


def stamp():
    return datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%SZ")


def plan_write(path, content, mode, actions):
    old = None
    if os.path.exists(path):
        with open(path, "rb") as fh:
            old = fh.read()
    if old == content:
        actions.append(("unchanged", path, None, mode))
    else:
        actions.append(("write", path, content, mode))


def install_broker_runner_and_load():
    """Build + ad-hoc sign the runner shim (launchd-runner policy), then (re)load the broker agent
    into the invoking user's GUI domain."""
    runner = os.path.join(LIBEXEC, BROKER_RUNNER)
    src = os.path.join(HERE, "runners", "SandboxDiagBrokerRunner.swift")
    tmp = runner + ".build"
    subprocess.run(["/usr/bin/swiftc", "-O", "-o", tmp, src], check=True)
    subprocess.run(["/usr/bin/codesign", "-s", "-", "-f", "-i", "com.terryli." + BROKER_RUNNER, tmp], check=True)
    os.chown(tmp, 0, 0)
    os.chmod(tmp, 0o755)
    os.replace(tmp, runner)
    print("built     " + runner + " (signed com.terryli." + BROKER_RUNNER + ")")
    uid = os.environ.get("SUDO_UID")
    if not uid:
        print("SUDO_UID unset: load it yourself with launchctl bootstrap gui/$UID " + BROKER_PLIST)
        return
    domain = "gui/" + uid
    subprocess.run(["/bin/launchctl", "bootout", domain + "/" + BROKER_LABEL], check=False,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    subprocess.run(["/bin/launchctl", "bootstrap", domain, BROKER_PLIST], check=True)
    print("loaded    " + domain + "/" + BROKER_LABEL)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--apply", action="store_true", help="make the changes (needs root); default is a preview")
    args = ap.parse_args()

    system = platform.system()
    if system not in MANAGED:
        sys.exit("unsupported platform: " + system)

    actions = []
    for name in SCRIPTS + (DARWIN_SCRIPTS if system == "Darwin" else []):
        with open(os.path.join(HERE, name), "rb") as fh:
            plan_write(os.path.join(LIBEXEC, name), fh.read(), 0o755, actions)
    if system == "Darwin":
        plan_write(BROKER_PLIST, broker_plist(), 0o644, actions)
    settings = managed_settings(system)
    blob = (json.dumps(settings, indent=2) + "\n").encode()
    json.loads(blob)  # validate before anything is written
    plan_write(MANAGED[system], blob, 0o644, actions)
    if system == "Linux":
        plan_write(APPARMOR_BWRAP, APPARMOR_BWRAP_PROFILE.encode(), 0o644, actions)

    for kind, path, _content, mode in actions:
        print("%-9s %s (mode %o)" % (kind, path, mode))
    if not args.apply:
        print("\npreview only; re-run with sudo and --apply to make these changes")
        print("\nmanaged settings that would be written:\n" + blob.decode())
        return
    if os.geteuid() != 0:
        sys.exit("--apply needs root: sudo /usr/bin/python3 " + os.path.abspath(__file__) + " --apply")

    ts = stamp()
    for kind, path, content, mode in actions:
        if kind != "write":
            continue
        os.makedirs(os.path.dirname(path), mode=0o755, exist_ok=True)
        if os.path.exists(path):
            backup = path + ".bak-" + ts
            shutil.copy2(path, backup)
            print("backup    " + backup)
        tmp = path + ".tmp-" + ts
        with open(tmp, "wb") as fh:
            fh.write(content)
            fh.flush()
            os.fsync(fh.fileno())
        os.chown(tmp, 0, 0)
        os.chmod(tmp, mode)
        os.replace(tmp, path)
        print("wrote     " + path)

    if system == "Linux":
        subprocess.run(["apparmor_parser", "-r", APPARMOR_BWRAP], check=True)
        print("loaded    AppArmor profile bwrap")

    if system == "Darwin":
        install_broker_runner_and_load()

    check = subprocess.run([python_for_hooks(), os.path.join(LIBEXEC, "sandbox_policy_session_check.py")],
                           capture_output=True, text=True, timeout=30, check=True)
    print("session check: " + ("OK" if not check.stdout.strip() else check.stdout.strip()))


if __name__ == "__main__":
    main()
