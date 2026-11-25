"""Builds LandMine.blend from nothing: the Derailer's anti-vehicle mine and its blast.

  blender --background --python build_land_mine.py

Everything is rebuilt each run. Z up, base on Z = 0, centred on the origin, metres. The mine is
0.9 m across and 0.18 m tall to the plate (docs/MINES.md, docs/LAND_MINE_MODEL.md).

Collections:
  land_mine        the mine. Parts with their own pivots, moved in the game by land_mine_model.gd:
                     mine_root            sinks as the mine settles in
                       mine_body          casing, oxblood shoulder, team band, fangs
                       mine_plate         pressure plate; rises as it arms
                         mine_lamp        the fuse light
                       mine_prong_1..4    tilt rods, modelled upright; local X is the hinge
                     mine_soil            the dirt thrown up round it; grows as it settles
                     mine_spotted         warning ring, shown while the enemy has it detected
  land_mine_blast  the blast pieces, keyed by animate_land_mine.py.
"""
import bpy, os, sys, random
from math import sin, cos, radians, pi
from mathutils import Vector as V, Matrix

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import importlib, mesh_kit
importlib.reload(mesh_kit)
from mesh_kit import *  # noqa: F401,F403

OUT = os.path.normpath(os.path.join(HERE, "..", "LandMine.blend"))
DRONE = os.path.normpath(os.path.join(HERE, "..", "..", "..", "Vehicles", "Drone", "Drone.blend"))
random.seed(5)

bpy.ops.wm.read_factory_settings(use_empty=True)
FANG = load_fang(DRONE)

# ---------------------------------------------------------------- materials (the Derailer's)
material("mine_gunmetal", (0.155, 0.147, 0.138), 0.40, 0.52)
material("mine_charcoal", (0.058, 0.055, 0.054), 0.25, 0.62)
material("mine_steel", (0.33, 0.32, 0.30), 0.50, 0.42)
material("mine_oxblood", (0.235, 0.028, 0.020), 0.15, 0.58)
material("mine_brass", (0.40, 0.25, 0.08), 0.70, 0.42)
material("mine_team", (0.235, 0.028, 0.020), 0.15, 0.50)          # team paint in the game
material("mine_lamp", (0.30, 0.03, 0.01), 0.0, 0.35, (1.0, 0.12, 0.03), 3.0)
material("mine_soil", (0.085, 0.060, 0.040), 0.0, 0.95)
material("mine_spotted", (0.9, 0.35, 0.05), 0.0, 0.5, (1.0, 0.38, 0.05), 2.0)
material("mine_fx_dirt", (0.11, 0.08, 0.055), 0.0, 0.95)
material("mine_fx_dust", (0.19, 0.155, 0.11), 0.0, 1.0)
material("mine_fx_scorch", (0.02, 0.018, 0.016), 0.0, 0.98)
material("mine_fx_flash", (1.0, 0.85, 0.55), 0.0, 0.5, (1.0, 0.7, 0.3), 6.0)
material("mine_fx_fire", (0.9, 0.35, 0.06), 0.0, 0.6, (1.0, 0.45, 0.08), 4.0)

R = 0.45            # casing radius
H = 0.14            # casing height at the shoulder
PLATE_R = 0.19
PLATE_TOP = 0.18
PRONG_R = 0.30

# ================================================================= the mine
C = bpy.data.collections.new("land_mine")
bpy.context.scene.collection.children.link(C)
root = empty(C, "mine_root", Matrix.Identity(4), None, 0.3)

P = Part()
# casing: a squat drum with a chamfered foot and a sloped shoulder up to the plate seat
P.add(mk_lathe([(0.0, 0.0), (R - 0.03, 0.0), (R, 0.025), (R, 0.075), (R - 0.01, 0.085),
                (R - 0.06, H), (PLATE_R + 0.05, H + 0.012), (PLATE_R + 0.03, H + 0.012), (0.0, H + 0.012)], seg=32),
      "mine_gunmetal")
# oxblood shoulder band and the team band round the drum
P.add(mk_lathe([(R - 0.055, H - 0.004), (R - 0.008, 0.088), (R - 0.004, 0.092), (R - 0.05, H + 0.002),
                (R - 0.055, H - 0.004)], seg=32), "mine_oxblood")
P.add(mk_lathe([(R + 0.004, 0.034), (R + 0.006, 0.036), (R + 0.006, 0.064), (R + 0.004, 0.066)], seg=32),
      "mine_team")
P.add(mk_lathe([(R - 0.02, 0.018), (R + 0.002, 0.018), (R + 0.002, 0.030), (R - 0.02, 0.030)], seg=32),
      "mine_charcoal")
