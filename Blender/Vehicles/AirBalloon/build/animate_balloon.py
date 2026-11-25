"""Stage 2 for AirBalloon.blend: NLA clips Rest, Run, Die, and air_balloon_death_fx.

Compatible directly with scripts/components/character_animator.gd!
Run right after build_balloon.py:
  blender AirBalloon.blend --background --python animate_balloon.py
"""

from __future__ import annotations

import random
from math import cos, pi, radians, sin

import bmesh
import bpy
from mathutils import Matrix, Quaternion, Vector as V

FPS = 24
FX_COLL = "air_balloon_death_fx"
random.seed(59)

X = V((1.0, 0.0, 0.0))
Y = V((0.0, 1.0, 0.0))
Z = V((0.0, 0.0, 1.0))
NIL = V((0.001, 0.001, 0.001))
ONE = V((1.0, 1.0, 1.0))

scene = bpy.context.scene
scene.render.fps = FPS
scene.render.fps_base = 1
scene.frame_set(0)

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
    if mat.name.startswith("ab_fx_"):
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


CRATES = ["crate_slot_1", "crate_slot_2", "crate_slot_3", "crate_slot_4"]
STATIC_SUBS = ["envelope_hull", "burner_rig", *CRATES]

# ===========================================================================
# 1. Rest (72 frames / 3.0 s looping — buoyant hover & slow prop idle)
# ===========================================================================
REST_FRAMES = 72
REST_T = REST_FRAMES / FPS

bake(
    OB["airframe_root"],
    "Rest",
    REST_FRAMES,
    lambda t: Tm(Z * (0.09 * sin(2.0 * pi * t / REST_T))) @ HOME["airframe_root"] @ Ry(radians(1.6) * sin(2.0 * pi * t / REST_T)),
)
bake(
    OB["gondola_hull"],
    "Rest",
    REST_FRAMES,
    lambda t: HOME["gondola_hull"] @ Ry(radians(-1.2) * sin(2.0 * pi * t / REST_T - 0.4)),
)
bake(OB["prop_L"], "Rest", REST_FRAMES, lambda t: HOME["prop_L"] @ Ry( 2.0 * pi * (t / REST_T)))
bake(OB["prop_R"], "Rest", REST_FRAMES, lambda t: HOME["prop_R"] @ Ry(-2.0 * pi * (t / REST_T)))
bake(
    OB["burner_flame"],
    "Rest",
    REST_FRAMES,
    lambda t: HOME["burner_flame"] @ Sc((0.92, 0.92, 0.85 + 0.25 * sin(6.0 * pi * t / REST_T))),
)
bake(
    OB["rudder_fin"],
    "Rest",
    REST_FRAMES,
    lambda t: HOME["rudder_fin"] @ Rz(radians(6.5) * sin(2.0 * pi * t / REST_T)),
)
for sname in STATIC_SUBS:
    bake(OB[sname], "Rest", REST_FRAMES, lambda t, n=sname: HOME[n])

# ===========================================================================
# 2. Run (36 frames / 1.5 s looping — forward -Y pitch tilt, fast props, surge)
# ===========================================================================
RUN_FRAMES = 36
RUN_T = RUN_FRAMES / FPS

# Nose down toward -Y around X is Rx(-5.5 deg)? Wait: check right-hand rule around +X:
# Rot_X(+theta) sends +Z to -Y (i.e., top tilts forward toward -Y = nose down forward pitch!).
# Rot_X(+5.5 deg) pitches the balloon top forward (-Y) like an accelerating airship!
bake(
    OB["airframe_root"],
    "Run",
    RUN_FRAMES,
    lambda t: Tm(Z * (0.07 * sin(2.0 * pi * t / RUN_T))) @ HOME["airframe_root"] @ Rx(radians(5.5) + radians(1.2) * sin(2.0 * pi * t / RUN_T)),
)
bake(
    OB["gondola_hull"],
    "Run",
    RUN_FRAMES,
    lambda t: HOME["gondola_hull"] @ Rx(radians(-2.8) + radians(1.0) * cos(2.0 * pi * t / RUN_T)),
)
bake(OB["prop_L"], "Run", RUN_FRAMES, lambda t: HOME["prop_L"] @ Ry( 6.0 * pi * (t / RUN_T)))
bake(OB["prop_R"], "Run", RUN_FRAMES, lambda t: HOME["prop_R"] @ Ry(-6.0 * pi * (t / RUN_T)))
bake(
    OB["burner_flame"],
    "Run",
    RUN_FRAMES,
    lambda t: HOME["burner_flame"] @ Sc((1.15, 1.15, 1.28 + 0.25 * sin(6.0 * pi * t / RUN_T))),
)
bake(
    OB["rudder_fin"],
    "Run",
    RUN_FRAMES,
    lambda t: HOME["rudder_fin"] @ Rz(radians(4.0) * sin(2.0 * pi * t / RUN_T)),
)
for sname in STATIC_SUBS:
    bake(OB[sname], "Run", RUN_FRAMES, lambda t, n=sname: HOME[n])

