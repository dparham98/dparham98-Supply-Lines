"""Builds TempleOfScience.blend from nothing: the static armoured observatory temple.

Run in background Blender:
  blender --background --python build_temple.py

Everything is rebuilt each run, so edits here never compound. The door faces -Y, Z up, base on Z = 0.
The game footprint is 6 x 6 m, so the plinth fills 5.8 x 5.8 m. The helpers and the base palette are the
Generator's own (its build_generator.py up to its layout section, run here), so the buildings share one
look; the materials are renamed tos_* afterwards. Design: docs/TEMPLE_OF_SCIENCE_MODEL.md.
"""
import os, math

HERE = os.path.dirname(os.path.abspath(__file__))
GEN = os.path.normpath(os.path.join(HERE, "..", "..", "Generator", "build", "build_generator.py"))
_src = open(GEN, encoding="utf-8").read()
_src = _src[:_src.index("# ---------------------------------------------------------------- layout")]
_g = {"__file__": GEN, "__name__": "temple_helpers"}
exec(compile(_src, GEN, "exec"), _g)
for _k, _v in _g.items():
    if not _k.startswith("__"):
        globals()[_k] = _v
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.normpath(os.path.join(HERE, "..", "TempleOfScience.blend"))
random.seed(23)

# ---------------------------------------------------------------- temple materials
# the side's paint, oxblood in Blender. The Drone's fang brought a material of that exact name (the fang is
# drawn black in its place), so it steps aside: the game's team paint matches the name exactly.
_old = bpy.data.materials.get("team_color")
if _old:
    _old.name = "team_color_fang"
material("team_color", (0.235, 0.030, 0.020), 0.25, 0.55)
material("gen_marble", (0.30, 0.285, 0.255), 0.05, 0.62)                      # pale worn stone for the steps
material("gen_science", (0.20, 0.55, 0.75), 0.0, 0.35, (0.35, 0.85, 1.0), 2.4)  # cyan research glow in the slits
material("gen_orb", (0.20, 0.62, 0.90), 0.0, 0.25, (0.30, 0.80, 1.0), 1.6)      # the orb (the game drives its glow)
material("gen_lens", (0.10, 0.35, 0.50), 0.2, 0.05, (0.30, 0.80, 1.0), 1.2)
material("gen_void", (0.012, 0.014, 0.018), 0.0, 0.9)                         # the dark inside of the dome

# ---------------------------------------------------------------- layout (metres)
C8 = math.cos(math.radians(22.5))
ANG = [math.radians(-90 + 45 * k) for k in range(8)]          # face normals of every octagon, front first
DRUM_A, DRUM_Z0, DRUM_Z1 = 1.6, 0.45, 3.45                    # the cella: apothem, floor, top
COL_R, COL_Z0, COL_Z1 = 2.15, 0.45, 3.1                       # the colonnade on the drum's corners
ENT_A_IN, ENT_A_OUT, ENT_Z0, ENT_Z1 = 1.5, 2.45, 3.1, 3.45
DOME_C, DOME_R = V((0, 0, 3.62)), 1.52
SLIT = math.radians(15)                                        # half-width of the dome's shutter slit
ARM_C = V((0, 0, 6.05))                                        # the armillary's centre


def octagon(a, z=0.0):
    r = a / C8
    return [V((r * cos(t + math.radians(22.5)), r * sin(t + math.radians(22.5)), z)) for t in ANG]


def oct_ring(a_in, a_out, z0, z1):
    """A solid octagonal ring between two apothems."""
    bm = bmesh.new()
    loops = [[bm.verts.new(p) for p in octagon(a, z)] for a, z in
             ((a_out, z0), (a_out, z1), (a_in, z1), (a_in, z0))]
    for k in range(4):
        l0, l1 = loops[k], loops[(k + 1) % 4]
        for i in range(8):
            j = (i + 1) % 8
            bm.faces.new((l0[i], l0[j], l1[j], l1[i]))
    return bm


def face_frame(k, a):
    """Centre (at z = 0), tangent and normal of face k of an octagon of apothem a."""
    n = V((cos(ANG[k]), sin(ANG[k]), 0))
    return n * a, Z.cross(n).normalized(), n


