"""Review renders for the Foundry and Forge files. Nothing is saved back to the .blend.

  blender Foundry.blend --background --python render_review.py -- <out_dir> <collection> [sheets...]

Sheets: "turnaround" (four views and a top view), or a clip name ("Idle", "Research", "Build", "Die"),
which renders eight frames across that clip from the game's three-quarter view. The death effects
collection, if there is one, is shown with Die.
"""
import bpy, sys, os, math
import numpy as np
from mathutils import Vector as V

args = sys.argv[sys.argv.index("--") + 1:]
OUT, COLL = os.path.abspath(args[0]), args[1]
want = args[2:] or ["turnaround"]
os.makedirs(OUT, exist_ok=True)
scene = bpy.context.scene
try:
    scene.render.engine = 'BLENDER_EEVEE_NEXT'
except TypeError:
    scene.render.engine = 'BLENDER_EEVEE'
scene.view_settings.view_transform = 'Standard'
scene.render.image_settings.file_format = 'PNG'
scene.render.resolution_x, scene.render.resolution_y = 720, 600
w = bpy.data.worlds.new("review")
scene.world = w
w.use_nodes = True
next(n for n in w.node_tree.nodes if n.type == 'BACKGROUND').inputs[0].default_value = (0.42, 0.40, 0.37, 1)
FX = COLL + "_death_fx"
for c in bpy.context.view_layer.layer_collection.children:
    c.exclude = c.name not in (COLL, FX)


def light(name, rot, energy, col=(1, 1, 1)):
    d = bpy.data.lights.new(name, 'SUN')
    d.energy = energy
    d.color = col
    o = bpy.data.objects.new(name, d)
    o.rotation_euler = [math.radians(a) for a in rot]
    scene.collection.objects.link(o)


light("key", (48, 0, -35), 3.4, (1.0, 0.96, 0.9))
light("fill", (60, 0, 150), 1.1, (0.85, 0.9, 1.0))
me = bpy.data.meshes.new("ground")
me.from_pydata([(-30, -30, -0.002), (30, -30, -0.002), (30, 30, -0.002), (-30, 30, -0.002)], [], [(0, 1, 2, 3)])
g = bpy.data.objects.new("ground", me)
gm = bpy.data.materials.new("ground")
gm.use_nodes = True
next(n for n in gm.node_tree.nodes if n.type == "BSDF_PRINCIPLED").inputs["Base Color"].default_value = (0.3, 0.25, 0.17, 1)
me.materials.append(gm)
scene.collection.objects.link(g)
cam_d = bpy.data.cameras.new("cam")
cam = bpy.data.objects.new("cam", cam_d)
scene.collection.objects.link(cam)
scene.camera = cam


def aim(pos, target, lens=40, ortho=None):
    cam_d.type = 'ORTHO' if ortho else 'PERSP'
    if ortho:
        cam_d.ortho_scale = ortho
    cam_d.lens = lens
    cam.location = pos
    cam.rotation_euler = (V(target) - V(pos)).to_track_quat('-Z', 'Y').to_euler()


def shot():
    path = os.path.join(OUT, "_t.png")
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    img = bpy.data.images.load(path)
    a = np.array(img.pixels[:], dtype=np.float32).reshape(img.size[1], img.size[0], 4)
    bpy.data.images.remove(img)
    os.remove(path)
    return a


def sheet(tiles, cols, name):
    while len(tiles) % cols:
        tiles.append(np.zeros_like(tiles[0]))
    rows = [np.concatenate(tiles[i:i + cols], axis=1) for i in range(0, len(tiles), cols)]
    a = np.concatenate(rows[::-1], axis=0)
    img = bpy.data.images.new("sheet", a.shape[1], a.shape[0])
    img.pixels = a.ravel()
    img.filepath_raw = os.path.join(OUT, name)
    img.file_format = 'PNG'
    img.save()
    print("WROTE", img.filepath_raw)


def clip_length(clip):
    end = 0
    for ob in bpy.data.objects:
        ad = ob.animation_data
        if ad:
            for tr in ad.nla_tracks:
                on = tr.name == clip or (clip == "Die" and tr.name == "Death")
                tr.mute = not on
                for st in tr.strips:
                    if on:
                        end = max(end, st.frame_end)
    return int(end)


GAME = ((9.0, -11.5, 11.0), (0, 0, 1.2))      # the game's camera: from the door side, high
for name in want:
    if name == "turnaround":
        clip_length("Idle")
        if FX in bpy.data.collections:
            for o in list(bpy.data.collections[FX].objects):
                o.hide_render = True
        scene.frame_set(0)
        tiles = []
        for pos, tgt, lens, ortho in ((GAME[0], GAME[1], 40, None), ((-10, -10, 6), (0, 0, 1.4), 40, None),
                                      ((0, -16, 2.2), (0, 0, 2.2), 40, 7.5), ((10, 10, 6), (0, 0, 1.4), 40, None),
                                      ((0, 0.01, 20), (0, 0, 0), 40, 7.0), ((-9, 11.5, 11), (0, 0, 1.2), 40, None)):
            aim(pos, tgt, lens, ortho)
            tiles.append(shot())
        sheet(tiles, 3, "turnaround.png")
    else:
        end = clip_length(name)
        if FX in bpy.data.collections:
            for o in list(bpy.data.collections[FX].objects):
                o.hide_render = name != "Die"
        tiles = []
        for k in range(8):
            scene.frame_set(round(end * k / 7))
            aim(*GAME)
            tiles.append(shot())
        sheet(tiles, 4, "clip_%s.png" % name.lower())
