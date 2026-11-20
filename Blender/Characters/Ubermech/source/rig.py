"""Rigid armour skeleton and the Ubermech's baked 30 fps game actions."""
from math import cos, pi, radians, sin, sqrt

import bpy
from mathutils import Matrix, Quaternion, Vector


FPS = 30
WALK_SPEED = 3.10
PERIODS = {"Rest": 60, "Walk": 36, "Shoot": 36, "PodVolley": 60}
FORWARD = Vector((0, -1, 0))
SIDES = (("R",-1),("L",1))
RELEASE_FRAME = 12   # Elapsed frames. Blender frame 1 is exported time zero.
POD_RELEASES = ((12,1),(17,4),(22,5),(27,2),(32,3),(37,6))


def end_face(obj):
    """Find the two end polygons of a lathed part, before its edge bevel."""
    caps=sorted(obj.data.polygons,key=lambda p: len(p.vertices),reverse=True)[:2]
    centres=[obj.matrix_world @ p.center for p in caps]
    tip,base=sorted(centres,key=lambda v:v.y)
    return tip,(tip-base).normalized()


def muzzle_frame(pieces):
    core=next(obj for obj in pieces if obj.name.startswith("Emitter | radiant core"))
    return end_face(core)


def skeleton(pieces):
    tip,axis=muzzle_frame(pieces)
    layout=[("Pelvis",None,(0,0,2.56),(0,0,2.90)),
            ("Chest","Pelvis",(0,0,2.96),(0,0,4.22)),
            ("Head","Chest",(0,0,4.30),(0,0,4.88))]
    for side,s in SIDES:
        def link(label,parent,start,end):
            layout.append((label+"."+side,parent,start,end))
        sh=(s*1.19,0,4);el=(s*1.61,-.05,3.18)
        hip=(s*.65,0,2.56);knee=(s*.79,-.11,1.47);ankle=(s*.90,.015,.48)
        link("Shoulder","Chest",sh,(s*1.4,0,4.13))
        link("UpperArm","Shoulder."+side,sh,el)
        link("Forearm","UpperArm."+side,el,(s*1.79,-.32,2.55))
        link("Tasset","Pelvis",(s*.53,0,2.81),(s*.63,-.14,2.18))
        link("Thigh","Pelvis",hip,knee)
        link("Shin","Thigh."+side,knee,ankle)
        link("Foot","Shin."+side,ankle,(s*.90,-.48,.16))
    layout.append(("Muzzle","Forearm.R",tip,tip+.21*axis))
    part={obj.name:obj for obj in pieces}
    band=part["Emitter | steel bridge band"]
    band_front,_=end_face(band)
    layout.append(("EmitterSlide","Forearm.R",band_front,band_front+.12*axis))
    band["joint"]="EmitterSlide"
    for port in range(1,7):
        cap=part[f"Pod | crimson ogive {port}"]
        point,pod_axis=end_face(cap)
        port_name=f"Pod{port:02d}"
        cap_name=f"PodCap{port:02d}"
        layout.append((port_name,"Forearm.L",point,point+.15*pod_axis))
        layout.append((cap_name,port_name,point,point+.08*pod_axis))
        cap["joint"]=cap_name
    arm_data=bpy.data.armatures.new("Ubermech linkages")
    arm=bpy.data.objects.new("Ubermech Rig",arm_data)
    bpy.context.scene.collection.objects.link(arm)
    bpy.ops.object.select_all(action="DESELECT")
    arm.select_set(True);bpy.context.view_layer.objects.active=arm
    bpy.ops.object.mode_set(mode="EDIT")
    for name,parent,h,t in layout:
        bone=arm_data.edit_bones.new(name)
        bone.head=h;bone.tail=t
        if parent:
            bone.parent=arm_data.edit_bones[parent]
    bpy.ops.object.mode_set(mode="OBJECT")
    arm_data.display_type='STICK'
    arm.show_in_front=False
    arm["muzzle_rest_axis"]=list(axis)
    arm["muzzle_rest_point"]=list(tip)
    arm["pod_rest_axis"]=list(pod_axis)
    arm["walk_speed_mps"]=WALK_SPEED
    for obj in pieces:
        bone=arm_data.bones[obj["joint"]]
        world=obj.matrix_world.copy()
        obj.parent=arm;obj.parent_type="BONE";obj.parent_bone=bone.name
        # Blender's rigid attachment includes an offset to the bone's tail.
        obj.matrix_parent_inverse=(bone.matrix_local @ Matrix.Translation((0,bone.length,0))).inverted()
        obj.matrix_basis=world
    bpy.context.view_layer.update()
    return arm


