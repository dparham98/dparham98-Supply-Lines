"""Render the saved hound using its exported geometry and studio lighting."""
from pathlib import Path
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
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(PACKAGE/'export/arthurian_hound.glb'))
    scene=bpy.context.scene
    scene.render.engine='CYCLES'
    scene.cycles.samples=40
    scene.cycles.use_denoising=True
    scene.view_settings.view_transform='AgX'
    scene.view_settings.look='AgX - Medium High Contrast'
    world=bpy.data.worlds.new('Ambient studio')
    world.use_nodes=True
    world.node_tree.nodes['Background'].inputs[0].default_value=(.32,.35,.40,1)
    world.node_tree.nodes['Background'].inputs[1].default_value=.48
    scene.world=world
    bpy.ops.mesh.primitive_plane_add(size=200)
    floor=bpy.context.object
    mat=bpy.data.materials.new('Slate studio')
    mat.diffuse_color=(.14,.145,.15,1)
    mat.use_nodes=True
    bs=mat.node_tree.nodes.get('Principled BSDF')
    bs.inputs['Base Color'].default_value=mat.diffuse_color
    bs.inputs['Roughness'].default_value=.85
    floor.data.materials.append(mat)
    light('Key',(-3,-4,5),(0,0,.6),500,4,(1,.9,.75))
    light('Fill',(3,-2,3),(0,0,.7),310,3,(.73,.84,1))
    light('Rim',(0,3,4),(0,0,.7),450,2.5,(1,.91,.78))
    camera=bpy.data.objects.new('Camera',bpy.data.cameras.new('Portrait lens'))
    scene.collection.objects.link(camera)
    scene.camera=camera
    camera.data.type='ORTHO'
    preview=PACKAGE/'preview'
    preview.mkdir(exist_ok=True,parents=True)
    for name,target,direction,scale,size in [
        ('hound',(0,0,.64),(-1,-1.4,.60),1.95,(1080,1080)),
        ('portrait',(0,-.54,1.0),(-.65,-1,.20),1.0,(900,900)),
        ('rear',(0,0,.64),(.7,1,.48),2.25,(900,900))]:
        target=Vector(target)
        camera.location=target+Vector(direction).normalized()*6
        camera.rotation_euler=(target-camera.location).to_track_quat('-Z','Y').to_euler()
        camera.data.ortho_scale=scale
        scene.render.resolution_x,scene.render.resolution_y=size
        scene.render.resolution_percentage=100
        scene.render.filepath=str(preview/(name+'.png'))
        bpy.ops.render.render(write_still=True)

if __name__=='__main__': main()
