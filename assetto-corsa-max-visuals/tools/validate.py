#!/usr/bin/env python3
"""Offline checks for the Max Visuals pack (development tool, not needed to play).

  python3 tools/validate.py                       # fetch CSP default configs from GitHub
  python3 tools/validate.py --csp-config DIR      # or use <assettocorsa>/extension/config

Checks:
  * every file the game or Windows PowerShell reads is plain ASCII (no BOM)
  * CSP presets: Content Manager format, every MODULE:SECTION/KEY exists in
    CSP's own module config, numeric values sit inside the documented range,
    "1 or 0" switches are 0/1, enumerated values are one of the listed ones
  * Ultra and High presets set exactly the same keys
  * PP filters only use known vanilla YEBIS / CSP keys
  * video fragments only use keys Content Manager itself reads/writes
"""
import argparse
import pathlib
import re
import sys
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parent.parent
FILES = ROOT / 'files'
CSP_RAW = 'https://raw.githubusercontent.com/ac-custom-shaders-patch/acc-extension-config/master/config/'

errors, warnings = [], []


def err(msg):
    errors.append(msg)


def warn(msg):
    warnings.append(msg)


def parse_ini(text, keep_commented=False):
    """Return {section: {key: (value, comment)}}. Commented-out keys optional."""
    data, section = {}, None
    for raw in text.splitlines():
        line = raw.strip()
        if not line:
            continue
        m = re.match(r'^\[([^\]]+)\]', line)
        if m:
            section = m.group(1).strip()
            data.setdefault(section, {})
            continue
        commented = False
        if line.startswith(';'):
            if not keep_commented:
                continue
            line = line.lstrip(';').strip()
            commented = True
            if not re.match(r'^[A-Z0-9_]+\s*=', line):
                continue
        if section is None or '=' not in line:
            continue
        key, rest = line.split('=', 1)
        value, _, comment = rest.partition(';')
        data[section].setdefault(key.strip(), (value.strip(), comment.strip(), commented))
    return data


def check_ascii(path):
    raw = path.read_bytes()
    if raw.startswith(b'\xef\xbb\xbf'):
        err(f'{path.relative_to(ROOT)}: has a UTF-8 BOM')
    try:
        raw.decode('ascii')
    except UnicodeDecodeError as e:
        err(f'{path.relative_to(ROOT)}: non-ASCII byte at offset {e.start}')


def load_csp_module(module, csp_dir, cache):
    if module in cache:
        return cache[module]
    name = module.lower() + '.ini'
    text = None
    if csp_dir:
        p = pathlib.Path(csp_dir) / name
        if p.exists():
            text = p.read_text(encoding='utf-8', errors='replace')
    else:
        try:
            with urllib.request.urlopen(CSP_RAW + name, timeout=30) as r:
                text = r.read().decode('utf-8', errors='replace')
        except Exception as e:  # noqa: BLE001
            warn(f'could not fetch {name}: {e}')
    cache[module] = parse_ini(text, keep_commented=True) if text else None
    return cache[module]


def check_value(where, value, comment):
    """Validate a value against CSP's inline documentation, e.g.
    "1 or 0", "from 0.08 to 0.32, perc.", "0 for Low, 1 for Medium",
    'Always is 0, "Exterior view" is 1', "MEDIUM, HIGH or ULTRA"."""
    c = comment
    if re.search(r'(?:^|;)\s*1 or 0\s*(?:;|$)', c):
        if value not in ('0', '1'):
            err(f'{where}: expected 1 or 0, got {value!r}')
        return
    m = re.search(r'\bfrom\s+(-?[\d.]+)\D*?\s+to\s+(-?[\d.]+)', c, re.I)
    if m:
        lo, hi = float(m.group(1)), float(m.group(2))
        try:
            v = float(value)
        except ValueError:
            err(f'{where}: expected a number in [{lo}, {hi}], got {value!r}')
            return
        if not lo <= v <= hi:
            err(f'{where}: {v} is outside the documented range [{lo}, {hi}]')
        return
    options = set(re.findall(r'(-?\d[\w.]*) for ', c)) | set(re.findall(r'\bis (-?[\w.]+)', c))
    options |= set(re.findall(r'\b[A-Z][A-Z0-9_]{2,}\b', c))
    if options and value not in options:
        err(f'{where}: {value!r} is not one of the documented options {sorted(options)}')


