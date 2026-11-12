"""Stage 2 for IronMine.blend: the clips Idle, Work, Depleted, Build and Die, and the death effects.

Run right after build_mine.py, on the saved file:
  blender IronMine.blend --background --python animate_mine.py

Run build_mine.py first each time: the saved file keeps the pose the clips leave at frame 0, and
a second run would take that as the rest pose.

It clears any animation and effects it made before, so it can be re-run. Everything is baked one key a
frame at 24 fps from the functions below, as NLA tracks named after their clip. The rest pose is the
finished pithead with its skip raised and loaded. The shared helpers follow the Barracks' animate_barracks.py.
"""
import bpy, bmesh, math, random
from math import sin, cos, radians, pi, exp
from mathutils import Vector as V, Matrix, Quaternion

FPS = 24
FX_COLLS = ("mine_death_fx",)
scene = bpy.context.scene
scene.render.fps = FPS
random.seed(5)
X, Y, Z = V((1, 0, 0)), V((0, 1, 0)), V((0, 0, 1))

# ---------------------------------------------------------------- start clean
scene.frame_set(0)
for ob in list(bpy.data.objects):
    if ob.animation_data:
        ob.animation_data_clear()
for name in FX_COLLS:
    c = bpy.data.collections.get(name)
    if c:
        for o in list(c.objects):
            bpy.data.objects.remove(o)
        bpy.data.collections.remove(c)
for a in list(bpy.data.actions):
    bpy.data.actions.remove(a)
for m in list(bpy.data.meshes):
    if m.users == 0:
        bpy.data.meshes.remove(m)
for m in list(bpy.data.materials):
    if m.name.startswith("mine_fx_"):
        bpy.data.materials.remove(m)
bpy.context.view_layer.update()
OB = bpy.data.objects
# Rest poses at full size: a re-run starts from the saved file, whose glows and dust are shrunk away.
HOME = {o.name: Matrix.LocRotScale(o.matrix_basis.to_translation(), o.matrix_basis.to_quaternion(), None) for o in OB}
NIL = V((0.001, 0.001, 0.001))
ONE = V((1, 1, 1))
IDQ = Quaternion()


def sm(x):
    x = max(0.0, min(1.0, x))
    return x * x * (3 - 2 * x)


def ramp(t, a, b):
    return sm((t - a) / (b - a))


def lin(t, a, b):
    return max(0.0, min(1.0, (t - a) / (b - a)))


def Tm(p):
    return Matrix.Translation(V(p))


def Rx(a):
    return Matrix.Rotation(a, 4, 'X')


def Ry(a):
    return Matrix.Rotation(a, 4, 'Y')


def Rz(a):
    return Matrix.Rotation(a, 4, 'Z')


def Sc(v):
    return Matrix.Diagonal((*V(v), 1))


def push(ob, clip):
    ad = ob.animation_data
    act = ad.action
    act.name = clip + "_" + ob.name
    track = ad.nla_tracks.new()
    track.name = clip
    strip = track.strips.new(clip, 0, act)
    strip.name = clip
    ad.action = None


def bake(ob, clip, frames, fn):
    """fn(t) -> matrix in the object's parent space."""
    ob.rotation_mode = 'QUATERNION'
    rest = ob.matrix_basis.copy()
    prev = None
    for f in range(frames + 1):
        loc, q, sc = fn(f / FPS).decompose()
        sc = V((max(sc.x, 0.001), max(sc.y, 0.001), max(sc.z, 0.001)))
        if prev is not None and prev.dot(q) < 0:
            q.negate()
        prev = q.copy()
        ob.location, ob.rotation_quaternion, ob.scale = loc, q, sc
        ob.keyframe_insert("location", frame=f)
        ob.keyframe_insert("rotation_quaternion", frame=f)
        ob.keyframe_insert("scale", frame=f)
    push(ob, clip)
    ob.matrix_basis = rest


def hidden(name):
    """The home pose shrunk to nothing, in place."""
    loc = HOME[name].translation
    return Tm(loc) @ Sc(NIL)


def about(pivot, R):
    return Tm(pivot) @ R @ Tm(-V(pivot))