# plate seat ring, rivets and four grab lugs
P.add(mk_annulus((0, 0, H + 0.008), PLATE_R + 0.002, PLATE_R + 0.045, 0.016, seg=32), "mine_steel")
for k in range(12):
    a = 2 * pi * k / 12
    P.rivet((cos(a) * (PLATE_R + 0.03), sin(a) * (PLATE_R + 0.03), H + 0.024), Z, 0.009)
for k in range(4):
    a = 2 * pi * k / 4 + pi / 4
    d = V((cos(a), sin(a), 0))
    t = Z.cross(d)
    c = d * (R - 0.005) + Z * 0.06
    P.box("mine_charcoal", c, (0.08, 0.035, 0.05), basis(t, d, Z), 0.006)
    for s in (1, -1):
        P.rivet(c + d * 0.018 + t * s * 0.025, d, 0.007)
# prong sockets on the shoulder
for k in range(4):
    a = 2 * pi * k / 4
    d = V((cos(a), sin(a), 0))
    z = H - (PRONG_R - PLATE_R - 0.03) * 0.4
    P.cyl("mine_charcoal", d * PRONG_R + Z * (z - 0.02), d * PRONG_R + Z * (z + 0.02), 0.028, seg=10)
body = finish(C, P, "mine_body", Matrix.Identity(4), root)
# faction fangs on the shoulder, between the prongs, tips pointing out
for k in range(4):
    a = 2 * pi * k / 4 + pi / 4
    d = V((cos(a), sin(a), 0))
    r = (R - 0.06 + PLATE_R + 0.06) / 2 + 0.03
    z = H - (r - PLATE_R - 0.05) * (H - 0.085) / (R - 0.06 - PLATE_R - 0.05) + 0.004
    slope = (V((d.x, d.y, -(H - 0.085) / (R - 0.06 - PLATE_R - 0.05)))).normalized()
    n = slope.cross(Z.cross(d)).normalized()
    if n.z < 0:
        n = -n
    fang(C, FANG, "mine_fang_%d" % (k + 1), d * r + Z * z + n * 0.003, n, slope, 0.085, body)

# pressure plate: a hexagon with ribs, on its own pivot so it can rise
P = Part()
hexa = [(cos(pi / 3 * i + pi / 6) * PLATE_R, sin(pi / 3 * i + pi / 6) * PLATE_R) for i in range(6)]
P.add(mk_prism(hexa, (0, 0, 0), X, Y, H - 0.01, PLATE_TOP - 0.008), "mine_charcoal", True)
hexb = [(x * 0.93, y * 0.93) for x, y in hexa]
P.add(mk_prism(hexb, (0, 0, 0), X, Y, PLATE_TOP - 0.008, PLATE_TOP), "mine_steel", True)
for k in range(3):
    a = pi / 3 * k
    P.box("mine_gunmetal", (0, 0, PLATE_TOP + 0.006), (0.30, 0.022, 0.012), rot_z(a), 0.003)
P.cyl("mine_brass", (0, 0, PLATE_TOP), (0, 0, PLATE_TOP + 0.02), 0.06, 0.055, seg=16)
plate = finish(C, P, "mine_plate", T((0, 0, H)), root)
P = Part()
P.add(mk_lathe([(0.0, PLATE_TOP + 0.02), (0.045, PLATE_TOP + 0.02), (0.044, PLATE_TOP + 0.035),
                (0.03, PLATE_TOP + 0.05), (0.0, PLATE_TOP + 0.056)], seg=16), "mine_lamp")
finish(C, P, "mine_lamp", T((0, 0, PLATE_TOP + 0.02)), plate)

# tilt-rod prongs: upright in the file; local X along the shoulder is the fold hinge
for k in range(4):
    a = 2 * pi * k / 4
    d = V((cos(a), sin(a), 0))
    t = Z.cross(d)
    base = d * PRONG_R + Z * (H - (PRONG_R - PLATE_R - 0.03) * 0.4 + 0.02)
    world = Matrix.Translation(base) @ basis(t, -d, Z)
    P = Part()
    P.cyl("mine_steel", base, base + Z * 0.14, 0.011, 0.008, seg=8)
    P.cyl("mine_brass", base + Z * 0.135, base + Z * 0.15, 0.018, 0.014, seg=8)
    P.cyl("mine_charcoal", base - Z * 0.005, base + Z * 0.02, 0.018, seg=8)
    finish(C, P, "mine_prong_%d" % (k + 1), world, root)

