"""Builds DragonYard.blend from nothing: the Arthurian Knights' Dragon Yard (docs/DRAGON_YARD_MODEL.md), where
Azure Dragons are raised and the coal trains ordered.

  blender --background --python build_dragon_yard.py

Everything is rebuilt each run. The open front faces -Y, Z up, base on Z = 0, inside the 6 x 6 m footprint.
The palette is the Keep's and Chapterhouse's: ivory stone, timber, brass and a team-blue roof. The helpers come
from ../../Foundry/build/building_kit.py, and animate_dragon_yard.py adds the clips.

Layout: the dragon pen fills the left and back, a stone hall under a team-blue gable roof with a 3.3 x 3.3 m
open front (the Azure Dragon is 3.6 m across with its wings folded and 3.2 m tall). Inside, a dragon egg glows
in a straw nest beside a feed trough, and a keeper with a pitchfork stands at the mouth by a brazier. Behind on
the right rises the roost: a stone tower with a timber perch and a pennant on top. In front on the right is the
rail and wagon works: a length of track with a coal wagon on it, a buffer stop, and a smith at an anvil by a
forge.
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

OUT = os.path.normpath(os.path.join(HERE, "..", "DragonYard.blend"))
random.seed(61)
bpy.ops.wm.read_factory_settings(use_empty=True)

material("dyd_stone", (0.62, 0.60, 0.55), 0.0, 0.85)
material("dyd_flag", (0.50, 0.48, 0.44), 0.0, 0.9)
material("dyd_ivory", (0.83, 0.82, 0.73), 0.35, 0.43)
material("dyd_timber", (0.18, 0.10, 0.05), 0.0, 0.8)
material("dyd_timber_light", (0.42, 0.28, 0.15), 0.0, 0.75)
material("dyd_timber_dark", (0.08, 0.045, 0.022), 0.0, 0.85)
material("dyd_iron", (0.22, 0.24, 0.26), 0.7, 0.45)
material("dyd_rail", (0.46, 0.49, 0.52), 0.8, 0.35)
material("dyd_coal", (0.035, 0.035, 0.04), 0.1, 0.6)
material("dyd_straw", (0.72, 0.56, 0.24), 0.0, 0.9)
material("dyd_meat", (0.45, 0.08, 0.06), 0.0, 0.6)
material("dyd_cloth", (0.34, 0.28, 0.20), 0.0, 0.85)
material("dyd_leather", (0.13, 0.07, 0.035), 0.0, 0.7)
material("dyd_skin", (0.55, 0.36, 0.25), 0.0, 0.7)
material("dyd_interior", (0.022, 0.025, 0.030), 0.1, 0.85)
material("dyd_amber_glass", (1.0, 0.69, 0.29), 0.14, 0.2, (1.0, 0.65, 0.22), 2.2)
material("dyd_egg", (0.10, 0.32, 0.85), 0.3, 0.25, (0.2, 0.45, 1.0), 0.6)
material("dyd_egg_glow", (0.45, 0.75, 1.0), 0.0, 0.5, (0.35, 0.65, 1.0), 3.0)
material("dyd_smoke", (0.17, 0.16, 0.15), 0.0, 1.0)
material("dyd_fire", (0.9, 0.4, 0.06), 0.0, 0.5, (1.0, 0.42, 0.06), 5.0)
material("dyd_spark", (1.0, 0.85, 0.5), 0.0, 0.4, (1.0, 0.8, 0.4), 8.0)
material("brass", (0.71, 0.44, 0.12), 0.65, 0.37)
material("team_color", (0.025, 0.075, 0.38), 0.08, 0.64)
material("team_color_shadow", (0.013, 0.033, 0.18), 0.04, 0.70)

C = bpy.data.collections.new("dragon_yard")
bpy.context.scene.collection.children.link(C)
B0 = 0.16


def fin(P, name, world, parent=None):
    return finish(C, P, name, world, parent)


def star(P, c, au, av, r, d0, d1, mat="brass"):
    """The Knights' eight-pointed star, flat in the au/av plane."""
    pts = []
    for k in range(16):
        a = pi / 2 + 2 * pi * k / 16
        rr = r if k % 2 == 0 else r * 0.38
        pts.append((cos(a) * rr, sin(a) * rr))
    P.add(mk_prism(pts, c, au, av, d0, d1), mat, True)


