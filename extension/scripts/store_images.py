"""Renders the Chrome Web Store images into extension/store/: three 1280x800
screenshots and a 440x280 promo tile. Drawn illustrations in the style of the
demo GIF; never screenshots of any real site.

Requires Pillow, and uses macOS's Helvetica Neue:

    python3 -m venv venv && venv/bin/pip install pillow
    venv/bin/python extension/scripts/store_images.py
"""

import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "docs" / "demo"))
import render as r  # noqa: E402

FONT = "/System/Library/Fonts/HelveticaNeue.ttc"
FACES = {"regular": 0, "bold": 1, "medium": 10}
SS = 2  # supersampling; drawing scales must keep SS * scale a whole number


def font(face, size):
    return ImageFont.truetype(FONT, size * SS, index=FACES[face])


def px(*v):
    return [x * SS for x in v]


def canvas(w, h):
    img = Image.new("RGB", (w * SS, h * SS), r.BG)
    return img, ImageDraw.Draw(img)


def rect(d, box, radius, fill):
    d.rounded_rectangle(px(*box), radius=radius * SS, fill=fill)


def text(d, xy, s, f, fill, anchor="la"):
    d.text(px(*xy), s, font=f, fill=fill, anchor=anchor)


def scaled(fn, scale):
    """Run one of the demo's drawing helpers at a different size."""
    old = r.S
    r.S = round(SS * scale)
    try:
        fn()
    finally:
        r.S = old


def wizard(img, x, ground, scale):
    """Paste the demo's wizard, feet at (x, ground), `scale` times its GIF size."""
    s = SS * scale
    layer = Image.new("RGBA", (int(140 * s), int(130 * s)), (0, 0, 0, 0))
    old_ground = r.GROUND
    r.GROUND = 120  # draw him at x=70 on the layer, feet at y=120
    scaled(lambda: r.wizard(ImageDraw.Draw(layer), 70, 0.2, None, False), scale)
    r.GROUND = old_ground
    img.paste(layer, (int((x - 70 * scale) * SS), int((ground - 120 * scale) * SS)), layer)


def bubble(d, x, y, s, f, tail="left"):
    """A speech bubble; (x, y) is the tip of its tail."""
    w = d.textlength(s, font=f) / SS + 44
    h = 46
    left = x + 14 if tail == "left" else x - 14 - w
    rect(d, (left, y - h / 2 - 12, left + w, y + h / 2 - 12), 16, r.TEXT)
    if tail == "left":
        d.polygon([tuple(px(left + 2, y - 14)), tuple(px(left + 2, y)), tuple(px(x, y + 4))], fill=r.TEXT)
    else:
        d.polygon([tuple(px(left + w - 2, y - 14)), tuple(px(left + w - 2, y)), tuple(px(x, y + 4))], fill=r.TEXT)
    text(d, (left + w / 2, y - 12), s, f, r.BG, "mm")


def speaker(d, x, y, muted, color, scale=1):
    scaled(lambda: r.speaker(d, x / scale, y / scale, muted, color), scale)


def equalizer(d, x, y, audible, color, scale=1):
    scaled(lambda: r.equalizer(d, x / scale, y / scale, 0.35, audible, color), scale)


def note(d, cx, cy, scale=1):
    scaled(lambda: r.note(d, cx / scale, cy / scale), scale)


def headline(d, w, title, sub):
    text(d, (w / 2, 92), title, font("bold", 52), r.TEXT, "mm")
    text(d, (w / 2, 150), sub, font("regular", 24), r.MUTED_TEXT, "mm")


def browser(d, box, tabs, active=0):
    """A generic browser window. tabs: [(title, sound)] where sound is None, "on" or "muted"."""
    x0, y0, x1, y1 = box
    rect(d, box, 16, r.CARD)
    rect(d, (x0, y0, x1, y0 + 54), 16, (19, 21, 26))
    d.rectangle(px(x0, y0 + 38, x1, y0 + 54), fill=(19, 21, 26))
    for i, c in enumerate(((229, 83, 75), (242, 184, 75), (87, 190, 110))):
        d.ellipse(px(x0 + 22 + i * 20, y0 + 21, x0 + 34 + i * 20, y0 + 33), fill=c)
    tx = x0 + 100
    for i, (title, sound) in enumerate(tabs):
        tw = 230
        if i == active:
            rect(d, (tx, y0 + 10, tx + tw, y0 + 62), 10, r.CARD)
        text(d, (tx + 18, y0 + 30), title, font("medium", 17), r.TEXT if i == active else r.MUTED_TEXT, "lm")
        if sound:
            speaker(d, tx + tw - 44, y0 + 20, sound == "muted", r.RED if sound == "muted" else r.TEXT, 1)
        tx += tw + 8