def turn(axis,degrees):
    return Quaternion(axis,radians(degrees))


def at(matrix,pivot,rotation):
    """Rotate an existing pose about its joint in armature space."""
    return Matrix.Translation(pivot) @ rotation.to_matrix().to_4x4() @ Matrix.Translation(-pivot) @ matrix


class Pose:
    def __init__(self,arm):
        self.arm=arm
        self.rest={b.name:b.matrix_local.copy() for b in arm.data.bones}
        self.parents={b.name:b.parent.name if b.parent else None for b in arm.data.bones}
        self.relative={n:self.rest[p].inverted()@m if p else m for n,m in self.rest.items()
                       for p in [self.parents[n]]}
        self.world={}
        self.previous={}

    def get(self,name):
        if name in self.world:
            return self.world[name]
        parent=self.parents[name]
        return self.get(parent)@self.relative[name] if parent else self.rest[name]

    def move(self,name,rotation,offset=None):
        inherited=self.get(name)
        self.world[name]=at(inherited,inherited.translation,rotation)
        if offset is not None:
            self.world[name].translation+=Vector(offset)

    def rigid(self,name,origin,rotation):
        rest=self.rest[name]
        self.world[name]=Matrix.Translation(origin)@rotation.to_matrix().to_4x4()@Matrix.Translation(-rest.translation)@rest

    def slide(self,name,distance):
        # The controls' local +Y directions coincide with their machined axes.
        self.world[name]=self.get(name)@Matrix.Translation((0,distance,0))

    def limb(self,name,origin,original,target):
        q=original.normalized().rotation_difference(target.normalized())
        self.rigid(name,origin,q)
        return q

    def record(self,frame):
        for bone in self.arm.pose.bones:
            name=bone.name
            parent=self.parents[name]
            base=self.get(parent)@self.relative[name] if parent else self.rest[name]
            delta=base.inverted()@self.get(name)
            loc=delta.translation
            if loc.length<.000001:loc=Vector((0,0,0))
            q=delta.to_quaternion().normalized()
            if name in self.previous:q.make_compatible(self.previous[name])
            self.previous[name]=q.copy()
            bone.location=loc;bone.rotation_mode='QUATERNION';bone.rotation_quaternion=q
            bone.keyframe_insert(data_path="location",frame=frame,group=name)
            bone.keyframe_insert(data_path="rotation_quaternion",frame=frame,group=name)


def place_leg(pose,side,s,offset,lift,pitch):
    upper,lower,foot=["%s.%s"%(key,side) for key in ("Thigh","Shin","Foot")]
    h,k,a=[pose.rest[key].translation for key in (upper,lower,foot)]
    af=a+Vector((0,offset,lift))
    hf=pose.get(upper).translation
    reach=af-hf
    distance=reach.length
    u=reach.normalized()
    l1,l2=(k-h).length,(a-k).length
    if distance>l1+l2+.0001:
        raise ValueError("Unreachable %s ankle: %.4f > %.4f"%(side,distance,l1+l2))
    along=(l1*l1-l2*l2+distance*distance)/(2*distance)
    forward=Vector((s*.10,-1,0))
    bend=(forward-u*forward.dot(u)).normalized()
    kf=hf+along*u+bend*sqrt(max(0,l1*l1-along*along))
    thigh=pose.limb(upper,hf,k-h,kf-hf)
    pose.limb(lower,kf,a-k,af-kf)
    pose.rigid(foot,af,turn((1,0,0),pitch))
    # Hinged coat plates lift with the thigh to open the hip socket in stride.
    pelvis=pose.get('Pelvis')@pose.rest['Pelvis'].inverted()
    inherited=pelvis.to_quaternion()
    tasset='Tasset.'+side
    pose.rigid(tasset,pose.get(tasset).translation,inherited.slerp(thigh,.52))


