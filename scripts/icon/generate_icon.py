#!/usr/bin/env python3
r"""Generate a shared-style launcher icon for a jirip Flutter app.

The shared style is:

    +-------------------------------+
    |          flat purple          |
    |        soft radial glow       |
    |     +----- ring -----+        |
    |    /  cyan -> magenta  \      |
    |   |    dark disc        |    |
    |   |   (with white glyph |    |
    |   |    centered)         |   |
    |    \                    /     |
    |     +------------------+      |
    |                               |
    +-------------------------------+

Per-app inputs (in `icon.config.yaml`):
- canvas size (default 1024)
- five colors: bg, glow_peak, disc, ring_left, ring_right
- ring inner / outer radii as fractions of canvas width
- disc radius as fraction
- a glyph: either a path to a white-on-transparent PNG or SVG, or a
  bundled keyword ("mic" reuses voicer's shape).

Outputs (next to the config, by default):
- icon.png            — composite, used by flutter_launcher_icons
                        as `image_path` (and for app store listings)
- icon_bg.png         — adaptive background (everything except the
                        glyph)
- icon_fg.png         — adaptive foreground (just the glyph on
                        transparent)

Why a Python script and not a Dart/Flutter generator: we run this at
build/setup time only, never at runtime. The dependency surface is
just Pillow + PyYAML; no Flutter SDK needed. CI runs it once per app
when icon inputs change and commits the PNGs.
"""

from __future__ import annotations

import argparse
import io
import math
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Sequence

import yaml
from PIL import Image, ImageDraw, ImageFilter


@dataclass(frozen=True)
class IconConfig:
    canvas: int
    bg_color: str
    glow_color: str
    glow_radius_ratio: float
    disc_color: str
    disc_radius_ratio: float
    ring_inner_ratio: float
    ring_outer_ratio: float
    legacy_zoom: float
    ring_left_color: str
    # Midpoint of the 3-stop ring gradient. A raw linear blend of
    # left+right tends to look muddy (cyan + magenta -> grey-blue);
    # the shared style explicitly chooses a colour for the top/bottom
    # of the ring. Voicer uses #7B61FF (cool purple).
    ring_mid_color: str
    ring_right_color: str
    glyph_path: Path
    glyph_size_ratio: float  # fg fills this fraction of disc diameter

    @classmethod
    def from_yaml(cls, config_path: Path) -> "IconConfig":
        data = yaml.safe_load(config_path.read_text())
        glyph_value = data["glyph"]
        # Path is relative to the config file's directory (so the recipe
        # can be invoked from anywhere and the app's repo-local glyph
        # still resolves correctly).
        glyph_path = (config_path.parent / glyph_value).resolve()
        if not glyph_path.exists():
            raise FileNotFoundError(
                f"Glyph not found: {glyph_path} "
                f"(referenced as {glyph_value!r} in {config_path})"
            )
        suffix = glyph_path.suffix.lower()
        if suffix not in (".png", ".svg"):
            raise ValueError(
                f"Unsupported glyph format {suffix!r}; use .png or .svg"
            )
        return cls(
            canvas=int(data.get("canvas", 1024)),
            bg_color=data["colors"]["bg"],
            glow_color=data["colors"]["glow"],
            glow_radius_ratio=float(data.get("glow_radius_ratio", 0.71)),
            disc_color=data["colors"]["disc"],
            disc_radius_ratio=float(data.get("disc_radius_ratio", 0.211)),
            ring_inner_ratio=float(data.get("ring_inner_ratio", 0.211)),
            ring_outer_ratio=float(data.get("ring_outer_ratio", 0.26)),
            # Legacy zoom: flutter_launcher_icons consumes our icon.png
            # as the composed legacy/playstore image. Voicer's original
            # legacy png is a tighter crop (~1.42x larger disc/ring) than
            # the adaptive background; setting legacy_zoom replicates
            # that look without affecting the adaptive layers.
            legacy_zoom=float(data.get("legacy_zoom", 1.0)),
            ring_left_color=data["colors"]["ring_left"],
            ring_mid_color=data["colors"]["ring_mid"],
            ring_right_color=data["colors"]["ring_right"],
            glyph_path=glyph_path,
            glyph_size_ratio=float(data.get("glyph_size_ratio", 0.30)),
        )


