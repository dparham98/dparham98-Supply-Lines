"""Stage 2 for Generator.blend: the clips Idle, Run, Build and Die, and the death effects.

Run right after build_generator.py, on the saved file:
  blender Generator.blend --background --python animate_generator.py

Run build_generator.py first each time: the saved file keeps the pose the clips leave at frame 0, and
a second run would take that as the rest pose.

It clears any animation and effects it made before, so it can be re-run. Everything is baked one key a
frame at 24 fps from the functions below, as NLA tracks named after their clip. The rest pose is the
finished generator standing still. The shared helpers follow the Barracks' animate_barracks.py.
"""
import bpy, bmesh, math, random
from math import sin, cos, radians, pi, exp
from mathutils import Vector as V, Matrix, Quaternion

FPS = 24
FX_COLLS = ("generator_death_fx",)
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
    if m.name.startswith("gen_fx_"):
        bpy.data.materials.remove(m)
bpy.context.view_layer.update()
OB = bpy.data.objects
# Rest poses at full size: a re-run starts from the saved file, whose glows are shrunk away.
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


ROOT_PARTS = ["plinth", "firebox", "boiler", "chimney", "hopper", "dynamo", "flywheel", "crosshead", "con_rod",
              "cylinder", "mast"]
PUFFS = ["puff_1", "puff_2", "puff_3"]
FW = HOME["flywheel"].translation.copy()
XH0 = HOME["crosshead"].translation.copy()
CRANK = 0.28                           # build_generator.py
ROD = 0.70


def engine(a):
    """Flywheel, crosshead and connecting rod at crank angle a (0 is the rest pose)."""
    pin = V((0, FW.y + CRANK * cos(a), FW.z + CRANK * sin(a)))
    yc = pin.y + math.sqrt(ROD * ROD - (pin.z - FW.z) ** 2)
    xh = V((XH0.x, yc, XH0.z))
    phi = math.atan2(-(pin.z - xh.z), -(pin.y - xh.y))
    return HOME["flywheel"] @ Rx(a), Tm(xh), Tm(xh) @ Rx(phi)


def bake_engine(clip, frames, angle):
    bake(OB["flywheel"], clip, frames, lambda t: engine(angle(t))[0])
    bake(OB["crosshead"], clip, frames, lambda t: engine(angle(t))[1])
    bake(OB["con_rod"], clip, frames, lambda t: engine(angle(t))[2])


def needle(deg):
    return HOME["gauge_needle"] @ Ry(radians(deg))


def cap(deg):
    return HOME["chimney_cap"] @ Rx(-radians(deg))


def valve(lift):
    return Tm(Z * 0.05 * lift) @ HOME["valve"] @ Ry(-radians(12) * lift)


def glow(name, s):
    return HOME[name] @ Sc(ONE * s) if s > 0.002 else hidden(name)


# ================================================================= Idle (cold, loops)
IDLE_FRAMES = 96                       # 4 s
IDLE_T = IDLE_FRAMES / FPS
W = 2 * pi / IDLE_T


def pilot_flicker(t):
    return 1.0 + 0.10 * sin(7 * W * t) + 0.06 * sin(13 * W * t + 1.0) + 0.04 * sin(23 * W * t + 2.0)


bake(OB["pilot"], "Idle", IDLE_FRAMES, lambda t: glow("pilot", pilot_flicker(t)))
bake(OB["fire_glow"], "Idle", IDLE_FRAMES, lambda t: hidden("fire_glow"))
bake(OB["coil_glow"], "Idle", IDLE_FRAMES, lambda t: hidden("coil_glow"))
bake(OB["arc"], "Idle", IDLE_FRAMES, lambda t: hidden("arc"))
for p in PUFFS:
    bake(OB[p], "Idle", IDLE_FRAMES, lambda t, p=p: hidden(p))
bake_engine("Idle", IDLE_FRAMES, lambda t: 0.0)
bake(OB["gauge_needle"], "Idle", IDLE_FRAMES, lambda t: needle(-70))
bake(OB["chimney_cap"], "Idle", IDLE_FRAMES, lambda t: cap(0))
bake(OB["valve"], "Idle", IDLE_FRAMES, lambda t: valve(0))

# ================================================================= Run (loops)
RUN_FRAMES = 48                        # 2 s
RUN_T = RUN_FRAMES / FPS
WR = 2 * pi / RUN_T
TURNS = 2                              # flywheel turns per loop: one a second


