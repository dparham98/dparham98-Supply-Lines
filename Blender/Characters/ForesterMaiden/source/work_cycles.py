"""Pose and bake the Forester's in-place work and travel cycles at 24 fps."""
from math import cos, pi, radians, sin, sqrt

import bpy
from mathutils import Matrix, Quaternion, Vector

from arms_axe import AXIS, WING, centerline

FPS = 24
PERIODS = {"Walk": 28, "Chop": 42, "Gather": 72, "Carry": 32, "Build": 36, "Till": 48, "CarryFood": 32}
SPEEDS = {"Walk": 1.16, "Carry": .84, "CarryFood": .84}
GRIPS = {"R": centerline(.235), "L": centerline(.648)}
V = Vector
I = Matrix.Identity(4)


def rx(angle):
    return Matrix.Rotation(radians(angle),4,'X')


def ry(angle):
    return Matrix.Rotation(radians(angle),4,'Y')


def rz(angle):
    return Matrix.Rotation(radians(angle),4,'Z')


def trans(point):
    return Matrix.Translation(V(point))


def pivot(point, rotation):
    return trans(point) @ rotation @ trans(-point)


def align(source, target, rotation):
    return trans(target) @ rotation @ trans(-source)


def frame_axes(axis, blade):
    y=V(axis).normalized()
    x=(V(blade)-y*V(blade).dot(y)).normalized()
    return Matrix((x,y,x.cross(y))).transposed()


def oriented(source, target, axis, blade):
    rotation=frame_axes(axis,blade) @ frame_axes(AXIS,WING).transposed()
    return align(source,target,rotation.to_4x4())


def sample(frame, points):
    """Cubic ease between distinct action landmarks, including scalar tuples."""
    for (a, start),(b, end) in zip(points,points[1:]):
        if frame<=b:
            t=min(1,max(0,(frame-a)/(b-a)))
            t=t*t*(3-2*t)
            return tuple(v+(w-v)*t for v,w in zip(start,end))
    return points[-1][1]


def two_bone(a, c, pole, upper, lower):
    line=c-a
    d=line.length
    if d>upper+lower+.0003 or d<abs(upper-lower)-.0003:
        raise ValueError(f"Target distance {d:.4f}, permitted {abs(upper-lower):.4f}–{upper+lower:.4f}")
    axis=line.normalized()
    center=(upper*upper-lower*lower+d*d)/(2*d)
    toward=pole-a
    normal=(toward-axis*toward.dot(axis)).normalized()
    return a+axis*center+normal*sqrt(max(0,upper*upper-center*center))


class Pose:
    """Build a single frame in armature space; local channels stay editable."""
    def __init__(self, rig):
        self.rig=rig
        self.bones=rig.data.bones
        self.rest={b.name:b.matrix_local.copy() for b in self.bones}
        self.inv={name:m.inverted() for name,m in self.rest.items()}
        self.previous={}
        self.world={}

    def parent(self, name):
        p=self.bones[name].parent
        return self.get(p.name)@self.inv[p.name]@self.rest[name] if p else self.rest[name]

    def get(self, name):
        return self.world[name] if name in self.world else self.parent(name)

    def delta(self, name):
        return self.get(name)@self.inv[name]

    def bend(self, name, pitch=0, yaw=0, roll=0):
        if name in self.rest:
            rot=rz(yaw)@ry(roll)@rx(pitch)
            self.world[name]=self.parent(name)@self.inv[name]@pivot(self.rest[name].translation,rot)@self.rest[name]

    def aim(self,name,start,end,transport):
        bone=self.bones[name]
        r=transport.to_3x3()
        direction=r@(bone.tail_local-bone.head_local)
        out=(direction.rotation_difference(end-start).to_matrix()@r@self.rest[name].to_3x3()).to_4x4()
        out.translation=start
        self.world[name]=out

    def limb(self,names,end,pole,transport):
        a,b,c=names
        start=self.parent(a).translation
        try:
            joint=two_bone(start,end.translation,pole,self.bones[a].length,self.bones[b].length)
        except ValueError as err:
            raise ValueError(f"{a} from {start[:]} to {end.translation[:]}: {err}") from err
        self.aim(a,start,joint,transport)
        self.aim(b,joint,end.translation,transport)
        self.world[c]=end

    def record(self, frame):
        for name,world in self.world.items():
            local=self.parent(name).inverted() @ world
            loc,q,_=local.decompose()
            if name in self.previous:
                q.make_compatible(self.previous[name])
            self.previous[name]=q.copy()
            pb=self.rig.pose.bones[name]
            pb.rotation_mode='QUATERNION'
            pb.rotation_quaternion=q
            pb.keyframe_insert("rotation_quaternion",frame=frame,group=name)
            if name in {"pelvis","tool","hammer","load","skirt.front","skirt.back"}:
                pb.location=loc
                pb.keyframe_insert("location",frame=frame,group=name)


