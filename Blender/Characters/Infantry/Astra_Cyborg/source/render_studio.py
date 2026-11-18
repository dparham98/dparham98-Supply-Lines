"""Render the editable character in a temporary studio. Does not save the studio to the asset."""
import argparse
from math import radians
from pathlib import Path
import sys
import bpy
from mathutils import Quaternion,Vector

BASE=Path(__file__).resolve().parents[1]


def light(scene,name,pos,aim,watts,size,color):
    data=bpy.data.lights.new(name,'AREA')
    data.energy=watts
    data.shape='DISK'
    data.size=size
    data.color=color
    ob=bpy.data.objects.new(name,data)
    scene.collection.objects.link(ob)
    ob.location=pos
    ob.rotation_euler=(Vector(aim)-ob.location).to_track_quat('-Z','Y').to_euler()


def setup(quick):
    sc=bpy.context.scene
    sc.render.engine='CYCLES'
    sc.cycles.samples=9 if quick else 36
    sc.cycles.use_denoising=True
    sc.cycles.seed=17
    sc.view_settings.view_transform='AgX'
    sc.view_settings.look='AgX - Medium High Contrast'
    sc.view_settings.exposure=-.15
    sc.render.film_transparent=False
    world=bpy.data.worlds.new('Warm-grey sweep')
    world.use_nodes=True
    sky=world.node_tree.nodes['Background']
    sky.inputs[0].default_value=(.59,.64,.72,1)
    sky.inputs[1].default_value=.40
    sc.world=world
    bpy.ops.mesh.primitive_plane_add(size=200,location=(0,0,-.002))
    floor=bpy.context.object
    mat=bpy.data.materials.new('Studio canvas')
    mat.use_nodes=True
    shader=mat.node_tree.nodes['Principled BSDF']
    shader.inputs['Base Color'].default_value=(.29,.263,.224,1)
    shader.inputs['Roughness'].default_value=.96
    # A camera-visible lift on the sweep preserves the soft ground shadow at the feet.
    shader.inputs['Emission Color'].default_value=(.42,.369,.295,1)
    path=mat.node_tree.nodes.new('ShaderNodeLightPath')
    cam_glow=mat.node_tree.nodes.new('ShaderNodeMath')
    cam_glow.operation='MULTIPLY'
    cam_glow.inputs[1].default_value=.91
    mat.node_tree.links.new(path.outputs['Is Camera Ray'],cam_glow.inputs[0])
    mat.node_tree.links.new(cam_glow.outputs[0],shader.inputs['Emission Strength'])
    floor.data.materials.append(mat)
    light(sc,'High softbox',(-3,-4,5.6),(0,0,.9),570,3.8,(1,.91,.79))
    light(sc,'Camera fill',(2.8,-3.2,3.0),(0,0,1.10),310,3.1,(.79,.88,1))
    light(sc,'Shoulder strip',(1.1,2.6,3.3),(0,0,1.0),260,3.0,(1,.92,.83))
    cam=bpy.data.objects.new('Inspection camera',bpy.data.cameras.new('Inspection lens'))
    sc.collection.objects.link(cam)
    cam.data.type='ORTHO'
    sc.camera=cam
    # A relaxed presentation wrist offers a side view of the hand prop. The
    # viewport and all five exported clips retain the original gameplay poses.
    rig=bpy.data.objects['infantry_rig2']
    rig.animation_data.use_nla=False
    rig.animation_data.action=bpy.data.actions['Rest']
    sc.frame_set(1)
    pose=rig.pose.bones['hand.L']
    local_x=pose.matrix.to_quaternion().inverted()@Vector((1,0,0))
    pose.rotation_mode='QUATERNION'
    pose.rotation_quaternion=pose.rotation_quaternion @ Quaternion(local_x,radians(30))
    head=rig.pose.bones['head']
    local_up=head.matrix.to_quaternion().inverted()@Vector((0,0,1))
    head.rotation_quaternion=head.rotation_quaternion @ Quaternion(local_up,radians(8))
    bpy.context.view_layer.update()
    return sc,cam


def shot(sc,cam,where,direction,aim,ortho,size,percent):
    target=Vector(aim)
    cam.location=target+Vector(direction).normalized()*8
    cam.rotation_euler=(target-cam.location).to_track_quat('-Z','Y').to_euler()
    cam.data.ortho_scale=ortho
    sc.render.resolution_x,sc.render.resolution_y=size
    sc.render.resolution_percentage=percent
    sc.render.filepath=str(where.resolve())
    sc.render.image_settings.file_format='PNG'
    sc.render.image_settings.color_mode='RGB'
    bpy.ops.render.render(write_still=True)


if __name__=='__main__':
    parser=argparse.ArgumentParser()
    parser.add_argument('--output',type=Path,default=BASE/'preview')
    parser.add_argument('--draft',action='store_true')
    parser.add_argument('--hero-only',action='store_true')
    opts=parser.parse_args(sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else [])
    opts.output.mkdir(parents=True,exist_ok=True)
    sc,cam=setup(opts.draft)
    percent=48 if opts.draft else 100
    shot(sc,cam,opts.output/'cyborg_infantry.png',(-.32,-1,.09),(0,.02,.90),2.01,(1040,1240),percent)
    if not opts.hero_only:
        shot(sc,cam,opts.output/'rear.png',(.30,1,.14),(0,0,.90),2.03,(650,840),percent)
        shot(sc,cam,opts.output/'portrait.png',(-.31,-1,.03),(0,.004,1.51),.70,(800,700),percent)
        paint=bpy.data.materials['team_color']
        paint.node_tree.nodes['Principled BSDF'].inputs['Base Color'].default_value=(.033,.163,.41,1)
        shot(sc,cam,opts.output/'blue.png',(.40,-1,.095),(0,.016,.90),2.03,(650,840),percent)
