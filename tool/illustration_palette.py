#!/usr/bin/env python3
"""Recolour the unDraw illustrations into this app's palette.

    python3 tool/illustration_palette.py

Reads assets/src/*.svg — the files as unDraw ships them — and writes a light and
a dark copy of each into assets/. Re-run after replacing or adding a source
file; do not hand-edit the generated ones.

Why
---

The pre-sign-in screens are drawn around two unDraw illustrations, and unDraw
has its own palette: a signature blue-grey for hair and clothing, a bright
yellow, a pink for the confetti. None of it is in this app's, so the entry flow
looked like a different product from the one behind it — and because the colours
were baked into the files, the only way to survive a dark background was
lib/widgets/pre_auth_theme.dart pinning those screens to the light theme, which
its own docstring calls a holding position rather than a fix.

Mapping rather than tinting. A `colorFilter` over the whole picture is the easy
version and it flattens a drawing that has depth in it — the figure would end up
the same colour as the shape behind them. Each of unDraw's colours has a job, so
each is mapped to the token that does that job here.

The skin tones are deliberately not mapped. They are people, not decoration, and
they are the same in both modes.

unDraw's licence allows this: the illustrations are free to use and modify,
commercially, without attribution.
"""

import os
import re
import sys

SRC_DIR = 'assets/src'
OUT_DIR = 'assets'

# Every colour unDraw uses in these two files, and what it is doing.
#
# The two blue-greys and the greys swap ends between modes: they are the
# figure's silhouette and the shape behind them, so on a dark ground the drawing
# is light-on-dark rather than the same picture with the lights off.
PALETTE = {
    # unDraw's near-black blue-grey — hair, trousers, the ground line.
    '#3f3d56': ('#1A1C16', '#E2E3D8'),   # onSurface
    # Hair and trousers. Neutral in both modes on purpose: mapping this to the
    # container green made the whole figure green in dark mode, and the shirt
    # stopped being an accent because everything around it was already the
    # accent. Light mode grounds the figure in near-black; dark mode does the
    # same job with a dimmer neutral than #3f3d56 above, so the two still
    # separate.
    '#2f2e41': ('#0E2000', '#C4C8BA'),
    # The accent. unDraw's yellow becomes Growth Green, the same value the logo
    # rays use, which is what ties the illustration to the mark above it.
    '#fae37e': ('#A8D46F', '#A8D46F'),
    # The confetti. Was a hot pink with nothing near it in this palette.
    '#ff6584': ('#4A672D', '#B0D18B'),   # primary
    # The soft shape behind the figure, and the smaller flat areas.
    '#e6e6e6': ('#E2E3D8', '#33362E'),   # surfaceContainerHighest
    '#f2f2f2': ('#EDEFE4', '#1E211A'),   # surfaceContainer
    '#f0f0f0': ('#E8E9DE', '#282B24'),   # surfaceContainerHigh
    '#e4e4e4': ('#E2E3D8', '#33362E'),
    '#cacaca': ('#C4C8BA', '#44483D'),   # outlineVariant
    '#fff':    ('#F9FAEF', '#12140E'),   # surface
    '#ffffff': ('#F9FAEF', '#12140E'),
}

# Left alone on purpose.
SKIN = {'#ffb6b6', '#9e616a'}

HEX = re.compile(r'#[0-9a-fA-F]{6}\b|#[0-9a-fA-F]{3}\b')


def recolour(svg, mode):
    """Rewrite every colour in [svg]; returns the file and anything unmapped."""
    index = 0 if mode == 'light' else 1
    unknown = set()

    def swap(match):
        found = match.group(0).lower()
        if found in SKIN:
            return match.group(0)
        if found in PALETTE:
            return PALETTE[found][index]
        unknown.add(found)
        return match.group(0)

    return HEX.sub(swap, svg), unknown


def main():
    if not os.path.isdir(SRC_DIR):
        print(f'{SRC_DIR} does not exist — put the unDraw originals there.')
        return 1

    problems = 0
    for name in sorted(os.listdir(SRC_DIR)):
        if not name.endswith('.svg'):
            continue
        source = open(os.path.join(SRC_DIR, name)).read()
        stem = name[:-4]
        for mode in ('light', 'dark'):
            out, unknown = recolour(source, mode)
            if unknown:
                # Loud rather than silent: an unmapped colour is a piece of the
                # drawing that stayed unDraw's, and it will be the one thing on
                # the screen that looks wrong.
                print(f'  {name} [{mode}]: unmapped {sorted(unknown)}')
                problems += 1
            path = os.path.join(OUT_DIR, f'{stem}_{mode}.svg')
            with open(path, 'w') as f:
                f.write(out)
            print(f'wrote {path}')
    return 1 if problems else 0


if __name__ == '__main__':
    sys.exit(main())
