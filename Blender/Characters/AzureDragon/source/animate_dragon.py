"""Bake Rest, Walk, and long-cone FireBreath animations at 24 fps onto Azure_Dragon_Rig.

Can be run standalone on an open/saved Azure_Dragon.blend:
  "C:/Program Files/Blender Foundation/Blender 4.5/blender.exe" -b --factory-startup "Blender/Characters/AzureDragon/source/Azure_Dragon.blend" --python-exit-code 1 -P "Blender/Characters/AzureDragon/source/animate_dragon.py"
"""

from math import cos, exp, pi, radians, sin, sqrt
from pathlib import Path
import sys

import bpy
from mathutils import Matrix, Quaternion, Vector


HERE = Path(__file__).resolve().parent
if str(HERE) not in sys.path:
    sys.path.insert(0, str(HERE))

from rig_dragon import clamp, iter_action_fcurves, smoothstep, stash_action


FPS = 24
REST_PERIOD = 48
WALK_PERIOD = 14
WALK_SAMPLES = 4
BREATH_PERIOD = 72

WALK_DUTY = 5.5 / WALK_PERIOD
WALK_SPEED_MPS = 5.5
WALK_STRIDE = WALK_PERIOD / FPS * WALK_SPEED_MPS


def rx(deg):
    return Matrix.Rotation(radians(deg), 4, "X")


def ry(deg):
    return Matrix.Rotation(radians(deg), 4, "Y")


def rz(deg):
    return Matrix.Rotation(radians(deg), 4, "Z")


def tr(x=0.0, y=0.0, z=0.0):
    return Matrix.Translation(Vector((x, y, z)))


def lerp(a, b, t):
    return a + (b - a) * t


def solve_two_bone_ik(start, end, pole_dir, len_a, len_b):
    """Analytic two-bone IK solver with soft reach clamping to prevent hyperextension locking."""
    delta = end - start
    d = delta.length
    min_reach = abs(len_a - len_b) + 0.015
    max_reach = (len_a + len_b) * 0.992
    if d < min_reach:
        d = min_reach
        end = start + (delta.normalized() if delta.length > 1e-6 else Vector((0, 0, -1))) * d
    elif d > max_reach:
        d = max_reach
        end = start + delta.normalized() * d

    axis = (end - start) / d
    along = (len_a * len_a - len_b * len_b + d * d) / (2.0 * d)
    perp_h = sqrt(max(0.0, len_a * len_a - along * along))
    bend = pole_dir - axis * axis.dot(pole_dir)
    if bend.length < 1e-5:
        bend = axis.cross(Vector((1, 0, 0)))
    bend.normalize()
    joint = start + axis * along + bend * perp_h
    return joint, end