def torus(c, axis, R, r, seg=32, rseg=6):
    prof = [(R + r * cos(2 * pi * i / rseg), r * sin(2 * pi * i / rseg)) for i in range(rseg)]
    return mk_lathe(prof, c, axis, seg, closed=True)


COLL = bpy.data.collections.new("temple_of_science")
_g["COLL"] = COLL
bpy.context.scene.collection.children.link(COLL)
root = empty("temple_root", Matrix.Identity(4), None, 0.5)

# ---------------------------------------------------------------- plinth: three stepped chamfered terraces
p = Part()
for i, (h, z0, z1) in enumerate(((2.9, 0.0, 0.16), (2.65, 0.16, 0.31), (2.42, 0.31, 0.45))):
    p.add(mk_prism(chamfer_poly(h, h, 0.42 - i * 0.05), V((0, 0, 0)), X, Y, z0, z1),
          "gen_gunmetal" if i == 0 else "gen_marble", True)
    p.add(mk_prism(chamfer_poly(h + 0.012, h + 0.012, 0.42 - i * 0.05), V((0, 0, 0)), X, Y, z1 - 0.03, z1),
          "gen_brass", True)
# hazard edging on the front of the lowest terrace, before the door
hazard(p, V((-0.6, -2.9 - 0.001, 0.0)), X, Z, -Y, 1.2, 0.14)
# team banners on the plinth corners: four slanted plates on the lowest terrace
for sx in (-1, 1):
    for sy in (-1, 1):
        d = V((sx, sy, 0)).normalized()
        c = V((sx * 2.6, sy * 2.6, 0.16))
        p.add(mk_box(c + Z * 0.04, (0.7, 0.18, 0.08), basis(Z.cross(d), d, Z), 0.01), "team_color", True)
plinth = finish(p, "plinth", Matrix.Identity(4), root)

# ---------------------------------------------------------------- drum: the plated octagonal cella with glowing slits
p = Part()
p.add(mk_prism([(q.x, q.y) for q in octagon(DRUM_A)], V((0, 0, 0)), X, Y, DRUM_Z0, DRUM_Z1),
      "gen_armour", True)
hw = DRUM_A * math.tan(math.radians(22.5))
for k in range(8):
    o, t, n = face_frame(k, DRUM_A)
    if k == 0:
        # door face: plates either side of the door, a lit lintel above it
        plates(p, o, t, Z, n, -hw + 0.05, -0.55, DRUM_Z0 + 0.1, DRUM_Z1 - 0.15, 1, 2)
        plates(p, o, t, Z, n, 0.55, hw - 0.05, DRUM_Z0 + 0.1, DRUM_Z1 - 0.15, 1, 2)
        plates(p, o, t, Z, n, -0.55, 0.55, 2.62, DRUM_Z1 - 0.15, 1, 1)
        plate_box(p, "gen_science", o + n * 0.05 + Z * 2.5, t, Z, n, 0.9, 0.07, 0.04, 0.0)
        continue
    plates(p, o, t, Z, n, -hw + 0.05, -0.12, DRUM_Z0 + 0.1, DRUM_Z1 - 0.15, 1, 2)
    plates(p, o, t, Z, n, 0.12, hw - 0.05, DRUM_Z0 + 0.1, DRUM_Z1 - 0.15, 1, 2)
    # the tall research slit between the plates, in a brass frame
    plate_box(p, "gen_brass", o + n * 0.02 + Z * 1.85, t, Z, n, 0.26, 2.2, 0.05)
    plate_box(p, "gen_science", o + n * 0.05 + Z * 1.85, t, Z, n, 0.12, 1.95, 0.03, 0.0)
# brass pipes climbing two rear corners to the dome collar
for ang in (math.radians(67.5), math.radians(112.5)):
    r0 = DRUM_A / C8 + 0.06
    b = V((cos(ang) * r0, sin(ang) * r0, 0))
    p.cyl("gen_copper", b + Z * DRUM_Z0, b + Z * ENT_Z0, 0.05, seg=8)
    for z in (1.0, 1.8, 2.6):
        p.cyl("gen_brass", b + Z * (z - 0.04), b + Z * (z + 0.04), 0.075, seg=8)