# ===========================================================================
# 3. Die (56 frames / 2.33 s — envelope crumples, craft banks & plunges out of sky)
# ===========================================================================
DIE_FRAMES = 56


def drop_z(t: float) -> float:
    return -13.5 * ramp(t, 0.35, 2.25)


bake(
    OB["airframe_root"],
    "Die",
    DIE_FRAMES,
    lambda t: Tm(Z * drop_z(t) + X * (0.8 * ramp(t, 0.2, 2.1))) @ HOME["airframe_root"] @ Rx(radians(-36.0) * ramp(t, 0.15, 1.8)) @ Ry(radians(28.0) * ramp(t, 0.10, 1.7)),
)
bake(
    OB["envelope_hull"],
    "Die",
    DIE_FRAMES,
    lambda t: HOME["envelope_hull"] @ Sc((1.0 - 0.55 * ramp(t, 0.08, 1.35), 1.0 - 0.42 * ramp(t, 0.08, 1.35), 1.0 - 0.65 * ramp(t, 0.12, 1.45))),
)
bake(OB["burner_flame"], "Die", DIE_FRAMES, lambda t: hidden("burner_flame") if t > 0.22 else HOME["burner_flame"])
bake(OB["gondola_hull"], "Die", DIE_FRAMES, lambda t: HOME["gondola_hull"] @ Rx(radians(18.0) * ramp(t, 0.2, 1.4)))
for pname in ["prop_L", "prop_R"]:
    bake(OB[pname], "Die", DIE_FRAMES, lambda t, n=pname: HOME[n] @ Ry(2.5 * min(t, 0.4)))
for sname in ["burner_rig", "rudder_fin", *CRATES]:
    bake(OB[sname], "Die", DIE_FRAMES, lambda t, n=sname: HOME[n])

# ===========================================================================
# Companion Death FX Collection (`air_balloon_death_fx`, track `"Death"`)
# ===========================================================================