# ================================================================= plinth: stone kerb and flagstones
P = Part()
P.box("dyd_stone", (0, 0, B0 / 2), (5.96, 5.96, B0), None, 0.02)
for i in range(9):
    for j in range(4):
        x = -2.62 + i * 0.66
        y = -2.62 + j * 0.62
        if x > 1.2:
            continue                                                            # the works corner is planked
        P.box("dyd_flag", (x + random.uniform(-0.02, 0.02), y, B0 + 0.008), (0.6, 0.56, 0.02), None, 0.01)
for i in range(6):
    P.box("dyd_timber_light" if i % 2 else "dyd_timber", (1.45 + i * 0.27, -1.1, B0 + 0.01), (0.25, 3.6, 0.02), None, 0.005)
plinth = fin(P, "plinth", Matrix.Identity(4))

# ================================================================= the dragon pen: stone hall, open front
PX0, PX1, PY0, PY1, WH = -2.9, 1.0, -0.95, 2.9, 3.3
PXC = (PX0 + PX1) / 2
P = Part()
P.box("dyd_straw", (PXC, (PY0 + PY1) / 2, B0 + 0.03), (PX1 - PX0 - 0.3, PY1 - PY0 - 0.2, 0.06), None, 0.02)
P.box("dyd_interior", (PXC, PY1 - 0.9, B0 + 1.6), (PX1 - PX0 - 0.6, 1.2, 3.0))                  # dark back
for sx, x in ((-1, PX0), (1, PX1)):
    P.box("dyd_stone", (x - sx * 0.15, (PY0 + PY1) / 2, B0 + 0.3), (0.34, PY1 - PY0, 0.6), None, 0.02)
    P.box("dyd_ivory", (x - sx * 0.13, (PY0 + PY1) / 2, B0 + (WH + 0.26) / 2), (0.24, PY1 - PY0 - 0.1, WH + 0.26), None, 0.01)
    P.box("dyd_timber", (x - sx * 0.13, (PY0 + PY1) / 2, B0 + WH + 0.2), (0.3, PY1 - PY0 + 0.1, 0.12), None, 0.01)  # wall plate
    for y in (PY0 + 0.6, (PY0 + PY1) / 2 + 0.3, PY1 - 0.2):                                       # buttresses
        P.box("dyd_stone", (x + sx * 0.06, y, B0 + 1.2), (0.26, 0.34, 2.4), None, 0.02)
        P.add(mk_prism([(-0.17, 0), (0.17, 0), (0, 0.35)], (x + sx * 0.06, y, B0 + 2.4), Y, Z, -0.13, 0.13),
              "dyd_stone", True)
    for y in (0.25, 1.55):                                                                        # lancet windows
        P.box("dyd_amber_glass", (x + sx * 0.005, y, B0 + 2.1), (0.02, 0.28, 0.7))
        P.box("brass", (x + sx * 0.01, y, B0 + 2.5), (0.02, 0.34, 0.05))
P.box("dyd_stone", (PXC, PY1 - 0.15, B0 + 0.3), (PX1 - PX0, 0.34, 0.6), None, 0.02)            # back wall
P.box("dyd_ivory", (PXC, PY1 - 0.13, B0 + (WH + 0.26) / 2), (PX1 - PX0 - 0.1, 0.24, WH + 0.26), None, 0.01)
for sx in (-1, 1):                                                                                # front piers
    x = PX0 + 0.2 if sx < 0 else PX1 - 0.2
    P.box("dyd_stone", (x, PY0, B0 + (WH + 0.2) / 2), (0.46, 0.46, WH + 0.2), None, 0.02)
    P.box("brass", (x, PY0 - 0.235, B0 + WH - 0.3), (0.3, 0.02, 0.06))
    P.box("team_color", (x, PY0 - 0.245, B0 + 1.9), (0.26, 0.02, 1.4))                        # pier banners
    star(P, V((x, PY0 - 0.26, B0 + 2.2)), X, Z, 0.09, -0.01, 0.01)
