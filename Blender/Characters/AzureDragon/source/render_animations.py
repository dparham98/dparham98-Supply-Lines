"""Render Cycles inspection sheets and hero shots for the Azure Dragon Walk and FireBreath animations.

Run headless:
  "C:/Program Files/Blender Foundation/Blender 4.5/blender.exe" -b --factory-startup "Blender/Characters/AzureDragon/source/Azure_Dragon.blend" --python-exit-code 1 -P "Blender/Characters/AzureDragon/source/render_animations.py"
"""

import argparse
from pathlib import Path
import sys
import tempfile

import bpy
from mathutils import Vector
import numpy as np


BASE = Path(__file__).resolve().parents[1]


def add_light(scene, name, pos, aim, watts, size, color):
    data = bpy.data.lights.new(name, "AREA")
    data.energy = watts
    data.shape = "DISK"
    data.size = size
    data.color = color
    ob = bpy.data.objects.new(name, data)
    scene.collection.objects.link(ob)
    ob.location = pos
    ob.rotation_euler = (Vector(aim) - ob.location).to_track_quat("-Z", "Y").to_euler()
    return ob


def setup_studio(dark_fire=False, samples=18):
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.samples = samples
    sc.cycles.use_denoising = True
    sc.cycles.seed = 17
    try:
        sc.view_settings.view_transform = "AgX"
        sc.view_settings.look = "AgX - Medium High Contrast"
    except Exception:
        pass
    sc.view_settings.exposure = -0.10 if not dark_fire else -0.25
    sc.render.film_transparent = False

    world = sc.world or bpy.data.worlds.new("Anim_Studio_World")
    world.use_nodes = True
    sky = next(n for n in world.node_tree.nodes if n.type == "BACKGROUND")
    if dark_fire:
        sky.inputs[0].default_value = (0.14, 0.16, 0.22, 1.0)
        sky.inputs[1].default_value = 0.25
    else:
        sky.inputs[0].default_value = (0.58, 0.64, 0.74, 1.0)
        sky.inputs[1].default_value = 0.45
    sc.world = world

    floor = bpy.data.objects.get("Studio_Floor_Plane")
    if floor is None:
        bpy.ops.mesh.primitive_plane_add(size=200, location=(0, 0, -0.002))
        floor = bpy.context.object
        floor.name = "Studio_Floor_Plane"
        mat = bpy.data.materials.new("Anim_Studio_Canvas")
        mat.use_nodes = True
        floor.data.materials.append(mat)
    else:
        mat = floor.data.materials[0]

    bsdf = next(n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    bsdf.inputs["Roughness"].default_value = 0.88 if dark_fire else 0.96
    if dark_fire:
        bsdf.inputs["Base Color"].default_value = (0.095, 0.088, 0.082, 1.0)
        bsdf.inputs["Emission Color"].default_value = (0.0, 0.0, 0.0, 1.0)
        bsdf.inputs["Emission Strength"].default_value = 0.0
    else:
        bsdf.inputs["Base Color"].default_value = (0.29, 0.255, 0.215, 1.0)
        bsdf.inputs["Emission Color"].default_value = (0.41, 0.355, 0.285, 1.0)
        bsdf.inputs["Emission Strength"].default_value = 0.20

    for name in ("Key_Softbox", "Fill_Softbox", "Rim_Strip"):
        old = bpy.data.objects.get(name)
        if old:
            bpy.data.objects.remove(old, do_unlink=True)

    mult = 0.55 if dark_fire else 1.0
    add_light(sc, "Key_Softbox", (-5.2, -5.8, 7.6), (0, -1.5, 1.3), 1850 * mult, 5.5, (1.0, 0.92, 0.80))
    add_light(sc, "Fill_Softbox", (4.8, -5.2, 4.4), (0, -1.5, 1.3), 920 * mult, 4.8, (0.78, 0.88, 1.0))
    add_light(sc, "Rim_Strip", (1.8, 5.2, 5.5), (0, -1.5, 1.5), 1100 * mult, 4.5, (1.0, 0.91, 0.78))

    cam = bpy.data.objects.get("Anim_Studio_Camera")
    if cam is None:
        cam = bpy.data.objects.new("Anim_Studio_Camera", bpy.data.cameras.new("Anim_Studio_Lens"))
        sc.collection.objects.link(cam)
    cam.data.type = "ORTHO"
    sc.camera = cam
    return sc, cam


def activate_clip(rig, clip_name):
    light_obj = bpy.data.objects.get("Breath_Light")
    anims = [rig.animation_data]
    if light_obj and light_obj.data and light_obj.data.animation_data:
        anims.append(light_obj.data.animation_data)
    for ad in anims:
        if ad is None:
            continue
        ad.action = None
        ad.use_nla = True
        for track in ad.nla_tracks:
            track.is_solo = False
            track.mute = track.name != clip_name
            for strip in track.strips:
                strip.extrapolation = "NOTHING"
    rig.data.pose_position = "POSE"


def render_frame(sc, cam, out_path, frame, direction, aim, ortho_scale, size):
    sc.frame_set(int(frame), subframe=frame % 1)
    bpy.context.view_layer.update()
    target = Vector(aim)
    cam.location = target + Vector(direction).normalized() * 18.0
    cam.rotation_euler = (target - cam.location).to_track_quat("-Z", "Y").to_euler()
    cam.data.ortho_scale = ortho_scale
    sc.render.resolution_x, sc.render.resolution_y = size
    sc.render.resolution_percentage = 100
    sc.render.filepath = str(out_path.resolve())
    sc.render.image_settings.file_format = "PNG"
    sc.render.image_settings.color_mode = "RGB"
    bpy.ops.render.render(write_still=True)


def assemble_grid(tile_paths, out_path, rows=2, cols=3, pad=8):
    tiles = []
    for p in tile_paths:
        img = bpy.data.images.load(str(p))
        w, h = img.size
        arr = np.asarray(img.pixels[:], dtype=np.float32).reshape((h, w, 4))
        tiles.append(arr)
        bpy.data.images.remove(img)

    h, w, _ = tiles[0].shape
    out_w = cols * w + (cols + 1) * pad
    out_h = rows * h + (rows + 1) * pad
    canvas = np.full((out_h, out_w, 4), (0.12, 0.12, 0.13, 1.0), dtype=np.float32)

    # Note: Blender image pixel buffer is bottom-to-top
    for idx, tile in enumerate(tiles):
        r = idx // cols
        c = idx % cols
        y0 = out_h - (r + 1) * (h + pad)
        x0 = pad + c * (w + pad)
        canvas[y0:y0 + h, x0:x0 + w] = tile

    out_img = bpy.data.images.new(out_path.stem, width=out_w, height=out_h, alpha=False)
    out_img.pixels.foreach_set(canvas.ravel())
    out_img.filepath_raw = str(out_path.resolve())
    out_img.file_format = "PNG"
    out_img.save()
    bpy.data.images.remove(out_img)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, default=BASE / "preview")
    parser.add_argument("--draft", action="store_true")
    opts = parser.parse_args(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else [])
    opts.output.mkdir(parents=True, exist_ok=True)

    rig = bpy.data.objects["Azure_Dragon_Rig"]
    samples = 10 if opts.draft else 20

    with tempfile.TemporaryDirectory() as tmp:
        tmp_dir = Path(tmp)

        # 1. Six evenly spaced samples from the current movement clip.
        sc, cam = setup_studio(dark_fire=False, samples=samples)
        activate_clip(rig, "Walk")
        walk_tiles = []
        walk = rig.animation_data.nla_tracks['Walk'].strips[0]
        sys.path.insert(0, str(Path(__file__).resolve().parent))
        from render_studio import subject_frame
        frames = [walk.frame_start + (walk.frame_end - walk.frame_start) * idx / 6 for idx in range(6)]
        direction = (-0.94, -0.40, 0.10)
        tile_size = (640, 620)
        target, scale = subject_frame(sc, direction, (0.0, 0.05, 1.38), tile_size, frames)
        for idx, f in enumerate(frames):
            tp = tmp_dir / f"walk_{idx}.png"
            render_frame(sc, cam, tp, f, direction, target, scale, tile_size)
            walk_tiles.append(tp)
        assemble_grid(walk_tiles, opts.output / "walk_sheet.png", rows=2, cols=3)

        # 2. FireBreath Contact Sheet (frames 12, 20, 28, 34, 45, 62)
        sc, cam = setup_studio(dark_fire=True, samples=samples)
        activate_clip(rig, "FireBreath")
        fb_tiles = []
        fire_frames = [12, 20, 28, 34, 45, 62]
        direction = (-0.82, -0.68, 0.26)
        target, scale = subject_frame(sc, direction, (0.0, -3.55, 1.45), (700, 540), fire_frames, True)
        for idx, f in enumerate(fire_frames):
            tp = tmp_dir / f"fb_{idx}.png"
            render_frame(sc, cam, tp, f, direction, target, scale, (700, 540))
            fb_tiles.append(tp)
        assemble_grid(fb_tiles, opts.output / "fire_breath_sheet.png", rows=2, cols=3)

        # 3. FireBreath Peak Hero 3/4 Shot (frame 30)
        direction = (-0.84, -0.64, 0.24)
        target, scale = subject_frame(sc, direction, (0.0, -3.5, 1.4), (1400, 1000), [30], True)
        render_frame(sc, cam, opts.output / "fire_breath_hero.png", 30, direction, target, scale, (1400, 1000))

        # 4. FireBreath Elevated 50-deg RTS Gameplay Camera Shot (frame 30)
        direction = (0.42, -0.68, 0.96)
        target, scale = subject_frame(sc, direction, (0.0, -3.5, 1.4), (1280, 900), [30], True)
        render_frame(sc, cam, opts.output / "fire_breath_top.png", 30, direction, target, scale, (1280, 900))