ROOT_PARTS = ["collar", "headframe", "sheave", "skip", "rope", "back_rope", "winch_house", "drum", "ore_bin", "chute", "lamp_post"]
DUSTS = ["dust_1", "dust_2", "dust_3"]
S = HOME["skip"].translation * V((1, 1, 0))      # the shaft centre on the ground
SK = HOME["skip"].translation.copy()             # the skip's hanger at rest (raised)
W = HOME["sheave"].translation.copy()
DRUM = HOME["drum"].translation.copy()
W_R = 0.30                             # build_mine.py
DRUM_R = 0.20
SKIP_W, SKIP_H = 0.36, 0.50
ROPE_TOP = HOME["rope"].translation.copy()
ROPE_LEN = ROPE_TOP.z - (SK.z + 0.12)
DEPTH = 2.7                            # how far the skip drops into the shaft: out of sight under the collar
TIP = radians(58)
TIP_PIVOT = V((S.x, S.y - SKIP_W / 2, SK.z - SKIP_H * 0.55))


def skip_at(d, tip=0.0, sway=0.0):
    """The skip lowered d metres (0 = raised), tipped forward by tip (0..1), swinging by sway radians."""
    M = Tm(-Z * d) @ about(TIP_PIVOT, Rx(TIP * tip)) @ HOME["skip"]
    if sway:
        M = about(ROPE_TOP, Rx(sway)) @ M
    return M


def rope_at(d, sway=0.0):
    k = (ROPE_LEN + d) / ROPE_LEN
    M = HOME["rope"] @ Sc((1, 1, k))
    if sway:
        M = about(ROPE_TOP, Rx(sway)) @ M
    return M


def sheave_at(d):
    return HOME["sheave"] @ Ry(-d / W_R)


def drum_at(d):
    return HOME["drum"] @ Ry(d / DRUM_R)


def glow(name, s):
    return HOME[name] @ Sc(ONE * s) if s > 0.002 else hidden(name)


def lamp_flicker(t, w):
    return 1.0 + 0.05 * sin(7 * w * t) + 0.03 * sin(13 * w * t + 1.0)


def bake_still(clip, frames, d=0.0):
    bake(OB["sheave"], clip, frames, lambda t: sheave_at(d))
    bake(OB["drum"], clip, frames, lambda t: drum_at(d))


# ================================================================= Idle (loops): the skip hangs raised and empty
IDLE_FRAMES = 96                       # 4 s
IDLE_T = IDLE_FRAMES / FPS
WI = 2 * pi / IDLE_T


def idle_sway(t):
    return radians(0.8) * sin(WI * t) + radians(0.3) * sin(3 * WI * t + 0.5)


bake(OB["skip"], "Idle", IDLE_FRAMES, lambda t: skip_at(0.0, 0.0, idle_sway(t)))
bake(OB["rope"], "Idle", IDLE_FRAMES, lambda t: rope_at(0.0, idle_sway(t)))
bake(OB["skip_ore"], "Idle", IDLE_FRAMES, lambda t: hidden("skip_ore"))
bake(OB["back_rope"], "Idle", IDLE_FRAMES, lambda t: HOME["back_rope"])
bake_still("Idle", IDLE_FRAMES)
bake(OB["ore_heap"], "Idle", IDLE_FRAMES, lambda t: HOME["ore_heap"])
for n in DUSTS:
    bake(OB[n], "Idle", IDLE_FRAMES, lambda t, n=n: hidden(n))
bake(OB["lamp"], "Idle", IDLE_FRAMES, lambda t: glow("lamp", lamp_flicker(t, WI)))
bake(OB["beacon"], "Idle", IDLE_FRAMES, lambda t: hidden("beacon"))

# ================================================================= Work (loops): lower, load, wind up, tip into the chute
# The loop starts and ends with the skip raised, as in Idle, so the switch either way is seamless.
WORK_FRAMES = 72                       # 3 s
WORK_T = WORK_FRAMES / FPS
WW = 2 * pi / WORK_T
DN0, DN1 = 0.0, 1.05                   # lowering into the shaft
UP0, UP1 = 1.15, 2.1                   # rising with a load
TIP0, TIP1, TIP2, TIP3 = 2.2, 2.45, 2.62, 2.9


def work_depth(t):
    if t < DN1:
        return DEPTH * sm(lin(t, DN0, DN1))
    if t < UP0:
        return DEPTH
    return DEPTH * (1 - sm(lin(t, UP0, UP1)))


def work_tip(t):
    return sm(lin(t, TIP0, TIP1)) * (1 - sm(lin(t, TIP2, TIP3)))


def work_skip(t):
    d = work_depth(t)
    bounce = 0.015 * sin(pi * lin(t, UP1, TIP0)) if UP1 < t < TIP0 else 0.0
    return skip_at(d - bounce, work_tip(t))


