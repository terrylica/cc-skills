#!/bin/bash
# Kokoro TTS Engine Manager — install, upgrade, health, uninstall, migrate
# Manages Python venv at ~/.local/share/kokoro/ (XDG-compliant)
#
# Usage:
#   kokoro-install.sh --install    # Fresh install (venv + deps + model + MPS verify)
#   kokoro-install.sh --upgrade    # Upgrade deps + re-download model
#   kokoro-install.sh --health     # Health check (venv, MPS, model, script)
#   kokoro-install.sh --uninstall  # Remove venv (keeps model cache)
#   kokoro-install.sh --migrate    # Migrate from ~/fork-tools/kokoro/

set -euo pipefail

# --- Configuration ---
KOKORO_DIR="${KOKORO_DIR:-${HOME}/.local/share/kokoro}"
KOKORO_VENV="${KOKORO_DIR}/.venv"
KOKORO_PYTHON="${KOKORO_VENV}/bin/python"
KOKORO_SCRIPT="${KOKORO_DIR}/tts_generate.py"
VERSION_FILE="${KOKORO_DIR}/version.json"
LEGACY_DIR="${HOME}/fork-tools/kokoro"

# Script directory (for bundled tts_generate.py)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUNDLED_SCRIPT="${SCRIPT_DIR}/tts_generate.py"

# Python deps
KOKORO_VERSION="0.9.4"

log() { echo "[kokoro-install] $(date '+%H:%M:%S') $*"; }
error() { echo "[kokoro-install] ERROR: $*" >&2; }

# --- Install ---
do_install() {
    log "Installing Kokoro TTS engine to ${KOKORO_DIR}"

    # Prerequisites
    if ! command -v uv &>/dev/null; then
        error "uv not found. Install: brew install uv"
        exit 1
    fi

    # Create directory
    mkdir -p "${KOKORO_DIR}"

    # Create venv with Python 3.13
    log "Creating Python 3.13 venv..."
    uv venv --python 3.13 "${KOKORO_VENV}"

    # Install deps
    log "Installing dependencies..."
    uv pip install --python "${KOKORO_PYTHON}" \
        pip \
        "kokoro==${KOKORO_VERSION}" \
        "misaki[en]>=0.9.4" \
        torch soundfile numpy transformers huggingface_hub loguru

    # Copy tts_generate.py
    if [[ -f "${BUNDLED_SCRIPT}" ]]; then
        log "Copying tts_generate.py from plugin bundle..."
        cp "${BUNDLED_SCRIPT}" "${KOKORO_SCRIPT}"
    elif [[ -f "${LEGACY_DIR}/tts_generate.py" ]]; then
        log "Copying tts_generate.py from legacy fork..."
        cp "${LEGACY_DIR}/tts_generate.py" "${KOKORO_SCRIPT}"
    else
        error "tts_generate.py not found in bundle or legacy location"
        exit 1
    fi

    # Download model
    log "Downloading Kokoro-82M model (first run may take a minute)..."
    "${KOKORO_PYTHON}" -c "from kokoro import KPipeline; KPipeline('en-us', repo_id='hexgrad/Kokoro-82M')"

    # Verify MPS
    log "Verifying Apple Silicon MPS..."
    "${KOKORO_PYTHON}" -c "import torch; assert torch.backends.mps.is_available(), 'MPS not available'"

    # Write version.json
    local torch_ver
    torch_ver=$("${KOKORO_PYTHON}" -c "import torch; print(torch.__version__)")
    cat > "${VERSION_FILE}" <<VJSON
{
  "kokoro": "${KOKORO_VERSION}",
  "torch": "${torch_ver}",
  "python": "3.13",
  "installed_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "source": "kokoro-install.sh --install",
  "venv_path": "${KOKORO_VENV}"
}
VJSON

    log "Installation complete. Run --health to verify."
}

# --- Upgrade ---
do_upgrade() {
    log "Upgrading Kokoro TTS engine..."

    if [[ ! -d "${KOKORO_VENV}" ]]; then
        error "Venv not found at ${KOKORO_VENV}. Run --install first."
        exit 1
    fi

    uv pip install --python "${KOKORO_PYTHON}" --upgrade \
        kokoro torch soundfile numpy transformers huggingface_hub loguru "misaki[en]"

    # Re-copy tts_generate.py from bundle
    if [[ -f "${BUNDLED_SCRIPT}" ]]; then
        cp "${BUNDLED_SCRIPT}" "${KOKORO_SCRIPT}"
        log "Updated tts_generate.py from plugin bundle"
    fi

    # Re-download model
    log "Re-downloading model..."
    "${KOKORO_PYTHON}" -c "from kokoro import KPipeline; KPipeline('en-us', repo_id='hexgrad/Kokoro-82M')"

    # Update version.json
    local torch_ver kokoro_ver
    torch_ver=$("${KOKORO_PYTHON}" -c "import torch; print(torch.__version__)")
    kokoro_ver=$("${KOKORO_PYTHON}" -c "import kokoro; print(kokoro.__version__)" 2>/dev/null || echo "${KOKORO_VERSION}")
    cat > "${VERSION_FILE}" <<VJSON
{
  "kokoro": "${kokoro_ver}",
  "torch": "${torch_ver}",
  "python": "3.13",
  "upgraded_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "source": "kokoro-install.sh --upgrade",
  "venv_path": "${KOKORO_VENV}"
}
VJSON

    log "Upgrade complete."
}

