"""Canine head, swept helmet and lit visor for the Round Table hound.

The figure faces -Y. The head pivots as a single rigid assembly around its
neck joint. Units are metres.
"""
from math import asin, cos, pi, sin
from mathutils import Vector

import kit


GROUP = "Head"


def form(name, rings, material, bevel=.003):
    """Loft equal sized polygonal rings in head coordinates."""
    n=len(rings[0])
    vertices=[p for ring in rings for p in ring]
    faces=[tuple(reversed(range(n)))]
    faces += [(j*n+i,j*n+(i+1)%n,(j+1)*n+(i+1)%n,(j+1)*n+i)
              for j in range(len(rings)-1) for i in range(n)]
    faces.append(tuple(range((len(rings)-1)*n,len(rings)*n)))
    return kit.mesh(name,vertices,faces,material,GROUP,bevel)


def barrel_ring(y,width,bottom,top):
    # Rounded octagonal dog muzzle, with wide cheeks and a slightly flat top.
    height=top-bottom
    return [(-width*.56,y,bottom),(-width,y,bottom+.23*height),
            (-width,y,bottom+.71*height),(-width*.61,y,top),
            (width*.61,y,top),(width,y,bottom+.71*height),
            (width,y,bottom+.23*height),(width*.56,y,bottom)]


def ears():
    for s in (-1,1):
        # Each ear is a tapered, enclosed wedge: dark outer cartilage with
        # a smaller inset on the forward-facing surface.
        x=s*.103
        outer=[(x-s*.046,-.712,1.34),(x+s*.043,-.687,1.34),
               (x+s*.030,-.664,1.46),(x-s*.013,-.643,1.665),
               (x-s*.043,-.716,1.47)]
        back=[(a,b+.028,c-.003) for a,b,c in outer]
        vertices=outer+back
        n=len(outer)
        faces=[tuple(range(n)),tuple(reversed(range(n,2*n)))]
        faces.extend((i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n))
        kit.mesh("Ear | outer cartilage",vertices,faces,"fur",GROUP,.002)
        inner=[(x-s*.029,-.716,1.367),(x+s*.027,-.696,1.365),
               (x+s*.019,-.682,1.46),(x-s*.012,-.656,1.616),
               (x-s*.031,-.716,1.459)]
        # A thin inset, attached to the actual forward plane of the ear.
        kit.mesh("Ear | inner leather",inner,[(0,1,2,3,4)],"muzzle",GROUP,0)