def heap_bump(t):
    k = lin(t, TIP1 - 0.05, TIP2 + 0.35)
    return 1.0 + 0.09 * sin(pi * k) if 0 < k < 1 else 1.0


def dust(i):
    def fn(t):
        t0 = TIP1 - 0.1 + 0.12 * i
        k = lin(t, t0, t0 + 0.9)
        if k <= 0.0 or k >= 1.0:
            return hidden(DUSTS[i])
        s = sm(k * 5) * (0.5 + 1.1 * k) * (1 - ramp(k, 0.5, 1.0))
        if s < 0.003:
            return hidden(DUSTS[i])
        drift = V(((i - 1) * 0.18 * k, -0.1 * k, 0.45 * k))
        return Tm(drift) @ HOME[DUSTS[i]] @ Sc(ONE * s)
    return fn


bake(OB["skip"], "Work", WORK_FRAMES, work_skip)
bake(OB["rope"], "Work", WORK_FRAMES, lambda t: rope_at(work_depth(t)))
bake(OB["back_rope"], "Work", WORK_FRAMES, lambda t: HOME["back_rope"])
bake(OB["skip_ore"], "Work", WORK_FRAMES, lambda t: HOME["skip_ore"] if DN1 + 0.02 < t < TIP1 - 0.08 else hidden("skip_ore"))
bake(OB["sheave"], "Work", WORK_FRAMES, lambda t: sheave_at(work_depth(t)))
bake(OB["drum"], "Work", WORK_FRAMES, lambda t: drum_at(work_depth(t)))
bake(OB["ore_heap"], "Work", WORK_FRAMES, lambda t: HOME["ore_heap"] @ Sc((1, 1, heap_bump(t))))
for i, n in enumerate(DUSTS):
    bake(OB[n], "Work", WORK_FRAMES, dust(i))
bake(OB["lamp"], "Work", WORK_FRAMES, lambda t: glow("lamp", lamp_flicker(t, WW)))
bake(OB["beacon"], "Work", WORK_FRAMES, lambda t: glow("beacon", 1.0 if (t / WORK_T * 4) % 1.0 < 0.5 else 0.0))

# ================================================================= Depleted (loops): worked out, lamp dark, bin empty
DEP_FRAMES = 96
DEP_T = DEP_FRAMES / FPS
WD = 2 * pi / DEP_T


def dep_sway(t):
    return radians(1.2) * sin(WD * t + 0.3)


bake(OB["skip"], "Depleted", DEP_FRAMES, lambda t: skip_at(0.0, 0.0, dep_sway(t)))
bake(OB["rope"], "Depleted", DEP_FRAMES, lambda t: rope_at(0.0, dep_sway(t)))
bake(OB["skip_ore"], "Depleted", DEP_FRAMES, lambda t: hidden("skip_ore"))
bake(OB["back_rope"], "Depleted", DEP_FRAMES, lambda t: HOME["back_rope"])
bake_still("Depleted", DEP_FRAMES)
bake(OB["ore_heap"], "Depleted", DEP_FRAMES, lambda t: hidden("ore_heap"))
for n in DUSTS:
    bake(OB[n], "Depleted", DEP_FRAMES, lambda t, n=n: hidden(n))
bake(OB["lamp"], "Depleted", DEP_FRAMES, lambda t: hidden("lamp"))
bake(OB["beacon"], "Depleted", DEP_FRAMES, lambda t: hidden("beacon"))

# ================================================================= Build (scrubbed by construction progress)
BUILD_FRAMES = 240                     # 10 s; the game maps progress 0..1 onto it
BUILD_T = BUILD_FRAMES / FPS


def grow_z(name, a, b):
    def fn(t):
        k = lin(t / BUILD_T, a, b)
        if k <= 0:
            return hidden(name)
        return HOME[name] @ Sc((1, 1, sm(k)))
    return fn


def pop(name, a, b):
    def fn(t):
        k = lin(t / BUILD_T, a, b)
        if k <= 0:
            return hidden(name)
        s = 1 + 0.12 * sin(pi * k) * (1 - k) if k > 0.6 else sm(k / 0.6) * 1.06
        return HOME[name] @ Sc(ONE * s)
    return fn


def lower(name, a, b, height):
    def fn(t):
        p = t / BUILD_T
        k = lin(p, a, a + 0.04)
        if k <= 0:
            return hidden(name)
        d = 1 - ramp(p, a + 0.04, b)
        return Tm(Z * height * d) @ HOME[name] @ Sc(ONE * sm(k))
    return fn


