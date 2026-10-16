"""
build_holder_icons.py -- the pictures in the holder menu: the delineator post and the twenty
cones, rendered from the same geometry their streamed models are built from (build_props.py,
build_cones.py), so a picture never drifts from the model. Writes ../images/holders/<id>.png,
256 x 256, transparent, with a soft contact shadow.

Needs only Blender (no Sollumz, no window):

    blender -b --factory-startup --python build_holder_icons.py [-- <id> <id> ...]

With ids after --, only those are rendered.
"""
import math
import os
import runpy
import sys

import bmesh
import bpy
import numpy as np
from bpy_extras.object_utils import world_to_camera_view
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.normpath(os.path.join(HERE, "..", "images", "holders"))
CONES = runpy.run_path(os.path.join(HERE, "build_cones.py"))
PROPS = CONES["B"]

SIZE = 256
SAMPLES = 256
CAM_YAW = 28.0          # degrees round from straight on: a square base shows two sides
CAM_ELEV = 16.0
COVERAGE = 0.8          # of the frame, so the shadow has room


def palette(module, name):
    """The model's palette atlas as a Blender image, uncompressed (the game gets it as DXT1)."""
    rgb = module["palette_rgb"]()                      # rows from the top, 0..255 sRGB
    tex = rgb.shape[0]
    img = bpy.data.images.new(name, tex, tex, alpha=False)
    px = np.ones((tex, tex, 4), np.float32)
    px[:, :, :3] = np.flipud(rgb) / 255.0             # Blender's rows run bottom-up
    img.pixels.foreach_set(px.ravel())
    return img


def make(name, builder, image, rough):
    bm = bmesh.new()
    uv = bm.loops.layers.uv.new("UVMap")
    builder(bm, uv)
    bmesh.ops.remove_doubles(bm, verts=bm.verts[:], dist=1e-6)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    for p in me.polygons:
        p.use_smooth = True
    me.set_sharp_from_angle(angle=math.radians(35))    # as the export does

    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = image
    tex.interpolation = "Closest"                      # the palette is flat blocks
    nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = rough
    me.materials.append(mat)

    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    return ob


def holders():
    """(id, builder, palette module) for the post and every cone, in configs/holders.lua order."""
    out = [("post", PROPS["build_post"], PROPS)]
    cell = CONES["cell"]
    for cid, _label, size, body, collar, base, bands in CONES["CONES"]:
        s = CONES["SIZES"][size]
        bands = s["bands"] if bands is None else bands
        out.append((cid, CONES["builder"](s, bands, cell(body), cell(collar or body), cell(base),
                                          cell(body + "_in")), CONES))
    return out


# -- scene ------------------------------------------------------------------------------------------
def look_at(ob, target):
    ob.rotation_euler = (target - ob.location).to_track_quat("-Z", "Y").to_euler()


def view_dir():
    yaw, el = math.radians(CAM_YAW), math.radians(CAM_ELEV)
    return Vector((math.sin(yaw) * math.cos(el), -math.cos(yaw) * math.cos(el), math.sin(el)))


def fit_camera(cam, points, target):
    scene = bpy.context.scene
    d = view_dir()
    dist = 3.0
    half = math.tan(cam.data.angle / 2)
    for _ in range(6):
        cam.location = target + d * dist
        look_at(cam, target)
        bpy.context.view_layer.update()
        ndc = [world_to_camera_view(scene, cam, p) for p in points]
        xs, ys = [p.x for p in ndc], [p.y for p in ndc]
        cx, cy = (min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2
        ext = max(max(xs) - min(xs), max(ys) - min(ys))
        m = cam.matrix_world.to_3x3()
        target = target + m @ Vector(((cx - 0.5) * 2 * half * dist, (cy - 0.5) * 2 * half * dist, 0))
        dist *= ext / COVERAGE
    cam.location = target + d * dist
    look_at(cam, target)
    return target


def area_light(name, target, az, el, dist, size, power):
    """A soft box `az` degrees round from the camera (positive: to its right), `el` up."""
    yaw = math.radians(CAM_YAW + az)
    e = math.radians(el)
    d = Vector((math.sin(yaw) * math.cos(e), -math.cos(yaw) * math.cos(e), math.sin(e)))
    li = bpy.data.lights.new(name, "AREA")
    li.shape, li.size, li.energy = "DISK", size, power
    ob = bpy.data.objects.new(name, li)
    bpy.context.scene.collection.objects.link(ob)
    ob.location = target + d * dist
    look_at(ob, target)
    ob.visible_camera = False
    return ob


def setup():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    prefs = bpy.context.preferences.addons["cycles"].preferences
    try:
        prefs.compute_device_type = "OPTIX"
        prefs.get_devices()
        for dv in prefs.devices:
            dv.use = dv.type == "OPTIX"
        scene.cycles.device = "GPU"
    except Exception:
        scene.cycles.device = "CPU"
    scene.cycles.samples = SAMPLES
    scene.cycles.use_denoising = True
    scene.render.film_transparent = True
    scene.render.resolution_x = scene.render.resolution_y = SIZE
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.view_settings.view_transform = "Standard"
    scene.view_settings.exposure = -1.2

    world = bpy.data.worlds.new("world")
    scene.world = world
    world.use_nodes = True
    bg = world.node_tree.nodes["Background"]
    bg.inputs["Color"].default_value = (0.86, 0.88, 0.92, 1)
    bg.inputs["Strength"].default_value = 0.22

    bpy.ops.mesh.primitive_plane_add(size=20)
    bpy.context.active_object.is_shadow_catcher = True

    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    scene.collection.objects.link(cam)
    scene.camera = cam
    cam.data.lens = 70
    return scene, cam


def render_one(scene, cam, hid, builder, module, image):
    ob = make(hid, builder, image, 0.42)
    pts = [ob.matrix_world @ v.co for v in ob.data.vertices]
    lo = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
    hi = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
    target = fit_camera(cam, pts, (lo + hi) / 2)
    h = hi.z - lo.z
    # Lights scale with the holder, power with the square of their distance, so a 30 cm cone and
    # a 1 m post come out lit the same.
    lights = [
        area_light("key", target, -40, 55, 2.2 * h, 1.2 * h, 40 * (2.2 * h) ** 2),
        area_light("fill", target, 75, 25, 2.4 * h, 1.6 * h, 10 * (2.4 * h) ** 2),
        area_light("rim", target, 160, 40, 2.0 * h, 0.8 * h, 28 * (2.0 * h) ** 2),
    ]
    os.makedirs(OUT, exist_ok=True)
    scene.render.filepath = os.path.join(OUT, hid + ".png")
    bpy.ops.render.render(write_still=True)
    print("ICON", hid, scene.render.filepath)
    for o in [ob] + lights:
        bpy.data.objects.remove(o, do_unlink=True)


def main(only):
    scene, cam = setup()
    images = {id(PROPS): palette(PROPS, "post_pal"), id(CONES): palette(CONES, "cones_pal")}
    done = 0
    for hid, builder, module in holders():
        if only and hid not in only:
            continue
        render_one(scene, cam, hid, builder, module, images[id(module)])
        done += 1
    print("ICONS DONE", done, "->", OUT)


if __name__ == "__main__":
    main(set(sys.argv[sys.argv.index("--") + 1:]) if "--" in sys.argv else set())
