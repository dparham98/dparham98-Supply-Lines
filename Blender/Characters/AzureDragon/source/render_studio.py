"""Render studio inspection views of the Azure Dragon in Cycles.

Run headless:
  "C:/Program Files/Blender Foundation/Blender 4.5/blender.exe" -b --factory-startup "Blender/Characters/AzureDragon/source/Azure_Dragon.blend" --python-exit-code 1 -P "Blender/Characters/AzureDragon/source/render_studio.py"
"""

import argparse
from pathlib import Path
import sys

import bpy
import numpy as np
from mathutils import Vector


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


def setup_studio(draft=False):
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.samples = 12 if draft else 24
    sc.cycles.use_denoising = True
    sc.cycles.seed = 17
    try:
        sc.view_settings.view_transform = "AgX"
        sc.view_settings.look = "AgX - Medium High Contrast"
    except Exception:
        pass
    sc.view_settings.exposure = -0.10
    sc.render.film_transparent = False

    world = bpy.data.worlds.new("Warm_Studio_World")
    world.use_nodes = True
    sky = next(n for n in world.node_tree.nodes if n.type == "BACKGROUND")
    sky.inputs[0].default_value = (0.58, 0.64, 0.74, 1.0)
    sky.inputs[1].default_value = 0.45
    sc.world = world

    bpy.ops.mesh.primitive_plane_add(size=200, location=(0, 0, -0.002))
    floor = bpy.context.object
    mat = bpy.data.materials.new("Studio_Canvas")
    mat.use_nodes = True
    bsdf = next(n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    bsdf.inputs["Base Color"].default_value = (0.29, 0.255, 0.215, 1.0)
    bsdf.inputs["Roughness"].default_value = 0.96
    bsdf.inputs["Emission Color"].default_value = (0.41, 0.355, 0.285, 1.0)
    path = mat.node_tree.nodes.new("ShaderNodeLightPath")
    cam_glow = mat.node_tree.nodes.new("ShaderNodeMath")
    cam_glow.operation = "MULTIPLY"
    cam_glow.inputs[1].default_value = 0.88
    mat.node_tree.links.new(path.outputs["Is Camera Ray"], cam_glow.inputs[0])
    mat.node_tree.links.new(cam_glow.outputs[0], bsdf.inputs["Emission Strength"])
    floor.data.materials.append(mat)

    add_light(sc, "Key_Softbox", (-4.8, -5.5, 7.2), (0, 0, 1.3), 1850, 5.5, (1.0, 0.92, 0.80))
    add_light(sc, "Fill_Softbox", (4.5, -4.8, 4.2), (0, 0, 1.3), 920, 4.8, (0.78, 0.88, 1.0))
    add_light(sc, "Rim_Strip", (1.8, 5.2, 5.5), (0, 0, 1.5), 1100, 4.5, (1.0, 0.91, 0.78))

    cam = bpy.data.objects.new("Studio_Camera", bpy.data.cameras.new("Studio_Lens"))
    sc.collection.objects.link(cam)
    cam.data.type = "ORTHO"
    sc.camera = cam
    return sc, cam


def subject_frame(sc, direction, aim, size, frames, include_flame=False):
    """Fit all poses into one orthographic frame, keeping scale constant through a clip."""
    rotation = (-Vector(direction)).to_track_quat("-Z", "Y")
    right = np.array(rotation @ Vector((1, 0, 0)))
    up = np.array(rotation @ Vector((0, 1, 0)))
    axes = np.stack((right, up), axis=1)
    lower, upper = np.full(2, np.inf), np.full(2, -np.inf)
    objects = [obj for obj in sc.objects if obj.type == "MESH" and obj.find_armature()
               and (include_flame or not obj.name.startswith("Dragon_Fire_"))]
    for frame in frames:
        sc.frame_set(int(frame), subframe=frame % 1)
        graph = bpy.context.evaluated_depsgraph_get()
        for obj in objects:
            posed = obj.evaluated_get(graph)
            coords = np.empty((len(posed.data.vertices), 3), dtype=np.float32)
            posed.data.vertices.foreach_get("co", coords.ravel())
            matrix = np.asarray(posed.matrix_world)
            projected = (coords @ matrix[:3, :3].T + matrix[:3, 3]) @ axes
            lower = np.minimum(lower, projected.min(axis=0))
            upper = np.maximum(upper, projected.max(axis=0))
    mid = (lower + upper) / 2
    center = np.asarray(aim)
    center = center + axes @ (mid - center @ axes)
    width, height = upper - lower
    aspect = size[0] / size[1]
    scale = max(width * max(1., 1. / aspect), height * max(1., aspect)) * 1.14
    return Vector(center.tolist()), scale


def render_shot(sc, cam, out_path, direction, aim, ortho_scale, size, percent=100):
    if out_path.stem != "azure_dragon_portrait":
        aim, ortho_scale = subject_frame(sc, direction, aim, size, [sc.frame_current])
    target = Vector(aim)
    cam.location = target + Vector(direction).normalized() * 14.0
    cam.rotation_euler = (target - cam.location).to_track_quat("-Z", "Y").to_euler()
    cam.data.ortho_scale = ortho_scale
    sc.render.resolution_x, sc.render.resolution_y = size
    sc.render.resolution_percentage = percent
    sc.render.filepath = str(out_path.resolve())
    sc.render.image_settings.file_format = "PNG"
    sc.render.image_settings.color_mode = "RGB"
    bpy.ops.render.render(write_still=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, default=BASE / "preview")
    parser.add_argument("--draft", action="store_true")
    opts = parser.parse_args(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else [])
    opts.output.mkdir(parents=True, exist_ok=True)
    rig = bpy.data.objects.get("Azure_Dragon_Rig")
    if rig and rig.animation_data:
        for track in rig.animation_data.nla_tracks:
            track.mute = track.name != "Rest"
        bpy.context.scene.frame_set(1)
    sc, cam = setup_studio(opts.draft)
    pct = 60 if opts.draft else 100

    # 1. Hero 3/4 view matching concept art camera angle (viewing right flank & chest, facing viewer's right)
    render_shot(sc, cam, opts.output / "azure_dragon_hero.png", (-0.88, -0.78, 0.14), (0.0, 0.12, 1.44), 4.65, (1100, 1200), pct)
    # 2. Front view
    render_shot(sc, cam, opts.output / "azure_dragon_front.png", (0.0, -1.0, 0.12), (0.0, 0.0, 1.44), 4.85, (1100, 1000), pct)
    # 3. Side profile
    render_shot(sc, cam, opts.output / "azure_dragon_side.png", (-1.0, -0.05, 0.08), (0.0, 0.18, 1.44), 4.75, (1200, 1000), pct)
    # 4. Rear 3/4 view (showing saddle, flank tassets, wings, and tail curve)
    render_shot(sc, cam, opts.output / "azure_dragon_rear.png", (-0.75, 0.85, 0.22), (0.0, 0.20, 1.42), 4.85, (1100, 1100), pct)
    # 5. Head & Peytral Shield Close-up Portrait
    render_shot(sc, cam, opts.output / "azure_dragon_portrait.png", (-0.70, -1.05, 0.26), (0.0, -0.48, 2.03), 2.85, (1000, 1000), pct)