drum = finish(p, "drum", Matrix.Identity(4), root)

# ---------------------------------------------------------------- door: armoured double leaf in a brass frame
o, t, n = face_frame(0, DRUM_A)
p = Part()
p.box("gen_brass", o + n * 0.04 + Z * 1.4, (1.08, 0.08, 1.95), bevel=0.02)
for s in (-1, 1):
    p.box("gen_gunmetal", o + n * 0.09 + t * s * 0.235 + Z * 1.37, (0.44, 0.06, 1.82), bevel=0.012)
    for z in (0.8, 1.4, 2.0):
        p.box("gen_steel", o + n * 0.125 + t * s * 0.235 + Z * z, (0.38, 0.02, 0.05))
p.box("gen_black", o + n * 0.12 + Z * 1.37, (0.03, 0.03, 1.82))
door = finish(p, "door", T(o + Z * DRUM_Z0), root)

# ---------------------------------------------------------------- colonnade: eight armoured columns on the corners
p = Part()
for k in range(8):
    a = ANG[k] + math.radians(22.5)
    c = V((cos(a) * COL_R, sin(a) * COL_R, 0))
    rz = rot_z(a)
    p.add(mk_box(c + Z * (COL_Z0 + 0.1), (0.46, 0.46, 0.2), rz, 0.02), "gen_gunmetal", True)        # base
    p.cyl("gen_brass", c + Z * (COL_Z0 + 0.2), c + Z * (COL_Z0 + 0.28), 0.22, 0.19, seg=8, flat=True)
    p.cyl("gen_armour", c + Z * (COL_Z0 + 0.28), c + Z * (COL_Z1 - 0.2), 0.17, 0.15, seg=8, flat=True)  # shaft
    for z in (1.25, 2.05):
        p.cyl("gen_brass", c + Z * (z - 0.04), c + Z * (z + 0.04), 0.185, seg=8, flat=True)
    # a cyan conduit strip down the outward face of each shaft
    d = V((cos(a), sin(a), 0))
    p.add(mk_box(c + d * 0.155 + Z * 1.65, (0.05, 0.03, 1.9), rz @ rot_z(math.radians(90)), 0.0), "gen_science", True)
    p.cyl("gen_brass", c + Z * (COL_Z1 - 0.2), c + Z * (COL_Z1 - 0.06), 0.16, 0.25, seg=8, flat=True)  # capital
    p.add(mk_box(c + Z * (COL_Z1 - 0.03), (0.5, 0.5, 0.06), rz, 0.01), "gen_gunmetal", True)        # abacus
columns = finish(p, "columns", Matrix.Identity(4), root)

# ---------------------------------------------------------------- entablature: the ring the columns carry, team frieze
p = Part()
p.add(oct_ring(ENT_A_IN, ENT_A_OUT, ENT_Z0, ENT_Z1), "gen_gunmetal", True)
p.add(oct_ring(ENT_A_OUT - 0.02, ENT_A_OUT + 0.025, ENT_Z0 + 0.07, ENT_Z1 - 0.1), "team_color", True)  # frieze
p.add(oct_ring(ENT_A_IN, ENT_A_OUT + 0.09, ENT_Z1, ENT_Z1 + 0.07), "gen_brass", True)                 # cornice
p.add(oct_ring(ENT_A_IN + 0.3, ENT_A_OUT - 0.04, ENT_Z1 + 0.07, ENT_Z1 + 0.13), "gen_gunmetal", True)
# studs on the frieze
for k in range(8):
    o, t, n = face_frame(k, ENT_A_OUT + 0.025)
    for u in (-0.75, -0.25, 0.25, 0.75):
        p.rivet(o + t * u + Z * 3.24, n, 0.03, "gen_brass")
