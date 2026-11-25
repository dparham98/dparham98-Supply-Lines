"""Render a selection portrait from the playable Grenadier GLB and its Rest pose."""
import argparse
import json
from pathlib import Path
import sys
import bpy
import imbuf
from mathutils import Vector


def light(scene, name, position, target, watts, size, color):
    data = bpy.data.lights.new(name, "AREA")
    data.shape = "RECTANGLE"
    data.size, data.size_y = size
    data.energy = watts
    data.color = color
    obj = bpy.data.objects.new(name, data)
    scene.collection.objects.link(obj)
    obj.location = position
    obj.rotation_euler = (target - obj.location).to_track_quat("-Z", "Y").to_euler()


def set_stage(scene):
    face = Vector((.006, -.052, 1.615))
    focus = Vector((.010, -.051, 1.586))
    direction = Vector((-.44, -1, .032)).normalized()
    camera = bpy.data.objects.new("Grenadier portrait camera", bpy.data.cameras.new("Portrait lens"))
    scene.collection.objects.link(camera)
    camera.location = focus + direction * 3.5
    camera.rotation_euler = (-direction).to_track_quat("-Z", "Y").to_euler()
    camera.data.type = "ORTHO"
    camera.data.ortho_scale = .433 * 720 / 408
    scene.camera = camera
    world = bpy.data.worlds.new("Graphite studio")
    world.use_nodes = True
    bg = world.node_tree.nodes.get("Background")
    bg.inputs["Color"].default_value = (.40, .45, .53, 1)
    bg.inputs["Strength"].default_value = .17
    scene.world = world
    light(scene, "Warm portrait key", (-.77, -1.05, 2.21), face, 46, (.62, .91), (1., .845, .71))
    light(scene, "Cool eye fill", (.86, -.93, 1.76), face, 16, (.66, .80), (.74, .85, 1.))
    light(scene, "Hat and hair rim", (.58, .44, 2.21), face, 58, (.51, .87), (1., .80, .59))
    light(scene, "Steel temple rim", (-.78, .32, 1.96), face, 35, (.25, .82), (.59, .80, 1.))
    light(scene, "Broad lower eye light", (-.05, -1.18, 1.51), face, 3.8, (.64, .30), (1., .92, .84))
    bpy.ops.mesh.primitive_plane_add(size=2.4, location=focus-direction*1.1)
    wall = bpy.context.object
    wall.name = "Portrait sweep"
    wall.rotation_euler = camera.rotation_euler
    material = bpy.data.materials.new("Warm steel backdrop")
    material.use_nodes = True
    nodes = material.node_tree.nodes
    links = material.node_tree.links
    uv = nodes.new("ShaderNodeTexCoord")
    radius = nodes.new("ShaderNodeVectorMath")
    radius.operation = "DISTANCE"
    radius.inputs[1].default_value = (.51, .54, 0)
    links.new(uv.outputs["UV"], radius.inputs[0])
    ramp = nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.interpolation = "EASE"
    ramp.color_ramp.elements[0].color = (.13, .113, .088, 1)
    ramp.color_ramp.elements[1].position = .29
    ramp.color_ramp.elements[1].color = (.016, .021, .028, 1)
    links.new(radius.outputs["Value"], ramp.inputs[0])
    shade = nodes.new("ShaderNodeEmission")
    links.new(ramp.outputs[0], shade.inputs["Color"])
    links.new(shade.outputs[0], nodes["Material Output"].inputs["Surface"])
    wall.data.materials.append(material)


def render(model, output, draft=False):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(model.resolve()))
    scene = bpy.context.scene
    rig = next(obj for obj in scene.objects if obj.type == "ARMATURE")
    rig.animation_data.use_nla = False
    rig.animation_data.action = bpy.data.actions["Rest"]
    scene.frame_set(1)
    for obj in scene.objects:
        if obj.type == "LIGHT" or obj.name == "Muzzle flash":
            obj.hide_render = True
    set_stage(scene)
    scene.render.engine = "CYCLES"
    scene.cycles.samples = 14 if draft else 60
    scene.cycles.use_denoising = True
    scene.cycles.seed = 37
    scene.view_settings.view_transform = "AgX"
    scene.view_settings.look = "AgX - Medium High Contrast"
    scene.view_settings.exposure = -.36
    scene.render.resolution_x, scene.render.resolution_y = 1440, 816
    scene.render.resolution_percentage = 50 if draft else 100
    scene.render.image_settings.color_mode = "RGB"
    output.mkdir(parents=True, exist_ok=True)
    # Orthographic projections at the game texture's native dimensions.
    camera = scene.camera
    bpy.context.view_layer.update()
    view = camera.matrix_world.inverted()
    graph = bpy.context.evaluated_depsgraph_get()
    bounds = {}
    px_per_m = 720 / camera.data.ortho_scale
    for obj in scene.objects:
        if obj.type != "MESH" or obj.name.casefold() not in ("face","cap","hair","goggles"):
            continue
        posed = obj.evaluated_get(graph)
        to_cam = view @ posed.matrix_world
        coords = [to_cam @ vertex.co for vertex in posed.data.vertices]
        bounds[obj.name] = [round(360 + px_per_m*min(p.x for p in coords),1),
                            round(204 - px_per_m*max(p.y for p in coords),1),
                            round(360 + px_per_m*max(p.x for p in coords),1),
                            round(204 - px_per_m*min(p.y for p in coords),1)]
    (output/"framing.json").write_text(json.dumps({"narrow_hud_crop":[188,0,532,408],"bounds":bounds},indent=2))
    source = output/"master.png"
    scene.render.filepath = str(source)
    bpy.ops.render.render(write_still=True)
    image = imbuf.load(str(source))
    image.resize((720,408), method="BILINEAR")
    imbuf.write(image, filepath=str(output/"grenadier.png"))


if __name__=="__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("model", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--draft", action="store_true")
    args=parser.parse_args(sys.argv[sys.argv.index("--")+1:])
    render(args.model, args.output.resolve(), args.draft)