class DragonPose:
    """Compose dragon bone transforms in armature space and key clean local quaternions/locations/scales."""

    def __init__(self, rig):
        self.rig = rig
        self.rest = {b.name: b.matrix_local.copy() for b in rig.data.bones}
        self.world = {}
        self.scales = {}
        self.loc_bones = {"pelvis"} | {f"breath_plume_{k}" for k in range(6)}
        self.prev_q = {}

    def clear(self):
        self.world.clear()
        self.scales.clear()

    def set(self, name, mat, scale=None):
        self.world[name] = mat
        if scale is not None:
            self.scales[name] = Vector(scale)

    def delta(self, name):
        return self.world[name] @ self.rest[name].inverted()

    def parent_pose(self, name):
        p = self.rig.data.bones[name].parent
        if p is None or p.name not in self.world:
            return self.rest[name]
        return self.delta(p.name) @ self.rest[name]

    def swing(self, name, rot_mat, shift=None, scale=None):
        """Rotate bone around its posed head by rot_mat (expressed in rest orientation) plus optional shift."""
        base = self.parent_pose(name)
        parent_delta = base @ self.rest[name].inverted()
        h = self.rest[name].translation
        sh = Vector(shift) if shift is not None else Vector((0, 0, 0))
        mat = parent_delta @ Matrix.Translation(h + sh) @ rot_mat @ Matrix.Translation(-h) @ self.rest[name]
        self.set(name, mat, scale=scale)

    def aim(self, name, start, end, parent_delta):
        bone = self.rig.data.bones[name]
        resting_dir = parent_delta.to_3x3() @ (bone.tail_local - bone.head_local)
        q = resting_dir.rotation_difference(end - start)
        rot3 = q.to_matrix() @ parent_delta.to_3x3() @ self.rest[name].to_3x3()
        mat = rot3.to_4x4()
        mat.translation = start
        self.set(name, mat)

    def follow(self, name, driven_name, fraction):
        base = self.parent_pose(driven_name)
        q = (base.inverted() @ self.world[driven_name]).to_quaternion()
        blend_q = Quaternion().slerp(q, fraction)
        self.set(name, self.parent_pose(name) @ blend_q.to_matrix().to_4x4())

    def solve_foreleg(self, side, wrist_target, foot_pitch=0.0, foot_yaw=0.0, elbow_splay=0.25):
        tag = "L" if side > 0 else "R"
        up_b, lo_b, ft_b, pld_b = f"fore_upper.{tag}", f"fore_lower.{tag}", f"fore_foot.{tag}", f"pauldron.{tag}"
        len_a = self.rig.data.bones[up_b].length
        len_b = self.rig.data.bones[lo_b].length

        chest_delta = self.delta("chest")
        shoulder = (chest_delta @ self.rest[up_b]).translation
        pole = Vector((side * elbow_splay, 1.0, 0.15)).normalized()
        elbow, wrist = solve_two_bone_ik(shoulder, wrist_target, pole, len_a, len_b)

        self.aim(up_b, shoulder, elbow, chest_delta)
        self.aim(lo_b, elbow, wrist, self.delta(up_b))

        foot_rot = rz(foot_yaw) @ rx(foot_pitch)
        foot_mat = Matrix.Translation(wrist) @ (foot_rot.to_3x3() @ self.rest[ft_b].to_3x3()).to_4x4()
        foot_mat.translation = wrist
        self.set(ft_b, foot_mat)
        self.follow(pld_b, up_b, 0.26)

    def solve_hindleg(self, side, ankle_target, ankle_pitch=0.0, foot_pitch=0.0, foot_yaw=0.0, knee_splay=0.24):
        tag = "L" if side > 0 else "R"
        th_b, sh_b, ak_b, ft_b, tas_b = (
            f"hind_thigh.{tag}", f"hind_shin.{tag}", f"hind_ankle.{tag}", f"hind_foot.{tag}", f"flank_tasset.{tag}"
        )
        len_a = self.rig.data.bones[th_b].length
        len_b = self.rig.data.bones[sh_b].length

        pelvis_delta = self.delta("pelvis")
        hip = (pelvis_delta @ self.rest[th_b]).translation

        rest_hock_vec = self.rest[ak_b].translation - self.rest[ft_b].translation
        hock_target = ankle_target + (rz(foot_yaw) @ rx(ankle_pitch)).to_3x3() @ rest_hock_vec
        pole = Vector((side * knee_splay, -1.0, 0.20)).normalized()
        knee, hock = solve_two_bone_ik(hip, hock_target, pole, len_a, len_b)

        self.aim(th_b, hip, knee, pelvis_delta)
        self.aim(sh_b, knee, hock, self.delta(th_b))
        self.aim(ak_b, hock, ankle_target, self.delta(sh_b))

        foot_rot = rz(foot_yaw) @ rx(foot_pitch)
        foot_mat = Matrix.Translation(ankle_target) @ (foot_rot.to_3x3() @ self.rest[ft_b].to_3x3()).to_4x4()
        foot_mat.translation = ankle_target
        self.set(ft_b, foot_mat)
        self.follow(tas_b, th_b, 0.28)

    def record(self, frame):
        for name, desired in self.world.items():
            pb = self.rig.pose.bones[name]
            local = self.parent_pose(name).inverted() @ desired
            loc, q, _ = local.decompose()
            if name in self.prev_q:
                q.make_compatible(self.prev_q[name])
            self.prev_q[name] = q.copy()
            pb.rotation_mode = "QUATERNION"
            pb.rotation_quaternion = q
            pb.keyframe_insert("rotation_quaternion", frame=frame, group=name)
            if name in self.loc_bones:
                pb.location = loc
                pb.keyframe_insert("location", frame=frame, group=name)
            if name in self.scales:
                pb.scale = self.scales[name]
                pb.keyframe_insert("scale", frame=frame, group=name)


def _set_linear(action):
    for fc in iter_action_fcurves(action):
        for kp in fc.keyframe_points:
            kp.interpolation = "LINEAR"