def helmet():
    # The wide, sculpted brow is below the shell. Each ring is formed with a
    # fixed-width axial stripe, continuous over the crown and down the back.
    levels=[(1.290,.153,.155,-.703),(1.325,.156,.158,-.703),
            (1.360,.153,.155,-.703),(1.395,.142,.143,-.699),
            (1.426,.122,.124,-.695),(1.451,.092,.096,-.690),
            (1.468,.055,.061,-.687),(1.476,.023,.026,-.686)]
    arcs=7
    rings=[]
    for z,rx,ry,cy in levels:
        cut=asin(min(.96,.031/rx))
        quarter=[0,cut]+[cut+(pi/2-cut)*i/(arcs-1) for i in range(1,arcs)]
        angles=(quarter[:-1]+[pi-a for a in reversed(quarter[1:])]
                +[pi+a for a in quarter[:-1]]+[2*pi-a for a in reversed(quarter[1:])])
        rings.append([(rx*sin(a),cy-ry*cos(a),z) for a in angles])
    count=len(rings[0])
    verts=[p for r in rings for p in r]
    # The two stripe slivers at front and rear become a single top band.
    stripe={0,2*arcs-1,2*arcs,4*arcs-1}
    faces=[]
    indices=[]
    faces.append(tuple(reversed(range(count))))
    indices.append(0)
    for j in range(len(rings)-1):
        for i in range(count):
            faces.append((j*count+i,j*count+(i+1)%count,(j+1)*count+(i+1)%count,(j+1)*count+i))
            indices.append(1 if i in stripe and j>=1 else 0)
    faces.append(tuple(range((len(rings)-1)*count,len(rings)*count)))
    indices.append(1)
    obj=kit.mesh("Helmet | shell and blue axial stripe",verts,faces,"white",GROUP,0)
    obj.data.materials.append(kit.material("team_color"))
    for face,mat in zip(obj.data.polygons,indices):
        face.material_index=mat
        if len(face.vertices)==4:
            face.use_smooth=True

    # Side flaps turn down over the temple behind the eyes.
    for s in (-1,1):
        v=[(s*.143,-.767,1.328),(s*.158,-.706,1.331),
           (s*.148,-.655,1.292),(s*.118,-.645,1.244),
           (s*.119,-.716,1.243),(s*.146,-.762,1.278)]
        vv=v+[(x-s*.008,y,z) for x,y,z in v]
        n=len(v)
        f=[tuple(range(n)),tuple(reversed(range(n,n*2)))]
        f += [(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)]
        kit.mesh("Helmet | lower side guard",vv,f,"white",GROUP,.003)
        kit.rod("Helmet | dark hinge", (s*.150,-.690,1.303),(s*.166,-.690,1.303),.027,"black",GROUP,20,.002)
        kit.rod("Helmet | steel hinge", (s*.163,-.690,1.303),(s*.172,-.690,1.303),.021,"steel",GROUP,20,.001)
        kit.rod("Helmet | hinge inset", (s*.171,-.690,1.303),(s*.174,-.690,1.303),.014,"white",GROUP,20,.001)

    # The visor is a closed faceted plate just underneath the brow. Its center
    # sits above the bridge of the snout and the ends meet the hinge guards.
    angles=[-pi/2+i*pi/24 for i in range(25)]
    def brow(a,z,depth):
        return (.151*sin(a),-.703-(.157+depth)*cos(a),z+.018*abs(sin(a)))
    upper=[brow(a,1.315,.005) for a in angles]
    lower=[brow(a,1.271+.018*abs(sin(a)),.006) for a in angles]
    white_verts=upper+lower
    n=len(angles)
    kit.mesh("Visor | ivory face plate",white_verts,
             [(i,i+1,n+i+1,n+i) for i in range(n-1)],"white",GROUP,0)

    # One continuous swept rail avoids visible joins between brow segments.
    def swept(label,z,depth,radius,material):
        rings=[]
        for a in angles:
            centre=Vector(brow(a,z,depth))
            outward=Vector((sin(a),-cos(a),0))
            rings.append([centre+radius*(outward*cos(2*pi*k/10)+Vector((0,0,sin(2*pi*k/10))))
                          for k in range(10)])
        form(label,rings,material,0)
    swept("Visor | continuous gold brow",1.320,.009,.006,"gold")
    swept("Visor | warm luminous band",1.316,.015,.0028,"glow")


def build():
    # The natural-looking snout stays separate from the white armored cranium.
    kit.ellipsoid("Head | angular cranial mass",(0,-.699,1.205),(.141,.170,.170),"fur",GROUP,16,8)
    form("Head | tapered muzzle",[
        barrel_ring(-.78,.106,1.122,1.260),
        barrel_ring(-.91,.101,1.105,1.244),
        barrel_ring(-1.025,.071,1.112,1.211),
        barrel_ring(-1.073,.051,1.126,1.191)],"muzzle",.003)
    # A slightly overlapping lower lip and black nose complete the silhouette.
    form("Head | lower jaw",[
        barrel_ring(-.79,.094,1.105,1.153),
        barrel_ring(-.94,.086,1.093,1.145),
        barrel_ring(-1.038,.055,1.108,1.151)],"muzzle",.002)
    kit.ellipsoid("Head | nose",(0,-1.074,1.176),(.052,.029,.032),"black",GROUP,16,6)
    for side in (-1,1):
        # The dark lip is inset against the side of the upper muzzle. Its
        # tapered wedge remains visible in the small portrait.
        lip=[(side*.104,-.814,1.143),(side*.103,-.887,1.130),
             (side*.089,-.946,1.130),(side*.073,-.990,1.136),
             (side*.083,-.960,1.119),(side*.097,-.901,1.119),
             (side*.102,-.849,1.127)]
        kit.mesh("Head | recessed mouth crease",lip,[tuple(range(len(lip)))],"black",GROUP,0)
        kit.ellipsoid("Nose | nostril",(side*.026,-1.095,1.179),(.010,.006,.005),"fur",GROUP,12,6)
    ears()
    helmet()
