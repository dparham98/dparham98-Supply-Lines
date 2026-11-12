"""Stage 2 for TankFactory.blend: the clips Idle, Build, Produce and Die, and the death effects.

Run right after build_tank_factory.py, on the saved file:
  blender TankFactory.blend --background --python animate_tank_factory.py

Run build_tank_factory.py first each time: the saved file keeps the pose the clips leave at frame 0, and
a second run would take that as the rest pose.

It clears any animation and effects it made before, so it can be re-run. Everything is baked one key a
frame at 24 fps from the functions below, as NLA tracks named after their clip. The rest pose stays the
finished plant with the door closed, the crane parked and no vehicle on the turntable. The shared
helpers follow the Barracks' animate_barracks.py.
"""
import bpy, bmesh, math, random
from math import sin, cos, radians, pi, exp
from mathutils import Vector as V, Matrix, Quaternion

FPS = 24
FX_COLLS = ("tank_factory_death_fx",)
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
    if m.name.startswith("fac_fx_"):
        bpy.data.materials.remove(m)
bpy.context.view_layer.update()
OB = bpy.data.objects
# Rest poses at full size: a re-run starts from the saved file, whose vehicle is shrunk away.
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


VENTS = ["vent_01", "vent_02"]
FANS = ["vent_fan_01", "vent_fan_02"]
CAPS = ["stack_cap_01", "stack_cap_02"]
BEACONS = ["beacon_01", "beacon_02"]
VEH = ["veh_hull", "veh_track_l", "veh_track_r", "veh_deck", "veh_turret"]
RTOP = 4.05
TT = HOME["turntable"].translation.copy()
PARK_Y = HOME["gantry"].translation.y
TO_TT = TT.y - PARK_Y                  # gantry travel from its park over the rear strip to the turntable
HOOK_REST = 0.25                       # the hook's hang below the trolley at rest (build_tank_factory.py)
SPREADER = HOME["hook"].translation.z + HOME["trolley"].translation.z + HOME["gantry"].translation.z - 0.45


def yaw_about(c, a):
    return Tm(c) @ Rz(a) @ Tm(-V(c))


def cable(d):
    """The cable's Z scale is its length below the trolley."""
    return HOME["hook_cable"] @ Sc((1, 1, HOOK_REST + d))


def ram(h):
    """The lift's ram is one metre long: its Z scale is the lift height."""
    return HOME["lift_ram"] @ Sc((1, 1, max(h, 0.001)))


def hook(d):
    return Tm(-Z * d) @ HOME["hook"]


def gantry_at(off):
    return Tm(Y * off) @ HOME["gantry"]


def cap_flap(name, t, amp, speed):
    """A stack's rain cap lifting on its hinge: a base lift plus flutter."""
    k = 0.5 + 0.5 * sin(t * speed + (0 if name.endswith("1") else 2.1))
    return HOME[name] @ Rx(-radians(amp * (0.45 + 0.55 * k)))


# ================================================================= Idle (loops)
IDLE_FRAMES = 96                       # 4 s
IDLE_T = IDLE_FRAMES / FPS
W = 2 * pi / IDLE_T                    # one loop
for i, fan in enumerate(FANS):
    turns = (3, 4)[i] * (1 if i % 2 == 0 else -1)
    bake(OB[fan], "Idle", IDLE_FRAMES, lambda t, n=turns, f=fan: HOME[f] @ Rz(2 * pi * n * t / IDLE_T))
for i, b in enumerate(BEACONS):
    bake(OB[b], "Idle", IDLE_FRAMES, lambda t, b=b, d=(1, -1)[i]: HOME[b] @ Rz(d * 2 * W * t))
for c in CAPS:
    bake(OB[c], "Idle", IDLE_FRAMES, lambda t, c=c: cap_flap(c, t, 14, 3 * W))
