"""
build_cones.py -- builds the twenty traffic cones tape can be tied to, as FiveM assets.

    sd_tape_cone_01 .. sd_tape_cone_20   embedded palette texture, embedded collision
    sd_policetape_cones.ytyp             one archetype per cone (its own file: a game that has
                                         already loaded sd_policetape.ytyp keeps its copy of it)
    tools/cones.lua                      the sizes as built, for configs/holders.lua

Reuses the helpers of build_props.py (lathe, Sollumz conversion, DXT1 writer), so the same rules
apply: Blender 5.x with Sollumz, run in a Blender WINDOW. From the Blender MCP or Scripting tab:

    import runpy
    C = runpy.run_path(r"C:\\...\\sd-policetape\\tools\\build_cones.py")
    print(C["main"]())

Sizes follow real cones. US (square base): 12", 18", 28" and 36" tall, collars 6" and 4" wide.
EU (round base): 50, 75 and 100 cm, red with white bands. Every cone is hollow with an open top,
and the tape is tied round it 6 cm (4-5 cm on small ones) below the top.
"""

import bpy
import bmesh
import json
import math
import os
import runpy
import tempfile
import traceback

import numpy as np

try:
    HERE = os.path.dirname(os.path.abspath(__file__))
except NameError:
    HERE = r"C:\txData\Qbox_6CE7D0.base\resources\[standalone]\sd-policetape\tools"

B = runpy.run_path(os.path.join(HERE, "build_props.py"))
STREAM = B["STREAM"]
YTYP = "sd_policetape_cones"
LOD_DIST = 100.0
WALL = 0.004            # cone wall, shown at the open top
PROUD = 0.0012          # collars stand this far off the body, so they never flicker with it
SEGS = 28

# -- palette ----------------------------------------------------------------------------------------
TEX_NAME = "sd_policetape_cones_pal"
TEX = 128
CELL = 16
BODY_COLOURS = {
    "orange": (255, 90, 10),
    "red": (205, 24, 34),
    "yellow": (245, 205, 25),
    "lime": (186, 230, 30),
    "blue": (24, 74, 186),
    "white": (225, 225, 219),
    "black": (33, 33, 33),       # on a DXT1 grey step (see build_props.py)
    "pink": (245, 82, 160),
    "green": (24, 114, 58),
}
COLOURS = [(k, v) for k, v in BODY_COLOURS.items()]
COLOURS += [(k + "_in", tuple(int(c * 0.55) for c in v)) for k, v in BODY_COLOURS.items()]
COLOURS += [
    ("reflect", (246, 246, 240)),
    ("reflect_yellow", (250, 226, 52)),
    ("rubber", (25, 25, 25)),
    ("ink", (16, 16, 16)),
]


