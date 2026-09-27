#!/usr/bin/env python3
"""Managed PreToolUse gate for Claude Code's sandbox escape hatch (``dangerouslyDisableSandbox``).

WHY. Claude Code's kernel sandbox confines an agent command's signals to its own subtree
(macOS Seatbelt ``(allow signal (target same-sandbox))``; Linux bubblewrap ``--unshare-pid``).
That is what would have made the 2026-09-27 incident impossible: ``pkill -f '<pat>' -n``
SIGTERMed every process whose argv contained "-n". But some everyday commands cannot run
sandboxed on macOS (ssh, ps, log, osascript, git over ssh), and ``sandbox.excludedCommands``
does not exempt them there (anthropics/claude-code#53012). So the escape hatch stays open, and
THIS gate is the only way through it: a Bash call carrying ``dangerouslyDisableSandbox: true``
runs unsandboxed only when every command in it is on a small allowlist, and never when any
word in it can signal or stop processes.

CONFIGURED MOON TASKS (operator decision, 2026-09-27). A repository's release task runs its full
gate and then semantic-release, whose git push goes over SSH, which cannot work sandboxed. So the
operator may name, per checkout, the moon tasks that may escape, in escape-allowed-moon-tasks.json
beside this file (written by install_managed_sandbox_policy.py --allow-moon-task). Exactly two
shapes are accepted, 'moon run <task> --concurrency <1-4>' and 'cd <checkout> && moon run <task>
--concurrency <1-4>', only in that checkout or a linked git worktree of it, and only when its
tree is clean, so that nothing uncommitted runs unsandboxed. See _classify_moon.

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
import stat
import subprocess
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
GIT_NETWORK_ONLY = {"push", "fetch", "pull", "clone", "ls-remote"}
LIBEXEC_HINT = "/usr/local/libexec/claude-code-sandbox-policy/"

# ── Configured moon tasks ────────────────────────────────────────────────────────────────────────
MOON_CONFIG_NAME = "escape-allowed-moon-tasks.json"
MOON_CONFIG_HOW = ("the operator names them with: sudo /usr/bin/python3 install_managed_sandbox_policy.py "
                   "--apply --allow-moon-task ROOT=TASK[,TASK...]")
MAX_MOON_CONFIG_BYTES = 64 * 1024
MAX_GIT_POINTER_BYTES = 4096
MOON_TASK = re.compile(r"[a-z0-9-]+:[a-z0-9-]+")   # always fullmatch: '$' would accept a trailing newline
MOON_CONCURRENCY = re.compile(r"[1-4]")            # bounded parallelism (process-storm rules)
# A path typed on the command line must contain nothing a shell could expand ($, ~, globs, braces,
# quotes), so the directory checked here is the directory the shell will cd into.
SAFE_PATH = re.compile(r"/[A-Za-z0-9._/+@-]*")
MOON_SHAPE = ("moon may escape only as 'moon run <task> --concurrency <1-4>' or 'cd <checkout> && moon run "
              "<task> --concurrency <1-4>' ('--concurrency=N' also works), with nothing else on the line: no "
              "other flags or arguments, pipes, redirections, environment assignments or chaining")
# The owner the config must have when the ownership check is on. For the installed gate it is root;
# a checkout copy skips the check unless the test suite sets this seam, which is ignored once installed.
CONFIG_OWNER_SEAM = "SANDBOX_GATE_CONFIG_OWNER_UID"

# The clean-tree check runs git OUTSIDE the sandbox (hooks are not sandboxed), in a checkout that any
# sandboxed process may write, so git must not execute anything that checkout configures. Measured
# 2026-09-27 on git 2.50.1: a plain `git status` ran an agent-writable .git/hooks/post-index-change
# (it rewrote the index), `git ls-files` ran a core.fsmonitor hook from .git/config, and a clean filter
# from .git/config plus info/attributes ran even with fsmonitor and hooks off. Hence: an absolute git,
# a scrubbed environment (no system or global config), --no-optional-locks (never write the index),
# hooks and fsmonitor forced off, and a refusal when the repo's config defines a filter (below). The
# untracked cache and relaxed stat checks are forced off because either can hide a changed file.
GIT = "/usr/bin/git"
GIT_ENV = {"PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "GIT_CONFIG_NOSYSTEM": "1", "GIT_CONFIG_GLOBAL": "/dev/null"}
GIT_CONFIG_OVERRIDES = ["-c", "core.fsmonitor=false", "-c", "core.hooksPath=/dev/null", "-c", "core.untrackedCache=false",
                        "-c", "core.checkStat=default", "-c", "core.trustctime=true"]
# A timed-out PreToolUse command hook does NOT block the tool call (Claude Code hooks docs, "Timeouts"),
# so these must sum to well under the timeout the installer registers the gate with (30 s).
GIT_CONFIG_TIMEOUT, GIT_LS_FILES_TIMEOUT, GIT_STATUS_TIMEOUT = 5, 5, 10


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
                "git [-C dir] push|fetch|pull|clone|ls-remote (escaped, git over SSH reaches the remote; "
                "sandboxed, it fails at the sandbox proxy), "
                "each optionally piped into grep/head/tail/cut/sort/uniq/wc/cat/tr/jq/column, with output "
                "redirected only to /dev/null; and 'moon run <task> --concurrency <1-4>', alone or as "
                "'cd <checkout> && moon run ...', for a task the operator configured for that checkout (or a "
                "linked git worktree of it) whose tree is clean, with nothing piped or redirected. "
                "Apple Notes drafts: host-notes, without the flag. "
                "Policy: plugins/itp-hooks/docs/managed-sandbox-policy.md"
            ),
        }
    }
    sys.stdout.write(json.dumps(out))
    sys.exit(0)


def _required_config_owner():
    """The uid that must own the moon-task config, or None when the ownership check is off."""
    if _INSTALLED:
        return 0
    seam = os.environ.get(CONFIG_OWNER_SEAM)
    if seam is None:
        return None
    return int(seam) if re.fullmatch(r"[0-9]{1,10}", seam) else -1   # -1 matches no file: deny


def _read_small_file(path, limit):
    """Bytes of a regular, non-symlink file of at most `limit` bytes, plus its stat; raises OSError or
    ValueError otherwise. O_NOFOLLOW + fstat check the file that is actually read, with no race."""
    fd = os.open(path, os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0) | getattr(os, "O_NONBLOCK", 0))
    try:
        st = os.fstat(fd)
        if not stat.S_ISREG(st.st_mode):
            raise ValueError("not a regular file")
        chunks, size = [], 0
        for chunk in iter(lambda: os.read(fd, 65536), b""):
            size += len(chunk)
            if size > limit:
                raise ValueError("larger than " + str(limit) + " bytes")
            chunks.append(chunk)
    finally:
        os.close(fd)
    return b"".join(chunks), st


def _parse_moon_config(cfg):
    """{root: [task, ...]} from the parsed JSON, or None if it is not exactly the expected shape."""
    if not isinstance(cfg, dict) or set(cfg) != {"version", "repos"}:
        return None
    if type(cfg["version"]) is not int or cfg["version"] != 1 or not isinstance(cfg["repos"], list):
        return None
    repos = {}
    for entry in cfg["repos"]:
        if not isinstance(entry, dict) or set(entry) != {"root", "tasks"}:
            return None
        root, tasks = entry["root"], entry["tasks"]
        if not isinstance(root, str) or not os.path.isabs(root) or os.path.normpath(root) != root:
            return None
        if not isinstance(tasks, list) or not tasks:
            return None
        for task in tasks:
            if not isinstance(task, str) or not MOON_TASK.fullmatch(task):
                return None
        listed = repos.setdefault(root, [])
        listed.extend(t for t in tasks if t not in listed)
    return repos


def _load_moon_config():
    """({root: [task, ...]}, None), or (None, why no moon task may escape). Fails closed."""
    path = os.path.join(POLICY_DIR, MOON_CONFIG_NAME)
    try:
        data, st = _read_small_file(path, MAX_MOON_CONFIG_BYTES)
    except FileNotFoundError:
        return None, "no moon tasks are configured (" + path + " does not exist); " + MOON_CONFIG_HOW
    except (OSError, ValueError) as exc:
        detail = (exc.strerror or type(exc).__name__) if isinstance(exc, OSError) else str(exc)
        return None, "cannot use " + path + " (" + detail + "), so no moon task may escape; " + MOON_CONFIG_HOW
    owner = _required_config_owner()
    if owner is not None and st.st_uid != owner:
        return None, (path + " is not owned by " + ("root" if owner == 0 else "uid " + str(owner))
                      + ", so it is ignored and no moon task may escape; " + MOON_CONFIG_HOW)
    if owner is not None and st.st_mode & (stat.S_IWGRP | stat.S_IWOTH):
        return None, (path + " is group- or world-writable, so it is ignored and no moon task may escape; "
                      + MOON_CONFIG_HOW)
    try:
        repos = _parse_moon_config(json.loads(data.decode("utf-8")))
    except ValueError:
        repos = None
    if repos is None:
        return None, (path + ' is malformed (expected {"version": 1, "repos": [{"root": "/abs/checkout", '
                      '"tasks": ["project:task"]}]}), so no moon task may escape; ' + MOON_CONFIG_HOW)
    return repos, None


def _real_directory(path, what):
    """(path, None) when `path` is an existing directory named by its real path, else (None, why).

    A symlink or '..' in the path is refused rather than resolved: the check here and the shell's cd
    happen at different moments, and a symlink could be re-pointed at another checkout in between."""
    if not isinstance(path, str) or not os.path.isabs(path):
        return None, what + " " + repr(path) + " is not an absolute path"
    given = path.rstrip("/") or "/"
    real = os.path.realpath(given)
    if real != given:
        return None, (what + " " + given + " is not its real path (" + real + "): a symlink or '..' could "
                      "point it elsewhere between this check and the run, so name the checkout by its real path")
    if not os.path.isdir(real):
        return None, what + " " + real + " is not a directory"
    return real, None


def _read_git_pointer(path):
    """The stripped text of a small .git or gitdir pointer file, or None when it is anything else."""
    try:
        data, _ = _read_small_file(path, MAX_GIT_POINTER_BYTES)
        return data.decode("utf-8").strip() or None
    except (OSError, ValueError):
        return None


def _has_own_git_dir(root):
    git_dir = os.path.join(root, ".git")
    return os.path.isdir(git_dir) and not os.path.islink(git_dir)


def _is_linked_worktree_of(d, root):
    """True when `d` is a linked git worktree of `root`, read from the pointer files only: d/.git is a
    file 'gitdir: <root>/.git/worktrees/<name>', that directory exists, and its 'gitdir' file points
    back to d/.git. Relative pointers (worktree.useRelativePaths) resolve from the file's directory."""
    git_file = os.path.join(d, ".git")
    if os.path.islink(git_file) or not _has_own_git_dir(root):
        return False
    text = _read_git_pointer(git_file)
    if text is None or not text.startswith("gitdir: "):
        return False
    admin = os.path.realpath(os.path.join(d, text[len("gitdir: "):]))
    if os.path.dirname(admin) != os.path.join(root, ".git", "worktrees") or not os.path.isdir(admin):
        return False
    back = _read_git_pointer(os.path.join(admin, "gitdir"))
    return back is not None and os.path.realpath(os.path.join(admin, back)) == git_file


