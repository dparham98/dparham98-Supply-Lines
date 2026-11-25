"""Stage 2 for Keep.blend: NLA clips Idle, Build, Train, LaunchBalloon, Die, and keep_death_fx.

Run right after build_keep.py on the saved file:
  blender Keep.blend --background --python animate_keep.py

Bakes 24 fps per-object NLA tracks starting at frame 0. Die is baked/pushed last so frame 0
stays at the clean finished rest pose (portcullis shut, mooring clamps latched).
"""

from __future__ import annotations

import math
import os
import random
from math import cos, pi, radians, sin

import bmesh
import bpy
from mathutils import Matrix, Quaternion, Vector as V

FPS = 24
FX_COLL = "keep_death_fx"
random.seed(17)

X = V((1.0, 0.0, 0.0))
Y = V((0.0, 1.0, 0.0))
Z = V((0.0, 0.0, 1.0))
NIL = V((0.001, 0.001, 0.001))
ONE = V((1.0, 1.0, 1.0))

scene = bpy.context.scene
scene.render.fps = FPS
scene.render.fps_base = 1
scene.frame_set(0)

# Un-exclude FX collection while cleaning
lc = bpy.context.view_layer.layer_collection.children
if FX_COLL in lc:
    lc[FX_COLL].exclude = False

for ob in list(bpy.data.objects):
    if ob.animation_data:
        ob.animation_data_clear()

old_fx = bpy.data.collections.get(FX_COLL)
if old_fx:
    for ob in list(old_fx.objects):
        bpy.data.objects.remove(ob)
    bpy.data.collections.remove(old_fx)

for act in list(bpy.data.actions):
    bpy.data.actions.remove(act)
for me in list(bpy.data.meshes):
    if me.users == 0:
        bpy.data.meshes.remove(me)
for mat in list(bpy.data.materials):
    if mat.name.startswith("keep_fx_"):
        bpy.data.materials.remove(mat)

bpy.context.view_layer.update()
OB = bpy.data.objects
HOME = {
    o.name: Matrix.LocRotScale(o.matrix_basis.to_translation(), o.matrix_basis.to_quaternion(), V((1.0, 1.0, 1.0)))
    for o in OB
}


def sm(x: float) -> float:
    x = max(0.0, min(1.0, x))
    return x * x * (3.0 - 2.0 * x)


def ramp(t: float, a: float, b: float) -> float:
    return sm((t - a) / max(1e-6, b - a))


def lin(t: float, a: float, b: float) -> float:
    return max(0.0, min(1.0, (t - a) / max(1e-6, b - a)))


def rnd(a: float, b: float) -> float:
    return random.uniform(a, b)


def Tm(v) -> Matrix:
    return Matrix.Translation(V(v))


def Rx(a: float) -> Matrix:
    return Matrix.Rotation(a, 4, "X")


def Ry(a: float) -> Matrix:
    return Matrix.Rotation(a, 4, "Y")


def Rz(a: float) -> Matrix:
    return Matrix.Rotation(a, 4, "Z")


def R_axis(axis: V, a: float) -> Matrix:
    return Matrix.Rotation(a, 4, axis.normalized())


def Sc(v) -> Matrix:
    vv = V(v)
    return Matrix.Diagonal((vv.x, vv.y, vv.z, 1.0))


def push(ob: bpy.types.Object, clip: str) -> None:
    ad = ob.animation_data
    act = ad.action
    act.name = f"{clip}_{ob.name}"
    track = ad.nla_tracks.new()
    track.name = clip
    strip = track.strips.new(clip, 0, act)
    strip.name = clip
    ad.action = None


