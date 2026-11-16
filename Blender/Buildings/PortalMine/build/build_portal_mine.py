"""Builds PortalMine.blend from nothing and exports it: the Iron Mine that stands in a mine site, dug into the rock.

Run in background Blender, from anywhere:
  blender --background --python Blender/Buildings/PortalMine/build/build_portal_mine.py

Everything is rebuilt each run. It writes Blender/Buildings/PortalMine/PortalMine.blend and
assets/models/buildings/portal_mine.glb. Design in docs/PORTAL_MINE_MODEL.md, after the concept of 2026-11-15: a
steel portal in a collar of rust-streaked rock, rails and an ore cart running out of it, a hoist beside it, a winch
house on a trestle and two tanks.

The front faces -Y, Z up, base on Z = 0. A mine site is 4 m across and 3 m deep (docs/MINE_SITES.md), so the
model stays within X +-2 and Y +-1.5; only the rails run on, flat, over the 2 m strip kept clear in front. The
mountain's cut has sheer walls at the back (Y = 1.5) and on both flanks (X = +-2), which the rock collar hides.

The geometry and animation helpers and the materials are the old Iron Mine's own: the first section of
Blender/Buildings/IronMine/build/build_mine.py and of animate_mine.py is run from here, so the two mines share
one look. If those files are reorganised, the two markers below have to follow.
"""
import os

HERE = os.path.dirname(os.path.abspath(__file__))
OLD = os.path.normpath(os.path.join(HERE, "..", "..", "IronMine", "build"))


def shared(path, marker):
    """The part of one of the old mine's scripts that comes before its own model."""
    source = open(os.path.join(OLD, path), encoding="utf-8").read()
    assert marker in source, "%s no longer has the line %r" % (path, marker)
    return source[:source.index(marker)]


exec(shared("build_mine.py", "# ---------------------------------------------------------------- layout (metres)"))
random.seed(41)
# The shared section names the old mine's files; these are this one's.
OUT = os.path.normpath(os.path.join(HERE, "..", "PortalMine.blend"))
GLB = os.path.normpath(os.path.join(HERE, "..", "..", "..", "..", "assets", "models", "buildings", "portal_mine.glb"))
PREVIEW = os.path.normpath(os.path.join(HERE, "..", "..", "..", "Previews", "PortalMine", "portal_mine_review.png"))

material("mine_rock", (0.2, 0.165, 0.135), 0.0, 0.92)
material("mine_rock2", (0.13, 0.105, 0.09), 0.0, 0.95)
material("mine_rock3", (0.27, 0.225, 0.18), 0.0, 0.9)
material("mine_rock_rust", (0.21, 0.085, 0.04), 0.1, 0.85)
material("mine_gravel", (0.13, 0.105, 0.08), 0.0, 0.95)
material("mine_banner", (0.27, 0.03, 0.025), 0.0, 0.8)
material("mine_banner_mark", (0.03, 0.025, 0.025), 0.0, 0.8)

scene = bpy.context.scene
scene.name = "PortalMine"
COLL = bpy.data.collections.new("portal_mine")
scene.collection.children.link(COLL)
root = empty("portal_mine_root", Matrix.Identity(4), None, 0.5)

# ---------------------------------------------------------------- layout (metres)
PORTAL_Y = 0.25                       # the portal's front face
PORTAL_W = 1.26                       # clear width of the mouth
PORTAL_H = 1.72                       # and its height
RAIL_X = 0.29                         # half the track gauge
CART_REST = V((0.0, -0.85, 0.0))      # the cart, loaded, just outside the mouth
CART_IN = 1.75                        # how far it runs into the tunnel, out of sight
HOIST = V((1.45, -0.1, 0.0))          # foot of the hoist post
JIB = V((1.45, -0.93, 2.72))          # the wheel at the end of its arm, axis along X
WHEEL_R = 0.19
ROPE_TOP = V((JIB.x, JIB.y - WHEEL_R, JIB.z))
BUCKET_TOP = 1.62                     # the bucket's bail at rest, raised
BUCKET_DROP = 0.95                    # how far it lowers, into the ore bin
DECK = (-1.92, -0.98, 0.12, 1.02, 1.42)   # winch house trestle x0, x1, y0, y1 and deck height


def boulder(part, c, r, scale=(1, 1, 1), mat=None, sub=1, rough=0.16):
    """A faceted rock: a stretched, turned icosphere with its corners knocked about."""
    bm = mk_ico(c, r, scale, rot_z(random.uniform(0, pi)) @ rot_x(random.uniform(-0.5, 0.5)), sub)
    for v in bm.verts:
        v.co += V((random.uniform(-1, 1), random.uniform(-1, 1), random.uniform(-1, 1))) * r * rough
        v.co.z = max(v.co.z, 0.0)
        v.co.x = max(-2.12, min(2.12, v.co.x))
        v.co.y = min(v.co.y, 1.62)
    if mat is None:
        mat = random.choice(("mine_rock", "mine_rock", "mine_rock2", "mine_rock3", "mine_rock_rust"))
    part.add(bm, mat, True)


# ---------------------------------------------------------------- the floor: a gravel pad, the track and its sleepers
p = Part()
p.box("mine_gravel", (0, 0, 0.02), (3.9, 2.94, 0.04))
p.box("mine_concrete2", (0, -0.15, 0.035), (1.7, 2.6, 0.05), bevel=0.01)          # the hard standing before the mouth
for k in range(7):
    c = V((random.uniform(-1.7, 1.7), random.uniform(-1.3, 0.2), 0.045))
    p.box("mine_stain", c, (random.uniform(0.15, 0.45), random.uniform(0.06, 0.2), 0.004), rot_z(random.uniform(0, pi)))
y = PORTAL_Y + 0.3
while y > -3.4:                         # sleepers, out over the strip kept clear in front
    p.box("mine_wood2" if random.random() < 0.4 else "mine_wood", (random.uniform(-0.015, 0.015), y, 0.075), (0.86, 0.11, 0.05), rot_z(random.uniform(-0.03, 0.03)), 0.006)
    y -= 0.32
