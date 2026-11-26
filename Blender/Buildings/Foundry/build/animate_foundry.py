"""Stage 2 for Foundry.blend: the clips Idle, Research, Build and Die, and the foundry_death_fx Death clip.

  blender Foundry.blend --background --python animate_foundry.py

Clears the animation it made before, so it can be re-run. Every part is keyed in every clip, at 24 fps,
as per-object NLA tracks. Die is pushed last, so frame 0 (the exported rest pose) is the finished building
with nothing being made. In the game scripts/components/research_rig.gd plays them:
  Idle      4 s loop: the vent fan turns, the brazier and the melt glow, thin smoke from the stacks.
  Research  4 s loop while an upgrade is researched: the crucible tips and pours into the ingot mould, the
            press stamps an armour plate twice with sparks, the lathe rifles a barrel, heavy smoke.
  Build     4.2 s, scrubbed by construction progress (production_rig.gd show_construction).
  Die       2.7 s, with foundry_death_fx on the same timeline.
"""
import bpy, os, sys, random
from math import sin, cos, radians, pi
from mathutils import Vector as V, Matrix

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import importlib, building_kit
importlib.reload(building_kit)
from building_kit import *  # noqa: F401,F403

random.seed(29)
scene = bpy.context.scene
scene.render.fps = FPS
for c in bpy.context.view_layer.layer_collection.children:
    c.exclude = False
scene.frame_set(0)
clear_animation()
OB = bpy.data.objects
PARTS = [o for o in bpy.data.collections["foundry"].all_objects]
HOME = {o.name: o.matrix_basis.copy() for o in PARTS + list(bpy.data.collections["foundry_death_fx"].all_objects)}


def hidden(name):
    return Tm(HOME[name].translation) @ Sc(NIL)


def home(name):
    return lambda t: HOME[name]


def puff(name, phase, period, rise, s0, s1):
    """A smoke puff on a loop: rises `rise` and swells s0 -> s1 over each period, gone at both ends."""
    def fn(t):
        u = (t / period + phase) % 1.0
        s = (s0 + (s1 - s0) * u) * ramp(u, 0.0, 0.15) * (1 - ramp(u, 0.75, 1.0))
        drift = V((0.25 * u, 0.15 * u, rise * u))
        return Tm(HOME[name].translation + drift) @ Sc(ONE * max(s, 0.001))
    return fn


GLOWS = ["furnace_glow", "crucible_melt", "mould_glow", "pour_stream", "press_sparks", "lathe_sparks"]
SMOKE = ["smoke_%d" % (k + 1) for k in range(9)]
done = set()


def clip(name, frames, fns):
    """Bakes `fns` (part name -> fn(t)) and holds every other part still."""
    for o in PARTS:
        fn = fns.get(o.name)
        if fn is None:
            fn = (lambda t, n=o.name: hidden(n)) if o.name in SMOKE + ["pour_stream", "press_sparks", "lathe_sparks"] else home(o.name)
        bake(o, name, frames, fn)


# ================================================================= Idle (4 s loop)
IDLE = 96
LOOP = IDLE / FPS
idle = {
    "vent_fan": lambda t: HOME["vent_fan"] @ Rz(2 * pi * t / 2.0),
    "furnace_glow": lambda t: HOME["furnace_glow"] @ Sc(ONE * (0.92 + 0.06 * sin(2 * pi * t / LOOP * 2))),
    "crucible_melt": lambda t: HOME["crucible_melt"] @ Sc((1, 1, 0.9 + 0.1 * sin(2 * pi * t / LOOP))),
    "mould_glow": lambda t: hidden("mould_glow"),
}
for k in range(3):
    idle[SMOKE[k]] = puff(SMOKE[k], k / 3, LOOP, 1.2, 0.35, 0.9)
clip("Idle", IDLE, idle)

# ================================================================= Research (4 s loop)
RES = 96
TILT = radians(38)
D = 0.53                                     # ram travel onto the plate


def ram(t):
    u = t % 2.0
    return -D * (ramp(u, 0.72, 0.92) - ramp(u, 1.1, 1.85))