def player(d, box, title, interrupted, sub):
    """The demo's player card, drawn inside a browser window."""
    x0, y0, x1, _ = box
    art = r.GAP_ART if interrupted else r.SONG_ART
    rect(d, (x0, y0, x0 + 150, y0 + 150), 12, art)
    if interrupted:
        text(d, (x0 + 75, y0 + 75), "!", font("bold", 44), (150, 155, 165), "mm")
    else:
        note(d, x0 + 66, y0 + 92, 1.5)
    text(d, (x0 + 180, y0 + 14), title, font("bold", 30), r.TEXT)
    text(d, (x0 + 180, y0 + 56), sub, font("regular", 18), r.MUTED_TEXT)
    equalizer(d, x1 - 50, y0 + 6, not interrupted, r.RED if interrupted else r.GOLD, 1.5)
    rect(d, (x0 + 180, y0 + 108, x1, y0 + 113), 3, r.LINE)
    rect(d, (x0 + 180, y0 + 108, x0 + 180 + (x1 - x0 - 180) * (0.2 if interrupted else 0.62), y0 + 113), 3, r.TEXT)


def shot_hero():
    w, h = 1280, 800
    img, d = canvas(w, h)
    headline(d, w, "Interruptions, muted.", "When something interrupts what you're watching or listening to, the tab goes quiet.")
    browser(d, (90, 250, 900, 620), [("Your playlist", "muted"), ("Another tab", None)])
    player(d, (140, 350, 850, 0), "Interruption", True, "The tab stays quiet until it's over")
    wizard(img, 1075, 660, 2.5)
    bubble(d, 1010, 545, "You shall not pass!", font("bold", 22), tail="right")
    return img


def shot_steps():
    w, h = 1280, 800
    img, d = canvas(w, h)
    headline(d, w, "Then the sound comes back.", "Everything still plays in full. It only mutes the tab, then unmutes it.")
    steps = [("Your song", False, "on", "Playing"), ("Interruption", True, "muted", "Muted"), ("Your next song", False, "on", "Sound back")]
    for i, (title, interrupted, sound, label) in enumerate(steps):
        x0 = 70 + i * 390
        rect(d, (x0, 290, x0 + 360, 590), 16, r.CARD)
        rect(d, (x0 + 30, 320, x0 + 150, 440), 12, r.GAP_ART if interrupted else (r.SONG_ART if i == 0 else r.NEXT_ART))
        if interrupted:
            text(d, (x0 + 90, 380), "!", font("bold", 40), (150, 155, 165), "mm")
        else:
            note(d, x0 + 84, 396, 1)
        equalizer(d, x0 + 280, 330, not interrupted, r.RED if interrupted else r.GOLD, 1.5)
        text(d, (x0 + 30, 470), title, font("bold", 28), r.TEXT)
        speaker(d, x0 + 30, 522, sound == "muted", r.RED if sound == "muted" else r.TEXT, 1.5)
        text(d, (x0 + 90, 538), label, font("medium", 22), r.RED if sound == "muted" else r.GOLD, "lm")
        if i < 2:
            d.polygon([tuple(px(x0 + 366, 425)), tuple(px(x0 + 384, 440)), tuple(px(x0 + 366, 455))], fill=r.LINE)
    return img


def shot_trust():
    w, h = 1280, 800
    img, d = canvas(w, h)
    headline(d, w, "Stands watch, quietly.", "An over-engineered remote control that handles distractions for you.")
    points = [
        ("Doesn't block, skip, or change anything", "It only mutes the tab, like clicking its speaker icon."),
        ("You stay in charge", "Unmute the tab yourself and it stays unmuted."),
        ("Only the tab that's playing", "Other tabs and your computer's volume are never touched."),
        ("Collects nothing", "No account, no analytics. Nothing leaves your browser."),
        ("Open source", "Read every line on GitHub."),
    ]
    rect(d, (90, 230, 880, 730), 16, r.CARD)
    for i, (title, sub) in enumerate(points):
        y = 270 + i * 92
        d.ellipse(px(130, y + 4, 150, y + 24), fill=r.GOLD)
        text(d, (176, y), title, font("bold", 26), r.TEXT)
        text(d, (176, y + 36), sub, font("regular", 19), r.MUTED_TEXT)
    wizard(img, 1075, 730, 2.5)
    return img


def promo():
    w, h = 440, 280
    img, d = canvas(w, h)
    wizard(img, 105, 250, 1.5)
    text(d, (190, 112), "shall-not-pass", font("bold", 30), r.TEXT)
    text(d, (190, 152), "Stands watch so", font("regular", 19), r.MUTED_TEXT)
    text(d, (190, 178), "you don't have to.", font("regular", 19), r.MUTED_TEXT)
    return img


def main():
    out = ROOT / "extension" / "store"
    out.mkdir(exist_ok=True)
    for name, fn, size in (
        ("screenshot-1.png", shot_hero, (1280, 800)),
        ("screenshot-2.png", shot_steps, (1280, 800)),
        ("screenshot-3.png", shot_trust, (1280, 800)),
        ("promo-small.png", promo, (440, 280)),
    ):
        fn().resize(size, Image.LANCZOS).save(out / name)
        print(f"Wrote extension/store/{name}")


if __name__ == "__main__":
    main()
