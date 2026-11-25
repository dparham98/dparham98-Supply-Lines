"""Stage 2 for Wainwright.blend: the clips Idle, Build and Die, and the wainwright_death_fx Death clip.

  blender Wainwright.blend --background --python animate_wainwright.py

Clears the animation it made before, so it can be re-run. Every part is keyed in every clip, at 24 fps,
as per-object NLA tracks. Die is pushed last, so frame 0 (the exported rest pose) is the finished building.
In the game scripts/components/production_rig.gd plays them (the Wainwright makes no units, so there is no
production clip):
  Idle      4 s loop: the wainwright dresses the wheel with an adze, chips flying at each cut, and turns it a
            spoke every 2 s; the rail on the sheerlegs sways, the banner stirs, smoke from the chimney.
  Build     4.2 s, scrubbed by construction progress (production_rig.gd show_construction).
  Die       2.7 s, with wainwright_death_fx on the same timeline.
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

random.seed(37)
scene = bpy.context.scene
scene.render.fps = FPS
for c in bpy.context.view_layer.layer_collection.children:
    c.exclude = False
scene.frame_set(0)
clear_animation()
PARTS = [o for o in bpy.data.collections["wainwright"].all_objects]
HOME = {o.name: o.matrix_basis.copy() for o in PARTS + list(bpy.data.collections["wainwright_death_fx"].all_objects)}


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


SMOKE = ["smoke_%d" % (k + 1) for k in range(4)]
QUIET = SMOKE + ["chips"]


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
LIFT = radians(100)                          # the adze raised; 0 is the cut on the wheel


def cut(t):
    return t % 1.0


def adze(t):
    u = cut(t)
    return LIFT * ramp(u, 0.1, 0.6) * (1 - ramp(u, 0.82, 0.97))


def chips(t):
    k = ((cut(t) - 0.97) % 1.0) / 0.25
    return 0.0 if k >= 1 else sin(pi * k) * 1.3


idle = {
    "wainwright_arm": lambda t: HOME["wainwright_arm"] @ Rx(adze(t)),
    "chips": lambda t: HOME["chips"] @ Tm(V((0, 0, 0.12 * min(1.0, ((cut(t) - 0.97) % 1.0) / 0.25)))) @ Sc(ONE * max(chips(t), 0.001)),
    "wheel": lambda t: HOME["wheel"] @ Rz((2 * pi / 10) * (int(t // 2.0) + ramp(t % 2.0, 1.4, 1.9))),
    "crane_load": lambda t: HOME["crane_load"] @ Rx(0.05 * sin(2 * pi * t / LOOP)) @ Ry(0.03 * sin(2 * pi * t / LOOP * 2 + 1.0)),
    "banner": banner("banner", 0.0, 0.06),
}
for k in range(3):
    idle[SMOKE[k]] = puff(SMOKE[k], k / 3, LOOP, 1.2, 0.25, 0.75)
clip("Idle", IDLE, idle)

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
    "workshop": grow_z("workshop", 0.10, 0.46),
    "roof": lower("roof", 0.44, 0.56, 0.66, 0.7),
    "wheel_bench": pop("wheel_bench", 0.52, 0.64),
    "rail_stack": grow_z("rail_stack", 0.30, 0.56),
    "sheerlegs": grow_z("sheerlegs", 0.60, 0.78),
    "crane_load": pop("crane_load", 0.78, 0.9),
    "banner_pole": grow_z("banner_pole", 0.70, 0.84),
    "banner": pop("banner", 0.84, 0.94),
    "wainwright": pop("wainwright", 0.88, 1.0),
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
    "plinth": lambda t: Tm(Z * (sink(t) - 0.06 * ramp(t, 0.2, 1.0))) @ HOME["plinth"],
    "workshop": wreck("workshop", 0.2, 1.0, (0.1, 0.2, -0.4), Rx(radians(7)) @ Ry(radians(-5))),
    "roof": wreck("roof", 0.1, 0.75, (0.2, -0.3, -1.4), Rx(radians(-16)) @ Ry(radians(9))),
    "wheel_bench": wreck("wheel_bench", 0.15, 0.6, (-0.3, -0.3, 0), Rz(radians(28))),
    "rail_stack": wreck("rail_stack", 0.2, 0.7, (0.1, -0.1, -0.05), Rz(radians(-8))),
    "sheerlegs": wreck("sheerlegs", 0.1, 0.9, (0.3, -0.4, 0), Ry(radians(70))),
    "crane_load": lambda t: hidden("crane_load") if t > 0.5 else HOME["crane_load"],
    "wainwright": gone("wainwright", 0.12),
    "banner_pole": wreck("banner_pole", 0.1, 0.9, (-0.2, -0.2, 0), Ry(radians(-75))),
    "banner": gone("banner", 0.6),
}
clip("Die", DIE, die)

# the death effects on Die's timeline
FXO = list(bpy.data.collections["wainwright_death_fx"].all_objects)
G = 9.8
for o in FXO:
    n = o.name
    h = HOME[n]
    if n == "Flash_Wainwright":
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

bpy.context.view_layer.layer_collection.children["wainwright_death_fx"].exclude = True
scene.frame_start, scene.frame_end = 0, DIE
scene.frame_set(0)
bpy.context.preferences.filepaths.save_version = 0
bpy.ops.wm.save_mainfile()
print("SAVED clips Idle", IDLE, "Build", BUILD, "Die", DIE)
