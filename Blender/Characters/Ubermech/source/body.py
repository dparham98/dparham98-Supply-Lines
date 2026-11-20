"""Torso, segmented armored coat, power pack and twin signal masts."""
from math import cos, pi, sin
from mathutils import Vector
from mech import box, material, mesh, rod, shell


def octagon(x,y,w,d,cut):
    a,b=w/2,d/2
    return [(x-a+cut,y-b),(x+a-cut,y-b),(x+a,y-b+cut),(x+a,y+b-cut),
            (x+a-cut,y+b),(x-a+cut,y+b),(x-a,y+b-cut),(x-a,y-b+cut)]


def casting(name,g,levels,mat="graphite",bevel=.028):
    return shell(name,[(z,octagon(x,y,w,d,c)) for z,x,y,w,d,c in levels],mat,g,bevel)


def plate(name,pts,mat,group,depth=.075,bevel=.018,keel=None,back=False):
    """A plate in the X/Z plane. Each corner carries its own depth and rake."""
    n=len(pts)
    inset=Vector((0,-depth if back else depth,0))
    vs=[Vector(p) for p in pts]
    vs += [p+inset for p in vs]
    fs=[tuple(range(n,2*n))]
    fs.extend((i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n))
    if keel is not None:
        vs.append(Vector(keel))
        fs.extend((i,(i+1)%n,len(vs)-1) for i in range(n))
    else:
        fs.append(tuple(range(n)))
    return mesh(name,vs,fs,mat,group,bevel)


def bolt(name,p,r,group,normal=(0,-1,0),collar=True):
    p,n=Vector(p),Vector(normal).normalized()
    if collar:
        rod(name+" counterbore",p-.005*n,p+.012*n,r*1.24,"black",group,16,.003)
    rod(name+" cap",p+.008*n,p+.034*n,r,"edge",group,12,.005)
    rod(name+" socket",p+.032*n,p+.036*n,r*.31,"joint",group,6,.001)