for side in (-1, 1):
    p.box("mine_steel", (side * RAIL_X, (PORTAL_Y + 0.45 - 3.45) / 2, 0.125), (0.045, PORTAL_Y + 0.45 + 3.45, 0.05), bevel=0.006)
    p.box("mine_rust", (side * RAIL_X, (PORTAL_Y + 0.45 - 3.45) / 2, 0.152), (0.03, PORTAL_Y + 0.45 + 3.45, 0.004))
p.box("mine_wood", (0, -3.42, 0.16), (0.8, 0.1, 0.16), bevel=0.01)                 # the buffer at the end of the track
p.box("mine_hazard", (0, -3.476, 0.16), (0.8, 0.012, 0.1))
for k in range(9):                      # spilled ore and stones about the pad
    c = V((random.uniform(-1.8, 1.8), random.uniform(-1.35, -0.2), 0.04))
    if abs(c.x) < 0.6: c.x += 0.9 if c.x > 0 else -0.9
    boulder(p, c, random.uniform(0.05, 0.11), (1, 1, 0.7), random.choice(("mine_ore", "mine_ore2", "mine_rock")), rough=0.2)
floor = finish(p, "floor", T((0, 0, 0)), root)

# ---------------------------------------------------------------- the rock collar the portal is set in
p = Part()
# The mass behind and above the mouth, highest in the middle.
for x in (-1.75, -1.05, -0.35, 0.4, 1.1, 1.75):
    high = 3.0 - abs(x) * 0.5
    boulder(p, (x + random.uniform(-0.1, 0.1), 1.2, 0.0), 0.6, (1.0, 0.6, 1.6))
    boulder(p, (x + random.uniform(-0.1, 0.1), 1.25, high * 0.5), 0.55, (1.05, 0.6, 1.3))
    boulder(p, (x + random.uniform(-0.15, 0.15), 1.2, high * 0.9), 0.5, (1.1, 0.7, 0.9))
# A higher tier against the back wall of the cut, which stands 3 to 6 m tall behind the mine.
for x in (-1.6, -0.8, 0.0, 0.85, 1.6):
    high = 4.5 - abs(x) * 0.55
    boulder(p, (x + random.uniform(-0.12, 0.12), 1.38, high * 0.78), 0.55, (1.1, 0.5, 1.25))
    boulder(p, (x + random.uniform(-0.2, 0.2) + 0.4, 1.45, high), 0.42, (1.2, 0.45, 1.0))
# The crown over the lintel, streaked with rust where the ore shows.
boulder(p, (-0.05, 0.72, 2.42), 0.62, (1.5, 0.7, 0.85), "mine_rock")
boulder(p, (0.55, 0.7, 2.7), 0.42, (1.2, 0.8, 0.9), "mine_rock_rust")
boulder(p, (-0.7, 0.75, 2.75), 0.4, (1.1, 0.8, 1.0), "mine_rock3")
boulder(p, (0.1, 0.95, 3.1), 0.5, (1.4, 0.7, 0.9), "mine_rock2")
# Shoulders either side of the mouth, falling away to the front. The left one leaves room for the trestle.
for x, mat, high in ((1.0, "mine_rock_rust", 2.0), (1.45, "mine_rock", 1.7), (1.85, "mine_rock2", 1.5)):
    boulder(p, (x, 0.62, 0.0), 0.5, (0.9, 0.9, 1.5), mat)
    boulder(p, (x, 0.7, high * 0.62), 0.42, (1.0, 0.85, 1.2))
    boulder(p, (x + 0.1, 0.8, high), 0.34, (1.1, 0.9, 1.0))
boulder(p, (1.9, 0.08, 0.0), 0.36, (0.6, 1.1, 1.5), "mine_rock3")
boulder(p, (1.92, 0.3, 0.75), 0.3, (0.6, 1.2, 1.1))
boulder(p, (1.92, -0.6, 0.0), 0.3, (0.55, 1.2, 1.1))
boulder(p, (1.9, -1.2, 0.0), 0.22, (0.7, 1.0, 0.9), "mine_rock_rust")
boulder(p, (-1.0, 0.68, 0.0), 0.4, (0.75, 0.8, 1.6), "mine_rock")
boulder(p, (-0.98, 0.72, 1.0), 0.36, (0.8, 0.8, 1.4), "mine_rock3")
boulder(p, (-1.0, 0.8, 1.9), 0.34, (0.9, 0.8, 1.1))
boulder(p, (-1.95, 0.6, 0.0), 0.3, (0.45, 1.6, 1.6), "mine_rock2")
boulder(p, (-1.95, 0.8, 0.9), 0.3, (0.45, 1.4, 1.5))
boulder(p, (-1.93, -0.5, 0.0), 0.28, (0.5, 1.2, 1.2), "mine_rock3")
boulder(p, (-1.9, -1.2, 0.0), 0.2, (0.7, 1.2, 0.9))
# Loose blocks at the foot of the collar.
for x, y, r in ((0.98, 0.1, 0.2), (-0.98, 0.12, 0.17), (1.1, -0.2, 0.11), (-1.75, -0.05, 0.14)):
    boulder(p, (x, y, 0.0), r, (1.1, 1.0, 1.0))
rock = finish(p, "rock", T((0, 0, 0)), root)

# ---------------------------------------------------------------- the portal: a plated steel frame round the mouth
p = Part()
hw = PORTAL_W / 2
# The tunnel: a dark box set back into the rock, with ribs of lining just inside the mouth.
p.box("mine_black", (0, PORTAL_Y + 0.8, PORTAL_H / 2 + 0.02), (PORTAL_W + 0.1, 1.1, PORTAL_H + 0.04))
for k, y in enumerate((PORTAL_Y + 0.34, PORTAL_Y + 0.52)):
    for side in (-1, 1):
        p.box("mine_plate2", (side * (hw - 0.03 - 0.03 * k), y, PORTAL_H / 2), (0.07, 0.07, PORTAL_H))
    p.box("mine_plate2", (0, y, PORTAL_H - 0.03 - 0.03 * k), (PORTAL_W, 0.07, 0.07))
