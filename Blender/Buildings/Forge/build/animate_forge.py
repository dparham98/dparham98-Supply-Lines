"""Stage 2 for Forge.blend: the clips Idle, Research, Build and Die, and the forge_death_fx Death clip.

  blender Forge.blend --background --python animate_forge.py

Clears the animation it made before, so it can be re-run. Every part is keyed in every clip, at 24 fps,
as per-object NLA tracks. Die is pushed last, so frame 0 (the exported rest pose) is the finished building.
In the game scripts/components/research_rig.gd plays them:
  Idle      4 s loop: embers in the hearth, a thread of chimney smoke, the banners stir, the smith rests.
  Research  4 s loop while an upgrade is researched: the bellows pump twice and the hearth flares, the
            smith strikes the hot billet four times with sparks, steam off the quench trough, heavy smoke.
  Build     4.2 s, scrubbed by construction progress (production_rig.gd show_construction).
  Die       2.7 s, with forge_death_fx on the same timeline.
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

random.seed(31)
scene = bpy.context.scene
scene.render.fps = FPS
for c in bpy.context.view_layer.layer_collection.children:
    c.exclude = False
scene.frame_set(0)
clear_animation()
PARTS = [o for o in bpy.data.collections["forge"].all_objects]
HOME = {o.name: o.matrix_basis.copy() for o in PARTS + list(bpy.data.collections["forge_death_fx"].all_objects)}


def hidden(name):
    return Tm(HOME[name].translation) @ Sc(NIL)


def home(name):
    return lambda t: HOME[name]


def puff(name, phase, period, rise, s0, s1):
    """A smoke puff on a loop: rises `rise` and swells s0 -> s1 over each period, gone at both ends."""
    def fn(t):
        u = (t / period + phase) % 1.0
        s = (s0 + (s1 - s0) * u) * ramp(u, 0.0, 0.15) * (1 - ramp(u, 0.75, 1.0))
        drift = V((0.3 * u, 0.2 * u, rise * u))
        return Tm(HOME[name].translation + drift) @ Sc(ONE * max(s, 0.001))
    return fn


SMOKE = ["smoke_%d" % (k + 1) for k in range(8)]
QUIET = SMOKE + ["anvil_sparks", "quench_steam", "anvil_billet"]


def clip(name, frames, fns):
    """Bakes `fns` (part name -> fn(t)) and holds every other part still; QUIET parts are hidden."""
    for o in PARTS:
        fn = fns.get(o.name)
        if fn is None:
            fn = (lambda t, n=o.name: hidden(n)) if o.name in QUIET else home(o.name)
        bake(o, name, frames, fn)


def banner(name, phase, amp):
    """Stirs about the banner's hinge on its crossbar; whole cycles in 4 s so the loops meet."""
    return lambda t: HOME[name] @ Rx(amp * sin(2 * pi * (t / 2.0 + phase))) @ Ry(amp * 0.5 * sin(2 * pi * (t / 4.0 + phase)))


# ================================================================= Idle (4 s loop)
IDLE = 96
LOOP = IDLE / FPS
idle = {
    "hearth_fire": lambda t: HOME["hearth_fire"] @ Sc((1, 1, 0.55 + 0.08 * sin(2 * pi * t / LOOP * 3))),
    "smith": lambda t: HOME["smith"] @ Sc((1, 1, 1 + 0.008 * sin(2 * pi * t / LOOP))),
    "banner_1": banner("banner_1", 0.0, 0.06),
    "banner_2": banner("banner_2", 0.4, 0.06),
}
for k in range(2):
    idle[SMOKE[k]] = puff(SMOKE[k], k / 2, LOOP, 1.4, 0.3, 0.8)
clip("Idle", IDLE, idle)

# ================================================================= Research (4 s loop)
RES = 96
LIFT = radians(-118)                         # the hammer arm raised overhead; 0 is the blow on the billet


def blow(t):
    """Phase within each 1 s strike; the hammer lands at u = 0 (and at 0.97 of the one before)."""
    return t % 1.0


def arm(t):
    u = blow(t)
    return LIFT * ramp(u, 0.12, 0.62) * (1 - ramp(u, 0.8, 0.97))


def sparks(t):
    k = ((blow(t) - 0.97) % 1.0) / 0.2
    return 0.0 if k >= 1 else sin(pi * k) * 1.4


def pump(t):
    return 0.5 - 0.5 * cos(2 * pi * t / 2.0)


research = {
    "smith_arm": lambda t: HOME["smith_arm"] @ Rx(arm(t)),
    "smith": lambda t: HOME["smith"] @ Tm(V((0, 0, -0.03 * ramp(blow(t), 0.85, 0.97) * (1 - ramp(blow(t), 0.0, 0.2))))),
    "anvil_billet": lambda t: HOME["anvil_billet"] @ Sc((1 - 0.04 * sparks(t), 1, 1)),
    "anvil_sparks": lambda t: HOME["anvil_sparks"] @ Rz(blow(t) * 3) @ Sc(ONE * max(sparks(t), 0.001)),
    "bellows_board": lambda t: HOME["bellows_board"] @ Ry(radians(-16) * pump(t)),
    "hearth_fire": lambda t: HOME["hearth_fire"] @ Sc((1.1, 1.1, 0.8 + 0.7 * (1 - pump(t)) + 0.06 * sin(2 * pi * t * 4))),
    "quench_steam": lambda t: Tm(V((0, 0, 0.9 * lin(t, 2.2, 3.9)))) @ HOME["quench_steam"]
    @ Sc(ONE * max(0.001, ramp(t, 2.2, 2.5) * (1 - ramp(t, 3.3, 3.9)) * (1 + 0.8 * lin(t, 2.2, 3.9)))),
    "banner_1": banner("banner_1", 0.0, 0.06),
    "banner_2": banner("banner_2", 0.4, 0.06),
}
for k in range(8):
    research[SMOKE[k]] = puff(SMOKE[k], k / 8, LOOP / 2, 2.4, 0.5, 1.5)
