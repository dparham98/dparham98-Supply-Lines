"""Builds Foundry.blend from nothing: the Cyborgs' weapons and armour works (docs/FOUNDRY_MODEL.md).

  blender --background --python build_foundry.py

Everything is rebuilt each run. The hall's door faces -Y, Z up, base on Z = 0, and everything stays
inside the 6 x 6 m footprint (+-3 m). Materials and helpers follow the Barracks (bar_ colours as fdy_).
Clips are added by animate_foundry.py.

Layout: an armoured hall across the back with three cooling stacks and a vent fan on its roof; in the
open yard in front, a tilting crucible over a brazier pouring into an ingot mould (left), a stamping
press for armour plate (right) and a barrel-rifling lathe (front).
"""
import bpy, os, sys, random
from math import sin, cos, radians, pi
from mathutils import Vector as V, Matrix

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import importlib, building_kit
importlib.reload(building_kit)
from building_kit import *  # noqa: F401,F403

OUT = os.path.normpath(os.path.join(HERE, "..", "Foundry.blend"))
DRONE = os.environ.get("SL_DRONE_BLEND") or os.path.normpath(os.path.join(HERE, "..", "..", "..", "Vehicles", "Drone", "Drone.blend"))
random.seed(17)
bpy.ops.wm.read_factory_settings(use_empty=True)
FANG = load_fang(DRONE)

# ---------------------------------------------------------------- materials (the Barracks' colours)
material("fdy_armour", (0.090, 0.074, 0.046), 0.35, 0.68)
material("fdy_plate2", (0.105, 0.085, 0.050), 0.35, 0.66)
material("fdy_gunmetal", (0.100, 0.092, 0.078), 0.45, 0.55)
material("fdy_steel", (0.20, 0.185, 0.165), 0.55, 0.48)
material("fdy_rust", (0.13, 0.052, 0.022), 0.2, 0.85)
material("fdy_oxblood", (0.235, 0.030, 0.020), 0.15, 0.58)
material("brass", (0.40, 0.25, 0.08), 0.70, 0.42)
material("fdy_copper", (0.44, 0.185, 0.075), 0.70, 0.38)
material("fdy_black", (0.020, 0.020, 0.022), 0.10, 0.70)
material("fdy_hazard", (0.62, 0.42, 0.035), 0.05, 0.60)
material("fdy_interior", (0.030, 0.026, 0.022), 0.30, 0.70)
material("fdy_redglow", (0.30, 0.02, 0.01), 0.0, 0.5, (1.0, 0.06, 0.02), 2.2)
material("fdy_amber", (0.45, 0.20, 0.04), 0.0, 0.5, (1.0, 0.45, 0.10), 2.0)
material("fdy_molten", (0.9, 0.45, 0.08), 0.0, 0.4, (1.0, 0.50, 0.10), 5.0)
material("fdy_ember", (0.6, 0.12, 0.02), 0.0, 0.5, (1.0, 0.25, 0.04), 3.0)
material("fdy_spark", (1.0, 0.8, 0.4), 0.0, 0.4, (1.0, 0.75, 0.35), 8.0)
material("fdy_smoke", (0.12, 0.11, 0.10), 0.0, 1.0)
material("team_color", (0.235, 0.030, 0.020), 0.15, 0.55)

C = bpy.data.collections.new("foundry")
bpy.context.scene.collection.children.link(C)
B0 = 0.20                       # plinth top
HY0, HY1 = 0.25, 2.78           # hall front and back faces
HX = 2.78
EAVE = 2.55
RTOP = 2.85


def fin(P, name, world, parent=None):
    return finish(C, P, name, world, parent)