# --- Health ---
do_health() {
    local ok=0 fail=0

    check() {
        local name="$1" cmd="$2"
        if eval "$cmd" &>/dev/null; then
            echo "  [OK] $name"
            ok=$((ok + 1))
        else
            echo "  [FAIL] $name"
            fail=$((fail + 1))
        fi
    }

    echo "=== Kokoro TTS Health Check ==="
    check "Venv exists"          "[[ -d '${KOKORO_VENV}' ]]"
    check "Python executable"    "[[ -x '${KOKORO_PYTHON}' ]]"
    check "tts_generate.py"      "[[ -f '${KOKORO_SCRIPT}' ]]"
    check "kokoro importable"    "'${KOKORO_PYTHON}' -c 'import kokoro'"
    check "torch importable"     "'${KOKORO_PYTHON}' -c 'import torch'"
    check "MPS available"        "'${KOKORO_PYTHON}' -c 'import torch; assert torch.backends.mps.is_available()'"
    check "Model cached"         "'${KOKORO_PYTHON}' -c 'from kokoro import KPipeline; KPipeline(\"en-us\", repo_id=\"hexgrad/Kokoro-82M\")'"
    check "version.json exists"  "[[ -f '${VERSION_FILE}' ]]"

    echo ""
    echo "Results: ${ok} passed, ${fail} failed"

    if [[ -f "${VERSION_FILE}" ]]; then
        echo ""
        echo "Version info:"
        cat "${VERSION_FILE}"
    fi

    [[ "$fail" -eq 0 ]]
}

# --- Uninstall ---
do_uninstall() {
    log "Removing Kokoro TTS engine from ${KOKORO_DIR}"

    if [[ ! -d "${KOKORO_DIR}" ]]; then
        log "Nothing to remove — ${KOKORO_DIR} does not exist"
        exit 0
    fi

    # Remove venv and script (keep model cache in ~/.cache/huggingface/)
    rm -rf "${KOKORO_VENV}"
    rm -f "${KOKORO_SCRIPT}" "${VERSION_FILE}"

    # Remove dir if empty
    rmdir "${KOKORO_DIR}" 2>/dev/null || true

    log "Removed. Model cache at ~/.cache/huggingface/ preserved."
    log "To also remove model cache: rm -rf ~/.cache/huggingface/hub/models--hexgrad--Kokoro-82M"
}

# --- Migrate ---
do_migrate() {
    log "Migration: ~/fork-tools/kokoro/ → ~/.local/share/kokoro/"

    if [[ ! -d "${LEGACY_DIR}" ]]; then
        log "No legacy installation found at ${LEGACY_DIR}"
        log "Run --install for a fresh installation."
        exit 0
    fi

    if [[ -d "${KOKORO_VENV}" ]]; then
        log "XDG installation already exists at ${KOKORO_DIR}"
        log "Run --health to verify, or --uninstall then --install to rebuild."
        exit 0
    fi

    log "Found legacy installation at ${LEGACY_DIR}"
    log "This will create a new venv at ${KOKORO_DIR} and copy tts_generate.py."
    log "The legacy dir at ${LEGACY_DIR} will NOT be deleted (it's a git repo)."
    echo ""

    do_install

    log "Migration complete."
    log "Update mise.toml:"
    log "  KOKORO_VENV = \"{{env.HOME}}/.local/share/kokoro/.venv\""
    log "  KOKORO_SCRIPT = \"{{env.HOME}}/.local/share/kokoro/tts_generate.py\""
}

# --- Main ---
case "${1:-}" in
    --install)   do_install ;;
    --upgrade)   do_upgrade ;;
    --health)    do_health ;;
    --uninstall) do_uninstall ;;
    --migrate)   do_migrate ;;
    *)
        echo "Usage: kokoro-install.sh [--install|--upgrade|--health|--uninstall|--migrate]"
        exit 1
        ;;
esac
