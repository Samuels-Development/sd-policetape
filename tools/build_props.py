"""
build_props.py -- builds the two sd-policetape props and exports them as FiveM assets.

    sd_tape_post   a portable delineator post that police tape is tied to (embedded collision)
    sd_tape_roll   a hand-held roll of barrier tape (no collision)

Writes into ../stream:

    sd_tape_post.ydr, sd_tape_roll.ydr   textures EMBEDDED in each drawable, so no .ytd
    sd_policetape.ytyp                   one archetype per model

Needs Blender 5.x with the Sollumz extension enabled, and a Blender WINDOW: Sollumz's ytyp
operators read context.space_data, which a background (-b) session does not have. From the
Blender MCP or the Scripting tab:

    import runpy
    B = runpy.run_path(r"C:\\...\\sd-policetape\\tools\\build_props.py")
    print(B["main"]())

or from a shell (builds, writes a JSON report, closes Blender again):

    blender --python build_props.py -- <log.json>

It builds in a scene of its own and removes it afterwards, so whatever else is open in that
Blender is left alone. main(keep=True) leaves the build scene up to look at; call tidy() when
done with it.

Everything is procedural: change the numbers below and re-run. If a model is changed and
re-exported for a server with players on it, give it a NEW name (main(suffix="_v2"), then
rename the files): a connected game client keeps drawing its own copy of a same-named streamed
file after the resource restarts, and only a file it has never seen is fetched fresh.

The one number the script side depends on is TIE_Z: the height above the post's origin where
the tape is tied, the middle of the groove in the cap.
"""

import bpy
import bmesh
import json
import math
import os
import struct
import sys
import tempfile
import traceback

import numpy as np
from mathutils import Matrix

try:
    HERE = os.path.dirname(os.path.abspath(__file__))
except NameError:
    HERE = r"C:\txData\Qbox_6CE7D0.base\resources\[standalone]\sd-policetape\tools"
RESOURCE = os.path.normpath(os.path.join(HERE, ".."))
STREAM = os.path.join(RESOURCE, "stream")

POST = "sd_tape_post"
ROLL = "sd_tape_roll"
YTYP = "sd_policetape"
LOD_DIST = 100.0
SCENE = "sd_policetape_build"
SZ = "bl_ext.user_default.sollumz"

# -- the post (metres; origin = centre of the base's underside, on the ground, +Z up) ------------
BASE_R = 0.150          # rubber base, 0.30 across
BASE_H = 0.045
COLLAR_R = 0.045        # raised collar where the pole enters
COLLAR_TOP = 0.075
POLE_R = 0.0275         # 55 mm pole
POLE_FOOT = 0.070       # the pole starts inside the collar, so no seam shows
POLE_TOP = 0.985
BAND_R = 0.0285         # reflective bands stand 1 mm proud of the pole
BAND_H = 0.055
BAND_Z = (0.78, 0.90)   # band centres
CAP_R = 0.031
CAP_TOP = 1.050
TIE_Z = 1.000           # THE TAPE TIES HERE: the middle of the cap's groove
NECK_R = 0.026          # the groove's floor
NECK_H = 0.017          # the groove spans TIE_Z +- NECK_H / 2
CAP_ROUND = 0.014       # radius of the rounding on the cap's top edge
SEGS_BASE = 32
SEGS_POLE = 20

# -- the roll (origin = centre of the roll, roll axis = local X) ---------------------------------
ROLL_R = 0.060          # 0.12 across
HOLE_R = 0.0375         # 0.075 hole
CORE_WALL = 0.004       # cardboard tube
CORE_R = HOLE_R + CORE_WALL
TAPE_W = 0.075
CORE_W = 0.078          # a little wider than the tape so its rim shows
SEGS_ROLL = 40

