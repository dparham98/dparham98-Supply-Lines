"""Studio and renders for the delivered model. All preview images use the exported GLB."""
import argparse
from math import cos, pi, sin
from pathlib import Path
import sys

import bpy
from mathutils import Matrix, Vector

PACKAGE=Path(__file__).resolve().parents[1]

def aim(obj,at):
    obj.rotation_euler=(Vector(at)-obj.location).to_track_quat("-Z","Y").to_euler()

def light(coll,name,location,target,power,size,color):
    data=bpy.data.lights.new(name,"AREA")
    data.shape="DISK"
    data.size=size
    data.energy=power
    data.color=color
    ob=bpy.data.objects.new(name,data)
    coll.objects.link(ob)
    ob.location=location
    aim(ob,target)

def place_camera(scene,at,direction,scale,size):
    c=scene.camera
    c.location=Vector(at)+Vector(direction).normalized()*6.0
    aim(c,at)
    c.data.ortho_scale=scale
    scene.render.resolution_x,scene.render.resolution_y=size

def stage(scene):
    coll=bpy.data.collections.new("Studio")
    scene.collection.children.link(coll)
    scene.render.engine="CYCLES"
    scene.cycles.samples=40
    scene.cycles.use_denoising=True
    scene.cycles.seed=19
    scene.world=bpy.data.worlds.new("Studio skylight")
    scene.world.use_nodes=True
    amb=scene.world.node_tree.nodes["Background"]
    amb.inputs[0].default_value=(.65,.73,.84,1)
    amb.inputs[1].default_value=.23
    light(coll,"Linen softbox",(-2.0,-3.0,3.5),(0,0,1.12),200,2.2,(1.,.84,.67))
    light(coll,"North window",(2.1,-1.75,2.35),(0,0,1.25),109,2.8,(.72,.83,1.0))
    light(coll,"Gold rim",(.6,1.55,2.8),(0,0,1.30),235,1.32,(1.,.76,.51))
    light(coll,"Eye catch",(.24,-2.3,1.64),(0,0,1.60),6,.62,(1,.91,.78))
    scene.view_settings.view_transform="AgX"
    scene.view_settings.look="AgX - Medium High Contrast"
    scene.render.image_settings.file_format="PNG"
    cam=bpy.data.objects.new("Studio lens",bpy.data.cameras.new("Studio lens"))
    coll.objects.link(cam)
    cam.data.type="ORTHO"
    scene.camera=cam
    place_camera(scene,(-.075,0,.875),(.18,-1,.105),1.99,(1000,1200))
    # A swept floor gives both front and rear views a soft horizon.
    section=[(-7,-.002),(1.1,-.002)]
    for i in range(1,27):
        t=pi/2*i/26
        section.append((1.1+2.7*sin(t),-.002+2.7*(1-cos(t))))
    section.append((3.8,18))
    vertices=[(x,y,z) for y,z in section for x in (-20,20)]
    faces=[(2*i,2*i+1,2*i+3,2*i+2) for i in range(len(section)-1)]
    mesh=bpy.data.meshes.new("Cyclorama")
    mesh.from_pydata(vertices,[],faces)
    for p in mesh.polygons:
        p.use_smooth=True
    cloth=bpy.data.materials.new("Smoked slate studio")
    cloth.use_nodes=True
    principled=cloth.node_tree.nodes["Principled BSDF"]
    principled.inputs["Base Color"].default_value=(.032,.043,.050,1)
    principled.inputs["Roughness"].default_value=.9
    mesh.materials.append(cloth)
    sweep=bpy.data.objects.new("Studio floor",mesh)
    coll.objects.link(sweep)
    return sweep

def shot(scene,path):
    scene.render.filepath=str(path)
    bpy.ops.render.render(write_still=True)

def portrait_lights(scene):
    key=scene.objects["Linen softbox"]
    key.location=(1.33,-1.86,2.70)
    aim(key,(0,-.02,1.59))
    key.data.energy,key.data.size=94,1.34
    fill=scene.objects["North window"]
    fill.location=(-1.8,-2.04,1.99)
    aim(fill,(0,0,1.57))
    fill.data.energy,fill.data.size=57,2.1
    rim=scene.objects["Gold rim"]
    rim.location=(-.42,1.6,2.52)
    aim(rim,(0,0,1.54))
    rim.data.energy=119

