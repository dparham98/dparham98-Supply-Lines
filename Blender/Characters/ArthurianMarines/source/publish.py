"""Export a revised working model. Run in Blender with the desired .blend open."""
import argparse
from collections import defaultdict
from pathlib import Path
import sys

import bpy
from mathutils import Matrix


PACKAGE = Path(__file__).resolve().parents[1]


def component(obj):
    if obj.get("asset_part") == "rifle":
        return "Rifle"
    kind = obj.get("source_component") or obj.get("prototype_component")
    if kind == "head" or "_head_" in obj.name.lower():
        return "Head"
    if kind == "body":
        return "Armor"
    name = obj.name.lower()
    for label, keywords in [
        ("Shield", ("shield",)),
        ("Carbine", ("carbine", "rifle")),
        ("Sword", ("sword", "scabbard", "pommel", "sheath")),
        ("Cloth", ("cape", "mantle", "tabard", "cloth")),
    ]:
        if any(word in name for word in keywords):
            return label
    return "Equipment"


def export(output):
    asset, = [c for c in bpy.data.collections if c.name.endswith("_ASSET")]
    rigs = [obj for obj in asset.all_objects if obj.type == "ARMATURE"]
    rig = None
    if rigs:
        rig, = rigs
        # Bake the armor's bevels and the artist's paint at bind pose. Baking
        # a frame of Run here would apply that pose again at playback.
        rig.data.pose_position = "REST"
        for part in asset.all_objects:
            for modifier in part.modifiers:
                if modifier.type == "ARMATURE" and modifier.object == rig:
                    modifier.show_viewport = False
        bpy.context.view_layer.update()
    deps = bpy.context.evaluated_depsgraph_get()
    groups = defaultdict(list)
    painted_materials = set()
    for src in asset.all_objects:
        if src.type not in {"MESH", "CURVE"} or src.hide_render:
            continue
        evaluated = src.evaluated_get(deps)
        mesh = bpy.data.meshes.new_from_object(evaluated, preserve_all_data_layers=True, depsgraph=deps)
        # The artist's separate pigment layers all become the first glTF color
        # set. Without this step, joining eyes, skin and lips adds white filler
        # layers and consumers which use COLOR_0 lose the paint in close-ups.
        if mesh.color_attributes:
            layer, = mesh.color_attributes
            for material in mesh.materials:
                if material and material.use_nodes:
                    for node in material.node_tree.nodes:
                        if node.type == "VERTEX_COLOR" and node.layer_name == layer.name:
                            painted_materials.add(material)
            layer.name = "Portrait pigment"
        mesh.transform(evaluated.matrix_world)
        if evaluated.matrix_world.to_3x3().determinant() < 0:
            mesh.flip_normals()
        obj = bpy.data.objects.new("Export piece", mesh)
        bpy.context.scene.collection.objects.link(obj)
        if rig:
            # The evaluated mesh carries per-vertex group indices; their names
            # belong to the object. Recreate the same indices before joining.
            for group in src.vertex_groups:
                obj.vertex_groups.new(name=group.name)
            if not obj.vertex_groups:
                raise ValueError(f"Unbound character piece: {src.name}")
        groups[component(src)].append(obj)

    for material in painted_materials:
        for node in material.node_tree.nodes:
            if node.type == "VERTEX_COLOR":
                node.layer_name = "Portrait pigment"
    objects = []
    for label, pieces in sorted(groups.items()):
        bpy.ops.object.select_all(action="DESELECT")
        for obj in pieces:
            obj.select_set(True)
        bpy.context.view_layer.objects.active = pieces[0]
        if len(pieces) > 1:
            bpy.ops.object.join()
        result = bpy.context.view_layer.objects.active
        result.name = label
        result.data.name = label
        if rig:
            for v in result.data.vertices:
                if not any(g.weight > 0 and result.vertex_groups[g.group].name in rig.data.bones
                           for g in v.groups):
                    raise ValueError(f"{label} vertex {v.index} has no bone influence")
            result.parent = rig
            result.matrix_parent_inverse = rig.matrix_world.inverted()
            result.matrix_basis = Matrix.Identity(4)
            skin = result.modifiers.new("Character skeleton", "ARMATURE")
            skin.object = rig
        objects.append(result)
    assert {"Head", "Armor"}.issubset({obj.name for obj in objects})
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects:
        obj.select_set(True)
    if rig:
        rig.select_set(True)
        bpy.context.view_layer.objects.active = rig
        rig.data.pose_position = "POSE"
        anim = rig.animation_data
        if not anim or not any(track.strips for track in anim.nla_tracks):
            raise ValueError("The rig has no animation tracks")
        anim.action = None
        anim.use_nla = True
        for track in anim.nla_tracks:
            track.is_solo = False
            track.mute = False
        bpy.context.scene.frame_set(bpy.context.scene.frame_start)
    output.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=str(output), export_format="GLB", use_selection=True,
        export_yup=True, export_animations=bool(rig), export_cameras=False,
        export_animation_mode="NLA_TRACKS", export_frame_range=False,
        export_anim_slide_to_zero=True, export_rest_position_armature=True,
        export_skins=True, export_def_bones=False,
        export_lights=False, export_normals=True,
        export_vertex_color="MATERIAL", export_all_vertex_colors=False,
    )
    print("Wrote", output, [obj.name for obj in objects])


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else [])
    name = Path(bpy.data.filepath).stem
    export(args.output or PACKAGE / "export" / (name + ".glb"))
