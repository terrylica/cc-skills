#!/bin/bash
# Kokoro TTS Engine Manager — install, upgrade, health, uninstall
# Manages Python venv at ~/.local/share/kokoro/ (XDG-compliant)
# Backend: MLX-Audio on Apple Silicon (no PyTorch/ONNX fallback)
# GitHub Issue: https://github.com/terrylica/claude-config/issues/62
#
# Usage:
#   kokoro-install.sh --install    # Fresh install (venv + mlx-audio + model + verify)
#   kokoro-install.sh --upgrade    # Upgrade deps + re-download model
#   kokoro-install.sh --health     # Health check (venv, mlx_audio, model, scripts)
#   kokoro-install.sh --uninstall  # Remove venv (keeps model cache)

set -euo pipefail

# --- Configuration ---
KOKORO_DIR="${KOKORO_DIR:-${HOME}/.local/share/kokoro}"
KOKORO_VENV="${KOKORO_DIR}/.venv"
KOKORO_PYTHON="${KOKORO_VENV}/bin/python"
VERSION_FILE="${KOKORO_DIR}/version.json"

# Script directory (for bundled scripts)
SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0" 2>/dev/null || echo "$0")")" && pwd)"

log() { echo "[kokoro-install] $(date '+%H:%M:%S') $*"; }
error() { echo "[kokoro-install] ERROR: $*" >&2; }

# --- Install ---
do_install() {
    # Require Apple Silicon
    if [[ "$(uname -s)" != "Darwin" || "$(uname -m)" != "arm64" ]]; then
        error "Kokoro TTS requires macOS Apple Silicon (M1+). Detected: $(uname -s) $(uname -m)"
        exit 1
    fi

    log "Installing Kokoro TTS engine to ${KOKORO_DIR}"

    # Prerequisites
    if ! command -v uv &>/dev/null; then
        error "uv not found. Install: brew install uv"
        exit 1
    fi

    # Create directory
    mkdir -p "${KOKORO_DIR}"

    # Create venv with Python 3.14
    log "Creating Python 3.14 venv..."
    uv venv --python 3.14 "${KOKORO_VENV}"

    # Install MLX-Audio deps
    log "Installing MLX-Audio dependencies..."
    uv pip install --python "${KOKORO_PYTHON}" \
        mlx-audio soundfile numpy

    # Verify MLX-Audio
    log "Verifying MLX-Audio..."
    "${KOKORO_PYTHON}" -c "from mlx_audio.tts.utils import load_model; print('MLX-Audio OK')"

    # Copy bundled scripts
    log "Copying bundled scripts..."
    for script in kokoro_common.py tts_generate.py; do
        if [[ -f "${SCRIPT_DIR}/${script}" ]]; then
            cp "${SCRIPT_DIR}/${script}" "${KOKORO_DIR}/"
            log "  Copied ${script}"
        else
            error "${script} not found in plugin bundle at ${SCRIPT_DIR}/"
            exit 1
        fi
    done

    # Download model (warmup downloads weights from HuggingFace)
    log "Downloading Kokoro-82M MLX model (first run may take a minute)..."
    "${KOKORO_PYTHON}" -c "from mlx_audio.tts.utils import load_model; load_model('mlx-community/Kokoro-82M-bf16')"

    # Write version.json
    local mlx_ver
    mlx_ver=$("${KOKORO_PYTHON}" -c "from importlib.metadata import version; print(version('mlx-audio'))")
    cat > "${VERSION_FILE}" <<VJSON
{
  "mlx_audio": "${mlx_ver}",
  "backend": "mlx",
  "python": "3.14",
  "model": "mlx-community/Kokoro-82M-bf16",
  "installed_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "source": "kokoro-install.sh --install",
  "venv_path": "${KOKORO_VENV}"
}
VJSON

    # Verification synthesis
    log "Running verification synthesis..."
    "${KOKORO_PYTHON}" "${KOKORO_DIR}/tts_generate.py" \
        --text "Warm up." --voice af_heart --lang en-us --speed 1.0 \
        --output "/tmp/kokoro-verify-$$.wav" && rm -f "/tmp/kokoro-verify-$$.wav"

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
        mlx-audio soundfile numpy

    # Re-copy bundled scripts
    for script in kokoro_common.py tts_generate.py; do
        if [[ -f "${SCRIPT_DIR}/${script}" ]]; then
            cp "${SCRIPT_DIR}/${script}" "${KOKORO_DIR}/"
            log "Updated ${script} from plugin bundle"
        fi
    done

    # Re-download model
    log "Re-downloading model..."
    "${KOKORO_PYTHON}" -c "from mlx_audio.tts.utils import load_model; load_model('mlx-community/Kokoro-82M-bf16')"

    # Update version.json
    local mlx_ver
    mlx_ver=$("${KOKORO_PYTHON}" -c "from importlib.metadata import version; print(version('mlx-audio'))")
    cat > "${VERSION_FILE}" <<VJSON
{
  "mlx_audio": "${mlx_ver}",
  "backend": "mlx",
  "python": "3.14",
  "model": "mlx-community/Kokoro-82M-bf16",
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
    check "Venv exists"            "[[ -d '${KOKORO_VENV}' ]]"
    check "Python 3.14 executable" "'${KOKORO_PYTHON}' --version 2>&1 | grep -q '3\\.13'"
    check "mlx_audio importable"   "'${KOKORO_PYTHON}' -c 'from mlx_audio.tts.utils import load_model'"
    check "kokoro_common.py"       "[[ -f '${KOKORO_DIR}/kokoro_common.py' ]]"
    check "tts_generate.py"        "[[ -f '${KOKORO_DIR}/tts_generate.py' ]]"
    check "version.json exists"    "[[ -f '${VERSION_FILE}' ]]"

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

    # Remove venv, scripts, version (keep model cache in ~/.cache/huggingface/)
    rm -rf "${KOKORO_VENV}"
    rm -f "${KOKORO_DIR}/tts_generate.py" "${KOKORO_DIR}/kokoro_common.py" "${VERSION_FILE}"

    # Remove dir if empty
    rmdir "${KOKORO_DIR}" 2>/dev/null || true

    log "Removed. Model cache at ~/.cache/huggingface/ preserved."
    log "To also remove model cache: rm -rf ~/.cache/huggingface/hub/models--mlx-community--Kokoro-82M-bf16"
}

# --- Main ---
case "${1:-}" in
    --install)   do_install ;;
    --upgrade)   do_upgrade ;;
    --health)    do_health ;;
    --uninstall) do_uninstall ;;
    *)
        echo "Usage: kokoro-install.sh [--install|--upgrade|--health|--uninstall]"
        exit 1
        ;;
esac
