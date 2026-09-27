#!/usr/bin/env python3
"""Managed PreToolUse gate for Claude Code's sandbox escape hatch (``dangerouslyDisableSandbox``).

WHY. Claude Code's kernel sandbox confines an agent command's signals to its own subtree
(macOS Seatbelt ``(allow signal (target same-sandbox))``; Linux bubblewrap ``--unshare-pid``).
That is what would have made the 2026-09-27 incident impossible: ``pkill -f '<pat>' -n``
SIGTERMed every process whose argv contained "-n". But some everyday commands cannot run
sandboxed on macOS (ssh, ps, log, osascript), and ``sandbox.excludedCommands``
does not exempt them there (anthropics/claude-code#53012). So the escape hatch stays open, and
THIS gate is the only way through it: a Bash call carrying ``dangerouslyDisableSandbox: true``
runs unsandboxed only when every command in it is on a small allowlist, and never when any
word in it can signal or stop processes.

HOW IT IS ENFORCED. The installer copies this file to a root-owned directory and registers it
in Claude Code's MANAGED settings, which no user, project or session setting can override or
unregister, and which an agent cannot edit without root.

CONTRACT. Stdin is the PreToolUse JSON. Without the escape flag the gate prints nothing and
exits 0 (the sandbox applies). With it, the gate either prints nothing (escape approved) or
prints a deny decision. It fails CLOSED: anything it cannot parse or classify is denied.

Deliberately stdlib-only and Python 3.9 compatible: it must run on macOS's /usr/bin/python3
(3.9) and Ubuntu's python3, with no user-writable toolchain on its path.
"""

import json
import os
import re
import shlex
import sys

# Any of these words ANYWHERE in the command, including an ssh remote command, a quoted string, or
# a script fed to ssh on stdin, denies the escape: they signal or stop processes.
KILL_WORDS = {"kill", "pkill", "killall", "shutdown", "reboot", "halt", "poweroff"}

# These additionally deny a LOCAL escape (anything but ssh): they would re-exec arbitrary code
# outside the sandbox. They are allowed inside an ssh remote command, which runs on another host.
LOCAL_EXEC_WORDS = {
    "sudo", "doas", "eval", "xargs", "sh", "bash", "zsh", "dash", "ksh", "fish",
    "python", "python3", "perl", "ruby", "node", "bun", "deno",
}

MAX_SSH_STDIN_SCRIPT_BYTES = 256 * 1024

# The directory this gate is installed in; host-ps / host-log must be called from here (root-owned).
# SANDBOX_POLICY_DIR exists only so the test suite and the pilot can run from a checkout: it is
# IGNORED whenever this file is root-owned (the installed copy), so it cannot widen production.
_HERE = os.path.dirname(os.path.abspath(__file__))
_INSTALLED = os.stat(os.path.abspath(__file__)).st_uid == 0
POLICY_DIR = _HERE if _INSTALLED else (os.environ.get("SANDBOX_POLICY_DIR") or _HERE)

# Text filters that may appear AFTER the first pipe segment. No awk/sed (awk system(), sed `e`/`w`).
FILTERS = {"grep", "egrep", "fgrep", "head", "tail", "cut", "sort", "uniq", "wc", "cat", "tr", "jq", "column"}

