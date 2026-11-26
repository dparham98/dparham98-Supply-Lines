"""Builds KnightsTrain.blend from nothing: the Arthurian Knights' coal-fired maglev car (docs/KNIGHTS_TRAIN_MODEL.md).

  blender --background --python build_knights_train.py

Everything is rebuilt each run. The car keeps the Astra Streamliner's runtime contract
(Blender/Vehicles/Maglev/Astra_Streamliner/validation/audit/accepted_contract.md), so scripts/rails/train_consist.gd
places it unchanged. The nose is to -Y, Z is up, and all sizes are authored metres (the game scales the car by 0.6).
The contract's nodes, all direct children of train_cargo_root with identity rotation, are at:
  cargo_body (0, 0, 2.5); sled_cargo_front (0, -3, 1) and sled_cargo_rear (0, 3, 1); cargo_coupler_F (0, -5.5, 1.67)
  and cargo_coupler_R (0, 5.5, 1.67); cargo_car_indicator (0, 3.55, 3.6).
scripts/rails/knights_train_model.gd animates the extra parts under cargo_body: firebox_glow, firebox_embers and
stack_smoke_1..5. Nothing here is keyed, so there are no clips.

The look: a stone firebox and a flared iron stack at the nose, a coal bunker behind it, then an iron-banded
timber hold under a team-blue roof with heater shields along both sides. Brass trim, team pennants at the tail,
and runner sleds of timber and iron with brass lodestone pads.
"""
import bpy, os, sys, random
from math import sin, cos, radians, pi
from mathutils import Vector as V, Matrix

HERE = os.path.dirname(os.path.abspath(__file__))
KIT = os.environ.get("SL_BUILDING_KIT") or os.path.normpath(os.path.join(HERE, "..", "..", "..", "Buildings", "Foundry", "build"))
sys.path.insert(0, KIT)
import importlib, building_kit
importlib.reload(building_kit)
from building_kit import *  # noqa: F401,F403

OUT = os.path.normpath(os.path.join(HERE, "..", "KnightsTrain.blend"))
random.seed(61)
bpy.ops.wm.read_factory_settings(use_empty=True)

material("kt_stone", (0.62, 0.60, 0.55), 0.0, 0.85)
material("kt_ivory", (0.83, 0.82, 0.73), 0.35, 0.43)
material("kt_timber", (0.20, 0.11, 0.05), 0.0, 0.8)
material("kt_timber_dark", (0.09, 0.05, 0.025), 0.0, 0.85)
material("kt_iron", (0.17, 0.18, 0.20), 0.75, 0.45)
material("kt_silver", (0.69, 0.72, 0.73), 0.6, 0.38)
material("kt_coal", (0.02, 0.02, 0.022), 0.0, 0.6)
material("kt_interior", (0.02, 0.02, 0.025), 0.1, 0.85)
material("kt_fire", (0.9, 0.4, 0.06), 0.0, 0.5, (1.0, 0.45, 0.08), 6.0)
material("kt_embers", (0.35, 0.06, 0.02), 0.0, 0.6, (0.8, 0.15, 0.03), 1.2)
material("kt_signal", (1.0, 0.7, 0.3), 0.1, 0.3, (1.0, 0.65, 0.22), 4.0)
material("kt_smoke", (0.2, 0.19, 0.18), 0.0, 1.0)
material("brass", (0.71, 0.44, 0.12), 0.65, 0.37)
material("team_color", (0.025, 0.075, 0.38), 0.08, 0.64)

C = bpy.data.collections.new("knights_train")
bpy.context.scene.collection.children.link(C)
root = empty(C, "train_cargo_root", Matrix.Identity(4), None, 0.5)


def fin(P, name, world, parent=root):
    return finish(C, P, name, world, parent)


# ================================================================= body (fixed), origin at (0, 0, 2.5)
P = Part()
# underframe: a timber bed with iron bands, buffer beams at both ends
P.box("kt_timber", (0, 0.1, 1.42), (3.1, 10.2, 0.34), None, 0.03)
for y in (-4.6, -2.4, 0.0, 2.4, 4.6):
    P.box("kt_iron", (0, y, 1.42), (3.16, 0.14, 0.38), None, 0.01)
for sy in (-1, 1):
    P.box("kt_iron", (0, sy * 5.15, 1.55), (3.0, 0.22, 0.5), None, 0.03)
    for sx in (-1, 1):
        P.cyl("brass", (sx * 1.0, sy * 5.25, 1.6), (sx * 1.0, sy * 5.42, 1.6), 0.16, 0.18, seg=10)  # buffers
