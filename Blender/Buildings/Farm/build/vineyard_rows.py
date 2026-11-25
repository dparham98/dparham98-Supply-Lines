"""Cultivate one walkable 10 x 10 metre vineyard. XY is the ground plane; Z is up."""
from math import cos, sin, pi
from random import Random

import bpy
from mathutils import Vector as V
from mathutils.noise import noise

from vineyard_mesh import Batch, scaled

ROW_X = [-4.05, -2.43, -.81, .81, 2.43, 4.05]
PLANT_Y = [-4.06,-2.77,-1.48,0,1.48,2.77,4.06]
UP = V((0,0,1))


def surface(x,y):
    border = min(1.0, max(0.0, (4.96-max(abs(x),abs(y)))/.32))
    ridge = max(0.0, 1-min(abs(x-r) for r in ROW_X)/.59)
    noise0=noise(V((x*1.9,y*1.7,1.6)))+.35*noise(V((x*7,y*7,6.6)))
    return .008+border*(.029+.077*ridge**2+.023*noise0)


def soft_patch_color(x,y):
    """Earth in the wheel lanes is less disturbed and warm. Vine rows hold darker humus."""
    rowdist=min(abs(x-r) for r in ROW_X)
    ridge=max(0.0,1-rowdist/.72)
    grain=noise(V((x*.7,y*.7,.9)))+.5*noise(V((x*4,y*4,1.9)))
    c=(.255-.074*ridge, .144-.057*ridge, .065-.024*ridge)
    return scaled(c,.9+.26*grain)


def create_ground(collection,parent,material,detritus):
    rng=Random(1255)
    ground=Batch(material)
    n=56
    pts=[]; cols=[]; faces=[]
    for j in range(n+1):
        for i in range(n+1):
            x=-4.96+i*9.92/n; y=-4.96+j*9.92/n
            if 0<i<n: x+=rng.uniform(-.045,.045)
            if 0<j<n: y+=rng.uniform(-.045,.045)
            # Irregular, tapered headland. The plot owns no raised or collidable border.
            if i in [0,n]: x+=(-1 if i==n else 1)*rng.uniform(0,.09)
            if j in [0,n]: y+=(-1 if j==n else 1)*rng.uniform(0,.09)
            pts.append((x,y,surface(x,y)))
            cols.append(scaled(soft_patch_color(x,y),rng.uniform(.84,1.14)))
    for j in range(n):
        for i in range(n):
            a=j*(n+1)+i
            faces.extend(((a,a+1,a+n+2),(a,a+n+2,a+n+1)))
    ground.patch(pts,faces,cols,True)
    ground.uvs=[(p[0]/1.23,p[1]/1.23) for p in pts]
    soil=ground.bake("Headland_and_furrows",collection,parent)
    gravel=Batch(detritus)
    for _ in range(560):
        x,y=rng.uniform(-4.82,4.82),rng.uniform(-4.82,4.82)
        r=rng.uniform(.010,.043)
        clr=rng.choice([(.44,.31,.18),(.16,.13,.08),(.33,.26,.16),(.34,.30,.23)])
        gravel.ellipsoid((x,y,surface(x,y)+.005),(r*rng.uniform(1,1.7),r,r*.55),clr,5,1,False,rng.random()*pi)
    for row in ROW_X:
        for _ in range(60):
            x=row+rng.uniform(-.29,.29)
            y=rng.uniform(-4.62,4.62)
            r=rng.uniform(.017,.042)
            gravel.ellipsoid((x,y,surface(x,y)+.008),(r*1.55,r,r*.55),(.133,.078,.034),5,1,False)
    gravel.bake("Gravel_and_broken_loam",collection,parent)
    margins=Batch(detritus)
    for _ in range(1900):
        x,y=rng.uniform(-4.87,4.87),rng.uniform(-4.87,4.87)
        edge = max(abs(x),abs(y))
        if edge<4.48 and min(abs(x-r) for r in ROW_X)>.31 and rng.random()<.88:continue
        pos=V((x,y,surface(x,y)+.004))
        hue=rng.choice([(.305,.29,.086),(.276,.24,.063),(.188,.231,.057),(.412,.307,.114)])
        for _ in range(rng.randint(3,6)):
            theta=rng.uniform(0,2*pi)
            sweep=V((cos(theta),sin(theta),0))
            ortho=UP.cross(sweep)*rng.uniform(.006,.014)
            start=pos+sweep*rng.uniform(0,.03)
            tip=start+sweep*rng.uniform(.018,.067)+UP*rng.uniform(.05,.14)
            margins.patch([start-ortho,start+ortho,start.lerp(tip,.53)+ortho*.52,tip],
                          [(0,1,2),(0,2,3)],[scaled(hue,.52),scaled(hue,.68),hue,scaled(hue,1.12)])
    margins.bake("Wild_herbs_at_the_headland",collection,parent)
    return soil