SSH_DANGEROUS_OPTIONS = re.compile(r"(?i)(proxycommand|localcommand|permitlocalcommand|knownhostscommand|proxyuseFdpass)")
LAUNCHCTL_READ_ONLY = {"list", "print", "print-disabled", "blame"}
LOG_READ_ONLY = {"show", "stream"}
# git is deliberately NOT escapable (changed 2026-09-27). Escaping it never helps: over SSH it
# fails whether or not the flag is set, and over HTTPS it already works inside the sandbox.
# Measured on macOS the same day: through the hatch, `ssh -T git@github.com-<alias>` authenticated,
# while `git ls-remote` and `git push` over the same alias did not, and still carried the sandbox's
# shell-init symptom, so Claude Code kept git sandboxed despite the flag. The proxy itself carries
# no SSH (SOCKS5 to :22 and :443 and HTTP CONNECT to :443 were all refused). Approving a git
# escape only sent sessions down a dead end, so the gate refuses it and names the fix.
GIT_ESCAPE_REFUSAL = (
    "git cannot usefully escape: Claude Code keeps git sandboxed even with dangerouslyDisableSandbox, "
    "and the sandbox proxy carries no SSH, so git over SSH fails either way. Use HTTPS, which works "
    "inside the sandbox: `url.\"https://github.com/\".pushInsteadOf = git@github.com-<account>:` in that "
    "account's gitconfig include, with credentials from Git Credential Manager (never gh in a credential "
    "helper, per the process-storm rule). One-off: git push https://github.com/<owner>/<repo>.git <branch>"
)
OSASCRIPT_FORBIDDEN = re.compile(r"(?i)(\bquit\b|do shell script|doShellScript|keystroke|key code|\bdelete\b|System Events)")


def _basename(word):
    return os.path.basename(word)


def _words_in(token):
    return [w for w in re.split(r"[\s;&|()<>`$'\"=,]+", token) if w]


def _check_ssh_stdin_script(path):
    """A script fed to a remote shell on stdin is scanned for kill-like words before approval."""
    if not path:
        return "missing input file for 'ssh ... <'"
    try:
        with open(os.path.expanduser(path), "rb") as fh:
            data = fh.read(MAX_SSH_STDIN_SCRIPT_BYTES + 1)
    except OSError as exc:
        return "cannot read ssh stdin script " + path + " (" + type(exc).__name__ + ")"
    if len(data) > MAX_SSH_STDIN_SCRIPT_BYTES:
        return "ssh stdin script is too large to inspect"
    text = data.decode("utf-8", "replace")
    for word in _words_in(text):
        if _basename(word) in KILL_WORDS:
            return "ssh stdin script " + path + " contains '" + word + "'"
    return None


def _deny(reason):
    out = {
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "deny",
            "permissionDecisionReason": (
                "[SANDBOX ESCAPE GATE] dangerouslyDisableSandbox refused: " + reason + "\n"
                "Run the command inside the sandbox (drop dangerouslyDisableSandbox). The sandbox confines "
                "signals to your own subtree, so a mistaken kill/pkill cannot reach the operator's apps "
                "(2026-09-27 incident). Escapes are allowed only for: ssh (no kill-like remote command, no "
                "ProxyCommand/LocalCommand), ps, log show|stream, launchctl list|print|print-disabled|blame, "
                "osascript -e without quit/do shell script/System Events, "
                "each optionally piped into grep/head/tail/cut/sort/uniq/wc/cat/tr/jq/column, with output "
                "redirected only to /dev/null. git is not escapable: push over HTTPS inside the sandbox instead. "
                "Policy: plugins/itp-hooks/docs/managed-sandbox-policy.md"
            ),
        }
    }
    sys.stdout.write(json.dumps(out))
    sys.exit(0)