def bake(ob: bpy.types.Object, clip: str, frames: int, fn) -> None:
    """Bake parent-space Matrix fn(t_sec) cleanly at every frame 0..frames into NLA track."""
    ob.rotation_mode = "QUATERNION"
    rest = ob.matrix_basis.copy()
    prev = None
    for f in range(frames + 1):
        loc, q, sc = fn(f / FPS).decompose()
        sc = V((max(sc.x, 0.001), max(sc.y, 0.001), max(sc.z, 0.001)))
        if prev is not None and prev.dot(q) < 0.0:
            q.negate()
        prev = q.copy()
        ob.location, ob.rotation_quaternion, ob.scale = loc, q, sc
        ob.keyframe_insert("location", frame=f)
        ob.keyframe_insert("rotation_quaternion", frame=f)
        ob.keyframe_insert("scale", frame=f)
    push(ob, clip)
    ob.matrix_basis = rest


def hidden(name: str) -> Matrix:
    return Tm(HOME[name].translation) @ Sc(NIL)


TOWERS = ["corner_tower_FL", "corner_tower_FR", "corner_tower_BL", "corner_tower_BR"]
BANNERS = ["banner_front_L", "banner_front_R", "banner_side_L", "banner_side_R"]
CLAMPS = [f"mooring_clamp_{i:02d}" for i in range(1, 5)]
BEACONS = [f"pad_beacon_{i:02d}" for i in range(1, 5)]

# ===========================================================================
# 1. Idle (96 frames / 4.0 s looping)
# ===========================================================================
IDLE_FRAMES = 96
IDLE_T = IDLE_FRAMES / FPS

for idx, bname in enumerate(BANNERS):
    axis = X if "front" in bname else Y
    phase = idx * 0.85
    bake(
        OB[bname],
        "Idle",
        IDLE_FRAMES,
        lambda t, ax=axis, ph=phase, n=bname: HOME[n] @ R_axis(ax, radians(2.8) * sin(2.0 * pi * t / IDLE_T + ph)),
    )

bake(
    OB["bay_lantern"],
    "Idle",
    IDLE_FRAMES,
    lambda t: HOME["bay_lantern"] @ Ry(radians(3.5) * sin(2.0 * pi * t / IDLE_T)),
)
bake(
    OB["gate_hearth_glow"],
    "Idle",
    IDLE_FRAMES,
    lambda t: HOME["gate_hearth_glow"] @ Sc(ONE * (0.96 + 0.06 * sin(4.0 * pi * t / IDLE_T))),
)
for idx, bname in enumerate(BEACONS):
    ph = idx * (pi * 0.5)
    bake(
        OB[bname],
        "Idle",
        IDLE_FRAMES,
        lambda t, p=ph, n=bname: HOME[n] @ Sc(ONE * (0.94 + 0.08 * sin(2.0 * pi * t / IDLE_T + p))),
    )
# Reset gates, clamps, and all static structural parts explicitly in Idle
STATIC_PARTS = ["plinth", "bastion_walls", "gatehouse_frame", "receiving_bay", "roof", "balloon_pad", "portcullis"] + TOWERS + CLAMPS
for sname in STATIC_PARTS:
    bake(OB[sname], "Idle", IDLE_FRAMES, lambda t, n=sname: HOME[n])

# ===========================================================================
# 2. Build (240 frames / 10.0 s scrubbed by construction progress)
# ===========================================================================
BUILD_FRAMES = 240
BUILD_T = BUILD_FRAMES / FPS


def grow_z(name: str, a: float, b: float):
    def fn(t: float) -> Matrix:
        k = lin(t / BUILD_T, a, b)
        if k <= 0.0:
            return hidden(name)
        return HOME[name] @ Sc((1.0, 1.0, sm(k)))
    return fn


def pop_in(name: str, a: float, b: float):
    def fn(t: float) -> Matrix:
        k = lin(t / BUILD_T, a, b)
        if k <= 0.0:
            return hidden(name)
        s = 1.0 + 0.10 * sin(pi * k) * (1.0 - k) if k > 0.65 else sm(k / 0.65) * 1.05
        return HOME[name] @ Sc(ONE * s)
    return fn


def lower_part(name: str, a_scale: float, b_scale: float, b_land: float, drop_z: float):
    def fn(t: float) -> Matrix:
        p = t / BUILD_T
        k = lin(p, a_scale, b_scale)
        if k <= 0.0:
            return hidden(name)
        d = 1.0 - ramp(p, b_scale, b_land)
        return Tm(Z * (drop_z * d)) @ HOME[name] @ Sc(ONE * sm(k))
    return fn