# Two piers and a deep lintel, with canted corners.
for side in (-1, 1):
    x = side * (hw + 0.17)
    p.box("mine_gunmetal", (x, PORTAL_Y + 0.17, PORTAL_H / 2), (0.34, 0.36, PORTAL_H), bevel=0.02)
    p.box("mine_concrete", (x, PORTAL_Y + 0.12, 0.2), (0.46, 0.5, 0.4), bevel=0.03)                     # footing
    p.box("mine_concrete2", (x, PORTAL_Y + 0.0, 0.52), (0.4, 0.22, 0.3), rot_x(radians(-22)), 0.02)       # its sloped cap
    plates(p, (x - 0.17, PORTAL_Y - 0.001, 0.45), X, Z, -Y, 0.0, 0.34, 0.0, PORTAL_H - 0.45, 1, 3, rust=0.5, gap=0.04)
    p.add(mk_prism([(0.0, 0.0), (0.26, 0.0), (0.0, -0.26)], (side * hw, PORTAL_Y + 0.02, PORTAL_H), -side * X, Z, 0.0, side * 0.3), "mine_steel", True)   # corner gusset
    # A banner hung on each pier: plain, as the mine is shared.
    p.box("mine_steel", (x, PORTAL_Y - 0.08, 1.56), (0.36, 0.035, 0.035))
    p.box("mine_banner", (x, PORTAL_Y - 0.085, 1.16), (0.28, 0.014, 0.78))
    p.box("mine_banner_mark", (x, PORTAL_Y - 0.094, 1.2), (0.13, 0.004, 0.13), rot_y(radians(45)))
p.box("mine_gunmetal", (0, PORTAL_Y + 0.17, PORTAL_H + 0.21), (PORTAL_W + 0.9, 0.42, 0.42), bevel=0.03)
plates(p, (-hw - 0.4, PORTAL_Y - 0.04, PORTAL_H + 0.02), X, Z, -Y, 0.0, PORTAL_W + 0.8, 0.0, 0.38, 4, 1, rust=0.6, gap=0.04)
p.box("mine_steel", (0, PORTAL_Y + 0.17, PORTAL_H + 0.45), (PORTAL_W + 1.0, 0.5, 0.06), bevel=0.01)       # the cap plate
hazard(p, (-hw, PORTAL_Y - 0.045, PORTAL_H), X, -Z, -Y, PORTAL_W, 0.07, 0.09)
# A railing along the top.
for k in range(5):
    x = -hw - 0.35 + k * (PORTAL_W + 0.7) / 4
    p.cyl("mine_hazard", (x, PORTAL_Y - 0.02, PORTAL_H + 0.48), (x, PORTAL_Y - 0.02, PORTAL_H + 0.78), 0.016, seg=6)
p.box("mine_hazard", (0, PORTAL_Y - 0.02, PORTAL_H + 0.78), (PORTAL_W + 0.74, 0.03, 0.03))
p.box("mine_hazard", (0, PORTAL_Y - 0.02, PORTAL_H + 0.63), (PORTAL_W + 0.74, 0.02, 0.02))
portal = finish(p, "portal", T((0, PORTAL_Y - 0.1, 0)), root)

# The lamps: over the mouth, down both sides of it and in the tunnel. One object, so a worked-out mine goes dark.
p = Part()
p.box("mine_lamp", (0, PORTAL_Y - 0.05, PORTAL_H + 0.25), (0.42, 0.03, 0.1), bevel=0.01)
p.box("mine_lamp", (0, PORTAL_Y + 0.45, PORTAL_H - 0.12), (0.3, 0.05, 0.05))
for side in (-1, 1):
    p.box("mine_lamp", (side * (hw - 0.085), PORTAL_Y + 0.2, 1.05), (0.03, 0.06, 0.16), bevel=0.008)
    p.box("mine_lamp", (side * (hw - 0.12), PORTAL_Y + 0.6, 1.2), (0.03, 0.05, 0.12))
    p.box("mine_lamp", (side * (hw + 0.17), PORTAL_Y - 0.01, 0.78), (0.1, 0.03, 0.06), bevel=0.008)
lamps = finish(p, "lamps", T((0, PORTAL_Y, PORTAL_H)), root)

# ---------------------------------------------------------------- the ore cart
p = Part()
c0 = CART_REST
wall = [V((sx * hx, sy * hy, z)) for z, hx, hy in ((0.3, 0.22, 0.34), (0.68, 0.3, 0.42)) for sx, sy in ((-1, -1), (1, -1), (1, 1), (-1, 1))]
p.add(mk_loft([[c0 + v for v in wall[:4]], [c0 + v for v in wall[4:]]]), "mine_gunmetal", True)
p.box("mine_black", c0 + V((0, 0, 0.675)), (0.52, 0.76, 0.012))                                  # the dark inside
p.box("mine_steel", c0 + V((0, 0, 0.69)), (0.66, 0.9, 0.035), bevel=0.008)                        # rim
p.box("mine_black", c0 + V((0, 0, 0.694)), (0.54, 0.78, 0.036))
for sy in (-1, 1):
    p.box("mine_rust", c0 + V((0, sy * 0.385, 0.5)), (0.36, 0.01, 0.2), rot_x(sy * radians(-12)))