P.box("dyd_timber", (PXC, PY0, B0 + WH + 0.08), (PX1 - PX0 + 0.1, 0.4, 0.3), None, 0.02)        # lintel
P.box("brass", (PXC, PY0 - 0.205, B0 + WH + 0.08), (PX1 - PX0 + 0.1, 0.02, 0.08))
for sx in (-1, 1):                                                                                # knee braces
    x = PX0 + 0.42 if sx < 0 else PX1 - 0.42
    P.beam("dyd_timber_dark", (x, PY0 - 0.05, B0 + WH - 0.75), (x - sx * 0.55, PY0 - 0.05, B0 + WH - 0.05), 0.12, 0.12)
pen = fin(P, "pen", Matrix.Identity(4))

# the roof: a gable along Y, so the front shows a gable over the opening
RZ0, RZ1 = B0 + WH + 0.22, B0 + WH + 1.45
XE0, XE1 = PX0 - 0.28, PX1 + 0.28
YF, YB = PY0 - 0.42, PY1 + 0.2
P = Part()
for xe in (XE0, XE1):
    P.add(mk_loft([[V((xe, YF, RZ0)), V((xe, YB, RZ0)), V((xe, YB, RZ0 + 0.09)), V((xe, YF, RZ0 + 0.09))],
                   [V((PXC, YF, RZ1)), V((PXC, YB, RZ1)), V((PXC, YB, RZ1 + 0.09)), V((PXC, YF, RZ1 + 0.09))]]),
          "team_color", True)
    for k in range(5):
        t = (k + 0.5) / 5
        x = xe + (PXC - xe) * t
        z = RZ0 + (RZ1 - RZ0) * t + 0.095
        P.box("team_color_shadow", (x, (YF + YB) / 2, z), (0.03, YB - YF, 0.012))
    P.beam("brass", (xe, YF - 0.01, RZ0 + 0.05), (PXC, YF - 0.01, RZ1 + 0.05), 0.06, 0.05)      # gilded verge
P.box("brass", (PXC, (YF + YB) / 2, RZ1 + 0.11), (0.12, YB - YF + 0.05, 0.07), None, 0.01)
for y in (PY0 - 0.12, PY1 - 0.05):                                                               # gables
    P.add(mk_prism([(PX0 - PXC, 0), (PX1 - PXC, 0), (0, RZ1 - RZ0 - 0.05)], (PXC, y, RZ0 - 0.02), X, Z, -0.06, 0.06),
          "dyd_ivory", True)
P.add(mk_prism([(-0.95, 0), (0.95, 0), (0, 0.8)], (PXC, PY0 - 0.2, RZ0 + 0.06), X, Z, -0.02, 0.02), "team_color", True)
star(P, V((PXC, PY0 - 0.23, RZ0 + 0.38)), X, Z, 0.22, -0.012, 0.012)
for xe in (XE0, XE1):                                                                            # finials
    P.cyl("brass", (xe, YF, RZ0 - 0.1), (xe, YF, RZ0 + 0.3), 0.04, 0.01, seg=6)
P.cyl("brass", (PXC, YF, RZ1), (PXC, YF, RZ1 + 0.5), 0.05, 0.01, seg=6)
roof = fin(P, "roof", T((PXC, (YF + YB) / 2, RZ0)))

# the nest and the egg, the feed trough and hay
NC = V((PXC - 0.1, 1.45, B0 + 0.06))
P = Part()
P.add(mk_annulus(NC, 0.32, 0.78, 0.26, seg=16), "dyd_straw", False)
for k in range(10):
    a = 2 * pi * k / 10
    P.cyl("dyd_straw", NC + V((cos(a) * 0.55, sin(a) * 0.55, 0.22)), NC + V((cos(a + 0.9) * 0.62, sin(a + 0.9) * 0.62, 0.3)), 0.03, seg=4)