def _key_breath_off(pose, frame):
    pose.swing("breath_muzzle", Matrix.Identity(4))
    pose.swing("breath_origin", Matrix.Identity(4), scale=(0.001, 0.001, 0.001))
    for k in range(4):
        pose.swing(f"breath_seg_{k}", Matrix.Identity(4), scale=(1.0, 1.0, 1.0))
    for k in range(6):
        pose.swing(f"breath_plume_{k}", Matrix.Identity(4), scale=(0.001, 0.001, 0.001))


def _pin_rest_feet(pose, foot_y_shift=0.0):
    for side in (-1.0, 1.0):
        tag = "L" if side > 0 else "R"
        wr = pose.rest[f"fore_foot.{tag}"].translation + Vector((0, foot_y_shift, 0))
        ak = pose.rest[f"hind_foot.{tag}"].translation + Vector((0, foot_y_shift, 0))
        pose.solve_foreleg(side, wr)
        pose.solve_hindleg(side, ak)


def _folded_wings(pose, lift, open_deg, settle):
    """Quiet shoulder support and delayed finger weight on the grounded dragon."""
    for side in (-1.0, 1.0):
        tag = "L" if side > 0 else "R"
        pose.swing(f"wing_arm.{tag}", ry(-side * lift))
        pose.swing(f"wing_forearm.{tag}", rz(-side * open_deg * 0.45) @ rx(0.28 * lift))
        for finger in range(1, 5):
            fan = 1.0 - 0.14 * (finger - 1)
            pose.swing(f"wing_finger_{finger}.{tag}", rz(-side * open_deg * fan) @ rx(settle * fan))


# ---------------------------------------------------------------------------
# CLIP 1: REST (2.0 s breathing idle loop, frames 1..49)
# ---------------------------------------------------------------------------

def build_rest(rig):
    action = bpy.data.actions.new("Rest")
    rig.animation_data_create().action = action
    pose = DragonPose(rig)

    for frame in range(1, REST_PERIOD + 2):
        t = ((frame - 1) % REST_PERIOD) / REST_PERIOD
        phase = 2.0 * pi * t
        breath = sin(phase)
        pose.clear()
        pose.set("root", pose.rest["root"])

        pose.swing("pelvis", rx(0.6 * breath), shift=(0.0, 0.0, -0.015 + 0.014 * breath))
        pose.swing("spine.01", rx(-0.8 * breath))
        pose.swing("chest", rx(-1.2 * breath))
        pose.swing("neck.01", rx(1.4 * breath))
        pose.swing("neck.02", rx(0.8 * breath))
        pose.swing("head", rx(-2.0 * breath) @ rz(1.6 * sin(phase * 0.5)))
        pose.swing("jaw", rx(0.8 * max(0.0, breath)))
        pose.swing("Rider_Mount", Matrix.Identity(4))

        # Each joint tracks a delayed angle. The broad base moves least.
        previous_yaw = previous_pitch = 0.0
        for idx in range(1, 6):
            lag = phase - 0.39 * (idx - 1)
            yaw = (0.9 + 0.75 * idx) * sin(lag)
            pitch = (0.45 + 0.26 * idx) * cos(lag)
            pose.swing(f"tail.0{idx}", rz(yaw - previous_yaw) @ rx(pitch - previous_pitch))
            previous_yaw, previous_pitch = yaw, pitch

        _folded_wings(pose, lift=0.7 * breath, open_deg=0.6 * sin(phase - 0.45),
                      settle=0.7 * sin(phase - 0.75))
        _pin_rest_feet(pose)
        _key_breath_off(pose, frame)
        pose.record(frame)

    _set_linear(action)
    stash_action(rig, action, mute=True)
    return action


# ---------------------------------------------------------------------------
# CLIP 2: WALK (mounted ground canter at the actor's actual 5.5 m/s)
# ---------------------------------------------------------------------------

def _swing_curve(keys, u):
    """A cubic with an explicit velocity at each key, in units per phase."""
    for (a, p, va), (b, q, vb) in zip(keys, keys[1:]):
        if u <= b:
            s = (u - a) / (b - a)
            blend = s * s * (3 - 2 * s)
            return (p * (1 - blend) + q * blend
                    + (b - a) * (va*s*(1-s)**2 - vb*s*s*(1-s)))
    return keys[-1][1]


