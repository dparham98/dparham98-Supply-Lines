"""Stage 2 for Barracks.blend: the clips Idle, Build, Print and Die, and the death effects.

Run right after build_barracks.py, on the saved file:
  blender Barracks.blend --background --python animate_barracks.py

Run build_barracks.py first each time: the saved file keeps the pose the clips leave at frame 0, and a
second run would take that as the rest pose.

It clears any animation and effects it made before, so it can be re-run. Everything is baked one key a
frame at 24 fps from the functions below, as NLA tracks named after their clip. The rest pose stays
the finished hall with the door closed and the cradle empty.
"""
import bpy, bmesh, math, random
from math import sin, cos, radians, pi, exp
from mathutils import Vector as V, Matrix, Quaternion

FPS = 24
FX_COLLS = ("barracks_death_fx",)
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
    if m.name.startswith("bar_fx_"):
        bpy.data.materials.remove(m)
bpy.context.view_layer.update()
OB = bpy.data.objects
# Rest poses at full size: a re-run starts from the saved file, whose figure is shrunk away.
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


VENTS = ["vent_%02d" % (i + 1) for i in range(4)]
FANS = ["vent_fan_%02d" % (i + 1) for i in range(4)]
PARTS = ["plinth", "frame", "walls", "roof", "bay_door", "cradle", "tank", "mast"] + VENTS

# ================================================================= Idle (loops)
IDLE_FRAMES = 96                       # 4 s
IDLE_T = IDLE_FRAMES / FPS
for i, fan in enumerate(FANS):
    turns = (3, 4, 4, 3)[i] * (1 if i % 2 == 0 else -1)
    bake(OB[fan], "Idle", IDLE_FRAMES, lambda t, n=turns, f=fan: HOME[f] @ Rz(2 * pi * n * t / IDLE_T))


def blink(t):
    k = t % 2.0
    on = ramp(k, 0.0, 0.06) * (1 - ramp(k, 0.4, 0.46))
    return HOME["mast_light"] @ Sc(V((1, 1, 1)) * max(on, 0.001))


bake(OB["mast_light"], "Idle", IDLE_FRAMES, blink)
bake(OB["print_head"], "Idle", IDLE_FRAMES,
     lambda t: Tm(Z * 0.03 * sin(2 * pi * t / IDLE_T)) @ HOME["print_head"])
# Idle also puts the door and the cradle back, in case a print was cut short.
bake(OB["print_figure"], "Idle", IDLE_FRAMES, lambda t: hidden("print_figure"))
bake(OB["bay_door"], "Idle", IDLE_FRAMES, lambda t: HOME["bay_door"])

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


def lower_roof(t):
    p = t / BUILD_T
    k = lin(p, 0.56, 0.6)
    if k <= 0:
        return hidden("roof")
    d = 1 - ramp(p, 0.6, 0.72)
    return Tm(Z * 2.4 * d) @ HOME["roof"] @ Sc(ONE * sm(k))


bake(OB["plinth"], "Build", BUILD_FRAMES, grow_z("plinth", 0.0, 0.1))
bake(OB["frame"], "Build", BUILD_FRAMES, grow_z("frame", 0.08, 0.3))
bake(OB["cradle"], "Build", BUILD_FRAMES, pop("cradle", 0.22, 0.34))
bake(OB["walls"], "Build", BUILD_FRAMES, grow_z("walls", 0.28, 0.56))
bake(OB["roof"], "Build", BUILD_FRAMES, lower_roof)
bake(OB["bay_door"], "Build", BUILD_FRAMES, grow_z("bay_door", 0.66, 0.74))
for i, v in enumerate(VENTS):
    bake(OB[v], "Build", BUILD_FRAMES, pop(v, 0.74 + 0.03 * i, 0.8 + 0.03 * i))
