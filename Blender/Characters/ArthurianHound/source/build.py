"""Build the Arthurian hound and export the assembled rig."""
from pathlib import Path
import sys
import bpy

HERE=Path(__file__).resolve().parent
PACKAGE=HERE.parent
sys.dont_write_bytecode=True
sys.path.insert(0,str(HERE))
import body,head,rig

def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.preferences.filepaths.save_version=0
    bpy.context.scene.render.fps=24
    body.build()
    head.build()
    pieces=[o for o in bpy.context.scene.objects if o.type=='MESH' and o.get("joint")]
    # Scale geometry and bind positions together so the game sees a one-unit
    # armature transform and a hound proportionate to the marines.
    for piece in pieces:
        for vertex in piece.data.vertices:
            vertex.co *= .78
        for modifier in piece.modifiers:
            if modifier.type=='BEVEL':
                modifier.width *= .78
    skeleton=rig.create(pieces)
    bpy.context.view_layer.update()
    bpy.ops.object.select_all(action='DESELECT')
    skeleton.select_set(True)
    bpy.context.view_layer.objects.active=skeleton
    for area in bpy.context.screen.areas:
        if area.type=='VIEW_3D':
            from mathutils import Vector
            area.spaces.active.region_3d.view_location=(0,0,.60)
            area.spaces.active.region_3d.view_distance=3.6
            area.spaces.active.region_3d.view_rotation=Vector((-.65,-1,.35)).to_track_quat('Z','Y')
            area.spaces.active.shading.color_type='MATERIAL'
    bpy.ops.wm.save_as_mainfile(filepath=str(HERE/"Arthurian_Hound.blend"),compress=True)
    for obj in pieces: obj.select_set(True)
    skeleton.select_set(True)
    skeleton.animation_data.action=None
    skeleton.animation_data.use_nla=True
    path=PACKAGE/"export"/"arthurian_hound.glb"
    path.parent.mkdir(exist_ok=True,parents=True)
    bpy.ops.export_scene.gltf(filepath=str(path),export_format='GLB',use_selection=True,
        export_yup=True,export_skins=True,export_animations=True,export_animation_mode='NLA_TRACKS',
        export_def_bones=False,export_materials='EXPORT',export_apply=True,
        export_cameras=False,export_lights=False)

if __name__=="__main__": main()