fin(P, "nest", T(NC))
EC = NC + V((0, 0, 0.42))
P = Part()
P.add(mk_ico(EC, 0.3, (1, 1, 1.32), None, 2), "dyd_egg", False)
for k in range(5):
    a = 2 * pi * k / 5
    P.add(mk_ico(EC + V((cos(a) * 0.27, sin(a) * 0.27, 0.05)), 0.07, (1, 1, 1.4), None, 1), "brass", False)  # scales
egg = fin(P, "egg", T(EC - V((0, 0, 0.36))))
P = Part()                                                                                        # motes that circle it as it quickens
for k in range(6):
    a = 2 * pi * k / 6
    P.add(mk_ico(EC + V((cos(a) * 0.5, sin(a) * 0.5, 0.1 * sin(3 * a))), 0.045, (1, 1, 1), None, 1), "dyd_egg_glow", False)
fin(P, "egg_motes", T(EC))
P = Part()
TX, TY = PX0 + 0.55, 1.2
P.box("dyd_timber", (TX, TY, B0 + 0.3), (0.5, 1.4, 0.4), None, 0.02)
P.box("dyd_interior", (TX, TY, B0 + 0.49), (0.38, 1.28, 0.04))
for k in range(4):
    P.add(mk_ico((TX + random.uniform(-0.1, 0.1), TY - 0.45 + k * 0.3, B0 + 0.53), 0.11, (1.4, 0.9, 0.6), None, 1), "dyd_meat", False)
for k, (x, y, z) in enumerate(((PX0 + 0.55, -0.2, 0.2), (PX0 + 0.55, 0.2, 0.2), (PX0 + 0.55, 0.0, 0.6))):  # hay bales
    P.box("dyd_straw", (x, y, B0 + z), (0.5, 0.4, 0.4), rot_z(radians(4 * k)), 0.03)
fin(P, "trough", Matrix.Identity(4))

# ================================================================= the roost: a stone tower with a perch on top
RX, RY, RS, RH = 2.15, 2.15, 1.3, 4.1
P = Part()
P.box("dyd_stone", (RX, RY, B0 + 0.4), (RS + 0.12, RS + 0.12, 0.8), None, 0.03)
P.box("dyd_ivory", (RX, RY, B0 + RH / 2), (RS, RS, RH), None, 0.02)
P.box("dyd_stone", (RX, RY, B0 + RH + 0.08), (RS + 0.16, RS + 0.16, 0.16), None, 0.02)
for i in range(4):                                                                                # crenels
    for s in (-1, 1):
        o = -0.5 + i * 0.33
        P.box("dyd_stone", (RX + o, RY + s * (RS / 2 + 0.02), B0 + RH + 0.32), (0.18, 0.14, 0.32), None, 0.01)
        P.box("dyd_stone", (RX + s * (RS / 2 + 0.02), RY + o, B0 + RH + 0.32), (0.14, 0.18, 0.32), None, 0.01)
P.box("dyd_interior", (RX - 0.1, RY - RS / 2 - 0.005, B0 + 0.8), (0.6, 0.02, 1.3))              # door
P.box("brass", (RX - 0.1, RY - RS / 2 - 0.012, B0 + 1.48), (0.66, 0.02, 0.06))
P.box("dyd_amber_glass", (RX + RS / 2 + 0.005, RY, B0 + 2.8), (0.02, 0.2, 0.55))
P.box("dyd_amber_glass", (RX, RY - RS / 2 - 0.005, B0 + 3.0), (0.2, 0.02, 0.55))
P.box("team_color", (RX + RS / 2 + 0.005, RY - 0.35, B0 + 2.0), (0.02, 0.3, 0.9))
tower = fin(P, "roost_tower", T((RX, RY, B0)))
PZ = B0 + RH + 0.16
P = Part()                                                                                        # the perch beam on forked posts
for x in (RX - 0.45, RX + 0.45):
    P.cyl("dyd_timber", (x, RY, PZ), (x, RY, PZ + 0.9), 0.07, 0.06, seg=8)
    for s in (-1, 1):
        P.cyl("dyd_timber", (x, RY, PZ + 0.85), (x + s * 0.12, RY, PZ + 1.05), 0.04, seg=6)
