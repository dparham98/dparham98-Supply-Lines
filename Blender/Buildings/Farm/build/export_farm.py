"""Exports Farm GLBs from Farm.blend and verifies them via clean glTF re-import.

Run in headless Blender 4.5:
  blender Farm.blend --background --python export_farm.py
  blender Farm.blend --background --python export_farm.py -- --to-assets
"""

from __future__ import annotations

import os
import sys

import bpy
from mathutils import Vector as V

HERE = os.path.dirname(os.path.abspath(__file__))
TO_ASSETS = "--to-assets" in (sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else [])

if TO_ASSETS:
    ASSETS = os.path.normpath(os.path.join(HERE, "..", "..", "..", "..", "assets", "models"))
    MAIN_OUT = os.path.join(ASSETS, "buildings", "farm.glb")
    FX_OUT = os.path.join(ASSETS, "effects", "farm_death_fx.glb")
else:
    OUT_DIR = os.path.normpath(os.path.join(HERE, "..", "export"))
    MAIN_OUT = os.path.join(OUT_DIR, "farm.glb")
    FX_OUT = os.path.join(OUT_DIR, "farm_death_fx.glb")

lc = bpy.context.view_layer.layer_collection.children
for child in lc:
    child.exclude = False
for ob in bpy.data.objects:
    if ob.animation_data:
        for track in ob.animation_data.nla_tracks:
            track.mute = False
bpy.context.view_layer.update()
bpy.context.scene.frame_set(0)


def export_collection(collection_name: str, target_path: str) -> None:
    bpy.ops.object.select_all(action="DESELECT")
    col = bpy.data.collections.get(collection_name)
    if col is None:
        raise RuntimeError(f"Missing collection '{collection_name}' in Farm.blend")
    objects = list(col.all_objects)
    if not objects:
        raise RuntimeError(f"Collection '{collection_name}' has no objects")
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


def verify_reimport(main_path: str, fx_path: str) -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=main_path)
    bpy.context.view_layer.update()
    mn = V((1e9, 1e9, 1e9))
    mx = V((-1e9, -1e9, -1e9))
    mats = set()
    tracks = set()
    for ob in bpy.data.objects:
        if ob.animation_data:
            for tr in ob.animation_data.nla_tracks:
                for st in tr.strips:
                    tracks.add(st.name)
        if ob.type == "MESH":
            for m in ob.data.materials:
                if m:
                    mats.add(m.name)
            for c in ob.bound_box:
                wc = ob.matrix_world @ V(c)
                mn.x, mn.y, mn.z = min(mn.x, wc.x), min(mn.y, wc.y), min(mn.z, wc.z)
                mx.x, mx.y, mx.z = max(mx.x, wc.x), max(mx.y, wc.y), max(mx.z, wc.z)
    assert mn.x >= -1.98 and mx.x <= 1.98 and mn.y >= -1.98 and mx.y <= 1.98, f"Reimport X/Y out of 4x4 m: {mn}..{mx}"
    assert mx.z <= 4.75, f"Reimport Z too tall: {mx.z}"
    assert {"Idle", "Work", "Depleted", "Build", "Die"}.issubset(tracks), f"Missing clips on reimport: {tracks}"
    assert "team_color" in mats, f"Missing team_color material: {mats}"

    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=fx_path)
    fx_tracks = set()
    fx_meshes = []
    for ob in bpy.data.objects:
        if ob.type == "MESH":
            fx_meshes.append(ob.name)
        if ob.animation_data:
            for tr in ob.animation_data.nla_tracks:
                for st in tr.strips:
                    fx_tracks.add(st.name)
    assert "Death" in fx_tracks, f"FX missing Death clip: {fx_tracks}"
    assert "Flash_Barn" in fx_meshes, f"Missing Flash_Barn in FX meshes: {fx_meshes[:8]}"
    print(f"VERIFIED re-import main={sorted(tracks)} mats={len(mats)} bounds=({mn.x:.2f}..{mx.x:.2f}, {mn.y:.2f}..{mx.y:.2f}, {mn.z:.2f}..{mx.z:.2f}) | fx_flash_idx={fx_meshes.index('Flash_Barn')}")


export_collection("farm", MAIN_OUT)
export_collection("farm_death_fx", FX_OUT)
verify_reimport(MAIN_OUT, FX_OUT)