bake(OB["tank"], "Build", BUILD_FRAMES, pop("tank", 0.8, 0.88))
bake(OB["mast"], "Build", BUILD_FRAMES, grow_z("mast", 0.86, 1.0))
bake(OB["print_figure"], "Build", BUILD_FRAMES, lambda t: hidden("print_figure"))

# ================================================================= Print (scaled to the print time)
# The game plays 0..SPAWN_AT while the unit prints, the unit appears at the exit at SPAWN_AT, and the
# rest (the door closing) plays out at normal speed.
PRINT_FRAMES = 120                     # 5 s
SPAWN_AT = 4.0
HEAD_TOP = 1.85
FIG_H = 1.86
CR = HOME["cradle"].translation        # cradle, in world space
FIG_HOME = HOME["print_figure"].translation   # feet, in cradle space
DOOR_LOCAL = V((0.0, -2.4, 0.2)) - CR - V((0, 0, 0))
DOOR_LOCAL.z = FIG_HOME.z - 0.18       # the plinth top, in cradle space
WALK = DOOR_LOCAL - FIG_HOME
YAW = math.atan2(WALK.x, -WALK.y)


def head(t):
    if t < 2.6:
        h = HEAD_TOP * sm(t / 2.6) * 0.15 + HEAD_TOP * 0.85 * (t / 2.6)
    else:
        h = HEAD_TOP * (1 - ramp(t, 4.0, 4.6))
    return Tm(Z * h) @ HOME["print_head"]


def figure(t):
    if t < 0.05 or t >= SPAWN_AT:
        return hidden("print_figure")
    if t < 2.6:
        h = min(1.0, (head(t).translation.z - HOME["print_head"].translation.z) / FIG_H + 0.02)
        return HOME["print_figure"] @ Sc((1, 1, max(h, 0.001)))
    k = ramp(t, 3.15, SPAWN_AT)
    turn = ramp(t, 2.95, 3.25)
    bob = 0.035 * abs(sin((t - 3.15) * pi * 3.2)) if 3.15 < t < SPAWN_AT else 0.0
    return Tm(FIG_HOME + WALK * k + Z * bob) @ Rz(YAW * turn)


def door(t):
    up = ramp(t, 2.85, 3.25) * (1 - ramp(t, SPAWN_AT + 0.05, SPAWN_AT + 0.6))
    return HOME["bay_door"] @ Sc((1, 1, 1 - 0.94 * up))


bake(OB["print_head"], "Print", PRINT_FRAMES, head)
bake(OB["print_figure"], "Print", PRINT_FRAMES, figure)
bake(OB["bay_door"], "Print", PRINT_FRAMES, door)
for i, fan in enumerate(FANS):         # the fans run harder while printing
    bake(OB[fan], "Print", PRINT_FRAMES,
         lambda t, f=fan, d=(1 if i % 2 == 0 else -1): HOME[f] @ Rz(d * 2 * pi * (1.6 * t + 0.25 * t * t)))

# ================================================================= Die
DIE_END = 5.0
DIE_FRAMES = int(DIE_END * FPS)
SINK0 = 3.7
SINK = 3.7
ROOF_DROP = 1.7
T_BURST = 0.3                          # the tank goes first
T_ROOF0, T_ROOF1 = 0.5, 1.05           # the roof caves in


def sink(t):
    return Tm(-Z * SINK * ramp(t, SINK0, DIE_END))


def shake(t, amp, ph):
    if t > 1.6:
        return Matrix.Identity(4)
    a = amp * exp(-t * 2.5) * min(t / 0.06, 1.0)      # from rest: the exported rest pose is Die's frame 0
    return Tm((a * sin(t * 47 + ph), a * sin(t * 53 + ph * 2), 0.5 * a * sin(t * 61 + ph * 3)))


def roof_fall(t):
    """Drop of the deck, with a small bounce where it lands."""
    if t < T_ROOF0:
        return 0.0
    if t < T_ROOF1:
        return ROOF_DROP * ((t - T_ROOF0) / (T_ROOF1 - T_ROOF0)) ** 2
    return ROOF_DROP - 0.09 * exp(-(t - T_ROOF1) * 7) * abs(sin((t - T_ROOF1) * 15))