# Five palmate lobes with deep sinuses, an angled petiole and small sawteeth.
EDGE=[(0,0),(-.14,-.12),(-.25,-.10),(-.30,-.15),(-.36,-.05),(-.43,-.07),
      (-.44,.04),(-.53,.10),(-.52,.19),(-.28,.23),(-.49,.31),(-.50,.41),
      (-.61,.45),(-.55,.49),(-.59,.58),(-.49,.59),(-.52,.68),(-.38,.67),
      (-.36,.74),(-.20,.59),(-.21,.76),(-.14,.80),(-.13,.91),(-.08,.89),
      (0,1.0),(.07,.87),(.12,.89),(.14,.79),(.21,.76),(.18,.57),(.35,.73),
      (.37,.65),(.47,.65),(.46,.58),(.57,.56),(.52,.48),(.57,.42),(.49,.39),
      (.47,.29),(.28,.22),(.51,.18),(.48,.10),(.52,.045),(.41,-.05),
      (.35,-.045),(.29,-.14),(.22,-.08),(.15,-.12)]
PALETTE=[(.101,.205,.034),(.15,.246,.043),(.224,.284,.054),(.183,.246,.044),
         (.106,.230,.062),(.235,.309,.066),(.128,.226,.053),(.299,.300,.056)]


def leaf(batch, start, heading, length, color, rng):
    # Each half rolls away from the central vein. Leaves tilt in different directions.
    across=V((-sin(heading),cos(heading),0))
    tilt=rng.uniform(.12,.98)
    forward=V((cos(heading)*cos(tilt),sin(heading)*cos(tilt),-sin(tilt)))
    up=forward.cross(across).normalized()
    span=rng.uniform(.76,1.03)
    roll=rng.uniform(-.24,.24)
    def point(x,y):
        crown=.09*sin(pi*max(0,y))-.13*x*x-.048*abs(x)+roll*x
        return start+length*(across*x*span+forward*y+up*crown)
    shape=[(x,y) for y in (-.16,.26,.62,1.02) for x in (-.62,0,.62)]
    vertices=[point(x,y) for x,y in shape]
    faces=[(i,i+3,i+4,i+1) for i in (0,1,3,4,6,7)]
    colors=[scaled(color,.85+.22*y+.04*x) for x,y in shape]
    batch.patch(vertices,faces,colors,True)
    batch.uvs.extend(((x+.62)/1.24,(y+.16)/1.18) for x,y in shape)


def grapes(batch, stems, location, rng, scale):
    h=rng.uniform(.148,.205)*scale
    spread=h*rng.uniform(.37,.44)
    stems.tube([location+UP*.046,location,location-UP*.042],[.008,.006,.004],(.147,.18,.046),4)
    hue=rng.choice([(.137,.077,.223),(.171,.102,.248),(.158,.080,.181),(.100,.062,.18)])
    for k,count in enumerate((4,6,5,3,1)):
        radius=spread*(.56,.72,.58,.34,0)[k]
        for j in range(count):
            a=2*pi*j/count + .78*k+rng.uniform(-.17,.17)
            p=location+V((radius*cos(a),radius*sin(a),-k*h/5+rng.uniform(-.009,.009)))
            br=rng.uniform(.023,.030)*scale
            batch.ellipsoid(p,(br,br,br*1.08),scaled(hue,rng.uniform(.68,1.25)),6,1,True,rng.random()*3)


