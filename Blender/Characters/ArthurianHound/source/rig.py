"""Quadruped bind rig, alert idle and a ground-matched diagonal trot."""
from math import acos, atan2, cos, hypot, pi, sin

import bpy
from mathutils import Matrix, Quaternion, Vector

SCALE = .78
FPS = 60
RUN_FRAMES = 50
RUN_SPEED = 1.45
STANCE = .44
FRONT = ((-.40,.74),(-.41,.41),(-.40,.105))
HIND = ((.46,.77),(.34,.51),(.67,.285),(.60,.095))
ROOT = (.13,.77)
X = Vector((1,0,0))
Z = Vector((0,0,1))


def skeleton():
    data=bpy.data.armatures.new("Hound skeleton")
    rig=bpy.data.objects.new("Hound rig",data)
    bpy.context.scene.collection.objects.link(rig)
    bpy.context.view_layer.objects.active=rig
    rig.select_set(True)
    bpy.ops.object.mode_set(mode='EDIT')

    def bone(name,head,tail,parent=None):
        b=data.edit_bones.new(name)
        b.head=Vector(head)*SCALE
        b.tail=Vector(tail)*SCALE
        if parent:
            b.parent=data.edit_bones[parent]
    bone("Body",(0,*ROOT),(0,-.32,.85))
    bone("Neck",(0,-.33,.85),(0,-.64,1.16),"Body")
    bone("Head",(0,-.64,1.16),(0,-.92,1.17),"Neck")
    tail=[(0,.57,.78),(-.035,.80,.54),(-.085,1.06,.40),(-.14,1.27,.43)]
    for i,name in enumerate(("Tail","TailMid","TailTip")):
        bone(name,tail[i],tail[i+1],("Body","Tail","TailMid")[i])
    for side,s in (("L",1),("R",-1)):
        bone("Ear."+side,(s*.108,-.695,1.366),(s*.135,-.602,1.647),"Head")
        for prefix,joints,links in (("Front",FRONT,("Upper","Lower")),
                                    ("Hind",HIND,("Upper","Lower","Hock"))):
            parent="Body"
            for i,label in enumerate(links):
                name=prefix+label+"."+side
                bone(name,(s*.23,*joints[i]),(s*.23,*joints[i+1]),parent)
                parent=name
            y,z=joints[-1]
            bone(prefix+"Paw."+side,(s*.23,y,z),(s*.23,y-.12,.04),parent)
    bpy.ops.object.mode_set(mode='OBJECT')
    return rig


def turn(pose,name,frame,pitch=0,yaw=0):
    b=pose[name]
    rest=b.bone.matrix_local.to_quaternion()
    b.rotation_mode='QUATERNION'
    b.rotation_quaternion=rest.inverted() @ Quaternion(Z,yaw) @ Quaternion(X,pitch) @ rest
    b.keyframe_insert(data_path="rotation_quaternion",frame=frame,group=name)


def angle(a,b):
    return atan2(b[0]-a[0],a[1]-b[1])


def leg_pose(pose,prefix,side,phase,frame,drop,pitch):
    is_front=prefix=="Front"
    points=FRONT if is_front else HIND
    t=phase%1.
    stride=RUN_SPEED*RUN_FRAMES/FPS/SCALE
    travel=stride*(t-STANCE/2)
    lift=0.
    paw_pitch=0.
    if t>STANCE:
        swing=(t-STANCE)/(1-STANCE)
        ease=swing*swing*(3-2*swing)
        travel-=stride*ease
        lift=(.190 if is_front else .154)*sin(pi*swing)**1.6
        paw_pitch=.23*sin(2*pi*swing)*sin(pi*swing)
    # The foot sweeps back at exactly the root travel speed through stance.
    end=(points[-1][0]+travel,points[-1][1]+lift)
    ty,tz=points[0][0]-ROOT[0],points[0][1]-ROOT[1]
    top=(ROOT[0]+ty*cos(pitch)-tz*sin(pitch),ROOT[1]+drop+ty*sin(pitch)+tz*cos(pitch))
    if not is_front:
        distal=angle(points[2],points[3])+.30*sin(2*pi*t-.3)
        length=hypot(points[3][0]-points[2][0],points[3][1]-points[2][1])
        end=(end[0]-sin(distal)*length,end[1]+cos(distal)*length)

    dy,dz=end[0]-top[0],end[1]-top[1]
    a=hypot(points[1][0]-points[0][0],points[1][1]-points[0][1])
    b=hypot(points[2][0]-points[1][0],points[2][1]-points[1][1])
    d=min(a+b-.0001,max(abs(a-b)+.0001,hypot(dy,dz)))
    inner=acos(max(-1.,min(1.,(a*a+d*d-b*b)/(2*a*d))))
    upper=atan2(dy,-dz)+(inner if is_front else -inner)
    knee=(top[0]+a*sin(upper),top[1]-a*cos(upper))
    lower=angle(knee,end)
    angles=[upper-angle(points[0],points[1]),lower-angle(points[1],points[2])]
    links=["Upper","Lower"]
    if not is_front:
        angles.append(distal-angle(points[2],points[3]))
        links.append("Hock")
    angles.append(paw_pitch)
    links.append("Paw")
    parent=pitch
    for label,rotation in zip(links,angles):
        turn(pose,prefix+label+"."+side,frame,rotation-parent)
        parent=rotation


