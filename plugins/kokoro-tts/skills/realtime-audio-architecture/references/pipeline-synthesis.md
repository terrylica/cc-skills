# Pipeline Synthesis for Gapless TTS

## The Gap Problem

Without pipelining, chunked TTS has silence between paragraphs:

```
[synth 700ms][play 10s][synth 700ms][play 8s][synth 600ms][play 9s]
                       ↑ 700ms gap!          ↑ 600ms gap!
```

## Pipeline Solution

Synthesize chunk N+1 while chunk N plays:

```
[synth chunk 1 700ms][play chunk 1 ───────────────── 10s ──────────────────]
                     [synth chunk 2 700ms][play chunk 2 ─────────── 8s ────]
                                          [synth chunk 3 600ms][play chunk 3]
```

No gaps — synthesis completes well before the current chunk finishes playing.

## Implementation

```python
from concurrent.futures import ThreadPoolExecutor, Future

def playback_worker(model, stream, speak_queue, interrupted):
    with ThreadPoolExecutor(max_workers=1, thread_name_prefix="synth-ahead") as pool:
        while True:
            item = speak_queue.get()
            if item is None:
                break

            text, voice, lang, speed = item
            interrupted.clear()
            chunks = chunk_paragraphs(text)
            n = len(chunks)

            # Submit first chunk
            ahead: Future | None = pool.submit(synthesize, model, chunks[0], voice, lang, speed)

            for i in range(n):
                if interrupted.is_set():
                    if ahead and not ahead.done():
                        ahead.cancel()
                    break

                audio, gen_ms, char_count, _ = ahead.result()
                ahead = None

                # Pipeline: start next synthesis while current plays
                if i + 1 < n and not interrupted.is_set():
                    ahead = pool.submit(synthesize, model, chunks[i + 1], voice, lang, speed)

                # Apply boundary fades and play
                audio = apply_boundary_fades(audio)
                write_audio(stream, audio, interrupted)
```

## Why Single-Threaded Synthesis Pool

`ThreadPoolExecutor(max_workers=1)` — only one synthesis at a time because:

1. **MLX Metal is single-device**: Multiple concurrent syntheses don't parallelize on GPU
2. **Memory**: Each synthesis allocates GPU memory; concurrent runs could OOM
3. **Simplicity**: One-ahead is sufficient since playback >> synthesis time

## When Pipeline Isn't Enough

If chunks are very short (< 1 second of audio), synthesis of the next chunk may not complete before the current one finishes. Solutions:

1. **Batch small chunks**: Merge consecutive short paragraphs before synthesis
2. **Pre-synthesize buffer**: Synthesize 2-3 chunks before starting playback
3. **Chunk sizing**: Target 100-300 chars per chunk (~4-12 seconds of audio at 24kHz)

## Chunk Paragraph Strategy

The `chunk_paragraphs()` function splits text at paragraph boundaries (`\n\n`) while keeping each chunk under the model's comfortable synthesis length (~400 chars). Long paragraphs are further split at sentence boundaries.

```python
def chunk_paragraphs(text: str, max_len: int = 400) -> list[str]:
    paragraphs = [p.strip() for p in text.split("\n\n") if p.strip()]
    chunks = []
    current = ""
    for p in paragraphs:
        if len(current) + len(p) + 1 <= max_len:
            current = f"{current} {p}" if current else p
        else:
            if current:
                chunks.append(current)
            current = p
    if current:
        chunks.append(current)
    return chunks
```
