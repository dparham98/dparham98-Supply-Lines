"""Regenerate the 4 m Arthurian home and its three object-animation tracks in Blender 4.5."""
from math import atan2, cos, pi, sin
from pathlib import Path
import random
import sys

import bpy
from mathutils import Vector

HERE = Path(__file__).resolve().parent
sys.path.insert(0,str(HERE))
from house_mesh import Assembly, X, Y, Z, material, tapered_leaf, trim, wood

bpy.ops.wm.read_factory_settings(use_empty=True)
scene=bpy.context.scene
scene.render.fps=24
bpy.context.preferences.filepaths.save_version=0
group=bpy.data.objects.new("House",None)
bpy.context.collection.objects.link(group)
# The design drawings face -Y. This turns the finished front door to Godot -Z.
group.rotation_euler.z=pi
group.empty_display_size=.22
group["footprint"]="4 by 4 metres"
group["front"]="Godot -Z"

oak=wood("Honey oak",(177,115,64),12)
fir=wood("Laminated fir",(207,151,92),15)
cedar=wood("Oiled cedar",(187,135,82),18)
walnut=wood("Smoked oak",(113,72,43),14)
shade=wood("Cedar heart",(165,105,62),18)
shakes=[wood("Heartwood shingles %d"%i,c,23+i) for i,c in enumerate(
    [(107,42,26),(125,52,30),(114,45,27),(138,64,37)])]
oxblood=material("Sealed oxblood flashing",(.235,.042,.034),.33,.4)
brass=material("Aged champagne bronze",(.52,.30,.11),.68,.33)
brass_light=material("Polished fasteners",(.78,.53,.23),.64,.3)
graphite=material("Flashed charcoal",(.047,.048,.046),.50,.49)
gasket=material("Weather gasket",(.023,.027,.029),0,.83)
foundation=material("Bluestone footings",(.135,.143,.139),.08,.78)
team=material("team_color",(.022,.078,.32),.17,.43)
team_dark=material("team_color_shadow",(.012,.042,.14),.06,.52)
linen=material("Unbleached linen",(.64,.47,.28),0,.95)
down=material("Indigo cushions",(.056,.12,.27),0,.88)
soil=material("Window planter soil",(.085,.041,.022))
leaves=[material("Potted bay %d"%i,c) for i,c in enumerate([(.085,.18,.054),(.17,.29,.079),(.24,.34,.09)])]
cream=material("Clay planter",(.73,.61,.44),0,.66)
honey=material("Loft lamplight",(1,.52,.16),.04,.38,3.0)
indicator=material("Entry reader",(.14,.56,.68),.12,.3,.62)
glass=material("Subtle warm glazing",(.59,.69,.67),.19,.18)
glass.node_tree.nodes["Principled BSDF"].inputs["Alpha"].default_value=.074
glass.surface_render_method="BLENDED"

sections={}
def section(name, pivot=(0,0,0), bevel=.007):
    sections[name]=Assembly(name,pivot,group,bevel)
    return sections[name]

base=section("Stone_sill")
frame=section("Timber_portals")
wall=section("Cedar_walls",bevel=0)
joinery=section("Door_and_windows")
furn=section("Loft_furnishings",bevel=0)
roofL=section("Shingle_roof_west",(-1.73,0,2.10),.004)
roofR=section("Shingle_roof_east",(1.73,0,2.10),.004)
ridge=section("Ridge_and_flashings",(0,0,3.8),.006)
fan=section("Air_recovery_fan",(-1.612,.889,.70),.003)
rng=random.Random(911)
front=-1.61
back=1.60
eaves=2.06
half_span=1.86
slope=.99
def roof_z(x):
    return eaves+(half_span-abs(x))*slope

base.block((0,0,.069),(3.44,3.43,.138),foundation)
base.block((0,0,.149),(3.36,3.37,.064),graphite)
base.block((0,-1.735,.065),(1.31,.35,.13),foundation)
base.block((0,-1.79,.139),(1.21,.23,.032),brass)
# The house has two full-depth side windows and an open loft recess in the front.
def front_board(a,b,za,zb,ta,tb,y,mat):
    if max(ta-za,tb-zb) < .014:
        return
    wall.prism([(a,y,za),(b,y,zb),(b,y,max(zb+.003,tb)),(a,y,max(za+.003,ta))],(0,.105,0),mat,Z)