# -- the palette atlas ------------------------------------------------------------------------------
# One 128 x 128 DXT1 texture for both models. Rows 0-31 are 16 px blocks of flat colour; every
# face's UVs sit in the middle of its block. Two bands below them are 1-D stripes, read along U:
# the tape's outer face (black printed edges) and its flat sides (faint wound-layer rings).
# Rows and pixels count from the TOP of the image, the way the DDS is written.
TEX_NAME = "sd_policetape_pal"   # Sollumz names an embedded texture after the image FILE
TEX = 128
CELL = 16
COLOURS = [
    ("orange", (255, 90, 10)),      # #FF5A0A signal orange
    ("reflect", (246, 246, 240)),   # retro-reflective white, the brightest thing on the post
    # Game light lifts dark albedo a long way, so these stay low. Greys must sit on a DXT1
    # 5:6:5 step that is the same in all three channels (8, 16, 25, 33...), or the rounding
    # tints them: (20, 20, 20) comes out (16, 20, 16), visibly green.
    ("rubber", (25, 25, 25)),
    ("cap", (16, 16, 16)),
    ("core", (154, 123, 79)),       # #9A7B4F cardboard
    ("core_in", (124, 98, 62)),     # inside of the tube, a shade darker
    ("yellow", (242, 210, 27)),     # #F2D21B
    ("ink", (8, 8, 8)),
]
YELLOW = (242, 210, 27)
INK = (8, 8, 8)
RING = (216, 186, 22)              # the faint darker wound layers
FACE_ROWS = (64, 96)               # U across the tape: 0 = one edge, 1 = the other
FACE_INK = [(8, 16), (112, 120)]   # px; 4-aligned so no DXT1 block holds three colours
SIDE_ROWS = (96, 128)              # U along the radius: 0 = core, 1 = outer rim
SIDE_RINGS = [(28, 32), (64, 68), (100, 104)]


