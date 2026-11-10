# Adds the death clip and the oil/spark/wiring effect to Infantry.blend or Scout.blend, saves the file,
# re-exports the character and exports the effect, then renders a review strip (not saved).
# Run with: blender <file.blend> --background --python death_build.py -- <repo> <scratch> infantry|scout
import bpy, bmesh, os, sys, math, random, logging, json, struct
import numpy as np
from mathutils import Vector, Euler, Quaternion, Matrix

ROOT, SP, WHO = sys.argv[sys.argv.index("--") + 1:][:3]
sys.path.insert(0, SP)
scn = bpy.context.scene
O = bpy.data.objects
FPS = scn.render.fps
rng = random.Random(4117)
bpy.context.preferences.filepaths.save_version = 0
TINY = (.001, .001, .001)


def pose(lift=0.0, loc=(0, 0, 0), air=False, gun=None, gun_rot=None, **bones):
    """A pose is absolute from the rig's rest shape. Rotations are degrees about the armature's axes, X leaning
    the top of an upright bone forward (-Y). `__` in a keyword stands for a dot in the bone's name."""
    return dict(lift=lift, loc=Vector(loc), air=air, gun=gun, gun_rot=gun_rot, bones={k.replace("__", "."): v for k, v in bones.items()})


def merged(p, **more):
    bones = dict(p["bones"])
    bones.update({k.replace("__", "."): v for k, v in more.items() if k not in ("lift", "loc", "air", "gun", "gun_rot")})
    out = dict(p)
    out["bones"] = bones
    for k in ("lift", "loc", "air", "gun", "gun_rot"):
        if k in more:
            out[k] = Vector(more[k]) if k == "loc" else more[k]
    return out


if WHO == "infantry":
    # A heavy machine that shuts down in stages: chest blown open, head thrashing, knees go, then face-down.
    HIT = pose(hips=(-6, 0, 3), spine=(-8, 0, 3), chest=(-18, 4, 8), neck=(14, 0, 0), head=(22, -8, -14), upper_arm__L=(-30, -30, 0), upper_arm__R=(-25, 30, 0), forearm__L=(-20, 0, 0), forearm__R=(-25, 0, 0), thigh__L=(-5, 0, 0), thigh__R=(4, 0, 0), loc=(0, .06, 0))
    SP1 = pose(spine=(12, 0, -6), chest=(22, -8, -15), neck=(-30, 8, 0), head=(-48, 18, 24), upper_arm__L=(-70, -20, 10), upper_arm__R=(-10, 55, 0), forearm__R=(-40, 0, 0), forearm__L=(-5, 0, 0), thigh__L=(-8, 0, 0), shin__L=(10, 0, 0))
    SP2 = pose(spine=(-10, 0, 8), chest=(-26, 10, 18), neck=(20, 0, 0), head=(38, -22, -30), upper_arm__L=(10, -60, 0), upper_arm__R=(-60, 20, 0), forearm__L=(-50, 0, 0), forearm__R=(-10, 0, 0), thigh__R=(-10, 0, 0), shin__R=(16, 0, 0))
    SP3 = pose(hips=(4, 0, -4), spine=(8, 0, -6), chest=(14, -6, -12), neck=(-14, 0, 0), head=(-30, 26, 10), upper_arm__L=(-35, -35, 0), upper_arm__R=(-40, 40, 0), forearm__L=(-30, 0, 0), forearm__R=(-30, 0, 0), thigh__L=(-30, 0, 0), thigh__R=(-34, 0, 0), shin__L=(45, 0, 0), shin__R=(50, 0, 0), foot__L=(-10, 0, 0), foot__R=(-10, 0, 0))
    KNEEL = pose(hips=(12, 0, 0), spine=(18, 0, 4), chest=(20, 0, 6), neck=(18, 0, 0), head=(30, -15, 20), upper_arm__L=(-6, -10, 0), upper_arm__R=(-12, 12, 0), forearm__L=(-10, 0, 0), forearm__R=(-6, 0, 0), thigh__L=(-12, 3, 0), thigh__R=(-12, -3, 0), shin__L=(100, 0, 0), shin__R=(100, 0, 0), foot__L=(30, 0, 0), foot__R=(30, 0, 0), skirt__L=(-12, 0, 0), skirt__R=(-12, 0, 0))
    TOPPLE = pose(hips=(52, 0, -8), spine=(10, 0, 0), chest=(10, 0, 4), neck=(-10, 0, 0), head=(-20, -10, 30), upper_arm__L=(-50, -24, 0), upper_arm__R=(-70, 18, 0), forearm__L=(-10, 0, 0), forearm__R=(-10, 0, 0), thigh__L=(-30, 4, 0), thigh__R=(-34, -4, 0), shin__L=(70, 0, 0), shin__R=(66, 0, 0), foot__L=(20, 0, 0), foot__R=(20, 0, 0), loc=(0, -.25, 0))
    SLAM = pose(hips=(90, 0, -12), spine=(-4, 0, 0), chest=(-4, 0, 0), neck=(-16, 0, 20), head=(-20, 0, 58), upper_arm__L=(-75, -62, 0), upper_arm__R=(-140, 22, 0), forearm__L=(-55, 0, 0), forearm__R=(-8, 0, 0), thigh__L=(-6, 8, 0), thigh__R=(-12, -6, 0), shin__L=(30, 0, 0), shin__R=(22, 0, 0), foot__L=(-40, 0, 0), foot__R=(-40, 0, 0), loc=(0, -.5, 0))
    LIE = merged(SLAM, spine=(2, 0, 3), chest=(-2, 0, 4), head=(-14, 0, 66), upper_arm__L=(-70, -66, 0), forearm__L=(-62, 0, 0))
    ARM_TW = merged(LIE, upper_arm__R=(-122, 30, 0), forearm__R=(-36, 0, 0), chainsaw=(-28, 0, 0))
    ARM_DOWN = merged(LIE, upper_arm__R=(-138, 20, 0), forearm__R=(-12, 0, 0))
    HEAD_TW = merged(LIE, neck=(-30, 12, 26), head=(-34, 14, 74))
    LEG_TW = merged(LIE, thigh__R=(-30, -10, 0), shin__R=(62, 0, 0), foot__R=(-15, 0, 0))
    FINAL = merged(LIE)
    TIMELINE = [(3, HIT), (6, merged(HIT, chest=(-30, 6, 12), head=(30, -14, -20))), (9, SP1), (13, SP2), (17, SP3), (26, KNEEL), (34, TOPPLE), (39, SLAM), (41, merged(SLAM, lift=.07, air=False, chest=(10, 0, 0), head=(0, 0, 50))), (46, LIE),
                (55, LIE), (57, ARM_TW), (60, ARM_DOWN), (63, LIE), (68, LIE), (70, HEAD_TW), (73, LIE), (79, LIE), (81, LEG_TW), (85, LIE), (92, FINAL)]
    LEN = 100
    CFG = dict(arm="infantry_rig2", base="Rest", clip="Die", body="hips", keep=["flash", "root"], glb="infantry", fx="infantry_death_oil")
    WOUNDS = dict(chest=("chest", (0, -.2, 1.2), (0, -1, .22)), neck=("neck", (0, .02, 1.46), (.1, -.25, 1)), back=("spine", (.08, .2, 1.05), (.25, 1, .1)))
    JETS = [("chest", 4, 38, .5, .05), ("neck", 8, 62, .6, .045), ("back", 12, 30, .35, .03)]
    GUTS = [("chest", 1.0), ("neck", .55)]
    SPARK_AT = ["neck", "chest", "back"]
    SPARK_WINDOWS = [(4, 9), (13, 17), (24, 27), (39, 43), (57, 60), (70, 73), (81, 84)]