def _sole_points(rig, front, tag):
    """Find all load-bearing pad and talon vertices in the rest foot's frame."""
    part = "Forefoot" if front else "Hindfoot"
    bone = rig.data.bones[("fore_foot." if front else "hind_foot.") + tag]
    inv = rig.matrix_world.inverted()
    points = []
    for obj in bpy.data.objects:
        if obj.type == "MESH" and obj.name.startswith(f"Dragon_{part}_{tag}_"):
            transform = inv @ obj.matrix_world
            points.extend(transform @ v.co - bone.head_local for v in obj.data.vertices)
    return points


def build_walk(rig):
    action = bpy.data.actions.new("Walk")
    rig.animation_data_create().action = action
    pose = DragonPose(rig)
    # Transverse footfalls. The outside hind initiates, the next hind drives,
    # then the two forelimbs receive the load. Adjacent stances overlap.
    landings = {(False, "R"): 0.0, (False, "L"): 2.0, (True, "R"): 6.5, (True, "L"): 8.5}
    soles = {key: _sole_points(rig, *key) for key in landings}
    half = WALK_STRIDE * WALK_DUTY / 2
    swing_v = WALK_STRIDE * (1 - WALK_DUTY)
    swing = [(0, half, swing_v), (.12, half+.075, 0), (.55, -.05, -2.6),
             (.86, -half-.065, 0), (1, -half, swing_v)]
    for step in range(WALK_PERIOD * WALK_SAMPLES + 1):
        frame = 1 + step / WALK_SAMPLES
        t = (step % (WALK_PERIOD * WALK_SAMPLES)) / (WALK_PERIOD * WALK_SAMPLES)
        phase = 2*pi*t
        drive = cos(phase - 2.55)
        # Load at the hind/fore contacts and rise through push-off. The rider
        # follows the saddle's bone exactly; the neck and tail absorb the roll.
        body_z = -.245 + .037*cos(2*phase-4.9)
        sway_x = .026 * sin(phase - .45)
        pose.clear()
        pose.set("root", pose.rest["root"])
        pose.swing("pelvis", rz(2.8*sin(phase)) @ ry(1.9*cos(phase)) @ rx(6.0*drive),
                   shift=(sway_x, .012*sin(2*phase), body_z))
        pose.swing("spine.01", rz(-3.0*sin(phase-.12)) @ ry(-1.8*cos(phase)) @ rx(-5.3*drive))
        pose.swing("chest", rz(-2.8*sin(phase-.23)) @ rx(-5.9*drive))
        pose.swing("Rider_Mount", Matrix.Identity(4))
        pose.swing("neck.01", rx(7.0+3.4*cos(phase-2.72)) @ rz(2.5*sin(phase-.1)))
        pose.swing("neck.02", rx(3.5+2.1*cos(phase-2.87)))
        pose.swing("head", rx(-6.0-2*cos(phase-2.87)) @ rz(-1.0*sin(phase)))
        pose.swing("jaw", rx(1.4+.7*sin(phase-.3)))
        # The tail takes the counter-roll from the pelvis, then follows with a
        # traveling sway. A small root lift carries it clear of the lowered gait.
        previous_yaw = 2.8 * sin(phase)
        previous_pitch = 6.0 * drive
        for idx in range(1, 6):
            lag = phase - 0.44 * (idx - 1)
            yaw = -(0.9 + 1.65 * idx) * sin(lag - 0.19)
            pitch = 4.9 + (1.4 - 0.14 * idx) * cos(lag - 2.55)
            pose.swing(f"tail.0{idx}", rz(yaw - previous_yaw) @ rx(pitch - previous_pitch))
            previous_yaw, previous_pitch = yaw, pitch
        _folded_wings(pose, lift=1.3 + 1.1 * cos(2 * phase - 0.5),
                      open_deg=1.0 + 0.55 * drive, settle=1.4 * cos(2 * phase - 1.0))
        for (front, tag), landing in landings.items():
            side = 1 if tag == "L" else -1
            u = (t - landing/WALK_PERIOD) % 1
            contact = u <= WALK_DUTY
            if contact:
                load = u/WALK_DUTY
                y = WALK_STRIDE*(u - WALK_DUTY/2)
                lift = 0
                pitch = (15 if front else 20)*smoothstep(.47, 1, load)
                widen = 0
            else:
                s = (u-WALK_DUTY)/(1-WALK_DUTY)
                y = _swing_curve(swing, s)
                lift = _swing_curve([(0, 0, 0), (.19, .115, .9), (.46, .32 if front else .38, 0),
                                     (.77, .165, -.78), (1, 0, 0)], s)
                pitch = _swing_curve([(0, 15 if front else 20, 0), (.29, 33 if front else 37, 0),
                                      (.67, -3, -11), (1, 0, 0)], s)
                widen = (-.07 if front else .19) * sin(pi*s)**2
            name = ("fore_foot." if front else "hind_foot.") + tag
            origin = pose.rest[name].translation
            sole = soles[(front, tag)]
            c, sn = cos(radians(pitch)), sin(radians(pitch))
            # Roll over a toe at take-off. The ankle rises and rotates around
            # the foremost talon rather than pushing the long claws into turf.
            toe = min(sole, key=lambda pt: pt.y)
            roll_offset = toe.y - (c*toe.y - sn*toe.z)
            z = lift - min(sn*pt.y + c*pt.z for pt in sole)
            center_y = -.66 if front else .70
            # The bunched hind talons pass outside of the folded foreleg.
            # The broad mounted stance also clears the dragon's long claws.
            lane = .33 if front else .69
            target = Vector((side*(lane+widen), center_y + y + roll_offset, z))
            if front:
                pose.solve_foreleg(side, target, foot_pitch=pitch, elbow_splay=-.28)
            else:
                pose.solve_hindleg(side, target, ankle_pitch=16*y/half-3, foot_pitch=pitch, knee_splay=1.2)
        _key_breath_off(pose, frame)
        pose.record(frame)
    _set_linear(action)
    action["forward_speed_mps"] = WALK_SPEED_MPS
    stash_action(rig, action, mute=False)
    return action