def puff(i):
    def fn(t):
        k = (2 * t / RUN_T + i / 3.0) % 1.0
        s = sm(k * 6) * (0.35 + 0.95 * k) * (1 - ramp(k, 0.55, 1.0))
        if s < 0.003:
            return hidden(PUFFS[i])
        drift = V((0.35 * k, 0.15 * k, 1.5 * k - 0.15 * k * k))
        return Tm(drift) @ HOME[PUFFS[i]] @ Sc(ONE * s)
    return fn


def coils(t):
    return 1.0 + 0.012 * sin(4 * WR * t)


def arc(t):
    on = sin(6 * WR * t) + 0.6 * sin(11 * WR * t + 1.3)
    return 1.0 + 0.25 * sin(17 * WR * t) if on > 0.2 else 0.0


def fire(t):
    return 1.0 + 0.05 * sin(5 * WR * t) + 0.03 * sin(9 * WR * t + 0.7)


def lift(t):
    """The safety valve blows once a loop."""
    return sm(lin(t / RUN_T, 0.55, 0.62)) * (1 - sm(lin(t / RUN_T, 0.78, 0.9)))


bake_engine("Run", RUN_FRAMES, lambda t: TURNS * WR * t)
bake(OB["pilot"], "Run", RUN_FRAMES, lambda t: HOME["pilot"])
bake(OB["fire_glow"], "Run", RUN_FRAMES, lambda t: HOME["fire_glow"] @ Sc((fire(t), 1.0, fire(t))))
bake(OB["coil_glow"], "Run", RUN_FRAMES, lambda t: glow("coil_glow", coils(t)))
bake(OB["arc"], "Run", RUN_FRAMES, lambda t: glow("arc", arc(t)))
for i, p in enumerate(PUFFS):
    bake(OB[p], "Run", RUN_FRAMES, puff(i))
bake(OB["gauge_needle"], "Run", RUN_FRAMES, lambda t: needle(48 + 4 * sin(3 * WR * t) + 6 * lift(t)))
bake(OB["chimney_cap"], "Run", RUN_FRAMES, lambda t: cap(22 + 10 * sin(4 * WR * t) + 6 * sin(TURNS * 2 * WR * t)))
bake(OB["valve"], "Run", RUN_FRAMES, lambda t: valve(lift(t)))

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


bake(OB["plinth"], "Build", BUILD_FRAMES, grow_z("plinth", 0.0, 0.1))
bake(OB["firebox"], "Build", BUILD_FRAMES, grow_z("firebox", 0.08, 0.3))
bake(OB["hopper"], "Build", BUILD_FRAMES, pop("hopper", 0.28, 0.38))
bake(OB["boiler"], "Build", BUILD_FRAMES, lower("boiler", 0.36, 0.5, 1.6))
bake(OB["chimney"], "Build", BUILD_FRAMES, grow_z("chimney", 0.5, 0.64))
bake(OB["dynamo"], "Build", BUILD_FRAMES, pop("dynamo", 0.6, 0.7))
bake(OB["flywheel"], "Build", BUILD_FRAMES, pop("flywheel", 0.68, 0.78))
bake(OB["cylinder"], "Build", BUILD_FRAMES, pop("cylinder", 0.74, 0.82))
bake(OB["crosshead"], "Build", BUILD_FRAMES, pop("crosshead", 0.8, 0.86))
bake(OB["con_rod"], "Build", BUILD_FRAMES, pop("con_rod", 0.82, 0.88))
bake(OB["mast"], "Build", BUILD_FRAMES, grow_z("mast", 0.86, 0.97))
bake(OB["pilot"], "Build", BUILD_FRAMES, lambda t: HOME["pilot"] if t / BUILD_T > 0.97 else hidden("pilot"))
for n in ["fire_glow", "coil_glow", "arc"] + PUFFS:
    bake(OB[n], "Build", BUILD_FRAMES, lambda t, n=n: hidden(n))
bake(OB["gauge_needle"], "Build", BUILD_FRAMES, lambda t: needle(-70))
bake(OB["chimney_cap"], "Build", BUILD_FRAMES, lambda t: cap(0))
bake(OB["valve"], "Build", BUILD_FRAMES, lambda t: valve(0))

# ================================================================= Die
DIE_END = 5.0
DIE_FRAMES = int(DIE_END * FPS)
SINK0 = 3.7
SINK = 4.8
T_BURST = 0.35                         # the boiler bursts
BOIL = HOME["boiler"].translation.copy()
CHIM = HOME["chimney"].translation.copy()