def palette_rgb():
    img = np.zeros((TEX, TEX, 3), np.float32)
    img[:, :] = (128, 128, 128)
    for i, (_, rgb) in enumerate(COLOURS):
        y, x = (i // 8) * CELL, (i % 8) * CELL
        img[y:y + CELL, x:x + CELL] = rgb
    return img


def write_dds(path):
    import struct
    body = b""
    for m in B["mip_chain"](palette_rgb()):
        u8 = np.clip(m + 0.5, 0, 255).astype(np.uint8)
        if u8.shape[0] < 4:
            u8 = np.tile(u8, (4 // u8.shape[0], 4 // u8.shape[1], 1))
        body += B["bc1"](u8)
    flags = 0x1 | 0x2 | 0x4 | 0x1000 | 0x20000 | 0x80000
    mips = int(math.log2(TEX)) + 1
    hdr = b"DDS " + struct.pack("<7I", 124, flags, TEX, TEX, (TEX // 4) ** 2 * 8, 0, mips) + b"\x00" * 44
    hdr += struct.pack("<2I4s5I", 32, 0x4, b"DXT1", 0, 0, 0, 0, 0)
    hdr += struct.pack("<5I", 0x1000 | 0x8 | 0x400000, 0, 0, 0, 0)
    with open(path, "wb") as f:
        f.write(hdr + body)


def palette_image():
    path = os.path.join(tempfile.gettempdir(), "sd_policetape_build", TEX_NAME + ".dds")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    write_dds(path)
    old = bpy.data.images.get(TEX_NAME + ".dds")
    if old is not None:
        bpy.data.images.remove(old)
    img = bpy.data.images.load(path)
    img.name = TEX_NAME + ".dds"
    img.colorspace_settings.name = 'sRGB'
    img.pack()
    return img


def cell(name):
    i = [n for n, _ in COLOURS].index(name)
    u = ((i % 8) * CELL + CELL / 2) / TEX
    v = 1.0 - ((i // 8) * CELL + CELL / 2) / TEX
    return lambda r, z: (u, v)


# -- the cones --------------------------------------------------------------------------------------
# H height, bh base height, r0 body radius at the base, r1 at the top. Square bases are w across,
# round ones R in radius. bands: (z from, z to) of each collar.
SIZES = {
    "us30": dict(H=0.305, bh=0.018, r0=0.076, r1=0.017, square=True, w=0.19, bands=[]),
    "us45": dict(H=0.457, bh=0.025, r0=0.105, r1=0.020, square=True, w=0.28, bands=[(0.229, 0.381)]),
    "us70": dict(H=0.711, bh=0.030, r0=0.135, r1=0.024, square=True, w=0.36,
                 bands=[(0.316, 0.418), (0.469, 0.621)]),
    "us90": dict(H=0.914, bh=0.032, r0=0.150, r1=0.026, square=True, w=0.39,
                 bands=[(0.509, 0.611), (0.662, 0.814)]),
    "us90r": dict(H=0.914, bh=0.034, r0=0.150, r1=0.026, square=False, R=0.21,
                  bands=[(0.509, 0.611), (0.662, 0.814)]),
    "eu50": dict(H=0.500, bh=0.030, r0=0.100, r1=0.020, square=False, R=0.15, bands=[(0.26, 0.36)]),
    "eu75": dict(H=0.750, bh=0.035, r0=0.130, r1=0.025, square=False, R=0.19,
                 bands=[(0.36, 0.46), (0.53, 0.63)]),
    "eu100": dict(H=1.000, bh=0.040, r0=0.160, r1=0.028, square=False, R=0.22,
                  bands=[(0.38, 0.48), (0.56, 0.66), (0.74, 0.84)]),
}
HAZARD = [(0.10, 0.19), (0.27, 0.36), (0.44, 0.53)]

# id, label, size, body colour, collar colour, base colour, collar override
CONES = [
    ("cone_orange", "Traffic cone (orange)", "us70", "orange", "reflect", "rubber", None),
    ("cone_orange_band", "Traffic cone (orange, one band)", "us70", "orange", "reflect", "rubber", [(0.469, 0.621)]),
    ("cone_orange_plain", "Traffic cone (orange, plain)", "us70", "orange", None, "orange", []),
    ("cone_highway", "Highway cone (orange, 90 cm)", "us90", "orange", "reflect", "rubber", None),
    ("cone_highway_round", "Highway cone (round base)", "us90r", "orange", "reflect", "rubber", None),
    ("cone_orange_45", "Traffic cone (orange, 45 cm)", "us45", "orange", "reflect", "rubber", None),
    ("cone_orange_45_plain", "Traffic cone (orange, 45 cm, plain)", "us45", "orange", None, "orange", []),
    ("cone_mini", "Mini cone (orange, 30 cm)", "us30", "orange", None, "orange", []),
    ("cone_red_white_75", "Traffic cone (red / white, 75 cm)", "eu75", "red", "reflect", "rubber", None),
    ("cone_red_white_50", "Traffic cone (red / white, 50 cm)", "eu50", "red", "reflect", "rubber", None),
    ("cone_red_white_100", "Traffic cone (red / white, 100 cm)", "eu100", "red", "reflect", "rubber", None),
    ("cone_yellow", "Traffic cone (yellow)", "us70", "yellow", "ink", "rubber", None),
    ("cone_lime", "Traffic cone (lime)", "us70", "lime", "reflect", "rubber", None),
    ("cone_blue", "Traffic cone (blue)", "us70", "blue", "reflect", "rubber", None),
    ("cone_white", "Traffic cone (white)", "us70", "white", "orange", "rubber", None),
    ("cone_black", "Traffic cone (black / yellow)", "us70", "black", "reflect_yellow", "rubber", None),
    ("cone_pink", "Traffic cone (pink)", "us70", "pink", "reflect", "rubber", None),
    ("cone_green", "Traffic cone (green)", "us70", "green", "reflect", "rubber", None),
    ("cone_hazard", "Hazard cone (yellow / black)", "us70", "yellow", "ink", "rubber", HAZARD),
    ("cone_red_45", "Traffic cone (red, 45 cm)", "us45", "red", "reflect", "rubber", None),
]


def tie_drop(H):
    return 0.06 if H >= 0.6 else (0.05 if H >= 0.45 else 0.04)


def r_at(s, z):
    return s["r0"] + (s["r1"] - s["r0"]) * (z - s["bh"]) / (s["H"] - s["bh"])


def build_body(bm, uv, s, bands, body, collar, inside):
    """The cone's shell, collars and open top, as one lathed surface."""
    H, bh = s["H"], s["bh"]
    depth = min(0.12, (H - bh) * 0.3)
    z0 = bh - 0.004                       # starts inside the base, so no seam shows
    prof, paints = [(r_at(s, z0), z0)], []
    for lo, hi in bands:
        prof.append((r_at(s, lo), lo)); paints.append(body)
        prof.append((r_at(s, lo) + PROUD, lo)); paints.append(collar)
        prof.append((r_at(s, hi) + PROUD, hi)); paints.append(collar)
        prof.append((r_at(s, hi), hi)); paints.append(collar)
    prof.append((s["r1"], H)); paints.append(body)
    prof.append((s["r1"] - WALL, H)); paints.append(body)          # the rim
    zd = H - depth
    prof.append((r_at(s, zd) - WALL, zd)); paints.append(inside)   # down the inside
    prof.append((0.0, zd)); paints.append(inside)                  # what the top shows
    B["lathe"](bm, uv, prof, paints, SEGS)


def build_round_base(bm, uv, s, paint):
    R, bh = s["R"], s["bh"]
    prof = [(0.0, 0.0), (R, 0.0), (R, bh * 0.55)]
    er, eh = 0.014, bh * 0.45
    for deg in (30, 60):
        a = math.radians(deg)
        prof.append((R - er + er * math.cos(a), bh * 0.55 + eh * math.sin(a)))
    prof += [(R - er, bh), (0.0, bh)]
    B["lathe"](bm, uv, prof, [paint] * (len(prof) - 1), 40)


def build_square_base(bm, uv, s, paint):
    """A slab with rounded corners and a chamfered top edge."""
    w, bh = s["w"], s["bh"]
    rc, steps, ch = min(0.03, w * 0.1), 4, min(0.006, bh * 0.3)

    def outline(inset):
        hw, rr = w / 2 - inset, rc - inset
        pts = []
        for cx, cy, a0 in ((1, 1, 0), (-1, 1, 90), (-1, -1, 180), (1, -1, 270)):
            for k in range(steps + 1):
                a = math.radians(a0 + 90 * k / steps)
                pts.append((cx * (hw - rr) + rr * math.cos(a), cy * (hw - rr) + rr * math.sin(a)))
        return pts

    rings = [[bm.verts.new((x, y, z)) for x, y in pts]
             for pts, z in ((outline(0), 0.0), (outline(0), bh - ch), (outline(ch), bh))]
    faces = [bm.faces.new(list(reversed(rings[0]))), bm.faces.new(rings[2])]
    n = len(rings[0])
    for a, b in ((rings[0], rings[1]), (rings[1], rings[2])):
        for j in range(n):
            k = (j + 1) % n
            faces.append(bm.faces.new([a[j], a[k], b[k], b[j]]))
    bmesh.ops.recalc_face_normals(bm, faces=faces)
    t = paint(0, 0)
    for f in faces:
        for loop in f.loops:
            loop[uv].uv = t


def builder(s, bands, body, collar, base, inside):
    def build(bm, uv):
        if s["square"]:
            build_square_base(bm, uv, s, base)
        else:
            build_round_base(bm, uv, s, base)
        build_body(bm, uv, s, bands, body, collar, inside)
    return build


def add_collision(drawable, coll, s):
    """Base and shell as two cylinders, so peds bump into a cone."""
    SollumType = B["sz"]("sollumz_properties").SollumType
    cm = B["sz"]("ybn.collision_materials")
    create_cylinder = B["sz"]("tools.meshhelper").create_cylinder
    apply_flag_preset = B["sz"]("tools.boundhelper").apply_flag_preset
    mat_index = {m.name: i for i, m in enumerate(cm.collisionmats)}

    comp = bpy.data.objects.new(drawable.name + ".col", None)
    comp.empty_display_size = 0
    comp.sollum_type = SollumType.BOUND_COMPOSITE
    coll.objects.link(comp)
    comp.parent = drawable
    base_r = s["w"] / 2 if s["square"] else s["R"]
    mid = r_at(s, (s["bh"] + s["H"]) / 2)
    for part, radius, z0, z1, material in (("base", base_r, 0.0, s["bh"], "RUBBER"),
                                           ("body", mid, s["bh"], s["H"], "PLASTIC")):
        me = bpy.data.meshes.new(drawable.name + ".col." + part)
        create_cylinder(me, radius=radius, length=z1 - z0, axis="Y")
        ob = bpy.data.objects.new(me.name, me)
        ob.sollum_type = SollumType.BOUND_CYLINDER
        coll.objects.link(ob)
        ob.parent = comp
        ob.rotation_euler = (math.radians(90), 0.0, 0.0)
        ob.location = (0.0, 0.0, (z0 + z1) / 2)
        apply_flag_preset(ob, 0)
        col_mat = cm.create_collision_material_from_index(mat_index[material])
        col_mat.name = "sd_tape_col_" + material.lower()
        me.materials.append(col_mat)


def facts(s, number, cid, label):
    tie = round(s["H"] - tie_drop(s["H"]), 4)
    return {
        "id": cid, "label": label, "model": "sd_tape_cone_%02d" % number,
        "tie": tie,
        # the radius at the lower edge of the tied tape (7.5 cm wide), so its turns sit on the cone
        "tieRadius": round(r_at(s, tie - 0.0375) + 0.002, 4),
        "body": [s["bh"], s["r0"], s["H"], s["r1"]],
        "base": [round(s["w"] / 2 if s["square"] else s["R"], 4), s["bh"], s["square"]],
    }


def write_lua(cones, path):
    lines = ["-- Written by tools/build_cones.py: the cones as built. configs/holders.lua",
             "-- holds a copy (tests/holders_check.lua compares the two).", "return {"]
    for c in cones:
        b, base = c["body"], c["base"]
        lines.append(("    { id = '%s', model = '%s', label = '%s', tie = %.4g, tieRadius = %.4g, "
                      "body = { %.4g, %.4g, %.4g, %.4g }, base = { %.4g, %.4g, %s } },")
                     % (c["id"], c["model"], c["label"].replace("'", "\\'"), c["tie"], c["tieRadius"],
                        b[0], b[1], b[2], b[3], base[0], base[1], "true" if base[2] else "false"))
    lines.append("}")
    with open(path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")


def export(report, stream):
    os.makedirs(stream, exist_ok=True)
    sc = bpy.context.scene
    coll = sc.collection
    image = palette_image()
    report["texture"] = {"name": TEX_NAME, "size": TEX, "format": "DXT1", "cells": len(COLOURS)}
    report["files"] = {}
    report["cones"] = []

    while len(sc.ytyps):
        bpy.ops.sollumz.deleteytyp()
    bpy.ops.sollumz.createytyp()
    ytyp = sc.ytyps[sc.ytyp_index]
    ytyp.name = YTYP

    for number, (cid, label, size, body, collar, base, bands) in enumerate(CONES, start=1):
        s = SIZES[size]
        bands = s["bands"] if bands is None else bands
        f = facts(s, number, cid, label)
        name = f["model"]
        ob = B["make_object"](name, builder(s, bands, cell(body), cell(collar or body), cell(base),
                                            cell(body + "_in")), coll, image)
        f["mesh"] = B["mesh_facts"](ob)
        drawable, _ = B["as_drawable"](ob)
        add_collision(drawable, coll, s)
        B["export_drawable"](drawable, name, stream, report)
        report["cones"].append(f)

    report["archetypes"] = {}
    for a in ytyp.archetypes:
        a.lod_dist = LOD_DIST
        report["archetypes"][a.name] = {"lod": a.lod_dist, "type": a.asset_type}
    bpy.ops.sollumz.export_ytyp_io(directory=stream, target_formats={'NATIVE'},
                                   target_versions={'GEN8'}, use_custom_settings=True)
    report["files"][YTYP + ".ytyp"] = B["file_facts"](os.path.join(stream, YTYP + ".ytyp"))
    write_lua(report["cones"], os.path.join(HERE, "cones.lua"))


def main(stream=None, keep=False, log_path=None):
    """Build and export all twenty cones. Returns a report."""
    report = {"ok": False}
    try:
        B["tidy"]()
        window = bpy.context.window_manager.windows[0]
        B["_state"]["scene"] = window.scene.name
        window.scene = bpy.data.scenes.new(B["SCENE"])
        area = next(a for a in window.screen.areas if a.type == 'VIEW_3D')
        region = next(r for r in area.regions if r.type == 'WINDOW')
        with bpy.context.temp_override(window=window, screen=window.screen, area=area,
                                       region=region, space_data=area.spaces.active):
            export(report, stream or STREAM)
        report["ok"] = len(report["cones"]) == len(CONES) and all(
            f["exists"] and (n.endswith(".ytyp") or f["magic"] == "RSC7") for n, f in report["files"].items())
    except Exception:
        report["error"] = traceback.format_exc()
    finally:
        if not keep:
            B["tidy"]()
    if log_path:
        with open(log_path, "w") as f:
            json.dump(report, f, indent=1, default=str)
    return report


if __name__ == "__main__":
    import sys
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    main(log_path=argv[0] if argv else None)
    bpy.ops.wm.quit_blender()
