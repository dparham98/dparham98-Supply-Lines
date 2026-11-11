"""Review renders for Motorcycle.blend. Nothing is saved back to the .blend.

  blender Motorcycle.blend --background --python render_review.py -- <out_dir> [views...]

Views: any of the names in VIEWS, "turnaround" (the six-up sheet) or "compare" (against the concept).
"""
import bpy, sys, os, math
import numpy as np
from mathutils import Vector as V

HERE = os.path.dirname(os.path.abspath(__file__))
args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT = args[0] if args else os.path.join(HERE, "..", "..", "Previews", "Motorcycle")
want = args[1:] or ["turnaround", "compare"]
OUT = os.path.abspath(OUT)
os.makedirs(OUT, exist_ok=True)
CONCEPT = os.path.join(HERE, "..", "..", "References", "Motorcycle_concept.webp")

scene = bpy.context.scene
scene.render.engine = 'BLENDER_EEVEE_NEXT'
scene.view_settings.view_transform = 'Standard'
scene.view_settings.look = 'None'
scene.render.image_settings.file_format = 'PNG'
scene.render.film_transparent = False
BG = (0.52, 0.49, 0.45)
w = scene.world or bpy.data.worlds.new("World")
scene.world = w
w.use_nodes = True
bgn = next(n for n in w.node_tree.nodes if n.type == 'BACKGROUND')
bgn.inputs[0].default_value = (*BG, 1)
bgn.inputs[1].default_value = 1.0
try:
    scene.eevee.use_raytracing = False
    scene.eevee.taa_render_samples = 32
except Exception:
    pass

# the spike is reviewed on its own
lc = bpy.context.view_layer.layer_collection.children
if "motorcycle_projectile" in lc:
    lc["motorcycle_projectile"].exclude = "spike" not in want
if want == ["spike"]:
    lc["motorcycle"].exclude = True


def light(name, kind, rot, energy, col=(1, 1, 1)):
    d = bpy.data.lights.new(name, kind)
    d.energy = energy
    d.color = col
    o = bpy.data.objects.new(name, d)
    o.rotation_euler = [math.radians(a) for a in rot]
    scene.collection.objects.link(o)
    return o


for m in bpy.data.materials:
    m.use_backface_culling = True      # as Godot draws it, so a flipped face shows as a hole
light("key", 'SUN', (48, 0, -40), 3.2, (1.0, 0.97, 0.92))
light("fill", 'SUN', (60, 0, 140), 1.2, (0.85, 0.9, 1.0))
light("rim", 'SUN', (70, 0, 215), 0.9)

cam_d = bpy.data.cameras.new("review_cam")
cam = bpy.data.objects.new("review_cam", cam_d)
scene.collection.objects.link(cam)
scene.camera = cam
CENTRE = V((0, 0, 0.9))


def aim(pos, target):
    cam.location = pos
    cam.rotation_euler = (V(target) - V(pos)).to_track_quat('-Z', 'Y').to_euler()


def view(name, res):
    cam_d.type = 'PERSP'
    cam_d.lens = 70
    if name == "side":          # the bike's left, as the sheet's SIDE view
        cam_d.type = 'ORTHO'; cam_d.ortho_scale = 3.3; aim((8, 0, 0.95), (0, 0, 0.95))
    elif name == "right":
        cam_d.type = 'ORTHO'; cam_d.ortho_scale = 3.3; aim((-8, 0, 0.95), (0, 0, 0.95))
    elif name == "front":
        cam_d.type = 'ORTHO'; cam_d.ortho_scale = 2.4 * max(1.0, res[0] / res[1]); aim((0, -8, 0.95), (0, 0, 0.95))
    elif name == "back":
        cam_d.type = 'ORTHO'; cam_d.ortho_scale = 2.4 * max(1.0, res[0] / res[1]); aim((0, 8, 0.95), (0, 0, 0.95))
    elif name == "top":
        cam_d.type = 'ORTHO'; cam_d.ortho_scale = 3.3
        cam.location = (0, 0, 9); cam.rotation_euler = (0, 0, math.radians(90))
    elif name == "front34":
        aim((4.6, -5.6, 2.6), CENTRE)
    elif name == "back34":
        aim((4.4, 5.8, 2.6), CENTRE)
    elif name == "back34r":
        aim((-4.4, 5.8, 2.6), CENTRE)
    elif name == "rts":         # roughly the game's high camera
        cam_d.lens = 150; aim((6.5, 9.5, 12.5), (0, 0, 0.6))
    elif name == "rider":
        cam_d.lens = 85; aim((1.7, -2.6, 2.0), (0, 0.08, 1.35))
    elif name == "gun":
        cam_d.lens = 85; aim((2.0, 1.7, 2.6), (0, 0.5, 1.72))
    elif name == "engine":
        cam_d.lens = 85; aim((3.0, -0.6, 0.9), (0, 0.0, 0.5))
    elif name == "under":
        cam_d.lens = 60; aim((3.2, -2.4, 0.5), (0, 0, 0.6))
    elif name == "spike":
        cam_d.lens = 85; aim((0.8, -0.75, 0.4), (0, -0.04, 0))
    scene.render.resolution_x, scene.render.resolution_y = res
    path = os.path.join(OUT, "_" + name + ".png")
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    return path


