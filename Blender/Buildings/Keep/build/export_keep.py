"""Exports Keep game GLBs from Keep.blend. Nothing is saved back to Keep.blend.

Run in headless Blender 4.5:
  blender Keep.blend --background --python export_keep.py
  blender Keep.blend --background --python export_keep.py -- --to-assets

Exports into Blender/Buildings/Keep/export/ by default (or assets/models/ with --to-assets):
  - buildings/keep.glb (from `keep` collection)
  - effects/keep_death_fx.glb (from `keep_death_fx` collection)

glTF Binary, +Y up, modifiers applied, animations as NLA tracks, no cameras or lights.
Front gatehouse faces -Y in Blender, which becomes +Z in Godot toward the default camera.
"""

from __future__ import annotations

import os
import sys

import bpy

HERE = os.path.dirname(os.path.abspath(__file__))
TO_ASSETS = "--to-assets" in (sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else [])

if TO_ASSETS:
    ASSETS = os.path.normpath(os.path.join(HERE, "..", "..", "..", "..", "assets", "models"))
    KEEP_OUT = os.path.join(ASSETS, "buildings", "keep.glb")
    FX_OUT = os.path.join(ASSETS, "effects", "keep_death_fx.glb")
else:
    OUT_DIR = os.path.normpath(os.path.join(HERE, "..", "export"))
    KEEP_OUT = os.path.join(OUT_DIR, "keep.glb")
    FX_OUT = os.path.join(OUT_DIR, "keep_death_fx.glb")

lc = bpy.context.view_layer.layer_collection.children
for child in lc:
    child.exclude = False
for ob in bpy.data.objects:
    if ob.animation_data:
        for track in ob.animation_data.nla_tracks:
            track.mute = False
bpy.context.scene.frame_end = 240
bpy.context.view_layer.update()
bpy.context.scene.frame_set(0)


def export_collection(collection_name: str, target_path: str) -> None:
    bpy.ops.object.select_all(action="DESELECT")
    col = bpy.data.collections.get(collection_name)
    if col is None:
        raise RuntimeError(f"Missing collection '{collection_name}' in Keep.blend")
    objects = list(col.all_objects)
    if not objects:
        raise RuntimeError(f"Collection '{collection_name}' has no objects to export")
    for ob in objects:
        ob.hide_set(False)
        ob.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    os.makedirs(os.path.dirname(target_path), exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=target_path,
        export_format="GLB",
        use_selection=True,
        export_yup=True,
        export_image_format="JPEG" if collection_name == "keep" else "AUTO",
        export_jpeg_quality=89,
        export_apply=True,
        export_cameras=False,
        export_lights=False,
        export_extras=False,
        export_animations=True,
        export_animation_mode="NLA_TRACKS",
        export_force_sampling=True,
        export_optimize_animation_size=False,
        export_optimize_animation_keep_anim_object=True,
    )
    print(f"EXPORTED {target_path} ({len(objects)} objects, {os.path.getsize(target_path)} bytes)")


export_collection("keep", KEEP_OUT)
export_collection("keep_death_fx", FX_OUT)