def belt():
    g="Pelvis"
    casting("Hip differential",g,[(2.33,0,.015,1.04,.68,.14),(2.51,0,.00,1.64,.82,.19),
                                    (2.91,0,0,1.33,.74,.14),(3.07,0,0,1.14,.70,.12)],"joint")
    for s in (-1,1):
        rod("Hip hinge axle",(.44*s,0,2.56),(.84*s,0,2.56),.23,"joint",g,20)
    for z in (2.91,3.00,3.10,3.20):
        casting("Waist rotary flange",g,[(z-.025,0,-.015,1.16,.87,.17),(z+.022,0,-.015,1.16,.87,.17)],"black",.007)
    casting("Belt body",g,[(2.985,0,-.025,1.27,.96,.19),(3.026,0,-.025,1.45,1.035,.22),
                             (3.223,0,-.025,1.45,1.035,.22),(3.254,0,-.025,1.31,.96,.19)],"graphite",.014)
    for s in (-1,1):
        plate("Belt cheek segment",[(.22*s,-.555,3.225),(.53*s,-.538,3.214),
               (.65*s,-.491,3.17),(.65*s,-.49,3.035),(.22*s,-.555,3.023)],"joint",g,.035,.009)
    # Raised steel rim around a visibly recessed square center.
    box("Clasp backing",(0,-.579,3.12),(.427,.134,.287),"edge",g,.024)
    box("Clasp recess",(0,-.649,3.12),(.299,.014,.188),"black",g,.012)
    box("Clasp insert",(0,-.658,3.112),(.23,.012,.137),"joint",g,.009)
    for s in (-1,1):
        group="Tasset.R" if s<0 else "Tasset.L"
        plate("Coat side outer flare",[(s*.49,-.31,3.00),(s*.83,-.11,2.90),
              (s*1.098,-.07,2.420),(s*1.01,-.06,2.23),(s*.68,-.30,2.29)],
              "graphite",group,.37,.026,(s*.84,-.36,2.62))
        pts=[(s*.36,-.512,2.985),(s*.71,-.479,2.987),(s*1.028,-.38,2.51),
             (s*1.00,-.475,2.424),(s*.645,-.63,2.44),(s*.441,-.64,2.59)]
        def thigh_plane(x,z):
            return -.601+.25*(abs(x)-.64)+.19*(z-2.73)
        plate("Upper thigh shield",[(x,thigh_plane(x,z),z) for x,_,z in pts],"plate",group,.125,.029)
        plate("Tasset outer return",[(s*.66,.03,2.92),(s*.90,.19,2.81),
              (s*.997,.36,2.19),(s*.63,.46,2.27)],"graphite",group,.13,.021,back=True)
        for x,y,z in [(.43,-.544,2.92),(.70,-.528,2.916),(.937,-.494,2.509)]:
            bolt("Tasset screw",(s*x,thigh_plane(x,z)-.003,z),.022,group)
        plate("Rear coat leaf",[(s*.08,.43,2.98),(s*.56,.46,2.89),(s*.68,.54,2.21),
              (s*.15,.55,2.12)],"plate",group,.09,.018,(s*.38,.595,2.51),back=True)
    plate("Lower ventral underplate",[(-.55,-.40,2.84),(.55,-.40,2.84),(.44,-.46,2.085),
          (.29,-.461,1.995),(-.32,-.46,1.995),(-.585,-.43,2.18)],"black",g,.13,.028)
    pts=[(-.27,-.553,3.013),(.28,-.553,3.013),(.438,-.585,2.17),
         (.32,-.602,2.078),(-.37,-.603,2.086),(-.397,-.595,2.20)]
    def coat_plane(z):
        return -.586+.042*(z-2.50)
    plate("Hanging central coat armor",[(x,coat_plane(z),z) for x,_,z in pts],"plate",g,.095,.023)
    for x,y,z,r in [(-.12,-.571,2.79,.060),(-.16,-.594,2.46,.062),(-.292,-.605,2.19,.026),(.323,-.601,2.18,.026)]:
        bolt("Coat boss",(x,coat_plane(z)-.002,z),r,g)


def pack():
    g="Chest"
    casting("Back power frame",g,[(3.18,0,.22,1.28,.72,.18),(3.34,0,.29,1.67,.87,.18),
                                 (4.24,0,.26,1.55,.86,.15),(4.41,0,.24,1.24,.65,.16)],"joint")
    for s in (-1,1):
        x=s*.607
        casting("Radiator tower",g,[(3.54,x,.31,.41,.64,.08),(3.81,x,.36,.49,.79,.085),
            (4.42,x,.32,.52,.70,.085),(4.78,x,.285,.49,.62,.080),
            (4.88,x,.30,.385,.50,.082)],"graphite",.022)
        box("Tower intake well",(x,-.037,4.602),(.325,.047,.397),"black",g,.022)
        for i in range(3):
            z=4.461+i*.104
            box("Intake heat line",(x,-.065,z),(.259,.018,.021),"enamel",g,.007)
            box("Intake hot core",(x,-.081,z),(.226,.012,.009),"glow_red",g,.002)
            box("Intake armored louver",(x,-.087,z+.038),(.316,.067,.048),"plate",g,.01)
        box("Tower top inspection plate",(x,.29,4.875),(.25,.28,.032),"joint",g,.013)
        for j in range(7):
            box("Rear heat exchanger fin",(x,.728,3.86+j*.089),(.327,.10,.041),"edge",g,.013)
        bolt("Lower pack fixing",(x,.739,3.73),.058,g,(0,1,0))
        for x2 in (.93,1.015):
            rod("Return conduit",(s*x2,.31,3.595),(s*(x2-.145),.47,3.31),.031,"steel",g)
    for j in range(4):
        box("Spine key",(0,.772,3.45+j*.199),(.446,.127,.146),"graphite",g,.033)
        box("Spine reveal",(0,.836,3.45+j*.199),(.257,.015,.055),"black",g,.006)
    for i,(x,z) in enumerate([(-.93,5.095),(-.79,5.14)]):
        rod("Aerial landing",(x,.38,4.18),(x,.38,4.39),.062,"plate",g)
        rod("Aerial whip",(x,.38,4.35),(x,.38,z),.018,"joint",g,12,.004)
        rod("Aerial tip",(x,.38,z-.049),(x,.38,z+.024),.033,"graphite",g,12,.005)


