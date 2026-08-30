#!/usr/bin/env python3
"""Derive every launch/icon asset from assets/icon/AppLogo.png.

Run this whenever the logo changes, then re-run both generators:

    python3 tool/logo_assets.py
    dart run flutter_native_splash:create
    dart run flutter_launcher_icons
    python3 tool/logo_assets.py --web-maskable   # must follow the line above

The last step exists because flutter_launcher_icons writes the maskable web
icons as byte-identical copies of the ordinary ones, and a maskable icon may
be cropped to a circle 80% across. At the size that suits a favicon the mark
then fills 92% of that circle and looks cramped, so those two files are
redrawn smaller afterwards.

Needs Pillow and NumPy (`pip install pillow numpy`); nothing in the app
depends on them, this is a build-time script only.

Why it exists rather than hand-exported PNGs:

* The master is a lossy raster. Its two greens measure #365A27 and ~#95C259
  with per-pixel noise, and the transparent edge is matted against black, so
  scaling it directly drags a dark fringe onto the cream splash. This rebuilds
  the mark as two flat masks and repaints them, so every derived file is clean
  at whatever size the platform asks for.
* The two greens are snapped to design tokens (docs/design-tokens.md), which
  keeps the logo and the UI on literally the same values. The measured pair
  sits at 3.83:1 against each other; the token pair at 3.77:1 — the same
  relationship the artwork was drawn with.
* Each platform wants a different canvas and safe area, and getting those
  wrong is invisible until it ships clipped.
"""

from PIL import Image, ImageFilter
import numpy as np
import math
import os
import sys

SRC = 'assets/icon/AppLogo.png'
OUT = 'assets/icon'

# Design tokens — see docs/design-tokens.md §1.
PRIMARY = '#4A672D'   # the R, light mode
GROWTH = '#A8D46F'    # the rays, both modes
PRIM_CONTAINER = '#CBEEA5'  # the R, dark mode: #4A672D on #12140E is 1.9:1
SURFACE = '#F9FAEF'

# Adaptive icons are 108dp with only the middle 72dp guaranteed visible.
# 66/108 is the keyline circle — the largest content may be without being
# clipped by a circular mask — and it is a limit, not a target: at that size
# the mark's enclosing circle fills 92% of the visible circle and the icon
# reads as cramped. 0.50 puts it at 75%, which is the same proportion the
# square icon below carries (0.58 * 1.263 = 0.73 of its width).
ADAPTIVE_SAFE = 0.50

# The mark inside the square icon, as a fraction of the canvas width. 0.68 was
# tight against the edges once iOS rounds the corners.
ICON_SCALE = 0.58

# A PWA maskable icon may be cropped to a circle 80% of the canvas across.
# 0.475 * 1.263 / 0.80 puts the mark at 75% of that circle — the same
# proportion ADAPTIVE_SAFE gives inside Android's.
MASKABLE_SCALE = 0.475
WEB_MASKABLE = ['web/icons/Icon-maskable-192.png', 'web/icons/Icon-maskable-512.png']
# Android 12 splash: 1152px canvas, icon inside a 768px circle.
A12_CANVAS, A12_CIRCLE = 1152, 768


def hexrgb(h):
    h = h.lstrip('#')
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def masks(path):
    """Split the mark into a dark mask and a light mask, both binary.

    Pixels that are fully opaque are classified by luminance; the partly
    transparent rim is then grown out from whichever core it touches, so the
    black matting in the source never decides a colour.
    """
    im = Image.open(path).convert('RGBA')
    a = np.asarray(im).astype(np.int16)
    rgb, al = a[..., :3], a[..., 3]
    lum = 0.2126 * rgb[..., 0] + 0.7152 * rgb[..., 1] + 0.0722 * rgb[..., 2]
    shape = al >= 100
    hard = al >= 250
    dark, light = hard & (lum < 125), hard & (lum >= 125)

    def grow(m):
        g = Image.fromarray((m * 255).astype(np.uint8)).filter(ImageFilter.MaxFilter(3))
        return np.asarray(g) > 127

    def shrink(m, n):
        g = Image.fromarray((m * 255).astype(np.uint8))
        for _ in range(n):
            g = g.filter(ImageFilter.MinFilter(3))
        return np.asarray(g) > 127

    # The master was compressed, so every dark edge carries a ring of lighter
    # pixels from the ringing. They are fully opaque and read as green, so a
    # straight luminance split hands them to the light class and paints a 1px
    # Growth-Green outline around the R. Erode both classes past the ring
    # first; the growth loop below then re-partitions the rim by distance,
    # which puts it back where it belongs.
    dark, light = shrink(dark, 4), shrink(light, 4)

    for _ in range(30):
        nd, nl = grow(dark) & shape & ~light, grow(light) & shape & ~dark
        if (nd == dark).all() and (nl == light).all():
            break
        dark, light = nd, nl
    return dark, light


