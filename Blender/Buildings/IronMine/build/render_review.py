"""Review renders for IronMine.blend. Nothing is saved back to the .blend.

  blender IronMine.blend --background --python render_review.py -- <out_dir> [views...]

Views: any of the names in view(), "turnaround" (the six-up sheet),
or "clip:<action>:<frame>,<frame>...[:<view>]" (a strip of one clip, by default the front
three-quarter view).
"""
import bpy, sys, os, math
import numpy as np
from mathutils import Vector as V

HERE = os.path.dirname(os.path.abspath(__file__))
args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT = args[0] if args else os.path.join(HERE, "..", "..", "..", "Previews", "IronMine")
want = args[1:] or ["turnaround"]
OUT = os.path.abspath(OUT)
os.makedirs(OUT, exist_ok=True)

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
lc = bpy.context.view_layer.layer_collection.children
if "mine_death_fx" in lc:
    lc["mine_death_fx"].exclude = True


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
CENTRE = V((0, 0, 1.6))


def aim(pos, target):
    cam.location = pos
    cam.rotation_euler = (V(target) - V(pos)).to_track_quat('-Z', 'Y').to_euler()


def view(name, res):
    cam_d.type = 'PERSP'
    cam_d.lens = 50
    asp = max(1.0, res[0] / res[1])
    if name == "front":
        cam_d.type = 'ORTHO'; cam_d.ortho_scale = 5.8 * asp / 1.333; aim((0, -20, 1.95), (0, 0, 1.95))
    elif name == "side":        # the winch side, as the sheet's SIDE view
        cam_d.type = 'ORTHO'; cam_d.ortho_scale = 5.8 * asp / 1.333; aim((-20, 0, 1.95), (0, 0, 1.95))
    elif name == "side_opposite":
        cam_d.type = 'ORTHO'; cam_d.ortho_scale = 5.8 * asp / 1.333; aim((20, 0, 1.95), (0, 0, 1.95))
    elif name == "back":
        cam_d.type = 'ORTHO'; cam_d.ortho_scale = 5.8 * asp / 1.333; aim((0, 20, 1.95), (0, 0, 1.95))
    elif name == "top":
        cam_d.type = 'ORTHO'; cam_d.ortho_scale = 2.4 * asp
        cam.location = (0, 0, 20); cam.rotation_euler = (0, 0, 0)
    elif name == "front34":
        aim((-4.9, -6.0, 4.3), CENTRE)
    elif name == "back34":
        aim((5.0, 5.6, 4.1), CENTRE)
    elif name == "rts":         # roughly the game's camera, which looks at the front
        cam_d.lens = 200; aim((0, -26, 30), (0, 0, 1.4))
    elif name == "winch":       # close on the winch house and drum
        cam_d.lens = 40; aim((-2.2, -3.6, 1.7), (-0.45, -0.15, 0.7))
    elif name == "head":        # the skip, chute and bin, from the front right
        cam_d.lens = 40; aim((3.4, -3.8, 3.3), (0.35, -0.1, 1.7))
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


def play(action_name, frame):
    """Pose every object at one frame of the named clip, from its NLA strip of that name."""
    for o in bpy.data.objects:
        ad = o.animation_data
        if not ad:
            continue
        ad.action = None
        for t in ad.nla_tracks:
            t.mute = not any(s.name in (action_name, "Death" if action_name == "Die" else "") for s in t.strips)
    scene.frame_set(frame)


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
    elif name.startswith("clip:"):
        parts = name.split(":")
        act, frames = parts[1], parts[2]
        cam_view = parts[3] if len(parts) > 3 else "front34"
        if act == "Die" and "mine_death_fx" in lc:
            lc["mine_death_fx"].exclude = False
        tiles = []
        for f in [int(x) for x in frames.split(",")]:
            play(act, f)
            tiles.append(load(view(cam_view, (560, 420))))
        while len(tiles) % 4:
            tiles.append(np.full_like(tiles[0], sRGB_BG))
        rows = [np.concatenate(tiles[i:i + 4], axis=1) for i in range(0, len(tiles), 4)]
        suffix = "" if cam_view == "front34" else "_" + cam_view
        save(np.concatenate(rows, axis=0), os.path.join(OUT, "clip_" + act.lower() + suffix + ".png"))
        os.remove(os.path.join(OUT, "_" + cam_view + ".png"))
    else:
        os.replace(view(name, (1400, 1000)), os.path.join(OUT, name + ".png"))
print("RENDERED", want)
