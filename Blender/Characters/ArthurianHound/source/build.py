"""Build the editable Arthurian hound or publish its saved pose rig to glTF."""
import argparse
from pathlib import Path
import sys
import bpy
from mathutils import Vector

HERE=Path(__file__).resolve().parent
PACKAGE=HERE.parent
sys.dont_write_bytecode=True
sys.path.insert(0,str(HERE))
import body,head,rig


def publish(skeleton,pieces,path):
    # Bake bevels in bind pose, retain the named joints and export one skinned
    # mesh with shared material surfaces. The saved Blender parts stay separate.
    skeleton.data.pose_position='REST'
    bpy.context.view_layer.update()
    graph=bpy.context.evaluated_depsgraph_get()
    baked=[]
    for piece in sorted(pieces,key=lambda obj:obj.name):
        evaluated=piece.evaluated_get(graph)
        geometry=bpy.data.meshes.new_from_object(evaluated,preserve_all_data_layers=True,depsgraph=graph)
        geometry.transform(evaluated.matrix_world)
        obj=bpy.data.objects.new("Baked hound part",geometry)
        bpy.context.scene.collection.objects.link(obj)
        group=obj.vertex_groups.new(name=piece["joint"])
        group.add(list(range(len(geometry.vertices))),1,'REPLACE')
        baked.append(obj)
    bpy.ops.object.select_all(action='DESELECT')
    for obj in baked:
        obj.select_set(True)
    bpy.context.view_layer.objects.active=baked[0]
    bpy.ops.object.join()
    mesh=bpy.context.object
    mesh.name=mesh.data.name="Arthurian Hound"
    mesh.parent=skeleton
    mod=mesh.modifiers.new("Hound rig",'ARMATURE')
    mod.object=skeleton
    skeleton.data.pose_position='POSE'
    skeleton.select_set(True)
    skeleton.animation_data.action=None
    skeleton.animation_data.use_nla=True
    for track in skeleton.animation_data.nla_tracks:
        track.mute=False
    bpy.context.scene.frame_set(1)
    path.parent.mkdir(exist_ok=True,parents=True)
    bpy.ops.export_scene.gltf(filepath=str(path),export_format='GLB',use_selection=True,
        export_yup=True,export_skins=True,export_rest_position_armature=True,
        export_animations=True,export_animation_mode='NLA_TRACKS',export_frame_range=False,
        export_anim_slide_to_zero=True,export_force_sampling=True,export_def_bones=False,
        export_materials='EXPORT',export_cameras=False,export_lights=False)


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--publish-open',action='store_true')
    parser.add_argument('--blend',type=Path,default=HERE/'Arthurian_Hound.blend')
    parser.add_argument('--glb',type=Path,default=PACKAGE/'export/arthurian_hound.glb')
    args=parser.parse_args(sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else [])
    if args.publish_open:
        pieces=[o for o in bpy.context.scene.objects if o.type=='MESH' and o.get('joint')]
        publish(bpy.data.objects['Hound rig'],pieces,args.glb)
        return
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.preferences.filepaths.save_version=0
    scene=bpy.context.scene
    scene.render.fps=rig.FPS
    scene.unit_settings.system='METRIC'
    body.build()
    head.build()
    pieces=[o for o in scene.objects if o.type=='MESH' and o.get('joint')]
    for piece in pieces:
        for vertex in piece.data.vertices:
            vertex.co *= rig.SCALE
        for modifier in piece.modifiers:
            if modifier.type=='BEVEL':
                modifier.width *= rig.SCALE
    skeleton=rig.create(pieces)
    bpy.context.view_layer.update()
    bpy.ops.object.select_all(action='DESELECT')
    skeleton.select_set(True)
    bpy.context.view_layer.objects.active=skeleton
    for area in bpy.context.screen.areas:
        if area.type=='VIEW_3D':
            view=area.spaces.active
            view.region_3d.view_location=(0,0,.64)
            view.region_3d.view_distance=2.8
            view.region_3d.view_rotation=Vector((1.35,-1,.18)).to_track_quat('Z','Y')
            view.region_3d.view_perspective='ORTHO'
            view.shading.color_type='MATERIAL'
            view.overlay.show_overlays=False
    args.blend.parent.mkdir(exist_ok=True,parents=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(args.blend),compress=True)
    publish(skeleton,pieces,args.glb)


if __name__=='__main__': main()