bake(OB["gantry"], "Idle", IDLE_FRAMES, lambda t: gantry_at(-0.35 * (1 - cos(W * t)) / 2))
bake(OB["trolley"], "Idle", IDLE_FRAMES, lambda t: Tm(X * 0.4 * sin(W * t)) @ HOME["trolley"])
bake(OB["hook"], "Idle", IDLE_FRAMES, lambda t: hook(0.0))
bake(OB["hook_cable"], "Idle", IDLE_FRAMES, lambda t: cable(0.0))
# Idle also puts the door, the turntable and the vehicle back, in case production was cut short.
bake(OB["bay_door"], "Idle", IDLE_FRAMES, lambda t: HOME["bay_door"])
bake(OB["turntable"], "Idle", IDLE_FRAMES, lambda t: HOME["turntable"])
bake(OB["lift_ram"], "Idle", IDLE_FRAMES, lambda t: ram(0.0))
bake(OB["vehicle"], "Idle", IDLE_FRAMES, lambda t: HOME["vehicle"])
for v in VEH:
    bake(OB[v], "Idle", IDLE_FRAMES, lambda t, v=v: hidden(v))

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
bake(OB["frame"], "Build", BUILD_FRAMES, grow_z("frame", 0.08, 0.3))
bake(OB["turntable"], "Build", BUILD_FRAMES, pop("turntable", 0.2, 0.3))
bake(OB["walls"], "Build", BUILD_FRAMES, grow_z("walls", 0.28, 0.55))
bake(OB["roof"], "Build", BUILD_FRAMES, lower("roof", 0.55, 0.68, 2.6))
bake(OB["bay_door"], "Build", BUILD_FRAMES, grow_z("bay_door", 0.66, 0.74))
for i, v in enumerate(VENTS):
    bake(OB[v], "Build", BUILD_FRAMES, pop(v, 0.72 + 0.03 * i, 0.78 + 0.03 * i))
bake(OB["gantry"], "Build", BUILD_FRAMES, lower("gantry", 0.76, 0.86, 2.0))
bake(OB["stacks"], "Build", BUILD_FRAMES, grow_z("stacks", 0.8, 0.92))
bake(OB["tank"], "Build", BUILD_FRAMES, pop("tank", 0.86, 0.94))
for i, b in enumerate(BEACONS):
    bake(OB[b], "Build", BUILD_FRAMES, pop(b, 0.93 + 0.03 * i, 0.97 + 0.03 * i))
bake(OB["lift_ram"], "Build", BUILD_FRAMES, lambda t: ram(0.0))
bake(OB["hook"], "Build", BUILD_FRAMES, lambda t: hook(0.0))
bake(OB["hook_cable"], "Build", BUILD_FRAMES, lambda t: cable(0.0))
for v in VEH:
    bake(OB[v], "Build", BUILD_FRAMES, lambda t, v=v: hidden(v))

# ================================================================= Produce (scaled to the production time)
# The game plays 0..SPAWN_AT while the unit is made, the unit appears at the exit at SPAWN_AT, and the
# rest (the door closing) plays out at normal speed. The turntable rises as a lift to near the roof, where
# the camera sees into the well, and turns the vehicle side-on (its front to +X). The crane fetches each
# part from its park over the rear strip, carries it over the well and lowers it on. The lift then sinks
# back to the floor, turning the vehicle to face the door, and the vehicle drives out.
PRODUCE_FRAMES = 120                   # 5 s
SPAWN_AT = 4.0
LIFT_H = 2.4
DRIVE = -(3.05 + 0.3) - TT.y           # from the turntable to just outside the door
# (parts, shown at the park, carried over, lowered, released, back at the park)
CYCLES = [(("veh_track_l", "veh_track_r"), 0.3, (0.35, 0.65), (0.65, 0.85), (0.95, 1.2)),
          (("veh_deck",), 1.15, (1.2, 1.45), (1.45, 1.62), (1.72, 1.95)),
          (("veh_turret",), 1.9, (1.95, 2.2), (2.2, 2.36), (2.46, 2.7))]
TOPS = {"veh_track_l": 0.63, "veh_track_r": 0.63, "veh_deck": 1.01, "veh_turret": 1.33}   # above the turntable


def lift(t):
    return LIFT_H * ramp(t, 0.0, 0.35) * (1 - ramp(t, 2.5, 2.85))