def plates(P, o, au, av, u0, u1, v0, v1, cols, rows, n, mat="fdy_gunmetal", gap=0.05):
    """Armour plates on a wall: o origin, au/av in-plane axes, n outward normal."""
    du, dv = (u1 - u0) / cols, (v1 - v0) / rows
    for i in range(cols):
        for j in range(rows):
            c = V(o) + au * (u0 + du * (i + 0.5)) + av * (v0 + dv * (j + 0.5)) + n * 0.03
            m = mat if random.random() > 0.25 else ("fdy_rust" if random.random() > 0.5 else "fdy_plate2")
            P.box(m, c, (du - gap, dv - gap, 0.05), basis(au, av, n), 0.012)
            for su in (-1, 1):
                for sv in (-1, 1):
                    P.rivet(c + au * su * (du / 2 - 0.08) + av * sv * (dv / 2 - 0.08) + n * 0.026, n, 0.018)


# ================================================================= plinth
P = Part()
P.box("fdy_gunmetal", (0, 0, B0 / 2), (5.96, 5.96, B0), None, 0.04)
P.box("fdy_black", (0, -1.3, B0 + 0.005), (5.6, 3.0, 0.01))
for k in range(12):                              # hazard stripes at the yard's front edge
    x = -2.6 + k * 0.47
    P.box("fdy_hazard" if k % 2 == 0 else "fdy_black", (x, -2.84, B0 + 0.008), (0.4, 0.16, 0.016), rot_z(radians(-20)))
for sx in (-1, 1):
    for sy in (-1, 1):
        P.box("fdy_steel", (sx * 2.84, sy * 2.84, B0 + 0.03), (0.22, 0.22, 0.06), None, 0.02)
plinth = fin(P, "plinth", Matrix.Identity(4))

# ================================================================= hall
P = Part()
P.box("fdy_armour", (0, (HY0 + HY1) / 2, (B0 + EAVE) / 2), (2 * HX, HY1 - HY0, EAVE - B0), None, 0.03)
# the door: a dark bay with a half-raised shutter and hazard posts
P.box("fdy_interior", (0, HY0 + 0.1, B0 + 0.95), (1.9, 0.24, 1.9))
for k in range(5):
    P.box("fdy_steel", (0, HY0 - 0.02, B0 + 1.42 + k * 0.1), (1.86, 0.04, 0.085), None, 0.01)
for sx in (-1, 1):
    P.box("fdy_gunmetal", (sx * 1.05, HY0 - 0.06, B0 + 1.1), (0.22, 0.18, 2.2), None, 0.02)
    for k in range(6):
        P.box("fdy_hazard" if k % 2 == 0 else "fdy_black", (sx * 1.05, HY0 - 0.16, B0 + 0.2 + k * 0.17), (0.2, 0.02, 0.16))
P.box("fdy_gunmetal", (0, HY0 - 0.07, B0 + 2.12), (2.3, 0.2, 0.22), None, 0.02)
# front wall plates either side of the door, side and back walls
plates(P, (0, HY0, 0), X, Z, 1.2, HX, B0 + 0.05, EAVE - 0.1, 2, 2, -Y)
plates(P, (0, HY0, 0), X, Z, -HX, -1.2, B0 + 0.05, EAVE - 0.1, 2, 2, -Y)
for sx in (-1, 1):
    plates(P, (sx * HX, 0, 0), Y, Z, HY0 + 0.05, HY1 - 0.05, B0 + 0.05, EAVE - 0.1, 3, 2, X * sx)
plates(P, (0, HY1, 0), X, Z, -HX + 0.05, HX - 0.05, B0 + 0.05, EAVE - 0.1, 4, 2, Y)
# oxblood band, red glow slits, team stripes on the corners
P.box("fdy_oxblood", (0, HY0 - 0.04, EAVE - 0.08), (2 * HX + 0.02, 0.06, 0.14))
for sx in (-1, 1):
    for k in range(2):
        P.box("fdy_redglow", (sx * (1.55 + k * 0.6), HY0 - 0.065, 1.95), (0.36, 0.02, 0.07))
    P.box("team_color", (sx * (HX - 0.12), HY0 - 0.07, 1.25), (0.16, 0.02, 1.6))
    P.box("fdy_gunmetal", (sx * HX, HY0, (B0 + EAVE) / 2 + 0.1), (0.3, 0.3, EAVE - B0 + 0.2), None, 0.03)
    P.box("fdy_gunmetal", (sx * HX, HY1, (B0 + EAVE) / 2 + 0.1), (0.3, 0.3, EAVE - B0 + 0.2), None, 0.03)
