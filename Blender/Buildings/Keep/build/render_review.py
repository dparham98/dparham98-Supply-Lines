"""Cycles verification renders for Keep.blend. Nothing is saved back to Keep.blend.

Run in headless Blender 4.5:
  blender Keep.blend --background --python render_review.py
  blender Keep.blend --background --python render_review.py -- <out_dir> [targets...]

Default targets render into Blender/Previews/Keep/:
  - turnaround.png          (front34, front, side, top, back34, rts 50-deg)
  - concept_comparison.png  (current concept beside the game-facing model)
  - clip_build.png          (frames 0, 72, 144, 240)
  - clip_train.png          (frames 0, 48, 72, 120)
  - clip_launch.png         (frames 0, 24, 48, 96)
  - clip_die.png            (frames 0, 24, 60, 126 with keep_death_fx enabled)
"""

from __future__ import annotations

import math
import os
import sys
from math import radians

import bpy
import numpy as np
from mathutils import Vector as V

HERE = os.path.dirname(os.path.abspath(__file__))
args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT = os.path.abspath(args[0]) if args and not args[0].startswith(("turnaround", "compare", "clip:")) else os.path.abspath(
    os.path.join(HERE, "..", "..", "..", "Previews", "Keep")
)
want = args[1:] if (args and not args[0].startswith(("turnaround", "compare", "clip:"))) else (
    args if args else [
        "turnaround",
        "compare",
        "clip:Build:0,72,144,240",
        "clip:Train:0,48,72,120",
        "clip:LaunchBalloon:0,24,48,96",
        "clip:Die:0,24,60,126",
    ]
)
os.makedirs(OUT, exist_ok=True)
CONCEPT = os.path.abspath(os.path.join(HERE, "..", "..", "..", "References", "ArthurianCivilian", "Keep_timber_and_iron_concept.png"))

scene = bpy.context.scene
scene.render.engine = "CYCLES"
scene.cycles.device = "CPU"
scene.cycles.samples = 28
scene.cycles.use_denoising = True
scene.cycles.seed = 7
scene.view_settings.view_transform = "AgX"
scene.view_settings.look = "AgX - Medium High Contrast"
scene.render.image_settings.file_format = "PNG"
scene.render.image_settings.color_mode = "RGB"
scene.render.film_transparent = False

BG = (0.14, 0.16, 0.19)
world = scene.world or bpy.data.worlds.new("StudioWorld")
scene.world = world
world.use_nodes = True
bg_node = next(n for n in world.node_tree.nodes if n.type == "BACKGROUND")
bg_node.inputs[0].default_value = (0.46, 0.56, 0.74, 1.0)
bg_node.inputs[1].default_value = 0.28

lc = bpy.context.view_layer.layer_collection.children
if "keep_death_fx" in lc:
    lc["keep_death_fx"].exclude = True

for m in bpy.data.materials:
    m.use_backface_culling = True