def arch_top(x):
    # Pointed arch over a short, straight-sided jamb.
    x=min(1,abs(x)/.645)
    return 2.44+.89*(1-x)**.64

cuts=sorted(set([round(-1.60+i*.16,3) for i in range(21)]+[-.645,-.52,.52,.645]))
for a,b in zip(cuts,cuts[1:]):
    lo,hi=a+.003,b-.003
    middle=(a+b)/2
    mat=rng.choice([cedar,cedar,fir,oak])
    if abs(middle)>.52:
        front_board(lo,hi,.175,.175,1.91,1.91,front,mat)
    if abs(middle)<.645:
        front_board(lo,hi,1.91,1.91,2.016,2.016,front,mat)
        front_board(lo,hi,arch_top(lo),arch_top(hi),roof_z(lo)-.035,roof_z(hi)-.035,front,mat)
    else:
        front_board(lo,hi,1.91,1.91,roof_z(lo)-.035,roof_z(hi)-.035,front,mat)
    front_board(lo,hi,.175,.175,roof_z(lo)-.035,roof_z(hi)-.035,back-.08,mat)

def wall_window(y):
    return -.92<y<.37

for sign in (-1,1):
    window_edges=sorted(set([-1.60+i*.16 for i in range(21)]+[-.92,.37]))
    for a,b in zip(window_edges,window_edges[1:]):
        if b-a<.012: continue
        y=(a+b)/2
        ranges=[(.175,2.295)] if not wall_window(y) else [(.175,.93),(1.78,2.295)]
        for lo,hi in ranges:
            wall.block((sign*1.53,y,(hi+lo)/2),(.10,b-a-.005,hi-lo),rng.choice([cedar,cedar,oak,fir]),Z)
    frame.block((sign*1.6,0,.27),(.14,3.35,.17),walnut,Y)
    frame.block((sign*1.6,0,2.02),(.19,3.53,.19),oak,Y)
    for y in [-1.51,.43,1.49]:
        frame.block((sign*1.591,y,1.11),(.15,.162,1.87),fir,Z)
        frame.block((sign*1.591,y,.255),(.174,.185,.14),brass)
    for y in [-.93,.37]:
        joinery.block((sign*1.575,y,1.35),(.14,.074,.88),walnut)
    for z in [.94,1.77]:
        joinery.block((sign*1.582,-.275,z),(.16,1.39,.085),oak)
    joinery.block((sign*1.626,-.275,.89),(.22,1.48,.056),team)
    joinery.block((sign*1.557,-.27,1.344),(.065,.035,.77),brass)
    joinery.prism([(sign*1.553,-.896, .991),(sign*1.553,.334,.991),
                   (sign*1.553,.334,1.723),(sign*1.553,-.896,1.723)],(sign*.004,0,0),glass,Y)
    # Amber warm rooms with a lit pendant, printed books and a side bench.
    furn.block((sign*1.13,-.265,1.36),(.08,1.35,.95),shade)
    furn.block((sign*1.32,-.265,.96),(.42,1.29,.09),fir)
    furn.block((sign*1.32,-.34,1.05),(.27,.47,.08),linen)
    for i in range(5):
        height=.175+.045*((i+2)%3)
        furn.block((sign*1.26,.16-.066*i,1.06+height/2),(.12,.05,height),[oxblood,down,linen,team_dark][i%4])
    furn.disk((sign*1.33,-.64,1.72),(0,0,-1),.010,.15,brass)
    furn.disk((sign*1.33,-.64,1.53),(0,0,1),.08,.055,honey,20)