bake(OB["plinth"], "Build", BUILD_FRAMES, grow_z("plinth", 0.00, 0.12))
for idx, tname in enumerate(TOWERS):
    a = 0.08 + 0.03 * idx
    bake(OB[tname], "Build", BUILD_FRAMES, grow_z(tname, a, a + 0.24))
bake(OB["bastion_walls"], "Build", BUILD_FRAMES, grow_z("bastion_walls", 0.18, 0.46))
bake(OB["gatehouse_frame"], "Build", BUILD_FRAMES, grow_z("gatehouse_frame", 0.28, 0.54))
bake(OB["receiving_bay"], "Build", BUILD_FRAMES, grow_z("receiving_bay", 0.42, 0.64))
bake(OB["bay_lantern"], "Build", BUILD_FRAMES, pop_in("bay_lantern", 0.62, 0.74))
bake(OB["roof"], "Build", BUILD_FRAMES, lower_part("roof", 0.50, 0.58, 0.68, 0.38))
bake(OB["balloon_pad"], "Build", BUILD_FRAMES, lower_part("balloon_pad", 0.64, 0.72, 0.82, 0.28))
for idx, cname in enumerate(CLAMPS):
    bake(OB[cname], "Build", BUILD_FRAMES, pop_in(cname, 0.78 + 0.02 * idx, 0.88 + 0.02 * idx))
for idx, bname in enumerate(BEACONS):
    bake(OB[bname], "Build", BUILD_FRAMES, pop_in(bname, 0.80 + 0.02 * idx, 0.90 + 0.02 * idx))
bake(OB["gate_hearth_glow"], "Build", BUILD_FRAMES, pop_in("gate_hearth_glow", 0.78, 0.90))
bake(
    OB["portcullis"],
    "Build",
    BUILD_FRAMES,
    lambda t: hidden("portcullis")
    if lin(t / BUILD_T, 0.80, 0.95) <= 0.0
    else Tm(Z * (1.2 * (1.0 - ramp(t / BUILD_T, 0.82, 0.95)))) @ HOME["portcullis"] @ Sc((1.0, sm(lin(t / BUILD_T, 0.80, 0.86)), 1.0)),
)
for idx, bname in enumerate(BANNERS):
    bake(OB[bname], "Build", BUILD_FRAMES, pop_in(bname, 0.86 + 0.015 * idx, 0.98))

# ===========================================================================
# 3. Train (120 frames / 5.0 s: hearth brightens, portcullis opens & closes)
# ===========================================================================
TRAIN_FRAMES = 120


def portcullis_train(t: float) -> Matrix:
    lift = ramp(t, 1.2, 2.1) * (1.0 - ramp(t, 3.8, 4.7))
    # Retract smoothly +1.48 m upward and telescope to 0.42 Z so top bar stays strictly behind 4.54 m pocket
    return Tm(Z * (1.48 * lift)) @ HOME["portcullis"] @ Sc((1.0, 1.0, 1.0 - 0.58 * lift))


def hearth_train(t: float) -> Matrix:
    flare = ramp(t, 0.1, 1.3) * (1.0 - ramp(t, 3.9, 4.9))
    return HOME["gate_hearth_glow"] @ Sc(ONE * (1.0 + 0.18 * flare))


bake(OB["portcullis"], "Train", TRAIN_FRAMES, portcullis_train)
bake(OB["gate_hearth_glow"], "Train", TRAIN_FRAMES, hearth_train)

# ===========================================================================
# 4. LaunchBalloon (96 frames / 4.0 s: beacons sequence, 4 clamps hinge open)
# ===========================================================================
LAUNCH_FRAMES = 96

