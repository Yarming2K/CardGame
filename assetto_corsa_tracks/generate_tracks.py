"""Generate UI graphics for four original Assetto Corsa tracks.

For each track this writes, under <track_id>/:
  ui/outline.png   - white track outline on transparent bg (track select screen)
  ui/preview.png   - stylised 1280x720 preview card
  ui/ui_track.json - track metadata read by Assetto Corsa / Content Manager
  map.png          - minimap (white on transparent) for the in-game HUD
Plus showcase.png with all four tracks side by side.

Run:  python3 generate_tracks.py
"""
import json
import math
import os

from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
FONT_B = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
FONT_R = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"

# Control points are in a 0..100 box; a closed Catmull-Rom spline runs through
# them in order. Point 0 -> 1 is the start/finish straight.
TRACKS = [
    {
        "id": "kestrel_ridge",
        "name": "Kestrel Ridge Raceway",
        "description": "A fast, flowing mountain circuit carved into a granite ridge. "
                       "Blind crests, a plunging downhill esses and a long uphill "
                       "back straight reward commitment.",
        "country": "Fictional - Alpine", "city": "Kestrel Pass",
        "length": "4820", "width": "12", "pitboxes": "24",
        "corners": 14, "elev": "86 m",
        "tags": ["circuit", "original", "mountain", "elevation"],
        "bg": [(18, 32, 48), (52, 84, 104)], "accent": (255, 176, 59),
        "sectors": [(255, 92, 92), (92, 200, 255), (255, 214, 92)],
        "pts": [(20, 80), (55, 84), (80, 80), (90, 68), (82, 58), (88, 46),
                (92, 30), (82, 16), (66, 20), (60, 34), (48, 40), (40, 28),
                (28, 14), (14, 22), (16, 40), (26, 52), (14, 64)],
    },
    {
        "id": "port_solano",
        "name": "Port Solano Street Circuit",
        "description": "A night street race through a Mediterranean harbour town. "
                       "Tight 90-degree corners, a waterfront promenade blast and "
                       "unforgiving walls.",
        "country": "Fictional - Mediterranean", "city": "Port Solano",
        "length": "3610", "width": "10", "pitboxes": "20",
        "corners": 18, "elev": "12 m",
        "tags": ["street", "original", "night", "city"],
        "bg": [(14, 12, 36), (64, 30, 92)], "accent": (255, 64, 160),
        "sectors": [(255, 64, 160), (64, 230, 255), (180, 255, 90)],
        "pts": [(14, 84), (50, 86), (86, 84), (88, 66), (74, 64), (72, 50),
                (88, 46), (88, 18), (70, 14), (68, 32), (54, 34), (52, 16),
                (32, 14), (30, 36), (44, 44), (42, 60), (24, 58), (12, 64)],
        "sharp": 0.32,
    },
    {
        "id": "valdren_ring",
        "name": "Valdren Ring",
        "description": "A long, high-speed forest circuit with sweeping curves, "
                       "a flat-out kink section and a heavy-braking hairpin at the "
                       "end of the 1.4 km Mistral straight.",
        "country": "Fictional - Northern Europe", "city": "Valdren",
        "length": "6140", "width": "13", "pitboxes": "30",
        "corners": 16, "elev": "41 m",
        "tags": ["circuit", "original", "forest", "high speed"],
        "bg": [(10, 34, 22), (40, 92, 58)], "accent": (196, 255, 120),
        "sectors": [(255, 120, 80), (120, 220, 255), (255, 235, 120)],
        "pts": [(10, 56), (12, 28), (26, 12), (44, 18), (52, 32), (64, 22),
                (84, 12), (94, 26), (86, 40), (90, 56), (84, 72), (68, 66),
                (56, 74), (60, 88), (40, 90), (24, 82)],
    },
    {
        "id": "sable_flats",
        "name": "Sable Flats Motorpark",
        "description": "A technical desert club circuit on a dry lake bed. "
                       "Wide run-offs, a tricky double-apex carousel and a "
                       "tight infield that punishes poor traction.",
        "country": "Fictional - Desert Southwest", "city": "Sable Flats",
        "length": "4210", "width": "14", "pitboxes": "28",
        "corners": 15, "elev": "6 m",
        "tags": ["circuit", "original", "desert", "technical"],
        "bg": [(64, 30, 14), (204, 120, 60)], "accent": (255, 240, 200),
        "sectors": [(255, 70, 70), (70, 170, 255), (255, 255, 255)],
        "pts": [(30, 88), (70, 88), (88, 80), (92, 62), (80, 54), (66, 60),
                (56, 50), (64, 38), (84, 32), (86, 14), (64, 10), (44, 18),
                (36, 34), (22, 30), (10, 40), (14, 58), (30, 60), (18, 76)],
    },
]


