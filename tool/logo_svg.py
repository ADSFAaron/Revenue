#!/usr/bin/env python3
"""Emit assets/icon/AppLogo.svg — the mark as geometry rather than as pixels.

    python3 tool/logo_svg.py

Why this exists
---------------

The mark only ever had a raster master, `assets/icon/AppLogo.png`, and
tool/logo_assets.py rebuilds it into flat masks to derive every launch and icon
asset from it. That is enough to produce clean PNGs at any size, but it cannot
give you the mark as *parts* — and an opening animation needs the ray to be a
ray and the stem to be a stem, each able to move on its own.

Tracing the raster would have produced a polygon soup that is vector in name
only. The mark is not organic: it is a rectangle, a circular arc of constant
width, a circle, a tapered bar, and four tapered capsules. So every number below
was measured off the mask and the model checked against it — see `verify()`,
which rasterises this geometry and compares it with the real mask. The
reconstruction agrees to an intersection-over-union of 0.991, the remainder
being the one-pixel antialiased rim around a 6000px perimeter.

Where the measurements came from
--------------------------------

* The bowl's two edges are least-squares circle fits, residual mean 0.35px and
  0.30px, and they come out concentric to 3px with a gap of 148.6px — the same
  width as the stem, which is what says the mark was drawn with one stroke
  weight rather than eyeballed.
* The bowl's end is a straight cut, not a radial one, and its slope (1.0475) is
  the leg's slope (1.0625). It is cut parallel to the leg on purpose; a radial
  cut is visibly wrong next to it and was the last thing the model got wrong.
* Each ray is the convex hull of two circles. Fitting the half-width along the
  axis gives a straight line to within 0.6px, which is what makes that the right
  model rather than a taper with curved sides.

This does NOT yet feed logo_assets.py, which still rasterises the PNG master.
Doing that needs an SVG rasteriser in the build environment; until then the two
are kept honest by `verify()`.
"""

import math
import sys

import numpy as np

# --- design tokens, the same values logo_assets.py uses (docs/design-tokens.md)
PRIMARY = '#4A672D'   # the R
GROWTH = '#A8D46F'    # the rays

# --- geometry, measured from assets/icon/AppLogo.png (1600x1580) -------------
STEM_X0, STEM_X1 = 76.0, 226.0
BASE_Y = 1472.0
BOWL_CX, BOWL_CY = 473.9, 677.8
BOWL_RO, BOWL_RI = 342.2, 193.6

# The flat top is the arc's own apex, and the top bar stops at the tangent
# point. Measured independently these disagreed by 2.6px — the topmost row of
# ink is at y=333 and the arc crowns at 335.6 — and because the bar ran on to
# x=515 past the tangent point, the arc had already fallen 5px away beneath its
# top edge by the time the two met. That corner is meant to be one continuous
# line and instead had a step chipped out of it.
#
# Derived rather than measured, so the two cannot drift apart again. It costs
# about three thousandths of IoU against the raster master, which is the master
# admitting it has the step too: it is a lossy export, and a scan of tangent
# positions puts the best fit within half a pixel of this one.
TOP_Y = BOWL_CY - BOWL_RO

DOT_CX, DOT_CY, DOT_R = 421.5, 865.4, 120.9

LEG_ML, LEG_BL = 0.9412, -507.8    # left edge,  x = m*y + b
LEG_MR, LEG_BR = 0.9703, -348.1    # right edge
LEG_TOP_Y = DOT_CY                 # hidden inside the dot

END_M, END_B = 1.0475, 230.8       # bowl end face, y = m*x + b

# Each ray is a tapered bar with rounded corners: four corners and one radius.
# A hull of two circles was the obvious first model and it is wrong — the ends
# are very nearly flat, so circular caps cut the tips off and cost four points
# of IoU. Measured by fitting the two long edges and then searching the end
# positions and the corner radius against the mask.
RAYS = [
    ([(1518.4, 513.0), (1452.9, 379.8), (913.6, 686.2), (946.3, 752.7)], 22.0),
    ([(1340.2, 176.3), (1228.8, 78.9), (877.0, 526.7), (943.0, 584.5)], 19.0),
    ([(1479.5, 889.5), (1465.9, 735.0), (889.7, 826.4), (896.2, 900.0)], 22.0),
    ([(829.2, 953.3), (795.8, 1023.1), (1189.6, 1250.6), (1253.5, 1116.8)], 25.0),
]

CANVAS_W, CANVAS_H = 1600, 1580


def line_circle(m, b, cx, cy, r):
    """Both intersections of y = m*x + b with a circle, left to right."""
    # (x-cx)^2 + (m*x + b - cy)^2 = r^2
    A = 1 + m * m
    B = -2 * cx + 2 * m * (b - cy)
    C = cx * cx + (b - cy) ** 2 - r * r
    disc = B * B - 4 * A * C
    if disc < 0:
        raise ValueError('the end face misses the arc')
    root = math.sqrt(disc)
    xs = sorted(((-B - root) / (2 * A), (-B + root) / (2 * A)))
    return [(x, m * x + b) for x in xs]