def footstep(pose,side,time,name):
    phase=(time/PERIODS[name]+(.5 if side=="L" else 0))%1.
    stride=SPEEDS[name]*PERIODS[name]/FPS
    contact=.555
    ankle=pose.rest["foot."+side].translation
    ball=pose.rest["toe."+side].translation
    # Constant rearward ground speed while planted cancels the actor's travel.
    if phase<=contact:
        offset=stride*(phase-contact/2)
        turn=max(0,(phase-.48)/(contact-.48))
        pitch=19*turn*turn
        roll=pivot(ball,rx(pitch))
        return trans((0,offset,0))@roll,trans((0,offset,0))
    u=(phase-contact)/(1-contact)
    # Hermite endpoint velocities are the same as the planted velocity.
    blend=u*u*(3-2*u)
    offset=stride*(contact/2+(1-contact)*u-blend)
    h=(.130 if name=="Walk" else .090)*sin(pi*u)**1.4
    pitch,=sample(u,[(0,(19,)),(.32,(31,)),(.65,(6,)),(.81,(-10,)),(1,(0,))])
    s=1 if side=="L" else -1
    turn=pivot(ball,rx(19))@ankle-ankle
    offset_y=offset+turn.y*(1-blend)
    d=trans((s*.012*sin(pi*u)**2,offset_y,h+turn.z*(1-blend)))@pivot(ankle,rx(pitch))
    toe=pivot(d@ball,rx(-19*(1-blend)))@d
    return d,toe


def body(p,d,spine,look,follow):
    # d = lateral/fore/vertical offset, pelvic pitch/yaw/roll.
    x,y,z,pitch,yaw,roll=d
    hips=p.rest["pelvis"].translation
    p.world["pelvis"]=trans((x,y,z))@pivot(hips,rz(yaw)@ry(roll)@rx(pitch))@p.rest["pelvis"]
    bend,twist,sway=spine
    for name,portion in [("spine.01",.36),("spine.02",.39),("chest",.25)]:
        p.bend(name,bend*portion,twist*portion,sway*portion)
    nod,turn=look
    p.bend("neck",nod*.55,turn*.43)
    p.bend("head",nod*.45,turn*.57)
    drag,lateral=follow
    for i,name in enumerate(["braid.01","braid.02","braid.03"]):
        p.bend(name,drag*(.47-.07*i),0,lateral*(.43+.045*i))


def stance(p,feet,close_squat=False):
    for side,(foot,toe) in feet.items():
        s=1 if side=="L" else -1
        end=foot@p.rest["foot."+side]
        low=min(1,max(0,(.57-p.get("pelvis").translation.z)/.215))
        pole=V((s*((.22 if side=="L" else .25)+(.19 if close_squat else .58)*low),
                -.93+(.08 if close_squat else .45)*low,.48+.58*low))
        p.limb(("thigh."+side,"shin."+side,"foot."+side),end,pole,I)
        p.world["toe."+side]=toe@p.rest["toe."+side]
    hips=p.delta("pelvis")
    # The front apron always clears the leading thigh while its waist stays pinned.
    slopes=[]
    for side in ["L","R"]:
        a=p.world["thigh."+side].translation
        b=p.world["shin."+side].translation
        direction=hips.to_3x3().inverted()@(b-a).normalized()
        slopes.append(min(0,direction.y))
    lead=-min(slopes)
    p.bend("skirt.front",-5-52*lead,0,(slopes[0]-slopes[1])*2.8)
    p.bend("skirt.back",4+8*lead)


