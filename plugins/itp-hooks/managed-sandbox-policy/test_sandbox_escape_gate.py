"""Tests for sandbox_escape_gate.py. Run with the SAME interpreters the gate targets:

    /usr/bin/python3 -m unittest -v test_sandbox_escape_gate      (macOS, 3.9)
    python3 -m unittest -v test_sandbox_escape_gate               (Ubuntu)

The hook is exercised END TO END through a subprocess speaking the real stdin/stdout protocol,
so wiring mistakes (wrong flag check, fail-open on error) are caught, not just the classifier.

The moon-task cases build real repositories and real linked worktrees with /usr/bin/git in a
temporary directory, and point the gate at a temporary policy directory through
SANDBOX_POLICY_DIR (ignored by the installed, root-owned gate). Everything is removed afterwards.
"""

import json
import os
import shutil
import subprocess
import sys
import tempfile
import time
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
GATE = os.path.join(HERE, "sandbox_escape_gate.py")
INSTALLER = os.path.join(HERE, "install_managed_sandbox_policy.py")
GIT = "/usr/bin/git"
MOON_CONFIG = "escape-allowed-moon-tasks.json"
TASKS = ["repo:check", "repo:release-full"]
CHECK = "moon run repo:check --concurrency 3"
# git with no system or global config, so the operator's own hooks, templates and signing stay out.
GIT_ENV = {"PATH": "/usr/bin:/bin", "GIT_CONFIG_NOSYSTEM": "1", "GIT_CONFIG_GLOBAL": "/dev/null",
           "GIT_AUTHOR_NAME": "gate test", "GIT_AUTHOR_EMAIL": "gate-test@example.invalid",
           "GIT_COMMITTER_NAME": "gate test", "GIT_COMMITTER_EMAIL": "gate-test@example.invalid"}


def decide(command, escape=True, tool="Bash", raw=None, cwd=None, env=None):
    """(decision, reason): 'pass' with no reason when the gate stays silent."""
    if raw is None:
        payload = {"tool_name": tool, "tool_input": {"command": command, "dangerouslyDisableSandbox": escape}}
        if cwd is not None:
            payload["cwd"] = cwd
        raw = json.dumps(payload)
    # check=True: the gate must always exit 0 (decisions travel on stdout); any other status is a bug.
    p = subprocess.run([sys.executable, GATE], input=raw, capture_output=True, text=True, timeout=60, check=True,
                       env=env)
    if not p.stdout.strip():
        return "pass", ""
    out = json.loads(p.stdout)["hookSpecificOutput"]
    return out["permissionDecision"], out["permissionDecisionReason"]


def run(command, escape=True, tool="Bash", raw=None):
    return decide(command, escape, tool, raw)[0]


def git(*args):
    return subprocess.run([GIT] + list(args), env=GIT_ENV, capture_output=True, text=True, timeout=30,
                          check=True).stdout


def write(path, text, mode=None):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as fh:
        fh.write(text)
    if mode is not None:
        os.chmod(path, mode)


class Checkouts:
    """Two throwaway moon repositories, each with one linked worktree, and a policy directory whose
    moon-task list allows TASKS for the first repository only. Paths are real paths (on macOS the
    temporary directory sits behind the /var -> /private/var symlink)."""

    def __init__(self):
        self.base = os.path.realpath(tempfile.mkdtemp(prefix="escape-gate-moon-"))
        self.root = self._repo("root")
        self.wt = self._worktree(self.root, "root-wt")
        self.other = self._repo("other")
        self.other_wt = self._worktree(self.other, "other-wt")
        self.policy = os.path.join(self.base, "policy")
        self.config = os.path.join(self.policy, MOON_CONFIG)
        self.write_config(self.good_config())

    def _repo(self, name):
        path = os.path.join(self.base, name)
        git("init", "-q", path)
        write(os.path.join(path, ".moon", "workspace.yml"), "projects: {}\n")
        write(os.path.join(path, "tracked.txt"), "committed\n")
        write(os.path.join(path, "sub", "keep.txt"), "committed\n")
        git("-C", path, "add", "-A")
        git("-C", path, "commit", "-qm", "init")
        return path

    def _worktree(self, repo, name):
        path = os.path.join(self.base, name)
        git("-C", repo, "worktree", "add", "-q", path, "-b", name)
        return path

    def good_config(self):
        return {"version": 1, "repos": [{"root": self.root, "tasks": list(TASKS)}]}

    def write_config(self, cfg, mode=0o644):
        write(self.config, cfg if isinstance(cfg, str) else json.dumps(cfg), mode)

    def env(self, **extra):
        env = dict(os.environ, SANDBOX_POLICY_DIR=self.policy)
        env.pop("SANDBOX_GATE_CONFIG_OWNER_UID", None)
        env.update(extra)
        return env

    def cleanup(self):
        shutil.rmtree(self.base)