p.box("mine_steel", c0 + V((0, 0, 0.27)), (0.5, 0.78, 0.06), bevel=0.008)                         # the frame
for sy in (-1, 1):
    p.box("mine_plate2", c0 + V((0, sy * 0.46, 0.27)), (0.16, 0.1, 0.07))                         # couplings
    p.cyl("mine_steel", c0 + V((-RAIL_X - 0.03, sy * 0.24, 0.24)), c0 + V((RAIL_X + 0.03, sy * 0.24, 0.24)), 0.022, seg=6)
    for sx in (-1, 1):
        p.cyl("mine_black", c0 + V((sx * (RAIL_X - 0.025), sy * 0.24, 0.24)), c0 + V((sx * (RAIL_X + 0.03), sy * 0.24, 0.24)), 0.095, seg=10)
        p.cyl("mine_steel", c0 + V((sx * (RAIL_X + 0.03), sy * 0.24, 0.24)), c0 + V((sx * (RAIL_X + 0.04), sy * 0.24, 0.24)), 0.05, seg=8)
cart = finish(p, "cart", T(c0), root)
p = Part()
for k in range(11):
    c = c0 + V((random.uniform(-0.17, 0.17), random.uniform(-0.28, 0.28), 0.7 + random.uniform(0.0, 0.07)))
    boulder(p, c, random.uniform(0.09, 0.14), (1, 1, 0.8), random.choice(("mine_ore", "mine_ore", "mine_ore2", "mine_copper")), rough=0.22)
cart_ore = finish(p, "cart_ore", T(c0 + V((0, 0, 0.66))), cart)

# ---------------------------------------------------------------- the hoist: a braced post, an arm, a wheel, a bucket
p = Part()
top = HOIST.z + 2.5
feet = [HOIST + V((sx * 0.17, sy * 0.17, 0.04)) for sx, sy in ((-1, -1), (1, -1), (1, 1), (-1, 1))]
heads = [HOIST + V((sx * 0.09, sy * 0.09, top)) for sx, sy in ((-1, -1), (1, -1), (1, 1), (-1, 1))]
p.box("mine_concrete", HOIST + V((0, 0, 0.06)), (0.56, 0.56, 0.12), bevel=0.02)
for a, b in zip(feet, heads):
    p.beam("mine_steel", a, b, 0.05, 0.05, 0.006)
levels = [0.04, 0.85, 1.65, top]
for face in range(4):
    for z0, z1 in zip(levels, levels[1:]):
        k0, k1 = (z0 - 0.04) / (top - 0.04), (z1 - 0.04) / (top - 0.04)
        a, b = feet[face].lerp(heads[face], k0), feet[(face + 1) % 4].lerp(heads[(face + 1) % 4], k0)
        c, d = feet[face].lerp(heads[face], k1), feet[(face + 1) % 4].lerp(heads[(face + 1) % 4], k1)
        p.add(mk_cyl(a, d, 0.014, seg=5), "mine_rust")
        p.add(mk_cyl(b, c, 0.014, seg=5), "mine_rust")
        p.add(mk_cyl(c, d, 0.02, seg=5), "mine_steel")
p.box("mine_gunmetal", HOIST + V((0, 0, top + 0.04)), (0.3, 0.3, 0.08), bevel=0.01)
# The arm out over the bin, its stay behind, and the cheeks that carry the wheel.
head = HOIST + V((0, 0, top + 0.06))
p.beam("mine_hazard", head + V((0, 0.12, 0)), JIB + V((0, -0.06, 0.02)), 0.09, 0.1, 0.01)
p.beam("mine_steel", HOIST + V((0, 0.02, 1.7)), JIB + V((0, 0.34, -0.06)), 0.04, 0.04)
p.beam("mine_steel", head + V((0, 0.1, 0.04)), head + V((0, 0.52, 0.3)), 0.05, 0.05)
p.add(mk_cyl(head + V((0, 0.5, 0.28)), HOIST + V((0, 0.62, 0.1)), 0.012, seg=5), "mine_black")          # back stay
p.box("mine_concrete2", HOIST + V((0, 0.62, 0.07)), (0.2, 0.2, 0.14), bevel=0.015)
for sx in (-1, 1):
    p.box("mine_gunmetal", JIB + V((sx * 0.06, -0.02, 0.0)), (0.02, 0.2, 0.26), bevel=0.006)
# A ladder up the post's front.
for sx in (-1, 1):
    p.add(mk_cyl(HOIST + V((sx * 0.1, -0.2, 0.1)), HOIST + V((sx * 0.1, -0.125, 2.0)), 0.012, seg=5), "mine_hazard")
for k in range(8):
    z = 0.3 + k * 0.23
    yy = -0.2 + (z - 0.1) / 1.9 * 0.075
    p.add(mk_cyl(HOIST + V((-0.1, yy, z)), HOIST + V((0.1, yy, z)), 0.01, seg=5), "mine_hazard")
hoist = finish(p, "hoist", T(HOIST), root)

p = Part()
p.add(mk_cyl(JIB - X * 0.035, JIB + X * 0.035, WHEEL_R + 0.02, seg=18), "mine_steel")
p.add(mk_cyl(JIB - X * 0.02, JIB + X * 0.02, WHEEL_R - 0.03, seg=18), "mine_black")
p.add(mk_cyl(JIB - X * 0.05, JIB + X * 0.05, 0.035, seg=8), "mine_copper")
for k in range(6):
    a = k * pi / 3
    p.add(mk_cyl(JIB - X * 0.037, JIB - X * 0.037 + V((0, cos(a), sin(a))) * (WHEEL_R - 0.01), 0.016, seg=5), "mine_hazard")
    p.add(mk_cyl(JIB + X * 0.037, JIB + X * 0.037 + V((0, cos(a), sin(a))) * (WHEEL_R - 0.01), 0.016, seg=5), "mine_hazard")
hoist_wheel = finish(p, "hoist_wheel", T(JIB), hoist)

ROPE_LEN = ROPE_TOP.z - BUCKET_TOP
p = Part()
p.add(mk_cyl(ROPE_TOP, ROPE_TOP - Z * ROPE_LEN, 0.012, seg=6), "mine_black")
hoist_rope = finish(p, "hoist_rope", T(ROPE_TOP), hoist)

