#!/usr/bin/env python3
"""
Kokoro TTS HTTP server — OpenAI-compatible /v1/audio/speech endpoint.
ADR: kokoro-tts-openai-server — OpenAI-compatible TTS at port 8779.
GitHub Issue: https://github.com/terrylica/claude-config/issues/62

Wraps MLX-Audio Kokoro-82M for on-device TTS on Apple Silicon (MLX Metal).
Mirrors the OpenAI TTS API subset.

Environment variables:
  KOKORO_SERVER_PORT   — port to listen on (default: 8779)
  KOKORO_SERVER_HOST   — bind address (default: 127.0.0.1)
  KOKORO_DEFAULT_VOICE — default voice (default: af_heart)
  KOKORO_DEFAULT_LANG  — default language code (default: en-us)
  KOKORO_DEFAULT_SPEED — speech speed multiplier (default: 1.0)
  KOKORO_PLAY_LOCAL    — if "1", play via afplay after synthesis
"""

import http.server
import io
import json
import os
import subprocess
import tempfile
import threading
import time
from dataclasses import dataclass

import numpy as np
import soundfile as sf

import kokoro_common as common


@dataclass(frozen=True)
class Config:
    """Server configuration — single validated read of all env vars at startup."""

    port: int = 8779
    host: str = "127.0.0.1"
    default_voice: str = common.DEFAULT_VOICE
    default_lang: str = common.DEFAULT_LANG
    default_speed: float = common.DEFAULT_SPEED
    play_local: bool = False

    @classmethod
    def from_env(cls) -> "Config":
        port = int(os.environ.get("KOKORO_SERVER_PORT", str(cls.port)))
        if not 1 <= port <= 65535:
            raise ValueError(f"KOKORO_SERVER_PORT must be 1–65535, got {port}")
        speed = float(os.environ.get("KOKORO_DEFAULT_SPEED", str(cls.default_speed)))
        if not 0.1 <= speed <= 5.0:
            raise ValueError(f"KOKORO_DEFAULT_SPEED must be 0.1–5.0, got {speed}")
        return cls(
            port=port,
            host=os.environ.get("KOKORO_SERVER_HOST", cls.host),
            default_voice=os.environ.get("KOKORO_DEFAULT_VOICE", cls.default_voice),
            default_lang=os.environ.get("KOKORO_DEFAULT_LANG", cls.default_lang),
            default_speed=speed,
            play_local=os.environ.get("KOKORO_PLAY_LOCAL", "0") == "1",
        )


# Serialise synthesis — MLX model resets pipeline.voices = {} on each call (not thread-safe)
_synthesis_lock = threading.Lock()
# Serialise playback so concurrent requests don't overlap audio output
_playback_lock = threading.Lock()


def synthesize_locked(model, text: str, voice: str, lang: str, speed: float) -> np.ndarray:
    """Thread-safe synthesis wrapper."""
    with _synthesis_lock:
        return common.synthesize(model, text, voice, lang, speed)


def to_wav_bytes(audio: np.ndarray) -> bytes:
    buf = io.BytesIO()
    sf.write(buf, audio, common.SAMPLE_RATE, format="WAV")
    return buf.getvalue()


def play_locally(wav_bytes: bytes) -> None:
    """Play via afplay on macOS (blocking — serialised by _playback_lock)."""
    with _playback_lock:
        with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as f:
            f.write(wav_bytes)
            tmp = f.name
        try:
            subprocess.run(["afplay", tmp], check=False)
        finally:
            try:
                os.unlink(tmp)
            except OSError:
                pass


def _ffmpeg_convert(wav_bytes: bytes, out_ext: str, codec_args: list[str]) -> bytes | None:
    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as f:
        f.write(wav_bytes)
        src = f.name
    dst = src.replace(".wav", out_ext)
    try:
        result = subprocess.run(
            ["ffmpeg", "-y", "-i", src] + codec_args + [dst],
            capture_output=True,
            check=False,
        )
        if result.returncode != 0:
            return None
        with open(dst, "rb") as f:
            return f.read()
    except FileNotFoundError:
        return None
    finally:
        for p in (src, dst):
            try:
                os.unlink(p)
            except OSError:
                pass


def to_mp3(wav_bytes: bytes) -> bytes | None:
    return _ffmpeg_convert(wav_bytes, ".mp3", ["-codec:a", "libmp3lame", "-q:a", "2"])