def animate(rig,clip,frames):
    rig.animation_data.action=bpy.data.actions.new(clip)
    for b in rig.pose.bones:
        b.matrix_basis=Matrix.Identity(4)
    pose=rig.pose.bones
    for i in range(frames+1):
        phase=i/frames
        a=2*pi*phase
        frame=i+1
        if clip=="Run":
            drop=-.133+.008*cos(2*a+.8)
            pitch=.015*sin(2*a-.3)
            for side,offset in (("L",0.),("R",.5)):
                leg_pose(pose,"Front",side,phase+offset,frame,drop,pitch)
                leg_pose(pose,"Hind",side,phase+offset+.5,frame,drop,pitch)
            head=.041*sin(2*a-.36)
            twist=.025*sin(a+.3)
        else:
            # Feet stay planted. A slow neck breath and an independent ear
            # flick read in portrait without the helmet rocking on the muzzle.
            drop=pitch=0.
            head=.015*sin(a)
            twist=.035*sin(a)
        pose['Body'].location=pose['Body'].bone.matrix_local.to_3x3().inverted() @ Vector((0,0,drop*SCALE))
        pose['Body'].keyframe_insert(data_path="location",frame=frame,group='Body')
        turn(pose,'Body',frame,pitch)
        turn(pose,'Neck',frame,head-pitch,twist)
        turn(pose,'Head',frame,-head*.72,-twist*.34)
        for side,sign in (("L",1),("R",-1)):
            flick=(max(0.,sin(a*2+sign*.58))**12)*(.08 if clip=="Rest" else .025)
            turn(pose,'Ear.'+side,frame,.035*sin(a+sign*.3) if clip=="Run" else 0,sign*flick)
        for j,name in enumerate(("Tail","TailMid","TailTip")):
            turn(pose,name,frame,.029*sin(a-.40*j),(.071 if clip=="Run" else .055)*sin(a-.5*j))
    action=rig.animation_data.action
    bag=action.layers[0].strips[0].channelbag(rig.animation_data.action_slot)
    for curve in bag.fcurves:
        for key in curve.keyframe_points:
            key.interpolation='LINEAR'
    action.use_cyclic=True
    rig.animation_data.action=None
    track=rig.animation_data.nla_tracks.new()
    track.name=clip
    track.strips.new(clip,1,action)
    track.mute=True
    return action


def create(pieces):
    rig=skeleton()
    for piece in pieces:
        joint=piece["joint"]
        if joint not in rig.data.bones:
            raise ValueError("Unknown joint "+joint+" on "+piece.name)
        piece.parent=rig
        group=piece.vertex_groups.new(name=joint)
        group.add(list(range(len(piece.data.vertices))),1,'REPLACE')
        mod=piece.modifiers.new("Hound skeleton",'ARMATURE')
        mod.object=rig
    rig.animation_data_create()
    rest=animate(rig,"Rest",160)
    animate(rig,"Run",RUN_FRAMES)
    for b in rig.pose.bones:
        b.matrix_basis=Matrix.Identity(4)
    rig.animation_data.use_nla=False
    rig.animation_data.action=rest
    rig["trot_speed_mps"]=RUN_SPEED
    bpy.context.scene.frame_start=1
    bpy.context.scene.frame_end=161
    bpy.context.scene.frame_set(1)
    return rig