def render(cfg: IconConfig) -> tuple[Image.Image, Image.Image, Image.Image]:
    """Render the three icon layers.

    Returns (composite, background, foreground).
    - bg and fg use the configured ratios; they map to the adaptive
      `ic_launcher_background` / `ic_launcher_foreground` slots and are
      what users see on Android 8+.
    - composite uses the same ratios scaled by `legacy_zoom` so the
      legacy `icon.png` (used by flutter_launcher_icons as image_path
      and by app stores) can be a tighter crop without forcing the
      adaptive layers to follow.
    """
    bg = _render_background(cfg, zoom=1.0)
    fg = _render_foreground(cfg, zoom=1.0)
    if cfg.legacy_zoom == 1.0:
        composite = bg.copy()
        composite.alpha_composite(fg)
    else:
        legacy_bg = _render_background(cfg, zoom=cfg.legacy_zoom)
        legacy_fg = _render_foreground(cfg, zoom=cfg.legacy_zoom)
        composite = legacy_bg
        composite.alpha_composite(legacy_fg)
    return composite, bg, fg


def _render_background(cfg: IconConfig, *, zoom: float) -> Image.Image:
    """Background = flat fill + radial halo + ring + dark disc."""
    W = cfg.canvas
    bg = Image.new("RGBA", (W, W), _hex(cfg.bg_color))

    _paint_radial_halo(
        bg,
        center=(W // 2, W // 2),
        inner_color=_hex(cfg.glow_color),
        outer_color=_hex(cfg.bg_color),
        radius=int(W * cfg.glow_radius_ratio * zoom),
    )

    _paint_ring(
        bg,
        center=(W // 2, W // 2),
        inner_radius=int(W * cfg.ring_inner_ratio * zoom),
        outer_radius=int(W * cfg.ring_outer_ratio * zoom),
        left_color=_hex(cfg.ring_left_color),
        mid_color=_hex(cfg.ring_mid_color),
        right_color=_hex(cfg.ring_right_color),
    )

    _paint_circle(
        bg,
        center=(W // 2, W // 2),
        radius=int(W * cfg.disc_radius_ratio * zoom),
        color=_hex(cfg.disc_color),
    )

    return bg


def _render_foreground(cfg: IconConfig, *, zoom: float) -> Image.Image:
    """Foreground = the glyph, white on transparent, centered.

    Glyph file format determined by extension:
    - .png: read directly; resampled to target size via Lanczos.
    - .svg: rasterised via cairosvg at the exact target size, so we
      get sharp output regardless of how the SVG was authored.
    """
    W = cfg.canvas
    fg = Image.new("RGBA", (W, W), (0, 0, 0, 0))

    target = int(W * cfg.glyph_size_ratio * zoom)
    glyph = _load_glyph(cfg.glyph_path, target)
    gw, gh = glyph.size

    paste_x = (W - gw) // 2
    paste_y = (W - gh) // 2
    fg.alpha_composite(glyph, (paste_x, paste_y))
    return fg


def _load_glyph(path: Path, target_max_side: int) -> Image.Image:
    """Load a glyph file and return it scaled so its longer side is
    `target_max_side`. Aspect ratio preserved.

    SVG path: rasterise via cairosvg straight to the target longer-side.
    cairosvg's output_width or output_height controls one axis; we
    figure out which axis is the longer one from the SVG viewbox so the
    rasterisation matches the target without a follow-up resize.
    """
    suffix = path.suffix.lower()
    if suffix == ".svg":
        try:
            import cairosvg  # type: ignore
        except ImportError as e:
            raise RuntimeError(
                "SVG glyphs require the `cairosvg` Python package "
                "(pip install cairosvg) and Cairo system libs "
                "(brew install cairo on macOS; apt-get install "
                "libcairo2 on Debian)."
            ) from e
        # Render large then resize: cairosvg's parametric output sizing
        # depends on SVG viewbox parsing which is finicky for some
        # exports. Rendering at 4x target then resizing is robust.
        big = target_max_side * 4
        png_bytes = cairosvg.svg2png(
            url=str(path),
            output_width=big,
            output_height=big,
        )
        img = Image.open(io.BytesIO(png_bytes)).convert("RGBA")
    else:
        img = Image.open(path).convert("RGBA")

    gw, gh = img.size
    scale = target_max_side / max(gw, gh)
    new_size = (max(1, int(round(gw * scale))),
                max(1, int(round(gh * scale))))
    return img.resize(new_size, Image.LANCZOS)


def _paint_radial_halo(
    img: Image.Image,
    *,
    center: tuple[int, int],
    inner_color: tuple[int, int, int, int],
    outer_color: tuple[int, int, int, int],
    radius: int,
) -> None:
    """Paint a soft radial gradient from `inner_color` at `center` to
    `outer_color` at `radius`. Operates per-pixel inside the bounding
    box; outside it the image keeps its existing fill (which should
    already be outer_color)."""
    cx, cy = center
    x0 = max(0, cx - radius)
    y0 = max(0, cy - radius)
    x1 = min(img.size[0], cx + radius)
    y1 = min(img.size[1], cy + radius)

    pixels = img.load()
    ir, ig, ib, _ = inner_color
    or_, og, ob, _ = outer_color
    for y in range(y0, y1):
        dy = y - cy
        for x in range(x0, x1):
            dx = x - cx
            d = math.hypot(dx, dy)
            if d >= radius:
                continue
            # Smoothstep for a softer falloff than linear; the eye reads
            # the resulting halo as a glow rather than a hard ramp.
            t = d / radius
            t = t * t * (3 - 2 * t)
            r = int(ir + (or_ - ir) * t)
            g = int(ig + (og - ig) * t)
            b = int(ib + (ob - ib) * t)
            pixels[x, y] = (r, g, b, 255)


def _paint_ring(
    img: Image.Image,
    *,
    center: tuple[int, int],
    inner_radius: int,
    outer_radius: int,
    left_color: tuple[int, int, int, int],
    mid_color: tuple[int, int, int, int],
    right_color: tuple[int, int, int, int],
) -> None:
    """Paint a horizontal 3-stop linear gradient ring (annulus).

    Stops at t=0 (leftmost) -> left_color, t=0.5 -> mid_color, t=1
    (rightmost) -> right_color. The voicer original passes through a
    cool purple at the top/bottom of the ring rather than the linear
    average of cyan and magenta; supporting an explicit mid stop lets
    us match that without baking a specific palette into the recipe.
    """
    cx, cy = center
    pixels = img.load()
    lr, lg, lb, _ = left_color
    mr, mg, mb, _ = mid_color
    rr, rg, rb, _ = right_color

    x_left = cx - outer_radius
    x_right = cx + outer_radius
    span = x_right - x_left

    for y in range(cy - outer_radius, cy + outer_radius + 1):
        if y < 0 or y >= img.size[1]:
            continue
        dy = y - cy
        for x in range(x_left, x_right + 1):
            if x < 0 or x >= img.size[0]:
                continue
            dx = x - cx
            r = math.hypot(dx, dy)
            if r < inner_radius or r > outer_radius:
                continue
            t = (x - x_left) / span
            if t <= 0.5:
                u = t * 2.0
                rcol = int(lr + (mr - lr) * u)
                gcol = int(lg + (mg - lg) * u)
                bcol = int(lb + (mb - lb) * u)
            else:
                u = (t - 0.5) * 2.0
                rcol = int(mr + (rr - mr) * u)
                gcol = int(mg + (rg - mg) * u)
                bcol = int(mb + (rb - mb) * u)
            pixels[x, y] = (rcol, gcol, bcol, 255)


def _paint_circle(
    img: Image.Image,
    *,
    center: tuple[int, int],
    radius: int,
    color: tuple[int, int, int, int],
) -> None:
    draw = ImageDraw.Draw(img)
    cx, cy = center
    # Anti-aliased disc via supersample-then-shrink: draw into a 4x
    # buffer, then resize down. Cheap and produces a smooth edge that
    # matches the original (which was clearly anti-aliased).
    supersample = 4
    big = Image.new("RGBA", (radius * 2 * supersample, radius * 2 * supersample), (0, 0, 0, 0))
    ImageDraw.Draw(big).ellipse(
        (0, 0, big.size[0] - 1, big.size[1] - 1),
        fill=color,
    )
    big = big.resize((radius * 2, radius * 2), Image.LANCZOS)
    img.alpha_composite(big, (cx - radius, cy - radius))


def _hex(s: str) -> tuple[int, int, int, int]:
    """Parse '#RRGGBB' or '#RRGGBBAA' into an RGBA tuple."""
    s = s.lstrip("#")
    if len(s) == 6:
        r = int(s[0:2], 16)
        g = int(s[2:4], 16)
        b = int(s[4:6], 16)
        return r, g, b, 255
    if len(s) == 8:
        r = int(s[0:2], 16)
        g = int(s[2:4], 16)
        b = int(s[4:6], 16)
        a = int(s[6:8], 16)
        return r, g, b, a
    raise ValueError(f"bad color: {s!r}")


def main(argv: Sequence[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "config",
        type=Path,
        help="Path to icon.config.yaml",
    )
    parser.add_argument(
        "-o", "--out",
        type=Path,
        default=None,
        help="Output directory (defaults to the config's parent)",
    )
    args = parser.parse_args(argv)

    cfg = IconConfig.from_yaml(args.config)
    out_dir = args.out or args.config.parent
    out_dir.mkdir(parents=True, exist_ok=True)

    composite, bg, fg = render(cfg)

    composite_path = out_dir / "icon.png"
    bg_path = out_dir / "icon_bg.png"
    fg_path = out_dir / "icon_fg.png"
    composite.save(composite_path)
    bg.save(bg_path)
    fg.save(fg_path)
    print(f"Wrote {composite_path}")
    print(f"Wrote {bg_path}")
    print(f"Wrote {fg_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