def check_csp_preset(path, csp_dir, cache):
    rel = path.relative_to(ROOT)
    data = parse_ini(path.read_text(encoding='utf-8', errors='replace'))
    conf = data.get('CONFIGURATION')
    if not conf or conf.get('VERSION', ('',))[0] != '1':
        err(f'{rel}: needs [CONFIGURATION] VERSION=1 (Content Manager preset format)')
    if conf and conf.get('AFFECTED_SECTIONS', ('x',))[0] != '':
        warn(f'{rel}: AFFECTED_SECTIONS is not empty - Content Manager will reset those modules first')
    keys = set()
    for section, entries in data.items():
        if section == 'CONFIGURATION':
            continue
        if section.count(':') != 1:
            err(f'{rel}: section [{section}] must look like [MODULE:SECTION]')
            continue
        module, sub = section.split(':')
        if module == 'WEATHER_FX' and sub == 'BASIC':
            err(f'{rel}: must not touch WEATHER_FX:BASIC (it selects the weather style)')
        defaults = load_csp_module(module, csp_dir, cache)
        for key, (value, _, _) in entries.items():
            keys.add(f'{section}/{key}')
            where = f'{rel} [{section}] {key}'
            if defaults is None:
                warn(f'{where}: no default config for module {module} to check against')
                continue
            if sub not in defaults:
                err(f'{where}: section [{sub}] does not exist in {module.lower()}.ini')
                continue
            if key not in defaults[sub]:
                err(f'{where}: key does not exist in {module.lower()}.ini [{sub}]')
                continue
            _, comment, commented = defaults[sub][key]
            check_value(where, value, comment)
    return keys


# Keys found in Kunos' default.ini plus CSP's EXT_* sections
PP_KNOWN = {
    'ABOUT': {'AUTHOR', 'VERSION', 'NOTES', 'URL', 'CSP_EDITOR'},
    'YEBIS': {'ENABLED'},
    'OPTIMIZATIONS': {'FIXED_WIDTH'},
    'VARIOUS': {'APERTURE_RESULT_BLUR_MOD'},
    'AUTO_EXPOSURE': {'ENABLED', 'DELAY', 'MIN', 'MAX', 'METERING_WIDTH', 'METERING_HEIGHT',
                      'METERING_OFFSET_X', 'METERING_OFFSET_Y', 'TARGET', 'INFLUENCED_BY_GLARE'},
    'EXT_AUTO_EXPOSURE': {'METERING_AREA_DEBUG', 'METERING_AREA_SIZE', 'METERING_AREA_OFFSET'},
    'HEAT_SHIMMER': {'ENABLED', 'HEAT_PARTICLE_RADIUS', 'HEAT_PARTICLE_SHIMMER', 'HEAT_PARTICLE_COORD',
                     'HEAT_PARTICLE_FRACTAL_OCTAVES', 'HEAT_PARTICLE_COLOR', 'HEAT_PARTICLE_MAX_NUMBER',
                     'HEAT_PARTICLE_MIN_LIFE', 'HEAT_PARTICLE_LIFE_MULT', 'HEAT_PARTICLE_INTENSITY_MULT',
                     'HEAT_PARTICLE_MIN_INTENSITY', 'HEAT_PARTICLE_VELOCITY_MULT', 'HEAT_PARTICLE_MIN_VELOCITY',
                     'HEAT_PARTICLE_RADIUS_VELOCITY_MULT', 'HEAT_PARTICLE_POSITION_VELOCITY'},
    'TONEMAPPING': {'HDR', 'EXPOSURE', 'GAMMA', 'FUNCTION', 'MAPPING_FACTOR', 'SCALE_WIDTH',
                    'SCALE_HEIGHT', 'OFFSET_X', 'OFFSET_Y'},
    'EXT_HDR': {'FILMIC_CONTRAST', 'COLOR_GAMMA_CORRECTION'},
    'DOF': {'ENABLED', 'QUALITY', 'APERTURE_F_NUMBER', 'IMAGE_SENSOR_HEIGHT', 'BASE_FOV',
            'ADAPTIVE_APERTURE_FACTOR', 'APERTURE_PARAMETER', 'APERTURE_FRONT_LEVELS_NUMBER',
            'APERTURE_BACK_LEVELS_NUMBER', 'BACKGROUND_MASK_THRESHOLD', 'EDGE_QUALITY', 'APERTURE_SHAPE'},
    'CHROMATIC_ABERRATION': {'ENABLED', 'SAMPLES', 'LATERAL_DISPERSION', 'UNIFORM_DISPERSION'},
    'FEEDBACK': {'ENABLED', 'ASPECT_RATIO', 'WEIGHT', 'CURRENT_WEIGHT', 'TIME'},
    'VIGNETTING': {'STRENGTH', 'FOV_DEPENDENCE'},
    'DIAPHRAGM': {'ROTATE_SCALE', 'ROTATE_OFFSET', 'TYPE'},
    'AIRYDISC': {'ENABLED', 'WAVELENGTH', 'AIRY_DISC_DISPERSION_ENABLED'},
    'GODRAYS': {'ENABLED', 'USE_SUN_LIGHT', 'DIFFRACTION_RING', 'DIFFRACTION_RING_RADIUS',
                'DIFFRACTION_RING_ATTENUATION', 'DIFFRACTION_RING_SPECTRUM_ORDER',
                'DIFFRACTION_RING_OUTER_COLOR', 'COLOR', 'LENGTH', 'GLARE_RATIO', 'ANGLE_ATTENUATION',
                'NOISE_MASK', 'NOISE_FREQUENCY', 'DEPTH_MASK_THRESHOLD'},
    'LENSDISTORTION': {'ENABLED', 'ROUNDNESS', 'SMOOTHNESS'},
    'ANTIALIAS': {'ENABLED', 'START_DISTANCE', 'END_DISTANCE'},
    'COLOR': {'HUE', 'SATURATION', 'BRIGHTNESS', 'CONTRAST', 'SEPIA', 'COLOR_TEMP', 'WHITE_BALANCE'},
}
GLARE_SHAPE = {'SHAPE_LUMINANCE', 'SHAPE_BLOOM_LUMINANCE', 'SHAPE_BLOOM_DISPERSION',
               'SHAPE_BLOOM_DISPERSION_BASE_LEVEL', 'SHAPE_GHOST_LUMINANCE', 'SHAPE_GHOST_HALO_LUMINANCE',
               'SHAPE_GHOST_DISTORTION', 'SHAPE_GHOST_SHARPENESS', 'SHAPE_STAR_LUMINANCE',
               'SHAPE_STAR_STREAKS_NUMBER', 'SHAPE_STAR_LENGTH', 'SHAPE_STAR_SECONDARY_LENGTH',
               'SHAPE_STAR_ROTATION', 'SHAPE_STAR_INCLINATION_ANGLE', 'SHAPE_STAR_DISPERSION',
               'SHAPE_STAR_FORCE_DISPERSION', 'SHAPE_AFTERIMAGE_LUMINANCE', 'SHAPE_AFTERIMAGE_LENGTH'}