def arms(p, grips, lift=0):
    chest=p.delta("chest")
    for side,(point,hand_delta) in grips.items():
        s=1 if side=="L" else -1
        p.bend("clavicle."+side,-lift*.12,0,-s*lift*.34)
        wrist=hand_delta@p.rest["hand."+side]
        wrist.translation=point
        pole=chest@V((s*.59,.025,1.02))+V((0,lift*.0007,0))
        p.limb(("upper_arm."+side,"forearm."+side,"hand."+side),wrist,pole,chest)


def object_grips(p,delta):
    return {s:((delta@p.rest["hand."+s]).translation,delta) for s in ("R","L")}


def stride_body(phase,loaded):
    w=cos(phase)
    return ((-.018*cos(phase-.44),-.012 if loaded else -.007,
             (-.088 if loaded else -.092)-.019*cos(2*phase-.39),
             3.0 if loaded else 1.8,-3.5*w,1.65*sin(phase)),
            (6.2 if loaded else 2.7,5.5*w, -1.5*sin(phase)),(-3.5 if loaded else -2.3, -1.8*w),
            (2+2.9*sin(2*phase-.2),3.8*sin(phase-.4)))


def lower_stance(p,name,t):
    phase=2*pi*t/PERIODS[name]
    body(p,*stride_body(phase,name!="Walk"))
    stance(p,{s:footstep(p,s,t,name) for s in ("R","L")})
    return phase


def axe_carry(p,phase):
    chest=p.delta("chest")
    anchor=(GRIPS["L"]+GRIPS["R"])*.5
    d=chest@trans((0,-.010,.012+.007*cos(2*phase-.4)))@pivot(anchor,ry(2*sin(phase))@rx(-3+2*sin(2*phase)))
    p.world["tool"]=d@p.rest["tool"]
    arms(p,object_grips(p,d))


def fixed_feet(mode):
    marks={"Chop":(.024,-.095,.082),"Build":(.017,-.060,.065),"Till":(.035,-.115,.10)}
    widen,right,left=marks[mode]
    return {s:(trans(((1 if s=="L" else -1)*widen,left if s=="L" else right,0)),)*2 for s in ("L","R")}


# These are upper-grip, haft-axis and blade-edge landmarks. Both closed hands
# and the two grip wraps travel under the same rigid transform through each cut.
CHOP=[
    (0,(-.12,-.29,1.16, .69,.02,-.72, 0,-.82,-.50)),
    (9,(-.19,-.22,1.48, .49,-.06,-.87, 0,-.96,.17)),
    (13,(-.19,-.15,1.55, .45,-.09,-.89, 0,-.97,.18)),
    (16,(-.18,-.33,1.43, .53,.65,-.55, 0,-.76,-.65)),
    (20,(-.14,-.47,.90, .52,.72,.46, 0,.25,-.97)),
    (22,(-.14,-.455,.89, .52,.72,.46, 0,.25,-.97)),
    (26,(-.13,-.443,.925, .52,.74,.40, 0,.21,-.98)),
    (32,(-.12,-.37,1.06, .65,.71,-.26, 0,-.63,-.78)),
    (42,(-.12,-.29,1.16, .69,.02,-.72, 0,-.82,-.50))]

TILL=[
    (0,(-.13,-.37,.91, .55,.71,.44, 0,.27,-.96)),
    (8,(-.15,-.37,1.02, .58,.76,.29, 0,.19,-.98)),
    (12,(-.16,-.42,.96, .46,.78,.42, 0,.29,-.96)),
    (17,(-.14,-.54,.407, .33,.68,.65, 0,.48,-.88)),
    (21,(-.13,-.52,.402, .31,.66,.68, 0,.43,-.90)),
    (30,(-.105,-.36,.428, .39,.50,.77, 0,.40,-.90)),
    (36,(-.12,-.31,.66, .46,.49,.74, 0,.44,-.90)),
    (43,(-.13,-.35,.83, .55,.67,.50, 0,.34,-.94)),
    (48,(-.13,-.37,.91, .55,.71,.44, 0,.27,-.96))]