def catmull_rom(pts, samples=40, tension=0.5):
    """Closed Catmull-Rom spline (tension 0.5 = standard; lower = sharper)."""
    out = []
    n = len(pts)
    for i in range(n):
        p0, p1, p2, p3 = pts[i - 1], pts[i], pts[(i + 1) % n], pts[(i + 2) % n]
        m1 = ((p2[0] - p0[0]) * tension, (p2[1] - p0[1]) * tension)
        m2 = ((p3[0] - p1[0]) * tension, (p3[1] - p1[1]) * tension)
        for s in range(samples):
            t = s / samples
            t2, t3 = t * t, t * t * t
            h00, h10 = 2 * t3 - 3 * t2 + 1, t3 - 2 * t2 + t
            h01, h11 = -2 * t3 + 3 * t2, t3 - t2
            out.append((h00 * p1[0] + h10 * m1[0] + h01 * p2[0] + h11 * m2[0],
                        h00 * p1[1] + h10 * m1[1] + h01 * p2[1] + h11 * m2[1]))
    return out


def fit(path, w, h, margin):
    xs, ys = [p[0] for p in path], [p[1] for p in path]
    minx, maxx, miny, maxy = min(xs), max(xs), min(ys), max(ys)
    s = min((w - 2 * margin) / (maxx - minx), (h - 2 * margin) / (maxy - miny))
    ox = (w - (maxx - minx) * s) / 2 - minx * s
    oy = (h - (maxy - miny) * s) / 2 - miny * s
    return [(x * s + ox, y * s + oy) for x, y in path]


