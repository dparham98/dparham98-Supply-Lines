"""Add the field's five independent NLA clips and its separate Death effect to the open vineyard."""
from math import cos, pi, sin
from pathlib import Path
from random import Random
import sys

import bpy
from mathutils import Vector as V

HERE=Path(__file__).resolve().parent
sys.path.insert(0,str(HERE))
from vineyard_mesh import Batch, WHITE, material
from vineyard_irrigation import POSITIONS

ONE=(1,1,1)
SMALL=(.0001,.0001,.0001)
DURATION={'Idle':96,'Work':192,'Build':96,'Depleted':96,'Die':72}
scene=bpy.context.scene
scene.frame_start=1
scene.frame_end=DURATION['Idle']
scene.render.fps=24
scene.frame_set(0)
bpy.context.preferences.filepaths.save_version=0


def key_track(ob,name,path,keys):
    """Add keyed transforms to a single action per object and named glTF clip."""
    ad=ob.animation_data_create()
    action=bpy.data.actions.get(f"{name}_{ob.name}")
    if action is None: action=bpy.data.actions.new(f"{name}_{ob.name}")
    ad.action=action
    for frame,value in keys:
        setattr(ob,path,value)
        ob.keyframe_insert(data_path=path,frame=frame)
    ad.action=None
    track=ad.nla_tracks.get(name)
    if track is None:
        track=ad.nla_tracks.new()
        track.name=name
        strip=track.strips.new(name,0,action)
        strip.name=name
        strip.extrapolation='NOTHING'
    else:
        track.strips[0].action_frame_end=action.frame_range[1]
    track.mute=True


def constant(ob,clip,path,value):
    key_track(ob,clip,path,[(0,value),(DURATION[clip],value)])


def breeze(ob,clip,phase):
    total=DURATION[clip]
    # The complete crowns bend only a few millimetres. The grounded root never wanders.
    w=.006 if clip=='Idle' else .012
    keys=[]
    for j in range(17):
        a=2*pi*j/16
        keys.append((round(total*j/16),(w*(sin(a+phase)-sin(phase)),.35*w*(sin(2*a+phase)-sin(phase)),0)))
    key_track(ob,clip,'rotation_euler',keys)


def field_tracks():
    field=bpy.data.objects['farm_root']
    for clip in ['Idle','Work','Depleted']:
        constant(field,clip,'location',(0,0,0))
        constant(field,clip,'scale',ONE)
    key_track(field,'Build','scale',[(0,(.015,.015,.025)),(17,(.98,.98,.18)),(27,ONE),(96,ONE)])
    key_track(field,'Die','scale',[(0,ONE),(52,ONE),(72,(.95,.95,.01))])
    key_track(field,'Die','location',[(0,(0,0,0)),(48,(0,0,0)),(72,(0,0,-.21))])
    for i in range(6):
        row=bpy.data.objects[f"Vine_row_{i+1:02d}"]
        for clip in ['Idle','Work','Depleted']:
            constant(row,clip,'scale',ONE)
            breeze(row,clip,i*.73)
        start=13+i*5
        key_track(row,'Build','scale',[(0,SMALL),(start,SMALL),(start+12,(.84,.84,.33)),(start+37,ONE),(96,ONE)])
        key_track(row,'Die','scale',[(0,ONE),(8+i*2,ONE),(28+i*3,(1.03,1.0,.55)),(60,(1,1,.04)),(72,(1,1,.04))])
        key_track(row,'Die','rotation_euler',[(0,(0,0,0)),(7,(0,0,0)),(13,((i%3-1)*.025,.055,0)),(37,(.0,.20*(-1 if i%2 else 1),0)),(72,(0,0,0))])
        fruit=bpy.data.objects[f"Grape_bunches_{i+1:02d}"]
        for clip in ['Idle','Work','Build','Die']: constant(fruit,clip,'scale',ONE)
        # Only the optional art-review Depleted shows stripped vines. Renewable gameplay stays on Idle/Work.
        constant(fruit,'Depleted','scale',SMALL)
    for name,(x,y,z) in POSITIONS.items():
        rig=bpy.data.objects["Irrigator_"+name]
        water=bpy.data.objects["Water_"+name]
        phase=0 if name=='West' else pi
        for clip in ['Idle','Depleted']:
            keys=[]
            for j in range(9):
                f=DURATION[clip]*j//8; ang=2*pi*j/8
                keys.append((f,(x,y,z+.032*sin(ang+phase))))
            key_track(rig,clip,'location',keys)
            constant(rig,clip,'scale',ONE)
            constant(rig,clip,'rotation_euler',(0,0,0))
            constant(water,clip,'scale',SMALL)
        work_locs=[]; bank=[]; mist=[]
        for j in range(33):
            a=2*pi*j/32
            work_locs.append((6*j,(x+.065*sin(2*a+phase),y*cos(a),z+.030*sin(2*a+phase))))
            bank.append((6*j,(.027*sin(a+phase),.015*sin(2*a+phase),.031*sin(a+phase))))
            # Gentle flow modulation around full strength. Inactive clips collapse both spray meshes.
            mist.append((6*j,(1+.026*sin(3*a+phase),1+.11*sin(5*a+phase),1+.055*sin(4*a+phase))))
        key_track(rig,'Work','location',work_locs)
        key_track(rig,'Work','rotation_euler',bank)
        constant(rig,'Work','scale',ONE)
        key_track(water,'Work','scale',mist)
        for clip in ['Build','Die']: constant(water,clip,'scale',SMALL)
        key_track(rig,'Build','location',[(0,(x,y,.04)),(51,(x,y,.04)),(80,(x,y,z+.09)),(96,(x,y,z))])
        key_track(rig,'Build','scale',[(0,SMALL),(49,SMALL),(67,ONE),(96,ONE)])
        key_track(rig,'Die','location',[(0,(x,y,z)),(11,(x+.02,y,z+.09)),(24,(x+.26,y+.21,.18)),(72,(x+.26,y+.21,.15))])
        key_track(rig,'Die','rotation_euler',[(0,(0,0,0)),(11,(.12,.13,0)),(26,(.46,.40,.27)),(72,(.46,.40,.27))])
        key_track(rig,'Die','scale',[(0,ONE),(43,ONE),(60,SMALL),(72,SMALL)])