def after(name, a):
    return lambda t: HOME[name] if t / BUILD_T >= a else hidden(name)


bake(OB["collar"], "Build", BUILD_FRAMES, grow_z("collar", 0.0, 0.1))
bake(OB["headframe"], "Build", BUILD_FRAMES, grow_z("headframe", 0.08, 0.42))
bake(OB["sheave"], "Build", BUILD_FRAMES, lower("sheave", 0.42, 0.52, 1.2))
bake(OB["skip"], "Build", BUILD_FRAMES, pop("skip", 0.52, 0.6))
bake(OB["rope"], "Build", BUILD_FRAMES, grow_z("rope", 0.56, 0.62))
bake(OB["back_rope"], "Build", BUILD_FRAMES, after("back_rope", 0.78))
bake(OB["winch_house"], "Build", BUILD_FRAMES, grow_z("winch_house", 0.6, 0.72))
bake(OB["drum"], "Build", BUILD_FRAMES, pop("drum", 0.7, 0.78))
bake(OB["chute"], "Build", BUILD_FRAMES, pop("chute", 0.76, 0.84))
bake(OB["ore_bin"], "Build", BUILD_FRAMES, grow_z("ore_bin", 0.82, 0.9))
bake(OB["lamp_post"], "Build", BUILD_FRAMES, grow_z("lamp_post", 0.88, 0.96))
bake(OB["ore_heap"], "Build", BUILD_FRAMES, lambda t: hidden("ore_heap"))
bake(OB["skip_ore"], "Build", BUILD_FRAMES, lambda t: hidden("skip_ore"))
for n in DUSTS:
    bake(OB[n], "Build", BUILD_FRAMES, lambda t, n=n: hidden(n))
bake(OB["lamp"], "Build", BUILD_FRAMES, after("lamp", 0.97))
bake(OB["beacon"], "Build", BUILD_FRAMES, lambda t: hidden("beacon"))

# ================================================================= Die
DIE_END = 5.0
DIE_FRAMES = int(DIE_END * FPS)
SINK0 = 3.7
SINK = 4.6
T_SNAP = 0.3                           # the hoist rope snaps
T_FALL0, T_FALL1 = 0.5, 1.45           # the headframe goes over to the right
T_FREE = 1.05                          # the sheave breaks loose from its frame
FOOT = V((0.86, 0.22, 0.12))           # the right-hand feet: the line the headframe pivots on


def sink(t):
    return Tm(-Z * SINK * ramp(t, SINK0, DIE_END))


def shake(t, amp, ph):
    if t > 1.8:
        return Matrix.Identity(4)
    a = amp * exp(-t * 2.5) * min(t / 0.06, 1.0)      # from rest: the exported rest pose is Die's frame 0
    return Tm((a * sin(t * 47 + ph), a * sin(t * 53 + ph * 2), 0.5 * a * sin(t * 61 + ph * 3)))


def skip_drop(t):
    if t < T_SNAP:
        return 0.0
    s = t - T_SNAP
    return min(0.5 * 9.8 * s * s, DEPTH + 0.6)


def head_angle(t):
    lurch = -radians(5) * sm(lin(t, T_SNAP, T_SNAP + 0.15)) * (1 - sm(lin(t, T_SNAP + 0.15, T_FALL0)))
    k = lin(t, T_FALL0, T_FALL1)
    fall = radians(84) * k * k
    if t > T_FALL1:
        s = t - T_FALL1
        fall = radians(84) - radians(3) * exp(-s * 7) * abs(sin(s * 16))
    return lurch + fall


def headframe_die(t):
    a = head_angle(t)
    twist = Rz(radians(-12) * sm(lin(t, T_FALL0, T_FALL1)))
    return sink(t) @ shake(t, 0.02, 0.7) @ about(FOOT, twist @ Ry(a)) @ HOME["headframe"]