# Add matte neutral studio floor so groundedness and Die sinking read accurately
floor_mat = bpy.data.materials.new("KeepStudioFloor")
floor_mat.use_nodes = True
fbsdf = next(n for n in floor_mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
fbsdf.inputs["Base Color"].default_value = (*BG, 1.0)
fbsdf.inputs["Roughness"].default_value = 0.90

bpy.ops.mesh.primitive_plane_add(size=80.0, location=(0.0, 0.0, -0.002))
floor_ob = bpy.context.active_object
floor_ob.name = "_review_floor"
floor_ob.data.materials.append(floor_mat)


def add_sun(name: str, rot_deg: tuple[float, float, float], energy: float, col=(1.0, 1.0, 1.0)) -> None:
    d = bpy.data.lights.new(name, "SUN")
    d.energy = energy
    d.color = col
    d.angle = radians(6.0)
    o = bpy.data.objects.new(name, d)
    o.rotation_euler = [radians(a) for a in rot_deg]
    scene.collection.objects.link(o)


add_sun("KeySun", (50.0, 0.0, -42.0), 2.8, (1.0, 0.94, 0.84))
add_sun("FillSun", (62.0, 0.0, 138.0), 0.9, (0.78, 0.88, 1.0))
add_sun("RimSun", (68.0, 0.0, 215.0), 0.7, (1.0, 0.90, 0.72))

cam_d = bpy.data.cameras.new("review_cam")
cam = bpy.data.objects.new("review_cam", cam_d)
scene.collection.objects.link(cam)
scene.camera = cam
CENTRE = V((0.0, 0.0, 3.1))


def aim(pos: tuple[float, float, float], target: tuple[float, float, float] | V) -> None:
    cam.location = pos
    cam.rotation_euler = (V(target) - V(pos)).to_track_quat("-Z", "Y").to_euler()


def set_camera(name: str, res: tuple[int, int]) -> None:
    asp = res[0] / max(1, res[1])
    cam_d.type = "ORTHO"
    if name == "front":
        cam_d.ortho_scale = 11.8 * asp / 1.333
        aim((0.0, -24.0, 3.7), (0.0, 0.0, 3.7))
    elif name == "side":  # -X receiving bay side
        cam_d.ortho_scale = 11.8 * asp / 1.333
        aim((-24.0, 0.0, 3.7), (0.0, 0.0, 3.7))
    elif name == "side_opposite":
        cam_d.ortho_scale = 11.8 * asp / 1.333
        aim((24.0, 0.0, 3.7), (0.0, 0.0, 3.7))
    elif name == "back":
        cam_d.ortho_scale = 11.8 * asp / 1.333
        aim((0.0, 24.0, 3.7), (0.0, 0.0, 3.7))
    elif name == "top":
        cam_d.ortho_scale = 10.6 * asp
        cam.location = (0.0, 0.0, 24.0)
        cam.rotation_euler = (0.0, 0.0, 0.0)
    elif name == "front34":
        cam_d.type = "PERSP"
        cam_d.lens = 50.0
        aim((-14.2, -16.5, 11.2), CENTRE)
    elif name == "back34":
        cam_d.type = "PERSP"
        cam_d.lens = 50.0
        aim((14.2, 16.0, 10.8), CENTRE)
    elif name == "rts":  # ~50-deg RTS camera matching game view looking at front gatehouse
        cam_d.ortho_scale = 15.2
        aim((0.0, -22.0, 26.2), (0.0, -0.2, 2.5))
    elif name == "side_bay_close":
        cam_d.type = "PERSP"
        cam_d.lens = 48.0
        aim((-10.5, -5.0, 4.2), (-3.8, 0.0, 1.8))


def load_arr(path: str) -> np.ndarray:
    img = bpy.data.images.load(path)
    w_, h_ = img.size
    a = np.array(img.pixels[:], dtype=np.float32).reshape(h_, w_, 4)[::-1]
    bpy.data.images.remove(img)
    return a


def save_arr(arr: np.ndarray, path: str) -> None:
    h_, w_, _ = arr.shape
    img = bpy.data.images.new("out", w_, h_, alpha=False)
    img.pixels = arr[::-1].reshape(-1).tolist()
    img.filepath_raw = path
    img.file_format = "PNG"
    img.save()
    bpy.data.images.remove(img)


def fit_tile(a: np.ndarray, w_: int, h_: int, bg) -> np.ndarray:
    sh, sw = a.shape[:2]
    s = min(w_ / sw, h_ / sh)
    nw, nh = max(1, int(sw * s)), max(1, int(sh * s))
    ys = (np.arange(nh) / s).astype(int).clip(0, sh - 1)
    xs = (np.arange(nw) / s).astype(int).clip(0, sw - 1)
    resized = a[ys][:, xs]
    out = np.empty((h_, w_, 4), np.float32)
    out[:] = bg
    y0, x0 = (h_ - nh) // 2, (w_ - nw) // 2
    out[y0:y0 + nh, x0:x0 + nw] = resized
    return out


def render_view(name: str, res: tuple[int, int], tag: str = "") -> np.ndarray:
    set_camera(name, res)
    scene.render.resolution_x, scene.render.resolution_y = res
    tmp = os.path.join(OUT, f"_tmp_{name}{tag}.png")
    scene.render.filepath = tmp
    bpy.ops.render.render(write_still=True)
    arr = load_arr(tmp)
    os.remove(tmp)
    return arr


def play_clip(action_name: str, frame: int) -> None:
    for ob in bpy.data.objects:
        ad = ob.animation_data
        if not ad:
            continue
        ad.action = None
        for t in ad.nla_tracks:
            t.mute = not any(s.name in (action_name, "Death" if action_name == "Die" else "") for s in t.strips)
    scene.frame_set(frame)
    bpy.context.view_layer.update()


def unmute_rest() -> None:
    if "keep_death_fx" in lc:
        lc["keep_death_fx"].exclude = True
    for ob in bpy.data.objects:
        ad = ob.animation_data
        if not ad:
            continue
        ad.action = None
        for t in ad.nla_tracks:
            t.mute = False
    scene.frame_set(0)
    bpy.context.view_layer.update()


sRGB_BG = [pow(c, 1.0 / 2.2) for c in BG] + [1.0]
STATIC_CACHE: dict[str, np.ndarray] = {}

for item in want:
    if item == "turnaround":
        unmute_rest()
        views = ["front34", "front", "side", "top", "back34", "rts"]
        tiles = []
        for vn in views:
            arr = render_view(vn, (560, 420))
            STATIC_CACHE[vn] = arr
            tiles.append(arr)
        sheet = np.concatenate([np.concatenate(tiles[:3], axis=1), np.concatenate(tiles[3:], axis=1)], axis=0)
        save_arr(sheet, os.path.join(OUT, "turnaround.png"))
        print("RENDERED", os.path.join(OUT, "turnaround.png"))

    elif item == "compare":
        unmute_rest()
        con = load_arr(CONCEPT)
        reference = fit_tile(con, 840, 560, con[3, 3])
        actual = render_view("front34", (840, 560))
        sheet = np.concatenate([reference, actual], axis=1)
        save_arr(sheet, os.path.join(OUT, "concept_comparison.png"))
        print("RENDERED", os.path.join(OUT, "concept_comparison.png"))

    elif item.startswith("clip:"):
        _, act, frames_csv = item.split(":")
        scene.cycles.samples = 22
        if "keep_death_fx" in lc:
            lc["keep_death_fx"].exclude = (act != "Die")
        frames = [int(f) for f in frames_csv.split(",")]
        tiles = []
        cam_name = "rts" if act == "LaunchBalloon" else "front34"
        for f in frames:
            play_clip(act, f)
            tiles.append(render_view(cam_name, (500, 380), f"_{act}_{f}"))
        while len(tiles) % 4:
            tiles.append(np.full_like(tiles[0], sRGB_BG))
        rows = [np.concatenate(tiles[i:i + 2], axis=1) for i in range(0, len(tiles), 2)]
        sheet = np.concatenate(rows, axis=0)
        clip_slug = "launch" if act == "LaunchBalloon" else act.lower()
        out_path = os.path.join(OUT, f"clip_{clip_slug}.png")
        save_arr(sheet, out_path)
        print("RENDERED", out_path)
