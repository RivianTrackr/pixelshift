"""PixelShift icon directions as Icon Composer (.icon) bundles. Run: python3 make.py"""
import json
import os
import shutil

HERE = os.path.dirname(os.path.abspath(__file__))
WHITE, INK, CYAN = "#ffffff", "#0d1b24", "#22c3ec"


def p3(hex_color):
    h = hex_color.lstrip("#")
    r, g, b = (int(h[i:i + 2], 16) / 255 for i in (0, 2, 4))
    return f"display-p3:{r:.5f},{g:.5f},{b:.5f},1.00000"


def svg(body):
    return ('<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" '
            f'viewBox="0 0 1024 1024">{body}</svg>\n')


def rect(x, y, w, h, r, fill):
    return f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{r}" fill="{fill}"/>'


def photo(x, y, size, color):
    """Sun and mountains fitted to a square tile at (x, y)."""
    s = size / 312
    dx, dy = x - 194 * s, y - 530 * s
    return (f'<g transform="translate({dx:.1f} {dy:.1f}) scale({s:.4f})" fill="{color}">'
            '<circle cx="420" cy="618" r="34"/>'
            '<path d="M242 790 L330 676 Q342 661 355 676 L402 734 L428 704 '
            'Q440 690 452 704 L470 726 L470 790 Z"/></g>')


def strokes(paths, color, width):
    d = "".join(f'<path d="{p}"/>' for p in paths)
    return (f'<g fill="none" stroke="{color}" stroke-width="{width}" stroke-linecap="round" '
            f'stroke-linejoin="round">{d}</g>')


def write(slug, top, bottom, groups):
    """groups: list of (name, translucency, [(layer, svg_body, glass)]) front to back."""
    path = os.path.join(HERE, f"{slug}.icon")
    shutil.rmtree(path, ignore_errors=True)
    os.makedirs(os.path.join(path, "Assets"))
    doc_groups = []
    for name, translucency, layers in groups:
        for layer, body, _ in layers:
            with open(os.path.join(path, "Assets", f"{layer}.svg"), "w") as f:
                f.write(svg(body))
        doc_groups.append({
            "name": name,
            "layers": [{"name": l, "image-name": f"{l}.svg", "glass": g} for l, _, g in layers],
            "shadow": {"kind": "neutral", "opacity": 0.5},
            "translucency": {"enabled": True, "value": translucency},
            "specular": True,
        })
    doc = {
        "fill": {"linear-gradient": [p3(top), p3(bottom)],
                 "orientation": {"start": {"x": 0.5, "y": 0}, "stop": {"x": 0.5, "y": 0.75}}},
        "groups": doc_groups,
        "supported-platforms": {"squares": ["macOS"]},
    }
    with open(os.path.join(path, "icon.json"), "w") as f:
        json.dump(doc, f, indent=2)


# A. Photo with a resize badge: one big glass photo, a cyan badge with a two-way arrow.
write("a-photo-badge", "#123a55", "#060f17", [
    ("Badge", 0.1, [
        ("badge-arrow", strokes(["M688 332 L792 228", "M688 272 L688 332 L748 332", "M732 228 L792 228 L792 288"], WHITE, 34), False),
        ("badge", f'<circle cx="740" cy="280" r="150" fill="{CYAN}"/>', True)]),
    ("Photo", 0.15, [
        ("photo-glyph", photo(200, 290, 540, CYAN), False),
        ("card", rect(200, 290, 540, 540, 116, WHITE), True)]),
])

# B. Shrink: a glass frame with a solid cyan square tucked in its corner and an arrow.
write("b-shrink", "#262b33", "#0b0d10", [
    ("Small", 0.0, [("small", rect(306, 454, 264, 264, 62, CYAN), True)]),
    ("Frame", 0.4, [
        ("arrow", strokes(["M726 298 L606 418", "M606 326 L606 418 L698 418"], WHITE, 52), False),
        ("frame", f'<rect x="222" y="170" width="630" height="630" rx="140" fill="none" stroke="{WHITE}" stroke-width="58"/>', True)]),
])

# C. Shift: a photo sliding down-left, with fading glass copies trailing behind it.
write("c-motion", "#56d8f6", "#0a78b8", [
    ("Photo", 0.0, [
        ("photo-glyph", photo(214, 386, 420, CYAN), False),
        ("photo", rect(214, 386, 420, 420, 96, WHITE), True)]),
    ("Trail 1", 0.55, [("trail1", rect(314, 286, 420, 420, 96, WHITE), True)]),
    ("Trail 2", 0.8, [("trail2", rect(414, 186, 420, 420, 96, WHITE), True)]),
])

# D. Crop handles: white glass corners around a cyan photo, on ink.
write("d-handles", "#22323d", "#090f14", [
    ("Photo", 0.1, [
        ("photo-glyph", photo(332, 332, 360, INK), False),
        ("photo", rect(332, 332, 360, 360, 84, CYAN), True)]),
    ("Handles", 0.35, [("handles", strokes([
        "M190 330 L190 190 L330 190", "M694 190 L834 190 L834 330",
        "M834 694 L834 834 L694 834", "M330 834 L190 834 L190 694"], WHITE, 60), True)]),
])

# E. Stacked sizes: three glass photos, large to small, on cyan.
write("e-stacked", "#5fd6f2", "#0f6fae", [
    ("Small", 0.0, [
        ("photo-glyph", photo(180, 540, 280, "#0f8fcf"), False),
        ("small", rect(180, 540, 280, 280, 68, WHITE), True)]),
    ("Medium", 0.45, [("medium", rect(290, 350, 360, 360, 84, WHITE), True)]),
    ("Large", 0.7, [("large", rect(400, 160, 460, 460, 100, WHITE), True)]),
])

# F. Inward arrows: four corners pressing in on a cyan square (the "make smaller" gesture).
write("f-inward", "#3b4149", "#111317", [
    ("Center", 0.0, [("center", rect(392, 392, 240, 240, 56, CYAN), True)]),
    ("Arrows", 0.3, [("arrows", strokes([
        "M222 222 L338 338", "M338 246 L338 338 L246 338",
        "M802 222 L686 338", "M686 246 L686 338 L778 338",
        "M222 802 L338 686", "M246 686 L338 686 L338 778",
        "M802 802 L686 686", "M778 686 L686 686 L686 778"], WHITE, 56), True)]),
])
print("ok")
