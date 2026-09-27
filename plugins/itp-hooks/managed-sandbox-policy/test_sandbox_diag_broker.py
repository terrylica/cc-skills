"""Tests for sandbox_diag_broker.py: query validation (pure) plus one live broker round-trip.

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


def _free_port():
    s = socket.socket()
    s.bind(("127.0.0.1", 0))
    port = s.getsockname()[1]
    s.close()
    return port


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


if __name__ == "__main__":
    unittest.main()
