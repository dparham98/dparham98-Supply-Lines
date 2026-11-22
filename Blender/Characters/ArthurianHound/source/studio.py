"""Render the saved hound using its exported geometry and studio lighting."""
from pathlib import Path
import argparse
import sys
import bpy
from mathutils import Vector

PACKAGE=Path(__file__).resolve().parent.parent

def light(name,loc,target,energy,size,color):
    data=bpy.data.lights.new(name,'AREA')
    data.energy=energy
    data.shape='DISK'
    data.size=size
    data.color=color
    obj=bpy.data.objects.new(name,data)
    bpy.context.scene.collection.objects.link(obj)
    obj.location=loc
    obj.rotation_euler=(Vector(target)-obj.location).to_track_quat('-Z','Y').to_euler()

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--asset',type=Path,default=PACKAGE/'export/arthurian_hound.glb')
    parser.add_argument('--output',type=Path,default=PACKAGE/'preview')
    parser.add_argument('--draft',action='store_true')
    args=parser.parse_args(sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else [])
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(args.asset))
    scene=bpy.context.scene
    skeleton=next(o for o in scene.objects if o.type=='ARMATURE')
    skeleton.animation_data.use_nla=False
    skeleton.animation_data.action=bpy.data.actions['Rest']
    scene.frame_set(1)
    scene.render.engine='CYCLES'
    scene.cycles.samples=10 if args.draft else 56
    scene.cycles.use_denoising=True
    scene.view_settings.view_transform='AgX'
    scene.view_settings.look='AgX - Medium High Contrast'
    scene.view_settings.exposure=-.20
    world=bpy.data.worlds.new('Ambient studio')
    world.use_nodes=True
    world.node_tree.nodes['Background'].inputs[0].default_value=(.40,.44,.51,1)
    world.node_tree.nodes['Background'].inputs[1].default_value=.42
    scene.world=world
    bpy.ops.mesh.primitive_plane_add(size=200)
    floor=bpy.context.object
    mat=bpy.data.materials.new('Slate studio')
    mat.diffuse_color=(.100,.098,.092,1)
    mat.use_nodes=True
    bs=mat.node_tree.nodes.get('Principled BSDF')
    bs.inputs['Base Color'].default_value=mat.diffuse_color
    bs.inputs['Roughness'].default_value=.85
    floor.data.materials.append(mat)
    light('Overhead softbox',(1.3,-2.5,3.6),(0,-.10,.68),275,2.65,(1,.91,.80))
    light('Cool fill',(-1.85,-1.9,2),(0,-.35,.8),125,2.5,(.73,.84,1))
    light('Portrait bounce',(2.15,-.15,1.5),(0,-.12,.76),58,2.15,(.86,.93,1))
    light('Armour edge',(-1.15,1.75,2.9),(0,.15,.78),215,1.9,(1,.95,.86))
    camera=bpy.data.objects.new('Camera',bpy.data.cameras.new('Portrait lens'))
    scene.collection.objects.link(camera)
    scene.camera=camera
    camera.data.type='ORTHO'
    preview=args.output
    preview.mkdir(exist_ok=True,parents=True)
    for name,target,direction,scale,size in [
        ('hound',(0,-.015,.64),(1.17,-1.07,.18),2.30,(1320,880)),
        ('portrait',(0,-.536,.985),(.92,-1,.13),.81,(960,880)),
        ('rear',(0,.005,.64),(-1.20,.98,.28),2.15,(1080,840))]:
        target=Vector(target)
        camera.location=target+Vector(direction).normalized()*6
        camera.rotation_euler=(target-camera.location).to_track_quat('-Z','Y').to_euler()
        camera.data.ortho_scale=scale
        scene.render.resolution_x,scene.render.resolution_y=size
        scene.render.resolution_percentage=48 if args.draft else 100
        scene.render.filepath=str(preview/(name+'.png'))
        bpy.ops.render.render(write_still=True)

if __name__=='__main__': main()