# the nose: stone firebox with a brass-framed fire door
P.box("kt_stone", (0, -4.15, 2.35), (2.7, 1.9, 1.5), None, 0.06)
P.box("kt_ivory", (0, -4.15, 3.14), (2.85, 2.0, 0.12), None, 0.02)
P.box("brass", (0, -5.12, 2.2), (1.0, 0.06, 0.8), None, 0.01)
P.box("kt_interior", (0, -5.13, 2.2), (0.8, 0.05, 0.62))
for sx in (-1, 1):
    P.box("kt_ivory", (sx * 1.38, -4.15, 2.35), (0.08, 2.0, 1.5), None, 0.01)
# the stack: flared iron, brass bands
P.add(mk_lathe([(0.0, 3.1), (0.34, 3.1), (0.3, 3.3), (0.26, 3.75), (0.3, 3.82), (0.46, 3.95), (0.42, 3.97), (0.0, 3.97)],
               (0, -4.45, 0), Z, 16), "kt_iron", False)
for z in (3.32, 3.72):
    P.cyl("brass", (0, -4.45, z), (0, -4.45, z + 0.06), 0.31, seg=16)
# coal bunker behind the firebox
P.box("kt_timber_dark", (0, -2.55, 2.1), (2.8, 1.25, 1.0), None, 0.03)
for sx in (-1, 1):
    P.box("kt_iron", (sx * 1.42, -2.55, 2.1), (0.05, 1.3, 1.04))
for i in range(9):
    P.add(mk_ico((random.uniform(-1.0, 1.0), -2.55 + random.uniform(-0.4, 0.4), 2.6 + random.uniform(0, 0.12)),
                 random.uniform(0.18, 0.28), (1, 1, 0.6)), "kt_coal", True)
# the hold: iron-banded timber walls under a team-blue barrel roof
HY0, HY1 = -1.85, 2.75
P.box("kt_timber", (0, (HY0 + HY1) / 2, 2.55), (3.3, HY1 - HY0, 1.9), None, 0.05)
for k in range(6):
    y = HY0 + 0.25 + k * (HY1 - HY0 - 0.5) / 5
    P.box("kt_iron", (0, y, 2.55), (3.38, 0.12, 1.96), None, 0.01)
P.box("kt_ivory", (0, (HY0 + HY1) / 2, 3.52), (3.44, HY1 - HY0 + 0.1, 0.1), None, 0.02)
roof = [[V((1.72 * cos(a), y, 3.57 + 0.38 * sin(a))) for a in [radians(d) for d in range(0, 181, 15)]] for y in (HY0, HY1)]
P.add(mk_loft(roof), "team_color", False)
P.cyl("brass", (0, HY0 - 0.02, 3.95), (0, HY1 + 0.02, 3.95), 0.05, seg=8)
for sx in (-1, 1):
    for k in range(3):                                                    # heater shields along each side
        y = -1.05 + k * 1.4
        c = V((sx * 1.7, y, 2.6))
        shield = [(-0.42, 0.45), (0.42, 0.45), (0.42, 0.0), (0.25, -0.35), (0, -0.55), (-0.25, -0.35), (-0.42, 0.0)]
        rim = [(x * 1.12, z * 1.1 + 0.02) for x, z in shield]
        P.add(mk_prism(rim, c, Y * -sx, Z, -0.03, 0.03), "kt_silver", True)
        P.add(mk_prism(shield, c + X * sx * 0.04, Y * -sx, Z, -0.03, 0.03), "team_color", True)
        P.box("kt_ivory", c + X * sx * 0.08 + Z * 0.0, (0.03, 0.12, 0.8), None)
        P.box("kt_ivory", c + X * sx * 0.08 + Z * 0.15, (0.03, 0.6, 0.12), None)
    P.box("brass", (sx * 1.7, (HY0 + HY1) / 2, 1.72), (0.06, HY1 - HY0, 0.1))
    # the open cargo deck at the tail: crates and sacks inside a low iron rail, pennant poles at its corners
P.box("kt_timber", (0, 3.95, 1.68), (3.2, 2.4, 0.18), None, 0.02)
for x, y, h in ((-0.75, 3.55, 0.75), (0.7, 3.4, 0.6), (0.6, 4.45, 0.7), (-0.8, 4.5, 0.5)):
    P.box("kt_timber", (x, y, 1.77 + h / 2), (0.9, 0.8, h), None, 0.03)
    for sx2 in (-1, 1):
        P.box("kt_iron", (x + sx2 * 0.44, y, 1.77 + h / 2), (0.04, 0.84, h + 0.02))
