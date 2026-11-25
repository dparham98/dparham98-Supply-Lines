"""Stage 2 for Farm.blend: NLA clips Idle, Work, Depleted, Build, Die, and farm_death_fx.

Compatible directly with scripts/components/mine_rig.gd!
Run right after build_farm.py on the saved file:
  blender Farm.blend --background --python animate_farm.py
"""

from __future__ import annotations

import random
from math import cos, pi, radians, sin

import bmesh
import bpy
from mathutils import Matrix, Quaternion, Vector as V

FPS = 24
FX_COLL = "farm_death_fx"
random.seed(43)

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
    if mat.name.startswith("fm_fx_"):
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


CROPS = ["crop_row_1", "crop_row_2", "crop_row_3"]
STATIC_PARTS = ["curb_base", "granary_barn", "crop_stubble", "harvest_bin", "harvest_sacks", "grain_riddle"]

# ===========================================================================
# 1. Idle (96 frames / 4.0 s looping — gentle windmill turn + crop sway)
# ===========================================================================
IDLE_FRAMES = 96
IDLE_T = IDLE_FRAMES / FPS

bake(
    OB["windmill_rotor"],
    "Idle",
    IDLE_FRAMES,
    lambda t: HOME["windmill_rotor"] @ Ry(-2.0 * pi * (t / IDLE_T)),
)
bake(
    OB["farm_pennant"],
    "Idle",
    IDLE_FRAMES,
    lambda t: HOME["farm_pennant"] @ Rz(radians(9.0) * sin(2.0 * pi * t / IDLE_T)),
)
for idx, cname in enumerate(CROPS):
    ph = idx * 0.9
    bake(
        OB[cname],
        "Idle",
        IDLE_FRAMES,
        lambda t, p=ph, n=cname: HOME[n] @ Ry(radians(2.2) * sin(2.0 * pi * t / IDLE_T + p)),
    )
for sname in STATIC_PARTS:
    bake(OB[sname], "Idle", IDLE_FRAMES, lambda t, n=sname: HOME[n])

# ===========================================================================
# 2. Work (48 frames / 2.0 s looping — brisk harvest spin + lively sacks/crops)
# ===========================================================================
WORK_FRAMES = 48
WORK_T = WORK_FRAMES / FPS

bake(
    OB["windmill_rotor"],
    "Work",
    WORK_FRAMES,
    lambda t: HOME["windmill_rotor"] @ Ry(-2.0 * pi * (t / WORK_T)),
)
bake(
    OB["farm_pennant"],
    "Work",
    WORK_FRAMES,
    lambda t: HOME["farm_pennant"] @ Rz(radians(14.0) * sin(4.0 * pi * t / WORK_T)),
)
for idx, cname in enumerate(CROPS):
    ph = idx * 1.1
    bake(
        OB[cname],
        "Work",
        WORK_FRAMES,
        lambda t, p=ph, n=cname: HOME[n] @ Ry(radians(4.0) * sin(4.0 * pi * t / WORK_T + p)),
    )
bake(
    OB["grain_riddle"],
    "Work",
    WORK_FRAMES,
    lambda t: HOME["grain_riddle"] @ Rx(radians(4.0) * sin(8*pi*t/WORK_T)),
)
for sname in ["curb_base", "granary_barn", "crop_stubble", "harvest_bin"]:
    bake(OB[sname], "Work", WORK_FRAMES, lambda t, n=sname: HOME[n])
bake(OB["harvest_sacks"], "Work", WORK_FRAMES, lambda t: HOME["harvest_sacks"])

# ===========================================================================
# 3. Depleted (48 frames / 2.0 s looping — wheat harvested cleanly to stubble)
# ===========================================================================
DEP_FRAMES = 48
DEP_T = DEP_FRAMES / FPS

for cname in CROPS:
    bake(OB[cname], "Depleted", DEP_FRAMES, lambda t, n=cname: hidden(n))
