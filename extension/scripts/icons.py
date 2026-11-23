"""Renders extension/icons/*.png: the wizard from the demo GIF, standing guard.

Requires Pillow:

    python3 -m venv venv && venv/bin/pip install pillow
    venv/bin/python extension/scripts/icons.py
"""

import sys
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "docs" / "demo"))
import render  # noqa: E402

SIZES = (16, 48, 128)


def icon():
    S = render.S
    x, ground = 60, render.GROUND
    # Draw the wizard on a canvas the size of a demo frame, then crop around him.
    img = Image.new("RGB", (render.W * S, render.H * S), render.CARD)
    render.wizard(ImageDraw.Draw(img), x, 0.2, None, False)
    box = (x - 63, ground - 114, x + 57, ground + 6)
    img = img.crop(tuple(v * S for v in box))

    # Rounded square, transparent corners.
    mask = Image.new("L", img.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, *img.size), radius=img.size[0] // 5, fill=255)
    img.putalpha(mask)
    return img


def main():
    out = ROOT / "extension" / "icons"
    out.mkdir(exist_ok=True)
    big = icon()
    for size in SIZES:
        big.resize((size, size), Image.LANCZOS).save(out / f"{size}.png")
        print(f"Wrote extension/icons/{size}.png")


if __name__ == "__main__":
    main()
