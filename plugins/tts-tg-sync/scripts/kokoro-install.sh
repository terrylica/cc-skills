#!/usr/bin/env bash
# Kokoro TTS Engine Manager — DELEGATING WRAPPER (SSoT lives in the kokoro-tts plugin).
#
# tts-tg-sync does NOT own the Kokoro installer. Per this plugin's CLAUDE.md,
# "the Kokoro TTS engine itself is managed by the kokoro-tts plugin." tts-tg-sync
# declares `requires: [kokoro-tts]` in the marketplace, and both plugins install
# under the SAME marketplace root, so the kokoro-tts installer is always a sibling
# directory away. We exec it verbatim so there is exactly ONE implementation to
# maintain (previously this was a byte-for-byte 206-line copy that could drift).
#
# Usage (forwarded unchanged): --install | --upgrade | --health | --uninstall
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# here = <marketplace>/plugins/tts-tg-sync/scripts  →  ../../kokoro-tts/scripts
canonical="${here}/../../kokoro-tts/scripts/kokoro-install.sh"

if [ ! -f "${canonical}" ]; then
    echo "[kokoro-install] ERROR: canonical installer not found at ${canonical}" >&2
    echo "[kokoro-install] The kokoro-tts plugin must be installed (tts-tg-sync requires it)." >&2
    echo "[kokoro-install] Install it: claude plugin install kokoro-tts@cc-skills" >&2
    exit 1
fi

exec bash "${canonical}" "$@"