p = Part()
b0 = V((ROPE_TOP.x, ROPE_TOP.y, BUCKET_TOP))
p.add(mk_cyl(b0, b0 - Z * 0.07, 0.03, 0.02, seg=6), "mine_steel")                                   # hook block
for sx in (-1, 1):                                                                                # the bail
    p.add(mk_cyl(b0 - Z * 0.06, b0 + V((sx * 0.2, 0, -0.26)), 0.011, seg=5), "mine_steel")
wall = [V((sx * hx, sy * hy, z)) for z, hx, hy in ((-0.58, 0.13, 0.13), (-0.26, 0.21, 0.19)) for sx, sy in ((-1, -1), (1, -1), (1, 1), (-1, 1))]
p.add(mk_loft([[b0 + v for v in wall[:4]], [b0 + v for v in wall[4:]]]), "mine_plate2", True)
p.box("mine_steel", b0 + V((0, 0, -0.255)), (0.46, 0.42, 0.03), bevel=0.006)
p.box("mine_black", b0 + V((0, 0, -0.252)), (0.38, 0.34, 0.031))
p.box("mine_rust", b0 + V((0, -0.166, -0.42)), (0.2, 0.008, 0.16), rot_x(radians(11)))
bucket = finish(p, "bucket", T(b0), hoist)
p = Part()
for k in range(6):
    boulder(p, b0 + V((random.uniform(-0.1, 0.1), random.uniform(-0.08, 0.08), -0.25 + random.uniform(0, 0.04))), random.uniform(0.07, 0.1), (1, 1, 0.8), random.choice(("mine_ore", "mine_ore2", "mine_copper")), rough=0.22)
bucket_ore = finish(p, "bucket_ore", T(b0 + V((0, 0, -0.27))), bucket)

# The ore bin under the hoist.
p = Part()
bin0 = V((ROPE_TOP.x, ROPE_TOP.y, 0.04))
p.box("mine_concrete2", bin0 + V((0, 0, 0.03)), (0.78, 0.74, 0.06), bevel=0.012)
for sx, sy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
    size = (0.03, 0.66, 0.36) if sx else (0.7, 0.03, 0.36)
    p.box("mine_gunmetal", bin0 + V((sx * 0.335, sy * 0.315, 0.24)), size, bevel=0.006)
plates(p, bin0 + V((-0.35, -0.331, 0.07)), X, Z, -Y, 0.0, 0.7, 0.0, 0.34, 2, 1, rust=0.7, gap=0.04)
for sx, sy in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
    p.box("mine_steel", bin0 + V((sx * 0.34, sy * 0.32, 0.25)), (0.06, 0.06, 0.4), bevel=0.008)
p.box("mine_black", bin0 + V((0, 0, 0.08)), (0.64, 0.6, 0.02))
ore_bin = finish(p, "ore_bin", T(bin0), root)
p = Part()
for k in range(12):
    boulder(p, bin0 + V((random.uniform(-0.22, 0.22), random.uniform(-0.2, 0.2), 0.12 + random.uniform(0, 0.16))), random.uniform(0.09, 0.13), (1, 1, 0.8), random.choice(("mine_ore", "mine_ore", "mine_ore2", "mine_copper")), rough=0.22)
bin_ore = finish(p, "bin_ore", T(bin0 + V((0, 0, 0.08))), ore_bin)

# ---------------------------------------------------------------- the winch house on its trestle, up the left shoulder
p = Part()
x0, x1, y0, y1, zd = DECK
cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
posts = [(x0 + 0.07, y0 + 0.07), (x1 - 0.07, y0 + 0.07), (x1 - 0.07, y1 - 0.07), (x0 + 0.07, y1 - 0.07)]
for x, y in posts:
    p.box("mine_wood", (x, y, zd / 2), (0.1, 0.1, zd), bevel=0.008)
    p.box("mine_concrete2", (x, y, 0.07), (0.2, 0.2, 0.1), bevel=0.012)
for k in range(4):                      # braces on each face
    (ax, ay), (bx, by) = posts[k], posts[(k + 1) % 4]
    for z0, z1 in ((0.2, zd - 0.12), (zd - 0.12, 0.2)):
        p.add(mk_cyl((ax, ay, z0), (bx, by, z1), 0.028, seg=5), "mine_wood2")
    p.add(mk_cyl((ax, ay, zd - 0.08), (bx, by, zd - 0.08), 0.04, seg=5), "mine_wood")
for k in range(7):                      # deck planks
    y = y0 + 0.02 + (k + 0.5) * (y1 - y0 - 0.04) / 7
    p.box("mine_wood2" if k % 3 == 0 else "mine_wood", (cx, y, zd + 0.02), (x1 - x0 + 0.08, (y1 - y0) / 7 - 0.012, 0.04))
# The house: plated walls, a low pitched roof, a stack.
hx0, hx1, hy0, hy1, hh = x0 + 0.08, x1 - 0.06, y0 + 0.22, y1 - 0.04, 0.62
hcx, hcy = (hx0 + hx1) / 2, (hy0 + hy1) / 2
p.box("mine_gunmetal", (hcx, hcy, zd + 0.04 + hh / 2), (hx1 - hx0, hy1 - hy0, hh), bevel=0.015)
plates(p, (hx0, hy0 - 0.001, zd + 0.04), X, Z, -Y, 0.0, hx1 - hx0, 0.0, hh, 3, 1, rust=0.6, gap=0.035)
plates(p, (hx1 + 0.001, hy0, zd + 0.04), Y, Z, X, 0.0, hy1 - hy0, 0.0, hh, 2, 1, rust=0.6, gap=0.035)
p.box("mine_plate2", (hcx, hcy - 0.02, zd + 0.04 + hh + 0.035), (hx1 - hx0 + 0.1, hy1 - hy0 + 0.1, 0.05), rot_x(radians(-5)), 0.01)
p.cyl("mine_plate2", (hcx - 0.18, hcy + 0.08, zd + hh), (hcx - 0.18, hcy + 0.08, zd + hh + 0.55), 0.07, seg=10)
p.cyl("mine_steel", (hcx - 0.18, hcy + 0.08, zd + hh + 0.5), (hcx - 0.18, hcy + 0.08, zd + hh + 0.58), 0.09, seg=10)
STACK = V((hcx - 0.18, hcy + 0.08, zd + hh + 0.62))
# A railing round the deck's open front, and a ladder down it.
for x in (x0 + 0.02, cx, x1 - 0.02):
    p.cyl("mine_hazard", (x, y0 + 0.02, zd + 0.04), (x, y0 + 0.02, zd + 0.42), 0.016, seg=6)
