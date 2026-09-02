#!/usr/bin/env python3
"""Frames raw device captures into Google Play screenshots.

Why this exists: the phone these were taken on is 1096x2560, a ratio of
1:2.34. Play refuses a phone screenshot whose long side is more than twice its
short side, so the raw file is rejected before anybody looks at it. Framing on
a 1440x2560 canvas (9:16) fixes the ratio and buys room for a headline, which
is what the listing wanted anyway.

    python3 tool/play_screenshots.py <capture-dir> <out-dir> [phone|tablet7|tablet10]

Play keeps a separate set per form factor, and the tablet slots want landscape
panels — a tablet listing assembled out of portrait phone panels is exactly
what "not designed for tablets" looks like on the store page. So the tablet
layouts turn the panel on its side and put the headline in a column beside the
device rather than above it; see frame_landscape.

Captures are matched to headlines by the number their filename starts with
(01-*.png, 02-*.png, ...), not by position, so one panel can be re-shot alone.
"""

import sys
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter, ImageFont

OLIVE = (74, 108, 45)
LEAF = (165, 206, 113)
CREAM = (245, 246, 238)
INK = (30, 38, 26)

# (path, ttc face index). Tried in order, first that loads wins — a .ttc holds
# several faces and the index is which one, so Helvetica Neue Bold is face 1 of
# the same file as its Regular.
#
# Latin faces, because the listing is English (play/listing-en-US.md). These
# were STHeiti Medium/Light, which are Chinese families: they do render Latin,
# but as the fallback glyphs of a CJK font — wrong proportions, wrong spacing,
# and visibly not what the rest of the page is set in. When Revenue is
# localised, PANELS_ZH below comes back and so do those two paths.
BOLD_CANDIDATES = [
    ("/System/Library/Fonts/HelveticaNeue.ttc", 1),   # Bold
    ("/System/Library/Fonts/Supplemental/Arial Bold.ttf", 0),
]
LIGHT_CANDIDATES = [
    ("/System/Library/Fonts/HelveticaNeue.ttc", 7),   # Light
    ("/System/Library/Fonts/Supplemental/Arial.ttf", 0),
]

W, H = 1440, 2560          # 9:16 — comfortably inside Play's 2:1 limit
SIDE = 150                 # margin either side of the device image

# (width, height, orientation) per Play form-factor slot. Every one of these is
# inside the 320..3840 per-side bounds and at a ratio of 1.6 or 1.78, so none
# of them can be rejected on geometry.
#
# The two tablet sizes are the same shape because Play's 7-inch and 10-inch
# slots have identical image rules — what actually differs is the layout the
# app draws, which is why the captures for each are taken at that tablet's own
# dp size rather than one set being a resize of the other.
LAYOUTS = {
    "phone":    (1440, 2560, "portrait"),
    "tablet7":  (1920, 1200, "landscape"),
    "tablet10": (2560, 1600, "landscape"),
}

# (headline, sub-line, dark background?)
#
# Six panels, and the order is an argument rather than a tour: what you sold,
# what it earned, that it keeps working, that setting it up is not a chore,
# what the numbers do over time, and that it is safe to hand to staff. Somebody
# swiping a listing stops after two or three, so the two that matter most are
# first.
PANELS_EN = [
    ("Today, at\na glance",
     "Takings, orders, and how far off target", False),
    ("Which dishes\nactually earn",
     "The thing a bestseller list cannot show you", True),
    ("Keeps trading when\nthe Wi-Fi doesn't",
     "Orders wait on the till and send themselves", False),
    ("Photograph the menu\ninstead of typing it",
     "Read into dishes and prices. Nothing saves until you say so", True),
    ("Takings you\ncan read",
     "Day, week, month — and out to Excel", False),
    # Was "Everyone sees what they should — staff take orders; prices and
    # settings stay read-only". True of the app, but it cannot be photographed
    # from an owner's account: the padlocks only appear for a member of staff,
    # and the demo store has one login. A caption promising something the
    # screenshot beneath it does not show is the kind of small lie a listing
    # does not need — the roles are described in the full description instead,
    # where words are the right medium for them.
    ("The rules your shop\nactually runs on",
     "Trading day cutoff, tax, payment methods, delivery commission", True),
]

# Kept for when the app is localised — see play/listing-zh-TW.md. Publishing
# these over an English app is the mismatch that earns a one-star review, which
# is why PANELS points at the English set.
PANELS_ZH = [
    ("今天賣了多少\n一眼看完", "營收、訂單數、離目標還差多少", False),
    ("哪道菜\n真的在賺錢", "暢銷排行看不出來的事，這裡看得出來", True),
    ("斷線\n也能做生意", "訂單先存在這台裝置裡，連上線自動補送", False),
    ("菜單用拍的\n不用一個一個打", "拍照辨識成菜名與價格，你確認後才寫入", True),
    ("看得懂的\n營收走勢", "日、週、月，可匯出 Excel", False),
    ("每個人\n該看到的不一樣", "店員點單，設定唯讀；改單超過五分鐘要管理者", True),
]