def axe_work(p,name,t):
    if name=="Chop":
        points=[(0,(.00,.00,-.076,5,4,2,5)),(12,(-.042,.035,-.073,-5,13,0,-7)),
                (16,(-.028,.012,-.087,2,7,1,1)),(20,(.007,-.065,-.124,14,-11,3,12)),
                (24,(.011,-.06,-.138,15,-12,3,13)),(33,(.003,-.025,-.092,8,-2,4,8)),
                (42,(.00,.00,-.076,5,4,2,5))]
    else:
        points=[(0,(.013,-.032,-.145,17,-5,3,12)),(9,(-.007,-.055,-.170,20,0,2,14)),
                (17,(-.035,-.10,-.384,36,7,2,32)),(22,(-.04,-.11,-.385,37,6,1,33)),
                (31,(.01,-.077,-.378,33,-6,-2,29)),(38,(.029,-.04,-.186,21,-10,-3,17)),
                (48,(.013,-.032,-.145,17,-5,3,12))]
    x,y,z,pitch,yaw,roll,bend=sample(t,points)
    if name=="Till":
        z-=.043
    w=2*pi*t/PERIODS[name]
    body(p,(x,y,z,pitch,yaw,roll),(bend, -yaw*.36,-roll*.3),
         (6-.44*pitch,-yaw*.28),(3*sin(w-.6)+.12*bend,4*cos(w-.48)))
    stance(p,fixed_feet(name))
    path=sample(t,CHOP if name=="Chop" else TILL)
    d=oriented(GRIPS["R"],V(path[:3]),path[3:6],path[6:9])
    # Turn the haft across the torso at the working hand so the long butt
    # passes outside the forward shoulder.
    if name=="Chop":
        sweep,=sample(t,[(0,(0.,)),(12,(-5.,)),(16,(-43.,)),(23,(-52.,)),
                         (30,(-49.,)),(35,(-25.,)),(42,(0.,))])
    else:
        sweep=-59.
    d=pivot(d@GRIPS["R"],rz(sweep))@d
    if name=="Till":
        d=trans((-.024,-.100,0))@d
    p.world["tool"]=d@p.rest["tool"]
    arms(p,object_grips(p,d),max(0,(path[2]-1.24)*78))


BUNDLE=V((0,-.282,1.130))
BUNDLE_GRIP={s:V((x,-.327,1.065)) for s,x in [("L",.163),("R",-.163)]}
GROUND_CENTER=V((-.003,-.636,.07950))
HAMMER_FACE=V((-.4387,-.2502,1.2761))
NAIL=V((-.14,-.492,.906))


def loaded_hands(p,delta):
    towards_log=frame_axes((1,0,0),(0,0,-1))@frame_axes(AXIS,WING).transposed()
    targets={}
    for side in ["R","L"]:
        hand=align(GRIPS[side],BUNDLE_GRIP[side],towards_log.to_4x4())
        hand=delta@hand
        targets[side]=((hand@p.rest["hand."+side]).translation,hand)
    return targets


def carry_delta(p,phase):
    return (p.delta("chest")@trans((0,-.008,.099+.004*sin(2*phase-.52)))
            @pivot(BUNDLE,rz(2*sin(phase-.6))@rx(-3+.9*sin(2*phase))))


def carry_food(p,phase):
    from harvest_trug import CENTER, GRIP
    # Keep the trug level as the hips roll and the chest counter-rotates.
    # Both palms wrap the same rigid hoop, with a small lift on the passing step.
    hip=p.get("pelvis").translation-p.rest["pelvis"].translation
    delta=trans((hip.x*.65,-.006,hip.z*.54+.006*cos(2*phase-.4)))@pivot(
        CENTER,rz(1.3*cos(phase-.30))@rx(-.8+.7*sin(2*phase))@ry(.95*sin(phase-.15)))
    p.world["load"]=delta@p.rest["load"]
    grip_rotation=frame_axes((1,0,0),(0,0,-1))@frame_axes(AXIS,WING).transposed()
    hands={}
    for s in ("R","L"):
        hand=delta@align(GRIPS[s],GRIP[s],grip_rotation.to_4x4())
        hands[s]=((hand@p.rest["hand."+s]).translation,hand)
    arms(p,hands)


