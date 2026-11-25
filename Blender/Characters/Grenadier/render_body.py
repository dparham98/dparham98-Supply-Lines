"""Render full-height portraits and detail views from the actual playable Grenadier GLB."""
import argparse
import math
from pathlib import Path
import sys
import bpy
import numpy as np
from mathutils import Vector

def light(name,pos,target,power,color,width,height):
    data=bpy.data.lights.new(name,"AREA")
    data.shape="RECTANGLE"
    data.size=width
    data.size_y=height
    data.energy=power
    data.color=color
    ob=bpy.data.objects.new(name,data)
    bpy.context.scene.collection.objects.link(ob)
    ob.location=pos
    ob.rotation_euler=(Vector(target)-ob.location).to_track_quat("-Z","Y").to_euler()

def studio(model,draft):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(model.resolve()))
    scene=bpy.context.scene
    rig,=[o for o in scene.objects if o.type=="ARMATURE"]
    for o in scene.objects:
        if o.type=="LIGHT" or o.name=="Muzzle flash":
            o.hide_render=True
    scene.render.engine="CYCLES"
    scene.cycles.samples=9 if draft else 36
    scene.cycles.use_denoising=True
    scene.cycles.seed=63
    scene.view_settings.view_transform="AgX"
    scene.view_settings.look="AgX - Medium High Contrast"
    scene.view_settings.exposure=-.22
    world=bpy.data.worlds.new("Charcoal studio")
    world.use_nodes=True
    world.node_tree.nodes["Background"].inputs[0].default_value=(.35,.42,.50,1)
    world.node_tree.nodes["Background"].inputs[1].default_value=.25
    scene.world=world
    light("Broad warm key",(-2.4,-3.2,3.8),(0,0,1.05),520,(1.0,.83,.69),2.5,2.8)
    light("Cool frontal fill",(2.5,-2.2,2.35),(0,0,1.1),240,(.72,.84,1.),1.9,2.8)
    light("High amber rim",(1.5,2.15,3.05),(0,0,1.15),610,(1.,.79,.57),1.65,2.2)
    light("Steel edge",(-2.0,1.75,2.1),(0,0,1.05),390,(.65,.81,1.),1.25,2.5)
    light("Lower bounce",(0,-2.6,1.05),(0,0,.85),44,(.91,.90,1.),1.8,.9)
    level=-.001
    sweep=[(-13.,level),(1.8,level)]
    for i in range(1,25):
        a=i*math.pi/48
        sweep.append((1.8+1.7*math.sin(a),level+1.7*(1-math.cos(a))))
    sweep.append((3.5,8.0))
    vertices=[(x,y,z) for y,z in sweep for x in (-15.,15.)]
    mesh=bpy.data.meshes.new("Cyclorama")
    mesh.from_pydata(vertices,[],[(2*i,2*i+1,2*i+3,2*i+2) for i in range(len(sweep)-1)])
    for face in mesh.polygons: face.use_smooth=True
    floor=bpy.data.objects.new("Seamless studio floor",mesh)
    scene.collection.objects.link(floor)
    mat=bpy.data.materials.new("Charcoal slate")
    mat.use_nodes=True
    bsdf=mat.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value=(.019,.029,.039,1)
    bsdf.inputs["Roughness"].default_value=.9
    bsdf.inputs["Specular IOR Level"].default_value=.16
    floor.data.materials.append(mat)
    cam=bpy.data.objects.new("Character portrait",bpy.data.cameras.new("Full-height lens"))
    scene.collection.objects.link(cam)
    cam.data.type="ORTHO"
    scene.camera=cam
    return scene,rig,cam

def pose(scene,rig,clip,t):
    ad=rig.animation_data
    ad.use_nla=False
    ad.action=bpy.data.actions[clip]
    start=ad.action.frame_range[0]
    frame=start+t*scene.render.fps/scene.render.fps_base
    scene.frame_set(int(frame),subframe=frame%1)
    bpy.context.view_layer.update()

def framing(scene,rig,direction,aspect,margin):
    view=(-Vector(direction)).to_track_quat("-Z","Y")
    axes=np.column_stack((np.asarray(view@Vector((1,0,0))),np.asarray(view@Vector((0,1,0)))))
    graph=bpy.context.evaluated_depsgraph_get()
    coords=[]
    for obj in scene.objects:
        if obj.type!="MESH" or obj.hide_render or not (obj.find_armature()==rig or obj.parent==rig):
            continue
        ev=obj.evaluated_get(graph)
        pts=np.empty((len(ev.data.vertices),3),dtype="f")
        ev.data.vertices.foreach_get("co",pts.ravel())
        matrix=np.asarray(ev.matrix_world)
        coords.append((pts@matrix[:3,:3].T+matrix[:3,3])@axes)
    pts=np.concatenate(coords)
    low,high=pts.min(axis=0),pts.max(axis=0)
    center=np.asarray((0.,0.,.9))
    center+=axes@((low+high)/2-center@axes)
    extent=high-low
    return Vector(center.tolist()), max(extent[0]*max(1,1/aspect),extent[1]*max(1,aspect))*margin

def render(model,output,draft=False,selected=None):
    scene,rig,cam=studio(model,draft)
    output.mkdir(parents=True,exist_ok=True)
    shots=[
        ("front","Rest",.23,(-.64,-1,.12),None,None,(1080,1350)),
        ("rear","Rest",.23,(.62,1,.19),None,None,(1080,1350)),
        ("side","Rest",.23,(-1.,-.03,.08),None,None,(648,810)),
        ("straight","Rest",.23,(.03,-1,.08),None,None,(648,810)),
        ("kit","Rest",.23,(-.5,.95,.12),(0,.075,1.22),.99,(990,900)),
        ("armor","Rest",.23,(-.56,-1,.04),(-.012,-.01,1.19),1.05,(990,900)),
        ("boots","Run",.17,(.81,-1,.21),(0,.05,.47),1.37,(990,900)),
        ("stride","Run",.17,(.85,-1,.13),None,None,(810,990)),
        ("brace","Shoot",.22,(-.72,-1,.15),None,None,(810,990)),
    ]
    for name,clip,t,direction,center,scale,size in shots:
        if selected and name not in selected:
            continue
        pose(scene,rig,clip,t)
        if center is None:
            center,scale=framing(scene,rig,direction,size[0]/size[1],1.12)
        center=Vector(center)
        bpy.data.objects["Seamless studio floor"].rotation_euler.z=math.atan2(direction[0],-direction[1])
        cam.location=center+Vector(direction).normalized()*9
        cam.rotation_euler=(center-cam.location).to_track_quat("-Z","Y").to_euler()
        cam.data.ortho_scale=scale
        scene.render.resolution_x,scene.render.resolution_y=size
        scene.render.resolution_percentage=45 if draft else 100
        scene.render.image_settings.file_format="PNG"
        scene.render.image_settings.color_mode="RGB"
        scene.render.filepath=str(output/(name+".png"))
        bpy.ops.render.render(write_still=True)

if __name__=="__main__":
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("model",type=Path)
    parser.add_argument("output",type=Path)
    parser.add_argument("--draft",action="store_true")
    parser.add_argument("--shots",nargs="+")
    args=parser.parse_args(sys.argv[sys.argv.index("--")+1:])
    render(args.model,args.output.resolve(),args.draft,args.shots)