class MoonCase(unittest.TestCase):
    co: Checkouts   # set by each subclass's setUpClass or setUp

    def gate(self, command, cwd=None, **env):
        return decide(command, cwd=cwd, env=self.co.env(**env))

    def assertPass(self, command, cwd=None, **env):
        decision, why = self.gate(command, cwd, **env)
        self.assertEqual(decision, "pass", command + " -> " + why)

    def assertDeny(self, command, cwd=None, why=None, **env):
        decision, reason = self.gate(command, cwd, **env)
        self.assertEqual(decision, "deny", command)
        if why is not None:
            self.assertIn(why, reason, command)


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

    def test_osascript_never_escapes(self):
        # Claude Code keeps osascript sandboxed even when escaped (-10810, measured 2026-09-27), so
        # the gate refuses it outright and points at host-notes instead of advertising a dead end.
        for cmd in ["osascript -e 'quit app \"Synergy\"'", "osascript -e 'do shell script \"ls\"'",
                    "osascript -e 'tell application \"System Events\" to keystroke \"q\"'",
                    "osascript script.scpt",
                    "/usr/bin/osascript -e 'tell application \"Finder\" to get name of front window'",
                    "osascript -e 'tell application \"Notes\" to count folders'"]:
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
            "git push origin main",
            "git -C /Users/terryli/eon/cc-skills fetch --dry-run origin",
            "git clone git@github.com:terrylica/cc-skills.git /tmp/x",
            "git ls-remote origin HEAD 2>/dev/null",
        ]:
            self.assertEqual(run(cmd), "pass", cmd)

    def test_ssh_stdin_readonly_script_is_allowed(self):
        with tempfile.NamedTemporaryFile("w", suffix=".sh", delete=False) as fh:
            fh.write("#!/bin/bash\nset -u\nuptime\nsystemctl is-active display-manager\n")
        try:
            self.assertEqual(run("ssh -o BatchMode=yes bigblack 'bash -s' < " + fh.name), "pass")
        finally:
            os.unlink(fh.name)

    def test_moon_inside_an_ssh_remote_command_keeps_the_ssh_rule(self):
        # Only a command that STARTS with moon (or cd <dir> && moon) is routed to the moon rule.
        self.assertEqual(run("ssh bigblack moon run repo:check"), "pass")


class MoonTasksApproved(MoonCase):
    @classmethod
    def setUpClass(cls):
        cls.co = Checkouts()

    @classmethod
    def tearDownClass(cls):
        cls.co.cleanup()

    def test_bare_form_in_the_root_and_in_its_linked_worktree(self):
        for cwd in (self.co.root, self.co.wt):
            self.assertPass(CHECK, cwd=cwd)
            self.assertPass("moon run repo:release-full --concurrency=1", cwd=cwd)

    def test_cd_form_for_the_root_and_its_linked_worktree(self):
        for d in (self.co.root, self.co.wt):
            self.assertPass("cd " + d + " && moon run repo:release-full --concurrency 4", cwd=self.co.base)
            self.assertPass("cd '" + d + "/'&&moon run repo:check --concurrency=2")   # quoting, trailing /, no cwd

    def test_moon_by_absolute_path(self):
        # As specified: an absolute path whose basename is moon, trusted like a bare name found on PATH.
        self.assertPass("/opt/tools/bin/moon run repo:check --concurrency 2", cwd=self.co.root)


