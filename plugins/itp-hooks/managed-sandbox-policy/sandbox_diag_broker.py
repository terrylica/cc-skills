#!/usr/bin/env python3
"""Diagnostics + drafts broker for sandboxed Claude Code agents (macOS).

WHY. Inside Claude Code's macOS sandbox, /bin/ps is denied and /usr/bin/log refuses to run
("Cannot run while sandboxed"). The escape flag does not help: Claude Code silently keeps those
commands sandboxed (measured 2026-09-27; undocumented). Agents still need process lists and the
unified log to diagnose incidents like the one that motivated the sandbox. This broker runs
OUTSIDE the sandbox, from root-owned code, and answers a FIXED menu of read-only queries on
127.0.0.1, which the sandbox allows. No shell is ever involved; every query is a fixed argv.

DRAFTS. The sandbox also blocks Apple Events, and the escape flag does not lift that either: an
escaped `osascript -e 'tell application "Notes" to count folders'` still failed -10810 (measured
2026-09-27). So agents could no longer park a human-in-the-loop draft (notes-commander draft-park).
The broker serves the smallest Notes surface that job needs, confined to ONE folder, "Claude
Drafts": list it, read a note in it, create a note in it, replace the body of a note in it. There
is no delete, no other folder, no other app. Note bodies reach AppleScript only as run-handler
ARGUMENTS of fixed scripts, never as script source, so a draft cannot inject AppleScript.

REQUEST HYGIENE (all endpoints). The Host header must name this broker (127.0.0.1 or localhost on
its port): without that, a web page on a DNS-rebinding domain could read /ps, /log or the drafts.
POSTs must also carry `X-Sandbox-Broker: 1`, a header a browser cannot add cross-site without a
preflight this broker never approves.

ENDPOINTS (127.0.0.1 only):
  GET  /healthz                  -> "ok"
  GET  /ps                       -> ps -Aww -o pid,ppid,user,lstart,stat,%cpu,rss,command
  GET  /log?last=5m[&predicate=..][&style=compact|syslog|json|ndjson][&level=info|debug]
  GET  /log?start=YYYY-MM-DD HH:MM:SS&end=YYYY-MM-DD HH:MM:SS[&...]
      `last` is at most 60m; a start/end window at most 60 minutes. One `log show` at a time
      (the unified log is expensive: see the process-storm doctrine), 120 s timeout, output capped.
  GET  /notes/drafts             -> JSON [{"id", "name"}] of notes in "Claude Drafts"
  GET  /notes/drafts/note?id=ID  -> the note's HTML body (only if it is in "Claude Drafts")
  POST /notes/drafts             body=HTML -> JSON {"id"} of a new note in "Claude Drafts"
  POST /notes/drafts/note?id=ID  body=HTML -> replaces that note's body (only in "Claude Drafts")
      One Notes operation at a time, 60 s timeout, bodies at most 512 KiB.

Stdlib-only, Python 3.9 (macOS /usr/bin/python3). Started by launchd through the signed runner
shim sandbox-diag-broker-runner (launchd-runner policy). Clients: host-ps, host-log, host-notes.
The first Notes request makes macOS ask once whether sandbox-diag-broker-runner may control Notes.

SETPROCTITLE-OK: stdlib-only on the OS-owned interpreter by design (no third-party module may be
imported into a root-owned policy component); the process is identifiable by its argv
(.../sandbox_diag_broker.py) in ps, and by the signed runner's identifier in the Background panel.
"""

import argparse
import datetime
import json
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

# --- drafts (Notes) -------------------------------------------------------------------------------
DRAFTS_FOLDER = "Claude Drafts"
NOTES_TIMEOUT_S = 60
MAX_NOTE_BYTES = 512 * 1024
NOTE_ID_RE = re.compile(r"^x-coredata://[0-9A-Fa-f-]{36}/ICNote/p[0-9]+$")
NOTES_SLOT = threading.Semaphore(1)
FS, RS = "\u0001", "\u0002"
OSASCRIPT = "/usr/bin/osascript"

# Fixed scripts. Everything variable arrives as a run-handler argument (argv), never as source.
OSA_LIST = """on run argv
  set folderName to item 1 of argv
  tell application "Notes"
    if not (exists folder folderName) then return ""
    set out to ""
    repeat with n in notes of folder folderName
      set out to out & (id of n) & (ASCII character 1) & (name of n) & (ASCII character 2)
    end repeat
    return out
  end tell
end run"""

# Every per-note script carries the same guard: the note must sit in THE drafts folder.
OSA_GET = """on run argv
  set folderName to item 1 of argv
  set noteId to item 2 of argv
  tell application "Notes"
    set n to note id noteId
    if (id of container of n) is not (id of folder folderName) then error "not a draft" number 1001
    return body of n
  end tell
end run"""

