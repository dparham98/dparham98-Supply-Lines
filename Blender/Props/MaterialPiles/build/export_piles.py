"""Exports the iron, wood and coal piles from MaterialPiles.blend. Nothing is saved back to the .blend.

  blender MaterialPiles.blend --background --python export_piles.py

glTF Binary, +Y up, no animation, cameras or lights. Each pile is moved back to the origin before export,
so it is centred on its cell in the game. The front (cut log ends, pallet tag) faces -Y in Blender, which
is +Z in Godot, toward the game's camera.
"""
import bpy, os

HERE = os.path.dirname(os.path.abspath(__file__))
ASSETS = os.path.normpath(os.path.join(HERE, "..", "..", "..", "..", "assets", "models", "props"))
for child in bpy.context.view_layer.layer_collection.children:
    child.exclude = False
for kind in ("iron", "wood", "coal"):
    root = bpy.data.objects[kind + "_root"]
    root.location = (0, 0, 0)
    bpy.context.view_layer.update()
    bpy.ops.object.select_all(action='DESELECT')
    objects = list(bpy.data.collections["pile_" + kind].all_objects)
    for ob in objects:
        ob.hide_set(False)
        ob.select_set(True)
    bpy.context.view_layer.objects.active = root
    target = os.path.join(ASSETS, "material_pile_%s.glb" % kind)
    bpy.ops.export_scene.gltf(filepath=target, export_format='GLB', use_selection=True, export_yup=True,
                              export_apply=True, export_cameras=False, export_lights=False, export_extras=False,
                              export_animations=False)
    print("EXPORTED", os.path.basename(target), len(objects), "objects", os.path.getsize(target), "bytes")
