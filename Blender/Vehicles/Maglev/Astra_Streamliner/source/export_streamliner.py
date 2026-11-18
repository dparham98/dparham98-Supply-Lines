"""Export the editable train in the open Blender file. Run as a background script."""
import bpy
from pathlib import Path


def batch_static_parts(root):
    """Evaluate fixed parts into one body mesh; keep articulated nodes and datums live.

    Joining temporary copies lets Blender combine identical material slots across
    pieces. The source keeps every editable panel, mask island and bevel modifier.
    """
    graph = bpy.context.evaluated_depsgraph_get()
    fixed = sorted((obj for obj in root.children if obj.type=='MESH' and
                    obj.name not in {'sled_cargo_rear','sled_cargo_front','cargo_car_indicator'}),
                   key=lambda obj: obj.name)
    copies = {}
    for obj in fixed:
        mesh = bpy.data.meshes.new_from_object(obj.evaluated_get(graph),depsgraph=graph)
        duplicate = bpy.data.objects.new("Export " + obj.name,mesh)
        bpy.context.scene.collection.objects.link(duplicate)
        duplicate.parent = root
        duplicate.matrix_world = obj.matrix_world.copy()
        duplicate.select_set(True)
        copies[obj.name] = duplicate
    body = copies['cargo_body']
    bpy.context.view_layer.objects.active = body
    bpy.ops.object.join()
    return body,set(fixed)


def export_train(destination):
    root = bpy.data.objects["train_cargo_root"]
    original = bpy.data.objects['cargo_body']
    selected = list(bpy.context.selected_objects)
    active = bpy.context.view_layer.objects.active
    bpy.ops.object.select_all(action='DESELECT')
    fixed = set()
    combined = None
    try:
        if 'cargo_car_indicator' in bpy.data.objects:
            combined,fixed = batch_static_parts(root)
            original.name = "Editable cargo midsection"
            combined.name = 'cargo_body'
            combined.data.name = "Streamliner fixed shell"
        root.select_set(True)
        for part in root.children_recursive:
            part.select_set(part not in fixed)
        bpy.context.view_layer.objects.active = root
        destination.parent.mkdir(parents=True, exist_ok=True)
        bpy.ops.export_scene.gltf(
            filepath=str(destination), export_format='GLB', use_selection=True,
            export_yup=True, export_apply=True, export_animations=False,
            export_cameras=False, export_lights=False, export_texcoords=False,
            export_tangents=False, export_extras=False,
        )
    finally:
        if combined:
            mesh = combined.data
            bpy.data.objects.remove(combined,do_unlink=True)
            bpy.data.meshes.remove(mesh)
            original.name = 'cargo_body'
        bpy.ops.object.select_all(action='DESELECT')
        for part in selected:
            part.select_set(True)
        bpy.context.view_layer.objects.active = active


if __name__ == "__main__":
    export_train(Path(__file__).resolve().parents[1] / "export" / "maglev_train_cargo.glb")
