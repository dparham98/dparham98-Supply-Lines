"""Build one staged Arthurian Warhound and render previews from its exported GLB.

Run in a fresh background Blender 4.5 process, passing -- <stageDir> build.
The editable recipe lives at <stageDir>/source/build_warhound.py.
"""

import argparse
import importlib.util
import math
import random
import struct
import sys
import zlib
from pathlib import Path

import bpy
from mathutils import Vector


def stage_path(stage, relative):
    path = (stage / relative).resolve()
    if not path.is_relative_to(stage):
        raise ValueError(f"Staged path points outside the run folder: {relative}")
    return path


def read_recipe(path):
    spec = importlib.util.spec_from_file_location("warhound_recipe", path)
    module = importlib.util.module_from_spec(spec)
    sys.dont_write_bytecode = True
    spec.loader.exec_module(module)
    return module


def make_leather_png(path, base_color):
    """Write a repeatable, fine-grained sRGB tile around the recipe's linear base color."""
    def encode(linear):
        srgb = 12.92 * linear if linear <= 0.0031308 else 1.055 * linear ** (1 / 2.4) - 0.055
        return round(255 * max(0, min(1, srgb)))

    def chunk(kind, payload):
        crc = zlib.crc32(kind + payload)
        return struct.pack(">I", len(payload)) + kind + payload + struct.pack(">I", crc)

    size = 128
    rng = random.Random(408)
    scanlines = bytearray()
    for y in range(size):
        scanlines.append(0)  # PNG filter byte
        for x in range(size):
            grain = 1 + 0.09 * math.sin(math.tau * (x + y) / 8) + rng.uniform(-0.14, 0.14)
            scanlines.extend(encode(channel * grain) for channel in base_color[:3])
    header = struct.pack(">IIBBBBB", size, size, 8, 2, 0, 0, 0)
    path.write_bytes(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header) + chunk(b"sRGB", b"\0")
                     + chunk(b"IDAT", zlib.compress(scanlines, 9)) + chunk(b"IEND", b""))


def apply_leather_texture(meshes, path):
    material = bpy.data.materials['Harness_Leather']
    socket = material.node_tree.nodes['Principled BSDF'].inputs['Base Color']
    if socket.is_linked:
        raise ValueError('The staged recipe already textures Harness_Leather. Reconcile its texture with this stage.')
    make_leather_png(path, socket.default_value)
    image = bpy.data.images.load(str(path), check_existing=False)
    image.pack()
    image.filepath = bpy.path.relpath(str(path))
    node = material.node_tree.nodes.new('ShaderNodeTexImage')
    node.image = image
    node.label = 'Harness leather grain'
    node.location = (-340, 290)
    material.node_tree.links.new(node.outputs['Color'], socket)

    for obj in meshes:
        mesh = obj.data
        if material.name not in mesh.materials or mesh.uv_layers.active is not None:
            continue
        uv = mesh.uv_layers.new(name='UVMap')
        # Local-space box projection preserves an even grain density across stiff leather straps.
        planes = ((1, 2), (0, 2), (0, 1))
        for face in mesh.polygons:
            normal_axis = max(range(3), key=lambda axis: abs(face.normal[axis]))
            u, v = planes[normal_axis]
            for i in face.loop_indices:
                p = mesh.vertices[mesh.loops[i].vertex_index].co
                uv.data[i].uv = (p[u] * 4, p[v] * 4)


def frame_asset(pivot, direction, size):
    """Fit deformed rest-pose mesh vertices in camera space and return target and view width."""
    bpy.context.view_layer.update()
    depsgraph = bpy.context.evaluated_depsgraph_get()
    points = []
    for obj in pivot.children_recursive:
        # Blender also imports a hidden, unskinned icosphere for displaying bones.
        if obj.type == 'MESH' and obj.find_armature() is not None:
            obj = obj.evaluated_get(depsgraph)
            points.extend(obj.matrix_world @ vertex.co for vertex in obj.data.vertices)
    if not points:
        raise ValueError('No meshes found in reimported GLB')
    rotation = (-direction).to_track_quat('-Z', 'Y')
    axes = [rotation @ Vector(axis) for axis in ((1, 0, 0), (0, 1, 0), (0, 0, 1))]
    extents = [(min(p.dot(axis) for p in points), max(p.dot(axis) for p in points)) for axis in axes]
    target = sum((axis * ((lo + hi) / 2) for axis, (lo, hi) in zip(axes, extents)), Vector())
    width = max(extents[0][1] - extents[0][0], (extents[1][1] - extents[1][0]) * size[0] / size[1])
    return target, width * 1.18


def render_previews(recipe, glb, preview):
    scene = recipe._setup_studio_scene()
    scene.cycles.samples = 8
    scene.render.threads_mode = 'FIXED'
    scene.render.threads = 4
    pivot = recipe._import_glb_at(glb)
    for name, yaw, pitch, size in [('hero', -52, 12, (512, 384)), ('rts', -35, 50, (384, 288))]:
        pivot.rotation_euler.z = math.radians(yaw)
        angle = math.radians(pitch)
        direction = Vector((0, -math.cos(angle), math.sin(angle)))
        target, width = frame_asset(pivot, direction, size)
        recipe._render_view(scene, target, direction, width, size, preview / f'{name}.png')

    # The Two Lakes camera covers 72 vertical units in 900 px at starting zoom.
    # A 96 px square samples 7.68 units; the model is rendered at authored scale.
    # The dog is turned for silhouette comparison while retaining the map camera's pitch.
    scene.cycles.samples = 20
    recipe._render_view(scene, target, direction, 96 * 72 / 900, (96, 96), preview / 'rts_native.png')


def build(stage):
    if not bpy.app.background or any((parent / 'project.godot').exists() for parent in (stage, *stage.parents)):
        raise ValueError('Run background Blender in a scratch stage outside the Godot project.')
    recipe_path = stage_path(stage, 'source/build_warhound.py')
    blend = stage_path(stage, 'source/warhound.blend')
    glb = stage_path(stage, 'export/warhound.glb')
    texture = stage_path(stage, 'textures/harness_leather_basecolor.png')
    preview = stage_path(stage, 'preview')
    for name in ('hero.png', 'rts.png', 'rts_native.png'):
        stage_path(stage, f'preview/{name}')
    for directory in (blend.parent, glb.parent, texture.parent, preview):
        directory.mkdir(parents=True, exist_ok=True)

    recipe = read_recipe(recipe_path)
    recipe.SOURCE_BLEND, recipe.EXPORT_GLB, recipe.PREVIEW_DIR = blend, glb, preview
    rig, meshes = recipe.build_scene()
    # The original recipe binds by modifier while parenting meshes to a sibling empty.
    # Parenting to the same rig avoids ambiguous armature lookup in the glTF exporter.
    for obj in meshes:
        if obj.parent != rig and any(mod.type == 'ARMATURE' and mod.object == rig for mod in obj.modifiers):
            transform = obj.matrix_world.copy()
            obj.parent = rig
            obj.matrix_world = transform
    apply_leather_texture(meshes, texture)
    bpy.ops.wm.save_as_mainfile(filepath=str(blend), compress=True)
    recipe.export_warhound_glb(rig, meshes, glb)
    render_previews(recipe, glb, preview)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('stage', type=Path)
    parser.add_argument('mode', choices=['build'])
    args = parser.parse_args(sys.argv[sys.argv.index('--') + 1:])
    build(args.stage.resolve(strict=True))
