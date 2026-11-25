"""The Forester's willow field trug, packed for a Food delivery to the Keep."""
from math import cos, pi, sin
from random import Random
import bpy

from mathutils import Vector

from art import cord, loops, mesh
from arms_axe import skin_tube, tint


V = Vector
TAU = 2*pi
CENTER = V((0,-.308,1.025))
GRIP = {"R": V((-.128,-.318,1.165)), "L": V((.128,-.318,1.165))}


def wicker():
    dark = tint("Trug | osier heartwood","634127",0,.78)
    reed = tint("Trug | peeled willow","bc915e",0,.74)
    honey = tint("Trug | honey willow","a87849",0,.72)
    blond = tint("Trug | buff willow","d0a575",0,.76)
    # Shallow oval base widens toward the mouth. Narrow tapes cross
    # alternately over and under the upright ribs instead of printing a grid.
    def wall(a, t, out=0):
        return V(((.165+.065*t+out)*cos(a),CENTER.y+(.092+.052*t+out)*sin(a),
                  .909+.15*t +.010*t*t*cos(a)**2))
    count=64
    angles=[TAU*i/count for i in range(count)]
    loops("Trug | willow base",[[wall(a,t,-.0025) for a in angles] for t in (0,.03)],dark)
    # A shallow cloth liner cups the produce below the lip. Its pleated rim
    # leaves a visible hollow between the vegetables and the basket walls.
    liner=tint("Trug | natural flax lining","887557",0,.93)
    rings=[]
    for radius,height in ((.018,.958),(.46,.961),(.78,.973),(.89,.996),(.94,1.029)):
        row=[]
        for a in angles:
            fold=cos(13*a+.5)*.004*radius
            row.append(((.209*radius+fold)*cos(a),
                        CENTER.y+(.122*radius+fold)*sin(a),
                        height+.010*radius**3*sin(4*a+.3)+.002*radius*sin(13*a)))
        rings.append(row)
    loops("Trug | pleated linen lining",rings,liner,True,False)
    for k in range(32):
        a=k*TAU/32
        points=[wall(a+.012*sin(pi*t),t,.0007) for t in (0,.2,.45,.7,.95,1)]
        cord("Trug | upright willow rib", points,.0034,honey if k%3 else blond,5)
    for row in range(11):
        # Square-cut splints have a broad face and gently bevelled edges.
        t=(row+.5)/11
        section=[(-.038,-.002),(-.038,.0005),(-.030,.0022),(.030,.0022),(.038,.0005),(.038,-.002)]
        rings=[]
        for i in range(129):
            a=TAU*i/128
            weave=.0034*cos(16*a+row*pi)
            rings.append([wall(a,t+dt,weave+dr) for dt,dr in section])
        loops("Trug | alternating woven splint",rings,(reed,honey,reed,blond)[row%4],True,False)
    for t,r in ((.015,.0043),(.965,.0046),(1,.0066)):
        cord("Trug | rolled willow lip",[wall(i*TAU/96,t,.002) for i in range(97)],r,honey,8)
    # A bent ash carrying hoop rises at the ends, leaving both palms around
    # its straight middle. Small pinned returns give it a physical fastening.
    points=[(-.223,1.015),(-.228,1.059),(-.219,1.105),(-.197,1.142),(-.167,1.162),
            (-.145,1.165),(-.128,1.165),(-.095,1.165),(-.05,1.165),(0,1.165),
            (.05,1.165),(.095,1.165),(.128,1.165),(.145,1.165),(.167,1.162),
            (.197,1.142),(.219,1.105),(.228,1.059),(.223,1.015)]
    cord("Trug | steamed ash carrier",[V((x,-.318,z)) for x,z in points],.0095,reed,10)
    for side in (-1,1):
        x=side*.128
        cord("Trug | bound handgrip",[(x-.034,-.318,1.165),(x+.034,-.318,1.165)],
             .0165,"leather",12)
        helix=[]
        for j in range(74):
            u=j/73
            a=TAU*4.5*u
            helix.append((x-.033+.066*u,-.318+.0163*cos(a),1.165+.0163*sin(a)))
        cord("Trug | waxed twine grip seam",helix,.0015,"thread",5)
        for z in (1.032,1.047):
            cord("Trug | copper staple",[(side*.223,-.329,z),(side*.229,-.327,z),
                                          (side*.230,-.311,z),(side*.223,-.308,z)],.0023,"brass_dark",6)