class MoonTasksDenied(MoonCase):
    @classmethod
    def setUpClass(cls):
        cls.co = Checkouts()
        cls.link = os.path.join(cls.co.base, "link-to-root")
        os.symlink(cls.co.root, cls.link)

    @classmethod
    def tearDownClass(cls):
        cls.co.cleanup()

    def test_unlisted_task(self):
        self.assertDeny("moon run repo:lint --concurrency 3", cwd=self.co.root, why="is not configured to escape")
        self.assertDeny("cd " + self.co.wt + " && moon run other:check --concurrency 3", why="is not configured")

    def test_concurrency_must_be_one_to_four(self):
        for tail in ["", " --concurrency", " --concurrency 0", " --concurrency 5", " --concurrency three",
                     " --concurrency 3a", " --concurrency=", " --concurrency=0", " --concurrency=5", " --concurrency 03",
                     " --concurrency -1", " --concurrency 10", " --concurrency=3,4"]:
            self.assertDeny("moon run repo:check" + tail, cwd=self.co.root)
        self.assertDeny("moon run repo:check --concurrency 5", cwd=self.co.root, why="must be 1, 2, 3 or 4")

    def test_extra_flags_and_arguments(self):
        for cmd in ["moon run repo:check --concurrency 3 --force", "moon run repo:check --force --concurrency 3",
                    "moon run --concurrency 3 repo:check", "moon --log trace run repo:check --concurrency 3",
                    "moon run repo:check repo:release-full --concurrency 3",
                    "moon run repo:check --concurrency 3 -- --dry-run", "moon ci repo:check --concurrency 3",
                    "moon run 'repo:check --force' --concurrency 3", "./moon run repo:check --concurrency 3",
                    "moon run repo:check --concurrency 3 --concurrency 3"]:
            self.assertDeny(cmd, cwd=self.co.root)

    def test_kill_after_the_command(self):
        self.assertDeny(CHECK + " ; kill 1", cwd=self.co.root, why="'kill' may not run outside the sandbox")

    def test_pipes_redirections_environment_and_chaining(self):
        for cmd in [CHECK + "; ls", CHECK + " | tail -5", CHECK + " > /dev/null", CHECK + " 2>&1", CHECK + " &",
                    "FOO=1 " + CHECK, "env " + CHECK, CHECK + " && moon run repo:release-full --concurrency 3",
                    CHECK + " || true", "time " + CHECK]:
            self.assertDeny(cmd, cwd=self.co.root)

    def test_the_one_and_form_is_exact(self):
        r = self.co.root
        for cmd in ["cd {r} && cd {r} && " + CHECK, "cd {r} ; " + CHECK, "cd {r} || " + CHECK, "cd {r} & " + CHECK,
                    "pushd {r} && " + CHECK, "cd {r} && FOO=1 " + CHECK, "cd {r} && " + CHECK + " && true",
                    "cd {r} && git push origin main", "cd -P {r} && " + CHECK, "(cd {r} && " + CHECK + ")",
                    "cd {r} && " + CHECK + " | cat"]:
            self.assertDeny(cmd.format(r=r), cwd=r)

    def test_existing_refusals_come_first(self):
        r = self.co.root
        for cmd, why in [("cd " + r + " && moon run repo:check --concurrency $(echo 3)", "command substitution"),
                         ("moon run repo:check --concurrency `echo 3`", "command substitution"),
                         (CHECK + "\nls", "multi-line"), ("cat <<EOF && " + CHECK, "heredocs"),
                         ("cd /tmp/bash && " + CHECK, "'/tmp/bash' may not run")]:
            self.assertDeny(cmd, cwd=r, why=why)

    def test_relative_and_expandable_directories(self):
        r = self.co.root
        for cmd in ["cd root && " + CHECK, "cd . && " + CHECK, "cd ~/root && " + CHECK, "cd " + r + "$X && " + CHECK,
                    "cd " + r + "* && " + CHECK, "cd " + r[:-1] + "{t,x} && " + CHECK, 'cd "' + r + ' " && ' + CHECK]:
            self.assertDeny(cmd, cwd=self.co.base)
        self.assertDeny("cd root && " + CHECK, cwd=self.co.base, why="must be an absolute path")
        self.assertDeny(CHECK, cwd="root", why="is not an absolute path")

    def test_a_subdirectory_is_not_the_checkout(self):
        sub = os.path.join(self.co.root, "sub")
        self.assertDeny("cd " + sub + " && " + CHECK, why="subdirectories do not count")
        self.assertDeny(CHECK, cwd=sub, why="subdirectories do not count")
        self.assertDeny("cd " + sub + "/.. && " + CHECK, why="is not its real path")

    def test_a_symlink_into_a_checkout_is_refused(self):
        # Decided: refused, not resolved. The gate checks the path when the hook runs and the shell
        # enters it later; a symlink could be re-pointed at another checkout in between.
        self.assertDeny("cd " + self.link + " && " + CHECK, why="is not its real path")
        self.assertDeny(CHECK, cwd=self.link, why="is not its real path")

    def test_another_repository_and_its_worktree(self):
        for d in (self.co.other, self.co.other_wt):
            self.assertDeny(CHECK, cwd=d, why="is neither a configured checkout")
            self.assertDeny("cd " + d + " && " + CHECK, why="is neither a configured checkout")

    def test_a_forged_worktree_pointer(self):
        admin = git("-C", self.co.wt, "rev-parse", "--absolute-git-dir").strip()
        self.assertEqual(os.path.dirname(admin), os.path.join(self.co.root, ".git", "worktrees"))
        # .git points at the root's real worktree admin directory, whose gitdir points back elsewhere.
        forged = os.path.join(self.co.base, "forged")
        write(os.path.join(forged, ".git"), "gitdir: " + admin + "\n")
        self.assertDeny(CHECK, cwd=forged, why="is neither a configured checkout")
        # .git points at the root's own git directory, which is not a worktree admin directory.
        forged2 = os.path.join(self.co.base, "forged2")
        write(os.path.join(forged2, ".git"), "gitdir: " + os.path.join(self.co.root, ".git") + "\n")
        self.assertDeny("cd " + forged2 + " && " + CHECK, why="is neither a configured checkout")
        # .git is a symlink to the real worktree's .git file.
        forged3 = os.path.join(self.co.base, "forged3")
        os.makedirs(forged3)
        os.symlink(os.path.join(self.co.wt, ".git"), os.path.join(forged3, ".git"))
        self.assertDeny(CHECK, cwd=forged3, why="is neither a configured checkout")

    def test_the_bare_form_needs_the_payload_cwd(self):
        self.assertDeny(CHECK, cwd=None, why="this hook input has none")


