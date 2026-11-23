"""Render the game GLB in a warm, neutral studio at three viewing distances."""
import argparse
from math import atan2, cos, pi, sin
from pathlib import Path
import sys
import bpy
from mathutils import Vector


def aim(obj, target):
    obj.rotation_euler=(Vector(target)-obj.location).to_track_quat("-Z","Y").to_euler()


def camera(scene, center, direction, size, resolution):
    cam=scene.camera
    cam.location=Vector(center)+Vector(direction).normalized()*17
    aim(cam,center)
    cam.data.ortho_scale=size
    scene.objects["Studio sweep"].rotation_euler.z=atan2(direction[0],-direction[1])
    scene.render.resolution_x,scene.render.resolution_y=resolution


def stage(scene):
    collection=bpy.data.collections.new("Portrait studio")
    scene.collection.children.link(collection)
    world=bpy.data.worlds.new("Overcast skylight")
    world.use_nodes=True
    scene.world=world
    world.node_tree.nodes["Background"].inputs[0].default_value=(.72,.77,.86,1)
    world.node_tree.nodes["Background"].inputs[1].default_value=.29
    def softbox(name,location,energy,size,tint):
        light=bpy.data.lights.new(name,"AREA")
        light.shape="DISK"
        light.size=size
        light.energy=energy
        light.color=tint
        ob=bpy.data.objects.new(name,light)
        collection.objects.link(ob)
        ob.location=location
        aim(ob,(0,-.09,2.83))
    softbox("Key | broad amber",(-4.7,-5.4,8.4),1200,5.2,(1,.86,.71))
    softbox("Fill | pearl",(5.1,-3.5,4.7),450,4.1,(.77,.85,1))
    softbox("Rim | high edge",(1.75,3.0,7.2),1150,3.6,(1,.80,.60))
    softbox("Soft face card",(0,-6.7,3.1),140,3.5,(1,.89,.79))
    ground=bpy.data.materials.new("Studio | warm umber")
    ground.diffuse_color=(.23,.186,.147,1)
    ground.use_nodes=True
    surf=ground.node_tree.nodes.get("Principled BSDF")
    surf.inputs["Base Color"].default_value=ground.diffuse_color
    surf.inputs["Roughness"].default_value=.94
    section=[(-80,-.007),(4,-.007)]
    for i in range(1,25):
        a=pi/2*i/24
        section.append((4+8*sin(a),-.007+8*(1-cos(a))))
    section.append((12,50))
    verts=[(x,y,z) for y,z in section for x in (-100,100)]
    data=bpy.data.meshes.new("Studio sweep")
    data.from_pydata(verts,[],[(2*i,2*i+1,2*i+3,2*i+2) for i in range(len(section)-1)])
    for p in data.polygons:
        p.use_smooth=True
    data.materials.append(ground)
    collection.objects.link(bpy.data.objects.new("Studio sweep",data))
    cam=bpy.data.objects.new("Studio lens",bpy.data.cameras.new("Studio lens"))
    collection.objects.link(cam)
    scene.camera=cam
    cam.data.type="ORTHO"
    scene.render.engine="CYCLES"
    scene.cycles.use_denoising=True
    try:
        pref=bpy.context.preferences.addons["cycles"].preferences
        pref.compute_device_type="OPTIX"
        pref.refresh_devices()
        if any(d.type=="OPTIX" for d in pref.devices):
            for device in pref.devices:
                device.use=device.type=="OPTIX"
            scene.cycles.device="GPU"
            scene.cycles.denoiser="OPTIX"
    except (ValueError,RuntimeError):
        pass
    scene.view_settings.view_transform="AgX"
    scene.view_settings.look="AgX - Medium High Contrast"
    scene.render.image_settings.file_format="PNG"
    scene.render.resolution_percentage=100


def render(args):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene=bpy.context.scene
    if args.raw:
        import arms,body,head,legs
        for component in (body,arms,legs,head):
            component.build()
    else:
        bpy.ops.import_scene.gltf(filepath=str(args.model))
        for arm in (o for o in scene.objects if o.type=="ARMATURE"):
            arm.data.pose_position="REST"
    stage(scene)
    scene.cycles.samples=8 if args.draft else 48
    views={
        "ubermech":((-.035,-.08,2.53),(-.36,-1,.135),5.85,(1080,1080)),
        "portrait":((-.009,-.15,4.72),(-.27,-1,.10),1.35,(880,780)),
        "rear":((0,.01,2.53),(.63,1,.28),5.94,(850,880)),
        "gameplay_distance":((0,0,2.08),(-.63,-.83,1.06),12.8,(640,520)),
    }
    args.output.mkdir(parents=True,exist_ok=True)
    for view in args.views:
        camera(scene,*views[view])
        scene.render.resolution_percentage=62 if args.draft else 100
        scene.render.filepath=str(args.output/(view+".png"))
        bpy.ops.render.render(write_still=True)


if __name__=="__main__":
    source=Path(__file__).resolve().parent
    sys.path.insert(0,str(source))
    sys.dont_write_bytecode=True
    parser=argparse.ArgumentParser()
    parser.add_argument("--model",type=Path,default=source.parents[3]/"assets/models/units/ubermech.glb")
    parser.add_argument("--output",type=Path,default=source.parent/"preview")
    parser.add_argument("--raw",action="store_true")
    parser.add_argument("--draft",action="store_true")
    parser.add_argument("--views",nargs="+",default=["ubermech","portrait","rear","gameplay_distance"])
    render(parser.parse_args(sys.argv[sys.argv.index("--")+1:] if "--" in sys.argv else []))