# soil thrown up round it as it beds in: lumps on a low ring
P = Part()
P.add(mk_lathe([(R - 0.02, 0.0), (R + 0.05, 0.05), (R + 0.13, 0.035), (R + 0.24, 0.0)], seg=32), "mine_soil")
for i in range(26):
    a = random.uniform(0, 2 * pi)
    rr = R + random.uniform(0.04, 0.22)
    P.add(mk_ico((cos(a) * rr, sin(a) * rr, 0.012), random.uniform(0.025, 0.05),
                 (1.3, 1.0, 0.55), rot_z(random.uniform(0, 6))), "mine_soil", True)
finish(C, P, "mine_soil", Matrix.Identity(4), None)

# spotted ring: eight amber chevron arcs and a thin outer circle, flat on the ground
P = Part()
for k in range(8):
    a0 = 2 * pi * k / 8 + 0.09
    P.add(mk_annulus((0, 0, 0.0), 0.78, 0.90, 0.02, a0, a0 + 2 * pi / 8 - 0.18, 6), "mine_spotted", True)
    a = 2 * pi * k / 8
    d, t = V((cos(a), sin(a), 0)), V((-sin(a), cos(a), 0))
    tri = [(0.0, 0.0), (0.09, -0.05), (0.09, 0.05)]
    P.add(mk_prism([(0.96 + u, v) for u, v in tri], (0, 0, 0), d, t, 0.0, 0.02), "mine_spotted", True)
P.add(mk_annulus((0, 0, 0.0), 1.10, 1.13, 0.015, seg=48), "mine_spotted", True)
finish(C, P, "mine_spotted", T((0, 0, 0.015)), None)

# ================================================================= blast pieces (keyed by animate_land_mine.py)
B = bpy.data.collections.new("land_mine_blast")
bpy.context.scene.collection.children.link(B)
P = Part()
P.add(mk_ico((0, 0, 0), 0.6, (1, 1, 0.8), None, 2), "mine_fx_flash")
finish(B, P, "Impact_Flash", T((0, 0, 0.35)), None)
P = Part()
P.add(mk_ico((0, 0, 0), 0.45, (1, 1, 1.4), None, 2), "mine_fx_fire")
finish(B, P, "blast_fire", T((0, 0, 0.4)), None)
P = Part()
P.add(mk_lathe([(0.0, 0.0), (1.0, 0.0), (0.98, 0.01), (0.0, 0.012)], seg=32), "mine_fx_scorch", True)
for i in range(14):
    a = 2 * pi * i / 14 + random.uniform(-0.1, 0.1)
    l = random.uniform(1.2, 1.55)
    P.add(mk_prism([(0.6, -0.12), (l, 0.0), (0.6, 0.12)], (0, 0, 0), V((cos(a), sin(a), 0)),
                   V((-sin(a), cos(a), 0)), 0.0, 0.01), "mine_fx_scorch", True)
finish(B, P, "blast_scorch", T((0, 0, 0.006)), None)
P = Part()
P.add(mk_lathe([(0.92, 0.0), (1.0, 0.03), (0.97, 0.08), (0.9, 0.03)], seg=40), "mine_fx_dust")
finish(B, P, "blast_ring", T((0, 0, 0.05)), None)
for i in range(16):
    P = Part()
    P.add(mk_ico((0, 0, 0), random.uniform(0.07, 0.13), (random.uniform(0.8, 1.3), 1, random.uniform(0.7, 1.1)),
                 rot_z(random.uniform(0, 6)) @ rot_x(random.uniform(0, 6))), "mine_fx_dirt", True)
    finish(B, P, "blast_clod_%02d" % i, T((0, 0, 0.1)), None)
for i in range(12):
    P = Part()
    P.add(mk_ico((0, 0, 0), random.uniform(0.26, 0.4), (1, 1, 0.8), None, 2), "mine_fx_dust")
    finish(B, P, "blast_dust_%02d" % i, T((0, 0, 0.2)), None)
for i in range(18):
    P = Part()
    P.box("mine_gunmetal" if i % 3 else "mine_oxblood", (0, 0, 0),
          (random.uniform(0.05, 0.09), random.uniform(0.03, 0.05), 0.012), None, 0.0)
    finish(B, P, "blast_shard_%02d" % i, T((0, 0, 0.12)), None)

bpy.context.view_layer.layer_collection.children["land_mine_blast"].exclude = True
bpy.context.preferences.filepaths.save_version = 0
bpy.ops.wm.save_as_mainfile(filepath=OUT)
print("SAVED", OUT, len(C.all_objects), "mine objects", len(B.all_objects), "blast objects")