PP_KNOWN['GLARE'] = {'ENABLED', 'QUALITY', 'GHOST', 'AFTER_IMAGE', 'PRECISION', 'ANAMORPHIC', 'LUMINANCE',
                     'SHAPE', 'BLUR', 'THRESHOLD', 'BRIGHT_PASS', 'BLOOM_FILTER_THRESHOLD',
                     'BLOOM_GAUSSIAN_RADIUS_SCALE', 'BLOOM_LUMINANCE_GAMMA', 'BLOOM_NUM_LEVELS',
                     'GENERATION_RANGE_SCALE', 'STAR_FILTER_THRESHOLD', 'STAR_SOFTNESS',
                     'STAR_LENGTH_FOV_DEPENDENCE', 'GHOST_CONCENTRIC_DISTORTION', 'USE_CUSTOM_SHAPE'} | GLARE_SHAPE
PP_KNOWN['EXT_GLARE_FIRSTPERSON_SHAPE'] = {'ENABLED'} | GLARE_SHAPE
# Sections every filter must have (missing ones fall back to engine defaults)
PP_REQUIRED = set(PP_KNOWN) - {'ABOUT', 'EXT_AUTO_EXPOSURE', 'EXT_HDR', 'EXT_GLARE_FIRSTPERSON_SHAPE'}
TONEMAP_FUNCTIONS = set(range(-1, 17))  # -1 default, 0-6 YEBIS, 7-16 CSP (16 = AgX)