def sheave_die(t):
    spin = -(skip_drop(t)) / W_R * 0.5
    if t < T_FREE:
        return headframe_die(t) @ HOME["headframe"].inverted() @ HOME["sheave"] @ Ry(spin)
    # loose: falls to the ground, turns to roll toward the front, wobbles and falls flat
    held = headframe_die(T_FREE) @ HOME["headframe"].inverted() @ HOME["sheave"]
    p0 = held.translation
    s = t - T_FREE
    fall_t = 0.42
    land = V((p0.x + 0.5, p0.y - 0.1, W_R + 0.06))
    if s < fall_t:
        k = s / fall_t
        pos = p0.lerp(land, k) + Z * 0.5 * sin(pi * k) * (1 - k)
        pos.z = p0.z + (land.z - p0.z) * k * k
    else:
        r = min(s - fall_t, 1.0)
        dist = 1.8 * r - 0.75 * r * r
        pos = land - Y * dist
    turn = Rz(radians(90) * sm(lin(s, 0.0, fall_t)))
    roll_ang = 0.0 if s < fall_t else (1.8 * min(s - fall_t, 1.0) - 0.75 * min(s - fall_t, 1.0) ** 2) / W_R
    k = sm(lin(s, fall_t + 0.75, fall_t + 1.35))
    pos = pos - Z * (W_R - 0.03) * k
    flat = Ry(radians(86) * k)
    rot = held.to_quaternion().slerp(Quaternion(), sm(lin(s, 0.0, fall_t))).to_matrix().to_4x4()
    return sink(t) @ Tm(pos) @ flat @ turn @ Ry(-roll_ang) @ rot @ Ry(spin)


T_BOTTOM = T_SNAP + math.sqrt(2 * (DEPTH + 0.6) / 9.8)


def skip_die(t):
    if t > T_BOTTOM:
        return hidden("skip")
    return sink(t) @ skip_at(skip_drop(t), 0.0, radians(4) * sin(t * 20) * exp(-t * 3) if t < T_SNAP + 0.4 else 0.0)


def rope_die(t):
    if t < T_SNAP:
        return rope_at(0.0)
    k = lin(t, T_SNAP, T_SNAP + 0.12)    # whips up and away
    if k >= 1:
        return hidden("rope")
    return HOME["rope"] @ Sc((1, 1, 1 - k))


def drum_die(t):
    if t < T_SNAP:
        return drum_at(0.0)
    s = t - T_SNAP
    turns = 14.0 * (1 - exp(-s * 2.2)) / 2.2       # runs free, slowing
    return sink(t) @ shake(t, 0.015, 3.0) @ HOME["drum"] @ Ry(turns)


def lean(name, pivot, R_end, t0, t1, drop=0.0, ease=sm):
    def fn(t):
        k = ease(lin(t, t0, t1))
        return sink(t) @ shake(t, 0.02, len(name)) @ Tm(-Z * drop * k) @ about(pivot, R_end(k)) @ HOME[name]
    return fn


def accel(x):
    return x * x


CHUTE_FOOT = V((0.62, -0.5, 0.12))
BIN_FOOT = V((0.62, -0.92, 0.12))
SHED_FOOT = V((-0.59, 0.92, 0.12))
LAMP_FOOT = HOME["lamp_post"].translation.copy()

bake(OB["collar"], "Die", DIE_FRAMES, lambda t: sink(t) @ shake(t, 0.012, 5.0) @ HOME["collar"])
bake(OB["headframe"], "Die", DIE_FRAMES, headframe_die)
bake(OB["beacon"], "Die", DIE_FRAMES, lambda t: glow("beacon", 1.3 if t < T_FALL0 + 0.2 and (t * 6) % 1.0 < 0.5 else 0.0))
bake(OB["sheave"], "Die", DIE_FRAMES, sheave_die)
bake(OB["skip"], "Die", DIE_FRAMES, skip_die)
bake(OB["skip_ore"], "Die", DIE_FRAMES, lambda t: HOME["skip_ore"])
bake(OB["rope"], "Die", DIE_FRAMES, rope_die)
bake(OB["back_rope"], "Die", DIE_FRAMES, lambda t: glow("back_rope", 1 - lin(t, T_SNAP, T_SNAP + 0.12)))
bake(OB["drum"], "Die", DIE_FRAMES, drum_die)
bake(OB["winch_house"], "Die", DIE_FRAMES, lean("winch_house", SHED_FOOT, lambda k: Rx(-radians(11) * k) @ Rz(radians(6) * k), T_SNAP + 0.1, T_SNAP + 0.7, 0.06))
bake(OB["chute"], "Die", DIE_FRAMES, lean("chute", CHUTE_FOOT, lambda k: Rx(-radians(62) * k), T_FALL0 + 0.1, T_FALL0 + 0.75, 0.15, accel))
bake(OB["ore_bin"], "Die", DIE_FRAMES, lean("ore_bin", BIN_FOOT, lambda k: Rx(radians(72) * k) @ Ry(radians(10) * k), T_FALL0 + 0.45, T_FALL0 + 1.0, 0.05, accel))
bake(OB["ore_heap"], "Die", DIE_FRAMES, lambda t: glow("ore_heap", 1.0 - sm(lin(t, T_FALL0 + 0.6, T_FALL0 + 0.95))))
for n in DUSTS:
    bake(OB[n], "Die", DIE_FRAMES, lambda t, n=n: hidden(n))