# Curved glulam members. Real parallel lamellae follow each bend through the gable.
def arch_path(sign):
    points=[Vector((sign*1.47,z)) for z in [.14,.46,.76,1.12]]
    a,b,c,d=[Vector((sign*x,z)) for x,z in [(1.47,1.12),(1.47,2.15),(1.28,2.55),(.05,3.66)]]
    for i in range(1,17):
        t=i/16
        points.append((1-t)**3*a+3*t*(1-t)**2*b+3*t*t*(1-t)*c+t**3*d)
    return points

def lamella(points,y,rad0,rad1,depth,mat):
    coords=[]
    for i,p in enumerate(points):
        tangent=(points[min(i+1,len(points)-1)]-points[max(i-1,0)]).normalized()
        side=Vector((-tangent.y,tangent.x))
        for rad,v in [(rad0,0),(rad1,0),(rad1,depth),(rad0,depth)]:
            pt=p+side*rad
            coords.append((pt.x,y+v,pt.y))
    faces=[(3,2,1,0)]
    for i in range(len(points)-1):
        for j in range(4):
            faces.append((4*i+j,4*i+(j+1)%4,4*i+4+(j+1)%4,4*i+4+j))
    n=len(coords)
    faces.append((n-4,n-3,n-2,n-1))
    frame.solid(coords,faces,mat,Vector((points[-1].x-points[0].x,0,points[-1].y-points[0].y)))

for y in [-1.836,1.595]:
    for sign in [-1,1]:
        path=arch_path(sign)
        for i,m in enumerate([oak,fir,cedar,fir,oak]):
            lamella(path,y,-.118+i*.047,-.118+(i+1)*.047-.001,.253,m)
        frame.block((sign*1.47,y+.123,.225),(.264,.293,.18),brass)
        # Flush bolted stainless/bronze straps protect the segment joins.
        facing=-1 if y<0 else 1
        py=y if facing<0 else y+.253
        for i in [3,12,16]:
            p=path[i]
            tangent=(path[i+1]-path[i-1]).normalized()
            side=Vector((-tangent.y,tangent.x))
            a=p-side*.124
            b=p+side*.124
            frame.beam((a.x,py+facing*.010,a.y),(b.x,py+facing*.010,b.y),.065,.035,brass)
            for q in [p-side*.088,p+side*.088]:
                frame.disk((q.x,py+facing*.027,q.y),(0,facing,0),.017,.012,brass_light)
    frame.block((0,y+.12,1.912),(2.63,.254,.20),oak)
    frame.block((0,y+.119,3.65),(.20,.28,.23),fir)

# Shaded ground-floor porch. Movable door panels ride separate metal rails.
joinery.block((0,-1.43,.996),(1.02,.09,1.65),gasket)
joinery.block((.19,-1.484,1.005),(.60,.058,1.655),shade)
joinery.block((-.226,-1.505,1.005),(.42,.074,1.655),oak)
for x in [-.525,.525]:
    joinery.block((x,-1.632,1.02),(.075,.13,1.76),walnut)
joinery.block((0,-1.635,1.839),(1.13,.14,.09),brass)
joinery.block((.418,-1.532,1.10),(.056,.025,.13),graphite)
joinery.block((.418,-1.549,1.123),(.028,.009,.039),indicator)
for x in [-.344,.345]:
    joinery.block((x,-1.566,.93),(.026,.057,.213),brass_light)
for x in [-.854,.854]:
    joinery.block((x,-1.706,1.02),(.50,.086,1.68),team)
    for i in range(4):
        joinery.block((x+(i-1.5)*.098,-1.754,1.025),(.094,.043,1.51),[fir,cedar,oak,cedar][i],Z)
    for z in [.26,1.79]:
        joinery.block((x,-1.782,z),(.436,.042,.038),brass)
    joinery.block((x,-1.688,1.862),(.63,.11,.049),graphite)
    for dx in [-.153,.153]:
        joinery.block((x+dx,-1.746,1.841),(.042,.057,.108),brass)

# An open, deep loft bay avoids flat painted glass. Mullions reveal a made bed,
# a lamp, a cushion and a living plant through the front arch.
furn.block((0,-1.12,2.02),(1.42,.97,.11),walnut)
furn.prism([(-.755,-.795,2.05),(.755,-.795,2.05),(.755,-.795,3.05),
            (0,-.795,3.39),(-.755,-.795,3.05)],(0,.07,0),cedar,Z)
