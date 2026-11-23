"""Animate the Round Table Marine's three-second, planted Shoot loop.

Run on a rigged working file with Blender --python combat_cycle.py [-- output.blend].
Frames 1 and 73 coincide at 24 fps. Shot onsets are explicit action markers.
"""

from math import cos, pi, radians, sin, sqrt
from pathlib import Path
import sys

import bpy
from mathutils import Matrix, Quaternion, Vector


FPS = 24
PERIOD = 72
SHOT_FRAMES = (6, 10, 14, 30, 34, 38, 54, 58, 62)
UP = Vector((0, 0, 1))
FORWARD = Vector((0, -1, 0))


def kick(frame):
    # Hard impact, short recovery and a tiny settling motion after each flash.
    envelope = {0: .23, 1: 1, 2: .48, 3: .13, 4: -.065, 5: -.029}
    return sum(envelope.get(frame-shot, 0)*(.86 + .07*(i%3)) for i,shot in enumerate(SHOT_FRAMES))


def axes(along, normal):
    along = Vector(along).normalized()
    right = along.cross(normal).normalized()
    return Matrix((right, along, right.cross(along))).transposed()


def translate(point):
    return Matrix.Translation(point)


def swivel(axis, degrees):
    return Quaternion(axis,radians(degrees)).to_matrix().to_4x4()


class SkeletonPose:
    """Compose in armature space, then key the actual rolled local bone axes."""

    def __init__(self, rig):
        self.rig = rig
        self.rest = {b.name:b.matrix_local.copy() for b in rig.data.bones}
        self.local = {b.name:(self.rest[b.parent.name].inverted()@self.rest[b.name]
                              if b.parent else self.rest[b.name]) for b in rig.data.bones}
        self.prior_rotation = {}
        self.world = {}

    def inherited(self, name):
        parent = self.rig.data.bones[name].parent
        return self.matrix(parent.name)@self.local[name] if parent else self.local[name]

    def matrix(self, name):
        if name not in self.world:
            self.world[name] = self.inherited(name)
        return self.world[name]

    def key(self, name, desired, frame, position=False):
        basis = self.inherited(name).inverted() @ desired
        location, rotation, _ = basis.decompose()
        pb = self.rig.pose.bones[name]
        if name in self.prior_rotation:
            rotation.make_compatible(self.prior_rotation[name])
        pb.rotation_mode = "QUATERNION"
        pb.rotation_quaternion = rotation
        self.prior_rotation[name] = rotation.copy()
        pb.keyframe_insert(data_path="rotation_quaternion",frame=frame,group=name)
        if position:
            pb.location = location
            pb.keyframe_insert(data_path="location",frame=frame,group=name)
        elif location.length > .0008:
            raise ValueError(f"Detached {name} at frame {frame}, offset {location.length:.4f} m")
        self.world[name] = desired

    def swing(self, name, rot, frame, shift=None):
        start = self.inherited(name)
        h = start.translation
        shift = Vector((0,0,0)) if shift is None else Vector(shift)
        self.key(name,translate(h+shift)@rot@translate(-h)@start,frame,
                 position=shift.length_squared>0)

    def limb(self, names, tip, pole, frame):
        upper, lower, end = names
        upper_rest, lower_rest, end_rest = [self.rest[n].translation for n in names]
        a,b = (lower_rest-upper_rest).length,(end_rest-lower_rest).length
        base = self.inherited(upper).translation
        delta = tip-base
        d = delta.length
        if not abs(a-b) < d < a+b:
            raise ValueError(f"{end} reach on frame {frame}: {d:.4f} vs {a+b:.4f} m")
        line = delta/d
        tangent = (pole-line*line.dot(pole)).normalized()
        run = (a*a-b*b+d*d)/(2*d)
        joint = base + line*run + tangent*sqrt(max(0,a*a-run*run))
        for name,source,dest,head in [(upper,lower_rest-upper_rest,joint-base,base),
                                      (lower,end_rest-lower_rest,tip-joint,joint)]:
            q = source.rotation_difference(dest)
            orientation = q.to_matrix()@self.rest[name].to_3x3()
            self.key(name,translate(head)@orientation.to_4x4(),frame)

    def armor_follow(self, armor, segment, fraction, frame):
        relative=self.inherited(segment).inverted()@self.matrix(segment)
        rotate=Quaternion().slerp(relative.to_quaternion(),fraction)
        self.key(armor,self.inherited(armor)@rotate.to_matrix().to_4x4(),frame)


def center(rig, name):
    obj = bpy.data.objects["A_"+name]
    matrix = rig.matrix_world.inverted()@obj.matrix_world
    return sum((matrix@Vector(corner) for corner in obj.bound_box), Vector())/8