def stroke(draw, path, width, fill):
    draw.line(path + [path[0]], fill=fill, width=width, joint="curve")
    r = width / 2
    for x, y in path[:: max(1, len(path) // 200)]:
        draw.ellipse((x - r, y - r, x + r, y + r), fill=fill)


def track_path(t):
    return catmull_rom(t["pts"], tension=t.get("sharp", 0.5))


def outline_png(t, size=1024, width=26, ss=2):
    img = Image.new("RGBA", (size * ss, size * ss), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    path = fit(track_path(t), size * ss, size * ss, 60 * ss)
    stroke(d, path, width * ss, (255, 255, 255, 255))
    return img.resize((size, size), Image.LANCZOS)


def map_png(t, size=1024, ss=2):
    # Minimap: thin white line, AC tints it in the HUD.
    return outline_png(t, size, width=14, ss=ss)


def gradient(w, h, c1, c2):
    img = Image.new("RGB", (w, h))
    px = img.load()
    for y in range(h):
        for x in range(w):
            k = min(1.0, (x / w) * 0.45 + (y / h) * 0.75)
            px[x, y] = tuple(int(c1[i] + (c2[i] - c1[i]) * k) for i in range(3))
    return img


def preview_png(t, W=1280, H=720, ss=2):
    w, h = W * ss, H * ss
    img = gradient(w // 4, h // 4, *t["bg"]).resize((w, h), Image.BICUBIC).convert("RGBA")

    # subtle grid
    grid = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    g = ImageDraw.Draw(grid)
    for x in range(0, w, 40 * ss):
        g.line([(x, 0), (x, h)], fill=(255, 255, 255, 12), width=ss)
    for y in range(0, h, 40 * ss):
        g.line([(0, y), (w, y)], fill=(255, 255, 255, 12), width=ss)
    img.alpha_composite(grid)

    # track area on the right
    box = (int(w * 0.42), 0, w, h)
    bw, bh = box[2] - box[0], box[3] - box[1]
    path = [(x + box[0], y) for x, y in fit(track_path(t), bw, bh, 70 * ss)]

    glow = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    stroke(ImageDraw.Draw(glow), path, 44 * ss, t["accent"] + (150,))
    img.alpha_composite(glow.filter(ImageFilter.GaussianBlur(18 * ss)))

    layer = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    stroke(d, path, 30 * ss, (20, 20, 24, 255))         # tarmac border
    stroke(d, path, 22 * ss, (58, 60, 66, 255))         # tarmac
    # sector colour centre line
    n = len(path)
    for si, col in enumerate(t["sectors"]):
        a, b = n * si // 3, n * (si + 1) // 3
        seg = path[a:b + 1] if b < n else path[a:] + [path[0]]
        d.line(seg, fill=col + (255,), width=5 * ss, joint="curve")
    # start / finish chequer across the track at path[0]
    (x0, y0), (x1, y1) = path[0], path[2]
    ang = math.atan2(y1 - y0, x1 - x0)
    nx, ny = -math.sin(ang), math.cos(ang)
    tx, ty = math.cos(ang), math.sin(ang)
    sq = 5.5 * ss
    for i in range(-2, 2):
        for j in range(2):
            cx = x0 + nx * (i + 0.5) * sq + tx * (j - 0.5) * sq
            cy = y0 + ny * (i + 0.5) * sq + ty * (j - 0.5) * sq
            col = (255, 255, 255, 255) if (i + j) % 2 == 0 else (0, 0, 0, 255)
            pts = [(cx + (dx * tx + dy * nx) * sq / 2, cy + (dx * ty + dy * ny) * sq / 2)
                   for dx, dy in ((-1, -1), (1, -1), (1, 1), (-1, 1))]
            d.polygon(pts, fill=col)
    # direction arrow just after S/F
    ax, ay = path[n // 30]
    bx, by = path[n // 30 + 3]
    a2 = math.atan2(by - ay, bx - ax)
    L = 26 * ss
    off = 34 * ss
    cx, cy = ax - math.sin(a2) * off, ay + math.cos(a2) * off
    tip = (cx + math.cos(a2) * L, cy + math.sin(a2) * L)
    left = (cx + math.cos(a2 + 2.5) * L * 0.6, cy + math.sin(a2 + 2.5) * L * 0.6)
    right = (cx + math.cos(a2 - 2.5) * L * 0.6, cy + math.sin(a2 - 2.5) * L * 0.6)
    d.polygon([tip, left, right], fill=t["accent"] + (255,))
    img.alpha_composite(layer)

    # text panel
    d = ImageDraw.Draw(img)
    fx = 70 * ss
    d.rectangle((fx - 30 * ss, 90 * ss, fx - 22 * ss, 250 * ss), fill=t["accent"] + (255,))
    words = t["name"].upper().split()
    lines, cur = [], ""
    for wd in words:
        if len(cur) + len(wd) > 12 and cur:
            lines.append(cur)
            cur = wd
        else:
            cur = (cur + " " + wd).strip()
    lines.append(cur)
    fnt = ImageFont.truetype(FONT_B, 54 * ss)
    y = 90 * ss
    for ln in lines:
        d.text((fx, y), ln, font=fnt, fill=(255, 255, 255, 255))
        y += 62 * ss
    sub = ImageFont.truetype(FONT_R, 20 * ss)
    d.text((fx, y + 6 * ss), f"{t['city']}  ·  {t['country'].replace('Fictional - ', '')}",
           font=sub, fill=t["accent"] + (255,))
    y += 70 * ss
    lab = ImageFont.truetype(FONT_R, 15 * ss)
    val = ImageFont.truetype(FONT_B, 30 * ss)
    stats = [("LENGTH", f"{int(t['length']) / 1000:.2f} km"), ("CORNERS", str(t["corners"])),
             ("ELEVATION", t["elev"]), ("DIRECTION", "CW" if t["run"] == "clockwise" else "CCW"),
             ("PIT BOXES", t["pitboxes"]), ("WIDTH", f"{t['width']} m")]
    for k, (l, v) in enumerate(stats):
        cx = fx + (k % 2) * 220 * ss
        cy = y + (k // 2) * 80 * ss
        d.text((cx, cy), l, font=lab, fill=(255, 255, 255, 160))
        d.text((cx, cy + 20 * ss), v, font=val, fill=(255, 255, 255, 255))
    # sector legend
    ly = y + 260 * ss
    for k, col in enumerate(t["sectors"]):
        lx = fx + k * 120 * ss
        d.rectangle((lx, ly, lx + 26 * ss, ly + 8 * ss), fill=col + (255,))
        d.text((lx + 34 * ss, ly - 6 * ss), f"S{k + 1}", font=lab, fill=(255, 255, 255, 200))

    return img.resize((W, H), Image.LANCZOS).convert("RGB")


def ui_json(t):
    return {
        "name": t["name"], "description": t["description"], "tags": t["tags"],
        "geotags": [], "country": t["country"], "city": t["city"],
        "length": t["length"], "width": t["width"], "pitboxes": t["pitboxes"],
        "run": t["run"], "author": "Original design", "version": "1.0", "url": "",
    }


def run_direction(pts):
    """Driving direction as seen on screen (y axis points down)."""
    area = sum(pts[i - 1][0] * p[1] - p[0] * pts[i - 1][1] for i, p in enumerate(pts))
    return "clockwise" if area > 0 else "anticlockwise"


def main():
    previews = []
    for t in TRACKS:
        t["run"] = run_direction(t["pts"])
        t["tags"] = t["tags"] + [t["run"]]
        root = os.path.join(HERE, t["id"])
        ui = os.path.join(root, "ui")
        os.makedirs(ui, exist_ok=True)
        outline_png(t).save(os.path.join(ui, "outline.png"))
        map_png(t).save(os.path.join(root, "map.png"))
        p = preview_png(t)
        p.save(os.path.join(ui, "preview.png"))
        previews.append(p)
        with open(os.path.join(ui, "ui_track.json"), "w") as f:
            json.dump(ui_json(t), f, indent=2)
        print("wrote", t["id"])
    sheet = Image.new("RGB", (2560, 1440))
    for i, p in enumerate(previews):
        sheet.paste(p, ((i % 2) * 1280, (i // 2) * 720))
    sheet.resize((1920, 1080), Image.LANCZOS).save(os.path.join(HERE, "showcase.png"))


if __name__ == "__main__":
    main()
