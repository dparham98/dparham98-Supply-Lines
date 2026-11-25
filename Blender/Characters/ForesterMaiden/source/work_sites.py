"""Rebuild the optional, matching-scale props for the Forester work-cycle review."""
from math import cos, exp, pi, sin
from pathlib import Path
from random import Random
import sys

import bpy
import numpy as np
from mathutils import Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
from art import bevel, cord, loops, mesh
from arms_axe import tint
from work_gear import bark_finishes, surface_uv, textured

V = Vector
TAU = 2*pi


def round_wood(name, center, profile, bark, cut, seed):
    count=60
    rings=[]
    phase=seed*.48
    for z,r,flare in profile:
        row=[]
        for j in range(count):
            a=j*TAU/count
            relief=.035*sin(7*a+phase)+.021*cos(11*a-phase)+.020*sin(3*a+seed)
            root=(.5+.5*cos(5*a+phase))**4
            radius=r*(1+relief)+flare*root
            row.append((center[0]+radius*cos(a),center[1]+radius*sin(a),z))
        rings.append(row)
    obj=loops(name,rings,bark)
    obj.data.materials.append(cut)
    radius=profile[-1][1]
    for poly in obj.data.polygons:
        if len(poly.vertices)>4:
            poly.material_index=1
            poly.use_smooth=False
    def coords(poly,indices):
        if poly.material_index:
            return [(.50+(obj.data.vertices[i].co.x-center[0])*.455/radius,
                     .50+(obj.data.vertices[i].co.y-center[1])*.455/radius) for i in indices]
        angular=[i%count for i in indices]
        seam=max(angular)-min(angular)>count//2
        return [((j+(count if seam and j<count//2 else 0))/count*1.8,
                 profile[i//count][0]*4.5) for i,j in zip(indices,angular)]
    surface_uv(obj,coords)
    return obj


def timber_block():
    bark,cut=bark_finishes()
    center=(-.285,-.449)
    round_wood("Oak chopping stump",center,[(0,.232,.055),(.025,.228,.040),
               (.096,.200,.028),(.178,.183,.011),(.287,.189,.005),
               (.375,.191,.002),(.386,.187,0)],bark,cut,3)
    round_wood("Standing billet",center,[(.385,.075,.005),(.394,.082,0),
               (.448,.079,0),(.521,.080,0),(.599,.077,0),(.605,.074,0)],bark,cut,7)
    # Two faint cuts on the upper end and chips fallen away from the swing.
    cut_shadow=tint("Oak | cut marks","78573d",0,.83)
    for dy,dx in [(.020,.012),(-.022,-.026)]:
        x,y=center[0]+dx,center[1]+dy
        cord("Old axe mark",[(x-.050,y,.6053),(x-.025,y-.004,.60555),
                             (x-.005,y-.003,.6053)],.00085,cut_shadow,5)
    rng=Random(67)
    for i in range(13):
        a=rng.uniform(0,TAU)
        near=i<5
        r=rng.uniform(.102,.17) if near else rng.uniform(.282,.37)
        x,y=center[0]+r*cos(a),center[1]+r*sin(a)
        z=.3865 if near else .0015
        long=rng.uniform(.014,.031)
        wid=rng.uniform(.006,.011)
        d=V((cos(a+.6),sin(a+.6),0)); side=V((-d.y,d.x,0))
        p=V((x,y,z))
        pts=[p-d*long,p-d*long*.1+side*wid,p+d*long,
             p+d*long*.41-side*wid,p+V((0,0,.005))]
        obj=mesh("Split oak chip",pts,[(0,1,2,3),(0,4,1),(1,4,2),(2,4,3),(3,4,0)],cut,False)
        surface_uv(obj,lambda poly,indices:[(.24+obj.data.vertices[i].co.x*4,
                                             .28+obj.data.vertices[i].co.y*4) for i in indices])


def boards_finish():
    n=192
    y,x=np.mgrid[0:n,0:n].astype(np.float32)*TAU/n
    lines=x*7+.62*np.sin(y+.20*np.sin(x))+.15*np.sin(2*y+4*x)
    groove=(.5+.5*np.cos(lines))**6
    streak=.14*np.cos(22*x+.58*np.sin(y*2))+.25*np.cos(2*x+.24*np.sin(y*3))
    h=.34*streak-.42*groove
    return textured("Joinery | adzed chestnut","a4764a",.68,
                    np.array((.63,.427,.274))*(1+.33*h[:,:,None]),h,.24)


def timber(name,a,b,width,depth,material,ease=.004):
    a,b=V(a),V(b)
    direction=(b-a).normalized()
    across=V((0,1,0))
    if abs(direction.dot(across))>.85:
        across=V((1,0,0))
    across=(across-direction*across.dot(direction)).normalized()
    normal=direction.cross(across).normalized()
    rows=[[p+width*s*across/2+depth*t*normal/2 for s,t in [(-1,-1),(1,-1),(1,1),(-1,1)]]
          for p in (a,b)]
    obj=loops(name,rows,material,False)
    def coords(poly,indices):
        pts=[obj.data.vertices[j].co-a for j in indices]
        if abs(poly.normal.dot(direction))>.9:
            return [(p.dot(across)*5+.3,p.dot(normal)*4+.47) for p in pts]
        side=normal if abs(poly.normal.dot(across))>.9 else across
        return [(p.dot(side)*4+.19,p.dot(direction)*1.2) for p in pts]
    surface_uv(obj,coords)
    bevel(obj,ease)


def timber_frame():
    wood=boards_finish()
    metal=tint("Joinery | peened square nails","514b43",.55,.51)
    # Stable trestle, with a working plank above the supporting crosspieces.
    for x in [-.41,.38]:
        for side in [-1,1]:
            y=-.491+side*.166
            timber("Trestle foot",(x,y,.006),(x,-.491+side*.043,.816),.068,.064,wood)
        timber("Trestle fork",(x,-.621,.812),(x,-.350,.812),.068,.061,wood)
        timber("Side tie",(x,-.638,.40),(x,-.343,.40),.039,.043,wood,.003)
    timber("Lower stretcher",(-.45,-.491,.399),(.425,-.491,.399),.053,.071,wood)
    timber("Trestle brace",(-.39,-.491,.409),(-.090,-.491,.805),.043,.054,wood,.003)
    timber("Trestle brace",(.365,-.491,.409),(.088,-.491,.805),.043,.054,wood,.003)
    timber("Framing plank",(-.565,-.491,.873),(.525,-.491,.873),.211,.061,wood,.0026)
    # The first nail's actual top is precisely the hammer's contact plane.
    for x,y in [(-.140,-.492),(-.416,-.549),(-.416,-.426),(.38,-.549),(.38,-.426)]:
        circles=[[(x+rr*cos(TAU*i/7+.22),y+rr*sin(TAU*i/7+.22),z) for i in range(7)]
                 for z,rr in [(.903,.0044),(.9057,.0053),(.906,.0045)]]
        loops("Nail in plank",circles,metal,False)


def planting_bed():
    rng=Random(318)
    n=256
    y,x=np.mgrid[0:n,0:n].astype(np.float32)*TAU/n
    grains=np.random.default_rng(216).uniform(-1,1,(n,n))
    crumb=.38*np.sin(17*x+np.sin(4*y))*np.cos(14*y+.7*np.cos(3*x))
    crumb+=.19*np.cos(5*x+2*np.sin(3*y))+.39*grains
    soil=textured("Garden | umber soil","554432",.92,
                  np.array((.34,.259,.18))*(1+.22*crumb[:,:,None]),crumb,.29)
    clod=tint("Garden | fresh earth","68513b",0,.95)
    grit=tint("Garden | river grit","8e8171",0,.84)
    sage=tint("Garden | sage cotyledons","778e49",0,.71)
    green=tint("Garden | young bean leaves","536d39",0,.72)
    vein=tint("Garden | new leaf veins","90a358",0,.70)
    center=(-.176,-.610)
    nx,ny=85,39
    pts=[]; faces=[]
    def height(x,y):
        ridges=0
        for xpos in [-.535,.108]:
            ridges+=.020*exp(-((x-xpos)/.067)**2)
        # Three shallow lines follow the measured pull through the middle.
        stroke=max(0,min(1,(y+.67)/.055,(-.354-y)/.056))
        track=-.381+(y+.623)*.499
        for shift in [-.037,0,.037]:
            r=x-track-shift
            ridges+=stroke*(.005*exp(-((r-.011)/.008)**2)-.006*exp(-(r/.007)**2))
        return .008+ridges+.0018*sin(41*x+4*y)*sin(42*y)+.0015*cos(34*x)
    for j in range(ny+1):
        b=j/ny*2-1
        for i in range(nx+1):
            a=i/nx*2-1
            x=center[0]+a*.477*(1-.074*abs(b)**4)+.0045*cos(7*b+2*a)
            y=center[1]+b*.310*(1-.088*abs(a)**4)+.0048*sin(7*a-3*b)
            edge=max(abs(a),abs(b))
            z=height(x,y)*max(0,min(1,(1-edge)/.115))+(.0028*rng.random()*(1-edge))
            pts.append((x,y,z))
            if i and j:
                v=j*(nx+1)+i
                faces.extend([(v-nx-2,v-nx-1,v),(v,v-1,v-nx-2)])
    bed=mesh("Turned bed",pts,faces,soil,True)
    surface_uv(bed,lambda poly,indices:[(pts[i][0]*3.7,pts[i][1]*3.7) for i in indices])
    for i in range(49):
        x=center[0]+rng.uniform(-.414,.414)
        y=center[1]+rng.uniform(-.251,.251)
        z=height(x,y)
        size=rng.uniform(.005,.014)
        p=V((x,y,z-.001))
        lower=[p+V((cos(j*TAU/7)*size,sin(j*TAU/7)*size*.66,0)) for j in range(7)]
        upper=[p+V((cos(j*TAU/7+.27)*size*.63,sin(j*TAU/7+.27)*size*.46,
                    size*rng.uniform(.28,.56))) for j in range(7)]
        loops("Gravel and tilth",[lower,upper],grit if i%5==0 else clod,False)
    for row,x in enumerate([-.535,.108]):
        for j in range(4):
            y=-.829+.144*j+.011*row+rng.uniform(-.008,.008)
            base=V((x+rng.uniform(-.013,.013),y,height(x,y)-.001))
            stem=base+V((rng.uniform(-.005,.005),rng.uniform(-.004,.004),rng.uniform(.027,.054)))
            cord("Young bean stem",[base,base.lerp(stem,.47)+V((.002,0,0)),stem],.0022,green)
            initial=rng.uniform(0,TAU)
            for k in range(4):
                a=initial+k*pi/2+.14*sin(k)
                tip=V((cos(a),sin(a),0))
                cross=V((-tip.y,tip.x,0))
                length=rng.uniform(.037,.056)*(1 if k%2==0 else .73)
                origin=stem+V((0,0,.008 if k%2 else -.005))
                leaf=[]; leaf_faces=[]
                for h in range(9):
                    f=h/8
                    spine=origin+tip*length*f+V((0,0,length*(.56*sin(pi*f)+.20*f)))
                    w=(.0008+.013*sin(pi*f)**.72)*(1 if k%2==0 else .74)
                    leaf.extend([spine-cross*w,spine+V((0,0,.003*sin(pi*f))),spine+cross*w])
                    if h:
                        l=h*3
                        leaf_faces.extend([(l-3,l-2,l+1,l),(l-2,l-1,l+2,l+1)])
                mesh("Young bean leaf",leaf,leaf_faces,green if k%2 else sage,True)
                cord("Leaf midrib",[leaf[q] for q in range(1,25,3)],.00047,vein,5)


def collect_site(name,builder):
    before=set(bpy.context.scene.objects)
    builder()
    objects=sorted(set(bpy.context.scene.objects)-before,key=lambda o:o.name)
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects:
        obj.select_set(True)
        bpy.context.view_layer.objects.active=obj
        for mod in list(obj.modifiers):
            bpy.ops.object.modifier_apply(modifier=mod.name)
    bpy.context.view_layer.objects.active=objects[0]
    bpy.ops.object.join()
    result=bpy.context.object
    result.name=result.data.name=name
    return result


def build(destination):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    root=bpy.data.objects.new("WorkSites",None)
    bpy.context.scene.collection.objects.link(root)
    for name,builder in [("TimberBlock",timber_block),("TimberFrame",timber_frame),("PlantingBed",planting_bed)]:
        obj=collect_site(name,builder)
        obj.parent=root
    bpy.ops.export_scene.gltf(filepath=str(destination),export_format="GLB",export_animations=False,
                              export_texcoords=True,export_normals=True,export_yup=True)


if __name__=="__main__":
    default=Path(__file__).resolve().parents[1]/"godot"/"work_sites.glb"
    build(Path(sys.argv[sys.argv.index("--")+1]) if "--" in sys.argv else default)
