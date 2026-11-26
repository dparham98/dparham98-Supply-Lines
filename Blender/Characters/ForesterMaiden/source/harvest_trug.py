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
    skins = [tint("Harvest | damson", "47305d", 0, .44),
             tint("Harvest | purple bloom", "705484", 0, .55),
             tint("Harvest | black grape", "392e4b", 0, .36)]
    stem = tint("Harvest | cut stems", "736342", 0, .8)
    for cx, cy, height in [(-.12,-.31,1.055),(-.045,-.35,1.060),
                           (.05,-.32,1.070),(.129,-.30,1.054),(0,-.25,1.066)]:
        for layer, count in enumerate((1,3,5,4)):
            radius = (.0,.014,.026,.020)[layer]
            for i in range(count):
                a = TAU*i/count + layer*.67
                center = V((cx+radius*cos(a), cy+radius*sin(a), height-.061+layer*.023))
                r = rng.uniform(.014,.020)
                rings = []
                for j in range(7):
                    t = pi*j/6
                    rings.append([center + r*V((sin(t)*cos(TAU*k/9), sin(t)*sin(TAU*k/9), -1.08*cos(t))) for k in range(9)])
                loops("Harvest | ripe grapes", rings, rng.choice(skins), True, False)
        base = V((cx,cy,height+.012))
        cord("Harvest | cut stems", [base,base+V((.006,.003,.020)),base+V((.020,.008,.027))], .003,stem,6)


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