def check_pp_filter(path):
    rel = path.relative_to(ROOT)
    data = parse_ini(path.read_text(encoding='utf-8', errors='replace'))
    for section, entries in data.items():
        if section not in PP_KNOWN:
            err(f'{rel}: unknown section [{section}]')
            continue
        for key in entries:
            if key not in PP_KNOWN[section]:
                err(f'{rel}: unknown key [{section}] {key}')
    for section in PP_REQUIRED - set(data):
        err(f'{rel}: missing section [{section}]')
    fn = int(data['TONEMAPPING']['FUNCTION'][0])
    if fn not in TONEMAP_FUNCTIONS:
        err(f'{rel}: TONEMAPPING FUNCTION={fn} is not a CSP tonemap function')
    return data


# Keys Content Manager's VideoSettings reads and writes (AcManager.Tools VideoSettings.cs)
VIDEO_KNOWN = {
    'VIDEO': {'AASAMPLES': {'1', '2', '4', '8'}, 'ANISOTROPIC': {'0', '2', '4', '8', '16'},
              'SHADOW_MAP_SIZE': {'-1', '32', '64', '128', '256', '512', '1024', '2048', '3072', '4096',
                                  '6144', '8192'}},
    'ASSETTOCORSA': {'WORLD_DETAIL': {str(i) for i in range(6)}},
    'EFFECTS': {'MOTION_BLUR': {'0'}, 'RENDER_SMOKE_IN_MIRROR': {'0', '1'}, 'SMOKE': {str(i) for i in range(6)}},
    'POST_PROCESS': {'ENABLED': {'1'}, 'QUALITY': {str(i) for i in range(6)}, 'FILTER': None,
                     'GLARE': {str(i) for i in range(6)}, 'DOF': {str(i) for i in range(6)},
                     'RAYS_OF_GOD': {'0', '1'}, 'HEAT_SHIMMER': {'0', '1'}, 'FXAA': {'1'}},
    'MIRROR': {'HQ': {'0', '1'}, 'SIZE': {'0', '256', '512', '1024', '2048'}},
    'CUBEMAP': {'SIZE': {'256', '512', '1024', '2048'}, 'FACES_PER_FRAME': {str(i) for i in range(1, 7)},
                'FARPLANE': None},
    'SATURATION': {'LEVEL': None},
}


def check_video(path, filters):
    rel = path.relative_to(ROOT)
    data = parse_ini(path.read_text(encoding='utf-8', errors='replace'))
    for section, entries in data.items():
        if section not in VIDEO_KNOWN:
            err(f'{rel}: unexpected section [{section}]')
            continue
        for key, (value, _, _) in entries.items():
            if key not in VIDEO_KNOWN[section]:
                err(f'{rel}: unexpected key [{section}] {key}')
                continue
            allowed = VIDEO_KNOWN[section][key]
            if allowed is not None and value not in allowed:
                err(f'{rel}: [{section}] {key}={value} not one of {sorted(allowed, key=lambda x: float(x))}')
    if data['POST_PROCESS']['FILTER'][0] not in filters:
        err(f'{rel}: FILTER={data["POST_PROCESS"]["FILTER"][0]} is not one of the shipped filters')
    return data


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--csp-config', help='path to <assettocorsa>/extension/config (default: fetch from GitHub)')
    args = ap.parse_args()

    for p in sorted(FILES.rglob('*.ini')) + sorted(ROOT.glob('*.ps1')) + sorted(ROOT.glob('*.bat')):
        check_ascii(p)

    cache = {}
    presets = {p.stem: check_csp_preset(p, args.csp_config, cache) for p in sorted((FILES / 'csp-presets').glob('*.ini'))}
    names = sorted(presets)
    for a in names:
        for b in names:
            if a < b and presets[a] != presets[b]:
                err(f'presets "{a}" and "{b}" set different keys: {sorted(presets[a] ^ presets[b])}')

    filters = {p.stem: check_pp_filter(p) for p in sorted((FILES / 'ppfilters').glob('*.ini'))}
    for p in sorted((FILES / 'video').glob('*.ini')):
        check_video(p, filters)

    for w in warnings:
        print('warning:', w)
    for e in errors:
        print('ERROR:', e)
    n_keys = sum(len(v) for v in presets.values())
    print(f'\nchecked {len(presets)} CSP presets ({n_keys} keys), {len(filters)} PP filters, '
          f'{len(list((FILES / "video").glob("*.ini")))} video files: '
          f'{len(errors)} error(s), {len(warnings)} warning(s)')
    return 1 if errors else 0


if __name__ == '__main__':
    sys.exit(main())