# ---------------------------------------------------------------------------
# CLIP 3: FIREBREATH (3.0 s long-cone sweeping AOE attack, frames 1..73)
# ---------------------------------------------------------------------------

def _animate_breath_light(light_data):
    """Bake fiery flickering Point Light energy onto Breath_Light's data NLA track."""
    if light_data.animation_data:
        light_data.animation_data_clear()
    action = bpy.data.actions.new("FireBreath_Light")
    ad = light_data.animation_data_create()
    ad.action = action
    for frame in range(1, BREATH_PERIOD + 2):
        f = (frame - 1) % BREATH_PERIOD + 1
        if f < 14 or f > 63:
            energy = 0.0
        elif f < 19:
            energy = 240.0 * smoothstep(14.0, 19.0, f)
        elif f <= 54:
            ramp_up = smoothstep(19.0, 24.0, f)
            flicker = 0.88 + 0.14 * sin(f * 1.85) + 0.08 * cos(f * 3.1)
            energy = lerp(240.0, 1150.0, ramp_up) * flicker
        else:
            energy = 1150.0 * (1.0 - smoothstep(54.0, 63.0, f))
        light_data.energy = energy
        light_data.keyframe_insert("energy", frame=frame)
    _set_linear(action)
    ad.action = None
    track = ad.nla_tracks.new()
    track.name = "FireBreath"
    strip = track.strips.new("FireBreath", 1, action)
    strip.name = "FireBreath"
    strip.extrapolation = "NOTHING"
    track.mute = True
    action.use_fake_user = True
    light_data.energy = 0.0