def about(pivot, R):
    return Tm(pivot) @ R @ Tm(-V(pivot))


def roof_die(t):
    k = sm(lin(t, T_ROOF0, T_ROOF1 + 0.1))
    tilt = Rx(radians(-9) * k) @ Ry(radians(6) * k)
    return sink(t) @ Tm(-Z * roof_fall(t)) @ about((0.0, 0.0, 3.15), tilt) @ HOME["roof"]


def walls_die(t):
    k = sm(lin(t, 0.55, 1.5))
    return sink(t) @ shake(t, 0.03, 1.0) @ Tm(-Z * 0.3 * k) @ about((0, 2.7, 0), Rx(radians(-4) * k) @ Ry(radians(3) * k)) @ HOME["walls"]


def frame_die(t):
    k = sm(lin(t, 0.6, 1.4))
    return sink(t) @ shake(t, 0.035, 2.0) @ Tm(-Z * 0.42 * k) @ about((0, -2.7, 0), Rx(radians(3) * k)) @ HOME["frame"]


def plinth_die(t):
    return sink(t) @ shake(t, 0.02, 3.0) @ HOME["plinth"]


def door_die(t):
    a = sm(lin(t, 0.45, 0.75))
    b = lin(t, 0.75, 1.1) ** 2
    hinge = HOME["bay_door"].translation
    swing = Rx(radians(-55) * a - radians(30) * b)
    drop = Tm((0, -0.25 * b, -(hinge.z - 0.3) * b))
    return sink(t) @ drop @ Tm(hinge) @ swing @ Tm(-hinge) @ HOME["bay_door"]


def tank_die(t):
    bulge = 1 + 0.18 * exp(-((t - T_BURST) / 0.08) ** 2)
    k = sm(lin(t, T_BURST, T_BURST + 0.6))
    c = HOME["tank"].translation
    return (sink(t) @ Tm((-0.4 * k, 0.1 * k, -0.28 * k)) @ Tm(c) @ Ry(radians(-38) * k) @ Rz(radians(9) * k)
            @ Sc((bulge, 1 + (bulge - 1) * 0.4, bulge)) @ Tm(-c) @ HOME["tank"])


def vent_die(i):
    name = VENTS[i]
    c = HOME[name].translation
    ax = V((random.uniform(-1, 1), random.uniform(-1, 1), 0)).normalized()
    ang = radians(random.uniform(55, 110))
    t0 = T_ROOF1 - 0.15 + 0.07 * i
    slide = V((ax.y, -ax.x, 0)) * random.uniform(0.15, 0.4)

    def fn(t):
        k = sm(lin(t, t0, t0 + 0.45))
        R = Matrix.Rotation(ang * k, 4, ax)
        return sink(t) @ Tm(-Z * roof_fall(t) + slide * k - Z * 0.1 * k) @ about(c, R) @ HOME[name]
    return fn


MAST_LEAN = radians(52)


def mast_die(t):
    k = lin(t, 1.0, 1.75) ** 2
    if t > 1.75:
        k = 1 - 0.05 * exp(-(t - 1.75) * 6) * abs(sin((t - 1.75) * 14))
    c = HOME["mast"].translation
    return sink(t) @ Tm(-Z * roof_fall(t)) @ about(c, Ry(-MAST_LEAN * k) @ Rx(radians(8) * k)) @ HOME["mast"]


def cradle_die(t):
    k = sm(lin(t, 0.9, 1.4))
    c = HOME["cradle"].translation
    return sink(t) @ Tm(-Z * 0.15 * k) @ about(c, Rx(radians(12) * k)) @ HOME["cradle"]