def bowl_path():
    """The arc of constant width, from the top round to the straight end cut."""
    # Outer and inner arcs both start at 12 o'clock, directly above the centre.
    o_start = (BOWL_CX, BOWL_CY - BOWL_RO)
    i_start = (BOWL_CX, BOWL_CY - BOWL_RI)
    # The cut crosses each circle twice; the end of the sweep is the right-hand
    # one on the outer circle and, on the inner, the one that keeps the width.
    o_end = line_circle(END_M, END_B, BOWL_CX, BOWL_CY, BOWL_RO)[1]
    i_end = line_circle(END_M, END_B, BOWL_CX, BOWL_CY, BOWL_RI)[1]
    return (
        f'M {o_start[0]:.1f} {o_start[1]:.1f} '
        f'A {BOWL_RO:.1f} {BOWL_RO:.1f} 0 0 1 {o_end[0]:.1f} {o_end[1]:.1f} '
        f'L {i_end[0]:.1f} {i_end[1]:.1f} '
        f'A {BOWL_RI:.1f} {BOWL_RI:.1f} 0 0 0 {i_start[0]:.1f} {i_start[1]:.1f} '
        f'Z'
    )


def top_path():
    """The solid block above the counter, bounded on the right by the arc.

    A rectangle stopping at the tangent point would be geometrically right and
    still wrong to look at: it and the bowl would share an edge rather than
    overlap, and two antialiased shapes meeting along a line leave a visible
    seam down it whatever their fill. Ending this block *on* the arc makes the
    two overlap in area, so there is no shared edge to show through, and it
    costs no accuracy because the arc is where the shape really ends.
    """
    # Where the outer arc has come down to the top of the counter.
    x_end = BOWL_CX + math.sqrt(BOWL_RO ** 2 - BOWL_RI ** 2)
    y_end = BOWL_CY - BOWL_RI
    return (
        f'M {STEM_X0:.1f} {TOP_Y:.1f} '
        f'L {BOWL_CX:.1f} {TOP_Y:.1f} '
        f'A {BOWL_RO:.1f} {BOWL_RO:.1f} 0 0 1 {x_end:.1f} {y_end:.1f} '
        f'L {STEM_X0:.1f} {y_end:.1f} '
        f'Z'
    )


def leg_path():
    def at(y):
        return LEG_ML * y + LEG_BL, LEG_MR * y + LEG_BR
    l0, r0 = at(LEG_TOP_Y)
    l1, r1 = at(BASE_Y)
    return (f'M {l0:.1f} {LEG_TOP_Y:.1f} L {r0:.1f} {LEG_TOP_Y:.1f} '
            f'L {r1:.1f} {BASE_Y:.1f} L {l1:.1f} {BASE_Y:.1f} Z')


def ray_path(corners, rho):
    """A convex quadrilateral with every corner rounded to the same radius."""
    n = len(corners)
    # Signed area decides which way the arcs sweep; the fit does not guarantee
    # a winding direction and the wrong flag turns each corner inside out.
    area = sum(corners[i][0] * corners[(i + 1) % n][1]
               - corners[(i + 1) % n][0] * corners[i][1] for i in range(n))
    sweep = 1 if area > 0 else 0

    parts = []
    for i in range(n):
        p = corners[i]
        prv = corners[(i - 1) % n]
        nxt = corners[(i + 1) % n]
        u1 = _unit(prv[0] - p[0], prv[1] - p[1])
        u2 = _unit(nxt[0] - p[0], nxt[1] - p[1])
        half = math.acos(max(-1.0, min(1.0, u1[0] * u2[0] + u1[1] * u2[1]))) / 2
        back = rho / math.tan(half)
        a = (p[0] + u1[0] * back, p[1] + u1[1] * back)
        b = (p[0] + u2[0] * back, p[1] + u2[1] * back)
        parts.append(('M' if i == 0 else 'L') + f' {a[0]:.1f} {a[1]:.1f}')
        parts.append(f'A {rho:.1f} {rho:.1f} 0 0 {sweep} {b[0]:.1f} {b[1]:.1f}')
    return ' '.join(parts) + ' Z'


def _unit(x, y):
    d = math.hypot(x, y)
    return (x / d, y / d)