bake(OB["lamp_post"], "Die", DIE_FRAMES, lean("lamp_post", LAMP_FOOT, lambda k: Ry(-radians(84) * k) @ Rx(radians(12) * k), T_FALL0 + 0.3, T_FALL0 + 1.15, 0.0, accel))
bake(OB["lamp"], "Die", DIE_FRAMES, lambda t: glow("lamp", 1.0 if t < T_FALL0 + 0.5 or (T_FALL0 + 0.6 < t < T_FALL0 + 0.7) else 0.0))

# ================================================================= death effects (Die's timeline)


def fx_material(name, col, rough=0.8, emis=None, strength=0.0, alpha=1.0, met=0.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = next(n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    b.inputs["Base Color"].default_value = (*col, 1)
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = met
    if emis:
        b.inputs["Emission Color"].default_value = (*emis, 1)
        b.inputs["Emission Strength"].default_value = strength
    if alpha < 1.0:
        b.inputs["Alpha"].default_value = alpha
        m.blend_method = 'BLEND'
        m.surface_render_method = 'BLENDED'
    m.diffuse_color = (*col, alpha)
    return m



M_DUST = fx_material("mine_fx_dust", (0.30, 0.22, 0.16), 1.0, None, 0.0, 0.75)
M_SMOKE = fx_material("mine_fx_smoke", (0.10, 0.09, 0.08), 1.0, None, 0.0, 0.85)
M_SPARK = fx_material("mine_fx_spark", (0, 0, 0), 0.8, (1.0, 0.62, 0.18), 5.0)
M_FLASH = fx_material("mine_fx_flash", (0, 0, 0), 0.8, (1.0, 0.8, 0.4), 3.2)
M_ORE = bpy.data.materials["mine_ore"]
M_SCRAP = bpy.data.materials["mine_steel"]
M_SCRAP2 = bpy.data.materials["mine_rust"]


def mesh_from(bm, name, mats, smooth=False):
    for f in bm.faces:
        f.smooth = smooth
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    for m in mats:
        me.materials.append(m)
    return me


def ico_mesh(name, mat, sub=1, jitter=0.0, smooth=False, radius=1.0):
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=sub, radius=radius)
    for v in bm.verts:
        v.co *= 1 + random.uniform(-jitter, jitter)
    return mesh_from(bm, name, [mat], smooth)


def shard_mesh(name, mat):
    """A thin diamond lying along Y, one unit long."""
    bm = bmesh.new()
    a, b = bm.verts.new((0, -0.5, 0)), bm.verts.new((0, 0.5, 0))
    ring = [bm.verts.new((0.12 * cos(i * pi / 2), -0.15, 0.12 * sin(i * pi / 2))) for i in range(4)]
    for i in range(4):
        j = (i + 1) % 4
        bm.faces.new((a, ring[j], ring[i]))
        bm.faces.new((b, ring[i], ring[j]))
    return mesh_from(bm, name, [mat])


def plate_mesh(name, mats):
    """A bent scrap plate about one unit across, two faces coloured differently."""
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0, matrix=Sc((1.0, 0.7, 0.06)))
    for v in bm.verts:
        v.co.z += 0.18 * v.co.x * v.co.x + random.uniform(-0.03, 0.03)
    for f in bm.faces:
        f.material_index = 1 if f.normal.z > 0.5 else 0
    return mesh_from(bm, name, mats)


def flame_mesh(name, mat):
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=5, radius1=1.0, radius2=0.02, depth=1.0,
                          matrix=Tm((0, 0, 0.5)))
    return mesh_from(bm, name, [mat])


def disc_mesh(name, mat):
    bm = bmesh.new()
    ring = []
    for i in range(18):
        a = 2 * pi * i / 18
        r = 1.0 + 0.16 * sin(3 * a + 1.0) + 0.09 * sin(7 * a)
        ring.append(bm.verts.new((r * cos(a), r * sin(a), 0)))
    bm.faces.new(ring)
    return mesh_from(bm, name, [mat])