bake(OB["roof"], "Die", DIE_FRAMES, roof_die)
bake(OB["walls"], "Die", DIE_FRAMES, walls_die)
bake(OB["frame"], "Die", DIE_FRAMES, frame_die)
bake(OB["plinth"], "Die", DIE_FRAMES, plinth_die)
bake(OB["bay_door"], "Die", DIE_FRAMES, door_die)
bake(OB["tank"], "Die", DIE_FRAMES, tank_die)
for i in range(4):
    bake(OB[VENTS[i]], "Die", DIE_FRAMES, vent_die(i))
bake(OB["mast"], "Die", DIE_FRAMES, mast_die)
bake(OB["cradle"], "Die", DIE_FRAMES, cradle_die)
bake(OB["skylight"], "Die", DIE_FRAMES,
     lambda t: HOME["skylight"] if t < T_ROOF0 + 0.05 else Tm(HOME["skylight"].translation) @ Sc(NIL))
bake(OB["mast_light"], "Die", DIE_FRAMES,
     lambda t: HOME["mast_light"] @ Sc(ONE * (1.0 if (t < 1.0 and (t * 9) % 1 < 0.6) else 0.001)))
bake(OB["print_figure"], "Die", DIE_FRAMES, lambda t: hidden("print_figure"))
for i, fan in enumerate(FANS):
    bake(OB[fan], "Die", DIE_FRAMES,
         lambda t, f=fan, d=(1 if i % 2 == 0 else -1): HOME[f] @ Rz(d * 2 * pi * 0.8 * (1 - exp(-t * 1.2)) / 1.2))

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


M_DUST = fx_material("bar_fx_dust", (0.24, 0.20, 0.16), 1.0, None, 0.0, 0.7)
M_SPARK = fx_material("bar_fx_spark", (0, 0, 0), 0.8, (1.0, 0.62, 0.18), 5.0)
M_FLASH = fx_material("bar_fx_flash", (0, 0, 0), 0.8, (1.0, 0.8, 0.4), 3.2)
M_FIRE = fx_material("bar_fx_fire", (0, 0, 0), 0.8, (1.0, 0.2, 0.02), 1.3)
M_CORE = fx_material("bar_fx_core", (0, 0, 0), 0.8, (1.0, 0.5, 0.08), 2.0)
M_SMOKE = fx_material("bar_fx_smoke", (0.05, 0.045, 0.045), 1.0)
M_OIL = fx_material("bar_fx_oil", (0.012, 0.011, 0.016), 0.07)
M_GLASS = fx_material("bar_fx_glass", (0.55, 0.35, 0.12), 0.1, (1.0, 0.45, 0.1), 0.6)
M_SCRAP = bpy.data.materials["bar_gunmetal"]
M_SCRAP2 = bpy.data.materials["bar_rust"]


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


C = collection("barracks_death_fx")
PUFF = ico_mesh("fxm_smoke", M_SMOKE, 2, 0.1, True)
DUST = ico_mesh("fxm_dust", M_DUST, 1, 0.14, True)
SHARD = shard_mesh("fxm_shard", M_SPARK)
GLASS = shard_mesh("fxm_glass", M_GLASS)
SCRAP = plate_mesh("fxm_scrap", [M_SCRAP, M_SCRAP2])
FLAME = flame_mesh("fxm_flame", M_FIRE)
FLAME_CORE = flame_mesh("fxm_flame_core", M_CORE)
POOL = disc_mesh("fxm_pool", M_OIL)
CORE = ico_mesh("fxm_core", M_FLASH, 1, 0.0, False, 0.4)
FADE0, FADE1 = SINK0 + 0.1, DIE_END - 0.1
TANK_AT = HOME["tank"].translation.copy()
HOLE = V((HOME["cradle"].translation.x + 0.6, -0.1, 3.15 - ROOF_DROP + 0.25))    # the caved-in deck


def fade(t):
    return 1 - ramp(t, FADE0, FADE1)


def sunk(p, t):
    return V(p) - Z * SINK * ramp(t, SINK0, DIE_END)