def _checkout_root(d, repos):
    """The configured root that `d` is, or is a linked worktree of; None otherwise. Subdirectories of
    a checkout do not count: moon would find the workspace from one, but the rule names checkouts."""
    for root in repos:
        if d == root and _has_own_git_dir(root):
            return root
    for root in repos:
        if _is_linked_worktree_of(d, root):
            return root
    return None


def _git(d, args, timeout):
    """Run /usr/bin/git on checkout `d` with the fixed safe options; never a shell."""
    return subprocess.run([GIT, "--no-optional-locks", "-C", d] + GIT_CONFIG_OVERRIDES + args, env=GIT_ENV,
                          stdin=subprocess.DEVNULL, capture_output=True, timeout=timeout, check=False)


def _tree_problem(d):
    """None when checkout `d` is clean, else why the escape is refused.

    WHY. An escaped task runs outside the sandbox, so it may run committed code only: a change that
    is not committed leaves no trail, and a clean tree is the cheapest proof that nothing is pending.
    Anything unexpected, a non-zero exit, a timeout or an exception, is a refusal ("cannot verify")."""
    cannot = "cannot verify a clean tree in " + d + " ("
    try:
        # 1. Config that would make git run code (a filter driver) or check another directory.
        p = _git(d, ["config", "--get-regexp", r"^(filter\..*|core\.worktree)$"], GIT_CONFIG_TIMEOUT)
        if p.returncode == 0:
            key = p.stdout.decode("utf-8", "replace").split(None, 1)[0]
            return ("the git config of " + d + " sets '" + key + "': git would run a filter outside the sandbox "
                    "while checking the tree, or check a different directory, so it cannot be verified; remove it")
        if p.returncode != 1:
            return cannot + "git config exited " + str(p.returncode) + ")"
        # 2. Index entries git status does not look at, and submodules, which it would have to enter.
        p = _git(d, ["ls-files", "-v", "-s", "-z"], GIT_LS_FILES_TIMEOUT)
        if p.returncode != 0:
            return cannot + "git ls-files exited " + str(p.returncode) + ")"
        for entry in p.stdout.split(b"\0"):
            if not entry:
                continue
            fields = entry.split(b"\t", 1)[0].split(b" ")
            if entry[:1].islower() or entry[:1] == b"S":
                return ("files in " + d + " are marked assume-unchanged or skip-worktree, which hides their "
                        "changes from git status; clear the flags (git update-index --no-assume-unchanged / "
                        "--no-skip-worktree, or disable sparse checkout) and retry")
            if len(fields) > 1 and fields[1] == b"160000":
                return "the checkout " + d + " has submodules, whose trees this check does not enter, so it cannot be verified"
        # 3. The tree itself.
        p = _git(d, ["status", "--porcelain", "--untracked-files=normal", "--ignore-submodules=all"],
                 GIT_STATUS_TIMEOUT)
    except subprocess.TimeoutExpired as exc:
        return cannot + "git timed out after " + str(exc.timeout) + " s)"
    except (OSError, ValueError, IndexError) as exc:
        return cannot + GIT + ": " + type(exc).__name__ + ")"
    if p.returncode != 0:
        err = p.stderr.decode("utf-8", "replace").strip().splitlines()
        return cannot + "git status exited " + str(p.returncode) + (": " + err[-1] if err else "") + ")"
    lines = p.stdout.decode("utf-8", "replace").splitlines()
    if lines:
        shown = "; ".join(line.strip() for line in lines[:3]) + ("; ..." if len(lines) > 3 else "")
        return ("uncommitted changes in " + d + " (" + shown + "): only committed code may run outside the "
                "sandbox, so commit or remove them, then retry")
    return None


