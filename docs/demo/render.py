"""Renders docs/demo.gif: an illustration of one interruption, using the
timings and log lines from the live test on 2026-11-05.

Nothing here is a screenshot of any app. Requires Pillow, ffmpeg, and the
Inter and JetBrains Mono fonts (both SIL Open Font License):

    python3 -m venv venv && venv/bin/pip install pillow
    venv/bin/python docs/demo/render.py --fonts <dir with the .ttf files> --out docs/demo.gif
"""

import argparse
import math
import shutil
import subprocess
import tempfile
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

W, H = 880, 452
S = 2  # supersampling factor; frames are drawn at 2x and scaled down
FPS = 25

# From the live test log (2026-11-05).
SAVED_VOLUME = 60
MUTE_MS = 67
SONG_LENGTH = 337  # seconds, the song that ended at 10:36:06
GAP_SECONDS = 90  # 10:36:06 -> 10:37:36
LOG = [
    "[10:36:06] Interruption detected at track end. Muted within 67ms. (saved volume: 60)",
    "[10:37:36] Interruption ended. Volume restored to 60.",
]

# Timeline of the GIF, in seconds.
T_END = 3.0  # song ends, interruption starts
T_SLOW = 1.2  # the first 67ms, slowed down to this long
T_MUTED = T_END + T_SLOW
T_SKIP = 6.2  # "90 seconds later" overlay starts
T_BACK = 7.0  # music returns
T_TOTAL = 11.0

BG = (13, 15, 19)
CARD = (25, 28, 34)
LINE = (44, 48, 56)
TEXT = (230, 232, 235)
MUTED_TEXT = (139, 145, 154)
GOLD = (242, 184, 75)
RED = (229, 83, 75)
TERM_BG = (9, 10, 13)
TERM_TEXT = (196, 201, 208)
SONG_ART = (88, 101, 242)
NEXT_ART = (38, 166, 154)
GAP_ART = (70, 74, 82)


def fonts(directory):
    d = Path(directory)

    def f(name, size):
        return ImageFont.truetype(str(next(d.rglob(name))), size * S)

    return {
        "title": f("Inter-Bold.ttf", 22),
        "track": f("Inter-SemiBold.ttf", 22),
        "body": f("Inter-Regular.ttf", 15),
        "small": f("Inter-Regular.ttf", 13),
        "badge": f("Inter-SemiBold.ttf", 15),
        "big": f("Inter-Bold.ttf", 30),
        "mono": f("JetBrainsMono-Regular.ttf", 12),
        "mono_bold": f("JetBrainsMono-Bold.ttf", 12),
    }


def mmss(seconds):
    seconds = max(0, int(seconds))
    return f"{seconds // 60}:{seconds % 60:02d}"


def state_at(t):
    """What the illustrated player shows at GIF time t."""
    if t < T_END:
        return {
            "phase": "song",
            "title": "Your song",
            "subtitle": "Playing",
            "art": SONG_ART,
            "pos": SONG_LENGTH - (T_END - t),
            "length": SONG_LENGTH,
            "volume": SAVED_VOLUME,
            "audible": True,
            "elapsed_ms": None,
        }
    if t < T_MUTED:
        ms = (t - T_END) / T_SLOW * MUTE_MS
        return {
            "phase": "detecting",
            "title": "Interruption",
            "subtitle": "Started at the end of the song",
            "art": GAP_ART,
            "pos": ms / 1000,
            "length": GAP_SECONDS,
            "volume": SAVED_VOLUME,
            "audible": True,
            "elapsed_ms": ms,
        }
    if t < T_BACK:
        if t < T_SKIP:
            pos = MUTE_MS / 1000 + (t - T_MUTED)
        else:
            pos = GAP_SECONDS - (T_BACK - t)
        return {
            "phase": "muted",
            "title": "Interruption",
            "subtitle": "Plays in full, at volume 0",
            "art": GAP_ART,
            "pos": pos,
            "length": GAP_SECONDS,
            "volume": 0,
            "audible": False,
            "elapsed_ms": MUTE_MS,
        }
    return {
        "phase": "back",
        "title": "Your next song",
        "subtitle": "Playing",
        "art": NEXT_ART,
        "pos": t - T_BACK,
        "length": 214,
        "volume": SAVED_VOLUME,
        "audible": True,
        "elapsed_ms": None,
    }


def rect(d, box, radius, fill):
    x0, y0, x1, y1 = box
    d.rounded_rectangle((x0 * S, y0 * S, x1 * S, y1 * S), radius=radius * S, fill=fill)


def text(d, xy, s, font, fill, anchor="la"):
    d.text((xy[0] * S, xy[1] * S), s, font=font, fill=fill, anchor=anchor)


def speaker(d, x, y, level, color):
    # A plain speaker glyph: body, cone, and 0-2 sound waves.
    d.rectangle(((x) * S, (y + 6) * S, (x + 6) * S, (y + 14) * S), fill=color)
    d.polygon(
        [((x + 6) * S, (y + 6) * S), ((x + 13) * S, (y) * S), ((x + 13) * S, (y + 20) * S), ((x + 6) * S, (y + 14) * S)],
        fill=color,
    )
    if level == 0:
        w = 2 * S
        d.line(((x + 17) * S, (y + 5) * S, (x + 25) * S, (y + 15) * S), fill=RED, width=w)
        d.line(((x + 25) * S, (y + 5) * S, (x + 17) * S, (y + 15) * S), fill=RED, width=w)
        return
    for i, r in enumerate((6, 11)):
        if level > i * 50:
            d.arc(
                ((x + 13 - r) * S, (y + 10 - r) * S, (x + 13 + r) * S, (y + 10 + r) * S),
                start=-45, end=45, fill=color, width=2 * S,
            )