def death_fx():
    coll=bpy.data.collections.new('farm_death_fx')
    scene.collection.children.link(coll)
    rng=Random(983)
    dust=material('Vineyard dust',(.36,.26,.15),roughness=1.,alpha=.21)
    gleam=material('Vineyard spilled water',(.58,.84,.9),roughness=.24,alpha=.61,glow=.29)
    leafmat=material("Scattered leaves",painted=True,roughness=.95)
    flash=material("Fault light",(.9,.56,.17),glow=1.1)
    for i in range(10):
        b=Batch(gleam if i<5 else leafmat)
        for j in range(7):
            a=rng.random()*2*pi;r=rng.uniform(.03,.28)
            c=V((r*cos(a),r*sin(a),rng.uniform(0,.19)))
            if i<5:b.ellipsoid(c,(.016,.017,.041),WHITE,5,1)
            else:
                b.patch([c+V((-.03,0,0)),c+V((.003,-.012,.014)),c+V((.05,.02,0)),c+V((0,.071,-.004))],[(0,1,3),(1,2,3)],(.24,.244,.044))
        obj=b.bake(f"Valve_splash_{i}" if i<5 else f"Falling_leaves_{i}",coll)
        x,y,z=POSITIONS['West' if i%2==0 else 'East']
        start=9+i%5
        key_track(obj,'Death','scale',[(0,SMALL),(start,SMALL),(start+3,ONE),(start+17,ONE),(start+26,SMALL),(72,SMALL)])
        key_track(obj,'Death','location',[(0,(x,y,.17)),(start,(x,y,.17)),(start+7,(x+rng.uniform(-.23,.23),y,.83)),(start+25,(x+rng.uniform(-.48,.48),y+.31,.13)),(72,(x,y,.13))])
    for i,(x,y,z) in enumerate(POSITIONS.values()):
        b=Batch(dust)
        for j in range(6):
            a=j*pi/3
            b.ellipsoid((.2*cos(a),.13*sin(a),.07),(.22,.17,.15),WHITE,7,1)
        o=b.bake(f"Dust_at_landing_{i}",coll)
        key_track(o,'Death','location',[(0,(x,y,.12)),(21,(x,y,.12)),(45,(x+.26,y,.29)),(72,(x+.28,y,.34))])
        key_track(o,'Death','scale',[(0,SMALL),(20,SMALL),(27,ONE),(38,(1.6,1.35,1.22)),(53,SMALL),(72,SMALL)])
    b=Batch(flash)
    b.ellipsoid((0,0,0),(.095,.08,.06),WHITE,7,2)
    o=b.bake("Valve_flash",coll)
    key_track(o,'Death','location',[(0,(-2.08,-2.70,1.18)),(72,(-2.08,-2.70,1.18))])
    key_track(o,'Death','scale',[(0,SMALL),(6,SMALL),(7,ONE),(9,SMALL),(72,SMALL)])
    return coll


def main():
    field_tracks()
    fx=death_fx()
    for ob in bpy.data.objects:
        if ob.animation_data:
            for tr in ob.animation_data.nla_tracks: tr.mute = tr.name!='Idle'
    bpy.context.view_layer.layer_collection.children[fx.name].exclude=True
    scene.frame_set(1)
    bpy.ops.wm.save_as_mainfile(filepath=bpy.data.filepath,compress=True)
    print("VINEYARD RIGGED",len(bpy.data.actions),"actions")

if __name__=='__main__': main()