# copper pipes along the left wall into the yard
P.tube("fdy_copper", [(-HX - 0.06, 2.4, 0.5), (-HX - 0.06, 0.6, 0.5), (-HX - 0.06, 0.35, 0.9), (-2.5, -0.2, 0.9)], 0.05)
hall = fin(P, "hall", Matrix.Identity(4))
P = Part()
P.box("fdy_oxblood", (0, HY0 - 0.2, 2.42), (0.62, 0.04, 0.62), rot_y(radians(45)), 0.02)
fin(P, "hall_badge", Matrix.Identity(4), hall)
fang(C, FANG, "hall_fang", (0, HY0 - 0.23, 2.42), -Y, -Z, 0.62, hall)

P = Part()                                      # roof: a sloped armour shoulder and a deck
P.add(mk_loft([[V((-HX, HY0, EAVE)), V((HX, HY0, EAVE)), V((HX, HY1, EAVE)), V((-HX, HY1, EAVE))],
               [V((-HX + 0.35, HY0 + 0.3, RTOP)), V((HX - 0.35, HY0 + 0.3, RTOP)), V((HX - 0.35, HY1 - 0.2, RTOP)),
                V((-HX + 0.35, HY1 - 0.2, RTOP))]]), "fdy_plate2", True)
P.box("fdy_gunmetal", (0, (HY0 + HY1) / 2 + 0.05, RTOP + 0.03), (2 * HX - 0.8, HY1 - HY0 - 0.6, 0.06))
for x in (-1.9, -1.2, 1.9):
    P.cyl("fdy_gunmetal", (x, 2.05, RTOP), (x, 2.05, RTOP + 0.2), 0.32, seg=14)
P.cyl("fdy_gunmetal", (0.9, 1.25, RTOP), (0.9, 1.25, RTOP + 0.22), 0.5, seg=20)
P.cyl("fdy_black", (0.9, 1.25, RTOP + 0.15), (0.9, 1.25, RTOP + 0.23), 0.44, seg=20)
for k in range(4):
    a = pi / 4 + k * pi / 2
    P.rivet((0.9 + cos(a) * 0.47, 1.25 + sin(a) * 0.47, RTOP + 0.22), Z, 0.03)
roof = fin(P, "hall_roof", T((0, 0, EAVE)))
FAN = V((0.9, 1.25, RTOP + 0.27))
P = Part()                                      # vent fan, spins about Z
P.cyl("brass", FAN - Z * 0.03, FAN + Z * 0.05, 0.07, seg=10)
for k in range(5):
    a = 2 * pi * k / 5
    d = V((cos(a), sin(a), 0))
    P.box("fdy_steel", FAN + d * 0.22, (0.32, 0.1, 0.015), basis(d, Z.cross(d), Z) @ rot_x(radians(25)), 0.004)
fin(P, "vent_fan", T(FAN), roof)

# cooling stacks: tall drums with brass bands and blackened mouths
for k, x in enumerate((-1.9, -1.2, 1.9)):
    P = Part()
    h = (4.55, 4.15, 4.35)[k]
    P.cyl("fdy_gunmetal", (x, 2.05, RTOP + 0.2), (x, 2.05, h), 0.24, 0.2, seg=14)
    for z in (RTOP + 0.55, (RTOP + h) / 2 + 0.2, h - 0.25):
        P.cyl("brass", (x, 2.05, z), (x, 2.05, z + 0.07), 0.25, seg=14)
    P.cyl("fdy_black", (x, 2.05, h), (x, 2.05, h + 0.12), 0.23, 0.26, seg=14)
    P.cyl("fdy_rust", (x, 2.05, h - 0.02), (x, 2.05, h + 0.015), 0.205, seg=14)
    fin(P, "stack_%d" % (k + 1), T((x, 2.05, RTOP + 0.2)))