P.cyl("dyd_timber_light", (RX - 1.35, RY, PZ + 0.98), (RX + 0.8, RY, PZ + 0.98), 0.1, 0.09, seg=10)
P.add(mk_annulus(V((RX - 1.2, RY, PZ + 0.9)), 0.08, 0.11, 0.03, seg=12), "brass", True)
P.cyl("dyd_iron", (RX - 1.2, RY, PZ + 0.98), (RX - 1.2, RY, PZ + 0.62), 0.012, seg=4)            # chain
for x in (RX - 1.3, RX - 0.8, RX + 0.1, RX + 0.6):                                                # claw marks
    P.box("dyd_timber_dark", (x, RY - 0.09, PZ + 1.0), (0.02, 0.02, 0.12), rot_y(radians(20)))
perch = fin(P, "perch", T((RX, RY, PZ)), tower)
P = Part()
x, y = RX + RS / 2 - 0.05, RY + RS / 2 - 0.05
P.cyl("dyd_timber_dark", (x, y, PZ), (x, y, PZ + 1.6), 0.03, 0.025, seg=6)
P.add(mk_ico((x, y, PZ + 1.63), 0.05), "brass", True)
pole = fin(P, "pennant_pole", T((x, y, PZ)), tower)
P = Part()
P.add(mk_prism([(0, 0), (0, -0.4), (-0.85, -0.2)], (x, y, PZ + 1.55), X, Z, -0.01, 0.01), "team_color", True)
fin(P, "pennant", T((x, y, PZ + 1.55)), pole)

# ================================================================= rail and wagon works (front right)
KX, KY0, KY1 = 2.35, -2.92, 0.75
P = Part()
for k in range(10):                                                                               # sleepers
    y = KY0 + 0.15 + k * (KY1 - KY0 - 0.3) / 9
    P.box("dyd_timber", (KX, y, B0 + 0.06), (1.05, 0.16, 0.08), None, 0.01)
for sx in (-1, 1):
    P.box("dyd_rail", (KX + sx * 0.34, (KY0 + KY1) / 2, B0 + 0.14), (0.06, KY1 - KY0, 0.06), None, 0.005)
    P.box("dyd_rail", (KX + sx * 0.34, (KY0 + KY1) / 2, B0 + 0.11), (0.12, KY1 - KY0, 0.02))
P.box("dyd_timber", (KX, KY1 - 0.08, B0 + 0.37), (1.0, 0.18, 0.3), None, 0.02)                   # buffer stop
for sx in (-1, 1):
    P.cyl("brass", (KX + sx * 0.3, KY1 - 0.17, B0 + 0.4), (KX + sx * 0.3, KY1 - 0.3, B0 + 0.4), 0.07, seg=8)
    P.beam("dyd_timber_dark", (KX + sx * 0.4, KY1 + 0.15, B0 + 0.07), (KX + sx * 0.4, KY1 - 0.05, B0 + 0.5), 0.1, 0.1)
for k in range(4):                                                                                # spare rails
    P.box("dyd_rail", (1.25 + k * 0.1, -2.25, B0 + 0.05 + (k % 2) * 0.06), (0.07, 1.1, 0.05), None, 0.005)
track = fin(P, "track", Matrix.Identity(4))

WY, WZ = -1.45, B0 + 0.44                                                                          # the coal wagon
P = Part()
P.box("dyd_timber_dark", (KX, WY, WZ), (0.86, 1.5, 0.12), None, 0.01)                             # bed
for sx in (-1, 1):
    P.box("dyd_timber", (KX + sx * 0.43, WY, WZ + 0.3), (0.06, 1.5, 0.5), None, 0.01)
for sy in (-1, 1):
    P.box("dyd_timber", (KX, WY + sy * 0.75, WZ + 0.3), (0.86, 0.06, 0.5), None, 0.01)
for k in range(3):                                                                                # iron straps
    y = WY - 0.5 + k * 0.5
    for sx in (-1, 1):
        P.box("dyd_iron", (KX + sx * 0.465, y, WZ + 0.3), (0.012, 0.06, 0.52))