for idx, (cname, deg) in enumerate(zip(CLAMPS, (45.0, 135.0, 225.0, 315.0))):
    a = radians(deg)
    tan = V((-sin(a), cos(a), 0.0))

    def clamp_open(t: float, ax=tan, n=cname, delay=0.05 * idx) -> Matrix:
        op = ramp(t, 0.45 + delay, 1.25 + delay) * (1.0 - ramp(t, 2.75, 3.65))
        return HOME[n] @ R_axis(ax, radians(96.0) * op)

    bake(OB[cname], "LaunchBalloon", LAUNCH_FRAMES, clamp_open)

for idx, bname in enumerate(BEACONS):
    def beacon_launch(t: float, n=bname, delay=0.10 * idx) -> Matrix:
        pulse = ramp(t, 0.05 + delay, 0.40 + delay) * (1.0 - ramp(t, 2.8, 3.8))
        return HOME[n] @ Sc(ONE * (1.0 + 0.35 * pulse))
    bake(OB[bname], "LaunchBalloon", LAUNCH_FRAMES, beacon_launch)

# ===========================================================================
# 5. Die (132 frames / 5.5 s) + keep_death_fx (pushed LAST!)
# ===========================================================================
DIE_FRAMES = 132
SINK0, SINK1 = 3.95, 5.45
SINK_D = 8.4


def sink_dz(t: float) -> float:
    return -SINK_D * ramp(t, SINK0, SINK1)


def wreck_pose(name: str, t0: float, t1: float, d_loc: V, d_rot: Matrix, pivot_top_tilt: bool = False):
    def fn(t: float) -> Matrix:
        k = ramp(t, t0, t1)
        dz = sink_dz(t)
        return Tm(d_loc * k + Z * dz) @ HOME[name] @ (Matrix.Identity(4).lerp(d_rot, k))
    return fn


# Plinth fractures subtly down with sink
bake(OB["plinth"], "Die", DIE_FRAMES, lambda t: Tm(Z * (sink_dz(t) - 0.12 * ramp(t, 0.3, 1.2))) @ HOME["plinth"])

# Rooftop pad caves inward, clamps/beacons pop outward
bake(
    OB["balloon_pad"],
    "Die",
    DIE_FRAMES,
    wreck_pose("balloon_pad", 0.15, 0.95, V((0.25, -0.18, -1.65)), Rx(radians(18.0)) @ Ry(radians(-12.0))),
)
for idx, (cname, deg) in enumerate(zip(CLAMPS, (45.0, 135.0, 225.0, 315.0))):
    a = radians(deg)
    rad = V((cos(a), sin(a), 0.0))
    bake(
        OB[cname],
        "Die",
        DIE_FRAMES,
        wreck_pose(cname, 0.10, 0.80, rad * 0.45 + Z * 0.20, Rz(radians(28.0 * (-1 if idx % 2 else 1)))),
    )
for bname in BEACONS:
    bake(OB[bname], "Die", DIE_FRAMES, lambda t, n=bname: hidden(n) if t > 0.28 else HOME[n])

# Roof slopes buckle downward into the courtyard
bake(
    OB["roof"],
    "Die",
    DIE_FRAMES,
    wreck_pose("roof", 0.25, 1.15, V((-0.18, 0.12, -1.35)), Rx(radians(-10.0)) @ Ry(radians(8.0))),
)

# Corner towers cant outward around their base Z = 0 pivots
tower_tilts = {
    "corner_tower_FL": Rx(radians(-22.0)) @ Ry(radians(-18.0)),
    "corner_tower_FR": Rx(radians(-18.0)) @ Ry(radians( 24.0)),
    "corner_tower_BL": Rx(radians( 20.0)) @ Ry(radians(-16.0)),
    "corner_tower_BR": Rx(radians( 16.0)) @ Ry(radians( 22.0)),
}
for idx, tname in enumerate(TOWERS):
    t0 = 0.45 + 0.12 * idx
    bake(OB[tname], "Die", DIE_FRAMES, wreck_pose(tname, t0, t0 + 0.95, V((0.0, 0.0, -0.20)), tower_tilts[tname]))