def svg():
    rays = '\n'.join(
        f'    <path id="ray-{i + 1}" d="{ray_path(c, rho)}"/>'
        for i, (c, rho) in enumerate(RAYS)
    )
    return f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {CANVAS_W} {CANVAS_H}">
  <!-- Generated by tool/logo_svg.py from measurements of AppLogo.png.
       Every shape is separately addressable on purpose: the opening animation
       moves the rays independently of the letter. -->
  <g id="mark-r" fill="{PRIMARY}">
    <path id="r-top" d="{top_path()}"/>
    <path id="r-stem" d="M {STEM_X0:.1f} {TOP_Y:.1f} L {STEM_X1:.1f} {TOP_Y:.1f} L {STEM_X1:.1f} {BASE_Y:.1f} L {STEM_X0:.1f} {BASE_Y:.1f} Z"/>
    <path id="r-bowl" d="{bowl_path()}"/>
    <path id="r-leg" d="{leg_path()}"/>
    <circle id="r-dot" cx="{DOT_CX:.1f}" cy="{DOT_CY:.1f}" r="{DOT_R:.1f}"/>
  </g>
  <g id="mark-rays" fill="{GROWTH}">
{rays}
  </g>
</svg>
'''


def verify(mask_path='assets/icon/AppLogo.png'):
    """Rasterise this geometry and score it against the real mask."""
    import importlib.util
    spec = importlib.util.spec_from_file_location('la', 'tool/logo_assets.py')
    la = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(la)
    dark, light = la.masks(mask_path)

    H, W = dark.shape
    Y, X = np.mgrid[0:H, 0:W]

    stem = (X >= STEM_X0) & (X < STEM_X1) & (Y >= TOP_Y) & (Y < BASE_Y)
    # Bounded by the arc on the right only — not by the disc, which would cut
    # the left of the block away as well.
    arc_right = BOWL_CX + np.sqrt(
        np.clip(BOWL_RO ** 2 - (Y - BOWL_CY) ** 2, 0, None))
    top = ((X >= STEM_X0) & (X <= arc_right)
           & (Y >= TOP_Y) & (Y < BOWL_CY - BOWL_RI))
    r = np.hypot(X - BOWL_CX, Y - BOWL_CY)
    ang = np.degrees(np.arctan2(Y - BOWL_CY, X - BOWL_CX))
    bowl = (r >= BOWL_RI) & (r <= BOWL_RO) & (ang >= -90) & (Y <= END_M * X + END_B)
    dot = np.hypot(X - DOT_CX, Y - DOT_CY) <= DOT_R
    leg = ((X >= LEG_ML * Y + LEG_BL) & (X <= LEG_MR * Y + LEG_BR)
           & (Y >= LEG_TOP_Y) & (Y < BASE_Y))
    model_dark = stem | top | bowl | dot | leg

    model_light = np.zeros_like(light)
    for corners, rho in RAYS:
        # A rounded polygon is the Minkowski sum of the polygon shrunk by rho
        # with a disc of rho — so "within rho of the shrunk outline" is the
        # whole test, and it shares no code with ray_path()'s arc construction.
        c = np.array(corners, float)
        cen = c.mean(0)
        inner = []
        for i in range(4):
            p, prv, nxt = c[i], c[(i - 1) % 4], c[(i + 1) % 4]
            u1 = (prv - p) / np.linalg.norm(prv - p)
            u2 = (nxt - p) / np.linalg.norm(nxt - p)
            bis = u1 + u2
            bis /= np.linalg.norm(bis)
            half = math.acos(float(np.clip(u1 @ u2, -1, 1))) / 2
            inner.append(p + bis * (rho / math.sin(half)))
        inner = np.array(inner)
        shape = np.zeros_like(light)
        interior = np.ones_like(light)
        for i in range(4):
            a, b = inner[i], inner[(i + 1) % 4]
            vx, vy = b - a
            L = vx * vx + vy * vy
            t = np.clip(((X - a[0]) * vx + (Y - a[1]) * vy) / L, 0, 1)
            shape |= np.hypot(X - (a[0] + t * vx), Y - (a[1] + t * vy)) <= rho
            nx, ny = -(b[1] - a[1]), b[0] - a[0]
            side = np.sign(nx * (cen[0] - a[0]) + ny * (cen[1] - a[1]))
            interior &= side * (nx * (X - a[0]) + ny * (Y - a[1])) >= 0
        model_light |= shape | interior

    out = 0
    for name, model, real in (('R', model_dark, dark), ('rays', model_light, light)):
        iou = (model & real).sum() / (model | real).sum()
        miss = int((real & ~model).sum())
        extra = int((~real & model).sum())
        print(f'{name:>5}: IoU {iou:.4f}  missing {miss}  extra {extra}  '
              f'of {int(real.sum())} px')
        if iou < 0.98:
            out = 1
    return out


if __name__ == '__main__':
    if '--verify' in sys.argv:
        sys.exit(verify())
    with open('assets/icon/AppLogo.svg', 'w') as f:
        f.write(svg())
    print('wrote assets/icon/AppLogo.svg')
