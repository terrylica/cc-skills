"""
Kokoro TTS shared constants and synthesis core.
GitHub Issue: https://github.com/terrylica/private-config/issues/62

SSoT for model ID, language aliases, default voice/lang/speed, and synthesis loop.
Used by both tts_server.py (HTTP) and tts_generate.py (CLI).
"""

import numpy as np

from mlx_audio.tts.utils import load_model

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