PANELS = PANELS_EN


def resolve(candidates):
    """The first candidate face that actually loads.

    A hard-coded font path is a script that works on the machine it was written
    on. Falling through a list means a missing family degrades to a plainer one
    rather than stopping the run with an OSError three steps before any output.
    """
    for path, index in candidates:
        try:
            ImageFont.truetype(path, 24, index=index)
            return (path, index)
        except OSError:
            continue
    raise SystemExit(
        "No usable font. Edit BOLD_CANDIDATES / LIGHT_CANDIDATES at the top of "
        "this file to point at one that exists on this machine."
    )


BOLD = resolve(BOLD_CANDIDATES)
LIGHT = resolve(LIGHT_CANDIDATES)


def font(face, size):
    path, index = face
    return ImageFont.truetype(path, size, index=index)


def fit(draw, text, face, start, maxw):
    size = start
    while size > 12 and draw.textlength(text, font=font(face, size)) > maxw:
        size -= 1
    return font(face, size)


def shadow(canvas, box, radius, dark, s=1.0):
    """Drops a soft shadow behind the device.

    Needed because the app's light theme is Warm Cream and so is the light
    panel — near enough the same value that the phone had no edge at all on
    panels 1, 3 and 5 and read as a texture rather than as a device. On the
    olive panels the contrast already does this job; the shadow is drawn on
    both so the six read as one set.

    Blurred at four times the offset so it stays a shadow rather than becoming
    a second rectangle, and kept weak on the dark panels, where a black shadow
    on a dark ground is only mud.
    """
    x, y, w, h = box
    pad = int(60 * s)
    layer = Image.new("L", (w + pad * 2, h + pad * 2), 0)
    ImageDraw.Draw(layer).rounded_rectangle(
        [pad, pad, pad + w, pad + h], radius=radius, fill=90 if dark else 130)
    layer = layer.filter(ImageFilter.GaussianBlur(28 * s))
    tint = Image.new("RGB", layer.size, (18, 24, 14))
    canvas.paste(tint, (x - pad, y - pad + int(14 * s)), layer)


def rounded(img, radius):
    mask = Image.new("L", img.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        [0, 0, img.size[0] - 1, img.size[1] - 1], radius=radius, fill=255)
    out = img.convert("RGB")
    out.putalpha(mask)
    return out