def depth(parts):
    """How far the hook goes down to set these parts on the raised vehicle."""
    return SPREADER - (HOME["turntable"].translation.z + 0.05 + LIFT_H + TOPS[parts[0]])


def travel(t):
    """0 at the park, 1 over the turntable."""
    g = 0.0
    for parts, shown, go, down, back in CYCLES:
        g += ramp(t, *go) * (1 - ramp(t, *back))
    return g


def drop(t):
    d = 0.0
    for parts, shown, go, down, back in CYCLES:
        d += depth(parts) * ramp(t, *down) * (1 - ramp(t, down[1] + 0.1, down[1] + 0.2))
    return d


def turn(t):
    """The turntable's yaw: a quarter turn to take the vehicle side-on, then back to face the door."""
    return radians(90) * ramp(t, 0.0, 0.35) * (1 - ramp(t, 2.5, 2.85))


def carried(name):
    for parts, shown, go, down, back in CYCLES:
        if name in parts:
            dp = depth(parts)

            def fn(t, shown=shown, release=down[1], dp=dp):
                if t < shown or t >= SPAWN_AT:
                    return hidden(name)
                s = sm((t - shown) / 0.08)
                if t >= release:
                    return HOME[name]
                w = V((0.0, (PARK_Y - TT.y) * (1 - travel(t)), dp - drop(t)))     # from its seat, in world axes
                local = Rz(-turn(t)).to_3x3() @ w                                     # in the turned vehicle's axes
                return Tm(local) @ HOME[name] @ Sc(ONE * max(s, 0.001))
            return fn


def vehicle(t):
    k = ramp(t, 3.1, SPAWN_AT)
    return Tm(Y * DRIVE * k + Z * lift(t)) @ yaw_about(TT, turn(t)) @ HOME["vehicle"]


def hull(t):
    if t < 0.3 or t >= SPAWN_AT:
        return hidden("veh_hull")
    return HOME["veh_hull"] @ Sc((1, 1, max(sm((t - 0.3) / 0.4), 0.001)))


def door(t):
    up = ramp(t, 2.8, 3.2) * (1 - ramp(t, SPAWN_AT + 0.05, SPAWN_AT + 0.6))
    return HOME["bay_door"] @ Sc((1, 1, 1 - 0.94 * up))


bake(OB["gantry"], "Produce", PRODUCE_FRAMES, lambda t: gantry_at(TO_TT * travel(t)))
bake(OB["hook"], "Produce", PRODUCE_FRAMES, lambda t: hook(drop(t)))
bake(OB["hook_cable"], "Produce", PRODUCE_FRAMES, lambda t: cable(drop(t)))
bake(OB["trolley"], "Produce", PRODUCE_FRAMES, lambda t: HOME["trolley"])
bake(OB["turntable"], "Produce", PRODUCE_FRAMES, lambda t: Tm(Z * lift(t)) @ yaw_about(TT, turn(t)) @ HOME["turntable"])
bake(OB["lift_ram"], "Produce", PRODUCE_FRAMES, lambda t: ram(lift(t)))
bake(OB["vehicle"], "Produce", PRODUCE_FRAMES, vehicle)
bake(OB["veh_hull"], "Produce", PRODUCE_FRAMES, hull)
for v in VEH[1:]:
    bake(OB[v], "Produce", PRODUCE_FRAMES, carried(v))
bake(OB["bay_door"], "Produce", PRODUCE_FRAMES, door)
for i, fan in enumerate(FANS):         # the plant runs harder while it works
    bake(OB[fan], "Produce", PRODUCE_FRAMES,
         lambda t, f=fan, d=(1 if i % 2 == 0 else -1): HOME[f] @ Rz(d * 2 * pi * (1.6 * t + 0.25 * t * t)))
for i, b in enumerate(BEACONS):
    bake(OB[b], "Produce", PRODUCE_FRAMES, lambda t, b=b, d=(1, -1)[i]: HOME[b] @ Rz(d * 2 * pi * 0.9 * t))
for c in CAPS:
    bake(OB[c], "Produce", PRODUCE_FRAMES, lambda t, c=c: cap_flap(c, t, 26, 9.0))