def build_fire_breath(rig):
    action = bpy.data.actions.new("FireBreath")
    rig.animation_data_create().action = action
    pose = DragonPose(rig)

    # Action markers for gameplay/VFX sync
    for label, mf in [
        ("Inhale", 4),
        ("BreathStart", 19),
        ("SweepRight", 33),
        ("SweepLeft", 45),
        ("BreathEnd", 56),
    ]:
        action.pose_markers.new(label).frame = mf

    def head_sweep_yaw(f_val):
        if f_val <= 25.0 or f_val >= 57.0:
            return 0.0
        if f_val < 33.0:
            return -18.0 * smoothstep(25.0, 33.0, f_val)
        if f_val < 45.0:
            return lerp(-18.0, +18.0, smoothstep(33.0, 45.0, f_val))
        return lerp(+18.0, 0.0, smoothstep(45.0, 57.0, f_val))

    for frame in range(1, BREATH_PERIOD + 2):
        f = float((frame - 1) % BREATH_PERIOD + 1)
        pose.clear()
        pose.set("root", pose.rest["root"])

        # Envelopes:
        # inhale: 0 -> 1 over f1..16, holds briefly, releases at f19..24
        inhale = smoothstep(1.0, 15.0, f) * (1.0 - smoothstep(18.0, 23.0, f))
        # blast: surges at f18..24, sustains f24..54, settles f54..68
        blast = smoothstep(18.0, 24.0, f) * (1.0 - smoothstep(54.0, 68.0, f))
        # roar jaw: cracks open in inhale, wide 40 deg during blast, shuts cleanly by f66
        jaw_open = 15.0 * smoothstep(4.0, 15.0, f) * (1.0 - smoothstep(18.0, 24.0, f)) + 41.0 * smoothstep(17.0, 22.0, f) * (1.0 - smoothstep(55.0, 67.0, f))

        yaw_main = head_sweep_yaw(f)
        # Neck/pelvis crouch & lunge
        shift_y = 0.14 * inhale - 0.10 * blast
        shift_z = -0.10 * inhale - 0.04 * blast
        pose.swing("pelvis", rx(5.0 * inhale - 3.0 * blast) @ rz(0.15 * yaw_main), shift=(0.0, shift_y, shift_z))
        pose.swing("spine.01", rx(-8.0 * inhale + 4.5 * blast) @ rz(0.18 * yaw_main))
        pose.swing("chest", rx(-10.0 * inhale + 6.5 * blast) @ rz(0.25 * yaw_main))
        pose.swing("Rider_Mount", rx(4.0 * inhale - 3.0 * blast))

        # Neck & Head aiming: arch up to inhale, then thrust forward & skim ground (~+6 deg world pitch)
        neck1_pitch = -18.0 * inhale + 6.0 * blast
        neck2_pitch = -8.0 * inhale + 3.0 * blast
        head_pitch = -12.0 * inhale - 9.0 * blast
        pose.swing("neck.01", rx(neck1_pitch) @ rz(0.32 * yaw_main))
        pose.swing("neck.02", rx(neck2_pitch) @ rz(0.32 * yaw_main))
        pose.swing("head", rx(head_pitch) @ rz(0.36 * yaw_main))
        pose.swing("jaw", rx(jaw_open))

        # Brace through the inhale, counterweight the head sweep, then relax.
        # Distal segments respond later as load travels down the tail.
        previous_yaw = 0.15 * yaw_main
        previous_pitch = 5.0 * inhale - 3.0 * blast
        for idx in range(1, 6):
            delayed = f - 0.85 * (idx - 1)
            brace = smoothstep(1.0, 15.0, delayed) * (1.0 - smoothstep(18.0, 24.0, delayed))
            recoil = smoothstep(18.0, 25.0, delayed) * (1.0 - smoothstep(32.0, 56.0, delayed))
            yaw = -(0.12 + 0.10 * idx) * head_sweep_yaw(delayed)
            pitch = (2.9 + 0.24 * idx) * brace + (2.2 + 0.54 * idx) * recoil
            pose.swing(f"tail.0{idx}", rz(yaw - previous_yaw) @ rx(pitch - previous_pitch))
            previous_yaw, previous_pitch = yaw, pitch

        # The wing wrists brace as the chest expands. The fingers stay gathered.
        _folded_wings(pose, lift=2.2 * inhale + 3.1 * blast,
                      open_deg=2.3 * inhale + 4.2 * blast,
                      settle=1.4 * inhale + 0.7 * sin(f * 0.28) * blast)

        # Pin all 4 feet solidly on Z = 0 throughout the attack
        _pin_rest_feet(pose)

        # Fire Cone & Plumes animation
        if f < 14.0 or f > 63.0:
            _key_breath_off(pose, frame)
        else:
            if f < 19.0:
                orig_s = lerp(0.001, 0.18, smoothstep(14.0, 19.0, f))
                len_s = 0.25
                rad_s = 0.45
            elif f <= 54.0:
                orig_s = lerp(0.18, 1.0, smoothstep(18.0, 21.5, f))
                len_s = lerp(0.28, 1.0, smoothstep(18.5, 25.0, f))
                rad_s = lerp(0.45, 1.0, smoothstep(18.5, 25.0, f))
            else:
                fade = 1.0 - smoothstep(54.0, 62.5, f)
                orig_s = max(0.001, fade)
                len_s = lerp(0.35, 1.0, fade)
                rad_s = max(0.05, fade)

            pose.swing("breath_muzzle", Matrix.Identity(4))
            pose.swing("breath_origin", Matrix.Identity(4), scale=(orig_s, orig_s, orig_s))

            # Progressive whip lag along the 4 cone segments during horizontal sweep!
            for k in range(4):
                lag_f = f - k * 2.2
                seg_yaw = (head_sweep_yaw(lag_f) - yaw_main) * (0.35 if k == 0 else 0.55)
                churn = 1.0 + 0.08 * sin(f * 1.15 - k * 1.1)
                roll_deg = 12.0 * sin(f * 0.65 - k * 0.9)
                seg_len_k = clamp(len_s * (1.06 if k < 2 else 1.0), 0.15, 1.05)
                seg_rad_k = clamp(rad_s * churn, 0.05, 1.12)
                pose.swing(f"breath_seg_{k}", rz(seg_yaw) @ ry(roll_deg), scale=(seg_rad_k, seg_len_k, seg_rad_k))

            # 6 streaming flame plumes surging down inside the active fire cone
            plume_period = 11.0
            plume_env = smoothstep(21.0, 25.0, f) * (1.0 - smoothstep(53.0, 57.0, f))
            for k in range(6):
                u = ((f - 19.0 + k * (plume_period / 6.0)) % plume_period) / plume_period
                if plume_env <= 0.02 or u > 0.86:
                    pose.swing(f"breath_plume_{k}", Matrix.Identity(4), shift=(0, 0, 0), scale=(0.001, 0.001, 0.001))
                else:
                    prog = u / 0.86
                    dist = lerp(0.25, 5.80 * len_s, prog ** 0.90)
                    sc = (sin(pi * prog) ** 0.6) * lerp(0.55, 1.75, prog) * clamp(len_s) * plume_env
                    sc = max(0.001, sc)
                    lat = 0.26 * sin(k * 2.1 + prog * 4.0) * prog
                    vert = 0.14 * cos(k * 1.7 + prog * 3.5) * prog
                    pose.swing(
                        f"breath_plume_{k}",
                        ry(k * 45.0 + prog * 140.0) @ rx(prog * 25.0),
                        shift=(lat, -dist, vert),
                        scale=(sc, sc * 1.25, sc * 0.82),
                    )

        pose.record(frame)

    _set_linear(action)
    rig["breath_period_frames"] = BREATH_PERIOD
    rig["breath_fps"] = FPS
    rig["breath_range_m"] = 7.5
    rig["breath_width_m"] = 3.3
    stash_action(rig, action, mute=True)

    light_obj = bpy.data.objects.get("Breath_Light")
    if light_obj and light_obj.data:
        _animate_breath_light(light_obj.data)

    return action


