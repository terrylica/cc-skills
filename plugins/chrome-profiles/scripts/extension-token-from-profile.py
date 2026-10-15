"""Read the Playwright Extension's auth token from a Chrome profile, so `chrome-profile.sh setup` needs no copy-paste.

The extension keeps its token in its own origin's localStorage under the key `auth-token` (lib/ui/authToken.js) and
creates it the first time its status page opens. Chrome stores localStorage in LevelDB with Snappy-compressed blocks,
so a text search finds the record only sometimes; this uses CCL Group's ccl_chromium_reader, the reference parser.
It reads a temporary COPY of the profile's Local Storage, never Chrome's live files.

Usage: uv run --no-project --with "ccl_chromium_reader @ git+https://github.com/cclgroupltd/ccl_chromium_reader" \
         python -I extension-token-from-profile.py <profile-dir> [--emit]
Without --emit it prints only the number of live records and the token's length; with --emit it writes the bare
token to stdout for piping straight into a secret store. Exit 1 when no token exists yet.
"""
import os
import pathlib
import shutil
import sys
import tempfile

from ccl_chromium_reader import ccl_chromium_localstorage as ls

ROOT = os.environ.get("CHROME_USER_DATA_DIR") or os.path.expanduser("~/Library/Application Support/Google/Chrome")
ORIGIN = "chrome-extension://" + os.environ.get("EXT_ID", "mmlmfjhmonkocbjadbfplnigmagldckm")

profile, emit = sys.argv[1], "--emit" in sys.argv[2:]
with tempfile.TemporaryDirectory() as td:
    copy = pathlib.Path(td) / "leveldb"
    shutil.copytree(pathlib.Path(ROOT) / profile / "Local Storage" / "leveldb", copy, ignore=shutil.ignore_patterns("LOCK"))
    db = ls.LocalStoreDb(copy)
    records = sorted(
        (r for r in db.iter_records_for_storage_key(ORIGIN) if r.script_key == "auth-token" and r.is_live),
        key=lambda r: r.leveldb_seq_number,
    )
    token = records[-1].value if records else ""
    db.close()

if not token:
    sys.exit(1)
if emit:
    sys.stdout.write(token)
else:
    print(f"{profile}: live auth-token records {len(records)}, length {len(token)}")