def fx_mat(name: str, col, rough: float = 0.75, emis=None, strength: float = 0.0) -> bpy.types.Material:
    m = bpy.data.materials.new("ab_fx_" + name)
    m.use_nodes = True
    b = next(n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    b.inputs["Base Color"].default_value = (*col, 1.0)
    b.inputs["Roughness"].default_value = rough
    if emis is not None:
        b.inputs["Emission Color"].default_value = (*emis, 1.0)
        b.inputs["Emission Strength"].default_value = strength
    m.diffuse_color = (*col, 1.0)
    return m


FX_CLOTH = fx_mat("cloth", (0.76, 0.74, 0.64), 0.78)
FX_OAK = fx_mat("oak", (0.24, 0.15, 0.08), 0.75)
FX_FLASH = fx_mat("flash", (1.0, 0.65, 0.20), 0.3, (1.0, 0.60, 0.16), 3.0)
FX_FLAME = fx_mat("flame", (0.98, 0.36, 0.06), 0.4, (1.0, 0.38, 0.05), 2.8)
FX_SMOKE = fx_mat("smoke", (0.14, 0.14, 0.16), 0.95)


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


ME_FLASH = make_fx_mesh("ab_fx_flash", lambda bm: bmesh.ops.create_icosphere(bm, subdivisions=2, radius=1.0), FX_FLASH)
ME_FLAME = make_fx_mesh("ab_fx_flame", lambda bm: bmesh.ops.create_cone(bm, cap_ends=True, segments=6, radius1=0.6, radius2=0.05, depth=1.5), FX_FLAME)
ME_SMOKE = make_fx_mesh("ab_fx_smoke", lambda bm: bmesh.ops.create_icosphere(bm, subdivisions=1, radius=1.0), FX_SMOKE)
ME_CLOTH = make_fx_mesh("ab_fx_cloth", lambda bm: bmesh.ops.create_cube(bm, size=1.0, matrix=Matrix.Diagonal((0.45, 0.9, 0.05, 1))), FX_CLOTH)
ME_OAK = make_fx_mesh("ab_fx_oak", lambda bm: bmesh.ops.create_cube(bm, size=1.0, matrix=Matrix.Diagonal((0.28, 0.8, 0.22, 1))), FX_OAK)

fx_col = bpy.data.collections.new(FX_COLL)
scene.collection.children.link(fx_col)
FX_FRAMES = 64


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
    return 1.0 - ramp(t, 1.65, 2.55)


spawn_fx(
    "Flash_Envelope",
    ME_FLASH,
    FX_FRAMES,
    lambda t: None if t < 0.04 or t > 0.48 else (V((0.0, 0.0, 3.6)), None, 2.1 * sin(pi * (t - 0.04) / 0.44)),
)

for i, off in enumerate([V((0.0, 0.0, 3.4)), V((-0.6, -0.4, 3.6)), V((0.6, 0.5, 3.5))]):
    w, h, fr, ph = rnd(0.35, 0.55), rnd(1.2, 1.8), rnd(10.0, 16.0), rnd(0.0, 6.0)

    def flame_fn(t: float, o=off, ww=w, hh=h, freq=fr, p=ph):
        b = ramp(t, 0.05, 0.30) * (1.0 - ramp(t, 1.0, 2.1))
        if b <= 0.01:
            return None
        return o + Z * (drop_z(t) * 0.45), Quaternion(Y, 0.15 * sin(t * freq + p)), V((ww * b, ww * b, hh * b * (0.8 + 0.2 * sin(t * freq + p))))

    spawn_fx(f"Fire_{i + 1:02d}", ME_FLAME, FX_FRAMES, flame_fn)

for i in range(10):
    ang = rnd(0.0, 2.0 * pi)
    spd = rnd(1.6, 3.8)
    vz = rnd(1.2, 3.5)
    p0 = V((rnd(-0.8, 0.8), rnd(-0.8, 0.8), rnd(2.2, 4.4)))
    spin = V((rnd(-7, 7), rnd(-7, 7), rnd(-7, 7)))
    is_cloth = (i % 3 != 0)

    def deb_fn(t: float, ps=p0, a=ang, sp=spd, v_z=vz, sv=spin):
        if t < 0.08 or t > 2.55:
            return None
        dt = t - 0.08
        z_cur = ps.z + v_z * dt - 4.4 * dt * dt
        p = V((ps.x + cos(a) * sp * dt, ps.y + sin(a) * sp * dt, z_cur))
        return p, Quaternion(sv.normalized(), dt * 5.5), fx_fade(t) * rnd(0.8, 1.1)

    spawn_fx(f"Debris_{i + 1:02d}", ME_CLOTH if is_cloth else ME_OAK, FX_FRAMES, deb_fn)

for i in range(9):
    t_emit = 0.06 + 0.16 * i
    life = 1.60
    src = V((rnd(-0.9, 0.9), rnd(-0.9, 0.9), rnd(3.0, 4.4)))
    drift = V((rnd(-0.5, 0.5), rnd(-0.4, 0.4), rnd(1.8, 3.2)))
    sz = rnd(0.65, 1.15)

    def smoke_fn(t: float, te=t_emit, lf=life, s0=src, dr=drift, s=sz):
        if t < te or t > te + lf or t > 2.60:
            return None
        k = (t - te) / lf
        sc = s * (0.4 + 0.6 * sm(k * 1.8)) * (1.0 - ramp(k, 0.65, 1.0)) * fx_fade(t)
        return s0 + dr * k + Z * (drop_z(t) * 0.2), Quaternion(Z, k * 2.0 + te), sc

    spawn_fx(f"Smoke_{i + 1:02d}", ME_SMOKE, FX_FRAMES, smoke_fn)

lc = bpy.context.view_layer.layer_collection.children
if FX_COLL in lc:
    lc[FX_COLL].exclude = True
scene.frame_start = 0
scene.frame_end = REST_FRAMES
scene.frame_set(0)

bpy.context.preferences.filepaths.save_version = 0
bpy.ops.wm.save_mainfile()
print("ANIMATED AirBalloon.blend clips: Rest, Run, Die + air_balloon_death_fx")