def collar():
    group="Chest"
    # Sections follow the open neck from the right front, around the nape and
    # back to the left front. The lip has a return on its inside face.
    side=[
        ((.270,-.411,4.302),(.327,-.434,4.208)),
        ((.402,-.312,4.438),(.514,-.370,4.209)),
        ((.446,-.187,4.497),(.562,-.233,4.246)),
        ((.425,-.073,4.490),(.515,-.093,4.276)),
        ((.342,.051,4.457),(.366,.067,4.294)),
        ((.296,.186,4.451),(.320,.214,4.300)),
        ((.177,.299,4.467),(.187,.331,4.300)),
        ((0,.329,4.476),(0,.360,4.302)),
    ]
    arc=side+[((-x,y,z),(-bx,by,bz)) for (x,y,z),(bx,by,bz) in reversed(side[:-1])]
    verts=[]
    for top,base in arc:
        t,b=Vector(top),Vector(base)
        radial=Vector((t.x,t.y,0)).normalized()
        verts.extend((b,t,t-radial*.045-Vector((0,0,.005)),b-radial*.054))
    faces=[(0,1,2,3)]
    for i in range(len(arc)-1):
        k=i*4
        for j in range(4):
            faces.append((k+j,k+(j+1)%4,k+4+(j+1)%4,k+4+j))
    faces.append(tuple(range(len(verts)-4,len(verts))))
    stand=mesh("Collar | wrapped nape stand",verts,faces,"graphite",group,.012)
    stand.data.materials.append(material("edge"))
    stand.data.materials.append(material("black"))
    for i in range(len(arc)-1):
        stand.data.polygons[2+4*i].material_index=1
        stand.data.polygons[3+4*i].material_index=2

    # Nested lames bridge the gimbal and breastplate under the open coat.
    for i in range(3):
        z=4.044+.060*i
        y=-.536+.050*i
        w=.38-.027*i
        plate("Collar | throat lame",[
            (-w,y+.054,z+.070),(-.18,y,z+.085),(.18,y,z+.085),(w,y+.054,z+.070),
            (w-.027,y+.044,z+.015),(.14,y-.013,z-.011),(-.14,y-.013,z-.011),
            (-w+.027,y+.044,z+.015)],"joint",group,.085,.009)

    for sign in (-1,1):
        # The longer facing crosses the shorter one at the sternum. Each roll
        # joins its facing to the collar stand behind the jaw.
        long=sign==1
        tip=(-.13,3.975) if long else (-.052,4.052)
        outline=[(.441,4.449),(.405,4.399),(.328,4.302),(.155,4.165),
                 tip,((-.096 if long else -.020),tip[1]-.029),
                 (.379,4.004 if long else 4.039),(.644,4.079),(.751,4.170),
                 (.700,4.197),(.783,4.236),(.796,4.318),(.596,4.369)]
        def surface(x,z):
            return -.66+.19*x+.38*(z-4.00)-(.046 if long else 0)
        outline3=[(sign*x,surface(x,z),z) for x,z in outline]
        plate("Raised gorget wing | coat facing",outline3,"plate",group,.070,.016)
        shoulder=[outline[i] for i in (11,12,0,1)]
        front=[Vector((sign*x,surface(x,z)+.002,z)) for x,z in shoulder]
        back=[Vector((sign*x,y,z)) for x,y,z in
              [(.731,-.219,4.290),(.550,-.200,4.375),(.456,-.202,4.481),(.408,-.311,4.432)]]
        outer=front+back
        vs=outer+[p-Vector((0,0,.052)) for p in outer]
        fs=[]
        for i in range(3):
            fs.extend([(i,i+1,5+i,4+i),(8+i,12+i,13+i,9+i),
                       (i,8+i,9+i,i+1),(4+i,5+i,13+i,12+i)])
        fs.extend([(0,4,12,8),(3,11,15,7)])
        mesh("Collar | rolled upper seam",vs,fs,"graphite",group,.008)
        normal=Vector((sign*.19,-1,.38)).normalized()
        for x,z,r in [(.677,4.255,.024),(.356,4.102,.016)]:
            bolt("Collar | recessed facing stud",(sign*x,surface(x,z),z),r,group,normal)