class MoonTaskConfig(MoonCase):
    @classmethod
    def setUpClass(cls):
        cls.co = Checkouts()

    @classmethod
    def tearDownClass(cls):
        cls.co.cleanup()

    def setUp(self):
        if os.path.islink(self.co.config) or os.path.isfile(self.co.config):
            os.remove(self.co.config)
        elif os.path.isdir(self.co.config):
            os.rmdir(self.co.config)
        self.co.write_config(self.co.good_config())

    def test_control_the_good_config_passes(self):
        self.assertPass(CHECK, cwd=self.co.root)

    def test_missing_config(self):
        os.remove(self.co.config)
        self.assertDeny(CHECK, cwd=self.co.root, why="does not exist")

    def test_malformed_configs(self):
        r = self.co.root

        def repos(*entries):
            return {"version": 1, "repos": list(entries)}
        for cfg in ["{", "", "[]", "null", {"version": 2, "repos": []}, {"version": True, "repos": [{"root": r, "tasks": TASKS}]},
                    {"version": "1", "repos": [{"root": r, "tasks": TASKS}]}, {"version": 1}, {"version": 1, "repos": {}},
                    dict(repos({"root": r, "tasks": TASKS}), extra=1), repos({"root": "root", "tasks": TASKS}),
                    repos({"root": r + "/", "tasks": TASKS}), repos({"root": r, "tasks": []}),
                    repos({"root": r, "tasks": "repo:check"}), repos({"root": r, "tasks": ["Repo:Check"]}),
                    repos({"root": r, "tasks": ["repo:check\n"]}), repos({"root": r, "tasks": TASKS, "extra": 1}),
                    repos({"root": r}), repos([r, TASKS])]:
            self.co.write_config(cfg)
            self.assertDeny(CHECK, cwd=r, why="is malformed")

    def test_a_config_that_is_a_symlink_or_not_a_file(self):
        real = os.path.join(self.co.base, "elsewhere.json")
        write(real, json.dumps(self.co.good_config()))
        os.remove(self.co.config)
        os.symlink(real, self.co.config)
        self.assertDeny(CHECK, cwd=self.co.root, why="cannot use")
        os.remove(self.co.config)
        os.makedirs(self.co.config)
        self.assertDeny(CHECK, cwd=self.co.root, why="not a regular file")

    def test_an_oversized_config(self):
        self.co.write_config(" " * (70 * 1024) + json.dumps(self.co.good_config()))
        self.assertDeny(CHECK, cwd=self.co.root, why="larger than")

    def test_ownership_when_treated_as_installed(self):
        # The installed gate requires a root-owned list. The seam swaps root for another uid so that
        # the same check runs here without root; the installed gate ignores the seam.
        uid = str(os.getuid())
        self.assertPass(CHECK, cwd=self.co.root, SANDBOX_GATE_CONFIG_OWNER_UID=uid)
        for mode in (0o664, 0o646, 0o666):
            self.co.write_config(self.co.good_config(), mode)
            self.assertDeny(CHECK, cwd=self.co.root, why="group- or world-writable", SANDBOX_GATE_CONFIG_OWNER_UID=uid)
        self.co.write_config(self.co.good_config(), 0o644)
        self.assertDeny(CHECK, cwd=self.co.root, why="is not owned by uid",
                        SANDBOX_GATE_CONFIG_OWNER_UID=str(os.getuid() + 1))
        self.assertDeny(CHECK, cwd=self.co.root, why="is not owned by", SANDBOX_GATE_CONFIG_OWNER_UID="root")

    def test_a_checkout_copy_without_the_seam_skips_the_ownership_check(self):
        # Documents the development mode that SANDBOX_POLICY_DIR already implies; production is root-owned.
        self.co.write_config(self.co.good_config(), 0o666)
        self.assertPass(CHECK, cwd=self.co.root)