P.add(mk_ico((0.0, 4.1, 2.0), 0.32, (1.1, 0.8, 0.7)), "kt_ivory", False)               # sack
for sx in (-1, 1):
    P.box("kt_iron", (sx * 1.55, 3.95, 2.3), (0.05, 2.4, 0.05))
    for y in (2.9, 3.95, 5.0):
        P.box("kt_iron", (sx * 1.55, y, 2.03), (0.05, 0.05, 0.55))
    P.cyl("kt_timber_dark", (sx * 1.5, 4.95, 1.77), (sx * 1.5, 4.95, 3.97), 0.04, seg=6)
    P.add(mk_ico((sx * 1.5, 4.95, 3.97), 0.06), "brass", True)
P.box("kt_iron", (0, 5.1, 2.3), (3.1, 0.05, 0.05))
P.cyl("kt_iron", (0, 3.55, 1.77), (0, 3.55, 3.3), 0.05, seg=6)                       # the lantern's post
body = fin(P, "cargo_body", T((0, 0, 2.5)))
P = Part()
for sx in (-1, 1):
    P.add(mk_prism([(0, 0), (0.75, 0.1), (0, 0.3)], V((sx * 1.5, 4.95, 3.62)), Y, Z, -0.01, 0.01), "team_color", True)
fin(P, "pennants", T((0, 4.95, 3.62)), body)
P = Part()                                                                # the fire behind the door: bright while running
P.box("kt_fire", (0, -5.185, 2.15), (0.74, 0.03, 0.5))
P.add(mk_ico((0, -5.17, 2.0), 0.3, (1.2, 0.25, 0.6)), "kt_fire", True)
fin(P, "firebox_glow", T((0, -5.185, 2.15)), body)
P = Part()                                                                # banked embers: what shows out of coal
P.box("kt_embers", (0, -5.165, 1.98), (0.7, 0.02, 0.22))
fin(P, "firebox_embers", T((0, -5.165, 1.98)), body)
for k in range(5):
    P = Part()
    c = V((0, -4.45, 4.15))
    P.add(mk_ico(c, 0.32, (1, 1, 0.85), None, 2), "kt_smoke")
    fin(P, "stack_smoke_%d" % (k + 1), T(c), body)

# ================================================================= sleds: timber bolster on iron runners, brass pads
for name, y in (("sled_cargo_front", -3.0), ("sled_cargo_rear", 3.0)):
    P = Part()
    P.box("kt_timber", (0, y, 1.2), (2.0, 1.2, 0.2), None, 0.02)                 # bolster
    for sx in (-1, 1):
        P.box("kt_iron", (sx * 1.0, y, 0.85), (0.4, 2.8, 0.28), None, 0.04)      # runner
        P.add(mk_prism([(-1.4, 0.14), (1.4, 0.14), (1.55, 0.0), (1.4, -0.14), (-1.4, -0.14), (-1.55, 0.0)],
                       V((sx * 1.0, y, 0.85)), Y, Z, -0.21, 0.21), "kt_iron", True)
        for k in (-1, 0, 1):
            P.box("brass", (sx * 1.0, y + k * 0.8, 0.69), (0.36, 0.5, 0.04), None, 0.01)  # lodestone pads
        P.box("kt_timber_dark", (sx * 0.6, y, 1.04), (0.2, 0.9, 0.2))
    P.cyl("kt_iron", (0, y, 1.08), (0, y, 1.34), 0.18, seg=10)                   # pivot
    fin(P, name, T((0, y, 1.0)))

# ================================================================= couplers and the cargo lantern
for name, y in (("cargo_coupler_F", -5.5), ("cargo_coupler_R", 5.5)):
    P = Part()
    s = -1 if y < 0 else 1
    P.box("kt_iron", (0, y - s * 0.12, 1.67), (0.3, 0.3, 0.22), None, 0.02)
    P.add(mk_annulus(V((0, y + s * 0.0, 1.67)), 0.08, 0.15, 0.08, seg=10), "kt_iron", True)
    fin(P, name, T((0, y, 1.67)))
P = Part()
L = V((0, 3.55, 3.6))
P.cyl("kt_iron", L - Z * 0.25, L - Z * 0.12, 0.13, seg=8)
P.cyl("kt_signal", L - Z * 0.12, L + Z * 0.14, 0.11, seg=8)
for a in range(4):
    d = V((cos(a * pi / 2 + pi / 4), sin(a * pi / 2 + pi / 4), 0)) * 0.12
    P.cyl("brass", L + d - Z * 0.12, L + d + Z * 0.14, 0.015, seg=4)
P.add(mk_lathe([(0.0, 0.14), (0.16, 0.14), (0.0, 0.3)], L, Z, 8), "brass", True)
P.add(mk_annulus(L + Z * 0.33, 0.03, 0.06, 0.03, seg=8), "brass", True)
fin(P, "cargo_car_indicator", T(L))

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
