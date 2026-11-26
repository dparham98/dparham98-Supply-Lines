"""Stage 2 for DragonYard.blend: the clips Idle, Work, Build and Die, and the dragon_yard_death_fx Death clip.

  blender DragonYard.blend --background --python animate_dragon_yard.py

Clears the animation it made before, so it can be re-run. Every part is keyed in every clip, at 24 fps,
as per-object NLA tracks. Die is pushed last, so frame 0 (the exported rest pose) is the finished building.
In the game scripts/components/production_rig.gd plays them:
  Idle      4 s loop: the smith strikes the anvil every 2 s with a spray of sparks, the egg stirs in its nest
            with a few slow motes about it, fires flicker, a thread of smoke rises from the forge, the banner
            and the roost's pennant stir.
  Work      4 s loop, while the Yard raises a dragon (production_rig.gd print_loops): the egg rocks and swells,
            its motes race round it; the keeper forks hay into the pen twice; the smith strikes twice a second;
            the forge roars and smokes; the coal wagon is worked a little along its track and back.
  Build     4.2 s, scrubbed by construction progress (production_rig.gd show_construction).
  Die       2.7 s, with dragon_yard_death_fx on the same timeline.
"""
import bpy, os, sys, random
from math import sin, cos, radians, pi
from mathutils import Vector as V, Matrix

HERE = os.path.dirname(os.path.abspath(__file__))
KIT = os.environ.get("SL_BUILDING_KIT") or os.path.normpath(os.path.join(HERE, "..", "..", "Foundry", "build"))
sys.path.insert(0, KIT)
import importlib, building_kit
importlib.reload(building_kit)
from building_kit import *  # noqa: F401,F403

random.seed(43)
scene = bpy.context.scene
scene.render.fps = FPS
for c in bpy.context.view_layer.layer_collection.children:
    c.exclude = False
scene.frame_set(0)
clear_animation()
PARTS = [o for o in bpy.data.collections["dragon_yard"].all_objects]
HOME = {o.name: o.matrix_basis.copy() for o in PARTS + list(bpy.data.collections["dragon_yard_death_fx"].all_objects)}
WHEELS = ["wagon_wheel_%d" % (k + 1) for k in range(4)]
WHEEL_R = 0.17


def hidden(name):
    return Tm(HOME[name].translation) @ Sc(NIL)


def home(name):
    return lambda t: HOME[name]


def puff(name, phase, period, rise, s0, s1):
    """A smoke puff on a loop: rises `rise` and swells s0 -> s1 over each period, gone at both ends."""
    def fn(t):
        u = (t / period + phase) % 1.0
        s = (s0 + (s1 - s0) * u) * ramp(u, 0.0, 0.15) * (1 - ramp(u, 0.75, 1.0))
        drift = V((0.3 * u, 0.25 * u, rise * u))
        return Tm(HOME[name].translation + drift) @ Sc(ONE * max(s, 0.001))
    return fn


SMOKE = ["smoke_%d" % (k + 1) for k in range(4)]
QUIET = SMOKE + ["sparks", "egg_motes"]


def clip(name, frames, fns, default=None):
    """Bakes `fns` (part name -> fn(t)) and holds every other part still; QUIET parts are hidden."""
    for o in PARTS:
        fn = fns.get(o.name)
        if fn is None and default is not None:
            fn = default(o)
        if fn is None:
            fn = (lambda t, n=o.name: hidden(n)) if o.name in QUIET else home(o.name)
        bake(o, name, frames, fn)


def stir(name, phase, amp, axis=Rx):
    """Stirs about the cloth's hinge; whole cycles in 4 s so the loops meet."""
    return lambda t: HOME[name] @ axis(amp * sin(2 * pi * (t / 2.0 + phase))) @ Ry(amp * 0.5 * sin(2 * pi * (t / 4.0 + phase)))


