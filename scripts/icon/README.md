# `jirip` shared launcher icon recipe

A one-shot generator that produces the launcher icon files
`flutter_launcher_icons` expects, in the shared `jirip` visual style.

The style: a dark coin disc inside a cyan→purple→magenta ring, sitting
on a flat coloured field with a soft halo. The colours change per app;
the shape language is fixed.

```
+-------------------------------+
|          flat colour          |
|        soft radial glow       |
|     +----- ring -----+        |
|    /  three-stop gradient \   |
|   |    dark disc          |   |
|   |    (with white glyph) |   |
|    \                      /   |
|     +--------------------+    |
+-------------------------------+
```

## What it produces

Three PNGs, sized to `canvas` (default 1024):

| File | Used by `flutter_launcher_icons` as | Where it shows |
|---|---|---|
| `icon.png` | `image_path` | Legacy single-image icon on pre-Android 8, Play Store listing |
| `icon_bg.png` | `adaptive_icon_background` | Android 8+ adaptive background layer |
| `icon_fg.png` | `adaptive_icon_foreground` | Android 8+ adaptive foreground layer (just the glyph on transparent) |

## Per-app inputs

Each app needs two files at its repo root:

### 1. `icon-glyph.png` (or `.svg`)

The white symbol that lives inside the disc. White on transparent.
Square aspect is easiest; otherwise the longer side will be the one
that's scaled to fit.

- **PNG**: any size; the recipe resamples via Lanczos.
- **SVG**: requires `pip install cairosvg` and Cairo system libs
  (`brew install cairo` / `apt install libcairo2`). Rasterised at 4× the
  target size, then downsampled — produces sharp output regardless of
  how the SVG was authored.

### 2. `icon.config.yaml`

```yaml
# Path to the glyph, relative to this config file.
glyph: icon-glyph.png

# All 6 colour stops are required. The 3-stop ring gradient is the
# defining feature of the shared style — a raw linear blend of left+
# right (e.g. cyan + magenta -> grey-blue) looks muddy, so each app
# picks an explicit ring_mid that ties the brand colours together.
colors:
  bg:         "#42237A"   # flat colour at the corners
  glow:       "#6A4DCD"   # halo peak around the disc (smoothstep falloff)
  disc:       "#1A0B2E"   # dark disc behind the glyph
  ring_left:  "#00E5FF"   # leftmost ring colour
  ring_mid:   "#7B61FF"   # ring at top/bottom (the curve's apex)
  ring_right: "#FF2D87"   # rightmost ring colour

# Geometry (all optional, all expressed as fractions of canvas width).
# Defaults reproduce voicer's icon; only override if you want a
# different proportion.
canvas: 1024
glyph_size_ratio: 0.328     # glyph max-side / canvas
disc_radius_ratio: 0.211    # 216 / 1024
ring_inner_ratio:  0.211    # ring inner edge = disc edge
ring_outer_ratio:  0.260    # 266 / 1024
glow_radius_ratio: 0.55     # halo dies off before the corners
legacy_zoom:       1.387    # composite icon.png uses zoomed-in geometry
                            # (1.0 = same as adaptive layers)
```

## Running

From the app's repo root:

```bash
python3 ../flutter_common/scripts/icon/generate_icon.py icon.config.yaml
```

The script writes `icon.png`, `icon_bg.png`, `icon_fg.png` next to the
config. Then run `flutter_launcher_icons` as usual:

```bash
dart run flutter_launcher_icons
```

…which fans out the three sources into all the `mipmap-*` and
`drawable-*` resolutions Android needs.

## Dependencies

The script needs PyYAML and Pillow; for SVG glyphs, cairosvg too.

```bash
pip install --user pyyaml pillow
pip install --user cairosvg   # only if you use SVG glyphs
```

## How to spin up a new app

1. Pick a 6-colour palette and a single white glyph (PNG or SVG).
2. Drop `icon-glyph.png` and `icon.config.yaml` at the app root.
3. Run the recipe.
4. Run `flutter_launcher_icons`.

Same workflow as `jirip_app`'s `Updater`: shared logic in commons,
per-app config in the app repo, one consistent end result across apps.
