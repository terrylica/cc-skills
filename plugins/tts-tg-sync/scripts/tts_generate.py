"""
Kokoro TTS CLI — generate WAV from text.
GitHub Issue: https://github.com/terrylica/private-config/issues/62

Called directly by the telegram-sync bot (no HTTP server needed).
Uses MLX-Audio Kokoro-82M for on-device TTS on Apple Silicon (MLX Metal).
Supports chunked mode for streaming playback of long text.

Usage:
  # Single WAV output:
  .venv/bin/python tts_generate.py --text "Hello" --voice af_heart --lang en-us --speed 1.0 --output /tmp/tts.wav

  # Chunked streaming (prints one WAV path per line as each chunk is ready):
  .venv/bin/python tts_generate.py --text "Long text..." --voice af_heart --lang en-us --speed 1.0 --output /tmp/tts.wav --chunk

Exit codes:
  0  Success (WAV written to --output)
  1  Error (message on stderr)
"""

import argparse
import os
import re
import sys
import time

import soundfile as sf

import kokoro_common as common


def sanitize_text(text: str) -> str:
    """Remove surrogates and non-printable chars that crash spaCy."""
    text = text.encode("utf-8", errors="surrogateescape").decode("utf-8", errors="replace")
    text = re.sub(r"[\ufffd\x00-\x08\x0b\x0c\x0e-\x1f]", "", text)
    return text


def chunk_text(text: str, max_chars: int = 500) -> list[str]:
    """Split text into chunks using a hierarchical boundary strategy.

    Priority: paragraph borders → sentence borders → character fallback.
    Each chunk <= max_chars unless a single sentence exceeds the limit.
    """
    paragraphs = re.split(r"\n\s*\n|\n", text)
    paragraphs = [p.strip() for p in paragraphs if p.strip()]

    chunks: list[str] = []
    current = ""

    for para in paragraphs:
        if current and len(current) + len(para) + 2 <= max_chars:
            current = f"{current}\n\n{para}"
            continue

        if current:
            chunks.append(current)
            current = ""

        if len(para) <= max_chars:
            current = para
            continue

        sentences = re.split(r"(?<=[.!?;:])\s+", para)
        for sentence in sentences:
            if not sentence.strip():
                continue

            if current and len(current) + len(sentence) + 1 > max_chars:
                chunks.append(current)
                current = ""

            if len(sentence) <= max_chars:
                current = f"{current} {sentence}" if current else sentence
                continue

            if current:
                chunks.append(current)
                current = ""
            words = sentence.split()
            for word in words:
                if current and len(current) + len(word) + 1 > max_chars:
                    chunks.append(current)
                    current = word
                else:
                    current = f"{current} {word}" if current else word

    if current.strip():
        chunks.append(current.strip())
    return chunks if chunks else [text]


def generate_wav(model, text: str, voice: str, lang: str, speed: float, output: str) -> bool:
    """Generate a single WAV file. Returns True on success."""
    try:
        audio = common.synthesize(model, text, voice, lang, speed)
    except RuntimeError:
        return False
    sf.write(output, audio, common.SAMPLE_RATE, format="WAV")
    return True


def main() -> None:
    parser = argparse.ArgumentParser(description="Kokoro TTS generate WAV")
    parser.add_argument("--text", required=True, help="Text to synthesize")
    parser.add_argument("--voice", default=common.DEFAULT_VOICE, help="Voice name")
    parser.add_argument("--lang", default=common.DEFAULT_LANG, help="Language code")
    parser.add_argument("--speed", type=float, default=common.DEFAULT_SPEED, help="Speech speed")
    parser.add_argument("--output", required=True, help="Output WAV path")
    parser.add_argument("--chunk", action="store_true",
                        help="Chunked streaming: print WAV path per chunk as ready")
    args = parser.parse_args()

    text = sanitize_text(args.text)
    if not text.strip():
        print("Empty text", file=sys.stderr)
        sys.exit(1)

    t0 = time.monotonic()
    model = common.create_model()

    if args.chunk:
        chunks = chunk_text(text)
        base, ext = os.path.splitext(args.output)
        for i, chunk in enumerate(chunks):
            chunk_path = f"{base}-{i:03d}{ext}" if len(chunks) > 1 else args.output
            if generate_wav(model, chunk, args.voice, args.lang, args.speed, chunk_path):
                print(chunk_path, flush=True)
            else:
                print(f"Warning: chunk {i} produced no audio", file=sys.stderr)

        gen_ms = int((time.monotonic() - t0) * 1000)
        print(f"DONE {gen_ms}", flush=True)
    else:
        if not generate_wav(model, text, args.voice, args.lang, args.speed, args.output):
            print("No audio generated", file=sys.stderr)
            sys.exit(1)

        gen_ms = int((time.monotonic() - t0) * 1000)
        print(f"{gen_ms}", flush=True)


if __name__ == "__main__":
    main()