# pediment over the door: a gabled armour plate with the team tympanum and the fang
o, t, n = face_frame(0, ENT_A_OUT)
hwe = ENT_A_OUT * math.tan(math.radians(22.5)) + 0.08
z0 = ENT_Z1 + 0.07
p.add(mk_prism([(-hwe, 0), (hwe, 0), (0, 0.72)], o + Z * z0, t, Z, -0.8, 0.02), "gen_gunmetal", True)
p.add(mk_prism([(-hwe + 0.16, 0.06), (hwe - 0.16, 0.06), (0, 0.6)], o + Z * z0, t, Z, 0.02, 0.045), "team_color", True)
for s in (-1, 1):   # brass raking cornices
    a0, a1 = V((s * (hwe + 0.05), 0, -0.02)), V((0, 0, 0.77))
    q0 = o + Z * z0 + t * a0.x + Z * a0.z
    q1 = o + Z * z0 + Z * a1.z
    p.beam("gen_brass", q0 + n * 0.03, q1 + n * 0.03, 0.1, 0.08)
entablature = finish(p, "entablature", Matrix.Identity(4), root)
fang("pediment_fang", o + Z * (z0 + 0.27) + n * 0.052, n, -Z, 0.42, entablature)

# ---------------------------------------------------------------- dome: ribbed observatory dome with a shutter slit
p = Part()
p.cyl("gen_brass", V((0, 0, DRUM_Z1 + 0.13)), DOME_C + Z * 0.02, 1.66, seg=32, flat=False)            # collar
p.add(oct_ring(1.2, 1.62, DRUM_Z1 + 0.06, DRUM_Z1 + 0.14), "team_color", True)
N = 14
prof = [(DOME_R * cos(math.radians(a)), DOME_R * sin(math.radians(a))) for a in range(0, 91, 6)] + [(0.0, 0.0)]
p.add(mk_lathe(prof, DOME_C, Z, 40, a0=SLIT, a1=2 * pi - SLIT, ref=-Y), "gen_gunmetal")
p.sphere("gen_void", DOME_C, DOME_R - 0.1, u=24, v=12)
# ribs, skipping the slit
for i in range(N):
    a = -pi / 2 + 2 * pi * (i + 0.5) / N
    if abs(math.atan2(sin(a + pi / 2), cos(a + pi / 2))) < SLIT + 0.1:
        continue
    d = V((cos(a), sin(a), 0))
    pts = [DOME_C + (d * cos(math.radians(e)) + Z * sin(math.radians(e))) * (DOME_R + 0.012) for e in range(0, 85, 10)]
    p.tube("gen_brass", pts, 0.035, 6)
# shutter rails along both edges of the slit, and the cap at the crown
for s in (-1, 1):
    a = -pi / 2 + s * SLIT
    d = V((cos(a), sin(a), 0))
    pts = [DOME_C + (d * cos(math.radians(e)) + Z * sin(math.radians(e))) * (DOME_R + 0.04) for e in range(0, 91, 10)]
    p.tube("gen_steel", pts, 0.06, 6)
p.cyl("gen_brass", DOME_C + Z * (DOME_R - 0.06), DOME_C + Z * (DOME_R + 0.1), 0.32, 0.22, seg=16)
dome = finish(p, "dome", T(DOME_C), root)

# ---------------------------------------------------------------- telescope: tilted out through the slit
TEL_P = DOME_C + Z * 0.35
tilt = math.radians(32)
ax = V((0, -cos(tilt), sin(tilt)))
p = Part()
p.cyl("gen_gunmetal", TEL_P - ax * 0.5, TEL_P + ax * 1.6, 0.22, 0.18, seg=14)
p.cyl("gen_brass", TEL_P + ax * 1.6, TEL_P + ax * 1.9, 0.25, 0.25, seg=14)
p.cyl("gen_lens", TEL_P + ax * 1.9, TEL_P + ax * 1.93, 0.21, 0.21, seg=14)
for f in (0.1, 0.65, 1.2):
    p.cyl("gen_brass", TEL_P + ax * (f - 0.03), TEL_P + ax * (f + 0.03), 0.22, seg=14)