# ================================================================= crucible over a brazier, pouring into a mould
CX, CY, TZ = -1.6, -0.75, 1.62                  # crucible trunnion
P = Part()
for sx in (-1, 1):
    x = CX + sx * 0.78
    P.beam("fdy_gunmetal", (x, CY - 0.45, B0), (x, CY, TZ + 0.12), 0.14, 0.14, 0.02)
    P.beam("fdy_gunmetal", (x, CY + 0.45, B0), (x, CY, TZ + 0.12), 0.14, 0.14, 0.02)
    P.box("fdy_steel", (x, CY, TZ), (0.18, 0.22, 0.2), None, 0.02)
    P.cyl("brass", (x - sx * 0.08, CY, TZ), (x - sx * 0.14, CY, TZ), 0.08, seg=12)
P.cyl("fdy_copper", (CX + 0.92, CY, TZ), (CX + 1.05, CY, TZ), 0.16, seg=6)      # tilt wheel hub
P.cyl("brass", (CX + 1.02, CY, TZ), (CX + 1.06, CY, TZ), 0.3, seg=16)
fin(P, "crucible_gantry", Matrix.Identity(4))
P = Part()                                      # brazier under the crucible
P.box("fdy_gunmetal", (CX, CY, B0 + 0.22), (0.9, 0.9, 0.44), None, 0.03)
P.box("fdy_black", (CX, CY, B0 + 0.45), (0.72, 0.72, 0.04))
for k in range(4):
    a = k * pi / 2
    P.box("fdy_redglow", (CX + cos(a) * 0.46, CY + sin(a) * 0.46, B0 + 0.2), (0.3, 0.02, 0.06), rot_z(a + pi / 2))
brazier = fin(P, "furnace", Matrix.Identity(4))
P = Part()
for i in range(9):
    P.add(mk_ico((CX + random.uniform(-0.25, 0.25), CY + random.uniform(-0.25, 0.25), B0 + 0.5), random.uniform(0.07, 0.12),
                 (1, 1, 0.6)), "fdy_ember", True)
fin(P, "furnace_glow", T((CX, CY, B0 + 0.47)), brazier)
P = Part()                                      # crucible: a riveted bowl on trunnions, spout to -Y
P.add(mk_lathe([(0.0, TZ - 0.5), (0.3, TZ - 0.5), (0.42, TZ - 0.28), (0.46, TZ + 0.18), (0.5, TZ + 0.2),
                (0.5, TZ + 0.27), (0.4, TZ + 0.27), (0.36, TZ + 0.05), (0.0, TZ + 0.05)], (CX, CY, 0), Z, 20), "fdy_gunmetal")
P.cyl("brass", (CX, CY, TZ + 0.2), (CX, CY, TZ + 0.28), 0.52, seg=20)
for sx in (-1, 1):
    P.cyl("fdy_steel", (CX + sx * 0.45, CY, TZ), (CX + sx * 0.66, CY, TZ), 0.07, seg=10)
for k in range(10):
    a = 2 * pi * k / 10
    P.rivet((CX + cos(a) * 0.45, CY + sin(a) * 0.45, TZ - 0.05), V((cos(a), sin(a), 0)), 0.025)
P.add(mk_prism([(-0.13, 0), (0.13, 0), (0.07, 0.34), (-0.07, 0.34)], (CX, CY - 0.4, TZ + 0.22), X, -Y, -0.05, 0.04),
      "brass", True)