class FiringPose:
    def __init__(self, rig):
        self.sk = SkeletonPose(rig)
        asset = bpy.data.collections["Round_Table_Marine_ASSET"]
        self.fitted_rifle = asset.objects.get("A_Rifle_trigger_socket") is not None
        if self.fitted_rifle:
            from rig_marines import rifle_landmarks
            self.grip, self.front_grip, _, forward, up = rifle_landmarks(asset, rig)
            self.weapon_axes = axes(forward, up)
        else:
            self.grip = center(rig,"Carbine_hand_grip")
            self.front_grip = center(rig,"Carbine_fore_end")
            bore = center(rig,"Carbine_muzzle_bore")
            collar = center(rig,"Carbine_muzzle_collar")
            self.weapon_axes = axes(bore-collar,center(rig,"Carbine_receiver")-self.grip)
        self.palms = {side:center(rig,"Glove_"+side+"_Palm") for side in ("R","L")}
        self.hand_axes = {}
        for side,palm in self.palms.items():
            wrist = self.sk.rest["hand."+side].translation
            dorsal = center(rig,"Glove_"+side+"_DorsalPlate")-palm
            self.hand_axes[side] = axes(palm-wrist,dorsal)

    def animate(self, frame):
        s = self.sk
        s.world.clear()
        phase = (frame-1) % PERIOD
        angle = 2*pi*phase/PERIOD
        recoil = kick(phase+1)
        body_kick = kick(phase)
        # Stagger the boots and flex the knees once. Everything below the
        # waist holds this same brace through every round and the loop seam.
        height = -.075
        s.swing("pelvis",swivel(UP,-7),frame,(0,.006,height))
        s.swing("spine.01",swivel(UP,-5.5)@swivel((1,0,0),4.5-1.3*body_kick),frame)
        shoulder_turn=-12.5 if self.fitted_rifle else 0.0
        s.swing("spine.02",swivel(UP,-5.5+shoulder_turn*.45)@swivel((1,0,0),4.4-1.7*body_kick),frame)
        s.swing("spine.03",swivel(UP,-4.2+shoulder_turn*.55)@swivel((1,0,0),2.5-body_kick),frame)
        s.swing("neck",swivel(UP,12.2-.55*shoulder_turn)@swivel((1,0,0),-4.8),frame)
        s.swing("head",swivel(UP,9.0-.45*shoulder_turn)@swivel((1,0,0),2.4+.6*body_kick)@
                swivel((0,1,0),-4.0),frame)
        for i,amount in [(1,1),(2,1.4),(3,1.8)]:
            bone=f"cape.{i:02d}"
            s.swing(bone,swivel((1,0,0),-.5*amount*cos(angle-.35*i)+.6*amount*body_kick),frame)
        for i in (1,2):
            s.swing(f"tabard.{i:02d}",swivel((1,0,0),-3.0),frame)

        for side in ("L","R"):
            sign = 1 if side=="L" else -1
            name = "foot."+side
            foot = s.rest[name].translation + Vector((
                .024*sign, -.035 if sign>0 else .054, 0))
            s.limb(("thigh."+side,"shin."+side,name),foot,
                   Vector((.095*sign,-.95,.02)),frame)
            s.armor_follow("poleyn."+side,"shin."+side,.55,frame)
            rotation = swivel(UP,sign*3.0)
            s.key(name,translate(foot)@rotation@s.rest[name].to_3x3().to_4x4(),frame)
            s.key("toe."+side,s.inherited("toe."+side),frame)

        # Aim from the shoulder. Both wrists follow the rifle's recoil and
        # its small rise and fall with the marine's breathing.
        grip_x,grip_y=(-.188,-.411) if self.fitted_rifle else (-.111,-.286)
        anchor = Vector((grip_x,grip_y,1.466+height+.002*sin(angle)))
        fixed_target = Vector((.01,-4.4,1.52))
        direction = (fixed_target-anchor).normalized()
        direction = (swivel((1,0,0),-3.8*recoil).to_3x3()@direction).normalized()
        gun_rotation = (axes(direction,Vector((-.215,0,1)))@
                        self.weapon_axes.transposed())
        actual_grip = anchor-.0305*recoil*direction
        prop_delta = translate(actual_grip)@gun_rotation.to_4x4()@translate(-self.grip)

        for side in ("R","L"):
            name="hand."+side
            sign=1 if side=="L" else -1
            s.swing("clavicle."+side,swivel(UP,-3.0 if sign>0 else 1.4)@
                    swivel((0,1,0),sign*(-2.7+.4*body_kick)),frame)
            if side=="R":
                palm=actual_grip+Vector((-.026,.014,-.009))
                direction,dorsal=(.46,-.64,.62),(-.92,-.18,.06)
            else:
                palm=prop_delta@self.front_grip+Vector((.010,.008,-.045))
                direction,dorsal=(-.67,-.47,.48),(.48,.19,-.83)
            hand_rotation=axes(direction,Vector(dorsal))@self.hand_axes[side].transposed()
            hand_delta=translate(palm)@hand_rotation.to_4x4()@translate(-self.palms[side])
            hand=hand_delta@s.rest[name]
            s.limb(("upper_arm."+side,"forearm."+side,name),hand.translation,
                   Vector((.68*sign,.09,-.92)),frame)
            s.armor_follow("pauldron."+side,"upper_arm."+side,.34,frame)
            s.key(name,hand,frame)
        s.key("carbine",prop_delta@s.rest["carbine"],frame,position=True)