def burning(t):
    return ramp(t, 1.0, 1.5) * fade(t)


def flash(t):
    burst = 1.4 * exp(-((t - T_BURST - 0.05) / 0.12) ** 2) if t > T_BURST - 0.1 else 0.0
    roof = 0.8 * exp(-((t - T_ROOF1) / 0.15) ** 2)
    glow = burning(t) * (0.35 + 0.08 * sin(t * 23) + 0.05 * sin(t * 37))
    s = max(burst, roof, glow)
    at = TANK_AT + V((-0.45, 0, 0.3)) if t < 0.8 else sunk(HOLE + Z * 0.4, t)
    return at, None, s


# The flash mesh's scale drives the light in the game, so it comes first in the collection.
fx(C, "Flash", CORE, "Death", DIE_FRAMES, flash)

for i in range(16):                    # the tank bursts
    vel = V((rnd(-5.0, -1.5), rnd(-3.0, 3.0), rnd(1.5, 5.5)))
    life = rnd(0.3, 0.6)
    size = rnd(0.18, 0.32)
    te = T_BURST + rnd(-0.02, 0.06)

    def spark(t, vel=vel, life=life, size=size, te=te):
        if t < te or t > te + life:
            return None
        s = t - te
        v_now = vel + V((0, 0, -GRAV * s))
        return ballistic(TANK_AT + V((-0.3, 0, 0.1)), vel, s), v_now.to_track_quat('Y', 'Z'), size * (1 - s / life)
    fx(C, "Burst_Spark_%d" % (i + 1), SHARD, "Death", DIE_FRAMES, spark)

for i in range(10):                    # scrap plates thrown out, then lying where they land
    src = V((rnd(-2.2, 2.2), rnd(-2.4, 2.4), rnd(2.4, 3.2)))
    out = V((src.x, src.y, 0)).normalized()
    vel = out * rnd(1.5, 3.5) + V((0, 0, rnd(2.0, 4.5)))
    te = rnd(T_ROOF0, T_ROOF1 + 0.1)
    size = rnd(0.35, 0.7)
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

for i in range(12):                    # the skylight shatters
    src = V((rnd(-1.35, -0.1), rnd(-1.7, 1.3), rnd(3.2, 3.8)))
    vel = V((rnd(-1.5, 1.5), rnd(-1.5, 1.5), rnd(0.5, 2.5)))
    te = T_ROOF0 + rnd(0.0, 0.08)
    size = rnd(0.15, 0.3)
    fall = (vel.z + math.sqrt(vel.z ** 2 + 2 * GRAV * (src.z - 1.0))) / GRAV

    def glass(t, src=src, vel=vel, te=te, size=size, fall=fall):
        if t < te or t > te + fall:
            return None
        s = t - te
        return ballistic(src, vel, s), Quaternion(V((1, 1, 0)).normalized(), 12 * s), size
    fx(C, "Glass_%d" % (i + 1), GLASS, "Death", DIE_FRAMES, glass)

for i in range(10):                    # a dust ring where the roof lands
    a = 2 * pi * i / 10 + rnd(-0.2, 0.2)
    d = V((cos(a), sin(a), 0))
    size = rnd(0.7, 1.1)

    def dust(t, d=d, size=size):
        if t < T_ROOF1 - 0.05 or t > T_ROOF1 + 1.6:
            return None
        k = (t - T_ROOF1 + 0.05) / 1.65
        p = V((0, 0, 0.4)) + d * (2.4 + 1.8 * (1 - (1 - k) ** 2.5)) + Z * 0.8 * k
        return p, None, size * sm(k * 4) * (1 - ramp(k, 0.45, 1.0))
    fx(C, "Dust_%d" % (i + 1), DUST, "Death", DIE_FRAMES, dust)

