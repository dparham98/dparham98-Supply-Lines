"""Render the editable field in its working state, plus a close view of one irrigator."""
import argparse
from pathlib import Path
import sys

import bpy
from mathutils import Vector

HERE=Path(__file__).resolve().parent


def activate(clip,frame):
    for ob in bpy.context.scene.objects:
        if ob.animation_data:
            ob.animation_data.action=None
            for t in ob.animation_data.nla_tracks:
                t.mute=t.name!=clip
    bpy.context.scene.frame_set(frame)
    bpy.context.view_layer.update()


def softbox(scene,name,loc,target,color,power,size):
    data=bpy.data.lights.new(name,'AREA')
    data.energy=power
    data.shape="DISK"
    data.size=size
    data.color=color
    ob=bpy.data.objects.new(name,data)
    scene.collection.objects.link(ob)
    ob.location=loc
    ob.rotation_euler=(Vector(target)-ob.location).to_track_quat('-Z','Y').to_euler()


def run():
    parser=argparse.ArgumentParser()
    parser.add_argument('--out',type=Path,default=HERE.parents[2]/"Previews/Farm")
    parser.add_argument('--quick',action='store_true')
    args=parser.parse_args(sys.argv[sys.argv.index("--")+1:] if "--" in sys.argv else [])
    args.out.mkdir(parents=True,exist_ok=True)
    scene=bpy.context.scene
    bpy.context.view_layer.layer_collection.children['farm_death_fx'].exclude=True
    scene.render.engine='CYCLES'
    scene.cycles.samples=10 if args.quick else 40
    scene.cycles.use_denoising=True
    scene.render.image_settings.file_format='PNG'
    scene.render.film_transparent=False
    scene.view_settings.view_transform='AgX'
    scene.view_settings.look='AgX - Medium High Contrast'
    scene.render.resolution_percentage=100
    world=scene.world or bpy.data.worlds.new("Clear studio morning")
    scene.world=world
    world.use_nodes=True
    background=world.node_tree.nodes.get("Background")
    background.inputs[0].default_value=(.64,.72,.86,1)
    background.inputs[1].default_value=.48
    floor=bpy.data.materials.new('Warm grey review background')
    floor.diffuse_color=(.25,.225,.20,1)
    bpy.ops.mesh.primitive_plane_add(size=200,location=(0,0,-.006))
    bpy.context.object.data.materials.append(floor)
    softbox(scene,'Morning',(-5,-5,11),(0,0,0),(1,.88,.69),2000,6)
    softbox(scene,'Sky',(4.5,3,9),(0,0,0),(.69,.8,1),1450,6)
    softbox(scene,'Grape backlight',(-5,6,5),(0,0,0),(1,.86,.58),1050,5)
    cam_data=bpy.data.cameras.new("Review Camera")
    camera=bpy.data.objects.new("Review Camera",cam_data)
    scene.collection.objects.link(camera)
    scene.camera=camera
    cam_data.type='ORTHO'
    activate("Work",62)
    def shot(filename,target,direction,scale,width,height):
        camera.location=Vector(target)+Vector(direction)
        camera.rotation_euler=(-Vector(direction)).to_track_quat('-Z','Y').to_euler()
        cam_data.ortho_scale=scale
        scene.render.resolution_x=int(width*(.6 if args.quick else 1))
        scene.render.resolution_y=int(height*(.6 if args.quick else 1))
        scene.render.filepath=str(args.out/filename)
        bpy.ops.render.render(write_still=True)
    shot("vineyard.png",(0,0,.35),(10,-13.3,12.5),15.25,1320,960)
    west=bpy.data.objects["Irrigator_West"].matrix_world.translation
    shot("vineyard_irrigation.png",(west.x,west.y,.72),(3,-5.1,2.3),4.25,1056,704)
    print("VINEYARD REVIEW RENDERED",args.out)

if __name__=='__main__':run()
