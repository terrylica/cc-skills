"""
Kokoro TTS shared constants and synthesis core.
GitHub Issue: https://github.com/terrylica/claude-config/issues/62

SSoT for model ID, language aliases, default voice/lang/speed, and synthesis loop.
Used by both tts_server.py (HTTP) and tts_generate.py (CLI).
"""

import numpy as np

from mlx_audio.tts.utils import load_model

# MODEL_ID is a deliberate DEPENDENCY PIN (like a lockfile entry), not a
# hard-coded display value: the local TTS engine must stay deterministic, so
# the model is never derived live from HuggingFace (an upstream rename would
# silently change audio output). Official registry entry:
# https://huggingface.co/mlx-community/Kokoro-82M-bf16
# SSoT for the pin: plugins/kokoro-tts/scripts/kokoro_common.py; the
# tts-tg-sync copy is byte-identical by necessity (plugins are self-contained
# for marketplace installs) - update BOTH together.
MODEL_ID = "mlx-community/Kokoro-82M-bf16"
SAMPLE_RATE = 24000
DEFAULT_VOICE = "af_heart"
DEFAULT_LANG = "en-us"
DEFAULT_SPEED = 1.0

_LANG_ALIASES = {"cmn": "zh"}


def map_lang(lang: str) -> str:
    """Map client language codes to MLX-Audio codes (e.g. cmn → zh)."""
    return _LANG_ALIASES.get(lang.lower(), lang)


def create_model():
    """Load the Kokoro MLX model. Caller owns the returned instance."""
    return load_model(MODEL_ID)


def synthesize(model, text: str, voice: str, lang: str, speed: float) -> np.ndarray:
    """Synthesize text → numpy float32 audio array (24 kHz mono).

    Caller must ensure thread-safety (MLX model is not thread-safe).
    """
    lang = map_lang(lang)
    chunks = []
    for result in model.generate(text=text, voice=voice, speed=speed, lang_code=lang):
        if result.audio is not None:
            chunks.append(np.array(result.audio))
    if not chunks:
        raise RuntimeError("Kokoro produced no audio")
    return np.concatenate(chunks)
