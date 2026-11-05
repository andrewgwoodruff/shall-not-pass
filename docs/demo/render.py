"""Renders docs/demo.gif: a song ends, a short interruption plays muted, and the
next song comes back at the same volume.

It's a drawn illustration, not a screenshot of any app. Requires Pillow,
ffmpeg, and the Inter font (SIL Open Font License):

    python3 -m venv venv && venv/bin/pip install pillow
    venv/bin/python docs/demo/render.py --fonts <dir with Inter .ttf files> --out docs/demo.gif
"""

import argparse
import math
import shutil
import subprocess
import tempfile
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

W, H = 720, 220
S = 2  # supersampling factor; frames are drawn at 2x and scaled down
FPS = 25

VOLUME = 60
SONG_LENGTH = 214
GAP_LENGTH = 5

# Timeline of the GIF, in seconds.
T_GAP = 3.0  # song ends, interruption starts
T_BACK = T_GAP + GAP_LENGTH  # next song starts
T_TOTAL = T_BACK + 3.5

BG = (13, 15, 19)
CARD = (25, 28, 34)
LINE = (44, 48, 56)
TEXT = (230, 232, 235)
MUTED_TEXT = (139, 145, 154)
GOLD = (242, 184, 75)
RED = (229, 83, 75)
SONG_ART = (88, 101, 242)
NEXT_ART = (38, 166, 154)
GAP_ART = (70, 74, 82)


def fonts(directory):
    d = Path(directory)

    def f(name, size):
        return ImageFont.truetype(str(next(d.rglob(name))), size * S)

    return {
        "track": f("Inter-SemiBold.ttf", 22),
        "small": f("Inter-Regular.ttf", 13),
        "big": f("Inter-Bold.ttf", 30),
    }


def mmss(seconds):
    seconds = max(0, int(seconds))
    return f"{seconds // 60}:{seconds % 60:02d}"


def state_at(t):
    if t < T_GAP:
        return dict(title="Your song", art=SONG_ART, pos=SONG_LENGTH - (T_GAP - t),
                    length=SONG_LENGTH, volume=VOLUME, gap=False)
    if t < T_BACK:
        return dict(title="Interruption", art=GAP_ART, pos=t - T_GAP,
                    length=GAP_LENGTH, volume=0, gap=True)
    return dict(title="Your next song", art=NEXT_ART, pos=t - T_BACK,
                length=187, volume=VOLUME, gap=False)


def px(*v):
    return [x * S for x in v]


def rect(d, box, radius, fill):
    d.rounded_rectangle(px(*box), radius=radius * S, fill=fill)


def text(d, xy, s, font, fill, anchor="la"):
    d.text(px(*xy), s, font=font, fill=fill, anchor=anchor)


def speaker(d, x, y, muted, color):
    d.rectangle(px(x, y + 6, x + 6, y + 14), fill=color)
    d.polygon([tuple(px(x + 6, y + 6)), tuple(px(x + 13, y)), tuple(px(x + 13, y + 20)), tuple(px(x + 6, y + 14))], fill=color)
    if muted:
        d.line(px(x + 17, y + 5, x + 25, y + 15), fill=RED, width=2 * S)
        d.line(px(x + 25, y + 5, x + 17, y + 15), fill=RED, width=2 * S)
        return
    for r in (6, 11):
        d.arc(px(x + 13 - r, y + 10 - r, x + 13 + r, y + 10 + r), start=-45, end=45, fill=color, width=2 * S)


def equalizer(d, x, y, t, audible, color):
    for i in range(5):
        if audible:
            h = 6 + 14 * (0.5 + 0.5 * math.sin(t * 9 + i * 1.7)) * (0.6 + 0.4 * math.sin(t * 3.1 + i))
        else:
            h = 3
        rect(d, (x + i * 7, y + 22 - h, x + i * 7 + 4, y + 22), 1, color)


def note(d, cx, cy):
    d.ellipse(px(cx - 9, cy - 6, cx + 9, cy + 8), fill=TEXT)
    d.rectangle(px(cx + 6, cy - 40, cx + 9, cy), fill=TEXT)
    d.polygon([tuple(px(cx + 9, cy - 40)), tuple(px(cx + 26, cy - 30)), tuple(px(cx + 26, cy - 24)), tuple(px(cx + 9, cy - 32))], fill=TEXT)


def frame(t, F):
    img = Image.new("RGB", (W * S, H * S), BG)
    d = ImageDraw.Draw(img)
    st = state_at(t)
    right = W - 44

    rect(d, (20, 20, W - 20, H - 20), 14, CARD)
    rect(d, (44, 50, 164, 170), 10, st["art"])
    if st["gap"]:
        text(d, (104, 110), "!", F["big"], (150, 155, 165), "mm")
    else:
        note(d, 96, 124)

    text(d, (188, 52), st["title"], F["track"], TEXT)
    equalizer(d, right - 32, 50, t, not st["gap"], RED if st["gap"] else GOLD)

    # Progress: elapsed on the left, time remaining on the right.
    frac = min(1, max(0, st["pos"] / st["length"]))
    rect(d, (188, 104, right, 108), 2, LINE)
    rect(d, (188, 104, 188 + (right - 188) * frac, 108), 2, TEXT)
    text(d, (188, 116), mmss(st["pos"]), F["small"], MUTED_TEXT)
    text(d, (right, 116), "-" + mmss(math.ceil(st["length"] - st["pos"])), F["small"], MUTED_TEXT, "ra")

    # Volume slider
    muted = st["volume"] == 0
    knob = 228 + 200 * st["volume"] / 100
    speaker(d, 188, 146, muted, RED if muted else TEXT)
    rect(d, (228, 154, 428, 158), 2, LINE)
    if not muted:
        rect(d, (228, 154, knob, 158), 2, GOLD)
    d.ellipse(px(knob - 6, 150, knob + 6, 162), fill=MUTED_TEXT if muted else TEXT)

    return img.resize((W, H), Image.LANCZOS)


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--fonts", required=True)
    p.add_argument("--out", default="docs/demo.gif")
    args = p.parse_args()
    if not shutil.which("ffmpeg"):
        raise SystemExit("ffmpeg is required")

    F = fonts(args.fonts)
    with tempfile.TemporaryDirectory() as tmp:
        for n in range(int(T_TOTAL * FPS)):
            frame(n / FPS, F).save(f"{tmp}/f{n:04d}.png")
        palette = f"{tmp}/palette.png"
        subprocess.run(
            ["ffmpeg", "-loglevel", "error", "-y", "-framerate", str(FPS), "-i", f"{tmp}/f%04d.png",
             "-vf", "palettegen=max_colors=128:stats_mode=full", palette],
            check=True,
        )
        subprocess.run(
            ["ffmpeg", "-loglevel", "error", "-y", "-framerate", str(FPS), "-i", f"{tmp}/f%04d.png",
             "-i", palette, "-lavfi", "paletteuse=dither=none", "-loop", "0", args.out],
            check=True,
        )
    print(f"Wrote {args.out}")


if __name__ == "__main__":
    main()
