"""Exports the five construction site sizes from ConstructionSite.blend. Nothing is saved back.

  blender ConstructionSite.blend --background --python export_site.py

glTF Binary, +Y up, animations as NLA tracks, no cameras or lights. Each site is moved back to the
origin before export, so it is centred on its footprint in the game. The front (gate and board)
faces -Y in Blender, which is +Z in Godot, toward the game's camera.
"""
import bpy, os

HERE = os.path.dirname(os.path.abspath(__file__))
ASSETS = os.path.normpath(os.path.join(HERE, "..", "..", "..", "..", "assets", "models", "buildings"))
SIZES = (2, 3, 6, 8, 10)
for child in bpy.context.view_layer.layer_collection.children:
    child.exclude = False
bpy.context.scene.frame_set(0)
for size in SIZES:
    root = bpy.data.objects["s%d_root" % size]
    root.location = (0, 0, 0)
    bpy.context.view_layer.update()
    bpy.ops.object.select_all(action='DESELECT')
    objects = list(bpy.data.collections["site_%d" % size].all_objects)
    for ob in objects:
        ob.hide_set(False)
        ob.select_set(True)
    bpy.context.view_layer.objects.active = root
    target = os.path.join(ASSETS, "construction_site_%dx%d.glb" % (size, size))
    os.makedirs(ASSETS, exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=target, export_format='GLB', use_selection=True, export_yup=True,
                              export_apply=True, export_cameras=False, export_lights=False, export_extras=False,
                              export_animations=True, export_animation_mode='NLA_TRACKS',
                              export_force_sampling=True, export_optimize_animation_size=False,
                              export_optimize_animation_keep_anim_object=True)
    print("EXPORTED", os.path.basename(target), len(objects), "objects", os.path.getsize(target), "bytes")