def sink(t):
    return Tm(-Z * SINK * ramp(t, SINK0, DIE_END))


def shake(t, amp, ph):
    if t > 1.6:
        return Matrix.Identity(4)
    a = amp * exp(-t * 2.5) * min(t / 0.06, 1.0)      # from rest: the exported rest pose is Die's frame 0
    return Tm((a * sin(t * 47 + ph), a * sin(t * 53 + ph * 2), 0.5 * a * sin(t * 61 + ph * 3)))


def hop(t, t0, t1, h):
    """Thrown up at t0, back down by t1."""
    if t < t0 or t > t1:
        return 0.0
    k = (t - t0) / (t1 - t0)
    return 4 * h * k * (1 - k)


def boiler_die(t):
    k = sm(lin(t, T_BURST, T_BURST + 0.55))
    up = hop(t, T_BURST, T_BURST + 0.55, 0.7)
    R = Ry(radians(-16) * k) @ Rx(radians(9) * k)
    return sink(t) @ shake(t, 0.03, 0.4) @ Tm(Z * (up - 0.35 * k) + X * 0.12 * k) @ about(BOIL, R) @ HOME["boiler"]


def chimney_die(t):
    k = lin(t, T_BURST + 0.05, T_BURST + 1.15)
    fall = k * k                       # gathers speed as it goes over
    bounce = 0.06 * exp(-(t - T_BURST - 1.15) * 8) * abs(sin((t - T_BURST - 1.15) * 18)) if k >= 1 else 0.0
    R = Ry(radians(-96) * fall + bounce) @ Rx(radians(-10) * fall)
    drop = Tm(-Z * 1.6 * sm(lin(t, T_BURST, T_BURST + 0.9)) + X * -0.2 * sm(k))
    return sink(t) @ drop @ about(CHIM, R) @ HOME["chimney"]


def flywheel_die(t):
    """Breaks loose: rolls off toward the front, wobbles and falls flat."""
    t0 = T_BURST + 0.2
    if t < t0:
        return engine(0.0)[0] if t < 0.01 else shake(t, 0.02, 1.0) @ engine(6.0 * t)[0]
    s = t - t0
    roll = min(s, 1.1)
    dist = 2.4 * roll - 0.9 * roll * roll          # slowing as it rolls
    spin = dist / 0.72
    k = sm(lin(s, 0.8, 1.5))
    pos = FW + V((0.15 * k, -dist, -0.15 * sm(lin(s, 0.3, 0.6)) - 0.72 * k))
    a0 = 6.0 * t0
    return sink(t) @ Tm(pos) @ Ry(radians(-88) * k) @ Rx(a0 + spin) @ Tm(-FW) @ HOME["flywheel"]


def rod_die(name):
    def fn(t):
        if t < T_BURST + 0.2:
            return shake(t, 0.02, 2.0) @ (engine(6.0 * t)[1] if name == "crosshead" else engine(6.0 * t)[2])
        k = sm(lin(t, T_BURST + 0.2, T_BURST + 0.7))
        base = engine(6.0 * (T_BURST + 0.2))[1 if name == "crosshead" else 2]
        p = base.translation
        return sink(t) @ Tm(-Z * (p.z - 0.12) * k + Y * -0.3 * k) @ about(p, Rx(radians(-35) * k) @ Rz(radians(20) * k)) @ base
    return fn


def lean(name, pivot, R_end, t0, t1, drop=0.0):
    def fn(t):
        k = sm(lin(t, t0, t1))
        return sink(t) @ shake(t, 0.025, len(name)) @ Tm(-Z * drop * k) @ about(pivot, R_end(k)) @ HOME[name]
    return fn


