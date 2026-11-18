"""Export the current editable character, including its five accepted NLA clips."""
from pathlib import Path
import bpy


def export(destination):
    rig=bpy.data.objects['infantry_rig2']
    ad=rig.animation_data
    previous_action,previous_nla=ad.action,ad.use_nla
    original_selection=list(bpy.context.selected_objects)
    active=bpy.context.view_layer.objects.active
    body=None
    generated=[]
    try:
        ad.action=None
        ad.use_nla=True
        bpy.ops.object.select_all(action='DESELECT')
        # The game addresses these props separately. All other skinned assemblies
        # can share one export mesh and one team paint slot across the entire body.
        separate={'pistol_rig','chainsaw_rig','chainsaw_teeth_rig','eye_lens_rig','Muzzle flash','Muzzle light'}
        children=sorted(rig.children_recursive,key=lambda obj:obj.name)
        for obj in children:
            if obj.type!='MESH' or obj.name in separate: continue
            part=obj.copy()
            part.data=obj.data.copy()
            generated.append(part.data)
            bpy.context.scene.collection.objects.link(part)
            part.select_set(True)
            if body is None: body=part
        if body is None: raise ValueError("No character geometry to export")
        bpy.context.view_layer.objects.active=body
        bpy.ops.object.join()
        body.name='infantry_cyborg_rig'
        body.data.name='Cyborg field uniform and head'
        for obj in [rig,body]+[o for o in children if o.name in separate]:
            obj.select_set(True)
        bpy.context.view_layer.objects.active=rig
        destination.parent.mkdir(parents=True,exist_ok=True)
        bpy.ops.export_scene.gltf(filepath=str(destination),export_format='GLB',
            use_selection=True,export_apply=True,export_yup=True,export_lights=True,
            export_cameras=False,export_animations=True,export_animation_mode='NLA_TRACKS',
            export_def_bones=False,export_force_sampling=True,export_optimize_animation_size=False,
            export_skins=True,export_materials='EXPORT')
    finally:
        if body is not None: bpy.data.objects.remove(body,do_unlink=True)
        for mesh in generated:
            if mesh.users==0: bpy.data.meshes.remove(mesh)
        ad.use_nla=previous_nla
        ad.action=previous_action
        bpy.context.scene.frame_set(1)
        bpy.ops.object.select_all(action='DESELECT')
        for obj in original_selection: obj.select_set(True)
        bpy.context.view_layer.objects.active=active


if __name__=='__main__': export(Path(__file__).resolve().parents[1]/'export/infantry.glb')