clip("Research", RES, research)

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
    "plinth": grow_z("plinth", 0.0, 0.14),
    "hearth": grow_z("hearth", 0.10, 0.42),
    "bellows": pop("bellows", 0.36, 0.48),
    "frame": grow_z("frame", 0.28, 0.52),
    "roof": lower("roof", 0.50, 0.60, 0.70, 0.8),
    "anvil": pop("anvil", 0.42, 0.54),
    "trough": pop("trough", 0.52, 0.64),
    "weapon_rack": pop("weapon_rack", 0.62, 0.76),
    "hauberk": pop("hauberk", 0.70, 0.82),
    "banner_pole_1": grow_z("banner_pole_1", 0.74, 0.86),
    "banner_pole_2": grow_z("banner_pole_2", 0.78, 0.90),
    "banner_1": pop("banner_1", 0.86, 0.96),
    "banner_2": pop("banner_2", 0.88, 0.98),
    "smith": pop("smith", 0.88, 1.0),
    "hearth_fire": pop("hearth_fire", 0.84, 0.94),
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
    return lambda t: hidden(name) if t > at else HOME[name]


die = {
    "plinth": lambda t: Tm(Z * (sink(t) - 0.08 * ramp(t, 0.2, 1.0))) @ HOME["plinth"],
    "hearth": wreck("hearth", 0.2, 1.1, (0.3, 0.2, -0.5), Ry(radians(-9)) @ Rx(radians(6))),
    "hearth_fire": gone("hearth_fire", 0.5),
    "bellows": wreck("bellows", 0.15, 0.7, (0.3, -0.4, 0), Rz(radians(35))),
    "frame": wreck("frame", 0.2, 0.9, (0.2, 0.1, -1.0), Rx(radians(-12)) @ Ry(radians(8))),
    "roof": wreck("roof", 0.1, 0.75, (0.3, -0.3, -2.0), Rx(radians(-14)) @ Ry(radians(10))),
    "weapon_rack": wreck("weapon_rack", 0.2, 0.8, (0, -0.5, -0.3), Rx(radians(-70))),
    "anvil": wreck("anvil", 0.15, 0.5, (0, 0, -0.1), Rz(radians(20))),
    "anvil_billet": lambda t: hidden("anvil_billet"),
    "smith": gone("smith", 0.12),
    "trough": wreck("trough", 0.3, 1.0, (0, 0, -0.1), Rz(radians(-6))),
    "hauberk": wreck("hauberk", 0.1, 0.7, (-0.4, -0.5, 0), Rx(radians(-82))),
    "banner_pole_1": wreck("banner_pole_1", 0.1, 0.9, (-0.2, -0.2, 0), Ry(radians(-75))),
    "banner_pole_2": wreck("banner_pole_2", 0.15, 0.95, (0.2, -0.2, 0), Ry(radians(75))),
    "banner_1": gone("banner_1", 0.6),
    "banner_2": gone("banner_2", 0.6),
}
clip("Die", DIE, die)

# the death effects on Die's timeline
FXO = list(bpy.data.collections["forge_death_fx"].all_objects)
G = 9.8
for o in FXO:
    n = o.name
    h = HOME[n]
    if n == "Flash_Forge":
        fn = lambda t, h=h: h @ Sc(ONE * (ramp(t, 0.0, 0.05) * (1 - ramp(t, 0.1, 0.45)) * 2.6 + 0.001))
    elif n.startswith("fx_fire"):
        late = random.uniform(0.0, 0.5)
        fn = lambda t, h=h, late=late: Tm(Z * 1.2 * ramp(t, late, late + 1.5)) @ h @ Sc(
            ONE * (ramp(t, late, late + 0.25) * (1 - ramp(t, late + 1.1, late + 1.9)) * 1.3 + 0.001))
    elif n.startswith("fx_smoke"):
        late = random.uniform(0.1, 0.8)
        fn = lambda t, h=h, late=late: Tm(V((0.4, 0.3, 2.5)) * ramp(t, late, DIE / FPS)) @ h @ Sc(
            ONE * (ramp(t, late, late + 0.6) * (1 - ramp(t, 2.2, DIE / FPS)) * 2.0 + 0.001))
    elif n.startswith("fx_debris"):
        a = random.uniform(0, 2 * pi)
        vr, vz = random.uniform(2.5, 5.0), random.uniform(3.5, 7.0)
        spin = V((random.uniform(-1, 1), random.uniform(-1, 1), random.uniform(-1, 1))).normalized()

        def fn(t, h=h, a=a, vr=vr, vz=vz, spin=spin):
            z = max(-1.5, vz * t - 0.5 * G * t * t)
            land = min(t, 2 * vz / G)
            q = Matrix.Rotation(10 * land, 4, spin)
            return Tm(V((cos(a) * vr * land, sin(a) * vr * land, z))) @ h @ q @ Sc(ONE * (1 - ramp(t, 2.2, DIE / FPS) + 0.001))
    else:
        fn = lambda t, h=h: h
    bake(o, "Death", DIE, fn)

bpy.context.view_layer.layer_collection.children["forge_death_fx"].exclude = True
scene.frame_start, scene.frame_end = 0, DIE
scene.frame_set(0)
bpy.context.preferences.filepaths.save_version = 0
bpy.ops.wm.save_mainfile()
print("SAVED clips Idle", IDLE, "Research", RES, "Build", BUILD, "Die", DIE)
