"""Review renders for LandMine.blend. Nothing is saved back to the .blend.

  blender LandMine.blend --background --python render_review.py -- <out_dir>

Writes states.png (laid / arming / armed / spotted, posed here as land_mine_model.gd poses them in
the game) and blast.png (six frames of Impact).
"""
import bpy, sys, os, math
import numpy as np
from mathutils import Vector as V

HERE = os.path.dirname(os.path.abspath(__file__))
args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT = os.path.abspath(args[0] if args else os.path.join(HERE, "..", "..", "..", "Previews", "LandMine"))
os.makedirs(OUT, exist_ok=True)
scene = bpy.context.scene
try:
    scene.render.engine = 'BLENDER_EEVEE_NEXT'
except TypeError:
    scene.render.engine = 'BLENDER_EEVEE'
scene.view_settings.view_transform = 'Standard'
scene.render.image_settings.file_format = 'PNG'
scene.render.resolution_x = scene.render.resolution_y = 640
w = scene.world or bpy.data.worlds.new("World")
scene.world = w
w.use_nodes = True
next(n for n in w.node_tree.nodes if n.type == 'BACKGROUND').inputs[0].default_value = (0.5, 0.47, 0.42, 1)
for c in bpy.context.view_layer.layer_collection.children:
    c.exclude = False


def light(name, rot, energy, col=(1, 1, 1)):
    d = bpy.data.lights.new(name, 'SUN')
    d.energy = energy
    d.color = col
    o = bpy.data.objects.new(name, d)
    o.rotation_euler = [math.radians(a) for a in rot]
    scene.collection.objects.link(o)


light("key", (48, 0, -40), 3.2, (1.0, 0.97, 0.92))
light("fill", (60, 0, 140), 1.0, (0.85, 0.9, 1.0))
# ground
me = bpy.data.meshes.new("ground")
me.from_pydata([(-8, -8, 0), (8, -8, 0), (8, 8, 0), (-8, 8, 0)], [], [(0, 1, 2, 3)])
g = bpy.data.objects.new("ground", me)
gm = bpy.data.materials.new("ground")
gm.use_nodes = True
next(n for n in gm.node_tree.nodes if n.type == "BSDF_PRINCIPLED").inputs["Base Color"].default_value = (0.2, 0.17, 0.11, 1)
me.materials.append(gm)
scene.collection.objects.link(g)
cam_d = bpy.data.cameras.new("cam")
cam = bpy.data.objects.new("cam", cam_d)
scene.collection.objects.link(cam)
scene.camera = cam
OB = bpy.data.objects
MINE = [o for o in bpy.data.collections["land_mine"].all_objects]
BLAST = [o for o in bpy.data.collections["land_mine_blast"].all_objects]


def aim(pos, target, lens=50):
    cam_d.lens = lens
    cam.location = pos
    cam.rotation_euler = (V(target) - V(pos)).to_track_quat('-Z', 'Y').to_euler()


def shot(path):
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    img = bpy.data.images.load(path)
    a = np.array(img.pixels[:], dtype=np.float32).reshape(img.size[1], img.size[0], 4)
    bpy.data.images.remove(img)
    os.remove(path)
    return a


def sheet(tiles, cols, path):
    rows = [np.concatenate(tiles[i:i + cols], axis=1) for i in range(0, len(tiles), cols)]
    a = np.concatenate(rows[::-1], axis=0)
    img = bpy.data.images.new("sheet", a.shape[1], a.shape[0])
    img.pixels = a.ravel()
    img.filepath_raw = path
    img.file_format = 'PNG'
    img.save()
    print("WROTE", path)


rest = {o.name: o.matrix_basis.copy() for o in MINE}


def pose(arm, settle, spotted, lamp):
    for o in MINE:
        o.matrix_basis = rest[o.name].copy()
    fold = math.radians(88) * (1 - arm)
    for k in range(1, 5):
        p = OB["mine_prong_%d" % k]
        p.rotation_mode = 'XYZ'
        p.rotation_euler.x += fold
    OB["mine_plate"].location.z -= 0.03 * (1 - arm)
    OB["mine_root"].location.z = -0.075 * settle
    OB["mine_soil"].scale = V((1, 1, 1)) * max(0.001, settle)
    OB["mine_spotted"].hide_render = not spotted
    lamp_mat = bpy.data.materials["mine_lamp"]
    next(n for n in lamp_mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED").inputs["Emission Strength"].default_value = lamp


for o in BLAST:
    o.hide_render = True
tiles = []
for arm, settle, spotted, lamp in ((0, 0, False, 1.0), (0.6, 0.5, False, 4.0), (1, 1, False, 0.8), (1, 1, True, 0.8)):
    pose(arm, settle, spotted, lamp)
    aim((1.6, -2.2, 1.5), (0, 0, 0.05), 50)
    tiles.append(shot(os.path.join(OUT, "_t.png")))
sheet(tiles, 4, os.path.join(OUT, "states.png"))

for o in MINE:
    o.hide_render = True
for o in BLAST:
    o.hide_render = False
tiles = []
for f in (1, 3, 6, 10, 18, 30):
    scene.frame_set(f)
    aim((7, -9, 6), (0, 0, 0.8), 35)
    tiles.append(shot(os.path.join(OUT, "_t.png")))
sheet(tiles, 3, os.path.join(OUT, "blast.png"))