def equalizer(d, x, y, t, audible, color):
    for i in range(5):
        if audible:
            h = 6 + 14 * (0.5 + 0.5 * math.sin(t * 9 + i * 1.7)) * (0.6 + 0.4 * math.sin(t * 3.1 + i))
        else:
            h = 3
        rect(d, (x + i * 7, y + 22 - h, x + i * 7 + 4, y + 22), 1, color)


def frame(t, F):
    img = Image.new("RGB", (W * S, H * S), BG)
    d = ImageDraw.Draw(img)
    st = state_at(t)

    text(d, (28, 22), "shall-not-pass", F["title"], TEXT)
    text(d, (W - 28, 28), "Illustration. Timings and log from a real run.", F["small"], MUTED_TEXT, "ra")

    # Player card
    rect(d, (24, 62, W - 24, 270), 14, CARD)
    rect(d, (48, 86, 168, 206), 10, st["art"])
    if st["phase"] in ("detecting", "muted"):
        text(d, (108, 146), "!", F["big"], (150, 155, 165), "mm")
    else:
        # A simple note glyph so the art reads as "music" without any branding.
        cx, cy = 100, 160
        d.ellipse(((cx - 9) * S, (cy - 6) * S, (cx + 9) * S, (cy + 8) * S), fill=TEXT)
        d.rectangle(((cx + 6) * S, (cy - 40) * S, (cx + 9) * S, cy * S), fill=TEXT)
        d.polygon([((cx + 9) * S, (cy - 40) * S), ((cx + 26) * S, (cy - 30) * S), ((cx + 26) * S, (cy - 24) * S), ((cx + 9) * S, (cy - 32) * S)], fill=TEXT)

    text(d, (192, 92), st["title"], F["track"], TEXT)
    text(d, (192, 124), st["subtitle"], F["body"], MUTED_TEXT)
    eq_color = GOLD if st["phase"] in ("song", "back") else RED
    equalizer(d, W - 84, 92, t, st["audible"], eq_color)

    # Progress
    frac = min(1, max(0, st["pos"] / st["length"]))
    rect(d, (192, 162, W - 48, 166), 2, LINE)
    rect(d, (192, 162, 192 + (W - 240) * frac, 166), 2, TEXT)
    text(d, (192, 174), mmss(st["pos"]), F["small"], MUTED_TEXT)
    text(d, (W - 48, 174), mmss(st["length"]), F["small"], MUTED_TEXT, "ra")

    # Volume
    vol = st["volume"]
    speaker(d, 192, 214, vol, TEXT)
    rect(d, (232, 222, 432, 226), 2, LINE)
    if vol:
        rect(d, (232, 222, 232 + 200 * vol / 100, 226), 2, GOLD)
    text(d, (446, 216), f"Spotify volume {vol}", F["body"], TEXT if vol else RED)

    # Badge on the right
    if st["phase"] == "detecting":
        ms = int(st["elapsed_ms"])
        text(d, (W - 48, 214), f"+{ms}ms", F["badge"], RED, "ra")
        text(d, (W - 48, 236), "slowed down", F["small"], MUTED_TEXT, "ra")
    elif st["phase"] == "muted":
        text(d, (W - 48, 214), f"Muted within {MUTE_MS}ms", F["badge"], RED, "ra")
    elif st["phase"] == "back" and t < T_BACK + 3:
        text(d, (W - 48, 214), f"Volume restored to {SAVED_VOLUME}", F["badge"], GOLD, "ra")

    # "90 seconds later" overlay
    if T_SKIP <= t < T_BACK:
        cx = W / 2 + 70
        rect(d, (cx - 100, 90, cx + 100, 122), 16, (52, 56, 64))
        text(d, (cx, 106), f"{GAP_SECONDS} seconds later", F["badge"], TEXT, "mm")

    # Terminal with the real log lines
    rect(d, (24, 288, W - 24, H - 22), 12, TERM_BG)
    for i, c in enumerate(((237, 106, 94), (245, 191, 79), (98, 197, 84))):
        cx, cy = 44 + i * 18, 306
        d.ellipse(((cx - 5) * S, (cy - 5) * S, (cx + 5) * S, (cy + 5) * S), fill=c)
    text(d, (W / 2, 300), "~/Library/Logs/shall-not-pass.log", F["small"], MUTED_TEXT, "ma")
    text(d, (44, 334), "$ tail -f ~/Library/Logs/shall-not-pass.log", F["mono"], MUTED_TEXT)
    y = 362
    if t >= T_MUTED:
        text(d, (44, y), LOG[0], F["mono"], TERM_TEXT)
        y += 24
    if t >= T_BACK:
        text(d, (44, y), LOG[1], F["mono"], TERM_TEXT)
        y += 24
    if int(t * 2) % 2 == 0:
        rect(d, (44, y, 51, y + 16), 1, TERM_TEXT)

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
