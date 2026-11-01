# Photoreal – Assetto Corsa PP filters

- `Photoreal.ini` (v3.1, bold): muted broadcast-camera colours, stronger contrast, camera-like bloom,
  vignette and lens distortion, slow exposure adaptation.
- `Photoreal_Subtle.ini` (v2.0): close to stock with small realism tweaks.

The rest of this file describes the subtle version; the bold one uses the same tuning keys.


A subtle, camera-like post-processing filter. Built directly on the game's stock
`default.ini`; only a handful of values are changed, each marked `; Photoreal`.

## Install
1. Copy `Photoreal.ini` to `<Steam>\steamapps\common\assettocorsa\system\cfg\ppfilters\`
2. Content Manager → Settings → Assetto Corsa → Video → **Post-processing filter** → `Photoreal`

## What it changes vs. stock
- Auto exposure adapts over ~0.8 s (like your eyes) and meters the centre of the view
- Slightly lower exposure target so skies and white cars don't blow out
- Less glare, no lens ghosts, softer sun stars and diffraction ring, slightly warm sun rays
- Subtler chromatic aberration, gentle vignette, less driving DOF blur
- Saturation 0.93, contrast 1.03
- Effects rendered at full resolution (`FIXED_WIDTH=0`). If FPS drops, set it back to `1280`.

## Quick tuning
| Too…          | Change                                       |
|---------------|----------------------------------------------|
| Dark          | `[AUTO_EXPOSURE] TARGET` 0.32–0.34           |
| Bright        | `[AUTO_EXPOSURE] TARGET` 0.26–0.28           |
| Grey / dull   | `[COLOR] SATURATION` 0.97–1.0                |
| Too much glow | `[GLARE] LUMINANCE` 1.0                      |
