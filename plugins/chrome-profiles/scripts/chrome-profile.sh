#!/usr/bin/env bash
# chrome-profile — let Claude Code drive ONE profile of your everyday Google Chrome, chosen by its ACCOUNT EMAIL.
#
#   chrome-profile.sh setup <email> [--name <server>]  # one-time: everything needed for no-click automation of that profile
#   chrome-profile.sh setup-main                       # one-time: the auto-connect server for the whole everyday Chrome
#   chrome-profile.sh doctor [<email>]                 # check Chrome, the debug toggle, every browser MCP registration
#   chrome-profile.sh resolve <email>                  # print the profile directory ("Profile 7"), or fail
#   chrome-profile.sh open <email> <url>               # open <url> in that profile of the RUNNING Chrome
#   chrome-profile.sh extension-status                 # which profiles have the Playwright Extension
#   chrome-profile.sh playwright-mcp <email>           # the MCP server command that `setup` registers
#
# macOS + Google Chrome. Doctrine and the reasons behind every rule: ../skills/browser-automation/.
#
# WHY BY EMAIL. Chrome names profile folders itself ("Default", "Profile 7") and the names differ per machine and
# change when a profile is rebuilt. A server pinned to a folder name silently ends up driving a different account.
# Resolving the email at every start, and refusing on zero or several matches, makes that impossible.
#
# NOTHING HERE LAUNCHES CHROME WITH A DEBUG FLAG. `open` hands a URL to the already-running Chrome, as clicking a
# link does. Attaching is done by the MCP servers: Microsoft's Playwright Extension inside the chosen profile, or
# Chrome's own opt-in at chrome://inspect/#remote-debugging.
#
# THE EXTENSION TOKEN is per profile. It is kept in the macOS login Keychain (service "playwright-extension-token",
# account = the email), or in a `vault` CLI scope "chrome-extension-tokens" if one exists, and handed to the one MCP
# process through its environment. It is never written to ~/.claude.json, never put on a command line, and never
# printed.
set -euo pipefail

ROOT="${CHROME_USER_DATA_DIR:-$HOME/Library/Application Support/Google/Chrome}"
CHROME_BIN="${CHROME_BIN:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"
EXT_ID="mmlmfjhmonkocbjadbfplnigmagldckm"   # Microsoft's "Playwright Extension", Chrome Web Store
EXT_URL="https://chromewebstore.google.com/detail/playwright-extension/$EXT_ID"
KC_SERVICE="playwright-extension-token"
VAULT_SCOPE="chrome-extension-tokens"
SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"

die() { printf '✗ %s\n' "$*" >&2; exit 1; }
say() { printf '→ %s\n' "$*"; }

resolve() {
  local email="$1"
  [ -n "$email" ] || die "an account email is required"
  [ -f "$ROOT/Local State" ] || die "no Chrome data at $ROOT — is Google Chrome installed and opened once?"
  python3 - "$ROOT/Local State" "$email" <<'EOF'
import json, sys
path, email = sys.argv[1], sys.argv[2].lower()
cache = json.load(open(path))["profile"]["info_cache"]
hits = sorted(d for d, v in cache.items() if (v.get("user_name") or "").lower() == email)
if len(hits) != 1:
    sys.stderr.write(f"✗ {len(hits)} Chrome profiles are signed in as {email} (need exactly 1)\n")
    sys.exit(1)
print(hits[0])
EOF
}

token_key() { printf '%s' "$1" | tr '@.' '__'; }

token_get() {
  local email="$1" t=""
  if command -v vault >/dev/null 2>&1; then
    t=$(vault get "$VAULT_SCOPE" "$(token_key "$email")" 2>/dev/null) || t=""
  fi
  if [ -z "$t" ]; then
    t=$(security find-generic-password -s "$KC_SERVICE" -a "$email" -w 2>/dev/null) || t=""
  fi
  # The extension shows the token as "PLAYWRIGHT_MCP_EXTENSION_TOKEN=<token>"; copying that whole line is natural.
  printf '%s' "${t#PLAYWRIGHT_MCP_EXTENSION_TOKEN=}"
}

# Store a token without it ever touching argv: `security -i` reads its command from stdin, value hex-encoded (-X).
token_put() {
  local email="$1" value="$2" hex
  value="${value#PLAYWRIGHT_MCP_EXTENSION_TOKEN=}"
  value="$(printf '%s' "$value" | tr -d '[:space:]')"
  [ -n "$value" ] || die "empty token"
  hex=$(printf '%s' "$value" | xxd -p | tr -d '\n')
  printf 'add-generic-password -U -s %s -a %s -X %s\n' "$KC_SERVICE" "$email" "$hex" | security -i >/dev/null
}