# Curtain walls slump down slightly & cant
bake(OB["bastion_walls"], "Die", DIE_FRAMES, wreck_pose("bastion_walls", 0.40, 1.35, V((0.0, 0.0, -0.38)), Rx(radians(-4.5))))
bake(OB["gatehouse_frame"], "Die", DIE_FRAMES, wreck_pose("gatehouse_frame", 0.35, 1.25, V((0.0, -0.22, -0.30)), Rx(radians(-12.0))))
bake(OB["portcullis"], "Die", DIE_FRAMES, wreck_pose("portcullis", 0.18, 0.95, V((0.10, -0.55, -2.10)), Rx(radians(-68.0)) @ Rz(radians(10.0))))
bake(OB["gate_hearth_glow"], "Die", DIE_FRAMES, lambda t: hidden("gate_hearth_glow") if t > 0.45 else HOME["gate_hearth_glow"])

# Receiving bay collapses & lantern falls
bake(OB["receiving_bay"], "Die", DIE_FRAMES, wreck_pose("receiving_bay", 0.50, 1.40, V((-0.25, 0.0, -0.45)), Ry(radians(-24.0))))
bake(OB["bay_lantern"], "Die", DIE_FRAMES, wreck_pose("bay_lantern", 0.30, 0.95, V((-0.30, 0.15, -1.85)), Rx(radians(78.0))))

# Banners tear loose and hang/sink
for idx, bname in enumerate(BANNERS):
    bake(OB[bname], "Die", DIE_FRAMES, wreck_pose(bname, 0.35, 1.10, V((0.0, -0.15 if "front" in bname else 0.0, -1.10)), Rx(radians(35.0 if idx % 2 else -30.0))))


# ===========================================================================
# Companion Death FX Collection (`keep_death_fx`, track `"Death"`)
# ===========================================================================