for i in range(6):                     # fire in the caved-in hall
    off = V((rnd(-0.9, 0.9), rnd(-1.4, 1.4), rnd(-0.05, 0.05)))
    w, h, rate, ph = rnd(0.18, 0.3), rnd(0.8, 1.4), rnd(12, 20), rnd(0, 6)
    core = i < 2

    def flame(t, off=off, w=w, h=h, rate=rate, ph=ph, core=core):
        b = burning(t)
        if b <= 0.0:
            return None
        lick = 0.75 + 0.25 * sin(t * rate + ph)
        k = 0.6 if core else 1.0
        return (sunk(HOLE + off, t), Quaternion(Y, 0.15 * sin(t * rate * 0.6 + ph)),
                V((w * k * b, w * k * b, h * k * b * lick)))
    fx(C, "Fire_%d" % (i + 1), FLAME_CORE if core else FLAME, "Death", DIE_FRAMES, flame)

for i in range(3):                     # and at the burst tank
    off = V((rnd(-0.2, 0.0), rnd(-0.6, 0.6), 0.0))
    w, h, rate, ph = rnd(0.12, 0.2), rnd(0.5, 0.8), rnd(14, 22), rnd(0, 6)

    def tank_fire(t, off=off, w=w, h=h, rate=rate, ph=ph):
        b = ramp(t, T_BURST + 0.2, T_BURST + 0.6) * fade(t)
        if b <= 0.0:
            return None
        lick = 0.75 + 0.25 * sin(t * rate + ph)
        return sunk(TANK_AT + V((-0.4, 0.1, 0.0)) + off, t), None, V((w * b, w * b, h * b * lick))
    fx(C, "Tank_Fire_%d" % (i + 1), FLAME, "Death", DIE_FRAMES, tank_fire)

for i in range(16):                    # smoke from the hall and the tank
    from_tank = i % 4 == 3
    te = (0.5 if from_tank else 1.1) + 0.2 * i
    life = 1.8
    drift = V((rnd(-0.4, 0.5), rnd(-0.3, 0.3), rnd(2.6, 3.4)))
    size = rnd(0.55, 0.85) * (0.7 if from_tank else 1.0)
    src = (TANK_AT + V((-0.4, 0, 0.5))) if from_tank else (HOLE + V((rnd(-0.6, 0.6), rnd(-1.0, 1.0), 0.4)))

    def smoke(t, te=te, life=life, drift=drift, size=size, src=src):
        if t < te or t > te + life or te > FADE0:
            return None
        k = (t - te) / life
        s = size * (0.3 + 0.7 * sm(k * 1.6)) * (1 - ramp(k, 0.65, 1.0)) * fade(t)
        return src + drift * k, Quaternion(Z, k * 2 + te), s
    fx(C, "Smoke_%d" % (i + 1), PUFF, "Death", DIE_FRAMES, smoke)

POOL_AT = V((TANK_AT.x - 0.55, TANK_AT.y, 0.015))


def pool(t):
    if t < T_BURST + 0.1:
        return None
    grow = 1 - (1 - min((t - T_BURST - 0.1) / 2.4, 1.0)) ** 2.5
    r = 1.3 * grow * fade(t)
    return POOL_AT, Quaternion(Z, 0.7), V((r * 0.8, r * 1.2, 1.0))


fx(C, "Oil_Pool", POOL, "Death", DIE_FRAMES, pool)

# ================================================================= finish
lc = bpy.context.view_layer.layer_collection.children
for name in FX_COLLS:
    lc[name].exclude = True
scene.frame_start, scene.frame_end = 0, DIE_FRAMES
scene.frame_set(0)
print("CLIPS Idle", IDLE_FRAMES, "Build", BUILD_FRAMES, "Print", PRINT_FRAMES, "spawn at", SPAWN_AT, "Die", DIE_FRAMES)
print("WALK", [round(v, 2) for v in WALK], "yaw", round(math.degrees(YAW), 1))
bpy.context.preferences.filepaths.save_version = 0
bpy.ops.wm.save_mainfile()
print("SAVED")