def build():
    belt()
    g="Chest"
    casting("Trapezoidal thorax frame",g,[(3.22,0,.015,1.23,.77,.19),(3.36,0,-.02,1.55,.87,.17),
        (3.79,0,-.015,1.85,1.01,.22),(4.07,0,.0,2.05,.935,.24),
        (4.31,0,.01,1.45,.78,.20)],"joint",.036)
    rod("Throat gimbal",(0,0,4.19),(0,0,4.43),.296,"black",g,24,.019)
    for z,r in [(4.27,.283),(4.32,.264)]:
        rod("Throat turntable",(0,0,z),(0,0,z+.037),r,"edge",g,24,.008)
    for s in (-1,1):
        rod("Shoulder pivot mounting",(s*.775,.00,4.00),(s*1.21,.00,4.00),.29,"joint",g,24)
        # Three stepped plates form the external lat armor and frame the active vents.
        for j in range(3):
            z=3.41+.229*j; x=.78+j*.065
            plate("Thorax flank scale",[(s*(x-.16),-.26,z+.17),(s*x,-.30,z+.24),
                   (s*(x+.15),-.19,z+.18),(s*(x+.10),-.16,z-.018),(s*(x-.12),-.25,z-.074)],
                   "graphite",g,.65,.020,(s*(x+.02),-.39,z+.092))
        pts=[(s*.49,-.49,3.926),(s*.805,-.429,4.077),(s*.92,-.397,3.888),
             (s*.751,-.443,3.575),(s*.555,-.525,3.394),(s*.477,-.556,3.429)]
        plate("Rib armor",pts,"plate",g,.08,.017,(s*.681,-.58,3.75))
        pts=[(s*.571,-.541,3.52),(s*.738,-.482,3.59),(s*.706,-.478,3.335),(s*.532,-.505,3.302)]
        plate("Reactor status recess",pts,"black",g,.026,.008)
        for i in range(3):
            x=s*(.566+i*.043)
            plate("Lower reactor gauge",[(x,-.548,3.337+i*.014),(x+s*.019,-.547,3.344+i*.014),
                 (x+s*.045,-.551,3.421+i*.014),(x+s*.026,-.55,3.417+i*.014)],"glow_red",g,.012,.002)
    pts=[(-.455,-.526,3.96),(.544,-.534,4.008),(.629,-.543,3.827),
         (.451,-.54,3.362),(.328,-.54,3.29),(-.32,-.538,3.302),(-.50,-.542,3.46)]
    plate("Sternal armor gasket",pts,"black",g,.09,.018)
    pts=[(-.435,-.589,3.965),(.515,-.569,3.994),(.588,-.562,3.817),
         (.418,-.586,3.378),(.315,-.609,3.329),(-.326,-.614,3.355),(-.463,-.60,3.525)]
    def breast_plane(x,z):
        return -.602+.035*(z-3.70)+.012*x
    plate("Central breastplate",[(x,breast_plane(x,z),z) for x,_,z in pts],"plate",g,.07,.017)
    for x,y,z in [(-.26,-.599,3.828),(.32,-.589,3.843),(-.251,-.608,3.475),(.28,-.601,3.48)]:
        bolt("Breastplate recessed stud",(x,breast_plane(x,z)-.001,z),.061,g)
    collar()
    pack()