def fx(coll, name, mesh, clip, frames, fn):
    """fn(t) -> (location, quaternion or None, scale as float or vector) or None while unseen."""
    ob = bpy.data.objects.new(name, mesh)
    coll.objects.link(ob)
    last = [V((0, 0, 0))]

    def mat(t):
        r = fn(t)
        if r is None:
            return Tm(last[0]) @ Sc(NIL)
        loc, q, sc = r
        last[0] = V(loc)
        if not isinstance(sc, V):
            sc = V((sc, sc, sc))
        sc = V((max(sc.x, 0.001), max(sc.y, 0.001), max(sc.z, 0.001)))
        return Tm(loc) @ (q or IDQ).to_matrix().to_4x4() @ Sc(sc)
    bake(ob, clip, frames, mat)
    ob.location, ob.scale = (0, 0, 0), NIL
    return ob


def collection(name):
    c = bpy.data.collections.new(name)
    scene.collection.children.link(c)
    return c


GRAV = 9.8


def ballistic(p0, v, s, g=GRAV):
    return V(p0) + V(v) * s + V((0, 0, -0.5 * g * s * s))


def rnd(a, b):
    return random.uniform(a, b)


C = collection("mine_death_fx")
PUFF = ico_mesh("fxm_dust", M_DUST, 2, 0.12, True)
SMOKE = ico_mesh("fxm_smoke", M_SMOKE, 2, 0.1, True)
SHARD = shard_mesh("fxm_shard", M_SPARK)
SCRAP = plate_mesh("fxm_scrap", [M_SCRAP, M_SCRAP2])
ORE = ico_mesh("fxm_ore", M_ORE, 0, 0.25, False, 1.0)
CORE = ico_mesh("fxm_core", M_FLASH, 1, 0.0, False, 0.45)
FADE0, FADE1 = SINK0 + 0.1, DIE_END - 0.1
SNAP_AT = V((S.x, S.y, W.z - 0.1))
T_LAND = T_FALL1                       # the headframe hits the ground


def fade(t):
    return 1 - ramp(t, FADE0, FADE1)


def sunk(p, t):
    return V(p) - Z * SINK * ramp(t, SINK0, DIE_END)


def flash(t):
    snap = 1.3 * exp(-((t - T_SNAP - 0.03) / 0.08) ** 2) if t > T_SNAP - 0.1 else 0.0
    return SNAP_AT, None, snap


# The flash mesh's scale drives the light in the game, so it comes first in the collection.
fx(C, "Flash", CORE, "Death", DIE_FRAMES, flash)

for i in range(14):                    # sparks where the rope parts over the sheave
    vel = V((rnd(-3.0, 3.0), rnd(-3.0, 3.0), rnd(1.0, 4.5)))
    life = rnd(0.3, 0.6)
    size = rnd(0.12, 0.2)
    te = T_SNAP + rnd(-0.02, 0.05)

    def spark(t, vel=vel, life=life, size=size, te=te):
        if t < te or t > te + life:
            return None
        s = t - te
        v_now = vel + V((0, 0, -GRAV * s))
        return ballistic(SNAP_AT, vel, s), v_now.to_track_quat('Y', 'Z'), size * (1 - s / life)
    fx(C, "Snap_Spark_%d" % (i + 1), SHARD, "Death", DIE_FRAMES, spark)

for i in range(8):                     # a plume of dust up the shaft when the skip hits the bottom
    d = V((rnd(-0.3, 0.3), rnd(-0.3, 0.3), 1.0)).normalized()
    size = rnd(0.25, 0.4)
    te = T_BOTTOM + rnd(0.0, 0.15)

    def plume(t, d=d, size=size, te=te):
        if t < te or t > te + 1.5:
            return None
        k = (t - te) / 1.5
        p = S + Z * 0.15 + d * (2.2 * (1 - (1 - k) ** 2.5))
        return p, Quaternion(Z, k * 2), size * sm(k * 6) * (1 - ramp(k, 0.45, 1.0))
    fx(C, "Plume_%d" % (i + 1), PUFF, "Death", DIE_FRAMES, plume)

for i in range(14):                    # dust thrown up along the fallen headframe
    along = rnd(0.6, 3.6)
    at = FOOT + V((along, rnd(-0.6, 0.6), 0.0))
    at.z = 0.1
    size = rnd(0.3, 0.5)
    te = T_LAND - 0.15 + along * 0.04 + rnd(0.0, 0.08)
    out = V((rnd(-0.4, 0.4), rnd(-1.0, 1.0), 0)).normalized()

    def impact(t, at=at, size=size, te=te, out=out):
        if t < te or t > te + 1.8:
            return None
        k = (t - te) / 1.8
        p = at + out * 0.9 * (1 - (1 - k) ** 3) + Z * 0.7 * k
        return sunk(p, t) if t > SINK0 else p, Quaternion(Z, k * 2 + te), size * sm(k * 5) * (1 - ramp(k, 0.4, 1.0))
    fx(C, "Impact_Dust_%d" % (i + 1), PUFF, "Death", DIE_FRAMES, impact)