# ================================================================= Die
DIE_END = 5.0
DIE_FRAMES = int(DIE_END * FPS)
SINK0 = 3.7
SINK = 4.4
ROOF_DROP = 2.0
T_BURST = 0.3                          # the fuel tank goes first
T_ROOF0, T_ROOF1 = 0.55, 1.1           # the roof caves in


def sink(t):
    return Tm(-Z * SINK * ramp(t, SINK0, DIE_END))


def shake(t, amp, ph):
    if t > 1.6:
        return Matrix.Identity(4)
    a = amp * exp(-t * 2.5) * min(t / 0.06, 1.0)      # from rest: the exported rest pose is Die's frame 0
    return Tm((a * sin(t * 47 + ph), a * sin(t * 53 + ph * 2), 0.5 * a * sin(t * 61 + ph * 3)))


def roof_fall(t):
    if t < T_ROOF0:
        return 0.0
    if t < T_ROOF1:
        return ROOF_DROP * ((t - T_ROOF0) / (T_ROOF1 - T_ROOF0)) ** 2
    return ROOF_DROP - 0.1 * exp(-(t - T_ROOF1) * 7) * abs(sin((t - T_ROOF1) * 15))


def about(pivot, R):
    return Tm(pivot) @ R @ Tm(-V(pivot))


def roof_die(t):
    k = sm(lin(t, T_ROOF0, T_ROOF1 + 0.1))
    tilt = Rx(radians(-8) * k) @ Ry(radians(7) * k)
    return sink(t) @ Tm(-Z * roof_fall(t)) @ about((0.0, 0.0, RTOP), tilt) @ HOME["roof"]


def walls_die(t):
    k = sm(lin(t, 0.6, 1.5))
    return sink(t) @ shake(t, 0.035, 1.0) @ Tm(-Z * 0.3 * k) @ about((0, 3.2, 0), Rx(radians(-4) * k) @ Ry(radians(3) * k)) @ HOME["walls"]


def frame_die(t):
    k = sm(lin(t, 0.65, 1.45))
    return sink(t) @ shake(t, 0.04, 2.0) @ Tm(-Z * 0.45 * k) @ about((0, -3.2, 0), Rx(radians(3) * k)) @ HOME["frame"]


def plinth_die(t):
    return sink(t) @ shake(t, 0.02, 3.0) @ HOME["plinth"]


def turntable_die(t):
    return sink(t) @ shake(t, 0.02, 4.0) @ HOME["turntable"]


def door_die(t):
    a = sm(lin(t, 0.45, 0.75))
    b = lin(t, 0.75, 1.1) ** 2
    hinge = HOME["bay_door"].translation
    swing = Rx(radians(-55) * a - radians(30) * b)
    dr = Tm((0, -0.3 * b, -(hinge.z - 0.35) * b))
    return sink(t) @ dr @ Tm(hinge) @ swing @ Tm(-hinge) @ HOME["bay_door"]


def tank_die(t):
    bulge = 1 + 0.18 * exp(-((t - T_BURST) / 0.08) ** 2)
    k = sm(lin(t, T_BURST, T_BURST + 0.6))
    c = HOME["tank"].translation
    return (sink(t) @ Tm((-0.45 * k, 0.1 * k, -0.3 * k)) @ Tm(c) @ Ry(radians(-38) * k) @ Rz(radians(9) * k)
            @ Sc((bulge, 1 + (bulge - 1) * 0.4, bulge)) @ Tm(-c) @ HOME["tank"])


GANTRY_FALL = 2.9


def gantry_die(t):
    """The crane drops off its rails into the well and lands across the turntable."""
    k = lin(t, T_ROOF0 - 0.05, T_ROOF1 - 0.05)
    fall = GANTRY_FALL * k * k
    if t > T_ROOF1 - 0.05:
        fall = GANTRY_FALL - 0.12 * exp(-(t - T_ROOF1 + 0.05) * 8) * abs(sin((t - T_ROOF1) * 16))
    slide = Tm(Y * TO_TT * 0.55 * sm(lin(t, 0.4, 0.8)))
    tilt = about(HOME["gantry"].translation, Rx(radians(18) * sm(k)) @ Ry(radians(-12) * sm(k)))
    return sink(t) @ Tm(-Z * fall) @ slide @ tilt @ HOME["gantry"]


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