P.box("brass", (KX, WY - 0.79, WZ + 0.5), (0.9, 0.02, 0.05))
P.box("team_color", (KX - 0.47, WY, WZ + 0.3), (0.012, 0.5, 0.28))
star(P, V((KX - 0.48, WY, WZ + 0.3)), Y, Z, 0.1, -0.012, 0.0)
P.add(mk_ico((KX, WY, WZ + 0.5), 0.5, (0.8, 1.35, 0.35), None, 2), "dyd_coal", True)              # coal heap
for sy in (-1, 1):                                                                                # couplings
    P.box("dyd_iron", (KX, WY + sy * 0.85, WZ - 0.02), (0.08, 0.2, 0.06))
wagon = fin(P, "wagon", T((KX, WY, B0 + 0.14)))
for i, (sx, sy) in enumerate(((-1, -1), (1, -1), (-1, 1), (1, 1))):
    c = V((KX + sx * 0.34, WY + sy * 0.48, B0 + 0.31))
    P = Part()
    P.cyl("dyd_iron", c - X * 0.04, c + X * 0.04, 0.17, seg=14)
    P.cyl("brass", c - X * 0.05, c + X * 0.05, 0.05, seg=8)
    P.box("dyd_rail", c, (0.09, 0.3, 0.03))
    fin(P, "wagon_wheel_%d" % (i + 1), T(c), wagon)

FX0, FY0 = 1.45, 0.45                                                                              # forge against the pen wall
P = Part()
P.box("dyd_stone", (FX0, FY0, B0 + 0.4), (0.7, 0.75, 0.8), None, 0.03)
P.box("dyd_interior", (FX0, FY0 - 0.36, B0 + 0.55), (0.4, 0.04, 0.3))
P.cyl("dyd_stone", (FX0 - 0.1, FY0 + 0.15, B0 + 0.8), (FX0 - 0.1, FY0 + 0.15, B0 + 2.75), 0.18, 0.14, seg=8, flat=True)
P.cyl("dyd_ivory", (FX0 - 0.1, FY0 + 0.15, B0 + 2.7), (FX0 - 0.1, FY0 + 0.15, B0 + 2.85), 0.2, seg=8, flat=True)
P.cyl("dyd_iron", (FX0 + 0.3, FY0 - 0.2, B0 + 0.4), (FX0 + 0.5, FY0 - 0.3, B0 + 0.4), 0.06, seg=6)    # bellows nozzle
P.add(mk_prism([(0, -0.16), (0.3, -0.1), (0.3, 0.1), (0, 0.16)], (FX0 + 0.5, FY0 - 0.3, B0 + 0.4), X, Y, -0.05, 0.05),
      "dyd_leather", True)
forge = fin(P, "forge", Matrix.Identity(4))
P = Part()
c = V((FX0, FY0 - 0.32, B0 + 0.58))
P.add(mk_ico(c, 0.15, (1.3, 0.6, 0.8), None, 2), "dyd_fire")
fin(P, "forge_fire", T(c), forge)

AX, AY = 1.4, -0.45                                                                                # anvil, smith and sparks
P = Part()
P.cyl("dyd_timber", (AX, AY, B0), (AX, AY, B0 + 0.45), 0.17, 0.15, seg=10)
P.box("dyd_iron", (AX, AY, B0 + 0.55), (0.2, 0.45, 0.16), None, 0.01)
P.add(mk_prism([(0, -0.08), (0.2, 0), (0, 0.08)], (AX, AY - 0.22, B0 + 0.55), -Y, Z, -0.07, 0.07), "dyd_iron", True)
P.box("dyd_fire", (AX, AY - 0.05, B0 + 0.64), (0.05, 0.22, 0.03))                                  # hot bar
anvil = fin(P, "anvil", Matrix.Identity(4))
P = Part()
for i in range(8):
    a = random.uniform(-pi, pi)
    d = V((cos(a) * 0.7, sin(a) * 0.7, random.uniform(0.3, 1.0))).normalized()
    P.box("dyd_spark", V((AX, AY - 0.05, B0 + 0.66)) + d * random.uniform(0.08, 0.26), (0.03, 0.03, 0.03))
fin(P, "sparks", T((AX, AY - 0.05, B0 + 0.66)), anvil)


