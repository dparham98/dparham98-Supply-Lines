"""Stage 2 for Chapterhouse.blend: NLA clips Idle, Build, Print, Die, and chapterhouse_death_fx.

Run right after build_chapterhouse.py on the saved file:
  blender Chapterhouse.blend --background --python animate_chapterhouse.py

Bakes 24 fps per-object NLA tracks starting at frame 0. Die is baked/pushed last so frame 0
stays at the clean finished rest pose (armored doors closed, banners straight).
"""

from __future__ import annotations

import os
import random
from math import cos, pi, radians, sin

import bmesh
import bpy
from mathutils import Matrix, Quaternion, Vector as V

FPS = 24
FX_COLL = "chapterhouse_death_fx"
random.seed(31)

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
    if mat.name.startswith("ch_fx_"):
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


BANNERS = ["banner_front_L", "banner_front_R"]
DOORS = ["portal_door_L", "portal_door_R"]

# ===========================================================================
# 1. Idle (96 frames / 4.0 s looping)
# ===========================================================================
IDLE_FRAMES = 96
IDLE_T = IDLE_FRAMES / FPS

for idx, bname in enumerate(BANNERS):
    ph = idx * 1.1
    bake(
        OB[bname],
        "Idle",
        IDLE_FRAMES,
        lambda t, p=ph, n=bname: HOME[n] @ Rx(radians(2.8) * sin(2.0 * pi * t / IDLE_T + p)),
    )

bake(
    OB["belfry_beacon"],
    "Idle",
    IDLE_FRAMES,
    lambda t: HOME["belfry_beacon"] @ Ry(radians(3.2) * sin(2.0 * pi * t / IDLE_T)) @ Sc(ONE * (0.96 + 0.06 * sin(4.0 * pi * t / IDLE_T))),
)
bake(
    OB["portal_hearth_glow"],
    "Idle",
    IDLE_FRAMES,
    lambda t: HOME["portal_hearth_glow"] @ Sc(ONE * (0.96 + 0.06 * sin(4.0 * pi * t / IDLE_T))),
)

for sname in ["plinth", "nave_walls", "armory_rack", "portal_frame", "roof", *DOORS]:
    bake(OB[sname], "Idle", IDLE_FRAMES, lambda t, n=sname: HOME[n])

# ===========================================================================
# 2. Build (100 frames / 4.17 s scrubbed by construction progress)
# ===========================================================================
BUILD_FRAMES = 100
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


def lower_part(name: str, a_s: float, b_s: float, b_land: float, drop_z: float):
    def fn(t: float) -> Matrix:
        p = t / BUILD_T
        k = lin(p, a_s, b_s)
        if k <= 0.0:
            return hidden(name)
        d = 1.0 - ramp(p, b_s, b_land)
        return Tm(Z * (drop_z * d)) @ HOME[name] @ Sc(ONE * sm(k))
    return fn


bake(OB["plinth"], "Build", BUILD_FRAMES, grow_z("plinth", 0.00, 0.16))
bake(OB["nave_walls"], "Build", BUILD_FRAMES, grow_z("nave_walls", 0.14, 0.48))
bake(OB["armory_rack"], "Build", BUILD_FRAMES, grow_z("armory_rack", 0.36, 0.62))
bake(OB["portal_frame"], "Build", BUILD_FRAMES, grow_z("portal_frame", 0.28, 0.60))
for dname in DOORS:
    bake(OB[dname], "Build", BUILD_FRAMES, pop_in(dname, 0.56, 0.78))
bake(OB["portal_hearth_glow"], "Build", BUILD_FRAMES, pop_in("portal_hearth_glow", 0.68, 0.86))
bake(OB["roof"], "Build", BUILD_FRAMES, lower_part("roof", 0.52, 0.66, 0.82, 0.42))
bake(OB["belfry_beacon"], "Build", BUILD_FRAMES, pop_in("belfry_beacon", 0.74, 0.92))
for idx, bname in enumerate(BANNERS):
    bake(OB[bname], "Build", BUILD_FRAMES, pop_in(bname, 0.80 + 0.03 * idx, 0.98))

# ===========================================================================
# 3. Print (72 frames / 3.0 s: doors swing outward open cleanly by 1.85 s, close by 3.0 s)
# ===========================================================================
PRINT_FRAMES = 72


def door_swing(side: float, name: str):
    def fn(t: float) -> Matrix:
        # 0..0.90 s closed/warm-up; 0.90..1.85 s swings outward +-96 deg; 1.85..2.10 hold; 2.10..2.95 close
        op = ramp(t, 0.90, 1.85) * (1.0 - ramp(t, 2.05, 2.95))
        return HOME[name] @ Rz(side * radians(96.0) * op)
    return fn