# -- texture ----------------------------------------------------------------------------------------
def palette_rgb():
    img = np.zeros((TEX, TEX, 3), np.float32)
    img[:, :] = YELLOW
    for i, (_, rgb) in enumerate(COLOURS):
        y, x = (i // 8) * CELL, (i % 8) * CELL
        img[y:y + CELL, x:x + CELL] = rgb
    f0, f1 = FACE_ROWS
    img[f0:f1, :] = YELLOW
    for a, b in FACE_INK:
        img[f0:f1, a:b] = INK
    s0, s1 = SIDE_ROWS
    img[s0:s1, :] = YELLOW
    for a, b in SIDE_RINGS:
        img[s0:s1, a:b] = RING
    return img


def bc1(rgb):
    """DXT1-compress uint8 (h, w, 3). Lifted from sd-minis build_textures.py."""
    h, w, _ = rgb.shape
    b = rgb.reshape(h // 4, 4, w // 4, 4, 3).transpose(0, 2, 1, 3, 4).reshape(-1, 16, 3).astype(np.float32)
    mean = b.mean(axis=1, keepdims=True)
    d = b - mean
    cov = np.einsum('nij,nik->njk', d, d)
    axis = np.tile(np.array([0.299, 0.587, 0.114], np.float32), (b.shape[0], 1))
    for _ in range(5):
        axis = np.einsum('njk,nk->nj', cov, axis)
        axis /= np.maximum(np.linalg.norm(axis, axis=1, keepdims=True), 1e-6)
    t = np.einsum('nij,nj->ni', d, axis)
    lo = mean[:, 0, :] + axis * t.min(axis=1, keepdims=True)
    hi = mean[:, 0, :] + axis * t.max(axis=1, keepdims=True)

    def to565(c):
        c = np.clip(c, 0, 255)
        return ((np.round(c[:, 0] * 31 / 255).astype(np.uint16) << 11)
                | (np.round(c[:, 1] * 63 / 255).astype(np.uint16) << 5)
                | np.round(c[:, 2] * 31 / 255).astype(np.uint16))

    def from565(c):
        return np.stack([((c >> 11) & 31) * (255.0 / 31), ((c >> 5) & 63) * (255.0 / 63),
                         (c & 31) * (255.0 / 31)], axis=1).astype(np.float32)

    a, z = to565(hi), to565(lo)
    c0, c1 = np.maximum(a, z), np.minimum(a, z)
    p0, p1 = from565(c0), from565(c1)
    pal = np.stack([p0, p1, (2 * p0 + p1) / 3, (p0 + 2 * p1) / 3], axis=1)
    idx = ((b[:, :, None, :] - pal[:, None, :, :]) ** 2).sum(axis=3).argmin(axis=2).astype(np.uint32)
    idx[c0 == c1] = 0
    bits = (idx << (2 * np.arange(16, dtype=np.uint32))).sum(axis=1).astype(np.uint32)
    out = np.zeros(b.shape[0], dtype=[('c0', '<u2'), ('c1', '<u2'), ('i', '<u4')])
    out['c0'], out['c1'], out['i'] = c0, c1, bits
    return out.tobytes()


def mip_chain(a):
    chain = [a]
    while chain[-1].shape[0] > 1 or chain[-1].shape[1] > 1:
        m = chain[-1]
        m = (m[0::2, 0::2] + m[1::2, 0::2] + m[0::2, 1::2] + m[1::2, 1::2]) * 0.25
        chain.append(m)
    return chain


def write_dds(path):
    """The atlas as a DXT1 .dds with a full mip chain. Sollumz only embeds a texture whose
    data is DDS: an embedded PNG is skipped at export with a warning and the model ships
    untextured."""
    body = b""
    for m in mip_chain(palette_rgb()):
        u8 = np.clip(m + 0.5, 0, 255).astype(np.uint8)
        if u8.shape[0] < 4:
            u8 = np.tile(u8, (4 // u8.shape[0], 4 // u8.shape[1], 1))
        body += bc1(u8)
    flags = 0x1 | 0x2 | 0x4 | 0x1000 | 0x20000 | 0x80000
    mips = int(math.log2(TEX)) + 1
    hdr = b"DDS " + struct.pack("<7I", 124, flags, TEX, TEX, (TEX // 4) ** 2 * 8, 0, mips) + b"\x00" * 44
    hdr += struct.pack("<2I4s5I", 32, 0x4, b"DXT1", 0, 0, 0, 0, 0)
    hdr += struct.pack("<5I", 0x1000 | 0x8 | 0x400000, 0, 0, 0, 0)
    with open(path, "wb") as f:
        f.write(hdr + body)
    return path


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


# UVs. Blender's V runs bottom-up; Sollumz flips it on export, so V = 1 - row / TEX.
def cell(name):
    i = [n for n, _ in COLOURS].index(name)
    u = ((i % 8) * CELL + CELL / 2) / TEX
    v = 1.0 - ((i // 8) * CELL + CELL / 2) / TEX
    return lambda r, z: (u, v)


def tape_face():
    v = 1.0 - (FACE_ROWS[0] + FACE_ROWS[1]) / 2 / TEX
    return lambda r, z: ((z + TAPE_W / 2) / TAPE_W, v)


def tape_side():
    v = 1.0 - (SIDE_ROWS[0] + SIDE_ROWS[1]) / 2 / TEX
    return lambda r, z: ((r - CORE_R) / (ROLL_R - CORE_R), v)


# -- geometry ---------------------------------------------------------------------------------------
def lathe(bm, uv, prof, paints, segs, closed=False):
    """Revolves `prof` [(r, z), ...] about +Z. paints[i] colours the band between prof[i] and
    prof[i + 1]: a function (r, z) -> (u, v). A point with r == 0 is one vertex (a fan).
    Walk the profile so the solid is on the left of the direction of travel in the (r, z)
    plane (outwards along the bottom, up the side, inwards across the top) and every face
    winds counter-clockwise seen from outside."""
    rings = []
    for r, z in prof:
        if r < 1e-9:
            rings.append([bm.verts.new((0.0, 0.0, z))] * segs)
        else:
            rings.append([bm.verts.new((r * math.cos(2 * math.pi * j / segs),
                                        r * math.sin(2 * math.pi * j / segs), z))
                          for j in range(segs)])
    n = len(prof)
    for i in range(n if closed else n - 1):
        i2 = (i + 1) % n
        a, b = rings[i], rings[i2]
        ua, ub = paints[i](*prof[i]), paints[i](*prof[i2])
        for j in range(segs):
            k = (j + 1) % segs
            corners = [(a[j], ua), (a[k], ua), (b[k], ub), (b[j], ub)]
            out = []
            for vert, t in corners:
                if not out or out[-1][0] is not vert:
                    out.append((vert, t))
            if out[0][0] is out[-1][0]:
                out.pop()
            face = bm.faces.new([vt for vt, _ in out])
            for loop, (_, t) in zip(face.loops, out):
                loop[uv].uv = t


def build_post(bm, uv):
    rub, ora, ref, cap = cell("rubber"), cell("orange"), cell("reflect"), cell("cap")

    # The base: underside, wall, a rounded top edge falling onto a gently domed top, the collar.
    prof = [(0.0, 0.0), (BASE_R, 0.0), (BASE_R, 0.024)]
    edge_r, edge_h = 0.017, BASE_H - 0.024       # quarter-ellipse rounding on the top edge
    for deg in (30, 60):
        a = math.radians(deg)
        prof.append((BASE_R - edge_r + edge_r * math.cos(a), 0.024 + edge_h * math.sin(a) * 0.95))
    prof += [(BASE_R - edge_r, BASE_H - 0.0008),  # the top falls 0.8 mm to its edge
             (COLLAR_R, BASE_H),
             (COLLAR_R, COLLAR_TOP - 0.0035), (COLLAR_R - 0.0035, COLLAR_TOP), (0.0, COLLAR_TOP)]
    lathe(bm, uv, prof, [rub] * (len(prof) - 1), SEGS_BASE)

    # The pole, its two bands, and the cap with its groove, as one surface.
    z = [BAND_Z[0] - BAND_H / 2, BAND_Z[0] + BAND_H / 2, BAND_Z[1] - BAND_H / 2, BAND_Z[1] + BAND_H / 2]
    n0, n1 = TIE_Z - NECK_H / 2, TIE_Z + NECK_H / 2
    rc = CAP_R - CAP_ROUND
    prof = [(POLE_R, POLE_FOOT),
            (POLE_R, z[0]), (BAND_R, z[0]), (BAND_R, z[1]), (POLE_R, z[1]),
            (POLE_R, z[2]), (BAND_R, z[2]), (BAND_R, z[3]), (POLE_R, z[3]),
            (POLE_R, POLE_TOP), (CAP_R, POLE_TOP),
            (CAP_R, n0), (NECK_R, n0), (NECK_R, n1), (CAP_R, n1),
            (CAP_R, CAP_TOP - CAP_ROUND)]
    for deg in (30, 60, 90):
        a = math.radians(deg)
        prof.append((rc + CAP_ROUND * math.cos(a), CAP_TOP - CAP_ROUND + CAP_ROUND * math.sin(a)))
    prof.append((0.0, CAP_TOP))
    paints = [ora, ref, ref, ref, ora, ref, ref, ref, ora] + [cap] * (len(prof) - 10)
    lathe(bm, uv, prof, paints, SEGS_POLE)


def build_roll(bm, uv):
    """Built round +Z (z = across the tape), then turned so the roll's axis is X."""
    hc, ht = CORE_W / 2, TAPE_W / 2
    core, core_in, face, side = cell("core"), cell("core_in"), tape_face(), tape_side()
    prof = [(HOLE_R, hc), (HOLE_R, -hc),            # inside of the tube, walked -z
            (CORE_R, -hc),                          # tube rim
            (CORE_R, -ht),                          # the sliver of tube outside the tape
            (ROLL_R, -ht),                          # flat side of the wound tape
            (ROLL_R, ht),                           # outer face
            (CORE_R, ht),                           # other flat side
            (CORE_R, hc)]                           # sliver; the closing band is the other rim
    paints = [core_in, core, core, side, face, side, core, core]
    lathe(bm, uv, prof, paints, SEGS_ROLL, closed=True)
    bmesh.ops.rotate(bm, verts=bm.verts[:], cent=(0, 0, 0), matrix=Matrix.Rotation(math.radians(90), 3, 'Y'))


# -- Sollumz ----------------------------------------------------------------------------------------
def sz(path):
    import importlib
    return importlib.import_module(SZ + "." + path)


def make_object(name, builder, coll, image):
    bm = bmesh.new()
    uv = bm.loops.layers.uv.new("UVMap 0")    # Sollumz binds the shader's UV node by this NAME
    builder(bm, uv)
    bmesh.ops.remove_doubles(bm, verts=bm.verts[:], dist=1e-6)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    # default.sps multiplies by a vertex colour; without these a surface can render black.
    for attr in ("Color 0", "Color 1"):
        layer = me.color_attributes.new(name=attr, type='BYTE_COLOR', domain='CORNER')
        for d in layer.data:
            d.color = (1.0, 1.0, 1.0, 1.0)

    mat = bpy.data.materials.new(name + "_mat")
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = next(n for n in nt.nodes if n.type == 'BSDF_PRINCIPLED')
    tex = nt.nodes.new('ShaderNodeTexImage')
    tex.image = image
    tex.interpolation = 'Closest'
    nt.links.new(tex.outputs['Color'], bsdf.inputs['Base Color'])
    me.materials.append(mat)

    ob = bpy.data.objects.new(name, me)
    coll.objects.link(ob)
    bpy.ops.object.select_all(action='DESELECT')
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.shade_auto_smooth(angle=math.radians(35))
    for mod in list(ob.modifiers):          # 4.1+ may do this with a modifier; bake it in
        bpy.ops.object.modifier_apply(modifier=mod.name)

    bpy.ops.sollumz.autoconvertmaterials()
    smat = ob.data.materials[0]
    for node in smat.node_tree.nodes:
        if node.type == 'TEX_IMAGE':
            node.image = image                  # the packed DDS
            node.interpolation = 'Closest'
    bpy.ops.sollumz.setallembedded()
    names = [a.name for a in me.color_attributes]
    uvs = [u.name for u in me.uv_layers]
    if "Color 1" not in names or "UVMap 0" not in uvs:
        raise RuntimeError("%s: attributes renamed by Sollumz: %s %s" % (name, names, uvs))
    return ob


def as_drawable(ob):
    bpy.context.scene.auto_create_embedded_col = False
    bpy.ops.object.select_all(action='DESELECT')
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    name = ob.name
    bpy.ops.sollumz.converttodrawable()
    drawable = bpy.data.objects[name]
    model = bpy.data.objects[name + ".model"]
    return drawable, model


def add_post_collision(drawable, coll):
    """A bound composite of two cylinders, base and pole, so peds bump into the post. Sollumz
    cylinders run along the bound's local Y, so each is turned 90 degrees about X."""
    SollumType = sz("sollumz_properties").SollumType
    cm = sz("ybn.collision_materials")
    create_cylinder = sz("tools.meshhelper").create_cylinder
    apply_flag_preset = sz("tools.boundhelper").apply_flag_preset
    mat_index = {m.name: i for i, m in enumerate(cm.collisionmats)}

    comp = bpy.data.objects.new(drawable.name + ".col", None)
    comp.empty_display_size = 0
    comp.sollum_type = SollumType.BOUND_COMPOSITE
    coll.objects.link(comp)
    comp.parent = drawable
    parts = [("base", BASE_R, 0.0, BASE_H, "RUBBER"),
             ("pole", CAP_R, BASE_H, CAP_TOP, "PLASTIC")]
    for part, radius, z0, z1, material in parts:
        me = bpy.data.meshes.new(drawable.name + ".col." + part)
        create_cylinder(me, radius=radius, length=z1 - z0, axis="Y")
        ob = bpy.data.objects.new(me.name, me)
        ob.sollum_type = SollumType.BOUND_CYLINDER
        coll.objects.link(ob)
        ob.parent = comp
        ob.rotation_euler = (math.radians(90), 0.0, 0.0)
        ob.location = (0.0, 0.0, (z0 + z1) / 2)
        apply_flag_preset(ob, 0)             # "General (Default)"
        col_mat = cm.create_collision_material_from_index(mat_index[material])
        col_mat.name = "sd_tape_col_" + material.lower()   # only the collision index is exported
        me.materials.append(col_mat)
    return comp


def export_drawable(drawable, name, stream, report):
    drawable.name = name                     # becomes the .ydr name AND the model name
    model = next(c for c in drawable.children if c.sollum_type == "sollumz_drawable_model")
    model.name = name + ".model"
    bpy.ops.object.select_all(action='DESELECT')
    for ob in [drawable] + list(drawable.children_recursive):
        ob.select_set(True)
    bpy.context.view_layer.objects.active = drawable
    # Omitting target_versions writes gen8/ and gen9/ subfolders instead of a .ydr.
    bpy.ops.sollumz.export_assets(
        directory=stream, target_formats={'NATIVE'}, target_versions={'GEN8'},
        limit_to_selected=True, apply_transforms=True, direct_export=True,
        use_custom_settings=True)
    # The archetype. Without it the .ydr streams but CreateObject cannot resolve the name.
    bpy.ops.object.select_all(action='DESELECT')
    drawable.select_set(True)
    bpy.context.view_layer.objects.active = drawable
    bpy.ops.sollumz.createarchetypefromselected()
    report["files"][name + ".ydr"] = file_facts(os.path.join(stream, name + ".ydr"))


def file_facts(path):
    ok = os.path.isfile(path)
    return {"exists": ok, "size": os.path.getsize(path) if ok else 0,
            "magic": open(path, "rb").read(4).decode("latin1") if ok else None}


def mesh_facts(ob):
    me = ob.data
    xs = [v.co for v in me.vertices]
    lo = [round(min(c[i] for c in xs), 4) for i in range(3)]
    hi = [round(max(c[i] for c in xs), 4) for i in range(3)]
    return {"triangles": sum(len(p.vertices) - 2 for p in me.polygons), "min": lo, "max": hi}


# -- driver -----------------------------------------------------------------------------------------
def export(report, stream, suffix, ytyp_name):
    os.makedirs(stream, exist_ok=True)
    sc = bpy.context.scene
    coll = sc.collection
    image = palette_image()
    report["texture"] = {"name": TEX_NAME, "size": TEX, "format": "DXT1"}
    report["files"] = {}

    while len(sc.ytyps):
        bpy.ops.sollumz.deleteytyp()
    bpy.ops.sollumz.createytyp()
    ytyp = sc.ytyps[sc.ytyp_index]
    ytyp.name = ytyp_name

    post = make_object(POST + suffix, build_post, coll, image)
    report[POST] = mesh_facts(post)
    report[POST].update({"tie_z": TIE_Z, "neck_r": NECK_R, "neck_z": [TIE_Z - NECK_H / 2, TIE_Z + NECK_H / 2],
                         "pole_r": POLE_R, "band_r": BAND_R, "cap_r": CAP_R, "base_r": BASE_R,
                         "height": CAP_TOP})
    drawable, _ = as_drawable(post)
    add_post_collision(drawable, coll)
    export_drawable(drawable, POST + suffix, stream, report)

    roll = make_object(ROLL + suffix, build_roll, coll, image)
    report[ROLL] = mesh_facts(roll)
    report[ROLL].update({"outer_r": ROLL_R, "hole_r": HOLE_R, "tape_w": TAPE_W, "core_w": CORE_W, "axis": "X"})
    drawable, _ = as_drawable(roll)
    export_drawable(drawable, ROLL + suffix, stream, report)

    report["archetypes"] = {}
    for a in ytyp.archetypes:
        a.lod_dist = LOD_DIST
        report["archetypes"][a.name] = {"txd": a.texture_dictionary, "physics": a.physics_dictionary,
                                        "lod": a.lod_dist, "type": a.asset_type}
    bpy.ops.sollumz.export_ytyp_io(directory=stream, target_formats={'NATIVE'},
                                   target_versions={'GEN8'}, use_custom_settings=True)
    report["files"][ytyp_name + ".ytyp"] = file_facts(os.path.join(stream, ytyp_name + ".ytyp"))


_state = {}


def tidy():
    """Removes the build scene and everything made for it, and puts the old scene back."""
    window = bpy.context.window_manager.windows[0]
    prev = _state.pop("scene", None)
    if prev and prev in bpy.data.scenes:
        window.scene = bpy.data.scenes[prev]
    sc = bpy.data.scenes.get(SCENE)
    if sc is not None:
        obs = list(sc.collection.all_objects)
        if window.scene == sc:
            window.scene = next(s for s in bpy.data.scenes if s != sc)
        bpy.data.scenes.remove(sc)
        for ob in obs:
            if ob.name in bpy.data.objects:
                bpy.data.objects.remove(ob, do_unlink=True)
    for block in (bpy.data.meshes, bpy.data.materials, bpy.data.images):
        for item in [i for i in block if i.users == 0 and i.name.startswith("sd_")]:
            block.remove(item)


def main(stream=None, suffix="", ytyp=None, keep=False, log_path=None):
    """Build and export both props. Returns a report (dimensions, triangles, files)."""
    report = {"ok": False}
    try:
        tidy()
        window = bpy.context.window_manager.windows[0]
        _state["scene"] = window.scene.name
        window.scene = bpy.data.scenes.new(SCENE)
        area = next(a for a in window.screen.areas if a.type == 'VIEW_3D')
        region = next(r for r in area.regions if r.type == 'WINDOW')
        with bpy.context.temp_override(window=window, screen=window.screen, area=area,
                                       region=region, space_data=area.spaces.active):
            export(report, stream or STREAM, suffix, ytyp or YTYP)
        report["ok"] = all(f["exists"] and (n.endswith(".ytyp") or f["magic"] == "RSC7")
                           for n, f in report["files"].items())
    except Exception:
        report["error"] = traceback.format_exc()
    finally:
        if not keep:
            tidy()
    if log_path:
        with open(log_path, "w") as f:
            json.dump(report, f, indent=1, default=str)
    return report


if __name__ == "__main__":
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    main(log_path=argv[0] if argv else None)
    bpy.ops.wm.quit_blender()
