"""Shared helpers for the M3 verify scripts (m3-probe / m3-context-probe / m3-bench / m3-verify).

Key acquisition mirrors scripts/minimax-check-upgrade:
  1. MINIMAX_API_KEY env var (if set, used directly)
  2. `op read` with MINIMAX_API_KEY_OP_PATH + MINIMAX_OP_ACCOUNT (1Password CLI)
  3. raise

Run via:  uv run --python 3.14 --with requests[,pillow] python scripts/<name>.py
Proxy is bypassed (Session.trust_env = False) — MiniMax 502s through the local proxy.
"""

import os
import subprocess

import requests

BASE = "https://api.minimax.io/v1"
# Model is read dynamically from the SSoT (MINIMAX_MODEL env, set by
# ~/.config/mise/config.toml) so consumers always track the current model and no
# prior version is ever pinned in code. Falls back to the GA model if unset.
MODEL = os.environ.get("MINIMAX_MODEL", "MiniMax-M3")

# Exceptions worth catching around a live API call (network + JSON decode).
# Centralized so probe scripts narrow their excepts instead of using inline ignores.
NET_ERRORS = (requests.RequestException, ValueError)

_OP_PATH_DEFAULT = "op://ggk4orq7rmcm7jinsb4ahygv7e/e54cb3ujopexslaq7loywpuycm/password"
_OP_ACCOUNT_DEFAULT = "K5BH72Z7O5BYXOGKBYT5FWTP2E"


def get_key() -> str:
    """Resolve the MiniMax API key from env or 1Password. Raises on failure."""
    key = os.environ.get("MINIMAX_API_KEY") or os.environ.get("MINIMAX_KEY")
    if key:
        return key.strip()
    op_path = os.environ.get("MINIMAX_API_KEY_OP_PATH", _OP_PATH_DEFAULT)
    op_account = os.environ.get("MINIMAX_OP_ACCOUNT", _OP_ACCOUNT_DEFAULT)
    env = {k: v for k, v in os.environ.items() if "PROXY" not in k.upper()}
    out = subprocess.run(
        ["op", "read", op_path, "--account", op_account],
        capture_output=True, text=True, env=env, check=False,
    )
    if out.returncode != 0 or not out.stdout.strip():
        raise RuntimeError(
            "Could not resolve MiniMax API key. Set MINIMAX_API_KEY, or configure the 1Password "
            f"op-path (MINIMAX_API_KEY_OP_PATH={op_path}). op stderr: {out.stderr.strip()[:160]}"
        )
    return out.stdout.strip()


def session() -> requests.Session:
    s = requests.Session()
    s.trust_env = False  # bypass *_PROXY env (MiniMax 502s through the local proxy)
    return s


def err_of(j: dict):
    """Return a human error string or None. MiniMax uses HTTP 200 + base_resp.status_code."""
    if "error" in j and j["error"]:
        return j["error"].get("message")
    code = (j.get("base_resp") or {}).get("status_code", 0)
    if code not in (0,):
        return f"{code}: {(j.get('base_resp') or {}).get('status_msg')}"
    return None