bake(OB["portal_door_L"], "Print", PRINT_FRAMES, door_swing(-1.0, "portal_door_L"))
bake(OB["portal_door_R"], "Print", PRINT_FRAMES, door_swing( 1.0, "portal_door_R"))
bake(
    OB["portal_hearth_glow"],
    "Print",
    PRINT_FRAMES,
    lambda t: HOME["portal_hearth_glow"] @ Sc(ONE * (1.0 + 0.22 * ramp(t, 0.15, 1.1) * (1.0 - ramp(t, 2.2, 2.95)))),
)
bake(
    OB["belfry_beacon"],
    "Print",
    PRINT_FRAMES,
    lambda t: HOME["belfry_beacon"] @ Ry(radians(14.0) * sin(t * 9.0) * ramp(t, 0.1, 0.6) * (1.0 - ramp(t, 2.3, 3.0))) @ Sc(ONE * (1.0 + 0.16 * ramp(t, 0.2, 1.0) * (1.0 - ramp(t, 2.2, 2.95)))),
)

# ===========================================================================
# 4. Die (64 frames / 2.67 s) + chapterhouse_death_fx
# ===========================================================================
DIE_FRAMES = 64
SINK0, SINK1 = 1.75, 2.62
SINK_D = 7.4


def sink_dz(t: float) -> float:
    return -SINK_D * ramp(t, SINK0, SINK1)


def wreck(name: str, t0: float, t1: float, d_loc: V, d_rot: Matrix):
    def fn(t: float) -> Matrix:
        k = ramp(t, t0, t1)
        return Tm(d_loc * k + Z * sink_dz(t)) @ HOME[name] @ (Matrix.Identity(4).lerp(d_rot, k))
    return fn


bake(OB["plinth"], "Die", DIE_FRAMES, lambda t: Tm(Z * (sink_dz(t) - 0.10 * ramp(t, 0.2, 1.0))) @ HOME["plinth"])
bake(OB["nave_walls"], "Die", DIE_FRAMES, wreck("nave_walls", 0.22, 1.15, V((0.0, 0.0, -0.35)), Rx(radians(-6.0)) @ Ry(radians(5.0))))
bake(OB["armory_rack"], "Die", DIE_FRAMES, wreck("armory_rack", 0.18, 0.90, V((-0.35, -0.10, -0.25)), Ry(radians(-34.0))))
bake(OB["portal_frame"], "Die", DIE_FRAMES, wreck("portal_frame", 0.20, 1.05, V((0.0, -0.22, -0.28)), Rx(radians(-16.0))))
bake(OB["portal_door_L"], "Die", DIE_FRAMES, wreck("portal_door_L", 0.12, 0.78, V((-0.18, -0.32, -0.20)), Rz(radians(-78.0)) @ Rx(radians(-22.0))))
bake(OB["portal_door_R"], "Die", DIE_FRAMES, wreck("portal_door_R", 0.14, 0.80, V((0.18, -0.34, -0.22)), Rz(radians(84.0)) @ Rx(radians(-18.0))))
bake(OB["portal_hearth_glow"], "Die", DIE_FRAMES, lambda t: hidden("portal_hearth_glow") if t > 0.35 else HOME["portal_hearth_glow"])
bake(OB["roof"], "Die", DIE_FRAMES, wreck("roof", 0.15, 0.95, V((0.16, 0.10, -1.45)), Rx(radians(12.0)) @ Ry(radians(-14.0))))
bake(OB["belfry_beacon"], "Die", DIE_FRAMES, lambda t: hidden("belfry_beacon") if t > 0.30 else HOME["belfry_beacon"])
for idx, bname in enumerate(BANNERS):
    bake(OB[bname], "Die", DIE_FRAMES, wreck(bname, 0.16, 0.85, V((0.0, -0.20, -0.95)), Rx(radians(-45.0 if idx == 0 else 38.0))))

# ===========================================================================
# Companion Death FX Collection (`chapterhouse_death_fx`, track `"Death"`)
# ===========================================================================


def fx_mat(name: str, col, rough: float = 0.75, emis=None, strength: float = 0.0) -> bpy.types.Material:
    m = bpy.data.materials.new("ch_fx_" + name)
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
FX_STONE = fx_mat("stone", (0.72, 0.70, 0.62), 0.55)
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


ME_ICO = make_fx_mesh("ch_fx_ico", lambda bm: bmesh.ops.create_icosphere(bm, subdivisions=1, radius=1.0), FX_DUST)
ME_STONE = make_fx_mesh("ch_fx_stone", lambda bm: bmesh.ops.create_cube(bm, size=1.0), FX_STONE)
ME_FLASH = make_fx_mesh("ch_fx_flash", lambda bm: bmesh.ops.create_icosphere(bm, subdivisions=2, radius=1.0), FX_FLASH)
ME_FLAME = make_fx_mesh("ch_fx_flame", lambda bm: bmesh.ops.create_cone(bm, cap_ends=True, segments=6, radius1=0.55, radius2=0.04, depth=1.5), FX_FLAME)
ME_SMOKE = make_fx_mesh("ch_fx_smoke", lambda bm: bmesh.ops.create_icosphere(bm, subdivisions=1, radius=1.0), FX_SMOKE)
ME_SCORCH = make_fx_mesh("ch_fx_scorch", lambda bm: bmesh.ops.create_cone(bm, cap_ends=True, segments=16, radius1=1.0, radius2=1.0, depth=0.04), FX_SCORCH)