for i in range(6):                     # girders and plates knocked off as it lands
    src = FOOT + V((rnd(1.0, 3.2), rnd(-0.3, 0.3), 0.3))
    vel = V((rnd(-0.6, 1.4), rnd(-1.8, 1.8), rnd(2.0, 3.5)))
    te = T_LAND + rnd(-0.05, 0.05)
    size = rnd(0.2, 0.35)
    spin_ax = V((rnd(-1, 1), rnd(-1, 1), rnd(-1, 1))).normalized()
    spin = rnd(8, 14)
    land_q = Quaternion(Z, rnd(0, 6)) @ Quaternion(X, rnd(-0.25, 0.25))
    fall = (vel.z + math.sqrt(vel.z ** 2 + 2 * GRAV * (src.z - 0.04))) / GRAV

    def scrap(t, src=src, vel=vel, te=te, size=size, spin_ax=spin_ax, spin=spin, land_q=land_q, fall=fall):
        if t < te:
            return None
        s = t - te
        if s < fall:
            return ballistic(src, vel, s), Quaternion(spin_ax, spin * s), size
        p = ballistic(src, vel, fall)
        p.z = 0.04
        return sunk(p, t), land_q, size
    fx(C, "Scrap_%d" % (i + 1), SCRAP, "Death", DIE_FRAMES, scrap)

BIN_AT = HOME["ore_bin"].translation + V((0, 0, 1.0))
for i in range(16):                    # ore spilled from the bin as it tips over
    vel = V((rnd(-0.6, 0.6), rnd(-2.0, -0.7), rnd(0.4, 1.8)))
    te = T_FALL0 + rnd(0.6, 0.95)
    size = rnd(0.05, 0.09)
    src = BIN_AT + V((rnd(-0.2, 0.2), rnd(-0.2, 0.1), 0.0))
    fall = (vel.z + math.sqrt(vel.z ** 2 + 2 * GRAV * (src.z - size))) / GRAV
    rest_q = Quaternion(V((rnd(-1, 1), rnd(-1, 1), 1)).normalized(), rnd(0, 6))

    def ore(t, vel=vel, te=te, size=size, src=src, fall=fall, rest_q=rest_q):
        if t < te:
            return None
        s = t - te
        if s < fall:
            return ballistic(src, vel, s), Quaternion(Z, s * 9), size
        p = ballistic(src, vel, fall)
        p.z = size * 0.6
        return sunk(p, t), rest_q, size
    fx(C, "Ore_%d" % (i + 1), ORE, "Death", DIE_FRAMES, ore)

for i in range(10):                    # dust and smoke hanging over the wreck
    te = 1.7 + 0.2 * i
    life = 1.8
    drift = V((rnd(-0.3, 0.4), rnd(-0.2, 0.2), rnd(1.4, 2.0)))
    size = rnd(0.25, 0.4)
    src = FOOT + V((rnd(-0.6, 2.4), rnd(-0.5, 0.5), 0.2))

    def smoke(t, te=te, life=life, drift=drift, size=size, src=src):
        if t < te or t > te + life or te > FADE0:
            return None
        k = (t - te) / life
        s = size * (0.3 + 0.7 * sm(k * 1.6)) * (1 - ramp(k, 0.65, 1.0)) * fade(t)
        return src + drift * k, Quaternion(Z, k * 2 + te), s
    fx(C, "Smoke_%d" % (i + 1), SMOKE, "Death", DIE_FRAMES, smoke)

# ================================================================= finish
lc = bpy.context.view_layer.layer_collection.children
for name in FX_COLLS:
    lc[name].exclude = True
scene.frame_start, scene.frame_end = 0, DIE_FRAMES
scene.frame_set(0)
print("CLIPS Idle", IDLE_FRAMES, "Work", WORK_FRAMES, "Depleted", DEP_FRAMES, "Build", BUILD_FRAMES, "Die", DIE_FRAMES)
bpy.context.preferences.filepaths.save_version = 0
bpy.ops.wm.save_mainfile()
print("SAVED")