elif WHO == "grenadier":
    # The pack ruptures: thrown back a step, the launcher slips from her hand, knees give, and she goes over on her right side, coat spread.
    base_pose = pose
    def dress(p):
        b = p["bones"]
        sp = p.get("spread", 0.0)
        dr = p.get("droop", 0.0)
        for n, s in (("L", 1), ("R", -1)):
            t = b.get("thigh." + n, (0, 0, 0))[0]
            ua = b.get("upper_arm." + n, (0, 0, 0))
            b["pauldron." + n] = tuple(x * .5 for x in ua)
            b["coat_f." + n] = (min(t, 6) * .8 - sp, dr, 0)
            b["coat_f_lo." + n] = (-min(t, 6) * .3 - sp * .5, dr * .4, 0)
            b["coat_s." + n] = (t * .38, -s * sp + dr, 0)
            b["coat_s_lo." + n] = (-t * .15, -s * sp * .5 + dr * .4, 0)
            b["coat_b." + n] = (max(t, -12) * .5 + sp, dr, 0)
            b["coat_b_lo." + n] = (sp * .5, dr * .4, 0)
        b["tabard"] = (min(b.get("thigh.L", (0, 0, 0))[0], 0) * .6 - sp * .6, dr, 0)
        return p
    def pose(lift=0.0, loc=(0, 0, 0), air=False, gun=None, gun_rot=None, spread=0.0, droop=0.0, **bones):
        p = base_pose(lift, loc, air, gun, gun_rot, **bones)
        p["spread"], p["droop"] = spread, droop
        return dress(p)
    base_merged = merged
    def merged(p, **more):
        return dress(base_merged(p, **more))
    G_DROP = dict(gun=(-.05, -.72, -.5), gun_rot=(-88, 0, 24))
    HIT = pose(hips=(-6, 0, 4), spine=(-6, 0, 2), chest=(-18, -4, 6), neck=(14, 0, 0), head=(24, 8, -10), upper_arm__L=(-35, -28, 0), upper_arm__R=(-30, 30, 0), forearm__L=(-30, 0, 0), forearm__R=(-20, 0, 0), thigh__L=(-6, 0, 0), thigh__R=(5, 0, 0), loc=(0, .08, 0), gun=(-.02, -.04, .05), gun_rot=(8, 6, 10))
    SP1 = pose(hips=(3, 0, -5), spine=(10, 0, -5), chest=(20, 6, -14), neck=(-24, -6, 0), head=(-40, -16, 20), upper_arm__L=(-75, -15, 0), forearm__L=(-70, 0, 0), upper_arm__R=(-20, 45, 0), forearm__R=(-30, 0, 0), thigh__L=(-8, 0, 0), shin__L=(10, 0, 0), loc=(0, .1, 0), gun=(-.1, -.08, -.05), gun_rot=(-22, 10, 20))
    SP2 = pose(hips=(-3, 0, 6), spine=(-8, 0, 6), chest=(-24, -10, 16), neck=(18, 0, 0), head=(34, 20, -26), upper_arm__L=(0, -55, 0), forearm__L=(-45, 0, 0), upper_arm__R=(-55, 20, 0), forearm__R=(-20, 0, 0), thigh__R=(-12, 0, 0), shin__R=(18, 0, 0), loc=(0, .12, 0), gun=(-.08, -.32, -.32), gun_rot=(-55, 6, 22))
    SAG = pose(hips=(8, -3, -4), spine=(12, 0, -6), chest=(16, -8, -10), neck=(10, 0, 0), head=(26, -20, 10), upper_arm__L=(-30, -30, 0), upper_arm__R=(-20, 30, 0), forearm__L=(-30, 0, 0), forearm__R=(-30, 0, 0), thigh__L=(-32, 0, 0), thigh__R=(-36, 0, 0), shin__L=(50, 0, 0), shin__R=(56, 0, 0), foot__L=(-12, 0, 0), foot__R=(-12, 0, 0), spread=8, **G_DROP)
    KNEEL = pose(hips=(10, -6, 0), spine=(14, -4, 4), chest=(16, -10, 6), neck=(14, -6, 0), head=(34, -24, 16), upper_arm__L=(-8, -14, 0), upper_arm__R=(-14, 14, 0), forearm__L=(-12, 0, 0), forearm__R=(-8, 0, 0), thigh__L=(-14, 3, 0), thigh__R=(-14, -3, 0), shin__L=(100, 0, 0), shin__R=(100, 0, 0), foot__L=(30, 0, 0), foot__R=(30, 0, 0), spread=32, **G_DROP)
    TILT = pose(hips=(12, -42, 0), spine=(8, -8, 0), chest=(8, -8, 4), neck=(8, -10, 0), head=(20, -20, 20), upper_arm__R=(-30, 8, 0), forearm__R=(-20, 0, 0), upper_arm__L=(-60, -30, 0), forearm__L=(-30, 0, 0), thigh__L=(-30, 0, 0), thigh__R=(-34, 0, 0), shin__L=(70, 0, 0), shin__R=(76, 0, 0), foot__L=(20, 0, 0), foot__R=(20, 0, 0), loc=(-.2, 0, 0), spread=14, droop=16, **G_DROP)
    SLAM = pose(hips=(8, -86, 0), spine=(6, -4, 0), chest=(8, -2, 0), neck=(6, 8, 0), head=(8, 18, 14), upper_arm__R=(-70, 0, 0), forearm__R=(-20, 0, 0), upper_arm__L=(-50, -20, 0), forearm__L=(-28, 0, 0), thigh__L=(-42, 0, 0), shin__L=(65, 0, 0), thigh__R=(-18, 0, 0), shin__R=(40, 0, 0), foot__L=(-15, 0, 0), foot__R=(-15, 0, 0), loc=(-.55, 0, 0), spread=2, droop=34, **G_DROP)
    LIE = merged(SLAM, chest=(4, -2, 0), head=(6, 22, 18))
    ARM_TW = merged(LIE, upper_arm__L=(-95, -34, 0), forearm__L=(-65, 0, 0))
    ARM_DOWN = merged(LIE, upper_arm__L=(-44, -18, 0), forearm__L=(-18, 0, 0))
    HEAD_TW = merged(LIE, neck=(-10, 14, 0), head=(-14, 30, 26))
    LEG_TW = merged(LIE, thigh__L=(-58, 0, 0), shin__L=(92, 0, 0))
    FINAL = merged(ARM_DOWN)
    TIMELINE = [(3, HIT), (7, SP1), (11, SP2), (16, SAG), (26, KNEEL), (34, TILT), (39, SLAM), (41, merged(SLAM, lift=.05, chest=(14, 0, 0), head=(0, 26, 14))), (46, LIE),
                (55, LIE), (57, ARM_TW), (60, ARM_DOWN), (63, LIE), (68, LIE), (70, HEAD_TW), (73, LIE), (79, LIE), (81, LEG_TW), (85, LIE), (92, FINAL)]
    LEN = 100
    CFG = dict(arm="grenadier_rig", base="Rest", clip="Die", body="hips", keep=["flash", "root"], glb="grenadier", fx="grenadier_death_oil")
    WOUNDS = dict(chest=("chest", (0, -.18, 1.3), (0, -1, .22)), neck=("neck", (.03, -.05, 1.49), (.2, -.4, 1)), pack=("pack", (.02, .34, 1.36), (.15, 1, .3)))
    JETS = [("chest", 4, 40, .5, .05), ("neck", 7, 62, .55, .045), ("pack", 3, 36, .5, .04)]
    GUTS = [("chest", .85), ("neck", .5)]
    SPARK_AT = ["neck", "chest", "pack"]
    SPARK_WINDOWS = [(3, 8), (11, 16), (26, 29), (39, 43), (57, 60), (70, 73), (81, 84)]