def leg_cycle(pose,side,s,phase):
    phase%=1
    stride=WALK_SPEED*PERIODS['Walk']/FPS
    if phase<=.5:
        offset=stride*(phase-.25)
        lift=pitch=0
    else:
        t=2*(phase-.5)
        # Contact velocity is continuous at lift-off and heel strike.
        offset=stride*(.25+.5*t-t*t*(3-2*t))
        lift=.305*sin(pi*t)**2
        pitch=11*sin(2*pi*t)*sin(pi*t)
    place_leg(pose,side,s,offset,lift,pitch)


def walk(pose,phase):
    w=2*pi*phase
    rot=turn((0,0,1),2.2*cos(w))@turn((0,1,0),1.4*sin(w))@turn((1,0,0),1.2)
    pose.move("Pelvis",rot,(-.075*sin(w),0,-.18-.12*cos(2*w)))
    pose.move("Chest",turn((0,0,1),-5*cos(w))@turn((0,1,0),-2*sin(w))@turn((1,0,0),1.7))
    pose.move("Head",turn((0,0,1),2.3*cos(w))@turn((1,0,0),-2.4))
    for side,s in SIDES:
        t=phase+(0 if side=="R" else .5)
        leg_cycle(pose,side,s,t)
        swing=cos(2*pi*t)
        pose.move("Shoulder."+side,turn((1,0,0),swing*1.9))
        pose.move("UpperArm."+side,turn((1,0,0),swing*9.0))
        pose.move("Forearm."+side,turn((1,0,0),-3.2+2.9*swing))


def rest(pose,phase):
    w=2*pi*phase
    pose.move("Chest",turn((1,0,0),.55*sin(w)),(0,0,.008*(1-cos(w))))
    pose.move("Head",turn((0,0,1),1.6*sin(w))@turn((1,0,0),-.65*sin(w)))
    for side in ('R','L'):
        pose.move("UpperArm."+side,turn((1,0,0),.55*sin(w)))


def envelope(time,keys):
    """Smooth keyed mechanical travel, including a hold before and after."""
    for (start,low),(end,high) in zip(keys,keys[1:]):
        if time<=end:
            amount=max(0.,(time-start)/(end-start))
            return low+(high-low)*amount*amount*(3-2*amount)
    return keys[-1][1]


def combat_legs(pose,side,brace,kick):
    # Load the outside hip while the soles stay flat through the recoil.
    roll=turn((0,1,0),side*(1.7*brace+.4*kick))
    pose.move("Pelvis",roll,(side*(.066*brace+.015*kick),.025*brace+.038*kick,
                             -.028-.075*brace-.028*kick))
    for label,direction in SIDES:
        place_leg(pose,label,direction,0.,0.,0.)


def aim_forearm(pose,side,axis,line,amount):
    name="Forearm."+side
    inherited=pose.get(name)
    rotation=(inherited@pose.rest[name].inverted()).to_quaternion()
    aligned=axis.rotation_difference(line)
    pose.rigid(name,inherited.translation,rotation.slerp(aligned,amount))


def shoot(pose,phase):
    f=phase*PERIODS["Shoot"]
    brace=envelope(f,[(0,.08),(7,.84),(11,1),(24,.96),(36,.88)])
    aim=envelope(f,[(0,.12),(5,.47),(10,1)])
    kick=envelope(f,[(12,0),(14,1),(16,.68),(20,.13),(23,-.08),(29,0)])
    combat_legs(pose,-1,brace,kick)
    pose.move("Chest",turn((0,0,1),5.0*brace-2.1*kick)@turn((1,0,0),2.2*brace-3.5*kick))
    pose.move("Head",turn((0,0,1),-4.8*brace+1.6*kick)@turn((1,0,0),-2.0*brace+2.3*kick))
    pose.move("Shoulder.R",turn((1,0,0),-5.8*brace+3.0*kick))
    pose.move("UpperArm.R",turn((1,0,0),-8.-31.*brace+11.*kick)@turn((0,1,0),3.4*brace))
    line=turn((1,0,0),-5.0*kick)@FORWARD
    aim_forearm(pose,"R",Vector(pose.arm["muzzle_rest_axis"]),line,aim)
    pose.move("UpperArm.L",turn((1,0,0),-6.5*brace+1.7*kick))
    pose.move("Forearm.L",turn((1,0,0),-3.5*brace))
    travel=envelope(f,[(0,0),(10,-.088),(12,-.09),(15,.105),(19,.066),(28,0)])
    pose.slide("EmitterSlide",travel)


