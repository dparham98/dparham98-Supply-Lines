"""Review renders for ConstructionSite.blend. Nothing is saved back to the .blend.

  blender ConstructionSite.blend --background --python render_review.py -- <out_dir> [views...]

Views: "sheet" (the five sizes from the front three-quarter view, one tile each), "rts" (the five
sizes from roughly the game's camera), "close" (the 6 x 6 gate, board and props up close) and
"idle" (the 3 x 3 bunting through its Idle clip).
"""
import bpy, sys, os, math
import numpy as np
from mathutils import Vector as V

HERE = os.path.dirname(os.path.abspath(__file__))
args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT = os.path.abspath(args[0] if args else os.path.join(HERE, "..", "..", "..", "Previews", "ConstructionSite"))
want = args[1:] or ["sheet", "rts", "close", "idle"]
os.makedirs(OUT, exist_ok=True)
SIZES = (2, 3, 6, 8, 10)

scene = bpy.context.scene
scene.render.engine = 'BLENDER_EEVEE_NEXT'
scene.view_settings.view_transform = 'Standard'
scene.render.image_settings.file_format = 'PNG'
w = scene.world or bpy.data.worlds.new("World")
scene.world = w
w.use_nodes = True
next(n for n in w.node_tree.nodes if n.type == 'BACKGROUND').inputs[0].default_value = (0.52, 0.49, 0.45, 1)
try:
    scene.eevee.taa_render_samples = 32
except Exception:
    pass
for m in bpy.data.materials:
    m.use_backface_culling = True


def light(name, rot, energy, col=(1, 1, 1)):
    d = bpy.data.lights.new(name, 'SUN')
    d.energy = energy
    d.color = col
    o = bpy.data.objects.new(name, d)
    o.rotation_euler = [math.radians(a) for a in rot]
    scene.collection.objects.link(o)


light("key", (48, 0, -40), 3.2, (1.0, 0.97, 0.92))
light("fill", (60, 0, 140), 1.2, (0.85, 0.9, 1.0))
# A ground plate per site, the size of its footprint, so the fence can be judged against it.
gm = bpy.data.materials.new("review_ground")
gm.diffuse_color = (0.24, 0.22, 0.17, 1)
gm.use_nodes = True
next(n for n in gm.node_tree.nodes if n.type == "BSDF_PRINCIPLED").inputs["Base Color"].default_value = (0.24, 0.22, 0.17, 1)
centres = {}
for size in SIZES:
    root = bpy.data.objects["s%d_root" % size]
    c = V(root.location)
    centres[size] = c
    bpy.ops.mesh.primitive_plane_add(size=1, location=(c.x, c.y, -0.002))
    p = bpy.context.object
    p.scale = (size + 3, size + 3, 1)
    p.data.materials.append(gm)
    bpy.ops.mesh.primitive_plane_add(size=1, location=(c.x, c.y, -0.001))
    q = bpy.context.object
    q.scale = (size, size, 1)
    fm = bpy.data.materials.new("review_foot")
    fm.use_nodes = True
    next(n for n in fm.node_tree.nodes if n.type == "BSDF_PRINCIPLED").inputs["Base Color"].default_value = (0.30, 0.27, 0.20, 1)
    q.data.materials.append(fm)

cam_d = bpy.data.cameras.new("review_cam")
cam = bpy.data.objects.new("review_cam", cam_d)
scene.collection.objects.link(cam)
scene.camera = cam


def aim(pos, target):
    cam.location = pos
    cam.rotation_euler = (V(target) - V(pos)).to_track_quat('-Z', 'Y').to_euler()


def shoot(name, res):
    scene.render.resolution_x, scene.render.resolution_y = res
    path = os.path.join(OUT, "_" + name + ".png")
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    img = bpy.data.images.load(path)
    a = np.array(img.pixels[:]).reshape(res[1], res[0], 4)
    bpy.data.images.remove(img)
    os.remove(path)
    return a


def save(name, a):
    h, w_ = a.shape[:2]
    img = bpy.data.images.new(name, w_, h, alpha=True)
    img.pixels[:] = a.ravel()
    img.filepath_raw = os.path.join(OUT, name + ".png")
    img.file_format = 'PNG'
    img.save()
    print("WROTE", img.filepath_raw)


def tile_row(tiles):
    return np.concatenate(tiles, axis=1)


for v in want:
    cam_d.type = 'PERSP'
    cam_d.lens = 40
    if v == "sheet":
        tiles = []
        for size in SIZES:
            c = centres[size]
            d = size * 0.9 + 2.2
            aim(c + V((-d * 0.75, -d, d * 0.75)), c + V((0, 0, 0.3)))
            tiles.append(shoot("t", (640, 520)))
        save("turnaround", tile_row(tiles))
    elif v == "rts":
        tiles = []
        for size in SIZES:
            c = centres[size]
            cam_d.lens = 120
            d = 10 + size * 2.2
            aim(c + V((0, -d * 0.66, d)), c + V((0, 0, 0.3)))
            tiles.append(shoot("t", (520, 520)))
        save("rts", tile_row(tiles))
    elif v == "close":
        c = centres[6]
        aim(c + V((-1.6, -5.4, 1.5)), c + V((-1.2, -2.6, 0.35)))
        save("gate_close", shoot("t", (1280, 800)))
    elif v == "idle":
        c = centres[3]
        tiles = []
        for f in (0, 18, 36, 54):
            scene.frame_set(f)
            aim(c + V((-1.0, -4.4, 1.1)), c + V((-0.6, -1.5, 0.45)))
            tiles.append(shoot("t", (480, 400)))
        scene.frame_set(0)
        save("clip_idle", tile_row(tiles))