else:
    # On skates: the feet shoot out from under her, she is thrown flat on her back and convulses while the wheels spin down.
    arms_out = dict(upper_arm__L=(-6, -78, 0), upper_arm__R=(-10, 84, 0), forearm__L=(-12, 0, 0), forearm__R=(-22, 0, 0))
    HIT = pose(pelvis=(-8, 0, 3), spine=(-6, 0, 0), chest=(-14, 3, 6), neck=(12, 0, 0), head=(24, -8, -10), upper_arm__L=(-60, -30, 0), upper_arm__R=(-50, 34, 0), forearm__L=(-30, 0, 0), forearm__R=(-40, 0, 0), thigh__L=(-14, 0, 0), thigh__R=(-6, 0, 0), shin__L=(12, 0, 0), shin__R=(10, 0, 0), gun=(-.05, -.12, .12), gun_rot=(10, 12, 18), hair1=(-12, 0, 0), hair2=(-8, 0, 0))
    AIR1 = pose(pelvis=(-40, 0, 4), loc=(0, .12, .1), air=True, spine=(-8, 0, 0), chest=(-10, 4, 8), neck=(16, 0, 0), head=(30, -6, -14), upper_arm__L=(-120, -34, 0), upper_arm__R=(-105, 40, 0), forearm__L=(-30, 0, 0), forearm__R=(-40, 0, 0), thigh__L=(-68, 4, 0), thigh__R=(-52, -4, 0), shin__L=(14, 0, 0), shin__R=(24, 0, 0), foot__L=(-20, 0, 0), foot__R=(-20, 0, 0), gun=(-.2, -.1, .48), gun_rot=(70, 30, 60), hair1=(-34, 0, 0), hair2=(-14, 0, 0), hair3=(-8, 0, 0))
    AIR2 = pose(pelvis=(-74, 0, 8), loc=(0, .4, -.3), air=True, spine=(-4, 0, 0), chest=(-4, 5, 8), neck=(22, 0, 0), head=(26, -4, -6), upper_arm__L=(-140, -44, 0), upper_arm__R=(-130, 50, 0), forearm__L=(-24, 0, 0), forearm__R=(-30, 0, 0), thigh__L=(-56, 6, 0), thigh__R=(-42, -6, 0), shin__L=(22, 0, 0), shin__R=(30, 0, 0), foot__L=(-20, 0, 0), foot__R=(-20, 0, 0), gun=(-.38, -.05, .3), gun_rot=(150, 60, 120), hair1=(-60, 0, 0), hair2=(-20, 0, 0), hair3=(-12, 0, 0))
    SLAM = pose(pelvis=(-92, 0, 6), loc=(0, .55, 0), spine=(-3, 0, 0), chest=(-4, 0, 0), neck=(-22, 0, 8), head=(-32, 0, 14), thigh__L=(-20, 7, 0), thigh__R=(-8, -7, 0), shin__L=(20, 0, 0), shin__R=(12, 0, 0), foot__L=(-6, 0, 0), foot__R=(-6, 0, 0), gun=(-.62, .1, -.6), gun_rot=(-34, 8, 70), hair1=(-80, 0, 0), hair2=(-8, 0, 0), hair3=(-4, 0, 0), **arms_out)
    BOUNCE = merged(SLAM, lift=.08, chest=(24, 0, 2), spine=(10, 0, 0), neck=(12, 0, 0), head=(32, 0, 12), thigh__L=(-40, 7, 0), shin__L=(46, 0, 0))
    LIE = merged(SLAM, chest=(0, 0, 0), neck=(-8, 0, 16), head=(-10, 0, 44))
    ARCH1 = merged(LIE, spine=(-16, 0, 0), chest=(-26, 3, 0), neck=(-14, 0, 20), head=(-24, 0, 60), upper_arm__L=(-24, -92, 0), forearm__L=(-6, 0, 0))
    ARCH2 = merged(LIE, spine=(-6, 0, 0), chest=(12, -3, 0), head=(14, 0, 16), upper_arm__R=(-30, 66, 0), forearm__R=(-34, 0, 0))
    KICK = merged(LIE, thigh__R=(-40, -9, 0), shin__R=(62, 0, 0), foot__R=(-20, 0, 0))
    HAND = merged(LIE, forearm__L=(-58, 0, 0), hand__L=(-40, 0, 0))
    HEAD_TW = merged(LIE, neck=(-14, 0, 2), head=(-20, 8, 16))
    FINAL = merged(LIE)
    TIMELINE = [(3, HIT), (7, AIR1), (12, AIR2), (16, SLAM), (19, BOUNCE), (23, LIE), (27, ARCH1), (30, ARCH2), (33, ARCH1), (36, merged(ARCH2, head=(4, 0, 30))), (40, LIE),
                (52, LIE), (54, KICK), (57, LIE), (64, LIE), (66, HAND), (69, LIE), (75, LIE), (77, HEAD_TW), (80, LIE), (92, FINAL)]
    LEN = 100
    CFG = dict(arm="Skater rig", base="idle", clip="die", body="pelvis", keep=["flash", "shell", "pump", "root"], glb="scout", fx="scout_death_oil")
    # Wounds sit on parts both heads share: chest plate, neck, and the throat inside the collar.
    WOUNDS = dict(chest=("chest", (0, -.10, 1.33), (0, -1, .2)), neck=("neck", (0, -.01, 1.50), (.1, -.5, 1)), visor=("neck", (.03, -.055, 1.485), (.15, -1, .35)))
    JETS = [("chest", 3, 58, .5, .045), ("neck", 6, 60, .45, .04), ("visor", 16, 44, .3, .025)]
    GUTS = [("chest", .85), ("neck", .5)]
    SPARK_AT = ["neck", "chest", "visor"]
    SPARK_WINDOWS = [(3, 8), (16, 21), (27, 30), (33, 37), (54, 57), (66, 69), (77, 80)]