p.box("mine_hazard", (cx, y0 + 0.02, zd + 0.42), (x1 - x0, 0.03, 0.03))
p.box("mine_hazard", (cx, y0 + 0.02, zd + 0.24), (x1 - x0, 0.02, 0.02))
for sx in (-1, 1):
    p.add(mk_cyl((x1 - 0.22 + sx * 0.09, y0 - 0.05, 0.08), (x1 - 0.22 + sx * 0.09, y0 - 0.02, zd + 0.3), 0.012, seg=5), "mine_hazard")
for k in range(6):
    z = 0.26 + k * 0.22
    p.add(mk_cyl((x1 - 0.31, y0 - 0.045, z), (x1 - 0.13, y0 - 0.045, z), 0.01, seg=5), "mine_hazard")
winch_house = finish(p, "winch_house", T((cx, cy, 0)), root)

# Its windows: lit while the mine has iron.
p = Part()
for k in range(3):
    p.box("mine_red", (hx0 + 0.16 + k * 0.2, hy0 - 0.02, zd + 0.04 + hh * 0.62), (0.13, 0.03, 0.09), bevel=0.008)
for k in range(2):
    p.box("mine_red", (hx1 + 0.02, hy0 + 0.14 + k * 0.2, zd + 0.04 + hh * 0.62), (0.03, 0.13, 0.09), bevel=0.008)
p.box("mine_lamp", (x1 - 0.04, y0 + 0.1, 0.72), (0.05, 0.05, 0.1), bevel=0.01)                          # a lamp on the trestle
windows = finish(p, "windows", T((hcx, hy0, zd + hh * 0.62)), root)

# Smoke from the stack.
SMOKE = []
for k in range(3):
    p = Part()
    p.add(mk_ico(STACK, 0.11, (1, 1, 1), rot_z(k * 1.3), 1), "mine_dust", False)
    SMOKE.append(finish(p, "smoke_%d" % (k + 1), T(STACK), root))

# ---------------------------------------------------------------- two tanks at the foot of the trestle
p = Part()
for k, (x, r, h) in enumerate(((-1.62, 0.2, 1.08), (-1.2, 0.2, 1.18))):
    y = -0.5
    p.box("mine_concrete2", (x, y, 0.07), (0.5, 0.5, 0.1), bevel=0.012)
    p.cyl("mine_steel", (x, y, 0.1), (x, y, h), r, seg=14)
    p.sphere("mine_steel", (x, y, h), r, (1, 1, 0.42), 14, 6)
    p.cyl("mine_plate2", (x, y, h + r * 0.38), (x, y, h + r * 0.38 + 0.1), 0.07, seg=8)
    for z in (0.34, 0.66, 0.96):
        p.cyl("mine_rust", (x, y, z), (x, y, z + 0.035), r + 0.012, seg=14)
p.add(mk_tube([V((-1.62, -0.5, 0.86)), V((-1.62, -0.24, 0.86)), V((-1.62, -0.24, 0.3)), V((-1.5, 0.05, 0.3))], 0.025, 6, 0.04), "mine_copper")
tanks = finish(p, "tanks", T((-1.41, -0.5, 0)), root)

# ---------------------------------------------------------------- report
tris = 0
lo, hi = V((9, 9, 9)), V((-9, -9, -9))
for o in COLL.objects:
    if o.type == 'MESH':
        o.data.calc_loop_triangles()
        tris += len(o.data.loop_triangles)
        print("PART %-12s %5d triangles, lowest %.2f" % (o.name, len(o.data.loop_triangles), min((o.matrix_world @ v.co).z for v in o.data.vertices)))
        for v in o.data.vertices:
            w = o.matrix_world @ v.co
            lo = V((min(lo.x, w.x), min(lo.y, w.y), min(lo.z, w.z)))
            hi = V((max(hi.x, w.x), max(hi.y, w.y), max(hi.z, w.z)))
print("TRIS total", tris)
print("BOUNDS", [round(v, 3) for v in lo], [round(v, 3) for v in hi])
bpy.context.view_layer.update()

# ================================================================= animation
exec(shared("animate_mine.py", "ROOT_PARTS = ["))
ROOT_PARTS = ["floor", "rock", "portal", "lamps", "cart", "hoist", "ore_bin", "winch_house", "windows", "tanks"]
CHILDREN = ["cart_ore", "hoist_wheel", "hoist_rope", "bucket", "bucket_ore", "bin_ore"]
PUFFS = ["smoke_1", "smoke_2", "smoke_3"]
EVERY = ROOT_PARTS + CHILDREN + PUFFS


def clip(name, frames, moves):
    """Keys every part through a clip: the ones named in moves by their function, the rest at home."""
    for part in EVERY:
        bake(OB[part], name, frames, moves.get(part, lambda t, part=part: HOME[part]))


def rope(d):
    return HOME["hoist_rope"] @ Sc((1, 1, (ROPE_LEN + d) / ROPE_LEN))


def wheel(d):
    return HOME["hoist_wheel"] @ Rx(-d / WHEEL_R)


def lowered(d, sway=0.0):
    M = Tm(-Z * d) @ HOME["bucket"]
    return about(HOME["hoist_rope"].translation, Rx(sway)) @ M if sway else M


def scaled(name, s):
    return HOME[name] @ Sc(ONE * max(s, 0.001))


def flicker(t, w):
    return 1.0 + 0.04 * sin(7 * w * t) + 0.025 * sin(13 * w * t + 1.0)


