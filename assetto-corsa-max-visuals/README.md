# Max Visuals for Assetto Corsa

A graphics pack that pushes Assetto Corsa (2014, Kunos) as far as it can go, built on top of
**Custom Shaders Patch (CSP)**. It contains:

| What | File(s) | What it does |
|---|---|---|
| Post-processing filter | `files/ppfilters/MaxVisuals.ini` | Natural, photographic look: filmic tonemapping, neutral colour, soft bloom only on truly bright things, subtle sun rays, cinematic depth of field on replay cameras. No chromatic aberration, lens ghosts or dirt. |
| Filter variant | `files/ppfilters/MaxVisuals_AgX.ini` | The same look using CSP's **AgX** tonemapper (CSP 0.2.1+), which keeps very bright coloured lights (brake lights, headlights, neon, a low sun) from clipping. Try both and keep the one you like. |
| CSP presets | `files/csp-presets/Max Visuals - Ultra.ini`, `... - High.ini` | Every visual CSP feature switched on and tuned: TAA, screen-space reflections, HBAO+ ambient occlusion, dynamic headlight shadows, volumetric lights, 4-cascade shadows, real mirrors, Grass FX, Particles FX, Rain FX quality, and more. |
| Video settings | `files/video/ultra.ini`, `high.ini` | The matching AC video settings (MSAA, shadows, reflections, mirrors, post-processing). |
| Installer | `Install-Ultra.bat`, `Install-High.bat`, `Uninstall.bat` | Applies all of the above in one go, backs up every file first, and can undo everything. |

Your resolution, window mode, refresh rate, V-sync, FPS limit, weather mod choice, controls, audio,
UI and VR settings are never touched.

---

## 1. What you need first

This pack is the configuration layer. The engine upgrades it configures are separate, and
it does not include or redistribute them:

1. **Assetto Corsa** on Steam. Launch it once so it creates its settings folder.
2. **Content Manager** (CM), the community launcher. The free version is enough:
   <https://acstuff.club/app/>
3. **Custom Shaders Patch**, installed from Content Manager → *Settings → Custom Shaders Patch*.
   The newest public version (0.3.1 as of October 2026) is recommended. 0.2.x works, and the AgX
   filter needs 0.2.1 or newer.
4. **A weather and lighting mod** (strongly recommended). This makes the biggest single difference:
   - **Pure** by Peter Boese, the best-looking option. See the author's page for current
     availability.
   - **Sol**, the free predecessor by the same author.
   - Or CSP's built-in default weather style. If you use it, turn on its *linear colour space*
     option in the style settings.

   Choose it in Content Manager → *Settings → Custom Shaders Patch → Weather FX*.

**Which preset?**

| Preset | Aimed at | Notes |
|---|---|---|
| **Ultra** | RTX 4070 Ti / RX 7900 XT or faster, 12 GB+ VRAM | Everything at maximum: 8192 shadow maps, MSAA 8x, reflections updated every frame, SSLR at 200 steps, dynamic shadows for 4 cars, real mirrors. |
| **High** | RTX 3070 / RX 6800 class, 8 GB+ VRAM | Same look with the most expensive options reduced. |