def produce():
    rng=Random(125)
    leaf=tint("Harvest | brassica leaf","59723d",0,.76)
    fresh=tint("Harvest | pale inner leaf","a7b968",0,.80)
    outer=tint("Harvest | blue-green leaf","426954",0,.74)
    beet=tint("Harvest | beetroot","743845",0,.79)
    carrot=tint("Harvest | golden root","bc7735",0,.80)
    straw=tint("Harvest | barley straw","a9823b",0,.78)
    grain=tint("Harvest | ripe ears","d8b563",0,.74)
    def cabbage(loc, size):
        # Individual overlapping lobed leaves curve upward and fold over the heart.
        c=V(loc)
        for layer,(n,r,h) in enumerate(((9,1,.78),(7,.80,.93),(6,.54,1.04),(4,.29,1.05))):
            for i in range(n):
                a=TAU*i/n+.32*layer+rng.uniform(-.06,.06)
                radial=V((cos(a),sin(a),0))
                lateral=V((-sin(a),cos(a),0))
                rings=[]
                for j in range(7):
                    t=j/6
                    arc=sin(pi*t*.82)
                    extent=r*(.18+.88*arc-.47*t**4)
                    width=(.115+.71*sin(pi*t)**.72)*(1-.14*layer)
                    row=[]
                    for q in range(7):
                        u=(q-3)/3
                        ripple=.03*sin(8*u+2*a)*t*t+.035*cos(4*pi*t+a)*abs(u)**2
                        row.append(c+size*(radial*(extent-.24*u*u*arc)+lateral*u*width+
                                           V((0,0,h*(t+.10*arc)-.125*u*u*arc+ripple))))
                    rings.append(row)
                faces=[(j*7+q,j*7+q+1,(j+1)*7+q+1,(j+1)*7+q)
                       for j in range(6) for q in range(6)]
                mat=(outer,leaf,fresh,fresh)[layer]
                mesh("Harvest | cupped cabbage leaf",[v for row in rings for v in row],faces,mat)
                if layer<2:
                    cord("Harvest | pale midrib",[rings[j][3]+radial*.0003 for j in range(1,6)],
                         size*.014,fresh,5)
    cabbage((.068,-.369,1.031),.074)
    cabbage((-.026,-.321,1.043),.062)
    roots=((-.086,-.373,1.063,.041),(.152,-.330,1.063,.034),(.120,-.260,1.063,.039),
           (.048,-.245,1.063,.040),(-.124,-.306,1.063,.041),(-.107,-.249,1.031,.037),
           (-.020,-.243,1.022,.038),(-.155,-.351,1.024,.034),(.151,-.370,1.027,.029))
    for idx,(x,y,z,size) in enumerate(roots):
        profile=((-.95,.05),(-.66,.40),(-.32,.79),(.06,1),(.51,.87),(.72,.53),(.75,.16))
        origin=V((x,y,z))
        rings=[[origin+size*V(((r+.03*sin(a*3))*cos(a),r*.89*sin(a),z))
                for a in [TAU*j/14 for j in range(14)]] for z,r in profile]
        loops("Harvest | fresh roots",rings,beet if idx%2==0 else carrot)
        for j in range(3):
            a=TAU*(j/3+rng.random()*.13)
            axis=V((cos(a),sin(a),0))
            side=V((-sin(a),cos(a),0))
            base=origin+V((0,0,.69*size))
            verts=[base,base+size*(axis*.28+side*.16+V((0,0,.30))),
                    base+size*(axis+V((0,0,.58))),base+size*(axis*.34-side*.14+V((0,0,.31)))]
            mesh("Harvest | root tops",verts,[(0,1,2),(0,2,3)],leaf,False)
    # A tied sheaf is visible above the back of the trug. Distinct paired
    # spikelets and tapering awns give the grain its recognizable outline.
    sheaf=V((.102,-.264,1.033))
    for i in range(10):
        base=sheaf+V((rng.uniform(-.012,.016),rng.uniform(-.021,.018),rng.uniform(-.009,.012)))
        axis=V((rng.uniform(-1,-.8),rng.uniform(-.08,.21),rng.uniform(.18,.36))).normalized()
        leaf_axis=V((0,0,1)).cross(axis).normalized()
        top=base+axis*rng.uniform(.250,.345)
        cord("Harvest | barley culm",[base,base.lerp(top,.45)+V((0,0,.008)),top],.0017,straw,5)
        for k in range(6):
            for side in (-1,1):
                start=top+axis*(k*.0064-.031)
                end=start+axis*.012+leaf_axis*(side*.0048)+V((0,0,.003))
                v=end-start
                skin_tube("Harvest | barley spikelet",[start,start+v*.51,end],
                          [(.0008,.0006),(.0035,.0024),(.00045,.00042)],leaf_axis,grain,6)
                cord("Harvest | barley awn",[end,end+axis*.012+leaf_axis*side*.0032],.00048,grain,4)


def build():
    before=set(bpy.context.scene.objects)
    wicker()
    produce()
    # Keep the editable weave, hoop, leaves and grain as separate components.
    # Each set of repeated fibres shares one object and one visibility driver.
    groups={}
    for obj in sorted(set(bpy.context.scene.objects)-before,key=lambda item:item.name):
        label=obj.name.rsplit(".",1)[0]
        groups.setdefault(label,[]).append(obj)
    bpy.ops.object.select_all(action='DESELECT')
    for label,parts in groups.items():
        if len(parts)<2:
            continue
        for obj in parts:
            obj.select_set(True)
        bpy.context.view_layer.objects.active=parts[0]
        bpy.ops.object.join()
        bpy.context.object.name=label
        bpy.context.object.select_set(False)