def figure(name, sx, sy, face, apron):
    """A worker standing at (sx, sy), facing `face` (radians about Z; 0 faces +Y). Returns the object, its
    rotation and a function from the figure's own frame to world space."""
    R = rot_z(face)

    def w(p):
        return V((sx, sy, 0)) + (R @ V(p).to_4d()).to_3d()
    P = Part()
    for s in (-1, 1):
        P.cyl("dyd_cloth", w((s * 0.1, 0, B0)), w((s * 0.11, 0, 0.9)), 0.07, 0.085, seg=8)
    P.add(mk_lathe([(0.0, 0.85), (0.19, 0.88), (0.21, 1.1), (0.23, 1.33), (0.16, 1.4), (0.0, 1.41)], w((0, 0, 0)), Z, 12), "dyd_cloth")
    P.box(apron, w((0, 0.19, 1.04)), (0.36, 0.04, 0.5), R, 0.01)
    P.cyl("dyd_skin", w((0, 0, 1.4)), w((0, 0, 1.47)), 0.055, seg=8)
    P.add(mk_ico(w((0, 0.01, 1.57)), 0.11, (1, 1, 1.15), None, 2), "dyd_skin", False)
    P.add(mk_ico(w((0, -0.01, 1.64)), 0.12, (1, 1.05, 0.55), None, 2), "dyd_leather", False)
    P.add(mk_ico(w((-0.2, 0, 1.33)), 0.075), "dyd_cloth", False)
    P.cyl("dyd_skin", w((-0.21, 0, 1.3)), w((-0.24, 0.12, 0.95)), 0.045, 0.04, seg=8)
    ob = fin(P, name, T((sx, sy, 0)) @ R)
    return ob, R, w


smith, R, w = figure("smith", AX + 0.05, AY - 0.62, 0.0, "dyd_leather")                          # facing the anvil
SH, HAND = w((0.2, 0, 1.33)), w((0.2, 0.42, 1.02))
P = Part()                                                                                        # hammer arm, modelled at the blow
P.add(mk_ico(SH, 0.075), "dyd_cloth", False)
P.cyl("dyd_skin", SH, HAND, 0.05, 0.04, seg=8)
P.add(mk_ico(HAND, 0.045), "dyd_skin", False)
P.cyl("dyd_timber", HAND, HAND + V((-0.2, 0.08, -0.02)), 0.018, seg=6)
P.box("dyd_iron", HAND + V((-0.22, 0.09, -0.06)), (0.07, 0.07, 0.14), None, 0.005)
fin(P, "smith_arm", T(SH) @ R, smith)

keeper, R, w = figure("keeper", -1.45, -1.75, radians(-25), "team_color")                         # at the mouth
SH, HAND = w((0.2, 0, 1.33)), w((0.26, 0.3, 1.05))
P = Part()                                                                                        # pitchfork arm, resting
P.add(mk_ico(SH, 0.075), "dyd_cloth", False)
P.cyl("dyd_skin", SH, HAND, 0.05, 0.04, seg=8)
P.add(mk_ico(HAND, 0.045), "dyd_skin", False)
F0, F1 = w((0.27, 0.32, 0.25)), w((0.25, 0.28, 1.9))
P.cyl("dyd_timber_light", F0, F1, 0.02, seg=6)
for k in (-1, 0, 1):
    P.cyl("dyd_iron", w((0.25 + k * 0.05, 0.28, 1.9)), w((0.25 + k * 0.05, 0.28, 2.18)), 0.008, seg=4)
P.box("dyd_iron", F1 + V((0, 0, 0.01)), (0.13, 0.02, 0.02), R)
P.add(mk_ico(F1 + V((0, 0, 0.22)), 0.12, (1.2, 0.8, 0.6), None, 1), "dyd_straw", False)             # a forkful
fin(P, "keeper_arm", T(SH) @ R, keeper)

BRX, BRY = 0.55, -1.6                                                                              # brazier at the mouth
P = Part()
for k in range(3):
    a = 2 * pi * k / 3
    P.cyl("dyd_iron", (BRX + cos(a) * 0.25, BRY + sin(a) * 0.25, B0), (BRX, BRY, B0 + 0.75), 0.025, seg=5)
