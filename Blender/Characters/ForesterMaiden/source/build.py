"""Assemble the editable worker, bake her work cycles, and publish the game rig."""
import argparse
from collections import defaultdict
import importlib
from pathlib import Path
import sys

import bpy
from mathutils import Matrix, Vector

SOURCE=Path(__file__).resolve().parent
PACKAGE=SOURCE.parent
sys.dont_write_bytecode=True
sys.path.insert(0,str(SOURCE))
import art
import outfit
from studio import stage

COMPONENTS={"field_kit":"Field Kit","garments":"Garments","arms_axe":"Arms","head":"Head",
            "work_gear":"Work gear"}

def assemble(components):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene=bpy.context.scene
    collection=bpy.data.collections.new("Forester Maiden artwork")
    scene.collection.children.link(collection)
    root=bpy.data.objects.new("Forester Maiden",None)
    collection.objects.link(root)
    root.empty_display_size=.10
    root["faction"]="Round Table"
    root["role"]="Forester"
    made=[]
    for module_name in components:
        group=COMPONENTS[module_name]
        layer=bpy.data.collections.new(group+" | editable")
        collection.children.link(layer)
        existing=set(bpy.data.objects)
        importlib.import_module(module_name).build()
        bpy.context.view_layer.update()
        objects=sorted(set(bpy.data.objects)-existing,key=lambda o:o.name)
        if not objects:
            raise ValueError(f"{module_name} made no character parts")
        for obj in objects:
            for coll in list(obj.users_collection):
                coll.objects.unlink(obj)
            layer.objects.link(obj)
            if not obj.parent:
                obj.parent=root
            if not obj.get("part"):
                obj["part"]=group
        made.extend(objects)
        print("Built",module_name,len(objects))
    outfit.tag_kerchief(made)
    bpy.context.view_layer.update()
    art.finish_textiles(made)
    if "head" in components:
        art.add_cheek_pigment()
    return root,made

