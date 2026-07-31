# unlimited-ocr

Local, offline, free document parsing with [`baidu/Unlimited-OCR`](https://github.com/baidu/Unlimited-OCR)
(MIT) — markdown, LaTeX mathematics, tables, and a bounding box for every block on the page.

Runs on **Apple Silicon** (MLX, ~2.4 s and ~5 GB per image) or an **NVIDIA GPU** (transformers).
No API key, no per-image cost, no upload quota, nothing leaves the machine.

```bash
S=~/eon/cc-skills/plugins/unlimited-ocr/scripts/unlimited_ocr.py

uv run --no-project $S doctor                                # what can this machine run?
uv run --no-project $S parse   --input page.png              # -> markdown
uv run --no-project $S parse   --input paper.pdf --output ./out
uv run --no-project $S segment --input figure.png --output ./panels
uv run --no-project $S spec                                  # the CLI contract as JSON
```

Nothing to install: `uv run` reads the script's PEP 723 header and materialises its own dependencies.

## Skills

| Skill                          | What it does                                              |
| ------------------------------ | --------------------------------------------------------- |
| `unlimited-ocr-parse-document` | image / PDF / directory → markdown + LaTeX + layout boxes |
| `unlimited-ocr-segment-figure` | composite figure → one cropped image per detected panel   |
| `unlimited-ocr-batch-folder`   | batch parse a folder with checkpoint/resume               |

## Read this before trusting it

- The prompt in the upstream README (`document parsing.`) **decodes infinite garbage on MLX**. This
  CLI defaults to the one that works and refuses the other.
- It **localises charts but transcribes nothing inside them.** By design. That is what `segment` is
  for.
- Multi-page single-pass **dropped a page** on near-identical pages. For archives, parse per page.

Full detail, with the measurements behind every claim:
[`CLAUDE.md`](CLAUDE.md) · [`references/EMPIRICAL.md`](references/EMPIRICAL.md) ·
[`references/PITFALLS.md`](references/PITFALLS.md)
