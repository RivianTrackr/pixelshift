"""Writes icon options as Icon Composer (.icon) bundles next to this script.

Each option is a set of SVG layers on a 1024 canvas plus an icon.json that
groups them; macOS adds the Liquid Glass material when it renders them.
Run: python3 make_options.py
"""
import json
import os
import shutil

HERE = os.path.dirname(os.path.abspath(__file__))
INK = "#1b1e24"


def p3(hex_color, alpha=1.0):
    h = hex_color.lstrip("#")
    r, g, b = (int(h[i:i + 2], 16) / 255 for i in (0, 2, 4))
    return f"display-p3:{r:.5f},{g:.5f},{b:.5f},{alpha:.5f}"


def svg(body):
    return ('<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" '
            f'viewBox="0 0 1024 1024">{body}</svg>\n')


# Shared shapes --------------------------------------------------------------

def plate(color):
    return svg(f'<rect x="330" y="196" width="500" height="500" rx="104" fill="{color}"/>')


def arrow(color):
    return svg(f'<g fill="none" stroke="{color}" stroke-width="58" stroke-linecap="round" '
               'stroke-linejoin="round"><path d="M738 288 L560 466"/>'
               '<path d="M556 330 L556 470 L696 470"/></g>')


def tile(color):
    return svg(f'<rect x="194" y="530" width="312" height="312" rx="76" fill="{color}"/>')


def photo(color, dx=0, dy=0, s=1.0):
    # Sun + mountains, drawn for the small tile; dx/dy/s move it for other layouts.
    t = f'transform="translate({dx} {dy}) scale({s})"'
    return svg(f'<g {t} fill="{color}"><circle cx="420" cy="618" r="34"/>'
               '<path d="M242 790 L330 676 Q342 661 355 676 L402 734 L428 704 '
               'Q440 690 452 704 L470 726 L470 790 Z"/></g>')


def group(name, layers, translucency=0.3, shadow="neutral"):
    return {
        "name": name,
        "layers": [{"name": n, "image-name": f"{n}.svg", "glass": g} for n, g in layers],
        "shadow": {"kind": shadow, "opacity": 0.5},
        "translucency": {"enabled": True, "value": translucency},
        "specular": True,
    }


def write(slug, top, bottom, files, groups, stop_y=0.7):
    path = os.path.join(HERE, f"{slug}.icon")
    shutil.rmtree(path, ignore_errors=True)
    os.makedirs(os.path.join(path, "Assets"))
    for name, content in files.items():
        with open(os.path.join(path, "Assets", f"{name}.svg"), "w") as f:
            f.write(content)
    doc = {
        "fill": {
            "linear-gradient": [p3(top), p3(bottom)],
            "orientation": {"start": {"x": 0.5, "y": 0}, "stop": {"x": 0.5, "y": stop_y}},
        },
        "groups": groups,
        "supported-platforms": {"squares": ["macOS"]},
    }
    with open(os.path.join(path, "icon.json"), "w") as f:
        json.dump(doc, f, indent=2)


# Options --------------------------------------------------------------------

# 1. Current: ink background, white glass frame, gold photo.
write("1-ink-gold", "#2d2f36", "#111316",
      {"photo": photo(INK), "tile": tile("#fba919"), "arrow": arrow(INK), "plate": plate("#ffffff")},
      [group("Resized", [("photo", False), ("tile", True)], 0.2, "layer-color"),
       group("Original", [("arrow", False), ("plate", True)], 0.45)])

# 2. Paper: the light site theme. Ink glass frame on warm off-white.
write("2-paper", "#fdfcf9", "#e4e0d8",
      {"photo": photo(INK), "tile": tile("#fba919"), "arrow": arrow("#f6f4f0"), "plate": plate("#23262d")},
      [group("Resized", [("photo", False), ("tile", True)], 0.2, "layer-color"),
       group("Original", [("arrow", False), ("plate", True)], 0.3)])

# 3. Blue: Apple utility feel. White glass shapes on a vivid blue.
write("3-blue", "#4a9bff", "#1546c4",
      {"photo": photo("#1f5fe0"), "tile": tile("#ffffff"), "arrow": arrow("#1f5fe0"), "plate": plate("#ffffff")},
      [group("Resized", [("photo", False), ("tile", True)], 0.1),
       group("Original", [("arrow", False), ("plate", True)], 0.7)])

# 4. Gold: all-in on the brand color, with an ink frame.
write("4-gold", "#ffcb57", "#ef8a00",
      {"photo": photo("#8a5800"), "tile": tile("#ffffff"), "arrow": arrow("#fba919"), "plate": plate(INK)},
      [group("Resized", [("photo", False), ("tile", True)], 0.15),
       group("Original", [("arrow", False), ("plate", True)], 0.35)])

# 5. Crop marks: a different idea. Corner handles squeezing a photo, on graphite.
brackets = svg(
    '<g fill="none" stroke="#ffffff" stroke-width="56" stroke-linecap="round" stroke-linejoin="round">'
    '<path d="M196 330 L196 196 L330 196"/><path d="M694 196 L828 196 L828 330"/>'
    '<path d="M828 694 L828 828 L694 828"/><path d="M330 828 L196 828 L196 694"/></g>')
center_tile = svg('<rect x="330" y="330" width="364" height="364" rx="84" fill="#fba919"/>')
write("5-crop-marks", "#4a4f58", "#16191e",
      {"photo2": photo(INK, dx=103.7, dy=-288.3, s=1.1667), "center": center_tile, "brackets": brackets},
      [group("Photo", [("photo2", False), ("center", True)], 0.2, "layer-color"),
       group("Handles", [("brackets", True)], 0.4)])

# 6. Stacked sizes: three cascading photos, large to small, on a coral gradient.
big = svg('<rect x="400" y="160" width="460" height="460" rx="100" fill="#ffffff"/>')
mid = svg('<rect x="290" y="350" width="360" height="360" rx="84" fill="#ffffff"/>')
small = svg('<rect x="180" y="540" width="280" height="280" rx="68" fill="#ffffff"/>')
write("6-stacked", "#ff8a5c", "#d6336c",
      {"photo3": photo("#e0485e", dx=5.9, dy=64.4, s=0.8974), "small": small, "mid": mid, "big": big},
      [group("Small", [("photo3", False), ("small", True)], 0.05),
       group("Medium", [("mid", True)], 0.45),
       group("Large", [("big", True)], 0.7)])

print("ok")
