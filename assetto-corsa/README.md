# Photoreal – Assetto Corsa PP filter

A neutral, camera-like post-processing filter for Assetto Corsa via Content Manager.

## Install
1. Copy `Photoreal.ini` to `<Steam>\steamapps\common\assettocorsa\system\cfg\ppfilters\`
2. Content Manager → Settings → Assetto Corsa → Video → **Post-processing filter** → `Photoreal`
3. Make sure **Post-processing** is enabled and quality is High or above.

## Recommended setup
- Custom Shaders Patch (latest) + Sol or Pure weather/lighting
- CSP → Graphics Adjustments: leave color/brightness at defaults (the filter handles it)
- Sol/Pure: let the weather drive exposure; if you use Pure, enable its PP-filter compatibility mode

## Quick tuning
| Too…            | Change                                    |
|-----------------|-------------------------------------------|
| Dark            | `[TONEMAPPING] EXPOSURE` +0.02            |
| Washed out      | `[COLOR] CONTRAST` 1.05–1.08              |
| Grey / dull     | `[COLOR] SATURATION` 0.98–1.00            |
| Blown-out sky   | `[TONEMAPPING] WHITE_POINT` 2.5–3.0       |
| Too much bloom  | `[GLARE] THRESHOLD` 0.95 or `BLOOM_RATIO` 0.03 |

You can also open the filter in CM's built-in PP filter editor and adjust live while the game runs.
