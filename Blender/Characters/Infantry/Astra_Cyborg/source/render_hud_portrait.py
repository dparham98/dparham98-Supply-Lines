"""Render a close-up selection portrait directly from the playable Cyborg GLB."""
import argparse
import sys
from pathlib import Path

import bpy
import imbuf
from mathutils import Vector


PROJECT = Path(__file__).resolve().parents[5]
PANEL_SIZE = (360, 204)


def area(scene, name, position, target, width, height, watts, color):
    light = bpy.data.lights.new(name, "AREA")
    light.shape = "RECTANGLE"
    light.size, light.size_y = width, height
    light.energy, light.color = watts, color
    lamp = bpy.data.objects.new(name, light)
    scene.collection.objects.link(lamp)
    lamp.location = position
    lamp.rotation_euler = (Vector(target) - lamp.location).to_track_quat("-Z", "Y").to_euler()


def stage(scene, aim, direction, height):
    camera = bpy.data.objects.new("Selection portrait", bpy.data.cameras.new("Orthographic lens"))
    scene.collection.objects.link(camera)
    scene.camera = camera
    camera.location = aim + direction * 4
    camera.rotation_euler = (-direction).to_track_quat("-Z", "Y").to_euler()
    camera.data.type = "ORTHO"
    # Leave the full helmet and cheek plates within the central 172 x 204
    # pixels used by the 1280-wide HUD. Extra width reveals the shoulders.
    camera.data.ortho_scale = height * PANEL_SIZE[0] / PANEL_SIZE[1]

    world = bpy.data.worlds.new("Soft ambient")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (.3, .35, .44, 1)
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = .15
    scene.world = world
    face = (0, -.09, 1.56)
    area(scene, "Warm cheek key", (-1.22, -1.7, 2.81), face, .86, 1.58, 112, (1, .87, .73))
    area(scene, "Soft eye fill", (1.28, -1.64, 1.9), face, 1.50, 1.75, 57, (.74, .83, 1))
    area(scene, "Helmet rim", (1.09, .62, 2.69), face, .50, 1.22, 90, (.96, .88, .71))
    area(scene, "Temple edge", (-1.25, .50, 1.82), face, .29, 1.4, 63, (.60, .78, 1))
    area(scene, "Eye catchlight", (.02, -1.66, 1.65), face, .46, .76, 9, (1, .89, .73))

    bpy.ops.mesh.primitive_plane_add(size=1.75, location=aim - direction * 1.2)
    wall = bpy.context.object
    wall.rotation_euler = camera.rotation_euler
    material = bpy.data.materials.new("Warm graphite backdrop")
    material.use_nodes = True
    wall.data.materials.append(material)
    nodes, links = material.node_tree.nodes, material.node_tree.links
    uv = nodes.new("ShaderNodeTexCoord")
    distance = nodes.new("ShaderNodeVectorMath")
    distance.operation = "DISTANCE"
    distance.inputs[1].default_value = (.47, .55, 0)
    links.new(uv.outputs["UV"], distance.inputs[0])
    ramp = nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].color = (.143, .119, .093, 1)
    ramp.color_ramp.elements[1].position = .345
    ramp.color_ramp.elements[1].color = (.018, .021, .025, 1)
    links.new(distance.outputs["Value"], ramp.inputs[0])
    screen = nodes.new("ShaderNodeEmission")
    links.new(ramp.outputs[0], screen.inputs["Color"])
    links.new(screen.outputs[0], nodes["Material Output"].inputs["Surface"])


def render(model, output, draft, unit="infantry"):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(model.resolve()))
    scene = bpy.context.scene
    if unit == "motorcycle":
        # The rider is in the riding pose on the real bike. Isolate it for the
        # portrait so the rear turret cannot cross the silhouette of the helmet.
        for obj in scene.objects:
            if obj.animation_data:
                obj.animation_data_clear()
            if obj.type == "MESH" and not obj.name.startswith("rider_"):
                obj.hide_render = True
        scene.frame_set(0)
        aim, angle, height = (.063,-.216,1.526), (-.56,-1,.11), .454
    else:
        rig = next(obj for obj in scene.objects if obj.type == "ARMATURE")
        rig.animation_data.use_nla = False
        rig.animation_data.action = bpy.data.actions["Rest"]
        scene.frame_set(1)
        aim, angle, height = (0,-.025,1.566), (-.47,-1,.052), .515
    for obj in scene.objects:
        if obj.type == "LIGHT" or obj.name == "Muzzle flash":
            obj.hide_render = True
    stage(scene, Vector(aim), Vector(angle).normalized(), height)
    scene.render.engine = "CYCLES"
    scene.cycles.samples = 12 if draft else 80
    scene.cycles.use_denoising = True
    scene.cycles.seed = 23
    scene.view_settings.view_transform = "AgX"
    scene.view_settings.look = "AgX - Medium High Contrast"
    scene.view_settings.exposure = -.48
    scene.render.resolution_x, scene.render.resolution_y = (n * 4 for n in PANEL_SIZE)
    scene.render.resolution_percentage = 50 if draft else 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGB"
    source = output / "source" / (unit + "_model.png")
    source.parent.mkdir(parents=True, exist_ok=True)
    scene.render.filepath = str(source)
    bpy.ops.render.render(write_still=True)

    image = imbuf.load(str(source))
    image.resize(tuple(n * 2 for n in PANEL_SIZE), method="BILINEAR")
    imbuf.write(image, filepath=str(output / (unit + ".png")))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--unit", choices=("infantry","motorcycle"), default="infantry")
    parser.add_argument("--model", type=Path)
    parser.add_argument("--output", type=Path, default=PROJECT / "assets/ui/portraits")
    parser.add_argument("--draft", action="store_true")
    options = parser.parse_args(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else [])
    render(options.model or PROJECT / "assets/models/units" / (options.unit + ".glb"),
           options.output.resolve(), options.draft, options.unit)