def flicker(name, base, amp, rate):
    return lambda t: HOME[name] @ Sc((base + amp * sin(2 * pi * rate * t), base + amp * sin(2 * pi * rate * t + 1.3),
                                      base + amp * 1.4 * sin(2 * pi * rate * t * 1.5 + 0.4)))


def blows(period, at=0.0):
    """The smith's hammer: raised and brought down once per period; 0 is the blow on the anvil."""
    def lift(t):
        u = ((t - at) / period) % 1.0
        return radians(95) * ramp(u, 0.08, 0.55) * (1 - ramp(u, 0.8, 0.97))
    return lift


def spray(period, at=0.0):
    """Sparks just after each blow: (rise, size)."""
    def fn(name):
        def f(t):
            k = (((t - at) / period - 0.97) % 1.0) * period / 0.22
            if k >= 1:
                return hidden(name)
            return HOME[name] @ Tm(V((0, 0, 0.1 * k))) @ Sc(ONE * max(sin(pi * k) * 1.4, 0.001))
        return f
    return fn


def egg(rock, swell, rate):
    return lambda t: HOME["egg"] @ Rx(rock * sin(2 * pi * rate * t)) @ Ry(rock * 0.7 * sin(2 * pi * rate * t + 1.1)) @ Sc(
        ONE * (1 + swell * (0.5 + 0.5 * sin(2 * pi * rate * 0.5 * t))))


def motes(scale, turns):
    """Motes circling the egg `turns` times a loop, at `scale`."""
    return lambda t: HOME["egg_motes"] @ Rz(2 * pi * turns * t / 4.0) @ Tm(V((0, 0, 0.08 * sin(2 * pi * t / 2.0)))) @ Sc(
        ONE * scale * (0.85 + 0.15 * sin(2 * pi * t)))


# ================================================================= Idle (4 s loop)
IDLE = 96
LOOP = IDLE / FPS
lift = blows(2.0)
idle = {
    "smith_arm": lambda t: HOME["smith_arm"] @ Rx(lift(t)),
    "sparks": spray(2.0)("sparks"),
    "egg": egg(radians(2.5), 0.02, 0.5),
    "egg_motes": motes(0.6, 1),
    "forge_fire": flicker("forge_fire", 1.0, 0.12, 2.0),
    "brazier_fire": flicker("brazier_fire", 1.0, 0.1, 1.5),
    "banner": stir("banner", 0.0, 0.06),
    "pennant": stir("pennant", 0.3, 0.12, Rz),
}
for k in range(2):
    idle[SMOKE[k]] = puff(SMOKE[k], k / 2, LOOP, 1.2, 0.25, 0.7)
clip("Idle", IDLE, idle)

# ================================================================= Work (4 s loop, while a dragon is raised)
WORK = 96
hammer = blows(0.5)


def toss(t):
    """The keeper's pitchfork: back, then forward to throw, twice a loop. Positive tips the fork back."""
    u = (t / 2.0) % 1.0
    return radians(18) * ramp(u, 0.0, 0.35) * (1 - ramp(u, 0.35, 0.5)) - radians(55) * ramp(u, 0.38, 0.52) * (1 - ramp(u, 0.6, 0.95))


def roll(t):
    """How far the wagon has been worked along the track (m): out 0.35 m and back over the loop."""
    return 0.35 * (0.5 - 0.5 * cos(2 * pi * t / LOOP))


work = {
    "smith_arm": lambda t: HOME["smith_arm"] @ Rx(hammer(t)),
    "sparks": spray(0.5)("sparks"),
    "keeper_arm": lambda t: HOME["keeper_arm"] @ Rx(toss(t)),
    "keeper": lambda t: HOME["keeper"] @ Rx(-0.4 * toss(t) * 0.25),
    "egg": egg(radians(9), 0.07, 1.5),
    "egg_motes": motes(1.0, 3),
    "forge_fire": flicker("forge_fire", 1.35, 0.2, 3.0),
    "brazier_fire": flicker("brazier_fire", 1.15, 0.14, 2.0),
    "banner": stir("banner", 0.0, 0.08),
    "pennant": stir("pennant", 0.3, 0.16, Rz),
    "wagon": lambda t: Tm(V((0, -roll(t), 0))) @ HOME["wagon"],
}
for w in WHEELS:
    work[w] = (lambda t, w=w: HOME[w] @ Rx(roll(t) / WHEEL_R))