for x in [-.71,.71]:
    furn.block((x,-1.17,2.63),(.065,.85,1.19),oak)
furn.block((-.17,-1.16,2.078),(.915,.54,.10),brass)
furn.block((-.17,-1.17,2.16),(.89,.50,.15),linen)
furn.block((-.43,-1.125,2.239),(.246,.49,.048),down)
furn.block((.105,-1.026,2.276),(.225,.17,.101),linen)
furn.block((-.13,-.82,2.54),(.87,.15,.055),walnut)
furn.disk((-.19,-1.41,2.80),Z,.013,.36,brass)
furn.disk((-.19,-1.41,2.721),Z,.101,.079,honey,16)
furn.disk((-.19,-1.41,2.80),Z,.112,.026,brass,16)
furn.disk((.407,-1.375,2.085),Z,.119,.17,cream,18)
furn.disk((.407,-1.375,2.249),Z,.124,.026,cream,18)
furn.disk((.407,-1.375,2.273),Z,.104,.006,soil,18)
for i in range(12):
    a=i*2.4
    root=Vector((.407,-1.375,2.277))
    length=.115+.045*(i%3)
    stem=root+Vector((cos(a)*length,sin(a)*length,.13+.047*(i%4)))
    furn.beam(root,stem,.010,.009,leaves[0])
    tapered_leaf(furn,stem+Vector((.08*cos(a),.08*sin(a),.098)),root.lerp(stem,.48),.046,(-sin(a),cos(a),0),leaves[i%3])

for sign in [-1,1]:
    points=[(sign*.645,-1.641,2.027),(sign*.645,-1.641,2.44)]
    for i in range(1,12):
        t=i/11
        x=.645*(1-t**1.55)
        points.append((sign*x,-1.641,arch_top(x)))
    trim(joinery,points,.052,.116,brass)
    joinery.beam((sign*.355,-1.665,2.041),(sign*.355,-1.665,2.60),.028,.045,brass)
    trim(joinery,[(sign*.355,-1.665,2.60),(sign*.31,-1.665,2.72),(0,-1.665,3.00)],.028,.047,brass)
joinery.beam((0,-1.663,2.035),(0,-1.663,3.308),.043,.057,brass)
joinery.block((0,-1.668,2.007),(1.46,.155,.082),brass)
outline=[(-.64,-1.614,2.025),(.64,-1.614,2.025)]
for i in range(23):
    x=.64-i*1.28/22
    outline.append((x,-1.614,arch_top(x)-.015))
joinery.prism(outline,(0,.004,0),glass)

# The faction emblem is small furniture on a civilian front.
def plaque(outline,y,thick,mat):
    joinery.prism([(x,y,z) for x,z in outline],(0,thick,0),mat,Z)

def shield(cx,cz,scale,y,mat):
    poly=[(-.142,.13),(0,.192),(.142,.13),(.129,-.043),(.081,-.112),(0,-.182),(-.081,-.112),(-.129,-.043)]
    plaque([(cx+x*scale,cz+z*scale) for x,z in poly],y,.020,mat)

cx,cz=.85,2.34
shield(cx,cz,1,-1.672,brass_light)
shield(cx,cz,.88,-1.69,team)
star=[]
for i in range(16):
    angle=i*pi/8
    r=.081 if i%2==0 else .025
    star.append((cx+r*cos(angle),cz+.017+r*sin(angle)))
plaque(star,-1.707,.011,brass_light)
blade=[(-.012,.13),(.012,.13),(.012,.083),(.040,.078),(.040,.067),(.011,.066),(.009,-.087),(0,-.13),(-.009,-.087),(-.011,.066),(-.040,.067),(-.040,.078),(-.012,.083)]
plaque([(cx+x,cz+z) for x,z in blade],-1.720,.012,brass_light)