def sparks(t):
    u = t % 2.0
    k = lin(u, 0.9, 1.25)
    return 0.0 if k <= 0 or k >= 1 else sin(pi * k) * 1.3


def tilt(t):
    return TILT * ramp(t, 0.3, 1.0) * (1 - ramp(t, 2.5, 3.2))


def pour(t):
    return ramp(t, 0.85, 1.05) * (1 - ramp(t, 2.45, 2.7))


research = {
    "vent_fan": lambda t: HOME["vent_fan"] @ Rz(2 * pi * t),
    "furnace_glow": lambda t: HOME["furnace_glow"] @ Sc(ONE * (1.25 + 0.1 * sin(2 * pi * t * 2))),
    "crucible": lambda t: HOME["crucible"] @ Rx(tilt(t)),
    "crucible_melt": lambda t: HOME["crucible_melt"] @ Sc((1.05, 1.05, 1.1)),
    "pour_stream": lambda t: HOME["pour_stream"] @ Sc((1 + 0.15 * sin(t * 40), 1 + 0.15 * cos(t * 37), max(pour(t), 0.001))) if pour(t) > 0.001 else hidden("pour_stream"),
    "mould_glow": lambda t: HOME["mould_glow"] @ Sc(ONE * max(0.001, ramp(t, 1.0, 2.4) * (1 - ramp(t, 3.4, 3.95)))),
    "press_ram": lambda t: Tm(V((0, 0, ram(t)))) @ HOME["press_ram"],
    "press_sparks": lambda t: HOME["press_sparks"] @ Sc(ONE * max(sparks(t), 0.001)),
    "press_plate": lambda t: HOME["press_plate"] @ Sc((1, 1, 1 - 0.12 * (sparks(t) / 1.3))),
    "lathe_barrel": lambda t: HOME["lathe_barrel"] @ Rx(2 * pi * 1.5 * t),
    "lathe_tool": lambda t: Tm(V((0.9 * (0.5 - 0.5 * cos(2 * pi * t / LOOP)), 0, 0))) @ HOME["lathe_tool"],
    "lathe_sparks": lambda t: Tm(V((0.9 * (0.5 - 0.5 * cos(2 * pi * t / LOOP)), 0, 0))) @ HOME["lathe_sparks"]
    @ Sc(ONE * (0.55 + 0.45 * abs(sin(2 * pi * t * 3)))),
}
for k in range(9):
    research[SMOKE[k]] = puff(SMOKE[k], (k % 3) / 3 + (k // 3) / 9, LOOP / 2, 2.2, 0.6, 1.7)
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
    "hall": grow_z("hall", 0.12, 0.48),
    "hall_roof": lower("hall_roof", 0.44, 0.56, 0.68, 0.8),
    "furnace": grow_z("furnace", 0.24, 0.40),
    "crucible_gantry": grow_z("crucible_gantry", 0.30, 0.52),
    "crucible": pop("crucible", 0.52, 0.66),
    "mould": pop("mould", 0.46, 0.58),
    "press_frame": grow_z("press_frame", 0.34, 0.62),
    "lathe": pop("lathe", 0.58, 0.74),
    "plate_rack": pop("plate_rack", 0.78, 0.92),
    "stack_1": grow_z("stack_1", 0.64, 0.80),
    "stack_2": grow_z("stack_2", 0.68, 0.84),
    "stack_3": grow_z("stack_3", 0.72, 0.88),
    "furnace_glow": pop("furnace_glow", 0.84, 0.94),
    "crucible_melt": pop("crucible_melt", 0.86, 0.96),
    "mould_glow": lambda t: hidden("mould_glow"),
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
    "hall": wreck("hall", 0.25, 1.2, (0, 0.1, -0.6), Rx(radians(5)) @ Ry(radians(-4))),
    "hall_roof": wreck("hall_roof", 0.15, 0.9, (0.2, 0.1, -1.6), Rx(radians(-10)) @ Ry(radians(12))),
    "stack_1": wreck("stack_1", 0.1, 0.85, (-0.6, 0.3, -1.2), Ry(radians(-70))),
    "stack_2": wreck("stack_2", 0.2, 0.95, (-0.2, 0.7, -1.4), Rx(radians(65))),
    "stack_3": wreck("stack_3", 0.15, 0.9, (0.6, 0.3, -1.2), Ry(radians(75))),
    "crucible_gantry": wreck("crucible_gantry", 0.2, 0.9, (-0.1, -0.2, -0.3), Rx(radians(-14))),
    "crucible": wreck("crucible", 0.1, 0.7, (0, -0.25, -0.9), Rx(radians(110))),
    "furnace": wreck("furnace", 0.3, 1.0, (0, 0, -0.15), Rz(radians(8))),
    "mould": wreck("mould", 0.2, 0.8, (-0.3, -0.4, 0), Rz(radians(-25))),
    "press_frame": wreck("press_frame", 0.2, 1.1, (0.3, -0.2, -0.3), Ry(radians(22))),
    "press_ram": lambda t: Tm(V((0, 0, -0.5 * ramp(t, 0.15, 0.35)))) @ HOME["press_ram"],
    "lathe": wreck("lathe", 0.15, 0.8, (0.2, -0.3, 0), Rz(radians(15)) @ Rx(radians(-10))),
    "plate_rack": wreck("plate_rack", 0.2, 0.7, (0.3, -0.2, -0.1), Rz(radians(30))),
    "furnace_glow": gone("furnace_glow", 0.4),
    "crucible_melt": gone("crucible_melt", 0.3),
    "mould_glow": lambda t: hidden("mould_glow"),
}
clip("Die", DIE, die)

# the death effects on Die's timeline
FXO = list(bpy.data.collections["foundry_death_fx"].all_objects)
G = 9.8
for o in FXO:
    n = o.name
    h = HOME[n]
    if n == "Flash_Foundry":
        fn = lambda t, h=h: h @ Sc(ONE * (ramp(t, 0.0, 0.05) * (1 - ramp(t, 0.1, 0.45)) * 2.6 + 0.001))
    elif n.startswith("fx_fire"):
        late = random.uniform(0.0, 0.5)
        fn = lambda t, h=h, late=late: Tm(Z * 1.2 * ramp(t, late, late + 1.5)) @ h @ Sc(
            ONE * (ramp(t, late, late + 0.25) * (1 - ramp(t, late + 1.1, late + 1.9)) * 1.3 + 0.001))
    elif n.startswith("fx_smoke"):
        late = random.uniform(0.1, 0.8)
        fn = lambda t, h=h, late=late: Tm(V((0.4, 0.3, 2.5)) * ramp(t, late, DIE / FPS)) @ h @ Sc(
            ONE * (ramp(t, late, late + 0.6) * (1 - ramp(t, 2.2, DIE / FPS)) * 2.0 + 0.001))
    elif n.startswith("fx_plate"):
        a = random.uniform(0, 2 * pi)
        vr, vz = random.uniform(2.5, 5.0), random.uniform(3.5, 7.0)
        spin = V((random.uniform(-1, 1), random.uniform(-1, 1), random.uniform(-1, 1))).normalized()

        def fn(t, h=h, a=a, vr=vr, vz=vz, spin=spin):
            z = max(-1.3, vz * t - 0.5 * G * t * t)
            land = min(t, 2 * vz / G)
            q = Matrix.Rotation(10 * land, 4, spin)
            return Tm(V((cos(a) * vr * land, sin(a) * vr * land, z))) @ h @ q @ Sc(ONE * (1 - ramp(t, 2.2, DIE / FPS) + 0.001))
    elif n == "fx_spill":
        fn = lambda t, h=h: h @ Sc((1.3 * ramp(t, 0.3, 1.1) + 0.001, 1.3 * ramp(t, 0.3, 1.1) + 0.001,
                                    1.0 - ramp(t, 2.2, DIE / FPS) + 0.001))
    else:
        fn = lambda t, h=h: h
    bake(o, "Death", DIE, fn)

bpy.context.view_layer.layer_collection.children["foundry_death_fx"].exclude = True
scene.frame_start, scene.frame_end = 0, DIE
scene.frame_set(0)
bpy.context.preferences.filepaths.save_version = 0
bpy.ops.wm.save_mainfile()
print("SAVED clips Idle", IDLE, "Research", RES, "Build", BUILD, "Die", DIE)