def _moon_attempt(tokens):
    """(cd target or None, separator or None, moon argv) when the command is an attempt at a moon
    run, else None. Only these two leading shapes route here; anything else keeps the general rules."""
    if tokens and _basename(tokens[0]) == "moon":
        return None, None, tokens
    if len(tokens) >= 4 and tokens[0] == "cd" and _basename(tokens[3]) == "moon":
        return tokens[1], tokens[2], tokens[3:]
    return None


def _classify_moon(cd_target, separator, argv, cwd):
    """None if this moon run may escape, else the reason. The checks run cheapest first; the git
    checks run last, and only for a configured task in a configured checkout."""
    if cd_target is not None and separator != "&&":
        return MOON_SHAPE
    moon, rest = argv[0], argv[1:]
    if moon != "moon" and not SAFE_PATH.fullmatch(moon):
        return "moon must be called as 'moon' or by an absolute path ending in /moon"
    if len(rest) == 4 and rest[0] == "run" and rest[2] == "--concurrency":
        task, concurrency = rest[1], rest[3]
    elif len(rest) == 3 and rest[0] == "run" and rest[2].startswith("--concurrency="):
        task, concurrency = rest[1], rest[2][len("--concurrency="):]
    else:
        return MOON_SHAPE
    if not MOON_TASK.fullmatch(task):
        return "'" + task + "' is not a moon task name of the form project:task"
    if not MOON_CONCURRENCY.fullmatch(concurrency):
        return ("--concurrency must be 1, 2, 3 or 4 so that an unsandboxed moon run stays bounded; got '"
                + concurrency + "'")

    if cd_target is not None:
        if not SAFE_PATH.fullmatch(cd_target):
            return ("the cd target '" + cd_target + "' must be an absolute path of letters, digits and "
                    "._+@-/ only, so that no shell expansion can change which directory is entered")
        d, why = _real_directory(cd_target, "the cd target")
    elif cwd is None:
        return ("'moon run' without 'cd <checkout> &&' runs in the session's cwd, and this hook input has "
                "none; use 'cd <checkout> && moon run " + task + " --concurrency " + concurrency + "'")
    else:
        d, why = _real_directory(cwd, "the session's cwd")
    if why:
        return why

    repos, why = _load_moon_config()
    if why:
        return why
    root = _checkout_root(d, repos)
    if root is None:
        return (d + " is neither a configured checkout (" + ", ".join(sorted(repos)) + ") nor a linked git "
                "worktree of one, and subdirectories do not count; run it from the checkout's top level")
    if task not in repos[root]:
        return ("'" + task + "' is not configured to escape for " + root + " (configured: "
                + ", ".join(repos[root]) + "); run it inside the sandbox, or ask the operator to add it")
    return _tree_problem(d)