def plant(x,y,row,bark,leaves,fruit,rng):
    z=surface(ROW_X[row]+x,y); s=rng.uniform(.83,1.06)
    root=V((x,y,z))
    skew=V((rng.uniform(-.10,.10),rng.uniform(-.10,.10),0))
    hub=root+skew+UP*.36*s
    knee=root+skew*.42+V((rng.uniform(-.07,.07),rng.uniform(-.06,.06),.16*s))
    wood=scaled((.142,.080,.036),rng.uniform(.76,1.14))
    bark.tube([root-UP*.026,knee,hub-skew*.25-UP*.055,hub],[.072*s,.063*s,.052*s,.064*s],wood,8,.16,True)
    for j in range(3):
        a=2*pi*j/3
        curl=[V((cos(a+t)*s*rad,sin(a+t)*s*rad,0)) for t,rad in ((0,.066),(.53,.057),(.9,.045))]
        bark.tube([root+curl[0],knee+curl[1],hub+curl[2]],[.012*s,.010*s,.005*s],scaled(wood,.66),4)
    for j in range(4):
        a=j*pi*.5+rng.uniform(-.35,.35)
        axis=V((cos(a),sin(a),0))
        bark.tube([knee-UP*.037,root+axis*.091+UP*.024,root+axis*rng.uniform(.121,.187)-UP*.013],
                  [.026*s,.032*s,.007],wood,6,0,True)
    for direction in (-1,1):
        end=hub+V((rng.uniform(-.14,.14),direction*rng.uniform(.34,.45)*s,rng.uniform(.10,.18)*s))
        elbow=hub.lerp(end,.46)+V((rng.uniform(-.07,.07),0,.066))
        bark.tube([hub,elbow,end,end+V((.013,direction*.09,.023))],[.072*s,.051*s,.027*s,.011*s],wood,7,.31)
        # Interleaved short vertical spurs give the crown a low, gnarled wine-vine silhouette.
        for j in range(5):
            base=hub.lerp(end,(j+.35)/5)
            side=1 if (j+row)%2 else -1
            shoot=base+V((side*rng.uniform(.15,.29)*s,direction*rng.uniform(.01,.13),
                          rng.uniform(.164,.26)*s))
            bend=base.lerp(shoot,.52)+UP*.033
            bark.tube([base,bend,shoot],[.025*s,.014*s,.0048],scaled(wood,1.35),5,.2)
            if j in [1,3] or (j==4 and rng.random()<.4):
                stalk=base.lerp(shoot,.80)+V((side*.055,0,-.036))
                grapes(fruit,bark,stalk,rng,s)
            for k in range(5):
                heading=(0 if side>0 else pi)+rng.uniform(-1.92,1.92)
                base_leaf=base.lerp(shoot,min(1.,.38+k*.145))+V((rng.uniform(-.035,.035),rng.uniform(-.045,.045),0))
                position=base_leaf+V((cos(heading)*.038,sin(heading)*.038,.027))
                bark.bevel_bar(base_leaf,position,.0039,scaled(wood,1.57),4)
                pale=(j==4 and k>=3 and rng.random()<.5)
                color=rng.choice(PALETTE if not pale else [(.265,.339,.055),(.327,.315,.052)])
                leaf(leaves,position,heading,rng.uniform(.16,.245)*s,scaled(color,rng.uniform(.88,1.11)),rng)


def create_rows(collection,parent,mats):
    rng=Random(733)
    for i,base_x in enumerate(ROW_X):
        root=bpy.data.objects.new(f"Vine_row_{i+1:02d}",None)
        collection.objects.link(root); root.parent=parent; root.location.x=base_x
        bark=Batch(mats["botanic"]); leaves=Batch(mats["canopy"])
        fruit=Batch(mats["fruit"])
        for y in PLANT_Y:
            plant(rng.uniform(-.095,.095),y+rng.uniform(-.085,.085),i,bark,leaves,fruit,rng)
        # Geometry is batched by material, leaving each row editable and independently animated.
        bark.bake(f"Cordons_{i+1:02d}",collection,root)
        leaves.bake(f"Canopy_{i+1:02d}",collection,root)
        fruit.bake(f"Grape_bunches_{i+1:02d}",collection,root)