STACK_LEAN = radians(55)


def stacks_die(t):
    """The stacks topple inward onto the caved-in roof, so the wreck stays on its footprint."""
    k = lin(t, 1.0, 1.8) ** 2
    if t > 1.8:
        k = 1 - 0.04 * exp(-(t - 1.8) * 6) * abs(sin((t - 1.8) * 14))
    c = HOME["stacks"].translation + X * 0.2
    return sink(t) @ about(c, Ry(-STACK_LEAN * k) @ Rx(radians(-10) * k)) @ HOME["stacks"]


def beacon_die(i):
    name = BEACONS[i]
    c = HOME[name].translation
    d = (-1, 1)[i]

    def fn(t):
        k = sm(lin(t, 0.65, 1.1))
        return sink(t) @ Tm(V((d * 0.3, -0.25, -0.45)) * k) @ about(c, Ry(d * radians(70) * k)) @ HOME[name]
    return fn


bake(OB["roof"], "Die", DIE_FRAMES, roof_die)
bake(OB["walls"], "Die", DIE_FRAMES, walls_die)
bake(OB["frame"], "Die", DIE_FRAMES, frame_die)
bake(OB["plinth"], "Die", DIE_FRAMES, plinth_die)
bake(OB["turntable"], "Die", DIE_FRAMES, turntable_die)
bake(OB["lift_ram"], "Die", DIE_FRAMES, lambda t: sink(t) @ ram(0.0))
bake(OB["bay_door"], "Die", DIE_FRAMES, door_die)
bake(OB["tank"], "Die", DIE_FRAMES, tank_die)
bake(OB["gantry"], "Die", DIE_FRAMES, gantry_die)
bake(OB["trolley"], "Die", DIE_FRAMES, lambda t: HOME["trolley"])
bake(OB["hook"], "Die", DIE_FRAMES, lambda t: hook(0.0))
bake(OB["hook_cable"], "Die", DIE_FRAMES, lambda t: cable(0.0))
for i in range(len(VENTS)):
    bake(OB[VENTS[i]], "Die", DIE_FRAMES, vent_die(i))
bake(OB["stacks"], "Die", DIE_FRAMES, stacks_die)
for i in range(len(BEACONS)):
    bake(OB[BEACONS[i]], "Die", DIE_FRAMES, beacon_die(i))
bake(OB["vehicle"], "Die", DIE_FRAMES, lambda t: sink(t) @ HOME["vehicle"])
for v in VEH:
    bake(OB[v], "Die", DIE_FRAMES, lambda t, v=v: hidden(v))
for c in CAPS:
    bake(OB[c], "Die", DIE_FRAMES, lambda t, c=c: HOME[c] @ Rx(-radians(min(t / 1.8, 1.0) * 100)))
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


M_DUST = fx_material("fac_fx_dust", (0.24, 0.20, 0.16), 1.0, None, 0.0, 0.7)
M_SPARK = fx_material("fac_fx_spark", (0, 0, 0), 0.8, (1.0, 0.62, 0.18), 5.0)
M_FLASH = fx_material("fac_fx_flash", (0, 0, 0), 0.8, (1.0, 0.8, 0.4), 3.2)
M_FIRE = fx_material("fac_fx_fire", (0, 0, 0), 0.8, (1.0, 0.2, 0.02), 1.3)
M_CORE = fx_material("fac_fx_core", (0, 0, 0), 0.8, (1.0, 0.5, 0.08), 2.0)
M_SMOKE = fx_material("fac_fx_smoke", (0.05, 0.045, 0.045), 1.0)
M_OIL = fx_material("fac_fx_oil", (0.012, 0.011, 0.016), 0.07)
M_SCRAP = bpy.data.materials["fac_gunmetal"]
M_SCRAP2 = bpy.data.materials["fac_rust"]


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