Both presets are for a **single screen** (see [VR & triple screens](#vr--triple-screens)).

---

## 2. Install

### Option A – installer (recommended)

1. Download and extract this folder anywhere.
2. **Close Content Manager and Assetto Corsa.**
3. Double-click **`Install-Ultra.bat`** (or **`Install-High.bat`**).

The installer finds Assetto Corsa through Steam, or asks you for the folder. Then it:

- copies both filters to `assettocorsa\system\cfg\ppfilters\`
- merges the video settings into `Documents\Assetto Corsa\cfg\video.ini`
- merges the CSP preset into `Documents\Assetto Corsa\cfg\extension\*.ini`, changing only the
  listed keys
- adds both CSP presets to Content Manager's preset list
- saves a backup of every file it touches in `Documents\Assetto Corsa\MaxVisuals-Backups\`

Extra options (run from PowerShell inside the folder, or add them after the `.bat` name):

```powershell
powershell -ExecutionPolicy Bypass -File install.ps1 -Preset Ultra -DryRun
```

```powershell
powershell -ExecutionPolicy Bypass -File install.ps1 -Preset Ultra -Filter MaxVisuals_AgX
```

| Option | Effect |
|---|---|
| `-DryRun` | Lists every value that would change, writes nothing |
| `-Filter MaxVisuals_AgX` | Activates the AgX variant instead of the main filter |
| `-SkipVideo` / `-SkipCsp` | Leave `video.ini` / the CSP settings alone |
| `-AcRoot "D:\SteamLibrary\steamapps\common\assettocorsa"` | Use this game folder |
| `-Verbose` | Print every changed key |

### Option B – by hand (3 steps)

1. Copy `files/ppfilters/*.ini` into `<assettocorsa>\system\cfg\ppfilters\`.
2. Drag `files/csp-presets/Max Visuals - Ultra.ini` onto the Content Manager window. Or copy
   it into `%LOCALAPPDATA%\AcTools Content Manager\Presets\Custom Shaders Patch Presets\` and
   pick it with the presets button at the bottom of *Settings → Custom Shaders Patch*.
   The preset **merges**: it doesn't reset your other CSP settings or your weather style.
3. In Content Manager → *Settings → Assetto Corsa → Video*, set:

| Setting | Ultra | High |
|---|---|---|
| Anti-aliasing (MSAA) | 8x | 4x |
| Anisotropic filtering | 16x | 16x |
| Shadow resolution | 8192 | 4096 |
| World detail | Maximum | Maximum |
| Smoke | Maximum, in mirrors | High, in mirrors |
| Motion blur | **Off** (required for Extra FX) | **Off** |
| Post-processing | On, quality Maximum | On, quality Maximum |
| Post-processing filter | `MaxVisuals` | `MaxVisuals` |
| Glare / Depth of field | Maximum / Maximum | Maximum / Maximum |
| Sun rays, Heat shimmer, FXAA | On (keep FXAA on, CSP hooks it) | On |
| Mirrors | High quality, 512×2048 | High quality, 256×1024 |
| Reflections | 1024, 6 faces per frame, 1500 m | 512, 2 faces per frame, 1000 m |

---

## 3. After installing

- **Pure users:** set overall brightness and exposure in the *Pure Config* app (PP section).
  Pure controls exposure, and the filter uses the exposure range Pure-compatible filters use
  (about 0.3).
- **Switch filters live:** CSP's in-game post-processing filter selector, or Content Manager →
  *Settings → Assetto Corsa → Video → Post-processing filter*.
- **Screenshots:** F8 now captures with 48-sample accumulation anti-aliasing at maximum JPEG
  quality (32 samples on High).
- Content Manager shows the presets as **Max Visuals - Ultra** and **Max Visuals - High** under
  *Settings → Custom Shaders Patch* (presets button), so you can switch tiers without the installer.

---

## 4. What exactly changes

<details>
<summary><b>CSP settings (Ultra → High)</b></summary>

| Module | Setting | Ultra | High | Why |
|---|---|---|---|---|
| Graphics Adjustments | Render scale / FSR upscaling | 100% / off | 100% / off | Native resolution |
| | LOD distance for cars, track, trees | 2.0× | 1.5× | Far less pop-in |
| | MSAA custom resolve and kernel | on / on | on / off | Cleaner edges near bright areas |
| | Post AA | SMAA Ultra + FidelityFX CAS 0.4 | SMAA High + CAS 0.4 | Sharper than FXAA. CSP's recommended pairing with TAA. |
| Extra FX | Enabled, all cameras | ✔ | ✔ | Powers everything below |
| | TAA (extra sharpening off, CAS instead) | ✔ | ✔ | Kills shimmer on fences, foliage and speculars |
| | SSLR reflections | Hi-Z, 200 steps | Hi-Z, 100 steps | Wet roads and glossy paint reflect the scene |
| | Ambient occlusion | HBAO+ 80% | HBAO+ 80% | Contact shadows and depth |
| | Screen-space lighting, light bounce, emissives | ✔ | ✔ | Light from flames and sparks, bounce light |
| | Volumetric headlights | 0.32 res | 0.20 res | Visible light beams in fog and at night |
| | Fog blur + heat distortion | ✔ | ✔ | |
| | Motion blur | exterior/replay cameras, high | exterior/replay, medium | Cockpit view stays crisp |
| Smart Shadows | Automatic splits | 250 m | 200 m | Sharper, longer shadows |
| | 4th cascade (distant shadows, shadows in mirrors) | 2000 m | 1500 m | |
| Lighting FX | Dynamic shadows from headlights and track lights | ✔ (4 cars, HQ headlights) | ✔ (2 cars) | Off by default in CSP. A big night-time upgrade. |
| | Cars casting light / mirror lighting | 20 / lights + sun shadows | 12 / lights | |
| Reflections FX | Cubemap resolution | 1024 | 512 | CSP marks 2048 as not recommended (slow, can mess up shading) |
| Smart Mirror | Real mirrors | ✔ | – | Accurate per-mirror reflections that follow your head position |
| Particles FX | Smoke, sparks, flames and debris with shadows, soft particles | ✔ (1.2× density) | ✔ | |
| Skidmarks FX | Advanced blending | ✔ | ✔ | |
| Grass FX | Quality / shadows / smooth MSAA blending | Very high / ✔ / ✔ | High / ✔ / – | |
| Rain FX | Rain map quality | High | Medium | |
| Track Adjustments | Trees receive shadows, A2C dithering | ✔ | ✔ | |
| Weather FX | HQ stars, cloud fidelity, detailed cloud shadows, mirage reflections, full-res PP | ✔ | partly | Your weather *style* isn't changed |
| Car Instruments | Distant headlights glare | ✔ | ✔ | Default in CSP 0.3 |
| Nice Screenshots | Accumulation AA samples / JPEG quality | 48 / 100 | 32 / 100 | |

</details>

<details>
<summary><b>Post-processing filter</b></summary>

| Section | Choice | Why |
|---|---|---|
| Resolution | `FIXED_WIDTH=0` | Bloom and DOF at full resolution. Kunos' default renders them at 1280 px and upscales. |
| Tonemapping | Sensitometric (2) + CSP `FILMIC_CONTRAST=0.3`. AgX (16) in the variant. | Filmic highlight roll-off. Sensitometric is what Pure/Sol filters are calibrated around. |
| Exposure | Auto, target 0.28, range 0.1–0.7, metering the central 60%×40% | Stable exposure that ignores the sky and dashboard. Pure/Sol take over when active. |
| Colour | Saturation 0.98, colour temperature 6350 K / white balance 6500 K | Neutral, very slightly warm daylight |
| Bloom | Threshold 2.5, effective bloom 0.08, star 0.03 (Kunos: 0.125), no ghosts | Only bright things glow. Values sit in the middle of the community's best-regarded filters. |
| First person | Fainter star streaks, no ghosts (`EXT_GLARE_FIRSTPERSON_SHAPE`) | Your eyes aren't a camera lens |
| Sun rays | Length 7, glare ratio 0.015 | Visible but not overpowering. Pure/Sol modulate them further. |
| Depth of field | Full-frame f/11, adaptive to FOV | Telephoto replay cameras get a soft background, wide views stay sharp |
| Vignette | 0.25 | Subtle |
| Off | Chromatic aberration, lens distortion, feedback/after-image | Cheap-looking |

</details>

---

## 5. Performance tuning

If Ultra is too heavy, switch to **High** first (`Install-High.bat`, or pick the preset in Content
Manager). If you still need frames, these are the biggest savings, roughly in order:

1. MSAA 8x → **4x**. With TAA on there is almost no visible difference.
2. Shadow resolution 8192 → **4096**.
3. Reflections: 6 → **2 faces per frame**. CSP reprojects the rest.
4. Extra FX → SSLR: Hi-Z steps 200 → **80**, or *Simple (New)*.
5. Lighting FX → shadows: *high quality headlight shadows* **off**, fewer cars with shadows.
6. Smart Mirror → *Real mirrors* **off**.
7. Grass FX quality **High** or **Medium**.
8. LOD distance multipliers back towards **1.0**. This also helps CPU-bound races with many cars.
9. CSP 0.3 adds temporal upscalers (DLSS, FSR 2/3/4, XeSS) to its upscaling options. Native
   resolution with TAA looks best, so use one only if you need the frames.

---

## 6. Optional extras

- **HDR monitor:** CSP → *DXGI Tweaks* → enable the DXGI flip model and HDR, and run AC in
  borderless/windowed mode.
- **ReShade:** not needed. CSP already provides SMAA, CAS sharpening, AO and SSR, and ReShade's
  depth effects tend to conflict with CSP.
- **Better content:** many older mod cars and tracks lack CSP configs. Content Manager downloads
  the official configs automatically. High-quality track mods with CSP configs make a huge
  difference.

### VR & triple screens

Extra FX (TAA, SSLR, AO, volumetric lights) is built for a single screen. CSP's module config
says it doesn't run in VR, and in triple-screen mode it only runs if you enable *Allow in triple*,
which is very expensive. In VR, use **High** or lower and follow a VR-specific guide; frame rate
matters more than effects there.

---

## 7. Troubleshooting

| Problem | Fix |
|---|---|
| Too dark or too bright | Pure: *Pure Config* → PP brightness/exposure. Without Pure: raise or lower `[AUTO_EXPOSURE] TARGET` in the filter (0.24 darker, 0.32 brighter). |
| Washed out or odd with **MaxVisuals_AgX** | Your CSP is older than 0.2.1. Update CSP or use `MaxVisuals`. |
| No reflections on wet roads, no AO, shimmering | Extra FX isn't running. Check: AC motion blur **off**, post-processing **on**, single screen, not VR. |
| Settings went back to the old values | Content Manager was open and saved over them. Close it and re-run the installer, or apply the preset from inside CM. |
| "Access denied" during install | Assetto Corsa is in a protected folder. Right-click the `.bat` → *Run as administrator*. |
| Want the old look back | `Uninstall.bat` |

---

## 8. Uninstall

Double-click **`Uninstall.bat`**. It restores every backup, newest first, so even after several
installs you get back exactly the settings you had before the first one. Files the pack created
are deleted. Use `uninstall.ps1 -LatestOnly` to undo just the last install.

Settings you changed in the touched files *after* installing are reverted too.

---

## Compatibility & status

- Targets **CSP 0.2.x–0.3.x** with Pure, Sol or the default weather style. The filter also loads
  without CSP; the `EXT_*` sections are simply ignored.
- Every CSP key and value is checked against CSP's own module configs by `tools/validate.py`
  (key exists, value inside the documented range):
  ```bash
  python3 tools/validate.py
  ```
  CSP 0.3 merged or renamed a few modules (the wheel effects, for example). The pack doesn't
  touch those, and any key a future CSP renames is ignored, not misapplied.
- The look is tuned from CSP's documentation and real-world filters, not yet calibrated in-game on
  every weather and track. Brightness and contrast are personal, so see the *Tuning tips* at the end
  of each filter file, or use CSP's in-game PP filter editor.

## Credits

Custom Shaders Patch and Content Manager by Ilja Jusupov and contributors; Pure and Sol by Peter
Boese; Assetto Corsa by Kunos Simulazioni. This pack contains only configuration files and scripts
written for it.