def pod_volley(pose,phase):
    f=phase*PERIODS["PodVolley"]
    brace=envelope(f,[(0,.05),(7,.78),(11,1),(39,1),(55,.85)])
    aim=envelope(f,[(0,0),(5,.32),(10,1)])
    kick=twist=0.
    for release,port in POD_RELEASES:
        impulse=envelope(f-release,[(0,0),(1,1),(2,.57),(4,.04),(5,0)])
        kick+=impulse
        twist+=impulse*(-1 if port%2 else 1)
    combat_legs(pose,1,brace,.77*kick)
    # The pod is carried low but level. Lift the entire support arm onto its
    # shoulder line, counterbalance with the torso, then cycle the six ports.
    pose.move("Chest",turn((0,0,1),-7.1*brace+1.9*kick)@turn((0,1,0),-2.5*brace)@
              turn((1,0,0),2.*brace-2.9*kick))
    pose.move("Head",turn((0,0,1),6.2*brace-1.4*kick)@turn((0,1,0),3.3*brace))
    pose.move("Shoulder.L",turn((1,0,0),-9.2*brace+2.6*kick))
    pose.move("UpperArm.L",turn((1,0,0),-56.*brace+7.8*kick)@turn((0,1,0),-3.*brace))
    line=turn((0,0,1),1.4*twist)@turn((1,0,0),-3.6*kick)@FORWARD
    aim_forearm(pose,"L",Vector(pose.arm["pod_rest_axis"]),line,aim)
    pose.move("UpperArm.R",turn((1,0,0),-12.*brace+2.5*kick))
    pose.move("Forearm.R",turn((0,1,0),3.5*brace)@turn((1,0,0),-5.5*brace))
    for index,(release,port) in enumerate(POD_RELEASES):
        reload_frame=43+index*1.4
        withdrawal=envelope(f,[(release,0),(release+1,.88),(release+2,1),
                               (reload_frame,1),(reload_frame+6,0)])
        pose.slide(f"PodCap{port:02d}",-.177*withdrawal)


def create(pieces):
    """Create and bake the native rig. Objects must retain their construction names."""
    pieces=list(pieces)
    arm=skeleton(pieces)
    scene=bpy.context.scene
    scene.render.fps=FPS;scene.render.fps_base=1.
    data=arm.animation_data_create()
    for name,intervals in PERIODS.items():
        pose=Pose(arm)
        action=bpy.data.actions.new(name)
        data.action=action
        animate={"Rest":rest,"Walk":walk,"Shoot":shoot,"PodVolley":pod_volley}[name]
        loop=name in ("Rest","Walk")
        for i in range(intervals+1):
            pose.world.clear()
            animate(pose,(i%intervals if loop else i)/intervals)
            pose.record(i+1)
        for curve in action.fcurves:
            for key in curve.keyframe_points:key.interpolation='LINEAR'
        action.use_fake_user=True
        action.use_cyclic=loop
        if name=="Shoot":
            action.pose_markers.new("Emitter release").frame=1+RELEASE_FRAME
        elif name=="PodVolley":
            for frame,port in POD_RELEASES:
                action.pose_markers.new(f"Release Pod{port:02d}").frame=1+frame
        data.action=None
        track=data.nla_tracks.new();track.name=name
        strip=track.strips.new(name,1,action);strip.extrapolation='NOTHING'
        track.mute=True
    for bone in arm.pose.bones:
        bone.matrix_basis=Matrix.Identity(4)
    data.nla_tracks['Rest'].mute=False
    scene.frame_start=1;scene.frame_end=PERIODS['Rest'];scene.frame_set(0)
    bpy.context.view_layer.update()
    return arm