crucible = fin(P, "crucible", T((CX, CY, TZ)))
P = Part()
P.cyl("fdy_molten", (CX, CY, TZ + 0.17), (CX, CY, TZ + 0.2), 0.37, seg=18)
fin(P, "crucible_melt", T((CX, CY, TZ + 0.18)), crucible)
SPOUT = V((CX, CY - 0.72, TZ - 0.28))           # where the spout's lip is when the crucible is tipped 38 degrees
P = Part()                                      # the pour: a stream from the lip down into the mould
P.cyl("fdy_molten", SPOUT, SPOUT - Z * (SPOUT.z - B0 - 0.39), 0.05, 0.035, seg=8)
fin(P, "pour_stream", T(SPOUT))
MX, MY = CX, -1.55
P = Part()                                      # ingot mould on a cart
P.box("fdy_gunmetal", (MX, MY, B0 + 0.28), (1.2, 0.6, 0.18), None, 0.02)
for k in range(4):
    P.box("fdy_black", (MX - 0.42 + k * 0.28, MY, B0 + 0.37), (0.22, 0.42, 0.02))
for sx in (-1, 1):
    for sy in (-1, 1):
        P.cyl("fdy_black", (MX + sx * 0.45, MY + sy * 0.3, B0 + 0.1), (MX + sx * 0.45, MY + sy * 0.36, B0 + 0.1), 0.1, seg=10)
mould = fin(P, "mould", Matrix.Identity(4))
P = Part()
for k in range(4):
    P.box("fdy_molten", (MX - 0.42 + k * 0.28, MY, B0 + 0.385), (0.18, 0.36, 0.02))
fin(P, "mould_glow", T((MX, MY, B0 + 0.38)), mould)

# ================================================================= stamping press
PX, PY = 1.55, -0.85
P = Part()
P.box("fdy_gunmetal", (PX, PY, B0 + 0.3), (1.35, 1.0, 0.6), None, 0.04)
P.box("fdy_steel", (PX, PY, B0 + 0.66), (0.86, 0.66, 0.12), None, 0.02)            # bottom die
for sx in (-1, 1):
    P.box("fdy_armour", (PX + sx * 0.56, PY, 1.5), (0.22, 0.5, 2.4), None, 0.03)
    P.box("fdy_oxblood", (PX + sx * 0.56, PY - 0.26, 1.5), (0.16, 0.02, 1.9))
    for z in (0.9, 1.6, 2.3):
        P.rivet((PX + sx * 0.67, PY - 0.15, z), X * sx, 0.03)
P.box("fdy_armour", (PX, PY, 2.72), (1.45, 0.62, 0.5), None, 0.04)                 # crown
P.cyl("brass", (PX, PY, 2.95), (PX, PY, 3.35), 0.2, seg=14)
P.cyl("fdy_gunmetal", (PX, PY, 3.35), (PX, PY, 3.42), 0.24, seg=14)
P.tube("fdy_copper", [(PX + 0.2, PY, 3.25), (PX + 0.62, PY, 3.25), (PX + 0.62, PY + 0.4, 2.6), (PX + 0.62, PY + 0.6, B0 + 0.3)], 0.04)
for k in range(5):
    P.box("fdy_hazard" if k % 2 == 0 else "fdy_black", (PX - 0.5 + k * 0.25, PY - 0.51, B0 + 0.5), (0.24, 0.02, 0.12))
press = fin(P, "press_frame", Matrix.Identity(4))
RAM_TOP = 2.47
P = Part()                                      # ram: piston rod and the top die, pivot at the rod's top
P.cyl("fdy_steel", (PX, PY, RAM_TOP), (PX, PY, RAM_TOP - 0.55), 0.09, seg=12)
P.box("fdy_gunmetal", (PX, PY, RAM_TOP - 0.7), (0.9, 0.66, 0.3), None, 0.03)
P.box("fdy_steel", (PX, PY, RAM_TOP - 0.88), (0.8, 0.58, 0.06), None, 0.01)
for sx in (-1, 1):
    P.box("fdy_hazard", (PX + sx * 0.3, PY - 0.335, RAM_TOP - 0.7), (0.12, 0.01, 0.26))
