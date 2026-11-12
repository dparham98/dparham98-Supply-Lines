"""Review renders for MaterialPiles.blend. Nothing is saved back to the .blend.

  blender MaterialPiles.blend --background --python render_review.py -- <out_dir>

Writes "stages.png": iron, wood and coal (rows) with a fifth, half and all of their pieces shown
(columns), from the front three-quarter view, on a 1 m cell plate, and "rts.png": the three full piles
from roughly the game's camera.
"""
import bpy, sys, os, math
import numpy as np
from mathutils import Vector as V

HERE = os.path.dirname(os.path.abspath(__file__))
args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT = os.path.abspath(args[0] if args else os.path.join(HERE, "..", "..", "..", "Previews", "MaterialPiles"))
os.makedirs(OUT, exist_ok=True)
KINDS = ("iron", "wood", "coal")
scene = bpy.context.scene
scene.render.engine = 'BLENDER_EEVEE_NEXT'
scene.view_settings.view_transform = 'Standard'
scene.render.image_settings.file_format = 'PNG'
w = scene.world or bpy.data.worlds.new("World")
scene.world = w
w.use_nodes = True
next(n for n in w.node_tree.nodes if n.type == 'BACKGROUND').inputs[0].default_value = (0.52, 0.49, 0.45, 1)
for m in bpy.data.materials:
    m.use_backface_culling = True
for name, rot, e in (("key", (48, 0, -40), 3.2), ("fill", (60, 0, 140), 1.2)):
    d = bpy.data.lights.new(name, 'SUN'); d.energy = e
    o = bpy.data.objects.new(name, d); o.rotation_euler = [math.radians(a) for a in rot]
    scene.collection.objects.link(o)
gm = bpy.data.materials.new("plate")
gm.use_nodes = True
next(n for n in gm.node_tree.nodes if n.type == "BSDF_PRINCIPLED").inputs["Base Color"].default_value = (0.42, 0.36, 0.24, 1)
for kind in KINDS:
    c = bpy.data.objects[kind + "_root"].location
    bpy.ops.mesh.primitive_plane_add(size=1, location=(c.x, c.y, -0.001))
    bpy.context.object.data.materials.append(gm)
cam_d = bpy.data.cameras.new("cam")
cam = bpy.data.objects.new("cam", cam_d)
scene.collection.objects.link(cam)
scene.camera = cam


def aim(pos, target):
    cam.location = pos
    cam.rotation_euler = (V(target) - V(pos)).to_track_quat('-Z', 'Y').to_euler()


def shoot(res):
    scene.render.resolution_x, scene.render.resolution_y = res
    path = os.path.join(OUT, "_t.png")
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    img = bpy.data.images.load(path)
    a = np.array(img.pixels[:]).reshape(res[1], res[0], 4)
    bpy.data.images.remove(img)
    os.remove(path)
    return a


def save(name, a):
    img = bpy.data.images.new(name, a.shape[1], a.shape[0], alpha=True)
    img.pixels[:] = a.ravel()
    img.filepath_raw = os.path.join(OUT, name + ".png")
    img.file_format = 'PNG'
    img.save()
    print("WROTE", img.filepath_raw)


def show(kind, fraction):
    pieces = sorted((o for o in bpy.data.objects if o.name.startswith(kind + "_piece_")), key=lambda o: o.name)
    shown = max(1, math.ceil(fraction * len(pieces)))
    for k, name in enumerate(o.name for o in pieces):
        bpy.data.objects[name].hide_render = k >= shown


rows = []
for kind in KINDS:
    c = bpy.data.objects[kind + "_root"].location
    tiles = []
    for fraction in (0.2, 0.5, 1.0):
        show(kind, fraction)
        cam_d.lens = 50
        aim(c + V((-1.25, -1.7, 1.2)), c + V((0, 0, 0.2)))
        tiles.append(shoot((420, 340)))
    show(kind, 1.0)
    rows.append(np.concatenate(tiles, axis=1))
save("stages", np.concatenate(rows[::-1], axis=0))
cam_d.lens = 120
centre = bpy.data.objects["wood_root"].location
aim(centre + V((0, -9, 13)), centre + V((0, 0, 0.2)))
save("rts", shoot((900, 420)))