# Weatherboards and layered shingles follow the pitch; every course spans from
# one verge to the other. A roof edition can be attached to either named slope.
for sign,roof in [(-1,roofL),(1,roofR)]:
    def roof_panel(x0,x1,y0,y1,above,thickness,mat,grain=None):
        def pt(x,y): return (sign*x,y,roof_z(x)+above)
        roof.prism([pt(x0,y0),pt(x1,y0),pt(x1,y1),pt(x0,y1)],(0,0,thickness),mat,
                   grain if grain is not None else Vector((sign,0,-slope)))
    roof_panel(0,1.885,-1.928,1.928,-.078,.078,walnut,Y)
    for y in [-1.78,-1.46,-1.10,-.73,-.36,0,.36,.73,1.10,1.46,1.78]:
        roof.beam((sign*.015,y,roof_z(0)-.15),(sign*1.84,y,roof_z(1.84)-.15),.12,.108,fir)
    for i in range(9):
        # Lay eaves upward, with slight overlap and open end grain.
        low=1.875-i*.208
        high=max(0,low-.208-.035)
        joints=[-1.915,1.915]
        pitch=.382
        start=-1.915+pitch*((i%2)*.5+1)
        if i%2: joints.append(-1.915+pitch*.5)
        v=start
        while v<1.91:
            joints.append(v)
            v+=pitch
        joints=sorted(set(joints))
        for a,b in zip(joints,joints[1:]):
            if b-a < .03: continue
            y0,y1=a+.003,b-.003
            h=.077+(.006*rng.random())
            xlow=low+rng.uniform(-.009,.009)
            shape=[(sign*high,y0,roof_z(high)+.043),
                   (sign*xlow,y0,roof_z(xlow)+h),
                   (sign*xlow,y1,roof_z(xlow)+h),
                   (sign*high,y1,roof_z(high)+.043)]
            roof.prism(shape,(0,0,-.046),rng.choice(shakes),Vector((sign,0,-slope)))
    for y in [-1.948,1.948]:
        roof.beam((sign*.003,y,roof_z(0)+.040),(sign*1.906,y,roof_z(1.906)+.04),.13,.076,oxblood)
        roof.beam((sign*.003,y*.994,roof_z(0)-.064),(sign*1.899,y*.994,roof_z(1.899)-.064),.091,.085,oak)
    roof.block((sign*1.876,0,roof_z(1.876)-.002),(.045,3.91,.095),oxblood,Y)
ridge.block((0,0,roof_z(0)+.064),(.124,3.93,.108),oxblood)
ridge.block((0,0,roof_z(0)+.122),(.069,3.82,.015),brass)
for y in (-1.973,1.953):
    cap=[(-.113,y,roof_z(0)-.042),(0,y,roof_z(0)-.147),(.113,y,roof_z(0)-.042),
         (.073,y,roof_z(0)+.067),(-.073,y,roof_z(0)+.067)]
    ridge.prism(cap,(0,.020,0),oxblood)
    ridge.disk((0,y-.005 if y<0 else y+.02,roof_z(0)-.018),(0,-1 if y<0 else 1,0),.028,.008,brass)

# Recuperator on the side: the compact fan moves behind a finger-safe grille.
for sign in [-1,1]:
    y=.889
    joinery.block((sign*1.594,y,.70),(.06,.68,.426),gasket)
    for d in [-.33,.33]:
        joinery.block((sign*1.63,y+d,.70),(.05,.033,.435),brass)
    for d in [-.203,.203]:
        joinery.block((sign*1.63,y,.70+d),(.05,.695,.029),brass)
    for k in range(5):
        joinery.block((sign*1.638,y,.547+.072*k),(.056,.60,.026),walnut,Y)
fan.disk((-1.607,.889,.70),(-1,0,0),.050,.024,brass,16)
for k in range(5):
    a=2*pi*k/5
    o=Vector((-1.612,.889,.70))
    radial=Vector((0,cos(a),sin(a)))
    side=Vector((0,-sin(a),cos(a)))
    fan.prism([o+radial*.045,o+radial*.171+side*.012,o+radial*.146+side*.073,o+radial*.054+side*.023],(-.010,0,0),graphite,radial)