arm = O[CFG["arm"]]
if WHO == "scout" and CFG["clip"] in bpy.data.actions:
    # Rebuild: drop the old clip and effect first.
    old = bpy.data.collections.get("scout_death_fx")
    if old:
        for o in list(old.objects):
            O.remove(o)
        bpy.data.collections.remove(old)
    for a in list(bpy.data.actions):
        if a.name.endswith("_Death") or a.name == CFG["clip"]:
            bpy.data.actions.remove(a)
    for me in list(bpy.data.meshes):
        if me.users == 0:
            bpy.data.meshes.remove(me)
    for m in list(bpy.data.materials):
        if m.name.startswith("death_"):
            bpy.data.materials.remove(m)
assert CFG["clip"] not in bpy.data.actions, "already applied: restore the backup first"
ad = arm.animation_data
base = bpy.data.actions[CFG["base"]]
previous = ad.action
ad.action = base
scn.frame_set(1)
bpy.context.view_layer.update()
BASE = {b.name: (b.location.copy(), b.rotation_quaternion.copy(), b.scale.copy()) for b in arm.pose.bones}
assert all(b.rotation_mode == "QUATERNION" for b in arm.pose.bones), "rig is not quaternion"
LOCAL = {b.name: b.bone.matrix_local.to_3x3() for b in arm.pose.bones}
LOCAL_Q = {k: v.to_quaternion() for k, v in LOCAL.items()}

die = bpy.data.actions.new(CFG["clip"])
die.use_fake_user = True
ad.action = die


def key_bone(b, frame):
    b.keyframe_insert("location", frame=frame, group=b.name)
    b.keyframe_insert("rotation_quaternion", frame=frame, group=b.name)
    b.keyframe_insert("scale", frame=frame, group=b.name)


def apply_pose(p):
    for b in arm.pose.bones:
        loc, rot, sca = BASE[b.name]
        if b.name in CFG["keep"] or b.name == "gun":
            b.location, b.rotation_quaternion, b.scale = loc, rot, sca
            continue
        b.scale = (1, 1, 1)
        b.location = (0, 0, 0)
        d = p["bones"].get(b.name)
        q = Quaternion() if d is None else LOCAL_Q[b.name].inverted() @ Euler([math.radians(x) for x in d], "XYZ").to_quaternion() @ LOCAL_Q[b.name]
        b.rotation_quaternion = q
    body = arm.pose.bones[CFG["body"]]
    body.location = LOCAL[body.name].inverted() @ p["loc"]
    if "gun" in arm.pose.bones:
        g = arm.pose.bones["gun"]
        loc, rot, sca = BASE["gun"]
        if p["gun"] is not None:
            g.location = loc + LOCAL["gun"].inverted() @ Vector(p["gun"])
            q = Euler([math.radians(x) for x in p["gun_rot"]], "XYZ").to_quaternion()
            g.rotation_quaternion = (LOCAL_Q["gun"].inverted() @ q @ LOCAL_Q["gun"]) @ rot


# Subdivision off while evaluating and exporting: the game mesh has none.
SUBSURF = [(m, m.levels) for o in O for m in o.modifiers if m.type == "SUBSURF"]
for m, _ in SUBSURF:
    m.levels = 0
if WHO == "infantry":
    body_meshes = [o for o in bpy.data.collections["rig_artpose"].objects if o.type == "MESH" and o.name != "Muzzle flash"]
    loose_meshes = []
elif WHO == "grenadier":
    body_meshes = [o for o in arm.children if o.type == "MESH" and o.name not in ("coat", "tabard_plate", "grenade_launcher", "Muzzle flash")]
    loose_meshes = [O["grenade_launcher"]]
else:
    skip = ("Muzzle flash", "Shell casing", "ponytail", "head_bare_hair", "shotgun")
    body_meshes = [o for o in O if o.type == "MESH" and not any(s in o.name for s in skip)]
    loose_meshes = [o for o in O if o.type == "MESH" and "shotgun" in o.name]