class MoonTreeMustBeClean(MoonCase):
    """Each test dirties or rewires a fresh pair of repositories."""

    def setUp(self):
        self.co = Checkouts()
        self.addCleanup(self.co.cleanup)

    def test_a_modified_tracked_file(self):
        for d in (self.co.root, self.co.wt):
            write(os.path.join(d, "tracked.txt"), "changed\n")
            self.assertDeny(CHECK, cwd=d, why="uncommitted changes")
            self.assertDeny("cd " + d + " && " + CHECK, why="M tracked.txt")

    def test_an_untracked_file(self):
        for d in (self.co.root, self.co.wt):
            write(os.path.join(d, "sub", "new.test.ts"), "x\n")
            self.assertDeny(CHECK, cwd=d, why="?? sub/new.test.ts")

    def test_a_staged_change(self):
        write(os.path.join(self.co.root, "tracked.txt"), "changed\n")
        git("-C", self.co.root, "add", "tracked.txt")
        self.assertDeny(CHECK, cwd=self.co.root, why="uncommitted changes")

    def test_edits_hidden_by_index_flags(self):
        # git status does not look at these entries, so a clean status would be a lie.
        git("-C", self.co.root, "update-index", "--assume-unchanged", "tracked.txt")
        write(os.path.join(self.co.root, "tracked.txt"), "changed\n")
        self.assertDeny(CHECK, cwd=self.co.root, why="assume-unchanged or skip-worktree")
        git("-C", self.co.wt, "update-index", "--skip-worktree", "tracked.txt")
        write(os.path.join(self.co.wt, "tracked.txt"), "changed\n")
        self.assertDeny(CHECK, cwd=self.co.wt, why="assume-unchanged or skip-worktree")

    def test_submodules(self):
        head = git("-C", self.co.root, "rev-parse", "HEAD").strip()
        git("-C", self.co.root, "update-index", "--add", "--cacheinfo", "160000," + head + ",vendored")
        git("-C", self.co.root, "commit", "-qm", "gitlink")
        self.assertDeny(CHECK, cwd=self.co.root, why="has submodules")

    def _touch_tracked(self, d):
        # A new mtime makes git re-read the file, run its filter, and rewrite the index.
        path = os.path.join(d, "tracked.txt")
        later = time.time() + 5
        os.utime(path, (later, later))

    def test_a_filter_driver_is_refused_and_never_runs(self):
        marker = os.path.join(self.co.base, "FILTER-RAN")
        git("-C", self.co.root, "config", "filter.x.clean", "touch " + marker + "; cat")
        write(os.path.join(self.co.root, ".git", "info", "attributes"), "* filter=x\n")
        self._touch_tracked(self.co.root)
        self.assertDeny(CHECK, cwd=self.co.root, why="sets 'filter.x.clean'")
        self.assertFalse(os.path.exists(marker), "the gate ran the repository's filter")
        # Control: a plain git status in the same state does run it, so the refusal is what stopped it.
        subprocess.run([GIT, "-C", self.co.root, "status", "--porcelain"], env=GIT_ENV, capture_output=True,
                       timeout=30, check=False)
        self.assertTrue(os.path.exists(marker), "control: plain git status did not run the filter")

    def test_core_worktree_is_refused(self):
        git("-C", self.co.root, "config", "core.worktree", self.co.other)
        self.assertDeny(CHECK, cwd=self.co.root, why="sets 'core.worktree'")

    def test_hooks_and_fsmonitor_never_run_during_the_check(self):
        hook_marker = os.path.join(self.co.base, "HOOK-RAN")
        fsmonitor_marker = os.path.join(self.co.base, "FSMONITOR-RAN")
        write(os.path.join(self.co.root, ".git", "hooks", "post-index-change"),
              "#!/bin/sh\ntouch " + hook_marker + "\n", 0o755)
        fsmonitor = os.path.join(self.co.base, "fsmonitor.sh")
        write(fsmonitor, "#!/bin/sh\ntouch " + fsmonitor_marker + "\nexit 1\n", 0o755)
        git("-C", self.co.root, "config", "core.fsmonitor", fsmonitor)
        self._touch_tracked(self.co.root)
        self.assertPass(CHECK, cwd=self.co.root)   # the tree is clean; only the check's side effects matter
        self.assertFalse(os.path.exists(hook_marker), "the gate ran .git/hooks/post-index-change")
        self.assertFalse(os.path.exists(fsmonitor_marker), "the gate ran the repository's fsmonitor hook")
        # Control: a plain git status runs both.
        subprocess.run([GIT, "-C", self.co.root, "status", "--porcelain"], env=GIT_ENV, capture_output=True,
                       timeout=30, check=False)
        self.assertTrue(os.path.exists(hook_marker), "control: plain git status did not run the hook")
        self.assertTrue(os.path.exists(fsmonitor_marker), "control: plain git status did not run fsmonitor")