# A native hidden-input dialog, so the token is pasted into macOS, not into a chat or a terminal history.
prompt_hidden() {
  osascript -e "text returned of (display dialog \"$1\" default answer \"\" with hidden answer with title \"chrome-profile\")" 2>/dev/null
}

stable_self() {
  # Plugin files under ~/.claude/plugins/cache/ are versioned and replaced on update; the marketplace checkout is not.
  local mp="$HOME/.claude/plugins/marketplaces/cc-skills/plugins/chrome-profiles/scripts/chrome-profile.sh"
  case "$SELF" in */plugins/cache/*) [ -f "$mp" ] && { printf '%s' "$mp"; return; } ;; esac
  printf '%s' "$SELF"
}

# ON-DEMAND MODE. Claude Code starts its own copy of every user-scope MCP server in every session, and a browser
# server holds 0.1-0.9 GB (measured: 7.8 of 12.3 GB across 9 sessions, 2026-10-06). When an on-demand file exists
# (default ~/.claude/mcp-browser.json, or CHROME_PROFILES_MCP_CONFIG), servers are registered there instead and load
# only in a session started with `claude --mcp-config <file>`; a same-named user-scope entry is removed so the server
# is never started twice. Without such a file, registration stays user scope, exactly as before.
MCP_ON_DEMAND_FILE="${CHROME_PROFILES_MCP_CONFIG:-$HOME/.claude/mcp-browser.json}"

register_mcp() {
  local name="$1" json="$2"
  if [ -n "${CHROME_PROFILES_MCP_CONFIG:-}" ] || [ -f "$MCP_ON_DEMAND_FILE" ]; then
    python3 - "$MCP_ON_DEMAND_FILE" "$name" "$json" <<'EOF'
import json, os, sys, tempfile
path, name, spec = sys.argv[1], sys.argv[2], json.loads(sys.argv[3])
d = json.load(open(path)) if os.path.exists(path) else {}
d.setdefault("mcpServers", {})[name] = spec
fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path) or ".", prefix=".mcp-on-demand.", suffix=".tmp")
with os.fdopen(fd, "w") as f:
    f.write(json.dumps(d, indent=2) + "\n")
os.chmod(tmp, 0o600)
os.replace(tmp, path)
EOF
    if python3 -c 'import json,os,sys; p=os.path.expanduser("~/.claude.json"); sys.exit(0 if sys.argv[1] in ((json.load(open(p)).get("mcpServers") or {}) if os.path.exists(p) else {}) else 1)' "$name"; then
      if command -v claude >/dev/null 2>&1 && claude mcp remove --scope user "$name" >/dev/null 2>&1; then
        say "removed the user-scope '$name' so it no longer starts in every session"
      else
        say "'$name' is ALSO registered for every session; remove it: claude mcp remove --scope user $name"
      fi
    fi
    say "registered MCP server '$name' ON DEMAND in $MCP_ON_DEMAND_FILE; load it with: claude --mcp-config $MCP_ON_DEMAND_FILE"
    return
  fi
  # User scope. Prefer the official CLI; fall back to editing ~/.claude.json (backed up first) when a wrapper named
  # `claude` refuses management subcommands.
  if command -v claude >/dev/null 2>&1 && claude mcp add-json --scope user "$name" "$json" >/dev/null 2>&1; then
    say "registered MCP server '$name' (claude mcp add-json)"
    return
  fi
  python3 - "$name" "$json" <<'EOF'
import json, os, shutil, sys, time
name, spec = sys.argv[1], json.loads(sys.argv[2])
p = os.path.expanduser("~/.claude.json")
d = json.load(open(p)) if os.path.exists(p) else {}
if os.path.exists(p):
    shutil.copy2(p, f"{p}.bak-{time.strftime('%Y%m%dT%H%M%S')}")
d.setdefault("mcpServers", {})[name] = spec
tmp = p + ".tmp"
with open(tmp, "w") as f:
    json.dump(d, f, indent=2)
os.chmod(tmp, 0o600)
os.replace(tmp, p)
EOF
  say "registered MCP server '$name' (wrote ~/.claude.json; a backup sits beside it)"
}

wait_for() {  # wait_for <seconds> <test-command...>
  local secs="$1"; shift
  local i=0
  until "$@"; do
    i=$((i + 2)); [ "$i" -ge "$secs" ] && return 1
    sleep 2
  done
}

cmd="${1:-}"; shift || true
case "$cmd" in
  resolve)
    resolve "${1:-}" ;;

  open)
    email="${1:-}"; url="${2:-}"
    [ -n "$url" ] || die "usage: open <email> <url>"
    dir=$(resolve "$email")
    pgrep -xq "Google Chrome" || die "Chrome is not running; start it normally first (no flags)"
    "$CHROME_BIN" --profile-directory="$dir" "$url" >/dev/null 2>&1 &
    say "opened in $dir ($email): $url" ;;

  playwright-mcp)
    email="${1:-}"
    dir=$(resolve "$email")
    [ -d "$ROOT/$dir/Extensions/$EXT_ID" ] || die "the Playwright Extension is not installed in $dir ($email) — run: $(basename "$0") setup $email"
    tok=$(token_get "$email")
    if [ -n "$tok" ]; then export PLAYWRIGHT_MCP_EXTENSION_TOKEN="$tok"; fi
    unset tok
    exec npx -y @playwright/mcp@latest --extension --profile-dir-name "$dir" ;;

  setup)
    email="${1:-}"; shift || true
    name=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --name) name="${2:-}"; shift 2 ;;
        *) die "unknown argument: $1" ;;
      esac
    done
    dir=$(resolve "$email")
    [ -n "$name" ] || name="chrome-$(printf '%s' "${email%@*}" | tr -c '[:alnum:]\n' '-' | tr '[:upper:]' '[:lower:]')"
    say "$email is $dir; MCP server name: $name"
    pgrep -xq "Google Chrome" || die "start Google Chrome normally first"

    if [ ! -d "$ROOT/$dir/Extensions/$EXT_ID" ]; then
      say "installing the Playwright Extension: click 'Add to Chrome' in the window that opens (only this profile)"
      "$CHROME_BIN" --profile-directory="$dir" "$EXT_URL" >/dev/null 2>&1 &
      wait_for 600 test -d "$ROOT/$dir/Extensions/$EXT_ID" || die "the extension did not appear in $dir within 10 minutes"
      say "extension installed"
    else
      say "extension already installed in $dir"
    fi

    if [ -z "$(token_get "$email")" ]; then
      say "opening the extension's status page: copy the token it shows"
      "$CHROME_BIN" --profile-directory="$dir" "chrome-extension://$EXT_ID/status.html" >/dev/null 2>&1 &
      sleep 2
      tok=$(prompt_hidden "Paste the Playwright Extension token for $email (the part after PLAYWRIGHT_MCP_EXTENSION_TOKEN= is enough):") || tok=""
      token_put "$email" "$tok"
      unset tok
      say "token stored in the login Keychain (service $KC_SERVICE)"
    else
      say "token already stored"
    fi

    path=$(stable_self)
    spec=$(python3 -c 'import json,sys; print(json.dumps({"type":"stdio","command":"bash","args":[sys.argv[1],"playwright-mcp",sys.argv[2]],"env":{}}))' "$path" "$email")
    register_mcp "$name" "$spec"
    say "done. Restart Claude Code so '$name' loads, then: $(basename "$0") doctor $email" ;;

  setup-main)
    spec=$(python3 -c 'import json,sys; print(json.dumps({"type":"stdio","command":"npx","args":["-y","chrome-devtools-mcp@latest","--autoConnect","--channel","stable","--userDataDir",sys.argv[1],"--no-usage-statistics"],"env":{}}))' "$ROOT")
    register_mcp "chrome-main" "$spec"
    "$CHROME_BIN" "chrome://inspect/#remote-debugging" >/dev/null 2>&1 &
    say "now tick 'Allow remote debugging' on the chrome://inspect page that opened (once), and restart Claude Code" ;;

  extension-status)
    python3 - "$ROOT" "$EXT_ID" <<'EOF'
import json, os, sys
root, ext = sys.argv[1], sys.argv[2]
cache = json.load(open(os.path.join(root, "Local State")))["profile"]["info_cache"]
missing = [(d, v.get("user_name") or "(not signed in)") for d, v in sorted(cache.items())
           if not os.path.isdir(os.path.join(root, d, "Extensions", ext))]
print(f"Playwright Extension in {len(cache) - len(missing)} of {len(cache)} profiles")
for d, who in missing:
    print(f"  missing: {d}  {who}")
EOF
    ;;

  doctor)
    email="${1:-}"
    rc=0
    ok()   { printf '  ✓ %s\n' "$*"; }
    warn() { printf '  ⚠ %s\n' "$*"; }
    bad()  { printf '  ✗ %s\n' "$*"; rc=1; }

    echo "Chrome"
    have=$("$CHROME_BIN" --version 2>/dev/null | awk '{print $3}') || have=""
    plat=mac; [ "$(uname -m)" = arm64 ] && plat=mac_arm64
    latest=$(curl -s --noproxy '*' --max-time 10 \
      "https://versionhistory.googleapis.com/v1/chrome/platforms/$plat/channels/stable/versions?pageSize=1" \
      | python3 -c 'import json,sys; print(json.load(sys.stdin)["versions"][0]["version"])' 2>/dev/null) || latest=""
    if [ -z "$have" ]; then bad "Chrome not found at $CHROME_BIN"
    elif [ -z "$latest" ]; then warn "installed $have; could not read the latest stable version"
    elif [ "$have" = "$latest" ]; then ok "installed $have = latest stable"
    else
      # Google lists a release as soon as its STAGED rollout starts; a given Mac may not be offered it for days.
      # Ask the update server what it will hand THIS machine before telling anyone to relaunch.
      offered=$(python3 - "$have" "$(uname -m)" <<'EOF' 2>/dev/null
import json, sys, urllib.request, uuid
have, arch = sys.argv[1], ("arm64" if sys.argv[2] == "arm64" else "x64")
body = {"request": {"@os": "mac", "@updater": "updater", "protocol": "3.1", "ismachine": True,
  "acceptformat": "crx3,download,puff,run,xz,zucc", "requestid": "{%s}" % uuid.uuid4(), "arch": arch,
  "os": {"platform": "Mac OS X", "arch": arch},
  "app": [{"appid": "com.google.Chrome", "version": have, "installsource": "ondemand",
           "enabled": True, "updatecheck": {}}]}}
req = urllib.request.Request("https://update.googleapis.com/service/update2/json", data=json.dumps(body).encode(),
  headers={"Content-Type": "application/json", "X-Goog-Update-Interactivity": "fg", "X-Goog-Update-AppId": "com.google.Chrome"})
raw = urllib.request.urlopen(req, timeout=20).read().decode()
uc = json.loads(raw[raw.index("{"):])["response"]["app"][0].get("updatecheck", {})
print(uc.get("nextversion") or uc.get("status") or "?")
EOF
) || offered=""
      case "$offered" in
        noupdate) ok "installed $have; $latest is in staged rollout and not yet offered to this Mac — Chrome updates itself" ;;
        ""|"?")   warn "installed $have, latest stable listed is $latest; could not ask the update server" ;;
        *)        warn "installed $have; the update server offers $offered — chrome://settings/help, then Relaunch" ;;
      esac
    fi
    major=${have%%.*}
    if [ -n "$major" ] && [ "$major" -lt 144 ]; then bad "Chrome $have is older than 144: auto-connect needs 144+"; fi

    echo "Remote debugging (chrome://inspect/#remote-debugging)"
    if [ -f "$ROOT/DevToolsActivePort" ]; then
      port=$(awk 'NR==1' "$ROOT/DevToolsActivePort")
      listen=$(lsof -nP -iTCP:"$port" -sTCP:LISTEN 2>/dev/null) || listen=""
      case "$listen" in
        *Google*) ok "ON, Chrome is listening on 127.0.0.1:$port" ;;
        *) warn "DevToolsActivePort names port $port but nothing listens — Chrome closed, or the toggle is off" ;;
      esac
    else
      warn "OFF — needed only by chrome-main: open chrome://inspect/#remote-debugging and tick 'Allow remote debugging'"
    fi

    echo "MCP registrations (~/.claude.json = every session; $MCP_ON_DEMAND_FILE = on demand via --mcp-config)"
    python3 - "$ROOT" "$EXT_ID" "$MCP_ON_DEMAND_FILE" <<'EOF' || rc=1
import json, os, sys
root, ext, ondemand = sys.argv[1], sys.argv[2], sys.argv[3]
def servers(path):
    return (json.load(open(path)).get("mcpServers") or {}) if os.path.exists(path) else {}
user = servers(os.path.expanduser("~/.claude.json"))
lazy = servers(ondemand)
cache = json.load(open(os.path.join(root, "Local State")))["profile"]["info_cache"]
rc = 0
def say(sym, msg):
    global rc
    print(f"  {sym} {msg}")
    if sym == "✗": rc = 1
for n in sorted(set(user) & set(lazy)):
    say("⚠", f"{n}: registered for every session AND on demand; remove the user-scope copy: claude mcp remove --scope user {n}")
cfg = {**lazy, **user}
where = {n: ("every session" if n in user else "on demand") for n in cfg}
browserish = [n for n, v in user.items() if any(k in " ".join([v.get("command", "")] + v.get("args", [])) for k in ("chrome-devtools-mcp", "@playwright/mcp", "playwright-mcp"))]
if browserish and os.path.exists(ondemand):
    say("⚠", f"browser servers start in EVERY session ({', '.join(sorted(browserish))}); each holds 0.1-0.9 GB — move them to {ondemand}")
for n in sorted(cfg):
    print(f"  · {n}: {where[n]}")
auto = [n for n, v in cfg.items() if "chrome-devtools-mcp" in " ".join(v.get("args", [])) and "--autoConnect" in v.get("args", [])]
for n in auto:
    a = cfg[n].get("args", [])
    say("✓" if "--userDataDir" in a else "✗", f"{n}: --autoConnect" + (" with explicit --userDataDir" if "--userDataDir" in a else " WITHOUT --userDataDir (can hang; rerun setup-main)"))
if not auto:
    say("⚠", "no auto-connect server (optional): chrome-profile.sh setup-main")
for n, v in sorted(cfg.items()):
    if "--browser-url" in " ".join(v.get("args", [])) and "chrome-devtools-mcp" in " ".join(v.get("args", [])):
        say("⚠", f"{n}: --browser-url reaches only a Chrome started on a separate --user-data-dir, never the everyday Chrome")
for n, v in sorted(cfg.items()):
    a = v.get("args", [])
    if "--extension" in a and "--profile-dir-name" in a:
        d = a[a.index("--profile-dir-name") + 1]
        who = (cache.get(d) or {}).get("user_name") or "NOBODY"
        say("⚠", f"{n}: hard-pinned to {d} = {who}; folder names drift — re-register with: chrome-profile.sh setup {who if who != 'NOBODY' else '<email>'}")
    elif "--extension" in a:
        say("✗", f"{n}: --extension without a profile pin connects to the LAST-USED profile")
    # A throwaway @playwright/mcp (no --extension) opens a VISIBLE, signed-out Chrome window per Claude
    # session on its first tool call, and its tools share names with the signed-in extension servers,
    # so a session wanting the signed-in profile can pick it by mistake and leave a blank window behind.
    elif any("@playwright/mcp" in x for x in a):
        problems = [p for p, ok_ in (("--headless", "--headless" in a), ("--isolated", "--isolated" in a)) if not ok_]
        if problems:
            say("⚠", f"{n}: throwaway Playwright without {' '.join(problems)} opens a visible signed-out window per session; add them")
        if "throwaway" not in n:
            say("⚠", f"{n}: name it so it cannot be mistaken for a signed-in server (e.g. playwright-throwaway-headless)")
    if "playwright-mcp" in a and any(x.endswith("chrome-profile.sh") for x in [v.get("command", "")] + a):
        i = a.index("playwright-mcp")
        email = a[i + 1] if len(a) > i + 1 else ""
        hits = [d for d, c in cache.items() if (c.get("user_name") or "").lower() == email.lower()]
        if len(hits) != 1:
            say("✗", f"{n}: {email} matches {len(hits)} profiles")
        else:
            inst = os.path.isdir(os.path.join(root, hits[0], "Extensions", ext))
            say("✓" if inst else "⚠", f"{n}: {email} → {hits[0]}; extension {'installed' if inst else 'NOT installed yet'}")
sys.exit(rc)
EOF

    if [ -n "$email" ]; then
      echo "Target profile"
      if dir=$(resolve "$email" 2>/dev/null); then
        ok "$email → $dir"
        if [ -n "$(token_get "$email")" ]; then ok "extension token stored"; else warn "no extension token stored — run setup $email"; fi
        # Look-alikes: other extensions with "Playwright" in the name are not the one the MCP server talks to.
        python3 - "$ROOT/$dir/Extensions" "$EXT_ID" <<'EOF' || true
import glob, json, os, sys
base, want = sys.argv[1], sys.argv[2]
for m in glob.glob(os.path.join(base, "*", "*", "manifest.json")):
    eid = m.split(os.sep)[-3]
    try: name = str(json.load(open(m)).get("name", ""))
    except Exception: continue
    if eid != want and "playwright" in name.lower():
        print(f"  ⚠ look-alike installed here: '{name}' ({eid}) — NOT the one the MCP server uses ({want})")
EOF
      else bad "$email is not signed in to exactly one Chrome profile"; fi
    fi
    exit "$rc" ;;

  *)
    sed -n '2,10p' "$0"; exit 2 ;;
esac