def lowest(obs):
    dg = bpy.context.evaluated_depsgraph_get()
    low = 1e9
    for o in obs:
        e = o.evaluated_get(dg)
        m = e.to_mesh()
        if len(m.vertices):
            c = np.empty(len(m.vertices) * 3)
            m.vertices.foreach_get("co", c)
            c = c.reshape(-1, 3)
            M = np.array(e.matrix_world)
            low = min(low, float((c @ M[2, :3] + M[2, 3]).min()))
        e.to_mesh_clear()
    return low


# ---- key the poses, resting each one on the ground
for b in arm.pose.bones:
    b.location, b.rotation_quaternion, b.scale = BASE[b.name]
    key_bone(b, 1)
SINK_FROM = 92
timeline = TIMELINE + [(LEN, merged(FINAL, lift=-.42))]
for f, p in timeline:
    apply_pose(p)
    bod = arm.pose.bones[CFG["body"]]
    for b in arm.pose.bones:
        key_bone(b, f)
    scn.frame_set(f)
    bpy.context.view_layer.update()
    low = lowest(body_meshes)
    dz = max(-low, 0.0) if p["air"] else -low
    apply_pose(p)
    bod.location = LOCAL[bod.name].inverted() @ (p["loc"] + Vector((0, 0, dz + p["lift"])))
    key_bone(bod, f)
    if loose_meshes and p["gun"] is not None and not p["air"] and f >= 16:
        scn.frame_set(f)
        bpy.context.view_layer.update()
        g = arm.pose.bones["gun"]
        dzg = max(-lowest(loose_meshes), 0.0) if f < 16 else -lowest(loose_meshes)
        g.location = g.location + LOCAL["gun"].inverted() @ Vector((0, 0, dzg + p["lift"]))
        key_bone(g, f)

# Wheels spin on after the fall and run down.
if WHO == "scout":
    for b in arm.pose.bones:
        if not b.name.startswith("wheel."):
            continue
        angle, speed = 0.0, math.radians(48)
        for f in range(1, LEN + 1, 2):
            if f < 16:
                speed = math.radians(48)
            else:
                speed *= .93
            angle += speed * 2
            b.rotation_quaternion = Quaternion((0, 1, 0), angle) @ BASE[b.name][1]
            b.location, b.scale = BASE[b.name][0], BASE[b.name][2]
            b.keyframe_insert("rotation_quaternion", frame=f, group=b.name)

for fc in die.fcurves:
    for k in fc.keyframe_points:
        k.interpolation = "BEZIER"
        k.handle_left_type = k.handle_right_type = "AUTO_CLAMPED"
    fc.update()
print("KEYED", CFG["clip"], "frames", LEN, "curves", len(die.fcurves))

# ---- where each wound is on every frame
ad.action = die
FRAMES = list(range(1, LEN + 1))
TRACK = {}
BONES_AT = {}
for f in FRAMES:
    scn.frame_set(f)
    bpy.context.view_layer.update()
    for name, (bone, at, d) in WOUNDS.items():
        b = arm.pose.bones[bone]
        M = arm.matrix_world @ b.matrix @ b.bone.matrix_local.inverted()
        p = M @ Vector(at)
        loc, rot, _ = M.decompose()
        TRACK.setdefault(name, {})[f] = (p, rot, (rot @ Vector(d)).normalized())
    if f == LEN - 8:
        REST_HIPS = (arm.matrix_world @ arm.pose.bones[CFG["body"]].head).copy()


def material(name, base=(0, 0, 0), rough=.8, metal=0.0, emit=None, power=0.0, spec=.5):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    p = next(n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    p.inputs["Base Color"].default_value = (*base, 1)
    p.inputs["Roughness"].default_value = rough
    p.inputs["Metallic"].default_value = metal
    p.inputs["Specular IOR Level"].default_value = spec
    if emit:
        p.inputs["Emission Color"].default_value = (*emit, 1)
        p.inputs["Emission Strength"].default_value = power
    return m


OIL = material("death_oil", (.012, .011, .016), .07, 0.0, spec=1.0)
SPARK = material("death_spark", emit=(.55, .85, 1), power=6)
COPPER = material("death_wire_copper", (.72, .36, .13), .32, 1.0)
INSUL = material("death_wire_black", (.03, .03, .035), .5)
STEEL = material("death_frame_steel", (.34, .36, .4), .3, 1.0)
GLOW = material("death_core", emit=(.2, .75, 1), power=4)


def finish(bm, name, mats, smooth=False):
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    for f in bm.faces:
        f.smooth = smooth
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    for m in mats:
        me.materials.append(m)
    return me


def blob(name):
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=1, radius=1)
    return finish(bm, name, [OIL], True)


DROP = blob("oil_drop_%s" % WHO)


def pool_mesh(name, seed):
    r = random.Random(seed)
    ph = [r.random() * 6.28 for _ in range(5)]
    bm = bmesh.new()
    N = 72
    centre = bm.verts.new((0, 0, .022))
    inner, outer = [], []
    for i in range(N):
        a = i * math.tau / N
        rad = 1 + .2 * math.sin(a * 2 + ph[0]) + .14 * math.sin(a * 3 + ph[1]) + .08 * math.sin(a * 5 + ph[2]) + .04 * math.sin(a * 8 + ph[3])
        d = Vector((math.cos(a), math.sin(a), 0))
        inner.append(bm.verts.new(d * rad * .86 + Vector((0, 0, .018))))
        outer.append(bm.verts.new(d * rad))
    for i in range(N):
        j = (i + 1) % N
        bm.faces.new((centre, inner[i], inner[j]))
        bm.faces.new((inner[i], outer[i], outer[j], inner[j]))
    return finish(bm, name, [OIL], True)


def tapered(name, mat, profile, n=7):
    bm = bmesh.new()
    rows = []
    for y, r in profile:
        rows.append([bm.verts.new((r * math.cos(k * math.tau / n), y, r * math.sin(k * math.tau / n))) for k in range(n)] if r > 0 else [bm.verts.new((0, y, 0))])
    for A, B in zip(rows, rows[1:]):
        for k in range(n):
            vs = list(dict.fromkeys((A[k % len(A)], A[(k + 1) % len(A)], B[(k + 1) % len(B)], B[k % len(B)])))
            bm.faces.new(vs)
    if len(rows[0]) > 1:
        bm.faces.new(rows[0][::-1])
    return finish(bm, name, [mat], True)


