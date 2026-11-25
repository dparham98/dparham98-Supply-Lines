"""Builds Forge.blend from nothing: the Arthurian Knights' smithy and armoury (docs/FORGE_MODEL.md).

  blender --background --python build_forge.py

Everything is rebuilt each run. The open front faces -Y, Z up, base on Z = 0, inside the 6 x 6 m footprint.
The palette is the Keep's and Chapterhouse's: ivory stone, silver, heraldic brass and the team-blue roof,
with timber, leather and amber glass. Helpers come from ../../Foundry/build/building_kit.py. Clips are
added by animate_forge.py.

Layout: a stone hearth with its hood and tall chimney at the back left, the bellows beside it, and a
lean-to roof over the back half only, so the work reads from above. In the open yard: the anvil with the
smith at it, a stone quench trough (right), a mail hauberk on its stand (left), a rack of swords and
lances against the back wall (right), and two banners at the front corners.
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

OUT = os.path.normpath(os.path.join(HERE, "..", "Forge.blend"))
random.seed(41)
bpy.ops.wm.read_factory_settings(use_empty=True)

material("frg_stone", (0.62, 0.60, 0.55), 0.0, 0.85)
material("frg_stone_dark", (0.34, 0.32, 0.30), 0.0, 0.9)
material("frg_ivory", (0.83, 0.82, 0.73), 0.35, 0.43)
material("frg_silver", (0.69, 0.72, 0.73), 0.55, 0.40)
material("frg_steel", (0.25, 0.29, 0.32), 0.65, 0.43)
material("brass", (0.71, 0.44, 0.12), 0.65, 0.37)
material("team_color", (0.025, 0.075, 0.38), 0.08, 0.64)
material("team_color_shadow", (0.013, 0.033, 0.18), 0.04, 0.70)
material("frg_timber", (0.16, 0.09, 0.045), 0.0, 0.8)
material("frg_timber_dark", (0.08, 0.045, 0.022), 0.0, 0.85)
material("frg_leather", (0.13, 0.07, 0.035), 0.0, 0.7)
material("frg_cloth", (0.34, 0.28, 0.20), 0.0, 0.85)
material("frg_skin", (0.55, 0.36, 0.25), 0.0, 0.7)
material("frg_coal", (0.02, 0.02, 0.022), 0.0, 0.6)
material("frg_interior", (0.022, 0.025, 0.030), 0.1, 0.85)
material("frg_fire", (0.9, 0.4, 0.06), 0.0, 0.5, (1.0, 0.42, 0.06), 5.0)
material("frg_ember", (0.6, 0.12, 0.02), 0.0, 0.5, (1.0, 0.25, 0.04), 3.0)
material("frg_hot", (0.9, 0.55, 0.15), 0.0, 0.4, (1.0, 0.6, 0.2), 5.0)
material("frg_spark", (1.0, 0.85, 0.5), 0.0, 0.4, (1.0, 0.8, 0.4), 8.0)
material("frg_amber_glass", (1.0, 0.69, 0.29), 0.14, 0.2, (1.0, 0.65, 0.22), 2.2)
material("frg_water", (0.04, 0.08, 0.10), 0.3, 0.08)
material("frg_smoke", (0.17, 0.16, 0.15), 0.0, 1.0)
material("frg_steam", (0.62, 0.62, 0.62), 0.0, 1.0)

C = bpy.data.collections.new("forge")
bpy.context.scene.collection.children.link(C)
B0 = 0.18


def fin(P, name, world, parent=None):
    return finish(C, P, name, world, parent)


# ================================================================= plinth: stone flags and a cobbled yard
P = Part()
P.box("frg_stone_dark", (0, 0, B0 / 2), (5.96, 5.96, B0), None, 0.03)
for i in range(6):
    for j in range(6):
        x, y = -2.5 + i, -2.5 + j
        P.box("frg_stone" if (i + j) % 3 else "frg_ivory", (x + random.uniform(-0.03, 0.03), y, B0 + 0.01),
              (0.94, 0.94, 0.03), rot_z(radians(random.uniform(-2, 2))), 0.01)
plinth = fin(P, "plinth", Matrix.Identity(4))

# ================================================================= hearth, hood and chimney (back left)
HX, HY = -1.55, 2.05
P = Part()
P.box("frg_stone", (HX, HY + 0.05, B0 + 0.55), (2.1, 1.5, 1.1), None, 0.03)              # hearth block
P.box("frg_interior", (HX, HY - 0.55, B0 + 0.72), (1.3, 0.5, 0.62))                      # fire mouth
P.box("frg_ivory", (HX, HY - 0.72, B0 + 1.08), (1.6, 0.14, 0.12), None, 0.02)            # lintel
for sx in (-1, 1):
    P.box("frg_ivory", (HX + sx * 0.72, HY - 0.72, B0 + 0.55), (0.16, 0.14, 1.1), None, 0.02)
P.add(mk_loft([[V((HX - 1.05, HY - 0.7, B0 + 1.1)), V((HX + 1.05, HY - 0.7, B0 + 1.1)), V((HX + 1.05, HY + 0.8, B0 + 1.1)),
                V((HX - 1.05, HY + 0.8, B0 + 1.1))],
               [V((HX - 0.45, HY - 0.05, 2.6)), V((HX + 0.45, HY - 0.05, 2.6)), V((HX + 0.45, HY + 0.65, 2.6)),
                V((HX - 0.45, HY + 0.65, 2.6))]]), "frg_stone", True)                    # hood
P.box("frg_stone", (HX, HY + 0.3, 3.85), (0.9, 0.7, 2.5), None, 0.02)                    # chimney
for z in (2.7, 3.9, 5.0):
    P.box("frg_ivory", (HX, HY + 0.3, z), (1.0, 0.8, 0.1), None, 0.02)
P.box("brass", (HX, HY + 0.3, 5.12), (0.8, 0.6, 0.06))
P.box("frg_interior", (HX, HY + 0.3, 5.14), (0.62, 0.42, 0.04))
for k in range(5):                                                                       # coal heap beside it
    P.add(mk_ico((HX + 1.25 + random.uniform(-0.15, 0.15), HY + 0.6 + random.uniform(-0.2, 0.2), B0 + 0.1),
                 random.uniform(0.15, 0.25), (1, 1, 0.6)), "frg_coal", True)
hearth = fin(P, "hearth", Matrix.Identity(4))
P = Part()                                                                               # the fire in the mouth
P.box("frg_ember", (HX, HY - 0.5, B0 + 0.45), (1.2, 0.45, 0.06))
for i in range(7):
    P.add(mk_ico((HX + random.uniform(-0.45, 0.45), HY - 0.5 + random.uniform(-0.12, 0.12), B0 + 0.55),
                 random.uniform(0.1, 0.18), (1, 0.8, 1.6)), "frg_fire", True)
fin(P, "hearth_fire", T((HX, HY - 0.5, B0 + 0.45)), hearth)

# bellows: a leather wedge on a timber cradle; its top board hinges at the nozzle end (toward the hearth)
BX, BY = -0.05, 1.95
P = Part()
P.box("frg_timber", (BX, BY, B0 + 0.3), (1.1, 0.6, 0.08), None, 0.01)
for sx in (-1, 1):
    for sy in (-1, 1):
        P.box("frg_timber_dark", (BX + sx * 0.45, BY + sy * 0.22, B0 + 0.13), (0.08, 0.08, 0.3))
P.add(mk_prism([(-0.5, 0.0), (0.5, 0.0), (0.5, 0.26), (-0.42, 0.06)], (BX, BY, B0 + 0.34), X, Z, -0.26, 0.26),
      "frg_leather", True)
P.cyl("brass", (BX - 0.5, BY, B0 + 0.38), (HX + 1.08, BY - 0.2, B0 + 0.6), 0.05, 0.03, seg=8)
bellows = fin(P, "bellows", Matrix.Identity(4))
P = Part()
P.box("frg_timber", (BX + 0.05, BY, B0 + 0.62), (0.98, 0.56, 0.05), None, 0.01)
P.cyl("frg_timber_dark", (BX + 0.5, BY, B0 + 0.65), (BX + 0.75, BY, B0 + 1.25), 0.03, seg=6)
P.box("brass", (BX + 0.2, BY, B0 + 0.65), (0.18, 0.2, 0.02))
fin(P, "bellows_board", T((BX - 0.45, BY, B0 + 0.62)), bellows)

# ================================================================= timber frame and lean-to roof over the back half
P = Part()
for x in (-2.75, 0.0, 2.75):
    P.box("frg_timber", (x, 0.55, (B0 + 2.55) / 2), (0.2, 0.2, 2.55 - B0), None, 0.015)
    P.box("frg_stone", (x, 0.55, B0 + 0.12), (0.32, 0.32, 0.24), None, 0.02)
    P.box("frg_timber", (x, 2.82, (B0 + 3.35) / 2), (0.2, 0.2, 3.35 - B0), None, 0.015)
P.box("frg_timber", (0, 0.55, 2.6), (5.75, 0.22, 0.2), None, 0.015)                     # front beam
P.box("frg_timber", (0, 2.82, 3.4), (5.75, 0.22, 0.2), None, 0.015)
for x in (-2.75, 0.0, 2.75):
    P.beam("frg_timber_dark", (x, 0.55, 2.4), (x, 1.2, 1.85), 0.1, 0.1)                 # braces
# low back wall (right half) with an amber-glass window
P.box("frg_stone", (1.4, 2.82, B0 + 0.7), (2.7, 0.26, 1.4), None, 0.02)
P.box("frg_ivory", (1.4, 2.82, B0 + 1.42), (2.8, 0.32, 0.08), None, 0.01)
P.box("frg_amber_glass", (2.3, 2.68, B0 + 0.95), (0.4, 0.02, 0.5))
P.box("frg_timber_dark", (2.3, 2.67, B0 + 0.95), (0.46, 0.02, 0.04))
frame = fin(P, "frame", Matrix.Identity(4))
P = Part()
P.add(mk_loft([[V((-3.0, 0.35, 2.68)), V((3.0, 0.35, 2.68)), V((3.0, 0.35, 2.78)), V((-3.0, 0.35, 2.78))],
               [V((-3.0, 2.98, 3.48)), V((3.0, 2.98, 3.48)), V((3.0, 2.98, 3.58)), V((-3.0, 2.98, 3.58))]]),
      "team_color", True)
for k in range(9):                                                                       # slate courses
    y = 0.5 + k * 0.28
    z = 2.78 + (y - 0.35) * 0.8 / 2.63
    P.box("team_color_shadow", (0, y, z + 0.012), (6.0, 0.03, 0.012), rot_x(radians(17)))
P.box("brass", (0, 0.33, 2.73), (6.04, 0.05, 0.14), None, 0.01)
for sx in (-1, 1):
    P.box("brass", (sx * 3.0, 1.66, 3.15), (0.05, 2.75, 0.12), rot_x(radians(17)), 0.01)
roof = fin(P, "roof", T((0, 1.66, 2.68)))

# weapon rack against the back wall: swords and lances
P = Part()
for y0, z0 in ((2.6, B0 + 0.45), (2.6, B0 + 1.15)):
    P.box("frg_timber", (1.4, y0, z0), (2.5, 0.08, 0.08), None, 0.01)
for k in range(6):                                                                       # swords, points down
    x = 0.4 + k * 0.32
    P.box("frg_silver", (x, 2.55, B0 + 0.75), (0.05, 0.015, 0.95), None, 0.004)
    P.box("brass", (x, 2.55, B0 + 1.25), (0.2, 0.03, 0.03))
    P.cyl("frg_leather", (x, 2.55, B0 + 1.26), (x, 2.55, B0 + 1.42), 0.018, seg=6)
    P.add(mk_ico((x, 2.55, B0 + 1.45), 0.03), "brass", True)
for k in range(3):                                                                       # lances with pennons
    x = 2.35 + k * 0.17
    P.cyl("frg_timber", (x, 2.55, B0 + 0.05), (x, 2.55, B0 + 3.0), 0.03, 0.018, seg=8)
    P.cyl("frg_silver", (x, 2.55, B0 + 3.0), (x, 2.55, B0 + 3.3), 0.03, 0.002, seg=8)
    P.add(mk_prism([(0, 0), (0.35, 0.08), (0, 0.18)], (x, 2.55, B0 + 2.75), -Y, Z, -0.005, 0.005), "team_color", True)
rack = fin(P, "weapon_rack", Matrix.Identity(4))

# ================================================================= the anvil, the work on it and the smith
AX, AY = -0.02, -0.6
P = Part()
P.cyl("frg_timber_dark", (AX, AY, B0), (AX, AY, B0 + 0.48), 0.28, 0.26, seg=12)          # stump
for k in range(3):
    P.cyl("frg_steel", (AX, AY, B0 + 0.08 + k * 0.17), (AX, AY, B0 + 0.11 + k * 0.17), 0.285, seg=12)
P.box("frg_steel", (AX, AY, B0 + 0.55), (0.32, 0.2, 0.14), None, 0.02)
P.box("frg_steel", (AX, AY, B0 + 0.66), (0.18, 0.14, 0.1))
P.box("frg_silver", (AX + 0.02, AY, B0 + 0.75), (0.56, 0.2, 0.1), None, 0.015)
P.cyl("frg_silver", (AX - 0.26, AY, B0 + 0.75), (AX - 0.48, AY, B0 + 0.76), 0.06, 0.01, seg=8)  # horn
anvil = fin(P, "anvil", Matrix.Identity(4))
P = Part()
P.box("frg_hot", (AX + 0.02, AY, B0 + 0.82), (0.42, 0.05, 0.035), None, 0.008)
fin(P, "anvil_billet", T((AX, AY, B0 + 0.82)), anvil)
P = Part()
for i in range(14):
    a = random.uniform(-pi, pi)
    d = V((cos(a), sin(a) * 0.8, random.uniform(0.15, 0.6))).normalized()
    c = V((AX + random.uniform(-0.1, 0.1), AY, B0 + 0.86))
    P.cyl("frg_spark", c + d * 0.05, c + d * random.uniform(0.18, 0.34), 0.012, 0.004, seg=4)
fin(P, "anvil_sparks", T((AX, AY, B0 + 0.86)), anvil)

SX, SY = AX, 0.05                                                                        # the smith, facing -Y
SH = V((SX - 0.22, SY - 0.02, 1.47))                                                     # right shoulder (-X)
P = Part()
for sx in (-1, 1):
    P.cyl("frg_cloth", (SX + sx * 0.11, SY, B0), (SX + sx * 0.12, SY, 0.98), 0.075, 0.09, seg=8)
    P.box("frg_leather", (SX + sx * 0.11, SY - 0.04, B0 + 0.05), (0.12, 0.24, 0.1), None, 0.02)
P.add(mk_lathe([(0.0, 0.92), (0.2, 0.95), (0.23, 1.2), (0.25, 1.45), (0.17, 1.52), (0.0, 1.53)], (SX, SY, 0), Z, 12),
      "frg_cloth")
P.box("frg_leather", (SX, SY - 0.2, 1.12), (0.4, 0.04, 0.6), None, 0.01)                 # apron
P.cyl("frg_skin", (SX, SY, 1.52), (SX, SY, 1.6), 0.06, seg=8)
P.add(mk_ico((SX, SY - 0.01, 1.71), 0.12, (1, 1, 1.15), None, 2), "frg_skin", False)
P.add(mk_ico((SX, SY + 0.02, 1.77), 0.125, (1, 1.05, 0.7), None, 2), "frg_timber_dark", False)  # hair
P.add(mk_ico((SX, SY - 0.09, 1.64), 0.08, (1, 0.6, 0.8), None, 1), "frg_timber_dark", True)   # beard
P.add(mk_ico((SX + 0.22, SY - 0.02, 1.45), 0.08), "frg_cloth", False)                    # left shoulder
P.cyl("frg_skin", (SX + 0.24, SY - 0.02, 1.42), (SX + 0.2, SY - 0.25, 1.08), 0.05, 0.045, seg=8)  # left arm, steadying
P.cyl("frg_steel", (SX + 0.2, SY - 0.25, 1.08), (AX + 0.15, AY + 0.02, B0 + 0.84), 0.018, seg=6)  # tongs
smith = fin(P, "smith", Matrix.Identity(4))
HAND = V((SX - 0.22, -0.38, 1.02))
HEAD = V((SX - 0.02, AY - 0.02, B0 + 0.93))
P = Part()                                                                               # hammer arm, modelled on the blow
P.add(mk_ico(SH, 0.085), "frg_cloth", False)
P.cyl("frg_skin", SH, HAND, 0.055, 0.045, seg=8)
P.add(mk_ico(HAND, 0.05), "frg_skin", False)
P.cyl("frg_timber", HAND + (HAND - HEAD).normalized() * 0.08, HEAD, 0.02, seg=6)
hd = (HEAD - HAND).normalized()
P.box("frg_steel", HEAD + Z * 0.02, (0.08, 0.16, 0.08), basis(X, Z.cross(X), Z), 0.01)
fin(P, "smith_arm", T(SH), smith)

# ================================================================= quench trough (front right) and hauberk (front left)
QX, QY = 1.85, -1.25
P = Part()
P.box("frg_stone", (QX, QY, B0 + 0.3), (1.2, 0.6, 0.6), None, 0.03)
P.box("frg_ivory", (QX, QY, B0 + 0.62), (1.28, 0.68, 0.05), None, 0.01)
P.box("frg_timber_dark", (QX + 0.5, QY - 0.2, B0 + 0.9), (0.05, 0.05, 0.5))              # a bucket and tongs
trough = fin(P, "trough", Matrix.Identity(4))
P = Part()
P.box("frg_water", (QX, QY, B0 + 0.58), (1.08, 0.48, 0.04))
fin(P, "trough_water", T((QX, QY, B0 + 0.58)), trough)
P = Part()
for i in range(4):
    P.add(mk_ico((QX + random.uniform(-0.3, 0.3), QY + random.uniform(-0.1, 0.1), B0 + 0.75), 0.16, (1, 1, 0.8), None, 2), "frg_steam")
fin(P, "quench_steam", T((QX, QY, B0 + 0.75)), trough)

MX, MY = -1.9, -1.35
P = Part()
P.cyl("frg_timber_dark", (MX, MY, B0), (MX, MY, B0 + 1.65), 0.04, seg=8)
P.box("frg_timber", (MX, MY, B0 + 1.42), (0.62, 0.06, 0.06))
for a in (0, 2.1, 4.2):
    P.cyl("frg_timber_dark", (MX, MY, B0 + 0.02), (MX + cos(a) * 0.3, MY + sin(a) * 0.3, B0 + 0.02), 0.03, seg=6)
P.add(mk_loft([[V((MX + x, MY + y, z)) for x, y in ((-0.26, -0.12), (0.26, -0.12), (0.26, 0.12), (-0.26, 0.12))]
               for z in (B0 + 0.55, B0 + 0.95)] + [[V((MX + x * 0.95, MY + y * 0.95, B0 + 1.4)) for x, y in
                                                     ((-0.26, -0.12), (0.26, -0.12), (0.26, 0.12), (-0.26, 0.12))]]),
      "frg_silver", True)
for sx in (-1, 1):
    P.cyl("frg_silver", (MX + sx * 0.25, MY, B0 + 1.36), (MX + sx * 0.42, MY - 0.03, B0 + 1.0), 0.08, 0.06, seg=8)
P.add(mk_ico((MX, MY, B0 + 1.6), 0.15, (1, 1, 1.1), None, 2), "frg_silver", True)       # coif
P.box("team_color", (MX, MY - 0.13, B0 + 1.05), (0.34, 0.02, 0.5))                       # surcoat tabard
P.box("brass", (MX, MY - 0.145, B0 + 1.1), (0.08, 0.01, 0.2))
P.box("brass", (MX, MY - 0.145, B0 + 1.15), (0.2, 0.01, 0.06))
fin(P, "hauberk", Matrix.Identity(4))

# banners on poles at the front corners; each banner hinges at its pole top
for k, sx in enumerate((-1, 1)):
    x, y = sx * 2.7, -2.7
    P = Part()
    P.cyl("frg_timber_dark", (x, y, B0), (x, y, 3.0), 0.045, 0.035, seg=8)
    P.add(mk_ico((x, y, 3.04), 0.07), "brass", True)
    P.box("brass", (x, y, 2.82), (0.7, 0.08, 0.04))
    fin(P, "banner_pole_%d" % (k + 1), Matrix.Identity(4))
    P = Part()
    P.add(mk_prism([(-0.32, 0), (0.32, 0), (0.32, -1.05), (0, -1.3), (-0.32, -1.05)], (x, y, 2.8), X, Z, -0.015, 0.015),
          "team_color", True)
    P.add(mk_prism([(0, 0.0), (0.08, -0.12), (0, -0.24), (-0.08, -0.12)], (x, y - 0.0, 2.35), X, Z, -0.02, 0.02),
          "brass", True)
    fin(P, "banner_%d" % (k + 1), T((x, y, 2.8)))

for k in range(8):                                                                       # chimney smoke
    P = Part()
    P.add(mk_ico((HX, HY + 0.3, 5.3), 0.28, (1, 1, 0.85), None, 2), "frg_smoke")
    fin(P, "smoke_%d" % (k + 1), T((HX, HY + 0.3, 5.3)))

# ================================================================= death effects (keyed by animate_forge.py)
D = bpy.data.collections.new("forge_death_fx")
bpy.context.scene.collection.children.link(D)
P = Part()
P.add(mk_ico((HX, HY - 0.4, 1.0), 1.0, (1, 1, 0.8), None, 2), "frg_spark")
finish(D, P, "Flash_Forge", T((HX, HY - 0.4, 1.0)), None)
for i in range(6):
    P = Part()
    c = (random.uniform(-2.3, 2.3), random.uniform(-1.5, 2.3), 0.9)
    P.add(mk_ico(c, 0.55, (1, 1, 1.3), None, 2), "frg_fire")
    finish(D, P, "fx_fire_%d" % i, T(c), None)
for i in range(10):
    P = Part()
    c = (random.uniform(-2, 2), random.uniform(-1.5, 2.3), 1.8)
    P.add(mk_ico(c, 0.7, (1, 1, 0.9), None, 2), "frg_smoke")
    finish(D, P, "fx_smoke_%d" % i, T(c), None)
for i in range(14):
    P = Part()
    P.box(random.choice(["frg_stone", "frg_timber", "team_color", "frg_ivory"]), (0, 1.0, 1.6),
          (random.uniform(0.2, 0.45), random.uniform(0.15, 0.3), random.uniform(0.05, 0.15)), None, 0.01)
    finish(D, P, "fx_debris_%d" % i, T((0, 1.0, 1.6)), None)

bpy.context.view_layer.layer_collection.children["forge_death_fx"].exclude = True
tris = 0
for o in C.all_objects:
    if o.type == 'MESH':
        o.data.calc_loop_triangles()
        tris += len(o.data.loop_triangles)
print("TRIS", tris)
bpy.context.preferences.filepaths.save_version = 0
bpy.ops.wm.save_as_mainfile(filepath=OUT)
print("SAVED", OUT, len(C.all_objects), "objects")