def geometry(union):
    """Bounding box and smallest enclosing circle of the mark."""
    ys, xs = np.nonzero(union)
    box = (int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1)
    pts = np.stack([xs, ys], 1).astype(np.float64)
    if len(pts) > 200000:
        pts = pts[np.random.default_rng(0).choice(len(pts), 200000, replace=False)]
    c = np.array([(box[0] + box[2]) / 2, (box[1] + box[3]) / 2])
    step = max(box[2] - box[0], box[3] - box[1]) / 4
    while step > 0.05:
        best = min(
            ((np.sqrt(((pts - (c + np.array([dx, dy]) * step)) ** 2).sum(1)).max(),
              c + np.array([dx, dy]) * step)
             for dx in (-1, 0, 1) for dy in (-1, 0, 1)),
            key=lambda t: t[0])
        if np.allclose(best[1], c):
            step /= 2
        c = best[1]
    return box, float(np.sqrt(((pts - c) ** 2).sum(1)).max()) * 2


def render(dark, light, box, canvas, content_w, colours, background=None):
    """Paint the two masks flat at `content_w` px wide, centred on `canvas`."""
    x0, y0, x1, y1 = box
    scale = content_w / (x1 - x0)
    size = (int(round((x1 - x0) * scale)), int(round((y1 - y0) * scale)))
    out = Image.new('RGBA', (canvas, canvas),
                    hexrgb(background) + (255,) if background else (0, 0, 0, 0))
    for mask, colour in ((light, colours[1]), (dark, colours[0])):
        m = Image.fromarray((mask[y0:y1, x0:x1] * 255).astype(np.uint8))
        # BOX on a downscale is a plain area average — exactly the coverage
        # each output pixel has, which is what antialiasing should be.
        m = m.resize(size, Image.BOX)
        layer = Image.new('RGBA', size, hexrgb(colour) + (0,))
        layer.putalpha(m)
        out.alpha_composite(layer, ((canvas - size[0]) // 2, (canvas - size[1]) // 2))
    return out


def web_maskable():
    """Redraw the maskable web icons that flutter_launcher_icons just copied."""
    dark, light = masks(SRC)
    box, _ = geometry(dark | light)
    for path in WEB_MASKABLE:
        if not os.path.exists(path):
            print(f'  {path} missing — run `dart run flutter_launcher_icons` first')
            continue
        n = Image.open(path).size[0]
        im = render(dark, light, box, n, n * MASKABLE_SCALE, (PRIMARY, GROWTH),
                    background=SURFACE)
        im.save(path)
        print(f'  {path:34} {n}x{n}')


def main():
    if '--web-maskable' in sys.argv:
        web_maskable()
        return
    dark, light = masks(SRC)
    box, circle = geometry(dark | light)
    bw = box[2] - box[0]
    ratio = circle / bw  # enclosing circle relative to the mark's width
    print(f'mark {bw}x{box[3] - box[1]}, enclosing circle {circle:.0f} '
          f'({ratio:.3f}x its width)')

    def save(name, im):
        im.save(os.path.join(OUT, name))
        print(f'  {name:32} {im.size[0]}x{im.size[1]}')

    light_pair = (PRIMARY, GROWTH)
    dark_pair = (PRIM_CONTAINER, GROWTH)

    # Legacy splash. flutter_native_splash treats the source as 4x, so 512
    # lands as 128dp — the old 256px mark showed at 64dp and read as an
    # afterthought.
    save('AppLogoSplash.png', render(dark, light, box, 512, 512, light_pair))
    save('AppLogoSplashDark.png', render(dark, light, box, 512, 512, dark_pair))

    # Android 12+ splash, mark inside the 768 circle.
    a12 = A12_CIRCLE / ratio
    save('AppLogoAndroid12.png',
         render(dark, light, box, A12_CANVAS, a12, light_pair))
    save('AppLogoAndroid12Dark.png',
         render(dark, light, box, A12_CANVAS, a12, dark_pair))

    # Adaptive icon foreground + Android 13 monochrome, same geometry so the
    # themed icon lands where the coloured one does.
    adaptive = 1024 * ADAPTIVE_SAFE / ratio
    save('AppLogoAdaptive.png',
         render(dark, light, box, 1024, adaptive, light_pair))
    save('AppLogoMonochrome.png',
         render(dark, light, box, 1024, adaptive, ('#FFFFFF', '#FFFFFF')))

    # Square icon for iOS / web / desktop / Android legacy. Opaque: an iOS app
    # icon may not carry alpha. At ICON_SCALE the enclosing circle is 0.73 of
    # the canvas, which also clears the 0.80 circle a PWA maskable icon may be
    # cropped to — so web shares this file rather than needing a smaller one.
    save('AppLogoIcon.png',
         render(dark, light, box, 1024, 1024 * ICON_SCALE, light_pair, background=SURFACE))
    # iOS 18 dark and tinted variants composite over the system's own ground.
    save('AppLogoIconDark.png',
         render(dark, light, box, 1024, 1024 * ICON_SCALE, dark_pair))


if __name__ == '__main__':
    main()