def fx_mat(name: str, col, rough: float = 0.75, emis=None, strength: float = 0.0) -> bpy.types.Material:
    m = bpy.data.materials.new("keep_fx_" + name)
    m.use_nodes = True
    b = next(n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    b.inputs["Base Color"].default_value = (*col, 1.0)
    b.inputs["Roughness"].default_value = rough
    if emis is not None:
        b.inputs["Emission Color"].default_value = (*emis, 1.0)
        b.inputs["Emission Strength"].default_value = strength
    m.diffuse_color = (*col, 1.0)
    return m


FX_DUST = fx_mat("dust", (0.45, 0.42, 0.36), 0.92)
FX_ENAMEL = fx_mat("enamel", (0.48, 0.42, 0.35), 0.45)
FX_TIMBER = fx_mat("timber", (0.31, 0.16, 0.065), 0.68)
FX_FLASH = fx_mat("flash", (1.0, 0.62, 0.18), 0.3, (1.0, 0.58, 0.15), 2.8)
FX_FLAME = fx_mat("flame", (0.95, 0.32, 0.05), 0.4, (1.0, 0.34, 0.04), 2.5)
FX_SMOKE = fx_mat("smoke", (0.14, 0.14, 0.16), 0.95)
FX_SCORCH = fx_mat("scorch", (0.025, 0.025, 0.028), 0.95)


def make_fx_mesh(name: str, bm_fn, mat: bpy.types.Material) -> bpy.types.Mesh:
    bm = bmesh.new()
    bm_fn(bm)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    for fc in bm.faces:
        fc.smooth = False
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    me.materials.append(mat)
    return me


ME_ICO = make_fx_mesh("fx_ico", lambda bm: bmesh.ops.create_icosphere(bm, subdivisions=1, radius=1.0), FX_DUST)
ME_ENAMEL = make_fx_mesh("fx_enamel", lambda bm: bmesh.ops.create_cube(bm, size=1.0, matrix=Matrix.Diagonal((1.3, 0.23, 0.93, 1))), FX_ENAMEL)
ME_TIMBER = make_fx_mesh("fx_timber", lambda bm: bmesh.ops.create_cube(bm, size=1.0, matrix=Matrix.Diagonal((0.35, 1.2, 0.25, 1))), FX_TIMBER)
ME_FLASH = make_fx_mesh("fx_flash", lambda bm: bmesh.ops.create_icosphere(bm, subdivisions=2, radius=1.0), FX_FLASH)
ME_FLAME = make_fx_mesh("fx_flame", lambda bm: bmesh.ops.create_cone(bm, cap_ends=True, segments=6, radius1=0.6, radius2=0.04, depth=1.6), FX_FLAME)
ME_SMOKE = make_fx_mesh("fx_smoke", lambda bm: bmesh.ops.create_icosphere(bm, subdivisions=1, radius=1.0), FX_SMOKE)
ME_SCORCH = make_fx_mesh("fx_scorch", lambda bm: bmesh.ops.create_cone(bm, cap_ends=True, segments=16, radius1=1.0, radius2=1.0, depth=0.04), FX_SCORCH)

fx_col = bpy.data.collections.new(FX_COLL)
scene.collection.children.link(fx_col)


def spawn_fx(name: str, mesh: bpy.types.Mesh, frames: int, fn) -> None:
    ob = bpy.data.objects.new(name, mesh)
    fx_col.objects.link(ob)
    ob.rotation_mode = "QUATERNION"
    prev = None
    for f in range(frames + 1):
        res = fn(f / FPS)
        if res is None:
            loc, q, sc = V((0.0, 0.0, -5.0)), Quaternion(), NIL
        else:
            loc, q, sc = res
            q = q or Quaternion()
            sc = V((max(sc.x, 0.001), max(sc.y, 0.001), max(sc.z, 0.001))) if isinstance(sc, V) else V((max(sc, 0.001),) * 3)
        if prev is not None and prev.dot(q) < 0.0:
            q.negate()
        prev = q.copy()
        ob.location, ob.rotation_quaternion, ob.scale = loc, q, sc
        ob.keyframe_insert("location", frame=f)
        ob.keyframe_insert("rotation_quaternion", frame=f)
        ob.keyframe_insert("scale", frame=f)
    push(ob, "Death")
    ob.location, ob.scale = V((0.0, 0.0, 0.0)), ONE


def fx_fade(t: float) -> float:
    return 1.0 - ramp(t, 4.1, 5.3)


# Rooftop & Gatehouse Initial Flash
spawn_fx(
    "Flash_Crown",
    ME_FLASH,
    DIE_FRAMES,
    lambda t: None
    if t < 0.10 or t > 0.65
    else (V((0.0, 0.0, 6.2)), None, 2.8 * sin(pi * (t - 0.10) / 0.55)),
)

# Ground Scorch Patch
spawn_fx(
    "Scorch_Ring",
    ME_SCORCH,
    DIE_FRAMES,
    lambda t: None if t < 0.2 else (V((0.0, 0.0, 0.02)), None, V((4.2 * ramp(t, 0.2, 1.4) * fx_fade(t), 4.2 * ramp(t, 0.2, 1.4) * fx_fade(t), 1.0))),
)

# Expanding Ground Dust Ring strictly around outer fortress perimeter (R = 4.6..6.8 m)
for i in range(12):
    ang = 2.0 * pi * i / 12.0 + rnd(-0.15, 0.15)
    d = V((cos(ang), sin(ang), 0.0))
    sz = rnd(0.85, 1.35)

    def dust_fn(t: float, dv=d, s=sz):
        if t < 0.40 or t > 2.40:
            return None
        k = (t - 0.40) / 2.00
        return V((0.0, 0.0, 0.40)) + dv * (4.6 + 2.4 * sm(k)) + Z * (1.1 * k), None, s * sm(k * 3.5) * (1.0 - ramp(k, 0.4, 1.0))

    spawn_fx(f"Dust_{i + 1:02d}", ME_ICO, DIE_FRAMES, dust_fn)

# Flying Enamel & Timber Debris settling onto Z ~ 0.15..0.25 and sinking cleanly
for i in range(14):
    ang = rnd(0.0, 2.0 * pi)
    spd = rnd(2.2, 4.8)
    vz = rnd(4.0, 7.5)
    t_land = rnd(0.85, 1.35)
    p0 = V((rnd(-1.6, 1.6), rnd(-1.6, 1.6), rnd(3.2, 5.8)))
    dim = V((rnd(0.28, 0.52), rnd(0.25, 0.48), rnd(0.22, 0.40)))
    is_wood = i % 2 == 1
    spin = V((rnd(-6, 6), rnd(-6, 6), rnd(-6, 6)))

    def debris_fn(t: float, p_start=p0, a=ang, sp=spd, v_z=vz, tl=t_land, dm=dim, sv=spin):
        if t < 0.20:
            return None
        dt = min(t - 0.20, tl)
        z_cur = max(0.18, p_start.z + v_z * dt - 4.9 * dt * dt)
        p = V((p_start.x + cos(a) * sp * dt, p_start.y + sin(a) * sp * dt, z_cur))
        rot = Quaternion(sv.normalized(), dt * 5.0)
        return p + Z * sink_dz(t), rot, dm * fx_fade(t)

    spawn_fx(f"Debris_{i + 1:02d}", ME_TIMBER if is_wood else ME_ENAMEL, DIE_FRAMES, debris_fn)

# Flames roaring from the caved-in rooftop crater, open gatehouse throat, and collapsed receiving bay
fire_spots = [
    V((0.0, 0.0, 4.6)),
    V((-0.8, 0.6, 4.4)),
    V((0.8, -0.5, 4.4)),
    V((0.0, -3.6, 0.9)),
    V((-0.6, -3.2, 0.8)),
    V((-4.1, -0.4, 0.8)),
    V((0.4, 0.8, 4.5)),
]
for i, off in enumerate(fire_spots):
    w, h, freq, ph = rnd(0.38, 0.62), rnd(1.5, 2.3), rnd(12.0, 20.0), rnd(0.0, 6.0)

    def flame_fn(t: float, o=off, ww=w, hh=h, fr=freq, p=ph):
        b = ramp(t, 0.20, 0.65) * fx_fade(t)
        if b <= 0.01:
            return None
        lick = 0.75 + 0.25 * sin(t * fr + p)
        return o + Z * sink_dz(t), Quaternion(Y, 0.12 * sin(t * fr * 0.5 + p)), V((ww * b, ww * b, hh * b * lick))

    spawn_fx(f"Fire_{i + 1:02d}", ME_FLAME, DIE_FRAMES, flame_fn)

# Smoke Plumes Billowing from Breached Crown & Clearing
for i in range(14):
    t_emit = 0.25 + 0.20 * i
    life = 2.00
    src = V((rnd(-1.5, 1.5), rnd(-1.5, 1.5), rnd(4.4, 5.6)))
    drift = V((rnd(-0.6, 0.7), rnd(-0.5, 0.5), rnd(3.2, 4.6)))
    sz = rnd(0.85, 1.35)

    def smoke_fn(t: float, te=t_emit, lf=life, s0=src, dr=drift, s=sz):
        if t < te or t > te + lf or t > 5.35:
            return None
        k = (t - te) / lf
        sc = s * (0.35 + 0.65 * sm(k * 1.8)) * (1.0 - ramp(k, 0.65, 1.0)) * fx_fade(t)
        return s0 + dr * k + Z * sink_dz(t) * 0.25, Quaternion(Z, k * 2.2 + te), sc

    spawn_fx(f"Smoke_{i + 1:02d}", ME_SMOKE, DIE_FRAMES, smoke_fn)

# Exclude FX collection from main view layer & reset to clean rest frame 0
lc = bpy.context.view_layer.layer_collection.children
if FX_COLL in lc:
    lc[FX_COLL].exclude = True
scene.frame_start = 0
scene.frame_end = IDLE_FRAMES
for ob in bpy.data.collections["keep"].all_objects:
    if ob.animation_data:
        for track in ob.animation_data.nla_tracks:
            track.mute = track.name != "Idle"
scene.frame_set(0)

bpy.context.preferences.filepaths.save_version = 0
bpy.ops.wm.save_mainfile()
print("ANIMATED Keep.blend clips: Idle, Build, Train, LaunchBalloon, Die + keep_death_fx")
