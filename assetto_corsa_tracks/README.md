# Assetto Corsa track graphics

UI graphics for four original, fictional tracks. Each folder mirrors the
layout of `content/tracks/<track_id>/` in Assetto Corsa:

| File | Purpose |
|---|---|
| `ui/preview.png` | 1280×720 preview card on the track select screen |
| `ui/outline.png` | 1024×1024 white outline on transparent bg |
| `ui/ui_track.json` | name, description, length, pit boxes, direction, tags |
| `map.png` | white minimap for the in-game HUD (needs a matching `data/map.ini` from your track's AI line) |

Tracks: **Kestrel Ridge Raceway** (mountain), **Port Solano Street Circuit**
(night street), **Valdren Ring** (high-speed forest), **Sable Flats Motorpark**
(desert). `showcase.png` shows all four.

These are graphics only; they don't include a 3D track model (`.kn5`).
To change a layout or colours, edit `TRACKS` in `generate_tracks.py` and run:

    python3 generate_tracks.py