def _animate_shoot(rig, action):
    scene = bpy.context.scene
    for bone in rig.pose.bones:
        bone.matrix_basis=Matrix.Identity(4)
    bpy.context.view_layer.update()
    rig.animation_data.action=action
    action.use_fake_user=True
    action.use_frame_range=True
    action.frame_start,action.frame_end=1,PERIOD+1
    for i,frame in enumerate(SHOT_FRAMES,1):
        action.pose_markers.new(f"Shot {i:02d}").frame=frame
    rig["shoot_event_frames"]=list(SHOT_FRAMES)
    rig["shoot_fps"]=FPS
    # Original object bounds can reflect the active armature pose, even when
    # read from the source object rather than its evaluated copy. Read every
    # landmark at bind pose so a refit works on any paused animation frame.
    rig.data.pose_position="REST"
    bpy.context.view_layer.update()
    try:
        pose=FiringPose(rig)
    finally:
        rig.data.pose_position="POSE"
        bpy.context.view_layer.update()
    for frame in range(1,PERIOD+2):
        pose.animate(frame)
    # The quaternion keys are already sampled at render frames, and linear
    # segments retain the intended sharp recoil without overshoot.
    for slot in action.slots:
        for layer in action.layers:
            for strip in layer.strips:
                bag=strip.channelbag(slot)
                if bag:
                    for curve in bag.fcurves:
                        for key in curve.keyframe_points:
                            key.interpolation="LINEAR"
    for frame in (1,*SHOT_FRAMES,PERIOD+1):
        scene.frame_set(frame)
        muzzle=rig.pose.bones["muzzle"]
        posed_axis=(muzzle.tail-muzzle.head).normalized()
        if posed_axis.dot(FORWARD)<.98:
            raise ValueError(f"Muzzle faces away from target at frame {frame}: {posed_axis}")
    if pose.fitted_rifle:
        from rig_marines import rifle_pose_signature
        action["rifle_pose"] = rifle_pose_signature(bpy.data.collections["Round_Table_Marine_ASSET"],rig)


def build_shoot(rig):
    if rig.get("variant") != "A":
        raise ValueError("Shoot is authored for the Round Table Marine")
    from rig_marines import stash_action
    scene=bpy.context.scene
    scene.render.fps=FPS
    data=rig.animation_data_create()
    old=bpy.data.actions.get("Shoot")
    tracked=bool(old and any(s.action==old for t in data.nla_tracks for s in t.strips))
    prior_action=data.action
    prior_pose={b.name:b.matrix_basis.copy() for b in rig.pose.bones}
    prior_nla=data.use_nla
    prior_pose_position=rig.data.pose_position
    frame,subframe=scene.frame_current,scene.frame_subframe
    data.use_nla=False
    action=bpy.data.actions.new("Shoot")
    try:
        _animate_shoot(rig,action)
    except Exception:
        data.action=prior_action
        bpy.data.actions.remove(action)
        data.use_nla=prior_nla
        rig.data.pose_position=prior_pose_position
        for bone in rig.pose.bones:
            bone.matrix_basis=prior_pose[bone.name]
        scene.frame_set(frame,subframe=subframe)
        raise

    if old:
        if prior_action==old:
            prior_action=action
        old.user_remap(action)
        bpy.data.actions.remove(old)
        action.name="Shoot"
    data.use_nla=prior_nla
    rig.data.pose_position=prior_pose_position
    if tracked:
        # Remap keeps the existing strip's bounds, blending, scale and track
        # state. Fitting prop art should not switch the artist's opening view.
        data.action=prior_action
        for bone in rig.pose.bones:
            bone.matrix_basis=prior_pose[bone.name]
        scene.frame_set(frame,subframe=subframe)
    else:
        stash_action(rig,action)
    return action


if __name__=="__main__":
    sys.path.insert(0,str(Path(__file__).resolve().parent))
    armature,=[o for o in bpy.context.scene.objects if o.type=="ARMATURE"]
    build_shoot(armature)
    args=sys.argv[sys.argv.index("--")+1:] if "--" in sys.argv else []
    output=Path(args[0] if args else bpy.data.filepath).resolve()
    bpy.context.preferences.filepaths.save_version=0
    bpy.ops.wm.save_as_mainfile(filepath=str(output),compress=True)