JET = tapered("oil_jet_%s" % WHO, OIL, [(0, 1.0), (.2, 1.25), (.5, .9), (.8, .75), (.92, .9), (1, 0)])


def spark_mesh(name):
    bm = bmesh.new()
    r = random.Random(9)
    for i in range(7):
        d = Vector((r.uniform(-1, 1), r.uniform(-1, 1), r.uniform(-1, 1))).normalized()
        side = d.orthogonal().normalized() * .018
        up = d.cross(side).normalized() * .018
        L = r.uniform(.14, .3)
        a, b, c, e = [bm.verts.new(v) for v in (side, up, -side, -up)]
        t = bm.verts.new(d * L)
        for x, y in ((a, b), (b, c), (c, e), (e, a)):
            bm.faces.new((x, y, t))
    return finish(bm, name, [SPARK])


def tube(bm, pts, r, mi, n=5):
    prev = None
    first = None
    for i, p in enumerate(pts):
        t = (pts[min(i + 1, len(pts) - 1)] - pts[max(i - 1, 0)]).normalized()
        u = t.orthogonal().normalized()
        v = t.cross(u)
        ring = [bm.verts.new(p + (u * math.cos(k * math.tau / n) + v * math.sin(k * math.tau / n)) * r) for k in range(n)]
        if prev:
            for k in range(n):
                f = bm.faces.new((prev[k], prev[(k + 1) % n], ring[(k + 1) % n], ring[k]))
                f.material_index = mi
        prev = ring
        first = first or ring
    bm.faces.new(prev).material_index = mi
    bm.faces.new(first[::-1]).material_index = mi


def guts_mesh(name, seed):
    """Wires, push-rods and a glowing core spilling out of the wound; authored in rest axes, spilling toward -Y."""
    r = random.Random(seed)
    bm = bmesh.new()
    for i in range(9):
        start = Vector((r.uniform(-.09, .09), .02, r.uniform(-.08, .08)))
        length, droop = r.uniform(.14, .42), r.uniform(.05, .22)
        side = r.uniform(-.14, .14)
        pts = [start + Vector((side * s, -length * s, -droop * s * s + .03 * math.sin(s * 5 + i))) for s in (0, .2, .4, .6, .8, 1)]
        tube(bm, pts, r.uniform(.007, .014), i % 2)
    for i in range(3):
        a = Vector((-.07 + i * .07, .03, -.04 + i * .03))
        b = a + Vector((r.uniform(-.05, .05), -.17, r.uniform(-.12, .05)))
        tube(bm, [a, b], .016, 2, 6)
        tube(bm, [b, b + (b - a).normalized() * .05], .025, 2, 6)
    core = bmesh.ops.create_icosphere(bm, subdivisions=1, radius=.05, matrix=Matrix.Translation((.01, -.015, .02)))
    for v in core["verts"]:
        for f in v.link_faces:
            f.material_index = 3
    return finish(bm, name, [COPPER, INSUL, STEEL, GLOW], False)


def coat_mesh(name, seed):
    r = random.Random(seed)
    bm = bmesh.new()
    def lump(at, size):
        m = Matrix.Translation(at) @ Matrix.Diagonal((*size, 1))
        bmesh.ops.create_icosphere(bm, subdivisions=2, radius=1, matrix=m)
    lump(Vector((0, .02, 0)), (.13, .045, .13))
    for i in range(5):
        x, l = r.uniform(-.11, .11), r.uniform(.2, .42)
        lump(Vector((x, .015, -l * .55)), (r.uniform(.016, .03), .02, l * .55))
    return finish(bm, name, [OIL], True)


col = bpy.data.collections.new(WHO + "_death_fx")
scn.collection.children.link(col)
FX = []


def spawn(name, mesh):
    ob = O.new(name, mesh)
    col.objects.link(ob)
    ob.rotation_mode = "QUATERNION"
    FX.append(ob)
    return ob


def bake(ob, keys):
    """keys: (frame, location, quaternion, scale); becomes the object's single NLA strip named Death."""
    for f, loc, q, s in keys:
        ob.location, ob.rotation_quaternion, ob.scale = loc, q, s
        for p in ("location", "rotation_quaternion", "scale"):
            ob.keyframe_insert(p, frame=f)
    a = ob.animation_data
    act = a.action
    act.name = ob.name + "_Death"
    act.use_fake_user = True
    for fc in act.fcurves:
        for k in fc.keyframe_points:
            k.interpolation = "LINEAR"
    t = a.nla_tracks.new()
    t.name = "Death"
    st = t.strips.new("Death", 1, act)
    st.frame_end = LEN
    a.action = None


def smooth(a, b, x):
    t = max(0.0, min(1.0, (x - a) / (b - a)))
    return t * t * (3 - 2 * t)


Y = Vector((0, 1, 0))
SINK = lambda f: 1 - smooth(SINK_FROM, LEN, f)
landed = []

# Jets pump in spurts, like a burst hydraulic line.
for j, (wound, start, end, reach, width) in enumerate(JETS):
    ob = spawn("Oil_Jet_%d" % (j + 1), JET)
    keys = [(1, Vector(), Quaternion(), TINY)]
    for f in FRAMES:
        p, rot, d = TRACK[wound][f]
        if f < start or f > end:
            if f in (start - 1, end + 1):
                keys.append((f, p, Quaternion(), TINY))
            continue
        fade = smooth(start, start + 2, f) * (1 - smooth(end - 8, end, f))
        pulse = .5 + .5 * max(0.0, math.sin((f - start) * 1.05))
        L = reach * pulse * fade
        w = width * (.6 + .4 * pulse) * fade
        wob = Vector((rng.uniform(-.1, .1), rng.uniform(-.1, .1), rng.uniform(-.05, .05)))
        keys.append((f, p, Y.rotation_difference((d + wob).normalized()), (max(w, .001), max(L, .001), max(w, .001))))
    keys.append((LEN, Vector(), Quaternion(), TINY))
    keys.sort(key=lambda k: k[0])
    bake(ob, keys)