fin(P, "press_ram", T((PX, PY, RAM_TOP)), press)
P = Part()                                      # the armour plate being stamped: a curved oxblood plate
rings = []
for i in range(7):
    u = -0.32 + i * 0.64 / 6
    z = B0 + 0.74 + 0.05 * (1 - (u / 0.32) ** 2)
    rings.append([V((PX + u, PY - 0.24, z)), V((PX + u, PY + 0.24, z)), V((PX + u, PY + 0.24, z + 0.035)), V((PX + u, PY - 0.24, z + 0.035))])
P.add(mk_loft(rings), "fdy_oxblood", True)
for sy in (-1, 1):
    P.rivet((PX - 0.22, PY + sy * 0.18, B0 + 0.79), Z, 0.02)
    P.rivet((PX + 0.22, PY + sy * 0.18, B0 + 0.79), Z, 0.02)
fin(P, "press_plate", T((PX, PY, B0 + 0.74)), press)
P = Part()                                      # sparks thrown from the die, keyed in on each blow
for i in range(14):
    a = random.uniform(0, 2 * pi)
    r = random.uniform(0.45, 0.8)
    d = V((cos(a), sin(a) * 0.7, random.uniform(0.1, 0.45))).normalized()
    c = V((PX + cos(a) * r, PY + sin(a) * r * 0.8, B0 + 0.8 + random.uniform(0, 0.3)))
    P.cyl("fdy_spark", c, c + d * random.uniform(0.08, 0.16), 0.012, 0.004, seg=4)
fin(P, "press_sparks", T((PX, PY, B0 + 0.8)), press)

# ================================================================= barrel-rifling lathe across the front
LY, LZ = -2.35, 0.78
P = Part()
P.box("fdy_gunmetal", (0.15, LY, B0 + 0.25), (2.1, 0.5, 0.5), None, 0.03)
P.box("fdy_steel", (0.15, LY, B0 + 0.52), (2.0, 0.34, 0.04))
P.box("fdy_armour", (-0.78, LY, LZ), (0.42, 0.52, 0.6), None, 0.03)             # headstock
P.cyl("brass", (-0.56, LY, LZ), (-0.5, LY, LZ), 0.14, seg=12)
P.box("fdy_armour", (1.05, LY, LZ - 0.06), (0.26, 0.36, 0.42), None, 0.02)       # tailstock
P.cyl("fdy_steel", (0.92, LY, LZ), (0.85, LY, LZ), 0.05, 0.02, seg=10)
P.box("fdy_redglow", (-0.78, LY - 0.265, LZ + 0.15), (0.24, 0.01, 0.05))
lathe = fin(P, "lathe", Matrix.Identity(4))
P = Part()                                      # the barrel in the chuck: spins about X
P.cyl("fdy_steel", (-0.5, LY, LZ), (0.86, LY, LZ), 0.065, 0.055, seg=10)
for x in (-0.45, 0.1, 0.65):
    P.cyl("fdy_black", (x, LY, LZ), (x + 0.04, LY, LZ), 0.07, seg=10)
P.cyl("brass", (-0.5, LY, LZ), (-0.4, LY, LZ), 0.12, seg=6)
fin(P, "lathe_barrel", T((0, LY, LZ)), lathe)
P = Part()                                      # the cutting carriage, slides along X
P.box("fdy_gunmetal", (0, LY + 0.0, B0 + 0.6), (0.24, 0.42, 0.12), None, 0.01)
P.box("fdy_oxblood", (0, LY + 0.16, LZ - 0.04), (0.12, 0.14, 0.16), None, 0.01)
P.cyl("fdy_steel", (0, LY + 0.1, LZ), (0, LY + 0.065, LZ), 0.015, 0.005, seg=6)
fin(P, "lathe_tool", T((-0.3, LY, LZ)), lathe)
P = Part()
for i in range(8):
    d = V((random.uniform(-0.6, 0.6), random.uniform(-1, -0.3), random.uniform(0.2, 0.9))).normalized()
    c = V((0, LY + 0.06, LZ + 0.02))
    P.cyl("fdy_spark", c + d * 0.03, c + d * random.uniform(0.12, 0.24), 0.008, 0.003, seg=4)
fin(P, "lathe_sparks", T((-0.3, LY + 0.06, LZ)), lathe)

