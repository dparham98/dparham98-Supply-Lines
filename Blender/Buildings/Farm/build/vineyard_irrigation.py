"""Two hovering vineyard irrigators. Their translucent water fans are exported with the model."""
from math import cos, pi, sin
from random import Random

import bpy
import numpy as np
from mathutils import Vector as V

from vineyard_mesh import Batch, WHITE

POSITIONS={"West":(-2.08,-2.70,1.18),"East":(2.08,2.70,1.18)}


def empty(name,collection,parent,location):
    ob=bpy.data.objects.new(name,None)
    collection.objects.link(ob)
    ob.parent=parent
    ob.location=location
    ob.empty_display_size=.15
    return ob


def plate(batch, outline, low, high, color):
    n=len(outline)
    faces=[tuple(reversed(range(n))),tuple(range(n,2*n))]
    faces += [(i,(i+1)%n,n+(i+1)%n,n+i) for i in range(n)]
    vertices=[(x,y,z) for z in [low,high] for x,y in outline]
    batch.patch(vertices,faces,color)


def rounded_plate(batch,cx,cy,hx,hy,low,high,bevel,color):
    pairs=[(-hx+bevel,-hy),(hx-bevel,-hy),(hx,-hy+bevel),(hx,hy-bevel),
           (hx-bevel,hy),(-hx+bevel,hy),(-hx,hy-bevel),(-hx,-hy+bevel)]
    plate(batch,[(cx+x,cy+y) for x,y in pairs],low,high,color)


def water_material():
    # Tangential streaks, mist and fine droplets are painted into the alpha.
    # This keeps a softly feathered plume in the engine with a handful of triangles.
    side=256
    rng=np.random.default_rng(77)
    v,u=np.mgrid[0:1:complex(side),0:1:complex(side)]
    cross=(v-.5)*2
    lines=np.zeros_like(u)
    for _ in range(64):
        angle=rng.uniform(-1,1)
        spread=rng.uniform(.011,.048)
        center=angle+.014*np.sin(u*rng.uniform(6,16)+rng.uniform(0,5))
        lines+=rng.uniform(.07,.23)*np.exp(-((cross-center)/spread)**2)
    drop=rng.random(u.shape)
    envelope=np.exp(-2.6*cross**2)*np.sin(pi*np.clip(u,0,1))**.64*(1-u*.65)
    alpha=envelope*(.13+lines*.55+np.where(drop>.9,.38,0))
    pixels=np.empty((side,side,4),np.float32)
    pixels[:,:,:3]=[.82,.91,.92]
    pixels[:,:,3]=np.clip(alpha,0,.72)
    img=bpy.data.images.new("Vineyard_water_mist",width=side,height=side,alpha=True)
    img.alpha_mode="STRAIGHT"
    img.pixels.foreach_set(pixels.ravel())
    img.pack()
    mat=bpy.data.materials.new("Atomized water")
    mat.use_nodes=True
    mat.surface_render_method="BLENDED"
    mat.use_transparency_overlap=False
    tree=mat.node_tree
    bs=tree.nodes.get("Principled BSDF")
    bs.inputs["Roughness"].default_value=.43
    bs.inputs["Base Color"].default_value=(.70,.87,.93,1)
    bs.inputs["Emission Color"].default_value=(.61,.78,.84,1)
    bs.inputs["Emission Strength"].default_value=.32
    tex=tree.nodes.new("ShaderNodeTexImage")
    tex.image=img
    tree.links.new(tex.outputs['Alpha'],bs.inputs['Alpha'])
    return mat