def to_opus(wav_bytes: bytes) -> bytes | None:
    return _ffmpeg_convert(wav_bytes, ".opus", ["-codec:a", "libopus", "-b:a", "64k"])


# ── HTTP handler ──────────────────────────────────────────────────────────────

class KokoroHandler(http.server.BaseHTTPRequestHandler):
    # Injected by main() before server starts
    config: Config
    model = None

    def log_message(self, fmt: str, *args) -> None:  # type: ignore[override]
        print(f"[kokoro-tts] {fmt % args}", flush=True)

    def _send_json(self, status: int, body: dict) -> None:
        data = json.dumps(body).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def _send_error(self, status: int, message: str) -> None:
        self._send_json(status, {"error": {"message": message, "type": "invalid_request_error"}})

    def do_GET(self) -> None:  # type: ignore[override]
        if self.path in ("/", "/health"):
            self._send_json(200, {
                "status": "ok",
                "provider": "kokoro-tts-mlx",
                "model": common.MODEL_ID,
                "device": "mlx-metal",
                "default_voice": self.config.default_voice,
                "default_lang": self.config.default_lang,
            })
        elif self.path == "/v1/models":
            self._send_json(200, {
                "object": "list",
                "data": [{"id": "kokoro-82m", "object": "model", "owned_by": "kokoro"}],
            })
        else:
            self._send_error(404, f"Not found: {self.path}")

    def do_POST(self) -> None:  # type: ignore[override]
        if self.path != "/v1/audio/speech":
            self._send_error(404, f"Not found: {self.path}")
            return

        length = int(self.headers.get("Content-Length", 0))
        try:
            body = json.loads(self.rfile.read(length))
        except json.JSONDecodeError:
            self._send_error(400, "Invalid JSON body")
            return

        text = str(body.get("input", "")).strip()
        if not text:
            self._send_error(400, "input must be a non-empty string")
            return

        cfg = self.config
        voice = str(body.get("voice", cfg.default_voice))
        lang = str(body.get("language", cfg.default_lang))
        speed = float(body.get("speed", cfg.default_speed))
        fmt = str(body.get("response_format", "wav")).lower()

        t0 = time.monotonic()
        try:
            audio = synthesize_locked(self.model, text, voice, lang, speed)
        except (RuntimeError, ValueError, AssertionError, OSError) as exc:
            print(f"[kokoro-tts] synthesis error: {exc}", flush=True)
            self._send_error(500, f"Synthesis failed: {exc}")
            return

        wav_bytes = to_wav_bytes(audio)
        if cfg.play_local:
            play_locally(wav_bytes)

        # Format negotiation
        audio_bytes: bytes = wav_bytes
        content_type = "audio/wav"
        if fmt == "mp3":
            converted = to_mp3(wav_bytes)
            if converted:
                audio_bytes, content_type = converted, "audio/mpeg"
        elif fmt == "opus":
            converted = to_opus(wav_bytes)
            if converted:
                audio_bytes, content_type = converted, "audio/opus"
        elif fmt == "pcm":
            audio_bytes = wav_bytes[44:]  # strip 44-byte WAV header → raw int16 PCM
            content_type = "audio/pcm"

        elapsed_ms = int((time.monotonic() - t0) * 1000)
        self.send_response(200)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(audio_bytes)))
        self.send_header("X-Voice", voice)
        self.send_header("X-Duration-Ms", str(elapsed_ms))
        self.end_headers()
        self.wfile.write(audio_bytes)


# ── Entry point ───────────────────────────────────────────────────────────────

def main() -> None:
    config = Config.from_env()

    print(f"[kokoro-tts] Loading model {common.MODEL_ID}…", flush=True)
    model = common.create_model()
    print("[kokoro-tts] Model ready", flush=True)

    # Warmup synthesis so first real request doesn't block
    print("[kokoro-tts] Running warmup synthesis…", flush=True)
    common.synthesize(model, "Warm up.", config.default_voice, config.default_lang, config.default_speed)
    print("[kokoro-tts] Warmup complete", flush=True)

    # Inject dependencies into handler class
    KokoroHandler.config = config
    KokoroHandler.model = model

    server = http.server.ThreadingHTTPServer((config.host, config.port), KokoroHandler)
    print(f"[kokoro-tts] Listening on http://{config.host}:{config.port}", flush=True)
    print(f"[kokoro-tts] Voice={config.default_voice}  Lang={config.default_lang}  Speed={config.default_speed}", flush=True)
    print(f"[kokoro-tts] Local afplay: {'enabled' if config.play_local else 'disabled'}", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