# Droplets thrown out on each spurt: ballistic, stretched along their flight, gone where they land.
N_DROPS = 54
for i in range(N_DROPS):
    wound, start, end, reach, width = rng.choice(JETS)
    f0 = rng.randint(start, max(start + 1, end - 8))
    p0, rot, d = TRACK[wound][f0]
    v = d * rng.uniform(1.4, 3.4) + Vector((rng.uniform(-.8, .8), rng.uniform(-.8, .8), rng.uniform(.4, 1.5)))
    size = rng.uniform(.012, .03)
    ob = spawn("Oil_Drop_%d" % (i + 1), DROP)
    keys = [(1, p0, Quaternion(), TINY)]
    if f0 > 2:
        keys.append((f0 - 1, p0, Quaternion(), TINY))
    f = f0
    p = p0
    while f < LEN:
        t = (f - f0) / FPS
        p = p0 + v * t + Vector((0, 0, -4.9 * t * t))
        vel = v + Vector((0, 0, -9.8 * t))
        if p.z <= .01:
            p.z = .01
            keys.append((f, p, Quaternion(), TINY))
            landed.append((f, p.copy(), size))
            break
        s = size * smooth(f0 - 1, f0 + 1, f)
        keys.append((f, p, Y.rotation_difference(vel.normalized()), (max(s, .001), max(s * (1 + vel.length * .3), .001), max(s, .001))))
        f += 1
    if keys[-1][0] < LEN:
        keys.append((LEN, p, Quaternion(), TINY))
    bake(ob, keys)

# A splat where the bigger droplets land, kept until the corpse goes.
landed.sort(key=lambda x: -x[2])
for i, (f, p, size) in enumerate(landed[:10]):
    ob = spawn("Oil_Splat_%d" % (i + 1), pool_mesh("oil_splat_%s_%d" % (WHO, i), 60 + i))
    p = Vector((p.x, p.y, .006))
    r = size * rng.uniform(3.5, 6.0)
    yaw = Quaternion((0, 0, 1), rng.random() * 6.28)
    keys = [(1, p, yaw, TINY), (max(f - 1, 2), p, yaw, TINY), (f + 1, p, yaw, (r, r, 1)), (SINK_FROM, p, yaw, (r * 1.05, r * 1.05, 1)), (LEN, p, yaw, TINY)]
    bake(ob, sorted(keys, key=lambda k: k[0]))

# The main pool spreads from under the torso for the rest of the clip.
FIRST_DOWN = 17 if WHO == "scout" else 40
chest_end = TRACK["chest"][SINK_FROM][0]
neck_end = TRACK["neck"][SINK_FROM][0]
main = Vector(((chest_end.x + REST_HIPS.x) / 2, (chest_end.y + REST_HIPS.y) / 2, .009))
for name, at, radius, f0, f1, seed in (("Oil_Pool", main, .66, FIRST_DOWN, 72, 11), ("Oil_Pool_Neck", Vector((neck_end.x, neck_end.y, .012)), .36, FIRST_DOWN + 3, 68, 23)):
    ob = spawn(name, pool_mesh("oil_%s_%s" % (name, WHO), seed))
    yaw = Quaternion((0, 0, 1), rng.random() * 6.28)
    keys = [(1, at, yaw, TINY), (f0, at, yaw, TINY)]
    for f in range(f0 + 3, LEN + 1, 3):
        g = (1 - (1 - smooth(f0, f1, f)) ** 1.8) * SINK(f)
        s = max(radius * g, .001)
        keys.append((f, at, yaw, (s, s, 1 if g > .01 else .001)))
    keys.append((LEN, at, yaw, TINY))
    bake(ob, keys)

# Oil coats the wounds and wiring spills out of them, riding on their bones.
for wound, scale in GUTS:
    bone_track = TRACK[wound]
    start = JETS[0][1] if wound == "chest" else JETS[1][1]
    g = spawn("Cyber_Guts_" + wound.title(), guts_mesh("cyber_guts_%s_%s" % (WHO, wound), 5 if wound == "chest" else 8))
    c = spawn("Oil_Coat_" + wound.title(), coat_mesh("oil_coat_%s_%s" % (WHO, wound), 15 if wound == "chest" else 18))
    gk, ck = [(1, bone_track[1][0], Quaternion(), TINY)], [(1, bone_track[1][0], Quaternion(), TINY)]
    for f in FRAMES:
        if f < start - 1:
            continue
        p, rot, d = bone_track[f]
        a = smooth(start - 1, start + 2, f) * scale * (.0 if f == LEN else 1)
        b = smooth(start - 1, start + 14, f) * scale * (.0 if f == LEN else 1)
        gk.append((f, p, rot, (max(a, .001),) * 3))
        ck.append((f, p, rot, (max(b, .001),) * 3))
    bake(g, gk)
    bake(c, ck)

# Sparks: the first one also drives the scene light.
for i, wound in enumerate(SPARK_AT):
    ob = spawn("Spark_Main" if i == 0 else "Spark_%d" % (i + 1), spark_mesh("death_spark_%s_%d" % (WHO, i)))
    keys = []
    for f in FRAMES:
        p, rot, d = TRACK[wound][f]
        live = any(a <= f <= b for a, b in SPARK_WINDOWS) and f < SINK_FROM and (i == 0 or rng.random() < .75)
        s = rng.uniform(.55, 1.15) if live and rng.random() < .8 else .001    # Spark_Main's scale is what the light reads
        q = Euler((rng.random() * 6, rng.random() * 6, rng.random() * 6)).to_quaternion()
        keys.append((f, p, q, (s,) * 3))
    bake(ob, keys)
print("FX objects", len(FX), "tris", sum(len(p.vertices) - 2 for o in FX for p in o.data.polygons))

# ---- exports
ad.action = die
scn.frame_set(1)
bpy.context.view_layer.update()
logging.disable(logging.CRITICAL)


def select(obs):
    for o in bpy.context.selected_objects:
        o.select_set(False)
    for o in obs:
        o.hide_set(False)
        o.select_set(True)
    bpy.context.view_layer.objects.active = obs[0]


EFFECTS = os.path.join(ROOT, "assets", "models", "effects")
os.makedirs(EFFECTS, exist_ok=True)
UNITS = os.path.join(ROOT, "assets", "models", "units")
GLB = dict(export_format="GLB", use_selection=True, export_yup=True, export_apply=True, export_materials="EXPORT", export_cameras=False, export_extras=False)
select(FX)
fx_path = os.path.join(EFFECTS, CFG["fx"] + ".glb")
bpy.ops.export_scene.gltf(filepath=fx_path, export_animations=True, export_animation_mode="NLA_TRACKS", export_lights=False, **GLB)