p.cyl("gen_steel", TEL_P - X * 0.32, TEL_P + X * 0.32, 0.08, seg=10)     # trunnion
telescope = finish(p, "telescope", T(TEL_P), dome)

# ---------------------------------------------------------------- mast and the armillary with its orb
p = Part()
p.cyl("gen_gunmetal", DOME_C + Z * (DOME_R + 0.08), ARM_C - Z * 0.6, 0.11, 0.07, seg=10)
p.cyl("gen_brass", ARM_C - Z * 0.62, ARM_C - Z * 0.56, 0.16, seg=10)
for k in range(3):   # three brass claws cradling the rings
    a = 2 * pi * k / 3
    d = V((cos(a), sin(a), 0))
    p.tube("gen_brass", [ARM_C - Z * 0.58, ARM_C - Z * 0.55 + d * 0.35, ARM_C - Z * 0.42 + d * 0.5], 0.025, 6, 0.1)
mast = finish(p, "mast", T(DOME_C + Z * DOME_R), root)

arm = empty("Armillary", T(ARM_C), root, 0.6, 'SPHERE')
p = Part()
p.sphere("gen_orb", ARM_C, 0.3, u=20, v=12)
orb = finish(p, "Orb", T(ARM_C), arm)
p = Part()
p.add(torus(ARM_C, V((0.0, 0.0, 1.0)), 0.55, 0.03), "gen_brass")
p.add(torus(ARM_C, V((0.0, 1.0, 0.0)), 0.55, 0.03), "gen_brass")
ring_a = finish(p, "RingA", T(ARM_C), arm)
p = Part()
p.add(torus(ARM_C, (rot_x(math.radians(60)) @ rot_z(math.radians(30))).to_3x3() @ Z, 0.47, 0.025), "gen_steel")
p.add(torus(ARM_C, (rot_y(math.radians(55))).to_3x3() @ Z, 0.47, 0.025), "gen_copper")
ring_b = finish(p, "RingB", T(ARM_C), arm)

# ---------------------------------------------------------------- four sensor pylons on the plinth corners
for i, (sx, sy) in enumerate(((-1, -1), (1, -1), (1, 1), (-1, 1))):
    c = V((sx * 2.1, sy * 2.1, 0.45))
    p = Part()
    p.add(mk_box(c + Z * 0.12, (0.42, 0.42, 0.24), rot_z(math.radians(45)), 0.02), "gen_gunmetal", True)
    p.cyl("gen_armour", c + Z * 0.24, c + Z * 1.55, 0.13, 0.07, seg=6, flat=True)
    p.cyl("gen_brass", c + Z * 0.7, c + Z * 0.78, 0.12, seg=6, flat=True)
    p.cyl("gen_steel", c + Z * 1.55, c + Z * 2.05, 0.025, seg=6)
    p.sphere("gen_science", c + Z * 2.08, 0.06, u=8, v=6)
    finish(p, "pylon_%02d" % (i + 1), T(c), root)

# ---------------------------------------------------------------- rename the materials to the temple's own
for m in bpy.data.materials:
    if m.name.startswith("gen_"):
        m.name = "tos_" + m.name[4:]

# ---------------------------------------------------------------- report
bpy.context.view_layer.update()
tris = 0
for o in bpy.data.objects:
    if o.type == 'MESH':
        o.data.calc_loop_triangles()
        tris += len(o.data.loop_triangles)
        print("TRIS", o.name, len(o.data.loop_triangles))
print("TRIS total", tris)
lo = V((9, 9, 9))
hi = V((-9, -9, -9))
for o in COLL.objects:
    if o.type == 'MESH':
        for v in o.data.vertices:
            w = o.matrix_world @ v.co
            lo = V((min(lo.x, w.x), min(lo.y, w.y), min(lo.z, w.z)))
            hi = V((max(hi.x, w.x), max(hi.y, w.y), max(hi.z, w.z)))
print("BOUNDS", [round(v, 3) for v in lo], [round(v, 3) for v in hi])

bpy.context.preferences.filepaths.save_version = 0
bpy.ops.wm.save_as_mainfile(filepath=OUT)
print("SAVED", OUT)