bake(OB["boiler"], "Die", DIE_FRAMES, boiler_die)
bake(OB["chimney"], "Die", DIE_FRAMES, chimney_die)
bake(OB["flywheel"], "Die", DIE_FRAMES, flywheel_die)
bake(OB["crosshead"], "Die", DIE_FRAMES, rod_die("crosshead"))
bake(OB["con_rod"], "Die", DIE_FRAMES, rod_die("con_rod"))
HOP_FOOT = HOME["hopper"].translation + V((-0.3, 0, 0))
bake(OB["hopper"], "Die", DIE_FRAMES, lean("hopper", HOP_FOOT, lambda k: Ry(radians(-62) * k), T_BURST + 0.1, T_BURST + 0.9))
MAST_FOOT = HOME["mast"].translation.copy()
bake(OB["mast"], "Die", DIE_FRAMES, lean("mast", MAST_FOOT, lambda k: Rx(radians(-82) * k ** 2) @ Ry(radians(20) * k), T_BURST + 0.3, T_BURST + 1.4))
DYN_FOOT = HOME["dynamo"].translation * V((1, 1, 0))
bake(OB["dynamo"], "Die", DIE_FRAMES, lean("dynamo", DYN_FOOT + X * 0.3, lambda k: Ry(radians(14) * k), T_BURST + 0.1, T_BURST + 0.5, 0.15))
CYL_FOOT = HOME["cylinder"].translation * V((1, 1, 0))
bake(OB["cylinder"], "Die", DIE_FRAMES, lean("cylinder", CYL_FOOT + X * 0.15, lambda k: Ry(radians(40) * k) @ Rx(radians(-12) * k), T_BURST + 0.25, T_BURST + 0.75, 0.1))
FB_FOOT = HOME["firebox"].translation.copy()
bake(OB["firebox"], "Die", DIE_FRAMES, lean("firebox", FB_FOOT, lambda k: Rx(radians(-5) * k) @ Ry(radians(4) * k), T_BURST, T_BURST + 0.4, 0.08))
bake(OB["plinth"], "Die", DIE_FRAMES, lambda t: sink(t) @ shake(t, 0.012, 5.0) @ HOME["plinth"])
bake(OB["pilot"], "Die", DIE_FRAMES, lambda t: HOME["pilot"] if t < T_BURST else hidden("pilot"))
bake(OB["fire_glow"], "Die", DIE_FRAMES,
     lambda t: HOME["fire_glow"] @ Sc(ONE * (1.0 + 0.5 * exp(-((t - T_BURST) / 0.15) ** 2)) * (1 - 0.5 * ramp(t, 1.5, 3.6))))
bake(OB["coil_glow"], "Die", DIE_FRAMES, lambda t: HOME["coil_glow"] if t < T_BURST + 0.25 else hidden("coil_glow"))
bake(OB["arc"], "Die", DIE_FRAMES, lambda t: glow("arc", (1.4 + 0.5 * sin(t * 90)) if T_BURST - 0.15 < t < T_BURST + 0.5 and sin(t * 41) > -0.3 else 0.0))
for p in PUFFS:
    bake(OB[p], "Die", DIE_FRAMES, lambda t, p=p: hidden(p))
bake(OB["gauge_needle"], "Die", DIE_FRAMES, lambda t: needle(min(t / T_BURST, 1.0) * 130 - 30 * ramp(t, T_BURST, T_BURST + 0.6)))
bake(OB["chimney_cap"], "Die", DIE_FRAMES, lambda t: cap(min(t / 0.8, 1.0) * 95))
bake(OB["valve"], "Die", DIE_FRAMES, lambda t: valve(min(t / T_BURST, 1.0)))

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


M_DUST = fx_material("gen_fx_dust", (0.24, 0.20, 0.16), 1.0, None, 0.0, 0.7)
M_SPARK = fx_material("gen_fx_spark", (0, 0, 0), 0.8, (1.0, 0.62, 0.18), 5.0)
M_FLASH = fx_material("gen_fx_flash", (0, 0, 0), 0.8, (1.0, 0.8, 0.4), 3.2)
M_FIRE = fx_material("gen_fx_fire", (0, 0, 0), 0.8, (1.0, 0.2, 0.02), 1.3)
M_SMOKE = fx_material("gen_fx_smoke", (0.05, 0.045, 0.045), 1.0)
M_OIL = fx_material("gen_fx_oil", (0.012, 0.011, 0.016), 0.07)
M_STEAM = fx_material("gen_fx_steam", (0.70, 0.70, 0.68), 1.0, None, 0.0, 0.8)
M_ARC = fx_material("gen_fx_arc", (0, 0, 0), 0.8, (0.55, 0.80, 1.0), 6.0)
M_COAL = bpy.data.materials["gen_coal"]
M_SCRAP = bpy.data.materials["gen_gunmetal"]
M_SCRAP2 = bpy.data.materials["gen_rust"]


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


