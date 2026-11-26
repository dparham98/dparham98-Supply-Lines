"""Builds Wainwright.blend from nothing: the Arthurian Knights' cartwright and track works (docs/WAINWRIGHT_MODEL.md).

  blender --background --python build_wainwright.py

Everything is rebuilt each run. The open yard faces -Y, Z up, base on Z = 0, inside the 4 x 4 m footprint.
The palette is the Keep's, Chapterhouse's and House's: ivory stone, timber, brass and a team-blue roof. The
helpers come from ../../Foundry/build/building_kit.py, and animate_wainwright.py adds the clips.

Layout: a timber workshop with a team-blue roof along the back. At the front left is the wheel bench, with a
wheel being made and the wainwright at it with an adze. At the front right are stacks of rails and sleepers,
with a sheerlegs crane over them holding a rail. A banner stands at the front corner, and a chimney rises from
the workshop.
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

OUT = os.path.normpath(os.path.join(HERE, "..", "Wainwright.blend"))
random.seed(53)
bpy.ops.wm.read_factory_settings(use_empty=True)

material("wwr_stone", (0.62, 0.60, 0.55), 0.0, 0.85)
material("wwr_ivory", (0.83, 0.82, 0.73), 0.35, 0.43)
material("wwr_timber", (0.18, 0.10, 0.05), 0.0, 0.8)
material("wwr_timber_light", (0.42, 0.28, 0.15), 0.0, 0.75)
material("wwr_timber_dark", (0.08, 0.045, 0.022), 0.0, 0.85)
material("wwr_iron", (0.22, 0.24, 0.26), 0.7, 0.45)
material("wwr_rail", (0.46, 0.49, 0.52), 0.8, 0.35)
material("wwr_rope", (0.45, 0.36, 0.22), 0.0, 0.9)
material("wwr_cloth", (0.34, 0.28, 0.20), 0.0, 0.85)
material("wwr_leather", (0.13, 0.07, 0.035), 0.0, 0.7)
material("wwr_skin", (0.55, 0.36, 0.25), 0.0, 0.7)
material("wwr_interior", (0.022, 0.025, 0.030), 0.1, 0.85)
material("wwr_amber_glass", (1.0, 0.69, 0.29), 0.14, 0.2, (1.0, 0.65, 0.22), 2.2)
material("wwr_chip", (0.62, 0.45, 0.26), 0.0, 0.8)
material("wwr_smoke", (0.17, 0.16, 0.15), 0.0, 1.0)
material("wwr_fire", (0.9, 0.4, 0.06), 0.0, 0.5, (1.0, 0.42, 0.06), 5.0)
material("wwr_spark", (1.0, 0.85, 0.5), 0.0, 0.4, (1.0, 0.8, 0.4), 8.0)
material("brass", (0.71, 0.44, 0.12), 0.65, 0.37)
material("team_color", (0.025, 0.075, 0.38), 0.08, 0.64)
material("team_color_shadow", (0.013, 0.033, 0.18), 0.04, 0.70)

C = bpy.data.collections.new("wainwright")
bpy.context.scene.collection.children.link(C)
B0 = 0.14


def fin(P, name, world, parent=None):
    return finish(C, P, name, world, parent)


# ================================================================= plinth: stone kerb, plank yard
P = Part()
P.box("wwr_stone", (0, 0, B0 / 2), (3.96, 3.96, B0), None, 0.02)
for i in range(13):
    x = -1.8 + i * 0.3
    P.box("wwr_timber_light" if i % 3 else "wwr_timber", (x, -0.55, B0 + 0.012), (0.28, 2.6, 0.025), None, 0.005)
plinth = fin(P, "plinth", Matrix.Identity(4))

# ================================================================= workshop along the back, with roof and chimney
WY0, WY1, WH = 0.75, 1.9, 1.85
P = Part()
P.box("wwr_stone", (0, (WY0 + WY1) / 2 + 0.45, B0 + 0.3), (3.8, 0.3, 0.6), None, 0.02)            # back wall footing
P.box("wwr_ivory", (0, WY1 - 0.05, B0 + 0.95), (3.7, 0.12, 0.75), None, 0.01)                      # back wall
for sx in (-1, 1):
    P.box("wwr_ivory", (sx * 1.85, (WY0 + WY1) / 2, B0 + 0.95), (0.12, WY1 - WY0, 1.6), None, 0.01)  # end walls
for x in (-1.85, -0.62, 0.62, 1.85):
    P.box("wwr_timber", (x, WY0, (B0 + WH) / 2 + 0.05), (0.14, 0.14, WH - B0), None, 0.01)          # front posts
    P.box("wwr_timber", (x, WY1, (B0 + WH) / 2 + 0.05), (0.12, 0.12, WH - B0), None, 0.01)
P.box("wwr_timber", (0, WY0, WH + 0.05), (3.84, 0.16, 0.14), None, 0.01)                             # lintel
for x in (-1.85, 1.85):
    P.beam("wwr_timber_dark", (x, WY1 - 0.05, B0 + 0.3), (x, WY0 + 0.05, WH - 0.1), 0.08, 0.06)    # cross braces
P.box("wwr_interior", (0, (WY0 + WY1) / 2 + 0.1, B0 + 0.85), (3.4, 0.85, 1.4))                     # dark inside
P.box("wwr_amber_glass", (-1.92, (WY0 + WY1) / 2, B0 + 1.15), (0.02, 0.35, 0.4))                  # end window
for k in range(3):                                                                                   # wheels hung inside
    x = -1.2 + k * 1.2
    ring = [V((x + cos(2 * pi * j / 20) * 0.34, WY1 - 0.14, B0 + 1.15 + sin(2 * pi * j / 20) * 0.34)) for j in range(21)]
    P.tube("wwr_timber", ring, 0.035, 6)
P.cyl("wwr_stone", (1.3, WY1 - 0.1, B0), (1.3, WY1 - 0.1, 3.0), 0.22, 0.2, seg=8, flat=True)       # chimney
P.cyl("wwr_ivory", (1.3, WY1 - 0.1, 2.95), (1.3, WY1 - 0.1, 3.1), 0.26, seg=8, flat=True)
P.cyl("wwr_interior", (1.3, WY1 - 0.1, 3.1), (1.3, WY1 - 0.1, 3.11), 0.16, seg=8, flat=True)
shop = fin(P, "workshop", Matrix.Identity(4))
P = Part()                                                                                           # gabled roof, ridge along X
RZ0, RZ1 = WH + 0.12, WH + 0.85
RYM = (WY0 + WY1) / 2
for sy, y0 in ((-1, WY0 - 0.3), (1, WY1 + 0.3)):
    P.add(mk_loft([[V((-2.0, y0, RZ0)), V((2.0, y0, RZ0)), V((2.0, y0, RZ0 + 0.08)), V((-2.0, y0, RZ0 + 0.08))],
                   [V((-2.0, RYM, RZ1)), V((2.0, RYM, RZ1)), V((2.0, RYM, RZ1 + 0.08)), V((-2.0, RYM, RZ1 + 0.08))]]),
          "team_color", True)
    for k in range(4):
        t = (k + 0.5) / 4
        y = y0 + (RYM - y0) * t
        z = RZ0 + (RZ1 - RZ0) * t + 0.085
        P.box("team_color_shadow", (0, y, z), (4.0, 0.03, 0.012))
P.box("brass", (0, RYM, RZ1 + 0.1), (4.05, 0.1, 0.06), None, 0.01)
for sx in (-1, 1):
    P.add(mk_prism([(WY0 - 0.3 - RYM, 0), (WY1 + 0.3 - RYM, 0), (0, RZ1 - RZ0)], (sx * 1.86, RYM, RZ0), Y, Z, -0.04, 0.04),
          "wwr_ivory", True)
roof = fin(P, "roof", T((0, RYM, RZ0)))

# ================================================================= the wheel bench and the wheel on it (front left)
BX, BY = -1.05, -0.35
P = Part()
P.box("wwr_timber_light", (BX, BY, B0 + 0.5), (1.3, 0.5, 0.08), None, 0.01)
for sx in (-1, 1):
    for sy in (-1, 1):
        P.box("wwr_timber", (BX + sx * 0.55, BY + sy * 0.18, B0 + 0.25), (0.08, 0.08, 0.5))
P.cyl("wwr_iron", (BX, BY, B0 + 0.54), (BX, BY, B0 + 0.66), 0.05, seg=8)                           # spindle
for k in range(6):                                                                                    # spokes waiting
    P.cyl("wwr_timber_light", (BX + 0.4, BY - 0.15 + k * 0.06, B0 + 0.56), (BX + 0.62, BY - 0.15 + k * 0.06, B0 + 0.56), 0.015, seg=5)
for k in range(10):
    P.add(mk_ico((BX + random.uniform(-0.6, 0.6), BY + random.uniform(-0.6, -0.3), B0 + 0.02), 0.03,
                 (1.6, 0.8, 0.3)), "wwr_chip", True)                                                  # chips
bench = fin(P, "wheel_bench", Matrix.Identity(4))
WC = V((BX, BY, B0 + 0.62))
P = Part()                                                                                            # wheel, flat on the bench, turns about Z
P.add(mk_annulus(WC, 0.36, 0.42, 0.06, seg=24), "wwr_timber", True)
P.add(mk_annulus(WC + Z * 0.015, 0.41, 0.43, 0.04, seg=24), "wwr_iron", True)
P.cyl("wwr_timber_dark", WC - Z * 0.04, WC + Z * 0.06, 0.08, seg=10)
for k in range(10):
    a = 2 * pi * k / 10
    P.cyl("wwr_timber_light", WC + V((cos(a), sin(a), 0)) * 0.08, WC + V((cos(a), sin(a), 0)) * 0.37, 0.018, seg=5)
fin(P, "wheel", T(WC), bench)

SX, SY = BX + 0.05, BY - 0.62                                                                         # the wainwright, facing +Y
P = Part()
for sx in (-1, 1):
    P.cyl("wwr_cloth", (SX + sx * 0.1, SY, B0), (SX + sx * 0.11, SY, 0.9), 0.07, 0.085, seg=8)
P.add(mk_lathe([(0.0, 0.85), (0.19, 0.88), (0.21, 1.1), (0.23, 1.33), (0.16, 1.4), (0.0, 1.41)], (SX, SY, 0), Z, 12), "wwr_cloth")
P.box("wwr_leather", (SX, SY + 0.19, 1.04), (0.36, 0.04, 0.5), None, 0.01)                           # apron
P.cyl("wwr_skin", (SX, SY, 1.4), (SX, SY, 1.47), 0.055, seg=8)
P.add(mk_ico((SX, SY + 0.01, 1.57), 0.11, (1, 1, 1.15), None, 2), "wwr_skin", False)
P.add(mk_ico((SX, SY - 0.01, 1.64), 0.12, (1, 1.05, 0.55), None, 2), "wwr_cloth", False)             # cap
P.add(mk_ico((SX - 0.2, SY, 1.33), 0.075), "wwr_cloth", False)
P.cyl("wwr_skin", (SX - 0.21, SY, 1.3), (SX - 0.25, SY + 0.28, 1.0), 0.045, 0.04, seg=8)              # left hand on the rim
smith = fin(P, "wainwright", Matrix.Identity(4))
SH = V((SX + 0.2, SY, 1.33))
HAND = V((SX + 0.22, SY + 0.3, 1.02))
P = Part()                                                                                            # adze arm, modelled at the cut
P.add(mk_ico(SH, 0.075), "wwr_cloth", False)
P.cyl("wwr_skin", SH, HAND, 0.05, 0.04, seg=8)
P.add(mk_ico(HAND, 0.045), "wwr_skin", False)
P.cyl("wwr_timber", HAND - V((0, 0.12, -0.1)), HAND + V((0, 0.2, -0.12)), 0.018, seg=6)
P.box("wwr_iron", HAND + V((0, 0.24, -0.18)), (0.1, 0.03, 0.12), rot_x(radians(30)), 0.005)
fin(P, "wainwright_arm", T(SH), smith)
P = Part()
for i in range(8):
    a = random.uniform(-pi, pi)
    d = V((cos(a) * 0.6, sin(a) * 0.6, random.uniform(0.4, 1.0))).normalized()
    c = WC + V((0.3, -0.2, 0.06))
    P.box("wwr_chip", c + d * random.uniform(0.08, 0.22), (0.05, 0.02, 0.008), None)
fin(P, "chips", T(WC + V((0.3, -0.2, 0.06))), bench)

# ================================================================= rails and sleepers (front right), sheerlegs crane
RX, RY = 1.0, -0.6
P = Part()
for layer in range(3):                                                                                # sleepers, crosswise stacks
    for k in range(4):
        if layer % 2 == 0:
            P.box("wwr_timber", (RX - 0.55 + k * 0.36, RY - 0.75, B0 + 0.06 + layer * 0.12), (0.24, 0.9, 0.12), None, 0.01)
        else:
            P.box("wwr_timber", (RX, RY - 1.15 + k * 0.27, B0 + 0.06 + layer * 0.12), (1.3, 0.2, 0.12), None, 0.01)
for layer in range(2):                                                                                # rails on chocks
    for k in range(4):
        y = RY + 0.1 + k * 0.17 + layer * 0.08
        z = B0 + 0.14 + layer * 0.1
        P.box("wwr_rail", (RX, y, z), (1.7, 0.07, 0.05), None, 0.005)
        P.box("wwr_rail", (RX, y, z + 0.03), (1.7, 0.025, 0.06))
for x in (RX - 0.6, RX + 0.6):
    P.box("wwr_timber_dark", (x, RY + 0.35, B0 + 0.06), (0.12, 0.8, 0.1))
stack = fin(P, "rail_stack", Matrix.Identity(4))
TOP = V((RX + 0.05, RY - 0.25, 2.55))
P = Part()
for foot in ((RX - 0.65, RY - 0.95), (RX + 0.75, RY - 0.95), (RX + 0.05, RY + 0.6)):
    P.cyl("wwr_timber", (foot[0], foot[1], B0), TOP, 0.06, 0.045, seg=8)
P.cyl("wwr_iron", TOP - Z * 0.05, TOP + Z * 0.08, 0.09, seg=8)
P.add(mk_annulus(V((RX + 0.75, RY - 0.95, B0 + 0.45)), 0.08, 0.13, 0.12, seg=12), "wwr_rope", True)   # windlass coil
crane = fin(P, "sheerlegs", Matrix.Identity(4))
P = Part()                                                                                            # rope, hook and the rail it lifts
P.cyl("wwr_rope", TOP, TOP - Z * 1.2, 0.015, seg=5)
P.add(mk_annulus(TOP - Z * 1.25, 0.03, 0.05, 0.02, seg=10), "wwr_iron", True)
for sx in (-1, 1):
    P.cyl("wwr_rope", TOP - Z * 1.25, TOP - Z * 1.6 + X * sx * 0.55, 0.01, seg=4)
P.box("wwr_rail", TOP - Z * 1.62, (1.5, 0.07, 0.05), None, 0.005)
P.box("wwr_rail", TOP - Z * 1.59, (1.5, 0.025, 0.06))
fin(P, "crane_load", T(TOP), crane)

# banner at the front left corner, hinged on its crossbar
P = Part()
x, y = -1.75, -1.75
P.cyl("wwr_timber_dark", (x, y, B0), (x, y, 2.6), 0.04, 0.03, seg=8)
P.add(mk_ico((x, y, 2.64), 0.06), "brass", True)
P.box("brass", (x, y, 2.45), (0.55, 0.06, 0.035))
fin(P, "banner_pole", Matrix.Identity(4))
P = Part()
P.add(mk_prism([(-0.25, 0), (0.25, 0), (0.25, -0.8), (0, -1.0), (-0.25, -0.8)], (x, y, 2.43), X, Z, -0.012, 0.012), "team_color", True)
P.add(mk_prism([(0, 0.0), (0.09, -0.13), (0, -0.26), (-0.09, -0.13)], (x, y, 2.13), X, Z, -0.02, 0.02), "brass", True)
fin(P, "banner", T((x, y, 2.43)))

for k in range(4):                                                                                    # chimney smoke
    P = Part()
    c = V((1.3, WY1 - 0.1, 3.25))
    P.add(mk_ico(c, 0.2, (1, 1, 0.85), None, 2), "wwr_smoke")
    fin(P, "smoke_%d" % (k + 1), T(c))

# ================================================================= death effects (keyed by animate_wainwright.py)
D = bpy.data.collections.new("wainwright_death_fx")
bpy.context.scene.collection.children.link(D)
P = Part()
P.add(mk_ico((0, 0.6, 0.9), 0.8, (1, 1, 0.8), None, 2), "wwr_spark")
finish(D, P, "Flash_Wainwright", T((0, 0.6, 0.9)), None)
for i in range(5):
    c = (random.uniform(-1.5, 1.5), random.uniform(-1.2, 1.5), 0.7)
    P = Part()
    P.add(mk_ico(c, 0.42, (1, 1, 1.3), None, 2), "wwr_fire")
    finish(D, P, "fx_fire_%d" % i, T(c), None)
for i in range(8):
    c = (random.uniform(-1.4, 1.4), random.uniform(-1.2, 1.5), 1.3)
    P = Part()
    P.add(mk_ico(c, 0.5, (1, 1, 0.9), None, 2), "wwr_smoke")
    finish(D, P, "fx_smoke_%d" % i, T(c), None)
for i in range(12):
    c = (0, 0.4, 1.2)
    P = Part()
    P.box(random.choice(["wwr_timber", "wwr_timber_light", "team_color", "wwr_rail"]), c,
          (random.uniform(0.15, 0.4), random.uniform(0.06, 0.2), random.uniform(0.04, 0.1)), None, 0.01)
    finish(D, P, "fx_debris_%d" % i, T(c), None)

bpy.context.view_layer.layer_collection.children["wainwright_death_fx"].exclude = True
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