def classify(command):
    """Return None if the unsandboxed run is approved, else a short reason string."""
    if not command or not command.strip():
        return "empty command"
    if "\n" in command or "\r" in command:
        return "multi-line commands cannot be escaped"
    if "$(" in command or "`" in command or "<(" in command or ">(" in command:
        return "command substitution cannot be escaped"
    if "<<" in command:
        return "heredocs cannot be escaped"

    try:
        lexer = shlex.shlex(command, posix=True, punctuation_chars=True)
        lexer.whitespace_split = True
        tokens = list(lexer)
    except ValueError as exc:
        return "unparseable command (" + str(exc) + ")"

    is_ssh = bool(tokens) and _basename(tokens[0]) == "ssh"
    for tok in tokens:
        for word in _words_in(tok):
            base = _basename(word)
            if base in KILL_WORDS:
                return "'" + word + "' may not run outside the sandbox"
            if base in LOCAL_EXEC_WORDS and not is_ssh:
                return "'" + word + "' may not run outside the sandbox"

    segments = [[]]
    i = 0
    while i < len(tokens):
        tok = tokens[i]
        if tok == "|":
            segments.append([])
        elif tok in (";", "&&", "||", "&", "|&", ";;", "(", ")"):
            return "command chaining ('" + tok + "') cannot be escaped"
        elif set(tok) <= set("<>&") and tok:
            if tok.startswith("<"):
                if tok != "<" or not is_ssh or len(segments) != 1:
                    return "input redirection is allowed only as 'ssh ... < script'"
                reason = _check_ssh_stdin_script(tokens[i + 1] if i + 1 < len(tokens) else "")
                if reason:
                    return reason
                i += 2
                continue
            # output redirection: previous fd digit was already appended as a word; drop it
            if segments[-1] and segments[-1][-1].isdigit():
                segments[-1].pop()
            nxt = tokens[i + 1] if i + 1 < len(tokens) else ""
            if tok.endswith("&"):
                if not nxt.isdigit():
                    return "redirection target must be /dev/null or an fd"
            elif nxt != "/dev/null":
                return "output may only be redirected to /dev/null"
            i += 2
            continue
        else:
            segments[-1].append(tok)
        i += 1

    if any(not seg for seg in segments):
        return "empty pipeline segment"

    first, rest = segments[0], segments[1:]
    for seg in rest:
        if _basename(seg[0]) not in FILTERS:
            return "'" + seg[0] + "' is not an allowed pipe filter"

    if re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", first[0]):
        return "environment assignments cannot be escaped"
    prog, args = _basename(first[0]), first[1:]

    if prog == "ssh":
        for a in args:
            if SSH_DANGEROUS_OPTIONS.search(a):
                return "ssh options that execute local commands cannot be escaped"
        return None
    # Claude Code keeps `ps` and `log` sandboxed whatever the escape flag says (measured 2026-09-27),
    # so they escape through root-owned wrappers named host-ps / host-log in the policy directory.
    if prog in ("ps", "log"):
        return ("Claude Code keeps '" + prog + "' sandboxed even with dangerouslyDisableSandbox. Run "
                + os.path.join(POLICY_DIR, "host-" + prog) + " WITHOUT the escape flag instead: it works "
                "inside the sandbox by asking the read-only diagnostics broker on 127.0.0.1")
    if prog in ("host-ps", "host-log"):
        if os.path.dirname(first[0]) != POLICY_DIR:
            return prog + " must be called by its installed path " + os.path.join(POLICY_DIR, prog)
        if prog == "host-log" and not (args and args[0] in LOG_READ_ONLY):
            return "only 'host-log show' and 'host-log stream' may escape"
        return None
    if prog == "launchctl":
        return None if args and args[0] in LAUNCHCTL_READ_ONLY else "only read-only launchctl subcommands may escape"
    if prog == "osascript":
        if not args or len(args) % 2 or any(args[j] != "-e" for j in range(0, len(args), 2)):
            return "osascript may escape only as '-e <script>' pairs"
        if OSASCRIPT_FORBIDDEN.search(command):
            return "osascript that quits apps, runs shell scripts or drives System Events may not escape"
        return None
    if prog == "git":
        return GIT_ESCAPE_REFUSAL
    return "'" + first[0] + "' is not on the escape allowlist"


def main():
    raw = sys.stdin.read()
    try:
        payload = json.loads(raw)
    except ValueError:
        if re.search(r'"dangerouslyDisableSandbox"\s*:\s*true', raw):
            _deny("hook input could not be parsed")
        sys.exit(0)
    if payload.get("tool_name") != "Bash":
        sys.exit(0)
    tool_input = payload.get("tool_input") or {}
    if tool_input.get("dangerouslyDisableSandbox") is not True:
        sys.exit(0)
    reason = classify(tool_input.get("command") or "")
    if reason is not None:
        _deny(reason)
    sys.exit(0)


if __name__ == "__main__":
    try:
        main()
    except SystemExit:
        raise
    except Exception as exc:  # fail CLOSED for an escape request
        _deny("gate error: " + type(exc).__name__)