C = collection("tank_factory_death_fx")
PUFF = ico_mesh("fxm_smoke", M_SMOKE, 2, 0.1, True)
DUST = ico_mesh("fxm_dust", M_DUST, 1, 0.14, True)
SHARD = shard_mesh("fxm_shard", M_SPARK)
SCRAP = plate_mesh("fxm_scrap", [M_SCRAP, M_SCRAP2])
FLAME = flame_mesh("fxm_flame", M_FIRE)
FLAME_CORE = flame_mesh("fxm_flame_core", M_CORE)
POOL = disc_mesh("fxm_pool", M_OIL)
CORE = ico_mesh("fxm_core", M_FLASH, 1, 0.0, False, 0.45)
FADE0, FADE1 = SINK0 + 0.1, DIE_END - 0.1
TANK_AT = HOME["tank"].translation.copy()
HOLE = V((TT.x, TT.y - 0.2, RTOP - ROOF_DROP + 0.2))      # the caved-in well, where the crane lands
CRANE_LAND = T_ROOF1 - 0.05


def fade(t):
    return 1 - ramp(t, FADE0, FADE1)


def sunk(p, t):
    return V(p) - Z * SINK * ramp(t, SINK0, DIE_END)


def burning(t):
    return ramp(t, 1.0, 1.5) * fade(t)


def flash(t):
    burst = 1.5 * exp(-((t - T_BURST - 0.05) / 0.12) ** 2) if t > T_BURST - 0.1 else 0.0
    crane = 0.9 * exp(-((t - CRANE_LAND) / 0.15) ** 2)
    glow = burning(t) * (0.35 + 0.08 * sin(t * 23) + 0.05 * sin(t * 37))
    s = max(burst, crane, glow)
    at = TANK_AT + V((-0.5, 0, 0.3)) if t < 0.8 else sunk(HOLE + Z * 0.4, t)
    return at, None, s


# The flash mesh's scale drives the light in the game, so it comes first in the collection.
fx(C, "Flash", CORE, "Death", DIE_FRAMES, flash)

for i in range(18):                    # the fuel tank bursts outward (-X)
    vel = V((rnd(-5.5, -1.5), rnd(-3.0, 3.0), rnd(1.5, 5.5)))
    life = rnd(0.3, 0.6)
    size = rnd(0.2, 0.34)
    te = T_BURST + rnd(-0.02, 0.06)

    def spark(t, vel=vel, life=life, size=size, te=te):
        if t < te or t > te + life:
            return None
        s = t - te
        v_now = vel + V((0, 0, -GRAV * s))
        return ballistic(TANK_AT + V((-0.35, 0, 0.1)), vel, s), v_now.to_track_quat('Y', 'Z'), size * (1 - s / life)
    fx(C, "Burst_Spark_%d" % (i + 1), SHARD, "Death", DIE_FRAMES, spark)

for i in range(14):                    # sparks where the crane hits the turntable
    vel = V((rnd(-3.5, 3.5), rnd(-3.5, 3.5), rnd(2.0, 5.0)))
    life = rnd(0.25, 0.5)
    size = rnd(0.16, 0.28)
    te = CRANE_LAND + rnd(-0.02, 0.05)

    def crane_spark(t, vel=vel, life=life, size=size, te=te):
        if t < te or t > te + life:
            return None
        s = t - te
        v_now = vel + V((0, 0, -GRAV * s))
        return ballistic(HOLE, vel, s), v_now.to_track_quat('Y', 'Z'), size * (1 - s / life)
    fx(C, "Crane_Spark_%d" % (i + 1), SHARD, "Death", DIE_FRAMES, crane_spark)

for i in range(12):                    # scrap plates thrown out, then lying where they land
    src = V((rnd(-2.8, 2.8), rnd(-3.0, 3.0), rnd(3.2, 4.1)))
    out = V((src.x, src.y, 0)).normalized()
    vel = out * rnd(1.2, 2.6) + V((0, 0, rnd(2.0, 4.5)))
    te = rnd(T_ROOF0, T_ROOF1 + 0.1)
    size = rnd(0.4, 0.8)
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