C = collection("generator_death_fx")
PUFF = ico_mesh("fxm_smoke", M_SMOKE, 2, 0.1, True)
STEAM = ico_mesh("fxm_steam", M_STEAM, 2, 0.12, True)
SHARD = shard_mesh("fxm_shard", M_SPARK)
BOLT = shard_mesh("fxm_bolt", M_ARC)
SCRAP = plate_mesh("fxm_scrap", [M_SCRAP, M_SCRAP2])
FLAME = flame_mesh("fxm_flame", M_FIRE)
POOL = disc_mesh("fxm_pool", M_OIL)
COAL = ico_mesh("fxm_coal", M_COAL, 0, 0.25, False, 1.0)
CORE = ico_mesh("fxm_core", M_FLASH, 1, 0.0, False, 0.45)
FADE0, FADE1 = SINK0 + 0.1, DIE_END - 0.1
DYN_AT = HOME["dynamo"].translation + V((-0.05, -0.05, 0.6))
FIRE_AT = HOME["firebox"].translation + V((0.0, -0.1, 0.3))
HOP_AT = HOME["hopper"].translation + V((-0.6, 0, 0.1))


def fade(t):
    return 1 - ramp(t, FADE0, FADE1)


def sunk(p, t):
    return V(p) - Z * SINK * ramp(t, SINK0, DIE_END)


def burning(t):
    return ramp(t, T_BURST + 0.3, T_BURST + 0.8) * fade(t)


def flash(t):
    burst = 1.6 * exp(-((t - T_BURST - 0.05) / 0.12) ** 2) if t > T_BURST - 0.1 else 0.0
    glow = burning(t) * (0.2 + 0.05 * sin(t * 23) + 0.03 * sin(t * 37))      # inside the firebox
    s = max(burst, glow)
    at = BOIL + V((0, -0.3, 0.2)) if t < 0.9 else sunk(FIRE_AT, t)
    return at, None, s


# The flash mesh's scale drives the light in the game, so it comes first in the collection.
fx(C, "Flash", CORE, "Death", DIE_FRAMES, flash)

for i in range(16):                    # the boiler bursts
    vel = V((rnd(-4.0, 4.0), rnd(-4.0, 3.0), rnd(2.0, 6.0)))
    life = rnd(0.3, 0.6)
    size = rnd(0.16, 0.28)
    te = T_BURST + rnd(-0.02, 0.06)

    def spark(t, vel=vel, life=life, size=size, te=te):
        if t < te or t > te + life:
            return None
        s = t - te
        v_now = vel + V((0, 0, -GRAV * s))
        return ballistic(BOIL + V((0, 0, 0.3)), vel, s), v_now.to_track_quat('Y', 'Z'), size * (1 - s / life)
    fx(C, "Burst_Spark_%d" % (i + 1), SHARD, "Death", DIE_FRAMES, spark)

for i in range(10):                    # blue sparks off the dynamo as it shorts
    vel = V((rnd(-2.5, 2.5), rnd(-2.5, 2.5), rnd(1.5, 4.0)))
    life = rnd(0.2, 0.4)
    size = rnd(0.12, 0.2)
    te = T_BURST - 0.1 + i * 0.06

    def arc_spark(t, vel=vel, life=life, size=size, te=te):
        if t < te or t > te + life:
            return None
        s = t - te
        v_now = vel + V((0, 0, -GRAV * s))
        return ballistic(DYN_AT, vel, s), v_now.to_track_quat('Y', 'Z'), size * (1 - s / life)
    fx(C, "Arc_Spark_%d" % (i + 1), BOLT, "Death", DIE_FRAMES, arc_spark)

for i in range(8):                     # boiler plates thrown out, then lying where they land
    src = BOIL + V((rnd(-0.4, 0.4), rnd(-0.6, 0.6), rnd(0.0, 0.4)))
    out = V((src.x + rnd(-0.5, 0.5), src.y + rnd(-0.5, 0.5), 0)).normalized()
    vel = out * rnd(1.0, 2.2) + V((0, 0, rnd(2.5, 4.5)))
    te = T_BURST + rnd(0.0, 0.05)
    size = rnd(0.25, 0.45)
    spin_ax = V((rnd(-1, 1), rnd(-1, 1), rnd(-1, 1))).normalized()
    spin = rnd(8, 16)
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