def puff(i, period, strength):
    """Smoke: each puff leaves the stack, rises, swells and thins away, one after another."""
    def fn(t):
        k = ((t / period) + i / 3.0) % 1.0
        size = strength * (0.45 + 1.5 * k) * (1.0 - sm(max(0.0, (k - 0.55) / 0.45)))
        drift = V((0.18 * k * k, 0.05 * sin(k * 5 + i), 0.9 * k))
        return Tm(drift) @ HOME["smoke_%d" % (i + 1)] @ Sc(ONE * max(size, 0.001))
    return fn


# ----------------------------------------------------------------- Idle (loops): lamps lit, a wisp of smoke
IDLE_FRAMES = 96
IDLE_T = IDLE_FRAMES / FPS
WI = 2 * pi / IDLE_T
idle = {"lamps": lambda t: scaled("lamps", flicker(t, WI)),
        "bucket": lambda t: lowered(0.0, radians(1.5) * sin(WI * t)),
        "hoist_rope": lambda t: about(HOME["hoist_rope"].translation, Rx(radians(1.5) * sin(WI * t))) @ rope(0.0),
        "bucket_ore": lambda t: hidden("bucket_ore")}
for i, name in enumerate(PUFFS):
    idle[name] = puff(i, IDLE_T, 0.55)
clip("Idle", IDLE_FRAMES, idle)

# ----------------------------------------------------------------- Work (loops): the cart runs in and comes out loaded
# The loop starts and ends as Idle stands: the cart loaded outside the mouth, the bucket raised and empty.
WORK_FRAMES = 96
WORK_T = WORK_FRAMES / FPS
WW = 2 * pi / WORK_T


def cart_run(t):
    return ramp(t, 0.55, 1.7) - ramp(t, 2.45, 3.6)


def cart_load(t):
    # Emptied before it goes in; loaded again while it is out of sight.
    return 1.0 - ramp(t, 0.05, 0.5) + ramp(t, 1.85, 2.3)


def bucket_depth(t):
    return BUCKET_DROP * (ramp(t, 0.5, 1.4) - ramp(t, 1.9, 2.9))


def bucket_load(t):
    return ramp(t, 1.5, 1.8) - ramp(t, 3.2, 3.6)


def bin_level(t):
    return 1.0 + 0.16 * sin(pi * lin(t, 0.1, 0.6)) - 0.22 * (ramp(t, 1.45, 1.8) - ramp(t, 3.2, 3.7))


work = {"cart": lambda t: Tm(Y * CART_IN * cart_run(t)) @ HOME["cart"] @ Rx(radians(0.8) * sin(31 * t) * (1 if 0.55 < t < 3.6 else 0)),
        "cart_ore": lambda t: scaled("cart_ore", cart_load(t)),
        "bucket": lambda t: lowered(bucket_depth(t)),
        "hoist_rope": lambda t: rope(bucket_depth(t)),
        "hoist_wheel": lambda t: wheel(bucket_depth(t)),
        "bucket_ore": lambda t: scaled("bucket_ore", bucket_load(t)),
        "bin_ore": lambda t: scaled("bin_ore", bin_level(t)),
        "lamps": lambda t: scaled("lamps", flicker(t, WW))}
for i, name in enumerate(PUFFS):
    work[name] = puff(i, WORK_T / 2, 1.0)
clip("Work", WORK_FRAMES, work)

# ----------------------------------------------------------------- Depleted (loops): worked out, dark, empty
DEP_FRAMES = 96
DEP_T = DEP_FRAMES / FPS
WD = 2 * pi / DEP_T
dep = {"lamps": lambda t: hidden("lamps"), "windows": lambda t: hidden("windows"),
       "cart_ore": lambda t: hidden("cart_ore"), "bin_ore": lambda t: hidden("bin_ore"), "bucket_ore": lambda t: hidden("bucket_ore"),
       "bucket": lambda t: lowered(0.45, radians(2.0) * sin(WD * t)),
       "hoist_rope": lambda t: about(HOME["hoist_rope"].translation, Rx(radians(2.0) * sin(WD * t))) @ rope(0.45),
       "hoist_wheel": lambda t: wheel(0.45)}
for name in PUFFS:
    dep[name] = lambda t, name=name: hidden(name)
clip("Depleted", DEP_FRAMES, dep)

# ----------------------------------------------------------------- Build: scrubbed by construction progress
BUILD_FRAMES = 240
BUILD_T = BUILD_FRAMES / FPS


def grow(name, a, b):
    def fn(t):
        k = lin(t / BUILD_T, a, b)
        return hidden(name) if k <= 0 else HOME[name] @ Sc((1, 1, max(sm(k), 0.001)))
    return fn


def pop(name, a, b):
    def fn(t):
        k = lin(t / BUILD_T, a, b)
        if k <= 0:
            return hidden(name)
        return HOME[name] @ Sc(ONE * (sm(k / 0.6) * 1.06 if k < 0.6 else 1 + 0.06 * (1 - (k - 0.6) / 0.4)))
    return fn


build = {"floor": pop("floor", 0.0, 0.08), "rock": grow("rock", 0.04, 0.26), "portal": grow("portal", 0.22, 0.46),
         "winch_house": grow("winch_house", 0.42, 0.62), "tanks": grow("tanks", 0.5, 0.64), "hoist": grow("hoist", 0.6, 0.78),
         "hoist_wheel": pop("hoist_wheel", 0.76, 0.81), "hoist_rope": grow("hoist_rope", 0.8, 0.85), "bucket": pop("bucket", 0.84, 0.88),
         "ore_bin": pop("ore_bin", 0.7, 0.77), "bin_ore": pop("bin_ore", 0.93, 0.97), "cart": pop("cart", 0.87, 0.92),
         "cart_ore": pop("cart_ore", 0.93, 0.97), "lamps": pop("lamps", 0.96, 1.0), "windows": pop("windows", 0.96, 1.0),
         "bucket_ore": lambda t: hidden("bucket_ore")}
for name in PUFFS:
    build[name] = lambda t, name=name: hidden(name)
