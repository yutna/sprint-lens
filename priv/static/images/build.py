#!/usr/bin/env python3
"""Builds every icon the browsers ask for, from `logo-mark.svg`.

`logo-mark.svg` is the only drawing anyone edits. Everything else — the
favicon, the icon a phone puts on its home screen, the image a link preview
shows — is derived here, so there is no second copy of the artwork to fall out
of step with the first.

The outputs are committed, because a build that needs a rasteriser installed
is a build that breaks for the next person. Re-run this after changing the
mark, and commit what it writes:

    python3 priv/static/images/build.py

Needs `rsvg-convert` and `magick` (`brew install librsvg imagemagick`).
"""

from __future__ import annotations

import re
import shutil
import subprocess
import sys
from pathlib import Path

IMAGES = Path(__file__).resolve().parent
STATIC = IMAGES.parent
MARK = IMAGES / "logo-mark.svg"

# The light theme's primary, as sRGB. Icons cannot inherit a colour the way the
# in-app mark does, so this is the one place the brand hue is written down
# outside `assets/css/app.css`; keep the two in step by hand.
BRAND = "#aa2b8a"
# Lifted for dark browser chrome, where the light value goes muddy.
BRAND_DARK = "#d060b4"
ON_BRAND = "#ffffff"


def require(*tools: str) -> None:
    missing = [tool for tool in tools if shutil.which(tool) is None]
    if missing:
        sys.exit(f"missing: {', '.join(missing)} — brew install librsvg imagemagick")


def mark_path() -> str:
    """The `d` attribute of the mark, and nothing else."""
    match = re.search(r'\sd="([^"]+)"', MARK.read_text())
    if not match:
        sys.exit(f"no path data found in {MARK}")

    return " ".join(match.group(1).split())


def svg(body: str, size: int = 32) -> str:
    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {size} {size}">{body}</svg>'
    )


def mark(colour: str, scale: float = 1.0, offset: float = 0.0) -> str:
    """The mark, optionally scaled down and centred inside a larger tile."""
    transform = f'transform="translate({offset} {offset}) scale({scale})"'

    return f'<g {transform}><path fill="{colour}" fill-rule="evenodd" d="{mark_path()}"/></g>'


def tile(size: int, scale: float) -> str:
    """The mark in white on a solid brand square.

    Used for anything a platform draws on its own background: a home screen
    icon has no page behind it, and a maskable icon may be cropped to a circle,
    so the artwork sits well inside the safe area rather than bleeding to the
    edge.
    """
    inset = size * (1 - scale) / 2
    return svg(
        f'<rect width="{size}" height="{size}" fill="{BRAND}"/>'
        + mark(ON_BRAND, scale=size * scale / 32, offset=inset),
        size,
    )


def render(source: str, out: Path, width: int, height: int | None = None) -> None:
    tmp = out.with_suffix(".tmp.svg")
    tmp.write_text(source)
    subprocess.run(
        ["rsvg-convert", "-w", str(width), "-h", str(height or width), str(tmp), "-o", str(out)],
        check=True,
    )
    tmp.unlink()
    print(f"  {out.relative_to(STATIC.parent.parent)}")


def main() -> None:
    require("rsvg-convert", "magick")
    print("building icons from logo-mark.svg")

    # The favicon a modern browser prefers. It carries its own colour because
    # an icon has no page to inherit one from, and switches with the browser's
    # colour scheme so the mark does not go muddy in a dark tab strip.
    (IMAGES / "favicon.svg").write_text(
        svg(
            "<style>"
            f".mark{{fill:{BRAND}}}"
            f"@media (prefers-color-scheme:dark){{.mark{{fill:{BRAND_DARK}}}}}"
            "</style>"
            + mark("currentColor").replace('fill="currentColor"', 'class="mark"')
        )
    )
    print("  priv/static/images/favicon.svg")

    # A genuine multi-resolution ICO for the browsers that still ask for one.
    # What was here before was a 64-pixel PNG with the wrong extension.
    sizes = (16, 32, 48)
    parts = []
    for size in sizes:
        part = IMAGES / f".ico-{size}.png"
        render(svg(mark(BRAND)), part, size)
        parts.append(str(part))
    subprocess.run(["magick", *parts, str(STATIC / "favicon.ico")], check=True)
    for part in parts:
        Path(part).unlink()
    print("  priv/static/favicon.ico")

    render(tile(180, 0.62), STATIC / "apple-touch-icon.png", 180)
    render(tile(192, 0.56), IMAGES / "icon-192.png", 192)
    render(tile(512, 0.56), IMAGES / "icon-512.png", 512)

    # The link preview. 1200x630 is what the platforms crop to.
    render(
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1200 630">'
        f'<rect width="1200" height="630" fill="{BRAND}"/>'
        f'<g transform="translate(430 155) scale(10)">'
        f'<path fill="{ON_BRAND}" fill-rule="evenodd" d="{mark_path()}"/>'
        "</g>"
        f'<text x="600" y="530" fill="{ON_BRAND}" text-anchor="middle" '
        'font-family="Helvetica Neue, Helvetica, Arial, sans-serif" '
        'font-size="76" font-weight="600" letter-spacing="-1">SprintLens</text>'
        "</svg>",
        IMAGES / "og-image.png",
        1200,
        630,
    )

    print("done — commit what changed")


if __name__ == "__main__":
    main()