bake(OB["harvest_sacks"], "Depleted", DEP_FRAMES, lambda t: hidden("harvest_sacks"))
bake(
    OB["windmill_rotor"],
    "Depleted",
    DEP_FRAMES,
    lambda t: HOME["windmill_rotor"] @ Ry(radians(2.5) * sin(2.0 * pi * t / DEP_T)),
)
bake(
    OB["farm_pennant"],
    "Depleted",
    DEP_FRAMES,
    lambda t: HOME["farm_pennant"] @ Rz(radians(5.0) * sin(2.0 * pi * t / DEP_T)),
)
for sname in ["curb_base", "granary_barn", "crop_stubble", "harvest_bin"]:
    bake(OB[sname], "Depleted", DEP_FRAMES, lambda t, n=sname: HOME[n])
bake(OB["grain_riddle"], "Depleted", DEP_FRAMES, lambda t: HOME["grain_riddle"])

# ===========================================================================
# 4. Build (96 frames / 4.0 s scrubbed by construction progress)
# ===========================================================================
BUILD_FRAMES = 96
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
        s = 1.0 + 0.08 * sin(pi * k) * (1.0 - k) if k > 0.65 else sm(k / 0.65) * 1.04
        return HOME[name] @ Sc(ONE * s)
    return fn


bake(OB["curb_base"], "Build", BUILD_FRAMES, grow_z("curb_base", 0.00, 0.20))
bake(OB["granary_barn"], "Build", BUILD_FRAMES, grow_z("granary_barn", 0.16, 0.56))
bake(OB["harvest_bin"], "Build", BUILD_FRAMES, grow_z("harvest_bin", 0.34, 0.62))
bake(OB["grain_riddle"], "Build", BUILD_FRAMES, pop_in("grain_riddle", 0.57, 0.72))
bake(OB["windmill_rotor"], "Build", BUILD_FRAMES, pop_in("windmill_rotor", 0.52, 0.76))
bake(OB["farm_pennant"], "Build", BUILD_FRAMES, pop_in("farm_pennant", 0.60, 0.80))
bake(OB["crop_stubble"], "Build", BUILD_FRAMES, grow_z("crop_stubble", 0.45, 0.72))
for idx, cname in enumerate(CROPS):
    bake(OB[cname], "Build", BUILD_FRAMES, grow_z(cname, 0.66 + 0.04 * idx, 0.96))
bake(OB["harvest_sacks"], "Build", BUILD_FRAMES, pop_in("harvest_sacks", 0.78, 0.98))

# ===========================================================================
# 5. Die (60 frames / 2.5 s) + farm_death_fx
# ===========================================================================
DIE_FRAMES = 60
SINK0, SINK1 = 1.65, 2.46
SINK_D = 5.4


def sink_dz(t: float) -> float:
    return -SINK_D * ramp(t, SINK0, SINK1)


def wreck(name: str, t0: float, t1: float, d_loc: V, d_rot: Matrix):
    def fn(t: float) -> Matrix:
        k = ramp(t, t0, t1)
        return Tm(d_loc * k + Z * sink_dz(t)) @ HOME[name] @ (Matrix.Identity(4).lerp(d_rot, k))
    return fn


bake(OB["curb_base"], "Die", DIE_FRAMES, lambda t: Tm(Z * (sink_dz(t) - 0.08 * ramp(t, 0.2, 1.0))) @ HOME["curb_base"])
bake(OB["granary_barn"], "Die", DIE_FRAMES, wreck("granary_barn", 0.18, 1.05, V((0.10, 0.06, -0.42)), Rx(radians(-14.0)) @ Ry(radians(12.0))))
bake(OB["windmill_rotor"], "Die", DIE_FRAMES, wreck("windmill_rotor", 0.08, 0.85, V((-0.35, -0.85, -1.95)), Rx(radians(-62.0)) @ Rz(radians(28.0))))
bake(OB["farm_pennant"], "Die", DIE_FRAMES, wreck("farm_pennant", 0.12, 0.75, V((0.20, 0.15, -1.20)), Rx(radians(45.0))))
bake(OB["harvest_bin"], "Die", DIE_FRAMES, wreck("harvest_bin", 0.22, 0.95, V((-0.12, -0.18, -0.15)), Rx(radians(-18.0)) @ Ry(radians(-15.0))))
bake(OB["harvest_sacks"], "Die", DIE_FRAMES, wreck("harvest_sacks", 0.18, 0.80, V((-0.18, -0.25, -0.20)), Rx(radians(-30.0))))
bake(OB["grain_riddle"], "Die", DIE_FRAMES, wreck("grain_riddle", 0.18, 0.9, V((.08,-.02,-.58)), Ry(radians(18.0))))
bake(OB["crop_stubble"], "Die", DIE_FRAMES, lambda t: Tm(Z * sink_dz(t)) @ HOME["crop_stubble"])
for idx, cname in enumerate(CROPS):
    bake(OB[cname], "Die", DIE_FRAMES, lambda t, n=cname, i=idx: Tm(Z * sink_dz(t)) @ HOME[n] @ Sc((1.0, 1.0, 1.0 - 0.85 * ramp(t, 0.10 + 0.05 * i, 0.65))))

