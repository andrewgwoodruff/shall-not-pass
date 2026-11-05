"""Renders docs/demo.gif: a song counts down to its end, a wizard turns the
volume down for a short interruption, and turns it back up for the next song.

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

W, H = 720, 330
S = 2  # supersampling factor; frames are drawn at 2x and scaled down
FPS = 25

VOLUME = 60
SONG_LENGTH = 10  # short, so the countdown to its end is visible
GAP_LENGTH = 5

# Timeline of the GIF, in seconds.
T_GAP = 5.0  # song ends, interruption starts
T_BACK = T_GAP + GAP_LENGTH  # next song starts
T_TOTAL = T_BACK + 3.5
DRAG = 0.15  # how long the wizard takes to move the slider

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

ROBE = (150, 156, 166)
ROBE_DARK = (112, 118, 128)
BEARD = (236, 236, 236)
FACE = (226, 192, 160)
STAFF = (138, 98, 62)

# Volume slider geometry
SLIDER_X, SLIDER_W, SLIDER_Y = 228, 200, 156
GROUND = H - 22
HOME_X = 620  # where the wizard waits


def fonts(directory):
    d = Path(directory)

    def f(name, size):
        return ImageFont.truetype(str(next(d.rglob(name))), size * S)

    return {
        "track": f("Inter-SemiBold.ttf", 22),
        "small": f("Inter-Regular.ttf", 13),
        "bubble": f("Inter-Bold.ttf", 15),
        "big": f("Inter-Bold.ttf", 30),
    }


def mmss(seconds):
    seconds = max(0, int(seconds))
    return f"{seconds // 60}:{seconds % 60:02d}"


def ease(x):
    x = min(1, max(0, x))
    return x * x * (3 - 2 * x)


def lerp(a, b, x):
    return a + (b - a) * ease(x)


def track_at(t):
    if t < T_GAP:
        return dict(title="Your song", art=SONG_ART, pos=SONG_LENGTH - (T_GAP - t), length=SONG_LENGTH, gap=False)
    if t < T_BACK:
        return dict(title="Interruption", art=GAP_ART, pos=t - T_GAP, length=GAP_LENGTH, gap=True)
    return dict(title="Your next song", art=NEXT_ART, pos=t - T_BACK, length=187, gap=False)


def volume_at(t):
    if t < T_GAP:
        return VOLUME
    if t < T_GAP + DRAG:
        return lerp(VOLUME, 0, (t - T_GAP) / DRAG)
    if t < T_BACK:
        return 0
    return lerp(0, VOLUME, (t - T_BACK) / DRAG)


def knob_x(volume):
    return SLIDER_X + SLIDER_W * volume / 100


def wizard_at(t):
    """Where the wizard stands, and where his staff points (None = upright)."""
    knob = knob_x(volume_at(t))
    beside = lambda k: k + 46  # standing just right of the knob, reaching up-left
    if t < T_GAP - 1.6:
        return HOME_X, None
    if t < T_GAP - 0.4:
        return lerp(HOME_X, beside(knob_x(VOLUME)), (t - (T_GAP - 1.6)) / 1.2), None
    if t < T_GAP:
        reach = ease((t - (T_GAP - 0.4)) / 0.4)
        return beside(knob), (reach, knob)
    if t < T_GAP + DRAG + 0.2:
        return beside(knob), (1, knob)
    if t < T_BACK - 0.4:
        return beside(knob), None  # on guard
    if t < T_BACK + DRAG + 0.2:
        reach = ease((t - (T_BACK - 0.4)) / 0.4)
        return beside(knob), (reach, knob)
    return lerp(beside(knob_x(VOLUME)), HOME_X, (t - (T_BACK + DRAG + 0.2)) / 1.2), None


def px(*v):
    return [x * S for x in v]


def rect(d, box, radius, fill):
    d.rounded_rectangle(px(*box), radius=radius * S, fill=fill)


def text(d, xy, s, font, fill, anchor="la"):
    d.text(px(*xy), s, font=font, fill=fill, anchor=anchor)


def poly(d, points, fill):
    d.polygon([tuple(px(x, y)) for x, y in points], fill=fill)


def glow(d, x, y, r, t):
    pulse = 0.5 + 0.5 * math.sin(t * 8)
    for radius, color in ((r + 7 + 2 * pulse, (60, 58, 46)), (r + 3, (150, 140, 100)), (r, (255, 250, 225))):
        d.ellipse(px(x - radius, y - radius, x + radius, y + radius), fill=color)


def wizard(d, x, t, staff, walking):
    """A grey wizard facing left, feet on the ground at x."""
    bob = abs(math.sin(t * 10)) * 3 if walking else 0
    y = GROUND - bob
    # Robe
    poly(d, [(x - 22, y), (x + 22, y), (x + 12, y - 52), (x - 12, y - 52)], ROBE)
    poly(d, [(x - 4, y), (x + 4, y), (x + 3, y - 50), (x - 3, y - 50)], ROBE_DARK)
    # Head, beard, hat
    d.ellipse(px(x - 10, y - 70, x + 10, y - 50), fill=FACE)
    poly(d, [(x - 11, y - 58), (x + 7, y - 58), (x - 4, y - 26)], BEARD)
    d.ellipse(px(x - 22, y - 70, x + 18, y - 62), fill=ROBE_DARK)
    poly(d, [(x - 13, y - 66), (x + 11, y - 66), (x + 4, y - 96), (x + 14, y - 104), (x - 2, y - 94)], ROBE)
    # Staff, held in the left hand
    hand = (x - 16, y - 40)
    d.ellipse(px(hand[0] - 4, hand[1] - 4, hand[0] + 4, hand[1] + 4), fill=FACE)
    if staff is None:
        top, bottom = (hand[0] - 2, y - 92), (hand[0] + 2, y)
    else:
        reach, target_x = staff
        upright = (hand[0] - 2, y - 92)
        top = (lerp(upright[0], target_x, reach), lerp(upright[1], SLIDER_Y, reach))
        # The staff runs from below the hand, through it, to the tip.
        dx, dy = top[0] - hand[0], top[1] - hand[1]
        length = math.hypot(dx, dy) or 1
        bottom = (hand[0] - dx / length * 30, hand[1] - dy / length * 30)
    d.line(px(*bottom, *top), fill=STAFF, width=4 * S)
    glow(d, top[0], top[1], 5, t)


def bubble(d, left, y, s, F):
    """A speech bubble whose tail points left, toward the wizard."""
    w = 196
    rect(d, (left, y - 18, left + w, y + 18), 12, TEXT)
    poly(d, [(left + 2, y - 2), (left + 2, y + 12), (left - 12, y + 12)], TEXT)
    text(d, (left + w / 2, y), s, F["bubble"], BG, "mm")


def speaker(d, x, y, muted, color):
    d.rectangle(px(x, y + 6, x + 6, y + 14), fill=color)
    poly(d, [(x + 6, y + 6), (x + 13, y), (x + 13, y + 20), (x + 6, y + 14)], color)
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
    poly(d, [(cx + 9, cy - 40), (cx + 26, cy - 30), (cx + 26, cy - 24), (cx + 9, cy - 32)], TEXT)


def frame(t, F):
    img = Image.new("RGB", (W * S, H * S), BG)
    d = ImageDraw.Draw(img)
    st = track_at(t)
    volume = volume_at(t)
    right = W - 44

    rect(d, (20, 20, W - 20, 200), 14, CARD)
    rect(d, (44, 50, 164, 170), 10, st["art"])
    if st["gap"]:
        text(d, (104, 110), "!", F["big"], (150, 155, 165), "mm")
    else:
        note(d, 96, 124)

    text(d, (188, 52), st["title"], F["track"], TEXT)
    equalizer(d, right - 32, 50, t, volume > 0, RED if st["gap"] else GOLD)

    # Progress: elapsed on the left, time remaining on the right.
    frac = min(1, max(0, st["pos"] / st["length"]))
    rect(d, (188, 104, right, 108), 2, LINE)
    rect(d, (188, 104, 188 + (right - 188) * frac, 108), 2, TEXT)
    text(d, (188, 116), mmss(st["pos"]), F["small"], MUTED_TEXT)
    text(d, (right, 116), "-" + mmss(math.ceil(st["length"] - st["pos"])), F["small"], MUTED_TEXT, "ra")

    # Volume slider
    muted = volume < 1
    knob = knob_x(volume)
    speaker(d, 188, SLIDER_Y - 10, muted, RED if muted else TEXT)
    rect(d, (SLIDER_X, SLIDER_Y - 2, SLIDER_X + SLIDER_W, SLIDER_Y + 2), 2, LINE)
    if not muted:
        rect(d, (SLIDER_X, SLIDER_Y - 2, knob, SLIDER_Y + 2), 2, GOLD)
    d.ellipse(px(knob - 6, SLIDER_Y - 6, knob + 6, SLIDER_Y + 6), fill=MUTED_TEXT if muted else TEXT)

    # The wizard stands below the player and reaches up with his staff.
    x, staff = wizard_at(t)
    walking = staff is None and (T_GAP - 1.6 < t < T_GAP - 0.4 or T_BACK + DRAG + 0.2 < t < T_BACK + DRAG + 1.4)
    wizard(d, x, t, staff, walking)
    if T_GAP + 0.3 < t < T_BACK - 0.5:
        bubble(d, x + 34, GROUND - 64, "You shall not pass!", F)

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