for i in range(12):                    # a dust ring where the roof lands
    a = 2 * pi * i / 12 + rnd(-0.2, 0.2)
    d = V((cos(a), sin(a), 0))
    size = rnd(0.8, 1.25)

    def dust(t, d=d, size=size):
        if t < T_ROOF1 - 0.05 or t > T_ROOF1 + 1.6:
            return None
        k = (t - T_ROOF1 + 0.05) / 1.65
        p = V((0, 0, 0.4)) + d * (3.2 + 2.0 * (1 - (1 - k) ** 2.5)) + Z * 0.9 * k
        return p, None, size * sm(k * 4) * (1 - ramp(k, 0.45, 1.0))
    fx(C, "Dust_%d" % (i + 1), DUST, "Death", DIE_FRAMES, dust)

for i in range(7):                     # fire in the caved-in hall
    off = V((rnd(-1.2, 1.2), rnd(-1.6, 1.6), rnd(-0.05, 0.05)))
    w, h, rate, ph = rnd(0.2, 0.34), rnd(0.9, 1.5), rnd(12, 20), rnd(0, 6)
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

for i in range(3):                     # and at the burst fuel tank
    off = V((rnd(-0.2, 0.0), rnd(-0.7, 0.7), 0.0))
    w, h, rate, ph = rnd(0.14, 0.22), rnd(0.55, 0.9), rnd(14, 22), rnd(0, 6)

    def tank_fire(t, off=off, w=w, h=h, rate=rate, ph=ph):
        b = ramp(t, T_BURST + 0.2, T_BURST + 0.6) * fade(t)
        if b <= 0.0:
            return None
        lick = 0.75 + 0.25 * sin(t * rate + ph)
        return sunk(TANK_AT + V((-0.45, 0.1, 0.0)) + off, t), None, V((w * b, w * b, h * b * lick))
    fx(C, "Tank_Fire_%d" % (i + 1), FLAME, "Death", DIE_FRAMES, tank_fire)

for i in range(18):                    # smoke from the hall and the tank
    from_tank = i % 4 == 3
    te = (0.5 if from_tank else 1.1) + 0.18 * i
    life = 1.8
    drift = V((rnd(-0.4, 0.5), rnd(-0.3, 0.3), rnd(2.8, 3.6)))
    size = rnd(0.6, 0.95) * (0.7 if from_tank else 1.0)
    src = (TANK_AT + V((-0.45, 0, 0.5))) if from_tank else (HOLE + V((rnd(-0.8, 0.8), rnd(-1.2, 1.2), 0.4)))

    def smoke(t, te=te, life=life, drift=drift, size=size, src=src):
        if t < te or t > te + life or te > FADE0:
            return None
        k = (t - te) / life
        s = size * (0.3 + 0.7 * sm(k * 1.6)) * (1 - ramp(k, 0.65, 1.0)) * fade(t)
        return src + drift * k, Quaternion(Z, k * 2 + te), s
    fx(C, "Smoke_%d" % (i + 1), PUFF, "Death", DIE_FRAMES, smoke)

POOL_AT = V((TANK_AT.x - 0.3, TANK_AT.y, 0.015))


def pool(t):
    if t < T_BURST + 0.1:
        return None
    grow = 1 - (1 - min((t - T_BURST - 0.1) / 2.4, 1.0)) ** 2.5
    r = 1.3 * grow * fade(t)
    return POOL_AT, Quaternion(Z, 0.7), V((r * 0.5, r * 1.3, 1.0))


fx(C, "Oil_Pool", POOL, "Death", DIE_FRAMES, pool)

# ================================================================= finish
lc = bpy.context.view_layer.layer_collection.children
for name in FX_COLLS:
    lc[name].exclude = True
scene.frame_start, scene.frame_end = 0, DIE_FRAMES
scene.frame_set(0)
print("CLIPS Idle", IDLE_FRAMES, "Build", BUILD_FRAMES, "Produce", PRODUCE_FRAMES, "spawn at", SPAWN_AT, "Die", DIE_FRAMES)
print("SPREADER", round(SPREADER, 2), "TO_TT", round(TO_TT, 2), "DRIVE", round(DRIVE, 2), "DEPTHS", [round(depth(c[0]), 2) for c in CYCLES])
bpy.context.preferences.filepaths.save_version = 0
bpy.ops.wm.save_mainfile()
print("SAVED")