clip("Build", BUILD_FRAMES, build)

# ----------------------------------------------------------------- Die: the works fall in and the wreck sinks
DIE_FRAMES = 120
DIE_T = DIE_FRAMES / FPS


def sink(t):
    return Tm(-Z * 5.2 * ramp(t, 3.6, 5.0) ** 1.4)


def shake(t, amp, phase):
    k = (1 - lin(t, 0.0, 1.4)) * amp
    return Tm(V((sin(41 * t + phase), sin(37 * t + 1.3 * phase), 0)) * k)


def accel(x):
    x = max(0.0, min(1.0, x))
    return x * x


def fall(name, pivot, turn, t0, t1, phase, drop=0.0):
    """Shakes, then goes over about a point on the ground, then sinks with the rest."""
    def fn(t):
        k = accel(lin(t, t0, t1))
        bounce = 0.06 * sin(pi * lin(t, t1, t1 + 0.35)) * (1 if t > t1 else 0)
        return sink(t) @ shake(t, 0.02, phase) @ Tm(-Z * drop * k) @ about(pivot, turn(k * (1 - bounce))) @ HOME[name]
    return fn


def cart_die(t):
    run = accel(lin(t, 0.5, 1.6))
    over = accel(lin(t, 1.5, 2.1))
    M = Tm(-Y * 1.9 * run) @ HOME["cart"]
    return sink(t) @ about(M.translation + V((-0.3, 0, 0.12)), Ry(radians(-96) * over)) @ M


die = {"floor": lambda t: sink(t) @ shake(t, 0.008, 0.3) @ HOME["floor"],
       "rock": lambda t: sink(t) @ shake(t, 0.015, 1.1) @ HOME["rock"],
       "portal": fall("portal", V((0, PORTAL_Y - 0.1, 0)), lambda k: Rx(radians(74) * k), 0.7, 1.9, 0.7, drop=0.1),
       "lamps": lambda t: hidden("lamps") if t > 0.35 else scaled("lamps", 1.0 + 0.5 * sin(60 * t)),
       "windows": lambda t: hidden("windows") if t > 0.5 else HOME["windows"],
       "hoist": fall("hoist", HOIST + V((0, -0.17, 0)), lambda k: Rx(radians(88) * k), 0.9, 2.0, 2.0),
       "winch_house": fall("winch_house", V((DECK[1], (DECK[2] + DECK[3]) / 2, 0)), lambda k: Ry(radians(58) * k), 1.1, 2.3, 2.9, drop=0.5),
       "tanks": fall("tanks", V((-1.41, -0.7, 0)), lambda k: Rx(radians(82) * k), 1.3, 2.2, 3.7),
       "ore_bin": lambda t: sink(t) @ shake(t, 0.03, 4.4) @ HOME["ore_bin"],
       "cart": cart_die,
       "cart_ore": lambda t: scaled("cart_ore", 1.0 - ramp(t, 1.5, 2.0)),
       "bucket": lambda t: Tm(-Z * 1.4 * accel(lin(t, 0.4, 0.9))) @ HOME["bucket"],
       "hoist_rope": lambda t: hidden("hoist_rope") if t > 0.4 else HOME["hoist_rope"],
       "bucket_ore": lambda t: hidden("bucket_ore")}
for name in PUFFS:
    die[name] = lambda t, name=name: hidden(name)
clip("Die", DIE_FRAMES, die)
print("CLIPS Idle", IDLE_FRAMES, "Work", WORK_FRAMES, "Depleted", DEP_FRAMES, "Build", BUILD_FRAMES, "Die", DIE_FRAMES)

# ================================================================= a review picture, the file and the game model
scene.frame_set(0)


def review():
    os.makedirs(os.path.dirname(PREVIEW), exist_ok=True)
    cam = bpy.data.objects.new("review_camera", bpy.data.cameras.new("review_camera"))
    scene.collection.objects.link(cam)
    scene.camera = cam
    cam.data.type = 'ORTHO'
    cam.data.ortho_scale = 7.6
    # The game's view: from the south, looking down at 50 degrees.
    pitch = radians(50)
    cam.location = (0, -30 * cos(pitch) - 0.6, 30 * sin(pitch) + 1.2)
    cam.rotation_euler = (radians(90) - pitch, 0, 0)
    scene.render.engine = 'BLENDER_WORKBENCH'
    scene.display.shading.light = 'STUDIO'
    scene.display.shading.color_type = 'MATERIAL'
    scene.display.shading.show_shadows = True
    scene.display.shading.shadow_intensity = 0.4
    scene.display.shading.show_cavity = True
    scene.view_settings.view_transform = 'Standard'
    scene.world = bpy.data.worlds.new("review")
    scene.world.color = (0.2, 0.24, 0.14)
    scene.render.film_transparent = False
    scene.render.resolution_x, scene.render.resolution_y = 1400, 1000
    scene.render.filepath = PREVIEW
    bpy.ops.render.render(write_still=True)
    bpy.data.objects.remove(cam)


review()
bpy.context.preferences.filepaths.save_version = 0
bpy.ops.wm.save_as_mainfile(filepath=OUT, compress=True)
print("SAVED", OUT)

bpy.ops.object.select_all(action='DESELECT')
objects = list(COLL.all_objects)
for ob in objects:
    ob.hide_set(False)
    ob.select_set(True)
bpy.context.view_layer.objects.active = objects[0]
os.makedirs(os.path.dirname(GLB), exist_ok=True)
bpy.ops.export_scene.gltf(filepath=GLB, export_format='GLB', use_selection=True, export_yup=True,
                          export_apply=True, export_cameras=False, export_lights=False, export_extras=False,
                          export_animations=True, export_animation_mode='NLA_TRACKS',
                          export_force_sampling=True, export_optimize_animation_size=False,
                          export_optimize_animation_keep_anim_object=True)
print("EXPORTED", GLB, len(objects), "objects", os.path.getsize(GLB), "bytes")