OSA_CREATE = """on run argv
  set folderName to item 1 of argv
  set bodyHTML to item 2 of argv
  tell application "Notes"
    if not (exists folder folderName) then make new folder with properties {name:folderName}
    set n to make new note at folder folderName with properties {body:bodyHTML}
    return id of n
  end tell
end run"""

OSA_UPDATE = """on run argv
  set folderName to item 1 of argv
  set noteId to item 2 of argv
  set bodyHTML to item 3 of argv
  tell application "Notes"
    set n to note id noteId
    if (id of container of n) is not (id of folder folderName) then error "not a draft" number 1001
    set body of n to bodyHTML
    return id of n
  end tell
end run"""


def valid_note_id(value):
    if not value or not NOTE_ID_RE.fullmatch(value):  # fullmatch: `$` alone admits a trailing newline
        raise BadRequest("id must look like x-coredata://<UUID>/ICNote/p<number>")
    return value


def valid_body(raw):
    if not raw:
        raise BadRequest("empty body")
    if len(raw) > MAX_NOTE_BYTES:
        raise BadRequest("body larger than 512 KiB")
    try:
        return raw.decode("utf-8")
    except UnicodeDecodeError:
        raise BadRequest("body must be UTF-8")


def parse_index(raw):
    """Parse OSA_LIST output into [{"id", "name"}]."""
    out = []
    for rec in raw.split(RS):
        if not rec.strip():
            continue
        parts = rec.split(FS, 1)
        out.append({"id": parts[0].strip(), "name": parts[1] if len(parts) > 1 else ""})
    return out


def notes_argv(script, *args):
    """The fixed osascript argv: script source first, then its arguments, never interpolated."""
    return [OSASCRIPT, "-e", script] + [DRAFTS_FOLDER] + list(args)


def host_allowed(host, port):
    return host in ("127.0.0.1:%d" % port, "localhost:%d" % port)
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
        m = LAST_RE.fullmatch(last)
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

    def _refused(self, post=False):
        """Loopback, Host and (for writes) header checks shared by every endpoint."""
        if self.client_address[0] != "127.0.0.1":
            self._send(403, b"loopback only\n")
            return True
        if not host_allowed(self.headers.get("Host", ""), self.server.server_address[1]):
            self._send(403, b"Host must name this broker (127.0.0.1 or localhost on its port)\n")
            return True
        if post and self.headers.get("X-Sandbox-Broker") != "1":
            self._send(403, b"POST needs the header X-Sandbox-Broker: 1\n")
            return True
        return False

    def _notes(self, argv):
        if not NOTES_SLOT.acquire(timeout=NOTES_TIMEOUT_S):
            self._send(429, b"another Notes operation is running; retry later\n")
            return None
        try:
            rc, out, err = run_capped(argv, NOTES_TIMEOUT_S)
        finally:
            NOTES_SLOT.release()
        if rc != 0:
            self._send(502, err or b"osascript failed\n")
            return None
        return out.decode("utf-8", "replace").rstrip("\n")

    def do_GET(self):
        if self._refused():
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
            elif url.path == "/notes/drafts":
                out = self._notes(notes_argv(OSA_LIST))
                if out is not None:
                    self._send(200, json.dumps(parse_index(out)).encode(), "application/json")
            elif url.path == "/notes/drafts/note":
                out = self._notes(notes_argv(OSA_GET, valid_note_id(q.get("id"))))
                if out is not None:
                    self._send(200, out.encode(), "text/html; charset=utf-8")
            else:
                self._send(404, b"endpoints: /healthz /ps /log /notes/drafts /notes/drafts/note\n")
        except BadRequest as exc:
            self._send(400, (str(exc) + "\n").encode())
        except subprocess.TimeoutExpired:
            self._send(504, b"query timed out\n")

    def do_POST(self):
        if self._refused(post=True):
            return
        url = urlparse(self.path)
        q = {k: v[0] for k, v in parse_qs(url.query).items()}
        try:
            length = int(self.headers.get("Content-Length") or 0)
            if length > MAX_NOTE_BYTES:
                raise BadRequest("body larger than 512 KiB")
            body = valid_body(self.rfile.read(length) if length > 0 else b"")
            if url.path == "/notes/drafts":
                out = self._notes(notes_argv(OSA_CREATE, body))
            elif url.path == "/notes/drafts/note":
                out = self._notes(notes_argv(OSA_UPDATE, valid_note_id(q.get("id")), body))
            else:
                self._send(404, b"POST endpoints: /notes/drafts /notes/drafts/note\n")
                return
            if out is not None:
                self._send(200, json.dumps({"id": out.strip()}).encode(), "application/json")
        except BadRequest as exc:
            self._send(400, (str(exc) + "\n").encode())
        except ValueError:
            self._send(400, b"bad Content-Length\n")
        except subprocess.TimeoutExpired:
            self._send(504, b"Notes did not answer in time\n")

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