def load(path):
    img = bpy.data.images.load(path)
    w_, h_ = img.size
    a = np.array(img.pixels[:], dtype=np.float32).reshape(h_, w_, 4)[::-1]
    bpy.data.images.remove(img)
    return a


def save(arr, path):
    h_, w_, _ = arr.shape
    img = bpy.data.images.new("out", w_, h_, alpha=False)
    img.pixels = arr[::-1].reshape(-1).tolist()
    img.filepath_raw = path
    img.file_format = 'PNG'
    img.save()
    bpy.data.images.remove(img)


def fit(a, w_, h_, bg):
    """Nearest-neighbour resize to fit inside w_ x h_, centred on bg."""
    sh, sw = a.shape[:2]
    s = min(w_ / sw, h_ / sh)
    nw, nh = int(sw * s), int(sh * s)
    ys = (np.arange(nh) / s).astype(int).clip(0, sh - 1)
    xs = (np.arange(nw) / s).astype(int).clip(0, sw - 1)
    r = a[ys][:, xs]
    out = np.empty((h_, w_, 4), np.float32)
    out[:] = bg
    y0, x0 = (h_ - nh) // 2, (w_ - nw) // 2
    out[y0:y0 + nh, x0:x0 + nw] = r
    return out


sRGB_BG = [c ** (1 / 2.2) for c in BG] + [1]

for name in want:
    if name == "turnaround":
        cells = [("front34", (640, 480)), ("front", (640, 480)), ("side", (640, 480)),
                 ("top", (640, 480)), ("back34", (640, 480)), ("rts", (640, 480))]
        tiles = [load(view(n, r)) for n, r in cells]
        sheet = np.concatenate([np.concatenate(tiles[:3], axis=1), np.concatenate(tiles[3:], axis=1)], axis=0)
        save(sheet, os.path.join(OUT, "turnaround.png"))
        for n, _ in cells:
            os.remove(os.path.join(OUT, "_" + n + ".png"))
    elif name == "compare":
        con = load(CONCEPT)
        side_c = con[185:520, 430:870]
        front_c = con[175:530, 15:195]
        side_r = load(view("side", (1100, 800)))[40:790]
        front_r = load(view("front", (600, 800)))[40:790, 60:540]
        H = 520
        row1 = np.concatenate([fit(side_c, 760, H, side_c[5, 5]), fit(side_r, 760, H, sRGB_BG)], axis=1)
        row2 = np.concatenate([fit(front_c, 760, H, front_c[5, 5]), fit(front_r, 760, H, sRGB_BG)], axis=1)
        save(np.concatenate([row1, row2], axis=0), os.path.join(OUT, "concept_comparison.png"))
        for n in ("side", "front"):
            os.remove(os.path.join(OUT, "_" + n + ".png"))
    elif name == "death":
        lc["motorcycle_death_fx"].exclude = False
        tiles = []
        for f in (5, 11, 18, 26, 44, 72, 100, 112):
            scene.frame_set(f)
            cam_d.type = 'PERSP'; cam_d.lens = 50
            aim((7.5, -9.5, 5.5), (0.2, -2.6, 0.4))
            scene.render.resolution_x, scene.render.resolution_y = 640, 480
            scene.render.filepath = os.path.join(OUT, "_death.png")
            bpy.ops.render.render(write_still=True)
            tiles.append(load(scene.render.filepath))
        save(np.concatenate([np.concatenate(tiles[:4], axis=1), np.concatenate(tiles[4:], axis=1)], axis=0),
             os.path.join(OUT, "death_strip.png"))
        os.remove(os.path.join(OUT, "_death.png"))
        scene.frame_set(0)
        lc["motorcycle_death_fx"].exclude = True
    elif name == "spike":
        p = view(name, (900, 500))
        os.replace(p, os.path.join(OUT, "rail_spike.png"))
    else:
        view(name, (1400, 1000))
print("RENDERED", want)
