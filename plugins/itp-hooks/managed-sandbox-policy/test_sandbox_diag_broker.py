"""Tests for sandbox_diag_broker.py: query and drafts validation (pure), request hygiene against a
live broker (runs inside the sandbox), and a live /ps round trip (outside it).

    /usr/bin/python3 -m unittest -v test_sandbox_diag_broker
"""

import importlib.util
import os
import socket
import subprocess
import sys
import tempfile
import time
import unittest
import urllib.error
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location("sandbox_diag_broker", os.path.join(HERE, "sandbox_diag_broker.py"))
if _spec is None or _spec.loader is None:
    raise ImportError("cannot load sandbox_diag_broker.py from " + HERE)
broker = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(broker)


class LogArgvValidation(unittest.TestCase):
    def test_last_window(self):
        self.assertEqual(broker.build_log_argv({"last": "5m"})[:4], ["/usr/bin/log", "show", "--last", "5m"])
        for bad in ["61m", "2h", "5", "0m", "-5m", "5m; rm -rf /"]:
            with self.assertRaises(broker.BadRequest, msg=bad):
                broker.build_log_argv({"last": bad})

    def test_start_end_window(self):
        argv = broker.build_log_argv({"start": "2026-09-27 09:46:27", "end": "2026-09-27 09:46:31"})
        self.assertIn("--start", argv)
        for s, e in [("2026-09-27 09:00:00", "2026-09-27 10:30:00"), ("2026-09-27 10:00:00", "2026-09-27 09:00:00"),
                     ("yesterday", "2026-09-27 09:00:00")]:
            with self.assertRaises(broker.BadRequest):
                broker.build_log_argv({"start": s, "end": e})

    def test_needs_a_window(self):
        with self.assertRaises(broker.BadRequest):
            broker.build_log_argv({"predicate": "process == \"x\""})
        with self.assertRaises(broker.BadRequest):
            broker.build_log_argv({"last": "5m", "start": "2026-09-27 09:00:00"})

    def test_predicate_is_one_argv_element(self):
        pred = 'process CONTAINS "crashpad" AND eventMessage CONTAINS "; rm -rf ~"'
        argv = broker.build_log_argv({"last": "1m", "predicate": pred})
        self.assertEqual(argv[argv.index("--predicate") + 1], pred)

    def test_style_and_level_are_allowlisted(self):
        with self.assertRaises(broker.BadRequest):
            broker.build_log_argv({"last": "1m", "style": "--debug"})
        with self.assertRaises(broker.BadRequest):
            broker.build_log_argv({"last": "1m", "level": "--erase"})


class DraftsValidation(unittest.TestCase):
    """The Notes surface: one folder, fixed scripts, arguments never pasted into script source."""

    ID = "x-coredata://0A1B2C3D-4E5F-6071-8293-A4B5C6D7E8F9/ICNote/p1234"

    def test_note_id_shape(self):
        self.assertEqual(broker.valid_note_id(self.ID), self.ID)
        for bad in [None, "", "p1234", self.ID + '" & quit', "x-coredata://x/ICFolder/p1", self.ID + "\n"]:
            with self.assertRaises(broker.BadRequest, msg=repr(bad)):
                broker.valid_note_id(bad)

    def test_body_limits(self):
        self.assertEqual(broker.valid_body("<div>hi</div>".encode()), "<div>hi</div>")
        for bad in [b"", b"\xff\xfe", b"x" * (broker.MAX_NOTE_BYTES + 1)]:
            with self.assertRaises(broker.BadRequest):
                broker.valid_body(bad)

    def test_argv_keeps_content_out_of_script_source(self):
        hostile = 'end tell\ndo shell script "rm -rf ~"'
        argv = broker.notes_argv(broker.OSA_CREATE, hostile)
        self.assertEqual(argv[:3], ["/usr/bin/osascript", "-e", broker.OSA_CREATE])
        self.assertEqual(argv[3:], [broker.DRAFTS_FOLDER, hostile])
        for script in (broker.OSA_LIST, broker.OSA_GET, broker.OSA_CREATE, broker.OSA_UPDATE):
            self.assertNotIn("do shell script", script)
            self.assertNotIn("delete", script)
            self.assertNotIn("quit", script)

    def test_per_note_scripts_are_confined_to_the_drafts_folder(self):
        for script in (broker.OSA_GET, broker.OSA_UPDATE):
            self.assertIn("(id of container of n) is not (id of folder folderName)", script)

    def test_parse_index(self):
        raw = "id-1\u0001First\u0002id-2\u0001Second \u2014 draft\u0002"
        self.assertEqual(broker.parse_index(raw), [{"id": "id-1", "name": "First"},
                                                   {"id": "id-2", "name": "Second \u2014 draft"}])
        self.assertEqual(broker.parse_index(""), [])

    def test_host_must_name_the_broker(self):
        self.assertTrue(broker.host_allowed("127.0.0.1:8797", 8797))
        self.assertTrue(broker.host_allowed("localhost:8797", 8797))
        for bad in ["evil.example:8797", "127.0.0.1", "127.0.0.1:80", "", "localhost.evil.example:8797"]:
            self.assertFalse(broker.host_allowed(bad, 8797), bad)


