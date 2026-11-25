"""Open House.blend in Blender 4.5 and run this script to publish the game rig."""
from pathlib import Path

import bpy

dest=Path(__file__).resolve().parents[1]/"export"/"house.glb"
root=bpy.data.objects["House"]
objects=[root,*root.children_recursive]
bpy.ops.object.select_all(action="DESELECT")
for ob in objects:
    ob.select_set(True)
    if ob.animation_data:
        for track in ob.animation_data.nla_tracks:
            track.mute=False
bpy.context.view_layer.objects.active=root
bpy.context.scene.frame_set(0)
dest.parent.mkdir(exist_ok=True)
bpy.ops.export_scene.gltf(filepath=str(dest),export_format="GLB",use_selection=True,
    export_apply=True,export_yup=True,export_normals=True,export_materials="EXPORT",
    export_texcoords=True,export_image_format="JPEG",export_jpeg_quality=85,
    export_animations=True,export_animation_mode="NLA_TRACKS",
    export_force_sampling=True,export_optimize_animation_size=False,export_cameras=False,
    export_lights=False,export_extras=False,export_optimize_animation_keep_anim_object=True)
print("HOUSE_EXPORTED",dest,dest.stat().st_size)
