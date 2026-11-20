"""Construct the editable Ubermech and publish the skinned model used by the live unit."""
import argparse
from pathlib import Path
import sys
import bpy
from mathutils import Matrix, Vector

SOURCE=Path(__file__).resolve().parent
REPO=SOURCE.parents[3]
sys.path.insert(0,str(SOURCE))
sys.dont_write_bytecode=True


def publish(skeleton,pieces,output):
    """Flatten bevels and combine rigidly weighted pieces into one game mesh."""
    pieces=sorted(pieces,key=lambda p:(p.name.startswith("Paint wear |"),p.name))
    scene=bpy.context.scene
    skeleton.data.pose_position="REST"
    scene.frame_set(0)
    # A single bevel face catches the same highlight at RTS scale. The native
    # source retains its rounded high-detail chamfers for close-up editing.
    for piece in pieces:
        for modifier in piece.modifiers:
            if modifier.type!="BEVEL":
                continue
            modifier.segments=1
            if piece["joint"]!="Head" and modifier.width<=.006 and max(piece.dimensions)<.20:
                modifier.show_viewport=False
    bpy.context.view_layer.update()
    graph=bpy.context.evaluated_depsgraph_get()
    baked=[]
    for piece in pieces:
        evaluated=piece.evaluated_get(graph)
        geometry=bpy.data.meshes.new_from_object(evaluated,preserve_all_data_layers=True,depsgraph=graph)
        geometry.transform(evaluated.matrix_world)
        if evaluated.matrix_world.to_3x3().determinant()<0:
            geometry.flip_normals()
        obj=bpy.data.objects.new("Baked armor plate",geometry)
        scene.collection.objects.link(obj)
        group=obj.vertex_groups.new(name=piece["joint"])
        group.add(list(range(len(geometry.vertices))),1,"REPLACE")
        baked.append(obj)
    bpy.ops.object.select_all(action="DESELECT")
    for obj in baked:
        obj.select_set(True)
    bpy.context.view_layer.objects.active=baked[0]
    bpy.ops.object.join()
    armor=bpy.context.object
    armor.name=armor.data.name="Ubermech Armor"
    armor.parent=skeleton
    armor.matrix_parent_inverse=skeleton.matrix_world.inverted()
    mod=armor.modifiers.new("Articulated chassis","ARMATURE")
    mod.object=skeleton
    for vertex in armor.data.vertices:
        if len(vertex.groups)!=1 or abs(vertex.groups[0].weight-1)>.0001:
            raise ValueError(f"Invalid armor binding at vertex {vertex.index}")
    skeleton.select_set(True)
    skeleton.data.pose_position="POSE"
    anim=skeleton.animation_data
    anim.action=None
    anim.use_nla=True
    for track in anim.nla_tracks:
        track.is_solo=False
        track.mute=False
    scene.frame_set(0)
    output.parent.mkdir(exist_ok=True,parents=True)
    bpy.ops.export_scene.gltf(filepath=str(output),export_format="GLB",use_selection=True,
        export_yup=True,export_skins=True,export_def_bones=False,export_rest_position_armature=True,
        export_animations=True,export_animation_mode="NLA_TRACKS",export_frame_range=False,
        export_anim_slide_to_zero=True,export_materials="EXPORT",export_cameras=False,
        export_lights=False,export_normals=True,export_texcoords=True,export_extras=False)
    print("Published",output,"from",len(pieces),"editable parts")


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--blend",type=Path,default=SOURCE/"Ubermech.blend")
    parser.add_argument("--glb",type=Path,default=REPO/"assets/models/units/ubermech.glb")
    parser.add_argument("--publish-open",action="store_true")
    args=parser.parse_args(sys.argv[sys.argv.index("--")+1:] if "--" in sys.argv else [])
    if args.publish_open:
        pieces=sorted((p for p in bpy.context.scene.objects if p.type=="MESH" and p.get("joint")),key=lambda p:p.name)
        skeleton=next(obj for obj in bpy.context.scene.objects if obj.type=="ARMATURE")
        publish(skeleton,pieces,args.glb)
        return
    import arms,body,head,legs,rig,finish
    from studio import stage,camera
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene=bpy.context.scene
    for component in (body,legs,head,arms):
        component.build()
    pieces=sorted((obj for obj in scene.objects if obj.type=="MESH"),key=lambda p:p.name)
    pieces.extend(finish.build(pieces))
    skeleton=rig.create(pieces)
    skeleton["faction"]="Cyborg"
    skeleton["walk_ground_speed_mps"]=3.1
    stage(scene)
    camera(scene,(-.035,-.08,2.53),(-.36,-1,.135),5.85,(1080,1080))
    scene.cycles.samples=40
    scene.render.filepath="//../preview/ubermech.png"
    bpy.ops.object.select_all(action="DESELECT")
    skeleton.select_set(True)
    bpy.context.view_layer.objects.active=skeleton
    for area in bpy.context.screen.areas:
        if area.type=="VIEW_3D":
            view=area.spaces.active
            view.overlay.show_overlays=False
            view.shading.color_type="MATERIAL"
            view.region_3d.view_distance=8.45
            view.region_3d.view_location=(0,0,2.56)
            view.region_3d.view_rotation=Vector((-.36,-1,.135)).to_track_quat("Z","Y")
            view.region_3d.view_perspective="ORTHO"
    bpy.context.preferences.filepaths.save_version=0
    args.blend.parent.mkdir(exist_ok=True,parents=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(args.blend),compress=True)
    publish(skeleton,pieces,args.glb)


if __name__=="__main__":
    main()
