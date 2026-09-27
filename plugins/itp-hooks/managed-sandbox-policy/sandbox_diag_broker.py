#!/usr/bin/env python3
"""Read-only diagnostics broker for sandboxed Claude Code agents (macOS).

WHY. Inside Claude Code's macOS sandbox, /bin/ps is denied and /usr/bin/log refuses to run
("Cannot run while sandboxed"). The escape flag does not help: Claude Code silently keeps those
commands sandboxed (measured 2026-09-27; undocumented). Agents still need process lists and the
unified log to diagnose incidents like the one that motivated the sandbox. This broker runs
OUTSIDE the sandbox, from root-owned code, and answers a FIXED menu of read-only queries on
127.0.0.1, which the sandbox allows. No shell is ever involved; every query is a fixed argv.

ENDPOINTS (GET, 127.0.0.1 only):
  /healthz                       -> "ok"
  /ps                            -> ps -Aww -o pid,ppid,user,lstart,stat,%cpu,rss,command
  /log?last=5m[&predicate=..][&style=compact|syslog|json|ndjson][&level=info|debug]
  /log?start=YYYY-MM-DD HH:MM:SS&end=YYYY-MM-DD HH:MM:SS[&...]
      `last` is at most 60m; a start/end window at most 60 minutes. One `log show` at a time
      (the unified log is expensive: see the process-storm doctrine), 120 s timeout, output capped.

Stdlib-only, Python 3.9 (macOS /usr/bin/python3). Started by launchd through the signed runner
shim sandbox-diag-broker-runner (launchd-runner policy). Clients: host-ps, host-log.

SETPROCTITLE-OK: stdlib-only on the OS-owned interpreter by design (no third-party module may be
imported into a root-owned policy component); the process is identifiable by its argv
(.../sandbox_diag_broker.py) in ps, and by the signed runner's identifier in the Background panel.
"""

import argparse
import datetime
import logging
import logging.handlers
import os
import re
import subprocess
import threading
from typing import Any
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

DEFAULT_PORT = 8797
MAX_OUTPUT_BYTES = 32 * 1024 * 1024
LOG_TIMEOUT_S = 120
MAX_WINDOW = datetime.timedelta(minutes=60)
PS_ARGV = ["/bin/ps", "-Aww", "-o", "pid,ppid,user,lstart,stat,%cpu,rss,command"]
STYLES = {"compact", "syslog", "json", "ndjson", "default"}
LEVELS = {"info": "--info", "debug": "--debug"}
LAST_RE = re.compile(r"^([1-9][0-9]*)([smh])$")
TS_FMT = "%Y-%m-%d %H:%M:%S"

LOG_SLOT = threading.Semaphore(1)
log = logging.getLogger("sandbox-diag-broker")


class BadRequest(Exception):
    pass


def build_log_argv(q):
    """Validate query params and return the fixed `log show` argv. Raises BadRequest."""
    argv = ["/usr/bin/log", "show"]
    last = q.get("last")
    start, end = q.get("start"), q.get("end")
    if last and (start or end):
        raise BadRequest("use either last or start/end")
    if last:
        m = LAST_RE.match(last)
        if not m:
            raise BadRequest("last must look like 30s, 5m or 1h")
        n, unit = int(m.group(1)), m.group(2)
        seconds = n * {"s": 1, "m": 60, "h": 3600}[unit]
        if seconds > MAX_WINDOW.total_seconds():
            raise BadRequest("last may be at most 60m")
        argv += ["--last", last]
    elif start and end:
        try:
            s = datetime.datetime.strptime(start, TS_FMT)
            e = datetime.datetime.strptime(end, TS_FMT)
        except ValueError:
            raise BadRequest("start/end must be 'YYYY-MM-DD HH:MM:SS'")
        if not (datetime.timedelta(0) < e - s <= MAX_WINDOW):
            raise BadRequest("start/end window must be positive and at most 60 minutes")
        argv += ["--start", start, "--end", end]
    else:
        raise BadRequest("give last=… or start=…&end=…")
    style = q.get("style", "compact")
    if style not in STYLES:
        raise BadRequest("style must be one of " + ", ".join(sorted(STYLES)))
    argv += ["--style", style]
    level = q.get("level")
    if level:
        if level not in LEVELS:
            raise BadRequest("level must be info or debug")
        argv.append(LEVELS[level])
    predicate = q.get("predicate")
    if predicate:
        if len(predicate) > 2000:
            raise BadRequest("predicate too long")
        argv += ["--predicate", predicate]
    return argv


def run_capped(argv, timeout):
    p = subprocess.run(argv, capture_output=True, timeout=timeout, check=False)
    out = p.stdout
    if len(out) > MAX_OUTPUT_BYTES:
        out = out[:MAX_OUTPUT_BYTES] + b"\n[sandbox-diag-broker: output truncated at 32 MiB]\n"
    return p.returncode, out, p.stderr[-4000:]


class Handler(BaseHTTPRequestHandler):
    server_version = "sandbox-diag-broker/1"

    def _send(self, code, body, ctype="text/plain; charset=utf-8"):
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.client_address[0] != "127.0.0.1":
            self._send(403, b"loopback only\n")
            return
        url = urlparse(self.path)
        q = {k: v[0] for k, v in parse_qs(url.query).items()}
        try:
            if url.path == "/healthz":
                self._send(200, b"ok\n")
            elif url.path == "/ps":
                rc, out, err = run_capped(PS_ARGV, 30)
                self._send(200 if rc == 0 else 502, out if rc == 0 else err)
            elif url.path == "/log":
                argv = build_log_argv(q)
                if not LOG_SLOT.acquire(timeout=LOG_TIMEOUT_S):
                    self._send(429, b"another log query is running; retry later\n")
                    return
                try:
                    rc, out, err = run_capped(argv, LOG_TIMEOUT_S)
                finally:
                    LOG_SLOT.release()
                self._send(200 if rc == 0 else 502, out if rc == 0 else err)
            else:
                self._send(404, b"endpoints: /healthz /ps /log\n")
        except BadRequest as exc:
            self._send(400, (str(exc) + "\n").encode())
        except subprocess.TimeoutExpired:
            self._send(504, b"query timed out\n")

    def log_message(self, format: str, *args: Any) -> None:
        log.info("%s %s", self.address_string(), format % args)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--port", type=int, default=DEFAULT_PORT)
    ap.add_argument("--log-file", default=os.path.expanduser("~/Library/Logs/sandbox-diag-broker/broker.log"))
    args = ap.parse_args()
    os.makedirs(os.path.dirname(args.log_file), exist_ok=True)
    handler = logging.handlers.RotatingFileHandler(args.log_file, maxBytes=2 * 1024 * 1024, backupCount=2)
    handler.setFormatter(logging.Formatter("%(asctime)s %(levelname)s %(message)s"))
    log.addHandler(handler)
    log.setLevel(logging.INFO)
    srv = ThreadingHTTPServer(("127.0.0.1", args.port), Handler)
    log.info("listening on 127.0.0.1:%d", args.port)
    srv.serve_forever()


if __name__ == "__main__":
    main()
