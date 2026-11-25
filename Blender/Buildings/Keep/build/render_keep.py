"""Studio hero render from the actual Keep mesh. Usage: blender -b Keep.blend -P build/render_keep.py"""
from pathlib import Path
import sys

import bpy
from mathutils import Vector


root=Path(__file__).resolve().parents[3]
args=sys.argv[sys.argv.index("--")+1:] if "--" in sys.argv else []
out=Path(args[0]) if args else root/"Previews"/"Keep"/"keep.png"
test=len(args)>1 and args[1]=="draft"
out.parent.mkdir(exist_ok=True,parents=True)
scene=bpy.context.scene
scene.render.engine="CYCLES"
scene.cycles.samples=9 if test else 42
scene.cycles.use_denoising=True
scene.render.resolution_percentage=100
scene.render.resolution_x=720 if test else 1440
scene.render.resolution_y=562 if test else 1124
scene.render.image_settings.file_format="PNG"
scene.render.image_settings.color_mode="RGB"
scene.view_settings.view_transform="AgX"
scene.view_settings.look="AgX - Medium High Contrast"
scene.world=bpy.data.worlds.new("Cloud fill")
scene.world.use_nodes=True
bg=scene.world.node_tree.nodes["Background"]
bg.inputs[0].default_value=(.73,.78,.87,1)
bg.inputs[1].default_value=.45
for ob in bpy.data.collections["keep"].all_objects:
    if ob.animation_data:
        ob.animation_data.action=None
        for track in ob.animation_data.nla_tracks:
            track.mute=track.name!="Idle"
scene.frame_set(12)
fx=bpy.context.view_layer.layer_collection.children.get("keep_death_fx")
if fx: fx.exclude=True
def area(name,position,power,size,rgb):
    bpy.ops.object.light_add(type="AREA",location=position)
    lamp=bpy.context.object
    lamp.name=name
    lamp.data.energy=power
    lamp.data.shape="DISK"
    lamp.data.size=size
    lamp.data.color=rgb
    lamp.rotation_euler=(Vector((0,0,2.9))-lamp.location).to_track_quat("-Z","Y").to_euler()

area("Daylight",(-9,-10,17),4900,11,(1,.89,.77))
area("Front softbox",(8,-15,8),2100,11,(.81,.88,1))
area("Edge light",(8,10,13),5200,10,(1,.89,.70))
bpy.ops.mesh.primitive_plane_add(size=200,location=(0,0,-.004))
floor=bpy.context.object
mat=bpy.data.materials.new("Warm gray background")
mat.use_nodes=True
mat.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value=(.19,.173,.151,1)
mat.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value=.82
floor.data.materials.append(mat)
bpy.ops.object.camera_add(location=(-12.7,-19.8,12.5))
camera=bpy.context.object
camera.rotation_euler=(Vector((0,0,3.0))-camera.location).to_track_quat("-Z","Y").to_euler()
camera.data.type="ORTHO"
camera.data.ortho_scale=15
scene.camera=camera
scene.render.filepath=str(out)
bpy.ops.render.render(write_still=True)
