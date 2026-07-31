#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.12"
# dependencies = ["pillow>=10.0.0", "mlx-vlm>=0.6.0"]
# ///
"""
Does the model drop near-duplicate pages when several images ride in ONE forward pass?

This is the question the 4090 probe raised: five near-identical synthetic pages went in and four
came out, with no error. The plugin's CLI sends one image per call and therefore cannot reproduce
it, so this probe calls mlx-vlm directly to exercise the model's own multi-image path.

Independent variable: how much text the pages SHARE. Each page carries one unmistakable unique
marker; the measurement is simply how many markers survive.
"""
import sys
from pathlib import Path
from PIL import Image, ImageDraw

from mlx_vlm import load, generate
from mlx_vlm.prompt_utils import apply_chat_template
from mlx_vlm.utils import load_config

MODEL_ID = "mlx-community/Unlimited-OCR-mxfp8"
WORKDIR = Path("/tmp/multipage_experiment")
WORKDIR.mkdir(exist_ok=True)

SHARED_BOILERPLATE = [
    "QUARTERLY OPERATIONS REVIEW",
    "Section A: this paragraph is identical on every page of this document.",
    "It exists so that consecutive pages share long runs of tokens.",
    "Any suppression of repeated content will remove it from later pages.",
]


def build_pages(count: int, share_boilerplate: bool) -> list[Path]:
    paths = []
    for page_number in range(1, count + 1):
        image = Image.new("RGB", (900, 460), "white")
        draw = ImageDraw.Draw(image)
        y = 40
        if share_boilerplate:
            for line in SHARED_BOILERPLATE:
                draw.text((40, y), line, fill="black")
                y += 34
        else:
            for i, line in enumerate(SHARED_BOILERPLATE):
                draw.text((40, y), f"Page {page_number} unique line {i}: {'zyx'[i % 3] * (page_number + i)}", fill="black")
                y += 34
        draw.text((40, y + 30), f"UNIQUE MARKER PAGE {page_number} IS ZEBRA{page_number}{page_number}{page_number}", fill="black")
        path = WORKDIR / f"{'shared' if share_boilerplate else 'varied'}_{count}p_page{page_number:02d}.png"
        image.save(path)
        paths.append(path)
    return paths


def markers_found(text: str, count: int) -> int:
    return sum(1 for n in range(1, count + 1) if f"ZEBRA{n}{n}{n}" in text.upper().replace(" ", ""))


print(f"loading {MODEL_ID} ...", file=sys.stderr)
model, processor = load(MODEL_ID)
config = load_config(MODEL_ID)
print("loaded\n", file=sys.stderr)

print(f"{'condition':<26} {'pages':>5} {'single-pass':>12} {'per-page':>9}")
print("-" * 56)

for share in (True, False):
    for count in (3, 5, 10):
        pages = build_pages(count, share)
        label = f"{'identical' if share else 'varied'} boilerplate"

        # --- one forward pass, all images ---
        prompt = apply_chat_template(processor, config, "Free OCR.", num_images=len(pages))
        try:
            out = generate(model, processor, prompt=prompt, image=[str(p) for p in pages],
                           max_tokens=6000, temperature=0.0, repetition_penalty=1.05, verbose=False)
            single = markers_found(getattr(out, "text", str(out)), count)
        except Exception as exc:  # noqa - probe: any failure is a datum
            single = f"ERR:{type(exc).__name__}"

        # --- control: one call per image ---
        per_page = 0
        for p in pages:
            pr = apply_chat_template(processor, config, "Free OCR.", num_images=1)
            o = generate(model, processor, prompt=pr, image=str(p), max_tokens=2000,
                         temperature=0.0, repetition_penalty=1.05, verbose=False)
            per_page += markers_found(getattr(o, "text", str(o)), count)

        print(f"{label:<26} {count:>5} {str(single):>12} {per_page:>9}")

print("\n(numbers are UNIQUE MARKERS RECOVERED out of `pages`)")