for k in range(4):
    work[SMOKE[k]] = puff(SMOKE[k], k / 4, LOOP / 2, 1.6, 0.3, 0.95)
clip("Work", WORK, work)

# ================================================================= Build (scrubbed by construction progress)
BUILD = 100
BT = BUILD / FPS


def grow_z(name, a, b):
    def fn(t):
        k = lin(t / BT, a, b)
        return hidden(name) if k <= 0 else HOME[name] @ Sc((1, 1, max(sm(k), 0.001)))
    return fn


def pop(name, a, b):
    def fn(t):
        k = lin(t / BT, a, b)
        if k <= 0:
            return hidden(name)
        s = sm(k / 0.7) * 1.06 if k < 0.7 else 1 + 0.06 * (1 - sm((k - 0.7) / 0.3))
        return HOME[name] @ Sc(ONE * s)
    return fn


def lower(name, a, b, land, drop):
    def fn(t):
        p = t / BT
        k = lin(p, a, b)
        if k <= 0:
            return hidden(name)
        return Tm(Z * drop * (1 - ramp(p, b, land))) @ HOME[name] @ Sc(ONE * sm(k))
    return fn


build = {
    "plinth": grow_z("plinth", 0.0, 0.12),
    "track": grow_z("track", 0.08, 0.22),
    "pen": grow_z("pen", 0.12, 0.45),
    "forge": grow_z("forge", 0.3, 0.45),
    "roost_tower": grow_z("roost_tower", 0.2, 0.5),
    "roof": lower("roof", 0.45, 0.58, 0.68, 0.8),
    "anvil": pop("anvil", 0.5, 0.6),
    "trough": pop("trough", 0.5, 0.6),
    "perch": pop("perch", 0.55, 0.65),
    "nest": pop("nest", 0.6, 0.7),
    "pennant_pole": grow_z("pennant_pole", 0.62, 0.7),
    "brazier": pop("brazier", 0.65, 0.75),
    "pennant": pop("pennant", 0.7, 0.78),
    "wagon": pop("wagon", 0.7, 0.82),
    "banner_pole": grow_z("banner_pole", 0.72, 0.84),
    "forge_fire": pop("forge_fire", 0.8, 0.86),
    "banner": pop("banner", 0.84, 0.92),
    "brazier_fire": pop("brazier_fire", 0.86, 0.92),
    "smith": pop("smith", 0.88, 0.96),
    "keeper": pop("keeper", 0.9, 0.98),
    "egg": pop("egg", 0.94, 1.0),
}
clip("Build", BUILD, build)

# ================================================================= Die (2.7 s) and its effects
DIE = 64
SINK0, SINK1, SINK = 1.8, 2.62, 5.0


def sink(t):
    return -SINK * ramp(t, SINK0, SINK1)


def wreck(name, t0, t1, d_loc, d_rot):
    def fn(t):
        k = ramp(t, t0, t1)
        R = Matrix.Identity(4).lerp(d_rot, k)
        return Tm(V(d_loc) * k + Z * sink(t)) @ HOME[name] @ R
    return fn


def gone(name, at):
    return lambda t: hidden(name) if t > at else Tm(Z * sink(t)) @ HOME[name]