# finished work: a rack of plates and barrels by the press
P = Part()
P.box("fdy_gunmetal", (2.45, -2.3, B0 + 0.04), (0.8, 0.8, 0.08))
for k in range(4):
    P.box("fdy_oxblood" if k % 2 else "fdy_plate2", (2.45, -2.3, B0 + 0.12 + k * 0.06), (0.62, 0.5, 0.05), rot_z(radians(4 * k)), 0.01)
for k in range(3):
    P.cyl("fdy_steel", (2.12 + k * 0.15, -2.62, B0 + 0.45), (2.12 + k * 0.15, -2.62, B0 + 1.4), 0.05, seg=8)
P.beam("fdy_gunmetal", (2.0, -2.68, B0 + 1.2), (2.5, -2.68, B0 + 1.2), 0.06, 0.06)
fin(P, "plate_rack", Matrix.Identity(4))

# smoke puffs over the stacks (keyed rising in Idle and Research)
for k in range(9):
    P = Part()
    P.add(mk_ico((0, 0, 0), 0.3, (1, 1, 0.85), None, 2), "fdy_smoke")
    x = (-1.9, -1.2, 1.9)[k % 3]
    fin(P, "smoke_%d" % (k + 1), T((x, 2.05, 4.6)))

# ================================================================= death effects (keyed by animate_foundry.py)
D = bpy.data.collections.new("foundry_death_fx")
bpy.context.scene.collection.children.link(D)
P = Part()
P.add(mk_ico((0, 0, 0), 1.0, (1, 1, 0.8), None, 2), "fdy_spark")
finish(D, P, "Flash_Foundry", T((0, 0.5, 1.6)), None)
for i in range(6):
    P = Part()
    P.add(mk_ico((0, 0, 0), 0.6, (1, 1, 1.2), None, 2), "fdy_ember")
    finish(D, P, "fx_fire_%d" % i, T((random.uniform(-2, 2), random.uniform(-1.5, 2), 1.0)), None)
for i in range(10):
    P = Part()
    P.add(mk_ico((0, 0, 0), 0.7, (1, 1, 0.9), None, 2), "fdy_smoke")
    finish(D, P, "fx_smoke_%d" % i, T((random.uniform(-2, 2), random.uniform(-1.5, 2.2), 2.0)), None)
for i in range(14):
    P = Part()
    P.box(random.choice(["fdy_armour", "fdy_gunmetal", "fdy_oxblood"]), (0, 0, 0),
          (random.uniform(0.25, 0.5), random.uniform(0.2, 0.4), 0.05), None, 0.01)
    finish(D, P, "fx_plate_%d" % i, T((0, 0.6, 1.5)), None)
P = Part()
P.add(mk_lathe([(0.0, 0.0), (1.0, 0.0), (0.95, 0.03), (0.0, 0.04)], seg=24), "fdy_molten", True)
finish(D, P, "fx_spill", T((CX, CY - 0.4, B0 + 0.01)), None)

bpy.context.view_layer.layer_collection.children["foundry_death_fx"].exclude = True
bpy.context.view_layer.update()
tris = 0
for o in C.all_objects:
    if o.type == 'MESH':
        o.data.calc_loop_triangles()
        tris += len(o.data.loop_triangles)
lo, hi = V((9, 9, 9)), V((-9, -9, -9))
for o in C.all_objects:
    if o.type == 'MESH' and not o.name.startswith(("smoke_", "pour_")):
        for v in o.data.vertices:
            w = o.matrix_world @ v.co
            lo = V([min(a, b) for a, b in zip(lo, w)])
            hi = V([max(a, b) for a, b in zip(hi, w)])
print("TRIS", tris, "BOUNDS", [round(v, 2) for v in lo], [round(v, 2) for v in hi])
bpy.context.preferences.filepaths.save_version = 0
bpy.ops.wm.save_as_mainfile(filepath=OUT)
print("SAVED", OUT, len(C.all_objects), "objects")