def stage_preview(rig):
    """Leave Azure_Dragon.blend on its first stride frame with Walk ready to play at 24 fps."""
    scene = bpy.context.scene
    scene.render.fps = FPS
    scene.render.fps_base = 1.0
    data = rig.animation_data
    data.action = None
    data.use_nla = True
    for track in data.nla_tracks:
        track.is_solo = False
        track.mute = track.name != "Walk"
        for strip in track.strips:
            strip.extrapolation = "NOTHING"
    for pb in rig.pose.bones:
        pb.matrix_basis = Matrix.Identity(4)
        pb.scale = Vector((1.0, 1.0, 1.0))
    rig.data.pose_position = "POSE"
    scene.frame_start = 1
    scene.frame_end = WALK_PERIOD
    scene.frame_set(1)
    bpy.context.view_layer.update()


def build_all_animations(rig):
    if rig.animation_data:
        rig.animation_data_clear()
    for name in ("Rest", "Walk", "FireBreath", "FireBreath_Light"):
        old = bpy.data.actions.get(name)
        if old:
            bpy.data.actions.remove(old)

    build_rest(rig)
    build_walk(rig)
    build_fire_breath(rig)
    if 'Rider_Upper' in rig.data.bones:
        # Standalone rebakes on an already mounted model must restore the rider's keys.
        from mounted_knight import add_response
        add_response(rig)
    stage_preview(rig)
    print("Baked Rest (1-49), Walk (1-15), and FireBreath (1-73) NLA tracks at 24 fps.")


if __name__ == "__main__":
    arm = bpy.data.objects["Azure_Dragon_Rig"]
    build_all_animations(arm)
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    dest = Path(args[0]) if args else Path(bpy.data.filepath)
    bpy.context.preferences.filepaths.save_version = 0
    bpy.ops.wm.save_as_mainfile(filepath=str(dest.resolve()), compress=True)