def blend_tuples(u,a,b):
    return tuple(v+(w-v)*u for v,w in zip(a,b))


def gather(p,t):
    # The ground bundle remains planted while hands approach and withdraw.
    # Its exposed billet faces up for pickup and rolls into the worker's palms.
    crouch,=sample(t,[(0,(.02,)),(5,(.05,)),(14,(.60,)),(22,(1.,)),(26,(1.,)),
                      (33,(.57,)),(41,(0.,)),(45,(0.,)),(53,(.54,)),(57,(1.,)),
                      (62,(1.,)),(68,(.35,)),(72,(.02,))])
    grip,=sample(t,[(0,(0.,)),(8,(.12,)),(16,(.48,)),(22,(1.,)),(59,(1.,)),
                    (66,(.37,)),(72,(0.,))])
    lift,=sample(t,[(0,(0.,)),(25,(0.,)),(33,(.44,)),(41,(1.,)),(45,(1.,)),
                    (53,(.40,)),(58,(0.,)),(72,(0.,))])
    if 25<=t<=58:
        crouch=1-lift
    stand=stride_body(0,True)
    body(p,*stand)
    high_delta=carry_delta(p,0)
    crouched=((.012,-.12,-.565,50,-2,0),(43,3,0),(-31,1),(17,-2))
    body(p,*(blend_tuples(crouch,a,b) for a,b in zip(stand,crouched)))
    # Set the left boot alongside the pickup, then step back into the carrying
    # stride once the load clears the ground. The right boot stays planted.
    feet={s:footstep(p,s,0,"Carry") for s in ("R","L")}
    plant,=sample(t,[(0,(1.,)),(28,(1.,)),(40,(0.,)),(46,(0.,)),(57,(1.,)),(72,(1.,))])
    boot=trans((0,-.43*plant,.092*sin(pi*plant)))
    feet["L"]=tuple(boot@d for d in feet["L"])
    stance(p,feet,close_squat=True)
    ground=align(BUNDLE,GROUND_CENTER,rx(-116))
    # Rotate about the billet bundle's center, not the armature origin.
    center=GROUND_CENTER.lerp(high_delta@BUNDLE,lift)
    center.z+=.092*sin(pi*lift)
    rot=ground.to_quaternion().slerp(high_delta.to_quaternion(),lift)
    delta=align(BUNDLE,center,rot.to_matrix().to_4x4())
    p.world["load"]=delta@p.rest["load"]
    loaded=loaded_hands(p,delta)
    targets={}
    chest=p.delta("chest")
    for side,(wrist,hand) in loaded.items():
        s=1 if side=="L" else -1
        free=chest@align(p.rest["hand."+side].translation,
                         V((s*.21,-.11,1.035)),rx(-10)@rz(s*18))
        free_wrist=(free@p.rest["hand."+side]).translation
        point=free_wrist.lerp(wrist,grip)
        if grip<.999:
            shoulder=p.parent("upper_arm."+side).translation
            offset=point-shoulder
            reach=p.bones["upper_arm."+side].length+p.bones["forearm."+side].length-.012
            if offset.length>reach:
                point=shoulder+offset.normalized()*reach
        targets[side]=(point,free.lerp(hand,grip))
    arms(p,targets)
    release,=sample(t,[(0,(.55,)),(18,(.83,)),(24,(0.,)),(58,(0.,)),(62,(.83,)),(72,(.55,))])
    return {"R":release,"L":release}


