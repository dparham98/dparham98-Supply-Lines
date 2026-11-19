"""Render the editable source against a warm matte sweep without saving the studio into it."""
from pathlib import Path
import bpy
from mathutils import Vector


def area(scene, name, position, aim, watts, width, color):
    data = bpy.data.lights.new(name, 'AREA')
    data.shape, data.size, data.energy, data.color = 'DISK', width, watts, color
    obj = bpy.data.objects.new(name,data)
    scene.collection.objects.link(obj)
    obj.location = position
    obj.rotation_euler = (Vector(aim)-obj.location).to_track_quat('-Z','Y').to_euler()


def render(destination, draft=False):
    scene = bpy.context.scene
    scene.render.engine = 'CYCLES'
    scene.cycles.samples = 9 if draft else 48
    scene.cycles.use_denoising = True
    scene.view_settings.view_transform = 'AgX'
    scene.view_settings.look = 'AgX - Medium High Contrast'
    world = bpy.data.worlds.new('Warm grey sweep')
    world.use_nodes = True
    bg = world.node_tree.nodes['Background']
    bg.inputs['Color'].default_value = (.73,.75,.80,1)
    bg.inputs['Strength'].default_value = .40
    scene.world = world
    bpy.ops.mesh.primitive_plane_add(size=200, location=(0,0,-.016))
    floor = bpy.context.object
    material = bpy.data.materials.new('Studio floor')
    material.use_nodes = True
    bs = material.node_tree.nodes['Principled BSDF']
    bs.inputs['Base Color'].default_value = (.39,.35,.30,1)
    bs.inputs['Roughness'].default_value = .95
    floor.data.materials.append(material)
    area(scene,'Key',(-6,-9,12),(0,0,1.6),1950,7.5,(1,.89,.76))
    area(scene,'Fill',(8,-5,6),(0,-.3,1.5),995,7.0,(.83,.90,1))
    area(scene,'Rim',(2,7,10),(0,1.0,1.8),2300,6.0,(1,.90,.76))
    camera = bpy.data.objects.new('Studio camera',bpy.data.cameras.new('Studio camera'))
    scene.collection.objects.link(camera)
    target = Vector((0,-.62,1.65))
    camera.location = target + Vector((.53,-1,.52)).normalized()*23
    camera.rotation_euler = (target-camera.location).to_track_quat('-Z','Y').to_euler()
    camera.data.type = 'ORTHO'
    camera.data.ortho_scale = 10.85
    scene.camera = camera
    scene.render.resolution_x,scene.render.resolution_y = (1260,980)
    scene.render.resolution_percentage = 55 if draft else 100
    scene.render.image_settings.color_mode = 'RGB'
    scene.render.filepath = str(destination.resolve())
    bpy.ops.render.render(write_still=True)


if __name__ == '__main__':
    preview = Path(__file__).resolve().parents[1] / 'preview'
    preview.mkdir(exist_ok=True)
    render(preview / 'bastion_studio.png')
