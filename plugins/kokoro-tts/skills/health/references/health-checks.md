# Health Checks Reference

Detailed documentation for each of the 6 Kokoro TTS health checks.

---

## Check 1: Venv Exists

**What it tests**: Whether the Python virtual environment for Kokoro TTS exists.

**Command**:

```bash
[[ -d ~/.local/share/kokoro/.venv ]]
```

**Pass condition**: Directory exists.

**Failure meaning**: Kokoro has never been installed, or the venv was deleted/corrupted.

**Remediation**: Run `/kokoro-tts:install` to install from scratch.

---

## Check 2: Python 3.13 Executable

**What it tests**: Whether the venv Python is version 3.13.

**Command**:

```bash
~/.local/share/kokoro/.venv/bin/python --version 2>&1 | grep -q '3\.13'
```

**Pass condition**: Output contains `3.13`.

**Failure meaning**: Wrong Python version in venv. Must be 3.13 per global Python version policy.

**Remediation**: Delete `.venv` and recreate: `kokoro-install.sh --uninstall && kokoro-install.sh --install`

---

## Check 3: MLX-Audio Importable

**What it tests**: Whether the `mlx_audio` Python package is importable within the venv.

**Command**:

```bash
~/.local/share/kokoro/.venv/bin/python -c "from mlx_audio.tts.utils import load_model"
```

**Pass condition**: Exit code 0 (import succeeds).

**Failure meaning**:

- **ModuleNotFoundError**: Package not installed in the venv.
- **ImportError**: Dependency conflict or corrupt installation.

**Remediation**: `uv pip install --python ~/.local/share/kokoro/.venv/bin/python mlx-audio`

---

## Check 4: kokoro_common.py Exists

**What it tests**: Whether the synthesis SSoT script is present.

**Command**:

```bash
[[ -f ~/.local/share/kokoro/kokoro_common.py ]]
```

**Pass condition**: File exists.

**Failure meaning**: Script was not copied during install, or was deleted.

**Remediation**: Re-run `kokoro-install.sh --install` to copy from plugin bundle.

---

## Check 5: tts_generate.py Exists

**What it tests**: Whether the CLI tool script is present.

**Command**:

```bash
[[ -f ~/.local/share/kokoro/tts_generate.py ]]
```

**Pass condition**: File exists.

**Failure meaning**: Script was not copied during install, or was deleted.

**Remediation**: Re-run `kokoro-install.sh --install` to copy from plugin bundle.

---

## Check 6: version.json Exists

**What it tests**: Whether the installation metadata file is present.

**Command**:

```bash
[[ -f ~/.local/share/kokoro/version.json ]]
```

**Pass condition**: File exists.

**Failure meaning**: Install did not complete, or file was deleted.

**Remediation**: Re-run `kokoro-install.sh --install`.