def installer(*args, env=None):
    return subprocess.run([sys.executable, INSTALLER] + list(args), capture_output=True, text=True, timeout=60,
                          check=False, env=env)


def previewed_moon_config(stdout):
    marker = "moon-task list that would be written to "
    return json.loads(stdout[stdout.index(marker):].split(":\n", 1)[1])


class InstallerMoonTaskFlag(MoonCase):
    """The installer's preview (no root needed, changes nothing) for --allow-moon-task."""

    @classmethod
    def setUpClass(cls):
        cls.co = Checkouts()

    @classmethod
    def tearDownClass(cls):
        cls.co.cleanup()

    def test_the_preview_shows_the_list_it_would_write(self):
        p = installer("--allow-moon-task", self.co.root + "=repo:check,repo:release-full",
                      "--allow-moon-task", self.co.root + "=repo:check")
        self.assertEqual(p.returncode, 0, p.stderr)
        self.assertIn("preview only", p.stdout)
        self.assertEqual(previewed_moon_config(p.stdout),
                         {"version": 1, "repos": [{"root": self.co.root, "tasks": TASKS}]})

    def test_tilde_and_symlinks_resolve_to_the_real_checkout(self):
        link = os.path.join(self.co.base, "link-to-root")
        if not os.path.islink(link):
            os.symlink(self.co.root, link)
        p = installer("--allow-moon-task", "~/link-to-root=repo:check", env=dict(os.environ, HOME=self.co.base))
        self.assertEqual(p.returncode, 0, p.stderr)
        self.assertEqual(previewed_moon_config(p.stdout)["repos"], [{"root": self.co.root, "tasks": ["repo:check"]}])

    def test_the_list_it_writes_is_one_the_gate_accepts(self):
        p = installer("--allow-moon-task", self.co.root + "=repo:check")
        self.assertEqual(p.returncode, 0, p.stderr)
        self.co.write_config(previewed_moon_config(p.stdout))
        try:
            self.assertPass(CHECK, cwd=self.co.wt)
        finally:
            self.co.write_config(self.co.good_config())

    def test_bad_values_are_rejected(self):
        r = self.co.root
        for spec in [r + "=Repo:Check", r + "=repo", r + "=repo:check,", r + "=repo:check;ls", r, "=repo:check",
                     r + "=", os.path.join(r, "sub") + "=repo:check", self.co.wt + "=repo:check",
                     os.path.join(self.co.base, "missing") + "=repo:check"]:
            p = installer("--allow-moon-task", spec)
            self.assertNotEqual(p.returncode, 0, spec)
            self.assertIn("--allow-moon-task", p.stderr, spec)

    def test_allow_and_clear_are_exclusive(self):
        p = installer("--allow-moon-task", self.co.root + "=repo:check", "--clear-moon-tasks")
        self.assertEqual(p.returncode, 2)

    def test_without_the_flag_the_list_is_left_alone(self):
        for args in ([], ["--clear-moon-tasks"]):
            p = installer(*args)
            self.assertEqual(p.returncode, 0, p.stderr)
            self.assertIn(MOON_CONFIG, p.stdout)
            self.assertIn("moon tasks: ", p.stdout)
            self.assertNotIn("moon-task list that would be written", p.stdout)


if __name__ == "__main__":
    unittest.main()