die = {
    "plinth": lambda t: Tm(Z * (sink(t) - 0.06 * ramp(t, 0.2, 1.0))) @ HOME["plinth"],
    "pen": wreck("pen", 0.2, 1.0, (0.1, 0.25, -0.6), Rx(radians(5)) @ Ry(radians(-4))),
    "roof": wreck("roof", 0.1, 0.75, (0.2, -0.3, -2.2), Rx(radians(-14)) @ Ry(radians(10))),
    "roost_tower": wreck("roost_tower", 0.15, 1.1, (0.6, 0.3, -0.2), Ry(radians(62)) @ Rx(radians(-10))),
    "wagon": wreck("wagon", 0.2, 0.7, (0.25, -0.3, 0.1), Ry(radians(80))),
    "forge": wreck("forge", 0.25, 0.9, (0.0, 0.0, -0.3), Rz(radians(10))),
    "brazier": wreck("brazier", 0.1, 0.45, (-0.2, -0.3, -0.1), Rx(radians(-85))),
    "brazier_fire": gone("brazier_fire", 0.25),
    "banner_pole": wreck("banner_pole", 0.1, 0.9, (-0.2, -0.2, 0), Ry(radians(-75))),
    "banner": gone("banner", 0.6),
    "smith": gone("smith", 0.12),
    "keeper": gone("keeper", 0.12),
    "egg": gone("egg", 0.1),
}


def die_default(o):
    """Anything not listed sinks with the plinth; a child part rides with its parent."""
    if o.name in QUIET:
        return None
    if o.parent is not None:
        return home(o.name)
    return lambda t, n=o.name: Tm(Z * sink(t)) @ HOME[n]


clip("Die", DIE, die, die_default)

# the death effects on Die's timeline
FXO = list(bpy.data.collections["dragon_yard_death_fx"].all_objects)
G = 9.8
for o in FXO:
    n = o.name
    h = HOME[n]
    if n == "Flash_DragonYard":
        fn = lambda t, h=h: h @ Sc(ONE * (ramp(t, 0.0, 0.05) * (1 - ramp(t, 0.1, 0.45)) * 2.4 + 0.001))
    elif n.startswith("fx_fire"):
        late = random.uniform(0.0, 0.5)
        fn = lambda t, h=h, late=late: Tm(Z * 1.4 * ramp(t, late, late + 1.5)) @ h @ Sc(
            ONE * (ramp(t, late, late + 0.25) * (1 - ramp(t, late + 1.1, late + 1.9)) * 1.4 + 0.001))
    elif n.startswith("fx_smoke"):
        late = random.uniform(0.1, 0.8)
        fn = lambda t, h=h, late=late: Tm(V((0.4, 0.3, 3.0)) * ramp(t, late, DIE / FPS)) @ h @ Sc(
            ONE * (ramp(t, late, late + 0.6) * (1 - ramp(t, 2.2, DIE / FPS)) * 2.2 + 0.001))
    elif n.startswith("fx_debris"):
        a = random.uniform(0, 2 * pi)
        vr, vz = random.uniform(2.5, 5.5), random.uniform(3.5, 7.5)
        spin = V((random.uniform(-1, 1), random.uniform(-1, 1), random.uniform(-1, 1))).normalized()

        def fn(t, h=h, a=a, vr=vr, vz=vz, spin=spin):
            z = max(-1.8, vz * t - 0.5 * G * t * t)
            land = min(t, 2 * vz / G)
            q = Matrix.Rotation(10 * land, 4, spin)
            return Tm(V((cos(a) * vr * land, sin(a) * vr * land, z))) @ h @ q @ Sc(ONE * (1 - ramp(t, 2.2, DIE / FPS) + 0.001))
    else:
        fn = lambda t, h=h: h
    bake(o, "Death", DIE, fn)

bpy.context.view_layer.layer_collection.children["dragon_yard_death_fx"].exclude = True
scene.frame_start, scene.frame_end = 0, DIE
scene.frame_set(0)
bpy.context.preferences.filepaths.save_version = 0
bpy.ops.wm.save_mainfile()
print("SAVED clips Idle", IDLE, "Work", WORK, "Build", BUILD, "Die", DIE)