def pose_worker(root,clip=None,frame=0,farm=False):
    sys.path.insert(0,str(Path(__file__).resolve().parent))
    from outfit import BONES,shown
    for obj in root.children_recursive:
        data=obj.animation_data
        if data:
            data.use_nla=False
            data.action=bpy.data.actions[clip] if clip else None
            if clip:
                slot=next((s for s in data.action.slots if s.identifier=="OB"+obj.name),None)
                if slot:
                    data.action_slot=slot
        if obj.type=="ARMATURE":
            obj.data.pose_position="POSE" if clip else "REST"
        if obj.name in BONES and not clip:
            obj.scale=(1,1,1)
            obj.hide_render=not shown(obj.name,"Till" if farm else None)
        elif obj.name in BONES:
            obj.hide_render=not shown(obj.name,clip)
    bpy.context.scene.frame_set(frame)

def render(glb,dest,draft=False,views=("figure","portrait","back")):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene=bpy.context.scene
    floor=stage(scene)
    bpy.ops.import_scene.gltf(filepath=str(glb))
    roots=[o for o in scene.objects if o.parent is None and o.name=="Forester Maiden"]
    if len(roots)!=1:
        raise ValueError("Missing character root")
    pose_worker(roots[0])
    dest.mkdir(parents=True,exist_ok=True)
    scene.cycles.samples=9 if draft else 46
    scene.render.resolution_percentage=50 if draft else 100
    if "figure" in views:
        shot(scene,dest/"forester_maiden.png")
    if "back" in views:
        front=roots[0].matrix_world.copy()
        roots[0].matrix_world=Matrix.Rotation(pi,4,"Z") @ front
        place_camera(scene,(.045,0,.875),(-.36,-1,.12),1.99,(900,1080))
        shot(scene,dest/"forester_maiden_back.png")
        roots[0].matrix_world=front
    if "farm" in views:
        pose_worker(roots[0],farm=True)
        place_camera(scene,(-.075,0,.9),(-.10,-1,.09),2.04,(1000,1200))
        shot(scene,dest/"farm_assignment.png")
        pose_worker(roots[0])
    if "delivery" in views:
        pose_worker(roots[0],"CarryFood",6)
        place_camera(scene,(0,-.05,.84),(.39,-1,.20),1.90,(830,1000))
        shot(scene,dest/"farm_delivery.png")
        pose_worker(roots[0])
    if "basket" in views:
        for obj in roots[0].children_recursive:
            if obj.type == 'MESH':
                obj.hide_render = obj.name not in {"FoodBasket", "HarvestGrapes"}
                if obj.name in {"FoodBasket", "HarvestGrapes"}:
                    obj.scale=(1,1,1)
        floor.hide_render=True
        scene.render.film_transparent=True
        place_camera(scene,(0,-.305,1.04),(.58,-1,.68),.56,(840,650))
        shot(scene,dest/"farm_basket.png")
        floor.hide_render=False
        scene.render.film_transparent=False
        for obj in roots[0].children_recursive:
            if obj.type == 'MESH':
                obj.hide_render=False
        pose_worker(roots[0])
    if "portrait" in views:
        portrait_lights(scene)
        floor.hide_render=True
        # The top corner of the axe falls into the bottom of this tight crop.
        # Isolate the upper body for the unit portrait.
        tool=next((o for o in roots[0].children_recursive if o.name=="WoodcuttingAxe"),None)
        if tool:
            tool.hide_render=True
        scene.render.film_transparent=True
        scene.render.image_settings.color_mode="RGBA"
        place_camera(scene,(0,-.015,1.566),(-.61,-1,.030),.385,(860,1000))
        shot(scene,dest/"forester_maiden_portrait.png")
        scene.render.film_transparent=False
        floor.hide_render=False

if __name__=="__main__":
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--model",type=Path,default=PACKAGE/"export/forester_maiden.glb")
    parser.add_argument("--output",type=Path,default=PACKAGE/"preview")
    parser.add_argument("--draft",action="store_true")
    parser.add_argument("--views",nargs="+",default=["figure","portrait","back"])
    args=parser.parse_args(sys.argv[sys.argv.index("--")+1:] if "--" in sys.argv else [])
    render(args.model,args.output,args.draft,args.views)