def spray(name,parent,coll,mist,drops):
    assembly=empty(name,coll,parent,(0,0,0))
    fan_verts=[]; poly=[]; uvs=[]
    droplets=Batch(drops)
    rng=Random(53)
    for sign in (-1,1):
        for angle in (0.,pi*.39,pi*.76):
            offset=len(fan_verts)
            for t in (0.,.26,.57,1.):
                spread=.010+.25*t
                c=V((sign*(.86+.78*t),-.02-.18*t*t,-.079-.32*t-.22*t*t))
                perpendicular=V((sign*.18*sin(angle),cos(angle),.74*sin(angle)))
                for s in (-1,1):
                    fan_verts.append(c+s*spread*perpendicular)
                    uvs.append((t,(s+1)/2))
            poly.extend((offset+k,offset+k+1,offset+k+3,offset+k+2) for k in (0,2,4))
        for _ in range(44):
            t=rng.uniform(.14,.98)
            depth=t*rng.uniform(-.20,.2)
            c=V((sign*(.86+.78*t),-.02-.18*t*t+depth,-.079-.32*t-.22*t*t+t*rng.uniform(-.12,.12)))
            vector=V((sign*.75,-.16-depth,-.38-.40*t)).normalized()*rng.uniform(.009,.029)
            w=V((0,rng.uniform(.002,.005),0))
            droplets.patch([c-w,c+vector,c+w,c-vector],[(0,1,2),(0,2,3)],WHITE)
    mesh=bpy.data.meshes.new(name+"_MistShells");mesh.from_pydata(fan_verts,[],poly)
    mesh.materials.append(mist)
    uv=mesh.uv_layers.new(name="Water fan falloff")
    for l in mesh.loops: uv.data[l.index].uv=uvs[l.vertex_index]
    mesh.update()
    part=bpy.data.objects.new(name+"_MistShells",mesh);coll.objects.link(part);part.parent=assembly
    droplets.bake(name+"_Droplets",coll,assembly)
    return assembly


def build_sprayers(collection,parent,mats):
    mist=water_material()
    bronze=(.31,.197,.071); iron=(.074,.091,.101); cream=(.71,.68,.54); steel=(.245,.267,.27)
    for name,loc in POSITIONS.items():
        rig=empty("Irrigator_"+name,collection,parent,loc)
        shell=Batch(mats['machinery'])
        dark=Batch(mats['machinery']); enamel=Batch(mats['team']); lights=Batch(mats['light'])
        # A proud horizontal reservoir with a thin, wing-like nozzle carriage below.
        shell.ellipsoid((0,.005,.143),(.314,.242,.157),cream,18,5,True)
        dark.ellipsoid((0,.012,.057),(.355,.277,.091),iron,14,3,True)
        for x in (-.18,.18):
            shell.bevel_bar((x,-.183,.139),(x,-.118,.265),.019,bronze)
            shell.bevel_bar((x,-.118,.265),(x,.12,.265),.019,bronze)
            shell.bevel_bar((x,.12,.265),(x,.194,.133),.019,bronze)
        shell.ellipsoid((0,.027,.291),(.096,.093,.021),steel,12,2)
        rounded_plate(enamel,0,-.008,.27,.19,.005,.071,.071,WHITE)
        rounded_plate(dark,0,-.03,.218,.16,-.08,.013,.072,iron)
        for sign in (-1,1):
            wing=[(.16,-.135),(.69,-.111),(.88,-.042),(.88,.049),(.71,.101),(.24,.148)]
            outline=[(sign*x,y) for x,y in wing]
            if sign<0: outline.reverse()
            plate(shell,outline,-.018,.033,bronze)
            for off in [-.047,.047]:
                shell.bevel_bar((sign*.27,off,-.013),(sign*.78,off,-.035),.0235,steel)
            rounded_plate(enamel,sign*.6,.015,.21,.069,.034,.059,.027,WHITE)
            shell.ellipsoid((sign*.83,.0,-.027),(.124,.091,.067),steel,12,3)
            dark.ellipsoid((sign*.862,0,-.071),(.084,.067,.042),iron,12,3)
            lights.ellipsoid((sign*.878,-.041,-.088),(.047,.030,.009),WHITE,12,2)
        shell.bake("Reservoir_and_spray_boom_"+name,collection,rig)
        dark.bake("Pump_and_lift_pods_"+name,collection,rig)
        enamel.bake("Enamel_"+name,collection,rig)
        lights.bake("Spray_lenses_"+name,collection,rig)
        spray("Water_"+name,rig,collection,mist,mats['spray'])
    # A single original flush Arthurian service plate replaces a fixed watering gantry.
    port=Batch(mats['machinery']); face=Batch(mats['team'])
    x,y=(-4.59,-3.34)
    port.tube([(x,y,.035),(x,y,.069)],[.267,.253],bronze,24)
    face.tube([(x,y,.066),(x,y,.078)],[.219,.219],WHITE,24)
    for i in range(8):
        a=i*pi/4
        center=V((x,y,.082))
        axis=V((cos(a),sin(a),0))
        side=V((-sin(a),cos(a),0))*.024
        port.patch([center+side,center+axis*(.166 if i%2==0 else .10),center-side,center-axis*.019],[(0,1,2,3)],(.75,.47,.13))
    port.bake("Irrigation_manifold",collection,parent)
    face.bake("Manifold_enamel",collection,parent)
