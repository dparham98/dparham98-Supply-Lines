"""Studio view of the saved base house. The review lights and floor stay out of the asset."""
from pathlib import Path
import bpy
from mathutils import Vector

dest=Path(__file__).resolve().parents[1]/"preview"/"house.png"
scene=bpy.context.scene
scene.render.engine="CYCLES"
scene.cycles.samples=28
scene.cycles.use_denoising=True
scene.render.resolution_x=920
scene.render.resolution_y=860
scene.render.resolution_percentage=100
scene.render.image_settings.file_format="PNG"
scene.view_settings.view_transform="AgX"
scene.world=bpy.data.worlds.new("Cloud daylight")
scene.world.use_nodes=True
bg=scene.world.node_tree.nodes["Background"]
bg.inputs[0].default_value=(.68,.74,.86,1)
bg.inputs[1].default_value=.43

def area(name,at,target,color,power,diameter):
    light=bpy.data.lights.new(name,"AREA")
    light.energy=power
    light.shape="DISK"
    light.size=diameter
    light.color=color
    ob=bpy.data.objects.new(name,light)
    scene.collection.objects.link(ob)
    ob.location=at
    ob.rotation_euler=(Vector(target)-ob.location).to_track_quat("-Z","Y").to_euler()

area("Late sun",(3.4,2.7,6.8),(0,0,1.5),(1,.87,.69),830,4.6)
area("Daylight",(-3.1,4.2,4.3),(0,0,1.5),(.84,.91,1),385,5)
area("Skylight",(3.5,-4.5,5.9),(0,0,2.1),(.85,.91,1),560,4)
bpy.ops.mesh.primitive_plane_add(size=200,location=(0,0,-.01))
ground=bpy.context.object
ground.data.materials.append(bpy.data.materials.new("Studio warm stone"))
ground.active_material.diffuse_color=(.275,.26,.237,1)
cam=bpy.data.objects.new("Camera",bpy.data.cameras.new("Studio camera"))
scene.collection.objects.link(cam)
cam.data.type="ORTHO"
cam.data.ortho_scale=6.3
center=Vector((0,0,1.71))
cam.location=center+Vector((5.30,7.95,3.34))
cam.rotation_euler=(center-cam.location).to_track_quat("-Z","Y").to_euler()
scene.camera=cam
scene.render.filepath=str(dest)
dest.parent.mkdir(exist_ok=True)
bpy.ops.render.render(write_still=True)