for i in range(10):                    # a burst of steam from the boiler
    d = V((rnd(-1, 1), rnd(-1, 1), rnd(0.3, 1.2))).normalized()
    size = rnd(0.35, 0.55)
    te = T_BURST + rnd(0.0, 0.12)

    def steam(t, d=d, size=size, te=te):
        if t < te or t > te + 1.6:
            return None
        k = (t - te) / 1.6
        p = BOIL + d * (0.4 + 1.6 * (1 - (1 - k) ** 2.5)) + Z * 0.8 * k
        return p, Quaternion(Z, k * 3), size * sm(k * 6) * (1 - ramp(k, 0.4, 1.0))
    fx(C, "Steam_%d" % (i + 1), STEAM, "Death", DIE_FRAMES, steam)

for i in range(14):                    # coal spilled from the hopper as it tips
    vel = V((rnd(-1.8, -0.6), rnd(-0.6, 0.6), rnd(0.5, 2.0)))
    te = T_BURST + rnd(0.3, 0.7)
    size = rnd(0.05, 0.09)
    src = HOME["hopper"].translation + V((-0.3, rnd(-0.3, 0.3), 1.4))
    fall = (vel.z + math.sqrt(vel.z ** 2 + 2 * GRAV * (src.z - size))) / GRAV
    rest_q = Quaternion(V((rnd(-1, 1), rnd(-1, 1), 1)).normalized(), rnd(0, 6))

    def coal(t, vel=vel, te=te, size=size, src=src, fall=fall, rest_q=rest_q):
        if t < te:
            return None
        s = t - te
        if s < fall:
            return ballistic(src, vel, s), Quaternion(Z, s * 9), size
        p = ballistic(src, vel, fall)
        p.z = size * 0.6
        return sunk(p, t), rest_q, size
    fx(C, "Coal_%d" % (i + 1), COAL, "Death", DIE_FRAMES, coal)

for i in range(5):                     # fire licking out of the burst boiler
    off = V((rnd(-0.25, 0.25), rnd(-0.45, 0.45), 0.0))
    w, h, rate, ph = rnd(0.07, 0.11), rnd(0.5, 0.8), rnd(12, 20), rnd(0, 6)

    def flame(t, off=off, w=w, h=h, rate=rate, ph=ph):
        b = burning(t)
        if b <= 0.0:
            return None
        lick = 0.75 + 0.25 * sin(t * rate + ph)
        return (sunk(BOIL + V((0.1, 0.0, 0.12)) + off, t), Quaternion(Y, 0.15 * sin(t * rate * 0.6 + ph)),
                V((w * b, w * b, h * b * lick)))
    fx(C, "Fire_%d" % (i + 1), FLAME, "Death", DIE_FRAMES, flame)

for i in range(12):                    # smoke from the wreck
    te = 0.9 + 0.22 * i
    life = 1.8
    drift = V((rnd(-0.3, 0.4), rnd(-0.2, 0.2), rnd(2.0, 2.6)))
    size = rnd(0.22, 0.36)
    src = BOIL + V((rnd(-0.3, 0.3), rnd(-0.4, 0.4), 0.3))

    def smoke(t, te=te, life=life, drift=drift, size=size, src=src):
        if t < te or t > te + life or te > FADE0:
            return None
        k = (t - te) / life
        s = size * (0.3 + 0.7 * sm(k * 1.6)) * (1 - ramp(k, 0.65, 1.0)) * fade(t)
        return src + drift * k, Quaternion(Z, k * 2 + te), s
    fx(C, "Smoke_%d" % (i + 1), PUFF, "Death", DIE_FRAMES, smoke)

POOL_AT = V((HOME["firebox"].translation.x + 0.4, -0.9, 0.165))


def pool(t):
    if t < T_BURST + 0.1:
        return None
    grow = 1 - (1 - min((t - T_BURST - 0.1) / 2.4, 1.0)) ** 2.5
    r = 0.9 * grow * fade(t)
    return sunk(POOL_AT, t), Quaternion(Z, 0.7), V((r * 1.2, r * 0.7, 1.0))


fx(C, "Oil_Pool", POOL, "Death", DIE_FRAMES, pool)

# ================================================================= finish
lc = bpy.context.view_layer.layer_collection.children
for name in FX_COLLS:
    lc[name].exclude = True
scene.frame_start, scene.frame_end = 0, DIE_FRAMES
scene.frame_set(0)
print("CLIPS Idle", IDLE_FRAMES, "Run", RUN_FRAMES, "Build", BUILD_FRAMES, "Die", DIE_FRAMES)
bpy.context.preferences.filepaths.save_version = 0
bpy.ops.wm.save_mainfile()
print("SAVED")