def export(root,objects,path,rig=None):
    if rig:
        rig["inspect_all_gear"]=1.
        rig.update_tag()
        bpy.context.scene.frame_set(0)
        rig.data.pose_position="REST"
        for obj in objects:
            for modifier in obj.modifiers:
                if modifier.type=="ARMATURE" and modifier.object==rig:
                    modifier.show_viewport=False
    bpy.context.view_layer.update()
    graph=bpy.context.evaluated_depsgraph_get()
    groups=defaultdict(list)
    for obj in sorted(objects, key=lambda piece: piece.name):
        if obj.type not in {"MESH","CURVE","SURFACE","FONT"}:
            continue
        if obj.hide_render and obj.get("part") not in outfit.BONES:
            continue
        evaluated=obj.evaluated_get(graph)
        mesh=bpy.data.meshes.new_from_object(evaluated,preserve_all_data_layers=True,depsgraph=graph)
        if not mesh.polygons:
            continue
        mesh.transform(evaluated.matrix_world)
        if evaluated.matrix_world.to_3x3().determinant()<0:
            mesh.flip_normals()
        # Joined components share one primary UV channel. Keep the explicit
        # complexion coordinates as well as the UVs on the cloth normal tiles.
        uv=mesh.uv_layers.active
        if uv and uv.name!="UVMap":
            original=uv.name
            uv.name="UVMap"
            for material in mesh.materials:
                if material and material.use_nodes:
                    for node in material.node_tree.nodes:
                        if node.type=="UVMAP" and node.uv_map==original:
                            node.uv_map=uv.name
        copy=bpy.data.objects.new("Export piece",mesh)
        bpy.context.scene.collection.objects.link(copy)
        if rig and obj["part"] not in outfit.BONES:
            for g in obj.vertex_groups:
                copy.vertex_groups.new(name=g.name)
        groups[obj["part"]].append(copy)
    exported=[]
    for label,pieces in sorted(groups.items()):
        bpy.ops.object.select_all(action="DESELECT")
        for obj in pieces:
            obj.select_set(True)
        bpy.context.view_layer.objects.active=pieces[0]
        if len(pieces)>1:
            bpy.ops.object.join()
        joined=bpy.context.view_layer.objects.active
        joined.name=label
        joined.data.name=label
        if not rig:
            joined.parent=root
        elif label in outfit.BONES:
            outfit.attach_for_export(joined,label,rig)
        else:
            joined.parent=rig
            joined.matrix_parent_inverse=rig.matrix_world.inverted()
            joined.matrix_basis=Matrix.Identity(4)
            skin=joined.modifiers.new("Worker skeleton","ARMATURE")
            skin.object=rig
            if any(not any(g.weight>0 for g in v.groups) for v in joined.data.vertices):
                raise ValueError(f"Unweighted vertex in {label}")
        exported.append(joined)
    bpy.ops.object.select_all(action="DESELECT")
    for ob in [root,*exported]:
        ob.select_set(True)
    if rig:
        rig.select_set(True)
        rig.data.pose_position="POSE"
        data=rig.animation_data
        data.action=None
        data.use_nla=True
        for track in data.nla_tracks:
            track.is_solo=False
            track.mute=False
        bpy.context.scene.frame_set(0)
    bpy.context.view_layer.objects.active=root
    bpy.ops.export_scene.gltf(filepath=str(path),export_format="GLB",use_selection=True,
        export_yup=True,export_animations=bool(rig),export_cameras=False,export_lights=False,
        export_animation_mode="NLA_TRACKS",export_frame_range=False,
        export_anim_slide_to_zero=True,export_rest_position_armature=True,
        export_def_bones=False,export_skins=True,
        export_normals=True,export_texcoords=True,export_vertex_color="MATERIAL",
        export_all_vertex_colors=False)
    if rig:
        outfit.publish_kit_tracks(path)
    print("Exported",str(path),", ".join(o.name for o in exported))

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--blend",type=Path,default=SOURCE/"ForesterMaiden.blend")
    parser.add_argument("--glb",type=Path,default=PACKAGE/"export/forester_maiden.glb")
    parser.add_argument("--components",nargs="+",choices=COMPONENTS,default=list(COMPONENTS))
    parser.add_argument("--publish-open",action="store_true",help="Export edits from the currently open working file")
    args=parser.parse_args(sys.argv[sys.argv.index("--")+1:] if "--" in sys.argv else [])
    args.glb.parent.mkdir(parents=True,exist_ok=True)
    if args.publish_open:
        root=bpy.data.objects["Forester Maiden"]
        rig=next((o for o in root.children_recursive if o.type=="ARMATURE"),None)
        export(root,[o for o in root.children_recursive if o.get("part")],args.glb,rig)
        return
    root,artwork=assemble(args.components)
    rig=None
    if set(args.components)==set(COMPONENTS):
        from rig import create_rig
        from work_cycles import build_actions
        rig=create_rig(root,artwork)
        build_actions(rig)
        outfit.source_controls(rig,artwork)
    stage(bpy.context.scene)
    bpy.context.scene.render.filepath="//../preview/forester_maiden.png"
    bpy.ops.object.select_all(action="DESELECT")
    selected=rig or root
    selected.select_set(True)
    bpy.context.view_layer.objects.active=selected
    for area in bpy.context.screen.areas:
        if area.type=="VIEW_3D":
            space=area.spaces.active
            space.overlay.show_overlays=False
            space.shading.color_type="MATERIAL"
            space.region_3d.view_distance=2.75
            space.region_3d.view_rotation=Vector((.21,-1,.10)).to_track_quat("Z","Y")
            space.region_3d.view_location=(0,0,.88)
            space.region_3d.view_perspective="ORTHO"
    bpy.context.preferences.filepaths.save_version=0
    args.blend.parent.mkdir(parents=True,exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(args.blend.resolve()),compress=True)
    export(root,artwork,args.glb,rig)

if __name__=="__main__":
    main()
