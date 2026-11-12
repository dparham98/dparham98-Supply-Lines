"""Exports the Iron Mine's game files from IronMine.blend. Nothing is saved back to the .blend.

  blender IronMine.blend --background --python export_mine.py

glTF Binary, +Y up, modifiers applied, animations as NLA tracks, no cameras or lights. Constant channels
are kept, so a part held still or hidden through a clip is still keyed in it. The front (lamp,
ore bin and skip) faces -Y in Blender, which is +Z in Godot, toward the game's camera.
"""
import bpy, os

HERE = os.path.dirname(os.path.abspath(__file__))
ASSETS = os.path.normpath(os.path.join(HERE, "..", "..", "..", "..", "assets", "models"))
lc = bpy.context.view_layer.layer_collection.children
for child in lc:
    child.exclude = False
bpy.context.view_layer.update()
bpy.context.scene.frame_set(0)


def export(collection, path, animations):
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
                              export_animations=animations, export_animation_mode='NLA_TRACKS',
                              export_force_sampling=True, export_optimize_animation_size=False,
                              export_optimize_animation_keep_anim_object=True)
    print("EXPORTED", path, len(objects), "objects", os.path.getsize(target), "bytes")


export("iron_mine", os.path.join("buildings", "iron_mine.glb"), True)
export("mine_death_fx", os.path.join("effects", "iron_mine_death_fx.glb"), True)