def frame(shot_path, headline, sub, dark, out_path):
    """Lays the headline out first, then gives the device whatever is left.

    A fixed device offset was wrong: a two-line headline at 96px plus a
    sub-line runs past any constant you pick, and the screenshot then lands on
    top of the words. Measuring the text block and flowing the device below it
    means a longer headline shrinks the device rather than colliding with it.
    """
    bg = OLIVE if dark else CREAM
    fg = CREAM if dark else OLIVE
    subfg = (205, 224, 186) if dark else (110, 122, 102)

    canvas = Image.new("RGB", (W, H), bg)
    d = ImageDraw.Draw(canvas)
    avail = W - SIDE * 2

    d.line([(SIDE + 2, 108), (SIDE + 92, 108)], fill=LEAF, width=7)

    lines = headline.split("\n")
    f_head = min((fit(d, ln, BOLD, 92, avail) for ln in lines),
                 key=lambda f: f.size)
    y = 158
    for ln in lines:
        d.text((SIDE, y), ln, font=f_head, fill=fg)
        y += int(f_head.size * 1.22)

    f_sub = fit(d, sub, LIGHT, 36, avail)
    y += 12
    d.text((SIDE, y), sub, font=f_sub, fill=subfg)
    y += int(f_sub.size * 1.5)

    top = y + 76
    shot = Image.open(shot_path).convert("RGB")
    room_h = H - top - 70
    scale = min(avail / shot.width, room_h / shot.height)
    shot = shot.resize((int(shot.width * scale), int(shot.height * scale)),
                       Image.LANCZOS)
    shot = rounded(shot, 44)
    x = (W - shot.width) // 2
    # Centred in the room left over, not pinned under the headline. A capture
    # cropped to its interesting half — the import screen is mostly empty below
    # the buttons — is shorter than the space available, and pinning it to the
    # top left the whole bottom third of the panel bare while the device
    # huddled under the text. Full-height captures are unaffected: their scale
    # is already limited by the room, so the offset works out at zero.
    y = top + max(0, (room_h - shot.height) // 2)
    shadow(canvas, (x, y, shot.width, shot.height), 44, dark)
    canvas.paste(shot, (x, y), shot)

    canvas.save(out_path, "PNG")
    return canvas.size


def frame_landscape(shot_path, headline, sub, dark, out_path, W, H):
    """Lays a landscape tablet capture out as headline-left, device-right.

    The portrait frame cannot be reused for these. A tablet capture is 16:10
    the other way up: dropped into a 9:16 panel underneath a headline it
    shrinks to a strip across the middle and leaves two thirds of the panel
    empty. Turning the panel on its side and giving the headline a column
    beside the device keeps the device large enough to read the app in, and
    lands at a ratio of 1.6 — well inside Play's 2:1 limit at both sizes.

    Everything is expressed against the 10-inch canvas and scaled by `s`, so
    the 7-inch panel is the same design rather than a second set of constants
    that drift apart the first time a margin is adjusted.
    """
    s = W / 2560.0
    px = lambda v: max(1, int(round(v * s)))

    bg = OLIVE if dark else CREAM
    fg = CREAM if dark else OLIVE
    subfg = (205, 224, 186) if dark else (110, 122, 102)

    canvas = Image.new("RGB", (W, H), bg)
    d = ImageDraw.Draw(canvas)

    margin, text_w, gap = px(130), px(820), px(80)

    # The text block is measured before it is drawn so it can be centred
    # against the device. Pinning it to the top is what the portrait frame
    # does, and it works there because the device fills everything below;
    # here the column is short and a top-pinned headline leaves the bottom
    # half of it conspicuously bare.
    lines = headline.split("\n")
    f_head = min((fit(d, ln, BOLD, px(76), text_w) for ln in lines),
                 key=lambda f: f.size)
    f_sub = fit(d, sub, LIGHT, px(32), text_w)
    rule_gap = px(50)
    block = (rule_gap + int(f_head.size * 1.22) * len(lines)
             + px(12) + int(f_sub.size * 1.4))
    y = (H - block) // 2

    d.line([(margin + px(2), y), (margin + px(92), y)], fill=LEAF, width=px(7))
    y += rule_gap
    for ln in lines:
        d.text((margin, y), ln, font=f_head, fill=fg)
        y += int(f_head.size * 1.22)
    y += px(12)
    d.text((margin, y), sub, font=f_sub, fill=subfg)

    box_x = margin + text_w + gap
    box_w = W - margin - box_x
    box_h = H - margin * 2
    shot = Image.open(shot_path).convert("RGB")
    scale = min(box_w / shot.width, box_h / shot.height)
    shot = shot.resize((int(shot.width * scale), int(shot.height * scale)),
                       Image.LANCZOS)
    radius = px(30)
    shot = rounded(shot, radius)
    x = box_x + (box_w - shot.width) // 2
    y = (H - shot.height) // 2
    shadow(canvas, (x, y, shot.width, shot.height), radius, dark, s)
    canvas.paste(shot, (x, y), shot)

    canvas.save(out_path, "PNG")
    return canvas.size


def main():
    if len(sys.argv) not in (3, 4):
        print(__doc__)
        return 1
    mode = sys.argv[3] if len(sys.argv) == 4 else "phone"
    if mode not in LAYOUTS:
        print(f"Unknown layout {mode!r} — one of {', '.join(LAYOUTS)}")
        return 1
    width, height, orientation = LAYOUTS[mode]
    src, dst = Path(sys.argv[1]), Path(sys.argv[2])
    dst.mkdir(parents=True, exist_ok=True)
    # Paired by the number the filename starts with, not by position in the
    # sorted list.
    #
    # Position was wrong the moment a panel was missing: capturing 01, 02, 04
    # and 05 handed 04 the caption written for 03, and every later shot was
    # off by one — silently, because the output still looked like six good
    # files. Reading the number means a panel can be re-shot on its own and the
    # rest do not have to be taken again to keep their captions.
    shots = {}
    for path in sorted(src.glob("*.png")):
        if path.name.startswith("_"):
            continue
        digits = ""
        for char in path.name:
            if not char.isdigit():
                break
            digits += char
        if not digits:
            print(f"Skipped {path.name} — filename must start with the panel "
                  f"number, e.g. 03-offline.png")
            continue
        index = int(digits)
        if not 1 <= index <= len(PANELS):
            print(f"Skipped {path.name} — no panel {index} (there are "
                  f"{len(PANELS)})")
            continue
        shots[index] = path

    if not shots:
        print(f"No numbered captures in {src}")
        return 1

    missing = [n for n in range(1, len(PANELS) + 1) if n not in shots]
    if missing:
        print(f"Not yet captured: {', '.join(f'{n:02d}' for n in missing)}\n")

    for index in sorted(shots):
        shot = shots[index]
        headline, sub, dark = PANELS[index - 1]
        out = dst / f"{index:02d}.png"
        if orientation == "portrait":
            size = frame(shot, headline, sub, dark, out)
        else:
            size = frame_landscape(shot, headline, sub, dark, out,
                                   width, height)
        ratio = max(size) / min(size)
        ok = "ok" if ratio <= 2.0 and 320 <= min(size) and max(size) <= 3840 else "REJECTED"
        print(f"{out.name}  {size[0]}x{size[1]}  ratio {ratio:.2f}  {ok}  <- {shot.name}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
