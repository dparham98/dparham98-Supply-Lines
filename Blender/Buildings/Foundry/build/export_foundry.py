"""Exports the Foundry's game files from Foundry.blend. Nothing is saved back to the .blend.

  blender Foundry.blend --background --python export_foundry.py

glTF Binary, +Y up, modifiers applied, animations as NLA tracks, no cameras or lights:
  foundry          -> assets/models/buildings/foundry.glb (Idle, Research, Build, Die)
  foundry_death_fx -> assets/models/effects/foundry_death_fx.glb (Death)
"""
import bpy, os

HERE = os.path.dirname(os.path.abspath(__file__))
ASSETS = os.path.normpath(os.path.join(HERE, "..", "..", "..", "..", "assets", "models"))
for child in bpy.context.view_layer.layer_collection.children:
    child.exclude = False
bpy.context.view_layer.update()
bpy.context.scene.frame_set(0)


def export(collection, path):
    bpy.ops.object.select_all(action='DESELECT')
    objects = list(bpy.data.collections[collection].all_objects)
    for ob in objects:
        ob.hide_set(False)
        ob.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    target = os.path.join(ASSETS, path)
    os.makedirs(os.path.dirname(target), exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=target, export_format='GLB', use_selection=True, export_yup=True,
                              export_apply=True, export_cameras=False, export_lights=False, export_extras=False,
                              export_animations=True, export_animation_mode='NLA_TRACKS',
                              export_force_sampling=True, export_optimize_animation_size=False)
    print("EXPORTED", path, len(objects), "objects", os.path.getsize(target), "bytes")


export("foundry", os.path.join("buildings", "foundry.glb"))
export("foundry_death_fx", os.path.join("effects", "foundry_death_fx.glb"))
