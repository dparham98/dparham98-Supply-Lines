"""Photograph the editable train using a temporary studio. Run against a .blend in background mode."""
import argparse
from pathlib import Path
import sys

import bpy
from bpy_extras.object_utils import world_to_camera_view
from mathutils import Vector


def studio_light(scene, target, name, offset, size, size_y, power, rgb):
    data = bpy.data.lights.new(name, "AREA")
    data.shape = "RECTANGLE"
    data.size, data.size_y = size, size_y
    data.energy, data.color = power, rgb
    obj = bpy.data.objects.new(name, data)
    scene.collection.objects.link(obj)
    obj.location = target + Vector(offset)
    obj.rotation_euler = (target - obj.location).to_track_quat("-Z", "Y").to_euler()


def render_source(output, scale):
    scene = bpy.context.scene
    root = bpy.data.objects["train_cargo_root"]
    objects = {root, *root.children_recursive}
    for obj in scene.objects:
        obj.hide_render = obj not in objects
    depsgraph = bpy.context.evaluated_depsgraph_get()
    vertices = []
    for obj in objects:
        if obj.type == "MESH":
            evaluated = obj.evaluated_get(depsgraph)
            vertices.extend(evaluated.matrix_world @ v.co for v in evaluated.data.vertices)
    low = Vector([min(v[i] for v in vertices) for i in range(3)])
    high = Vector([max(v[i] for v in vertices) for i in range(3)])
    target = (low + high) / 2

    # A broad, matte sweep gives the raw metal a neutral surround and a soft contact shadow.
    bpy.ops.mesh.primitive_plane_add(size=200, location=(target.x, target.y, root.matrix_world.translation.z))
    floor = bpy.context.object
    floor.name = "Temporary studio sweep"
    matte = bpy.data.materials.new("Temporary neutral sweep")
    matte.use_nodes = True
    shader = matte.node_tree.nodes.get("Principled BSDF")
    shader.inputs["Base Color"].default_value = (0.32, 0.335, 0.35, 1)
    shader.inputs["Roughness"].default_value = 0.88
    floor.data.materials.append(matte)
    world = bpy.data.worlds.new("Temporary studio surround")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.57, 0.65, 0.74, 1)
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.22
    scene.world = world
    studio_light(scene, target, "Broad key", (5, -5, 10), 6, 10, 1200, (1.0, 0.94, 0.87))
    studio_light(scene, target, "Rear strip", (-5, 4, 7), 2, 10, 1650, (0.82, 0.91, 1.0))
    studio_light(scene, target, "Nose card", (-3, -8, 4.5), 5, 5, 360, (0.96, 0.98, 1.0))
    studio_light(scene, target, "Lower fill", (8, 4, 3), 7, 5, 260, (1.0, 0.96, 0.90))
    camera = bpy.data.cameras.new("Studio inspection camera")
    camera_obj = bpy.data.objects.new(camera.name, camera)
    scene.collection.objects.link(camera_obj)
    scene.camera = camera_obj
    camera_obj.location = target + Vector((16, -11.5, 8.0))
    camera_obj.rotation_euler = (target-camera_obj.location).to_track_quat("-Z","Y").to_euler()
    camera.lens = 65
    scene.render.resolution_x, scene.render.resolution_y = 1680, 960
    scene.render.resolution_percentage = scale
    scene.render.pixel_aspect_x = scene.render.pixel_aspect_y = 1
    bpy.context.view_layer.update()
    coords = [world_to_camera_view(scene, camera_obj, v) for v in vertices]
    minx, maxx = min(v.x for v in coords), max(v.x for v in coords)
    miny, maxy = min(v.y for v in coords), max(v.y for v in coords)
    factor = min(0.88/(maxx-minx), 0.80/(maxy-miny))
    camera.lens *= factor
    camera.shift_x = factor * ((minx+maxx)/2 - 0.5)
    camera.shift_y = (factor * ((miny+maxy)/2 - 0.5) - 0.02) * 960/1680
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 40
    scene.cycles.use_denoising = True
    scene.cycles.adaptive_threshold = 0.04
    scene.cycles.seed = 7
    scene.view_settings.view_transform = "AgX"
    scene.view_settings.look = "AgX - Medium High Contrast"
    scene.view_settings.exposure = -0.46
    scene.render.film_transparent = False
    scene.render.use_border = False
    scene.use_nodes = False
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGB"
    output.parent.mkdir(parents=True, exist_ok=True)
    scene.render.filepath = str(output.resolve())
    bpy.ops.render.render(write_still=True)
    print(f"{bpy.app.version_string} source studio render: {output}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path,
        default=Path(__file__).resolve().parents[1]/"preview/blender_studio.png")
    parser.add_argument("--scale", type=int, default=100)
    render_args = sys.argv[sys.argv.index("--")+1:] if "--" in sys.argv else []
    args = parser.parse_args(render_args)
    render_source(args.output, args.scale)