def build_work(p,t):
    # The two taps have different lifts. The bracing hand stays a hand-span
    # from the strike face and keeps the workpiece steady through both blows.
    up,=sample(t,[(0,(.38,)),(6,(1.,)),(8,(.98,)),(12,(0.,)),(13,(0.,)),
                  (16,(.41,)),(21,(.68,)),(23,(.67,)),(27,(0.,)),(28,(0.,)),
                  (31,(.20,)),(36,(.38,))])
    lean=1-up
    body(p,(-.018-.013*lean,-.032-.019*lean,-.105-.019*lean,10+7*lean,-4+5*up,1.2),
         (9+5*lean,-3+5*up,-2),(7-4*lean,-4),(2.2+4*up,1.3-2*lean))
    stance(p,fixed_feet("Build"))
    head=NAIL+V((-.081*up,.060*up,.313*up))
    d=oriented(HAMMER_FACE,head,(.50-.12*up,.86-.26*up,-.82*up),(0,-.34*up,-1))
    p.world["hammer"]=d@p.rest["hammer"]
    grips=object_grips(p,d)
    # Rotate the closed grasp to put the back of the open glove facing up.
    left=align(p.rest["hand.L"].translation,V((.17,-.391,.963)),rx(15)@ry(-49)@rz(-13))
    grips["L"]=((left@p.rest["hand.L"]).translation,left)
    arms(p,grips,5*up)
    return {"L":.88,"R":0.}


def set_digits(p,openness,frame):
    from rig import open_hand
    for side,amount in openness.items():
        open_hand(p.rig,side,amount)
        for bone in p.rig.pose.bones:
            if bone.name.endswith("."+side) and bone.name.split(".")[0] in {"thumb","index","middle","ring","pinky"}:
                q=bone.rotation_quaternion.copy()
                if bone.name in p.previous:
                    q.make_compatible(p.previous[bone.name])
                p.previous[bone.name]=q.copy()
                bone.rotation_quaternion=q
                bone.keyframe_insert("rotation_quaternion",frame=frame,group=bone.name)


def make_pose(p,name,t):
    p.world.clear()
    if name in SPEEDS:
        wave=lower_stance(p,name,t)
        if name=="Walk":
            axe_carry(p,wave)
        elif name=="CarryFood":
            carry_food(p,wave)
        else:
            d=carry_delta(p,wave)
            p.world["load"]=d@p.rest["load"]
            arms(p,loaded_hands(p,d))
    elif name in {"Chop","Till"}:
        axe_work(p,name,t)
    elif name=="Gather":
        return gather(p,t)
    elif name=="Build":
        return build_work(p,t)
    return {"R":0.,"L":0.}


def build_actions(rig):
    scene=bpy.context.scene
    scene.render.fps,scene.render.fps_base=FPS,1.
    data=rig.animation_data_create()
    actions={}
    for name,period in PERIODS.items():
        pose=Pose(rig)
        existing=data.nla_tracks.get(name)
        if existing:
            prior=existing.strips[0].action if existing.strips else None
            data.nla_tracks.remove(existing)
            if prior and prior.name==name:
                prior.use_fake_user=False
                if prior.users==0:
                    bpy.data.actions.remove(prior)
        for pb in rig.pose.bones:
            pb.matrix_basis=I
        action=bpy.data.actions.new(name)
        data.action=action
        for frame in range(1,period+2):
            try:
                opened=make_pose(pose,name,(frame-1)%period)
                pose.record(frame)
                if any(pb.name.startswith("index.") for pb in rig.pose.bones):
                    set_digits(pose,opened,frame)
            except Exception as err:
                raise RuntimeError(f"{name} frame {frame}: {err}") from err
        for curve in action.fcurves:
            for key in curve.keyframe_points:
                key.interpolation='LINEAR'
        action.use_fake_user=True
        action.use_cyclic=True
        if name in SPEEDS:
            action["forward_speed_mps"]=SPEEDS[name]
        actions[name]=action
        data.action=None
        track=data.nla_tracks.new()
        track.name=name
        strip=track.strips.new(name,1,action)
        strip.extrapolation='NOTHING'
        track.mute=True
    for pb in rig.pose.bones:
        pb.matrix_basis=I
    scene.frame_start,scene.frame_end=1,max(PERIODS.values())
    scene.frame_set(0)
    bpy.context.view_layer.update()
    return actions