objects={name:part.finish() for name,part in sections.items()}

def nla(ob,name,keys):
    loc=ob.location.copy()
    rot=ob.rotation_euler.copy()
    for frame,offset,turn,scale in keys:
        ob.location=loc+Vector(offset)
        ob.rotation_euler=tuple(rot[i]+turn[i] for i in range(3))
        ob.scale=scale
        for prop in ["location","rotation_euler","scale"]:
            ob.keyframe_insert(data_path=prop,frame=frame,group=name)
    ad=ob.animation_data
    action=ad.action
    action.name=name+"_"+ob.name
    for fc in action.fcurves:
        for key in fc.keyframe_points:
            key.interpolation="LINEAR"
    track=ad.nla_tracks.new()
    track.name=name
    track.strips.new(name,0,action)
    ad.action=None
    track.mute=True
    ob.location=loc
    ob.rotation_euler=rot
    ob.scale=(1,1,1)

zero=(0,0,0)
one=(1,1,1)
tiny=(.001,.001,.001)
stages={"Stone_sill":(1,14),"Timber_portals":(12,42),"Cedar_walls":(35,61),
        "Door_and_windows":(53,72),"Loft_furnishings":(53,72),"Air_recovery_fan":(57,72),
        "Shingle_roof_west":(62,84),"Shingle_roof_east":(66,89),"Ridge_and_flashings":(83,96)}
for i,(name,ob) in enumerate(objects.items()):
    a,b=stages[name]
    under=(0,0,-.65 if name=="Stone_sill" else -max(.65,ob.location.z+.4))
    # Meshes enter in construction order. A roof half lowers onto its eave pivot.
    if name.startswith("Shingle_roof"):
        prep=[(a+1,(0,0,.25),zero,(.98,.99,.16))]
    else:
        prep=[(a+1,zero,zero,(1,1,.015))]
    construction=[(0,under,zero,tiny),(a,under,zero,tiny),*prep,(b,zero,zero,one)]
    if b<96:
        construction.append((96,zero,zero,one))
    nla(ob,"Build",construction)
    start=(5+i%4) if name not in ["Stone_sill","Timber_portals"] else 14+i%3
    rot_y={"Shingle_roof_west":.68,"Shingle_roof_east":-.61}.get(name,.09*(-1)**i)
    drop=-1.07 if "roof" in name else -.63
    nla(ob,"Die",[(0,zero,zero,one),(start,zero,zero,one),
                  (34,(.075*(-1)**i,.03,drop),(.03,rot_y,0),(1,1,.50)),
                  (54,(0,0,-4.35),(.03,rot_y,0),tiny)])
    if name=="Air_recovery_fan":
        nla(ob,"Idle",[(0,zero,zero,one),(24,zero,(pi,0,0),one),(48,zero,(2*pi,0,0),one),
                        (72,zero,(3*pi,0,0),one),(96,zero,(4*pi,0,0),one)])
    else:
        nla(ob,"Idle",[(0,zero,zero,one),(96,zero,zero,one)])

for ob in objects.values():
    for track in ob.animation_data.nla_tracks:
        track.mute=track.name!="Idle"
scene.frame_start=0
scene.frame_end=96
scene.frame_set(0)
bpy.context.view_layer.update()
bpy.ops.object.select_all(action="DESELECT")
group.select_set(True)
bpy.context.view_layer.objects.active=group
for screen in bpy.data.screens:
    for area in screen.areas:
        if area.type=="VIEW_3D":
            s=area.spaces.active
            s.overlay.show_overlays=False
            s.shading.color_type="MATERIAL"
            s.region_3d.view_distance=8.5
            s.region_3d.view_location=(0,0,1.75)
            s.region_3d.view_rotation=Vector((-.61,-.91,-.42)).to_track_quat("-Z","Y")
            s.region_3d.view_perspective="ORTHO"
target=HERE.parent/"House.blend"
bpy.ops.wm.save_as_mainfile(filepath=str(target),compress=True)
print("HOUSE_SAVED",target)
