"""Exports the Knights train car from KnightsTrain.blend. Nothing is saved back to the .blend.

  blender KnightsTrain.blend --background --python export_knights_train.py

glTF Binary, +Y up, modifiers applied, no animation, no cameras or lights:
  knights_train -> assets/models/units/knights_train_cargo.glb (root train_cargo_root, as the Streamliner's car)
"""
import bpy, os

HERE = os.path.dirname(os.path.abspath(__file__))
ASSETS = os.path.normpath(os.path.join(HERE, "..", "..", "..", "..", "assets", "models"))
for child in bpy.context.view_layer.layer_collection.children:
    child.exclude = False
bpy.context.view_layer.update()
bpy.ops.object.select_all(action='DESELECT')
objects = list(bpy.data.collections["knights_train"].all_objects)
for ob in objects:
    ob.hide_set(False)
    ob.select_set(True)
bpy.context.view_layer.objects.active = objects[0]
target = os.path.join(ASSETS, "units", "knights_train_cargo.glb")
bpy.ops.export_scene.gltf(filepath=target, export_format='GLB', use_selection=True, export_yup=True,
                          export_apply=True, export_cameras=False, export_lights=False, export_extras=False,
                          export_animations=False)
print("EXPORTED", target, len(objects), "objects", os.path.getsize(target), "bytes")