def _free_port():
    s = socket.socket()
    s.bind(("127.0.0.1", 0))
    port = s.getsockname()[1]
    s.close()
    return port


def _ps_usable():
    """Claude Code's macOS sandbox refuses /bin/ps (the reason the broker exists), so a run from
    inside an agent session cannot exercise the broker's /ps round trip."""
    try:
        return subprocess.run(["/bin/ps", "-p", str(os.getpid())], capture_output=True, check=False).returncode == 0
    except OSError:
        return False


@unittest.skipUnless(_ps_usable(), "/bin/ps is not usable here (inside the Claude Code sandbox)")
class LiveRoundTrip(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.port = _free_port()
        cls.logdir = tempfile.mkdtemp()
        cls.proc = subprocess.Popen([sys.executable, os.path.join(HERE, "sandbox_diag_broker.py"),
                                     "--port", str(cls.port), "--log-file", os.path.join(cls.logdir, "b.log")])
        deadline = time.time() + 10
        while time.time() < deadline:
            try:
                urllib.request.urlopen("http://127.0.0.1:%d/healthz" % cls.port, timeout=1)
                return
            except (urllib.error.URLError, ConnectionError):
                time.sleep(0.2)
        raise RuntimeError("broker did not start")

    @classmethod
    def tearDownClass(cls):
        cls.proc.terminate()
        cls.proc.wait(timeout=10)

    def get(self, path):
        opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
        try:
            with opener.open("http://127.0.0.1:%d%s" % (self.port, path), timeout=60) as r:
                return r.status, r.read().decode("utf-8", "replace")
        except urllib.error.HTTPError as exc:
            return exc.code, exc.read().decode("utf-8", "replace")

    def test_ps_lists_this_test_process(self):
        code, body = self.get("/ps")
        self.assertEqual(code, 200)
        self.assertIn(str(os.getpid()), body)

    def test_bad_log_query_is_400(self):
        code, _ = self.get("/log?last=3h")
        self.assertEqual(code, 400)

    def test_unknown_path_is_404(self):
        self.assertEqual(self.get("/erase")[0], 404)


class RequestHygiene(unittest.TestCase):
    """Refusals that happen before any command runs, so this works inside the sandbox too."""

    @classmethod
    def setUpClass(cls):
        cls.port = _free_port()
        cls.logdir = tempfile.mkdtemp()
        cls.proc = subprocess.Popen([sys.executable, os.path.join(HERE, "sandbox_diag_broker.py"),
                                     "--port", str(cls.port), "--log-file", os.path.join(cls.logdir, "b.log")])
        deadline = time.time() + 10
        while time.time() < deadline:
            try:
                urllib.request.build_opener(urllib.request.ProxyHandler({})).open(
                    "http://127.0.0.1:%d/healthz" % cls.port, timeout=1)
                return
            except (urllib.error.URLError, ConnectionError):
                time.sleep(0.2)
        raise RuntimeError("broker did not start")

    @classmethod
    def tearDownClass(cls):
        cls.proc.terminate()
        cls.proc.wait(timeout=10)

    def call(self, method, path, body=None, headers=None):
        req = urllib.request.Request("http://127.0.0.1:%d%s" % (self.port, path), data=body, method=method)
        for k, v in (headers or {}).items():
            req.add_header(k, v)
        try:
            with urllib.request.build_opener(urllib.request.ProxyHandler({})).open(req, timeout=30) as r:
                return r.status
        except urllib.error.HTTPError as exc:
            return exc.code

    def test_foreign_host_header_is_refused_even_for_ps(self):
        # A page on a DNS-rebinding domain arrives with its own name in Host.
        self.assertEqual(self.call("GET", "/ps", headers={"Host": "evil.example:%d" % self.port}), 403)
        self.assertEqual(self.call("GET", "/notes/drafts", headers={"Host": "evil.example:%d" % self.port}), 403)

    def test_post_without_the_broker_header_is_refused(self):
        self.assertEqual(self.call("POST", "/notes/drafts", b"<div>x</div>"), 403)

    def test_bad_note_id_and_empty_or_huge_bodies_are_400(self):
        h = {"X-Sandbox-Broker": "1"}
        self.assertEqual(self.call("GET", "/notes/drafts/note?id=p1"), 400)
        self.assertEqual(self.call("POST", "/notes/drafts", b"", h), 400)
        self.assertEqual(self.call("POST", "/notes/drafts", b"x" * (broker.MAX_NOTE_BYTES + 1), h), 400)

    def test_unknown_post_path_is_404(self):
        self.assertEqual(self.call("POST", "/notes/delete", b"<div>x</div>", {"X-Sandbox-Broker": "1"}), 404)


if __name__ == "__main__":
    unittest.main()