P.add(mk_lathe([(0.05, 0.7), (0.26, 0.78), (0.3, 0.95), (0.26, 0.96), (0.0, 0.84)], (BRX, BRY, B0), Z, 12), "dyd_iron")
P.add(mk_ico((BRX, BRY, B0 + 0.93), 0.2, (1, 1, 0.4), None, 1), "dyd_coal", True)
brazier = fin(P, "brazier", Matrix.Identity(4))
P = Part()
c = V((BRX, BRY, B0 + 1.05))
P.add(mk_ico(c, 0.2, (1, 1, 1.6), None, 2), "dyd_fire")
P.add(mk_ico(c + V((0.06, -0.04, 0.14)), 0.1, (1, 1, 1.8), None, 1), "dyd_spark")
fin(P, "brazier_fire", T(c - V((0, 0, 0.12))), brazier)

P = Part()                                                                                         # banner, front left corner
x, y = -2.72, -2.72
P.cyl("dyd_timber_dark", (x, y, B0), (x, y, 2.9), 0.045, 0.035, seg=8)
P.add(mk_ico((x, y, 2.94), 0.07), "brass", True)
P.box("brass", (x, y, 2.75), (0.6, 0.06, 0.035))
fin(P, "banner_pole", Matrix.Identity(4))
P = Part()
P.add(mk_prism([(-0.27, 0), (0.27, 0), (0.27, -0.9), (0, -1.12), (-0.27, -0.9)], (x, y, 2.73), X, Z, -0.012, 0.012), "team_color", True)
star(P, V((x, y - 0.015, 2.33)), X, Z, 0.13, -0.02, 0.02)
fin(P, "banner", T((x, y, 2.73)))

for k in range(4):                                                                                 # forge smoke
    P = Part()
    c = V((FX0 - 0.1, FY0 + 0.15, B0 + 3.0))
    P.add(mk_ico(c, 0.2, (1, 1, 0.85), None, 2), "dyd_smoke")
    fin(P, "smoke_%d" % (k + 1), T(c))

# ================================================================= death effects (keyed by animate_dragon_yard.py)
D = bpy.data.collections.new("dragon_yard_death_fx")
bpy.context.scene.collection.children.link(D)
P = Part()
P.add(mk_ico((PXC, 1.0, 1.4), 1.1, (1, 1, 0.8), None, 2), "dyd_spark")
finish(D, P, "Flash_DragonYard", T((PXC, 1.0, 1.4)), None)
for i in range(7):
    c = (random.uniform(-2.5, 2.5), random.uniform(-2.0, 2.5), 0.8)
    P = Part()
    P.add(mk_ico(c, 0.5, (1, 1, 1.3), None, 2), "dyd_fire")
    finish(D, P, "fx_fire_%d" % i, T(c), None)
for i in range(10):
    c = (random.uniform(-2.4, 2.4), random.uniform(-2.0, 2.5), 1.6)
    P = Part()
    P.add(mk_ico(c, 0.6, (1, 1, 0.9), None, 2), "dyd_smoke")
    finish(D, P, "fx_smoke_%d" % i, T(c), None)
for i in range(16):
    c = (random.uniform(-1.5, 1.5), random.uniform(-0.5, 2.0), 1.8)
    P = Part()
    P.box(random.choice(["dyd_timber", "dyd_ivory", "team_color", "dyd_stone", "dyd_straw"]), c,
          (random.uniform(0.2, 0.5), random.uniform(0.08, 0.25), random.uniform(0.05, 0.14)), None, 0.01)
    finish(D, P, "fx_debris_%d" % i, T(c), None)

bpy.context.view_layer.layer_collection.children["dragon_yard_death_fx"].exclude = True
bpy.context.view_layer.update()
tris = 0
for o in C.all_objects:
    if o.type == 'MESH':
        o.data.calc_loop_triangles()
        tris += len(o.data.loop_triangles)
print("TRIS", tris)
bpy.context.preferences.filepaths.save_version = 0
bpy.ops.wm.save_as_mainfile(filepath=OUT)
print("SAVED", OUT, len(C.all_objects), "objects")
