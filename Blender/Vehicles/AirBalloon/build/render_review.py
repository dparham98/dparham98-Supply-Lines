"""Cycles verification renders for AirBalloon.blend. Nothing is saved back to AirBalloon.blend.

Run in headless Blender 4.5:
  blender AirBalloon.blend --background --python render_review.py
"""

from __future__ import annotations

import os
from math import radians

import bpy
import numpy as np
from mathutils import Vector as V

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.abspath(os.path.join(HERE, "..", "..", "..", "Previews", "AirBalloon"))
os.makedirs(OUT, exist_ok=True)

want = [
    "turnaround",
    "clip:Run:0,9,18,27",
    "clip:Die:0,10,24,42",
]

scene = bpy.context.scene
scene.render.engine = "CYCLES"
scene.cycles.device = "CPU"
scene.cycles.samples = 24
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
if "air_balloon_death_fx" in lc:
    lc["air_balloon_death_fx"].exclude = True

for m in bpy.data.materials:
    m.use_backface_culling = True

floor_mat = bpy.data.materials.new("AbStudioFloor")
floor_mat.use_nodes = True
fbsdf = next(n for n in floor_mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
fbsdf.inputs["Base Color"].default_value = (*BG, 1.0)
fbsdf.inputs["Roughness"].default_value = 0.90

bpy.ops.mesh.primitive_plane_add(size=50.0, location=(0.0, 0.0, -0.002))
floor_ob = bpy.context.active_object
floor_ob.name = "_review_floor"
floor_ob.data.materials.append(floor_mat)


def add_sun(name: str, rot_deg, energy: float, col=(1.0, 1.0, 1.0)) -> None:
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
CENTRE = V((0.0, 0.1, 2.75))


def aim(pos, target) -> None:
    cam.location = pos
    cam.rotation_euler = (V(target) - V(pos)).to_track_quat("-Z", "Y").to_euler()


def set_camera(name: str, res: tuple[int, int]) -> None:
    asp = res[0] / max(1, res[1])
    cam_d.type = "ORTHO"
    if name == "front":
        cam_d.ortho_scale = 7.4 * asp / 1.333
        aim((0.0, -15.0, 2.8), (0.0, 0.0, 2.8))
    elif name == "side":
        cam_d.ortho_scale = 7.6 * asp / 1.333
        aim((-15.0, 0.2, 2.85), (0.0, 0.2, 2.85))
    elif name == "top":
        cam_d.ortho_scale = 5.4 * asp
        cam.location = (0.0, 0.2, 15.0)
        cam.rotation_euler = (0.0, 0.0, 0.0)
    elif name == "front34":
        cam_d.type = "PERSP"
        cam_d.lens = 50.0
        aim((-8.5, -10.0, 6.2), CENTRE)
    elif name == "back34":
        cam_d.type = "PERSP"
        cam_d.lens = 50.0
        aim((8.2, 9.8, 5.8), CENTRE)
    elif name == "rts":
        cam_d.ortho_scale = 8.4
        aim((0.0, -12.0, 14.4), (0.0, 0.1, 2.2))


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
    if "air_balloon_death_fx" in lc:
        lc["air_balloon_death_fx"].exclude = True
    for ob in bpy.data.objects:
        ad = ob.animation_data
        if not ad:
            continue
        ad.action = None
        for t in ad.nla_tracks:
            t.mute = False
    scene.frame_set(0)
    bpy.context.view_layer.update()


for item in want:
    if item == "turnaround":
        unmute_rest()
        views = ["front34", "front", "side", "top", "back34", "rts"]
        tiles = [render_view(vn, (520, 400)) for vn in views]
        sheet = np.concatenate([np.concatenate(tiles[:3], axis=1), np.concatenate(tiles[3:], axis=1)], axis=0)
        save_arr(sheet, os.path.join(OUT, "turnaround.png"))
        print("RENDERED", os.path.join(OUT, "turnaround.png"))
    elif item.startswith("clip:"):
        _, act, frames_csv = item.split(":")
        scene.cycles.samples = 18
        if "air_balloon_death_fx" in lc:
            lc["air_balloon_death_fx"].exclude = (act != "Die")
        frames = [int(f) for f in frames_csv.split(",")]
        tiles = []
        cam_name = "side" if act == "Run" else "front34"
        for f in frames:
            play_clip(act, f)
            tiles.append(render_view(cam_name, (480, 360), f"_{act}_{f}"))
        rows = [np.concatenate(tiles[i:i + 2], axis=1) for i in range(0, len(tiles), 2)]
        sheet = np.concatenate(rows, axis=0)
        out_path = os.path.join(OUT, f"clip_{act.lower()}.png")
        save_arr(sheet, out_path)
        print("RENDERED", out_path)