fx_col = bpy.data.collections.new(FX_COLL)
scene.collection.children.link(fx_col)
FX_FRAMES = 72


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
    return 1.0 - ramp(t, 2.0, 2.9)


# First object in fx_col MUST be Flash_Spire (index 0 for BurstEffect)
spawn_fx(
    "Flash_Spire",
    ME_FLASH,
    FX_FRAMES,
    lambda t: None if t < 0.06 or t > 0.55 else (V((0.0, 0.1, 4.4)), None, 2.2 * sin(pi * (t - 0.06) / 0.49)),
)
spawn_fx(
    "Scorch_Ring",
    ME_SCORCH,
    FX_FRAMES,
    lambda t: None if t < 0.12 else (V((0.0, 0.0, 0.02)), None, V((2.9 * ramp(t, 0.12, 0.9) * fx_fade(t), 2.9 * ramp(t, 0.12, 0.9) * fx_fade(t), 1.0))),
)

for i in range(8):
    ang = 2.0 * pi * i / 8.0 + rnd(-0.15, 0.15)
    d = V((cos(ang), sin(ang), 0.0))
    sz = rnd(0.65, 1.05)

    def dust_fn(t: float, dv=d, s=sz):
        if t < 0.25 or t > 1.75:
            return None
        k = (t - 0.25) / 1.50
        return V((0.0, 0.0, 0.35)) + dv * (2.6 + 1.5 * sm(k)) + Z * (0.8 * k), None, s * sm(k * 3.5) * (1.0 - ramp(k, 0.4, 1.0))

    spawn_fx(f"Dust_{i + 1:02d}", ME_ICO, FX_FRAMES, dust_fn)

for i in range(10):
    ang = rnd(0.0, 2.0 * pi)
    spd = rnd(1.8, 3.6)
    vz = rnd(3.2, 5.8)
    tl = rnd(0.75, 1.15)
    p0 = V((rnd(-1.0, 1.0), rnd(-1.0, 1.0), rnd(2.2, 4.4)))
    dim = V((rnd(0.22, 0.40), rnd(0.20, 0.36), rnd(0.18, 0.32)))
    spin = V((rnd(-6, 6), rnd(-6, 6), rnd(-6, 6)))

    def deb_fn(t: float, ps=p0, a=ang, sp=spd, v_z=vz, t_l=tl, dm=dim, sv=spin):
        if t < 0.12:
            return None
        dt = min(t - 0.12, t_l)
        z_cur = max(0.16, ps.z + v_z * dt - 4.9 * dt * dt)
        p = V((ps.x + cos(a) * sp * dt, ps.y + sin(a) * sp * dt, z_cur))
        return p + Z * sink_dz(t), Quaternion(sv.normalized(), dt * 5.0), dm * fx_fade(t)

    spawn_fx(f"Debris_{i + 1:02d}", ME_STONE, FX_FRAMES, deb_fn)

for i, off in enumerate([V((0.0, 0.1, 3.1)), V((-0.5, -0.4, 2.8)), V((0.6, 0.5, 2.9)), V((0.0, -2.1, 0.8))]):
    w, h, freq, ph = rnd(0.30, 0.48), rnd(1.1, 1.7), rnd(12.0, 18.0), rnd(0.0, 6.0)

    def flame_fn(t: float, o=off, ww=w, hh=h, fr=freq, p=ph):
        b = ramp(t, 0.12, 0.45) * fx_fade(t)
        if b <= 0.01:
            return None
        return o + Z * sink_dz(t), Quaternion(Y, 0.10 * sin(t * fr * 0.5 + p)), V((ww * b, ww * b, hh * b * (0.78 + 0.22 * sin(t * fr + p))))

    spawn_fx(f"Fire_{i + 1:02d}", ME_FLAME, FX_FRAMES, flame_fn)

for i in range(10):
    t_emit = 0.15 + 0.16 * i
    life = 1.65
    src = V((rnd(-1.0, 1.0), rnd(-1.0, 1.0), rnd(3.0, 4.2)))
    drift = V((rnd(-0.4, 0.5), rnd(-0.4, 0.4), rnd(2.6, 3.8)))
    sz = rnd(0.65, 1.05)

    def smoke_fn(t: float, te=t_emit, lf=life, s0=src, dr=drift, s=sz):
        if t < te or t > te + lf or t > 2.90:
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
print("ANIMATED Chapterhouse.blend clips: Idle, Build, Print, Die + chapterhouse_death_fx")
