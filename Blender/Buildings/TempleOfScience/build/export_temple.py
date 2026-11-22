"""Exports the Temple of Science's game file from TempleOfScience.blend. Nothing is saved back to the .blend.

  blender TempleOfScience.blend --background --python export_temple.py

glTF Binary, +Y up, modifiers applied, no cameras or lights. The empty `temple_root` stays behind, so
its children (`plinth`, `drum`, ..., `Armillary` with `Orb`, `RingA` and `RingB`) are the GLB's top-level
nodes and the model scene's script finds `Armillary` and `Armillary/Orb` directly under its root. The door
faces -Y in Blender, which is +Z in Godot, toward the game's camera.
"""
import bpy, os

HERE = os.path.dirname(os.path.abspath(__file__))
ASSETS = os.path.normpath(os.path.join(HERE, "..", "..", "..", "..", "assets", "models"))
bpy.context.scene.frame_set(0)
bpy.ops.object.select_all(action='DESELECT')
objects = [o for o in bpy.data.collections["temple_of_science"].all_objects if o.name != "temple_root"]
for ob in objects:
    ob.hide_set(False)
    ob.select_set(True)
bpy.context.view_layer.objects.active = objects[0]
target = os.path.join(ASSETS, "buildings", "temple_of_science.glb")
os.makedirs(os.path.dirname(target), exist_ok=True)
bpy.ops.export_scene.gltf(filepath=target, export_format='GLB', use_selection=True, export_yup=True,
                          export_apply=True, export_cameras=False, export_lights=False, export_extras=False,
                          export_animations=False)
print("EXPORTED", target, len(objects), "objects", os.path.getsize(target), "bytes")