# ===========================================================================
# Companion Death FX Collection (`farm_death_fx`, track `"Death"`)
# ===========================================================================


def fx_mat(name: str, col, rough: float = 0.75, emis=None, strength: float = 0.0) -> bpy.types.Material:
    m = bpy.data.materials.new("fm_fx_" + name)
    m.use_nodes = True
    b = next(n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    b.inputs["Base Color"].default_value = (*col, 1.0)
    b.inputs["Roughness"].default_value = rough
    if emis is not None:
        b.inputs["Emission Color"].default_value = (*emis, 1.0)
        b.inputs["Emission Strength"].default_value = strength
    m.diffuse_color = (*col, 1.0)
    return m


FX_CHAFF = fx_mat("chaff", (0.76, 0.56, 0.16), 0.85)
FX_OAK = fx_mat("oak", (0.24, 0.15, 0.08), 0.75)
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


ME_CHAFF = make_fx_mesh("fm_fx_chaff", lambda bm: bmesh.ops.create_icosphere(bm, subdivisions=1, radius=1.0), FX_CHAFF)
ME_OAK = make_fx_mesh("fm_fx_oak", lambda bm: bmesh.ops.create_cube(bm, size=1.0, matrix=Matrix.Diagonal((0.35, 1.1, 0.25, 1))), FX_OAK)
ME_FLASH = make_fx_mesh("fm_fx_flash", lambda bm: bmesh.ops.create_icosphere(bm, subdivisions=2, radius=1.0), FX_FLASH)
ME_FLAME = make_fx_mesh("fm_fx_flame", lambda bm: bmesh.ops.create_cone(bm, cap_ends=True, segments=6, radius1=0.45, radius2=0.04, depth=1.2), FX_FLAME)
ME_SMOKE = make_fx_mesh("fm_fx_smoke", lambda bm: bmesh.ops.create_icosphere(bm, subdivisions=1, radius=1.0), FX_SMOKE)
ME_SCORCH = make_fx_mesh("fm_fx_scorch", lambda bm: bmesh.ops.create_cone(bm, cap_ends=True, segments=14, radius1=1.0, radius2=1.0, depth=0.04), FX_SCORCH)

fx_col = bpy.data.collections.new(FX_COLL)
scene.collection.children.link(fx_col)
FX_FRAMES = 68


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
    return 1.0 - ramp(t, 1.85, 2.75)


spawn_fx(
    "Flash_Barn",
    ME_FLASH,
    FX_FRAMES,
    lambda t: None if t < 0.06 or t > 0.50 else (V((-0.6, 0.7, 2.4)), None, 1.75 * sin(pi * (t - 0.06) / 0.44)),
)
spawn_fx(
    "Scorch_Ring",
    ME_SCORCH,
    FX_FRAMES,
    lambda t: None if t < 0.10 else (V((0.0, 0.0, 0.02)), None, V((2.1 * ramp(t, 0.10, 0.8) * fx_fade(t), 2.1 * ramp(t, 0.10, 0.8) * fx_fade(t), 1.0))),
)

for i in range(8):
    ang = 2.0 * pi * i / 8.0 + rnd(-0.15, 0.15)
    d = V((cos(ang), sin(ang), 0.0))
    sz = rnd(0.45, 0.75)

    def chaff_fn(t: float, dv=d, s=sz):
        if t < 0.18 or t > 1.45:
            return None
        k = (t - 0.18) / 1.27
        return V((0.0, 0.2, 0.45)) + dv * (1.4 + 1.1 * sm(k)) + Z * (0.9 * k), None, s * sm(k * 3.0) * (1.0 - ramp(k, 0.4, 1.0))

    spawn_fx(f"Chaff_{i + 1:02d}", ME_CHAFF, FX_FRAMES, chaff_fn)

for i in range(8):
    ang = rnd(0.0, 2.0 * pi)
    spd = rnd(1.4, 2.9)
    vz = rnd(2.8, 5.2)
    tl = rnd(0.7, 1.05)
    p0 = V((rnd(-1.2, 0.2), rnd(0.1, 1.4), rnd(1.5, 3.0)))
    dim = V((rnd(0.22, 0.36), rnd(0.20, 0.34), rnd(0.18, 0.28)))
    spin = V((rnd(-6, 6), rnd(-6, 6), rnd(-6, 6)))

    def deb_fn(t: float, ps=p0, a=ang, sp=spd, v_z=vz, t_l=tl, dm=dim, sv=spin):
        if t < 0.10:
            return None
        dt = min(t - 0.10, t_l)
        z_cur = max(0.14, ps.z + v_z * dt - 4.9 * dt * dt)
        p = V((ps.x + cos(a) * sp * dt, ps.y + sin(a) * sp * dt, z_cur))
        return p + Z * sink_dz(t), Quaternion(sv.normalized(), dt * 5.0), dm * fx_fade(t)

    spawn_fx(f"Debris_{i + 1:02d}", ME_OAK, FX_FRAMES, deb_fn)

for i, off in enumerate([V((-0.8, 0.9, 1.8)), V((-1.2, 1.2, 1.9)), V((-0.4, 0.6, 1.6))]):
    w, h, freq, ph = rnd(0.24, 0.38), rnd(0.9, 1.4), rnd(12.0, 18.0), rnd(0.0, 6.0)

    def flame_fn(t: float, o=off, ww=w, hh=h, fr=freq, p=ph):
        b = ramp(t, 0.10, 0.42) * fx_fade(t)
        if b <= 0.01:
            return None
        return o + Z * sink_dz(t), Quaternion(Y, 0.10 * sin(t * fr * 0.5 + p)), V((ww * b, ww * b, hh * b * (0.78 + 0.22 * sin(t * fr + p))))

    spawn_fx(f"Fire_{i + 1:02d}", ME_FLAME, FX_FRAMES, flame_fn)

for i in range(8):
    t_emit = 0.12 + 0.16 * i
    life = 1.50
    src = V((rnd(-1.2, 0.2), rnd(0.2, 1.4), rnd(2.0, 3.0)))
    drift = V((rnd(-0.3, 0.4), rnd(-0.3, 0.3), rnd(2.0, 3.0)))
    sz = rnd(0.50, 0.85)

    def smoke_fn(t: float, te=t_emit, lf=life, s0=src, dr=drift, s=sz):
        if t < te or t > te + lf or t > 2.75:
            return None
        k = (t - te) / lf
        sc = s * (0.35 + 0.65 * sm(k * 1.8)) * (1.0 - ramp(k, 0.65, 1.0)) * fx_fade(t)
        return s0 + dr * k + Z * sink_dz(t) * 0.25, Quaternion(Z, k * 2.0 + te), sc

    spawn_fx(f"Smoke_{i + 1:02d}", ME_SMOKE, FX_FRAMES, smoke_fn)

lc = bpy.context.view_layer.layer_collection.children
if FX_COLL in lc:
    lc[FX_COLL].exclude = True
scene.frame_start = 0
scene.frame_end = BUILD_FRAMES
scene.frame_set(0)

bpy.context.preferences.filepaths.save_version = 0
bpy.ops.wm.save_mainfile()
print("ANIMATED Farm.blend clips: Idle, Work, Depleted, Build, Die + farm_death_fx")