if WHO == "infantry":
    t = ad.nla_tracks.new()
    t.name = CFG["clip"]
    st = t.strips.new(CFG["clip"], 1, die)
    st.frame_end = LEN
    ad.action = None
    coll = bpy.data.collections["rig_artpose"]
    select([arm] + [o for o in coll.objects if o is not arm])
    bpy.ops.export_scene.gltf(filepath=os.path.join(UNITS, "infantry.glb"), export_animations=True, export_animation_mode="NLA_TRACKS", export_lights=True, **GLB)
elif WHO == "grenadier":
    t = ad.nla_tracks.new()
    t.name = CFG["clip"]
    st = t.strips.new(CFG["clip"], 1, die)
    st.frame_end = LEN
    ad.action = None
    select([arm] + list(arm.children))
    bpy.ops.export_scene.gltf(filepath=os.path.join(UNITS, "grenadier.glb"), export_animations=True, export_animation_mode="NLA_TRACKS", export_lights=True, **GLB)
else:
    ad.action = previous
    scn.frame_set(1)
    obs = [o for o in O if o.type == "MESH" and o.users_collection and o.users_collection[0].name == "Collection"] + [O["Skater rig"], O["Muzzle light"]]
    select([arm] + [o for o in obs if o is not arm])
    bpy.ops.export_scene.gltf(filepath=os.path.join(UNITS, "scout.glb"), export_format="GLB", use_selection=True, export_apply=True, export_yup=True, export_lights=True, export_animations=True, export_animation_mode="ACTIONS", export_def_bones=False,
                              export_force_sampling=True, export_frame_step=1, export_optimize_animation_size=False, export_skins=True, export_morph=False, export_cameras=False)
logging.disable(logging.NOTSET)
for path in (fx_path, os.path.join(UNITS, CFG["glb"] + ".glb")):
    with open(path, "rb") as h:
        h.read(12)
        ln, _ = struct.unpack("<I4s", h.read(8))
        g = json.loads(h.read(ln))
    acc = g["accessors"]
    print("GLB", os.path.basename(path), os.path.getsize(path) // 1024, "KB nodes", len(g["nodes"]), "anims", [(a["name"], round(max(acc[s["input"]]["max"][0] for s in a["samplers"]), 3)) for a in g.get("animations", [])], "scene", [g["nodes"][n]["name"] for n in g["scenes"][0]["nodes"]][:8], "skins", [len(s["joints"]) for s in g.get("skins", [])])

# ---- save, leaving the file as it was found
for o in bpy.context.selected_objects:
    o.select_set(False)
for m, lv in SUBSURF:
    m.levels = lv
for lc in bpy.context.view_layer.layer_collection.children:
    if lc.name == WHO + "_death_fx":
        lc.exclude = True
scn.frame_set(1)
bpy.ops.wm.save_mainfile()
print("SAVED", bpy.data.filepath)

# ---- review strip (not saved)
if WHO in ("grenadier", "scout"):
    print("DONE")
    sys.exit(0)
for m, _ in SUBSURF:
    m.levels = 0
keep_coll = {"rig_artpose", WHO + "_death_fx"} if WHO == "infantry" else {"Collection", WHO + "_death_fx"}
for lc in bpy.context.view_layer.layer_collection.children:
    lc.exclude = lc.name not in keep_coll
ad.action = die
for t in ad.nla_tracks:
    t.mute = True
for o in O:
    if o.type == "CAMERA" or (o.type == "LIGHT" and "Muzzle" not in o.name):
        o.hide_render = True
try:
    scn.render.engine = "CYCLES"
except TypeError as e_:
    print(e_)
scn.cycles.device = "CPU"
scn.cycles.samples = 24
scn.cycles.use_denoising = False
scn.view_settings.view_transform = "Standard"
scn.view_settings.look = "None"
w = bpy.data.worlds.new("w")
w.use_nodes = True
bg = next(n for n in w.node_tree.nodes if n.type == "BACKGROUND")
bg.inputs[0].default_value = (.5, .55, .62, 1)
bg.inputs[1].default_value = .8
scn.world = w
sun = O.new("sun", bpy.data.lights.new("sun", "SUN"))
scn.collection.objects.link(sun)
sun.data.energy = 3
sun.rotation_euler = (math.radians(42), 0, math.radians(35))
me = bpy.data.meshes.new("g")
me.from_pydata([(-20, -20, 0), (20, -20, 0), (20, 20, 0), (-20, 20, 0)], [], [(0, 1, 2, 3)])
g_ob = O.new("g", me)
scn.collection.objects.link(g_ob)
g_m = material("ground", (.42, .36, .25), .9)
me.materials.append(g_m)
cam = O.new("cam", bpy.data.cameras.new("cam"))
scn.collection.objects.link(cam)
scn.camera = cam
cam.data.lens = 40
t_ = Vector((0, 0 if WHO == "scout" else -.3, .55))
cam.location = t_ + Vector((3.3, -3.2, 2.6))
cam.rotation_euler = (cam.location - t_).to_track_quat("Z", "Y").to_euler()
W, H = 460, 380
scn.render.resolution_x, scn.render.resolution_y = W, H
scn.render.resolution_percentage = 100
scn.render.image_settings.file_format = "PNG"
PICK = [4, 9, 13, 18, 26, 34, 42, 60, 88, 97]
strip = np.zeros((H * 2, W * 5, 4), np.float32)
for i, fr in enumerate(PICK):
    scn.frame_set(fr)
    bpy.context.view_layer.update()
    out = os.path.join(SP, "%s_d%02d.png" % (WHO, fr))
    scn.render.filepath = out
    bpy.ops.render.render(write_still=True)
    img = bpy.data.images.load(out)
    px = np.empty(W * H * 4, np.float32)
    img.pixels.foreach_get(px)
    row = 1 if i < 5 else 0
    col_ = i % 5
    strip[row * H:(row + 1) * H, col_ * W:(col_ + 1) * W] = px.reshape(H, W, 4)
res = bpy.data.images.new("strip", W * 5, H * 2, alpha=True)
res.pixels.foreach_set(strip.ravel())
pv = os.path.join(ROOT, "Blender", "Previews", WHO.title())
os.makedirs(pv, exist_ok=True)
res.filepath_raw = os.path.join(pv, "death_strip.png")
res.file_format = "PNG"
res.save()
print("DONE")