def classify(command, cwd=None):
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

    # Configured moon tasks: after every refusal above, before the chaining rule below, because the
    # one accepted 'cd <checkout> && moon run ...' form contains '&&'.
    moon = _moon_attempt(tokens)
    if moon is not None:
        return _classify_moon(moon[0], moon[1], moon[2], cwd)

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
        # It used to be allowed as '-e' pairs. Removed 2026-09-27: Claude Code keeps osascript
        # sandboxed even with the flag (an escaped Notes call still failed -10810, Apple Events
        # blocked), so the allowance only advertised a dead end. Drafts go through the broker.
        return ("Claude Code keeps osascript sandboxed even with this flag (Apple Events blocked, -10810). "
                "For the 'Claude Drafts' folder in Notes use " + LIBEXEC_HINT + "host-notes WITHOUT the flag")
    if prog == "git":
        j = 0
        while j < len(args) and args[j] == "-C":
            j += 2
        if j < len(args) and args[j].startswith("-"):
            return "git options before the subcommand (e.g. -c) cannot be escaped"
        if j < len(args) and args[j] in GIT_NETWORK_ONLY:
            return None
        return "only git push|fetch|pull|clone|ls-remote may escape"
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
    reason = classify(tool_input.get("command") or "", payload.get("cwd"))
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
