"""Builds IronMine.blend from nothing: the static pithead over a mine shaft.

Run in background Blender:
  blender --background --python build_mine.py

Everything is rebuilt each run, so edits here never compound. The front faces -Y, Z up, base on
Z = 0. Animation and effects are added afterwards by animate_mine.py. The game footprint is 2 x 2 m,
so everything stays within +-0.97 m of the centre. The mine is shared infrastructure, so it wears no
faction colours: weathered steel, concrete, rust and hazard paint. The helpers are the Barracks' own
(Blender/Buildings/Barracks/build/build_barracks.py), so the buildings share one look.
"""
import bpy, bmesh, math, os, random
from math import sin, cos, radians, pi
from mathutils import Vector as V, Matrix

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.normpath(os.path.join(HERE, "..", "IronMine.blend"))
X, Y, Z = V((1, 0, 0)), V((0, 1, 0)), V((0, 0, 1))
random.seed(17)

bpy.ops.wm.read_factory_settings(use_empty=True)

# ---------------------------------------------------------------- materials (flat PBR, linear colour)
MATS = {}


def material(name, col, met, rough, emis=None, strength=0.0, alpha=1.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = next(n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    b.inputs["Base Color"].default_value = (*col, 1)
    b.inputs["Metallic"].default_value = met
    b.inputs["Roughness"].default_value = rough
    if emis:
        b.inputs["Emission Color"].default_value = (*emis, 1)
        b.inputs["Emission Strength"].default_value = strength
    if alpha < 1.0:
        b.inputs["Alpha"].default_value = alpha
        try:
            m.surface_render_method = 'BLENDED'
        except Exception:
            m.blend_method = 'BLEND'
    m.diffuse_color = (*col, alpha)
    MATS[name] = m
    return m

material("mine_concrete", (0.26, 0.25, 0.23), 0.0, 0.9)
material("mine_concrete2", (0.20, 0.195, 0.18), 0.0, 0.9)
material("mine_stain", (0.10, 0.075, 0.055), 0.0, 0.95)
material("mine_gunmetal", (0.10, 0.095, 0.088), 0.45, 0.55)
material("mine_plate2", (0.12, 0.11, 0.098), 0.45, 0.58)
material("mine_steel", (0.21, 0.20, 0.19), 0.55, 0.5)
material("mine_rust", (0.15, 0.058, 0.024), 0.2, 0.85)
material("mine_copper", (0.44, 0.185, 0.075), 0.70, 0.38)
material("mine_black", (0.020, 0.020, 0.022), 0.10, 0.70)
material("mine_hazard", (0.62, 0.42, 0.035), 0.05, 0.60)
material("mine_wood", (0.15, 0.095, 0.05), 0.0, 0.85)
material("mine_wood2", (0.10, 0.06, 0.03), 0.0, 0.9)
material("mine_ore", (0.22, 0.07, 0.035), 0.35, 0.55)        # iron ore: rust red with a dull sheen
material("mine_ore2", (0.12, 0.05, 0.035), 0.25, 0.7)
material("mine_lamp", (0.6, 0.45, 0.2), 0.0, 0.4, (1.0, 0.72, 0.35), 3.0)
material("mine_red", (0.30, 0.02, 0.01), 0.0, 0.5, (1.0, 0.08, 0.03), 2.5)
material("mine_dust", (0.30, 0.20, 0.15), 0.0, 0.95, alpha=0.75)


# ---------------------------------------------------------------- geometry helpers


def basis(x, y, z):
    m = Matrix.Identity(4)
    for i, a in enumerate((x, y, z)):
        m[0][i], m[1][i], m[2][i] = a.x, a.y, a.z
    return m


def rot_x(a):
    return Matrix.Rotation(a, 4, 'X')


def rot_y(a):
    return Matrix.Rotation(a, 4, 'Y')


def rot_z(a):
    return Matrix.Rotation(a, 4, 'Z')


def mk_box(c, size, rot=None, bevel=0.0):
    bm = bmesh.new()
    M = Matrix.Translation(V(c)) @ (rot if rot else Matrix.Identity(4)) @ Matrix.Diagonal((*size, 1))
    bmesh.ops.create_cube(bm, size=1.0, matrix=M)
    if bevel > 0:
        bmesh.ops.bevel(bm, geom=bm.edges[:], offset=bevel, segments=1, profile=0.5, affect='EDGES')
    return bm


def mk_cyl(p0, p1, r0, r1=None, seg=12, cap=True):
    p0, p1 = V(p0), V(p1)
    r1 = r0 if r1 is None else r1
    d = p1 - p0
    bm = bmesh.new()
    M = Matrix.Translation((p0 + p1) / 2) @ d.to_track_quat('Z', 'Y').to_matrix().to_4x4()
    bmesh.ops.create_cone(bm, cap_ends=cap, cap_tris=False, segments=seg, radius1=max(r0, 1e-4),
                          radius2=max(r1, 1e-4), depth=d.length, matrix=M)
    return bm


def mk_sphere(c, r=1.0, scale=(1, 1, 1), u=12, v=8, rot=None):
    bm = bmesh.new()
    M = Matrix.Translation(V(c)) @ (rot if rot else Matrix.Identity(4)) @ Matrix.Diagonal((*scale, 1))
    bmesh.ops.create_uvsphere(bm, u_segments=u, v_segments=v, radius=r, matrix=M)
    return bm


def mk_ico(c, r, scale=(1, 1, 1), rot=None, sub=1):
    bm = bmesh.new()
    M = Matrix.Translation(V(c)) @ (rot if rot else Matrix.Identity(4)) @ Matrix.Diagonal((*scale, 1))
    bmesh.ops.create_icosphere(bm, subdivisions=sub, radius=r, matrix=M)
    return bm


def mk_loft(rings, cap=True):
    bm = bmesh.new()
    vr = [[bm.verts.new(p) for p in ring] for ring in rings]
    n = len(rings[0])
    for k in range(len(vr) - 1):
        for i in range(n):
            j = (i + 1) % n
            bm.faces.new((vr[k][i], vr[k][j], vr[k + 1][j], vr[k + 1][i]))
    if cap:
        bm.faces.new(vr[0])
        bm.faces.new(vr[-1])
    return bm


def rrect(c, au, av, hu, hv, rc, cseg=3):
    c = V(c)
    rc = min(rc, hu, hv)
    pts = []
    for k, (sx, sy) in enumerate(((1, 1), (-1, 1), (-1, -1), (1, -1))):
        cx, cy = sx * (hu - rc), sy * (hv - rc)
        for j in range(cseg + 1):
            a = k * pi / 2 + (j / cseg) * pi / 2
            pts.append(c + au * (cx + rc * cos(a)) + av * (cy + rc * sin(a)))
    return pts


def mk_tube(pts, r, seg=8, fillet=0.0, cap=True):
    pts = [V(p) for p in pts]
    if fillet > 0 and len(pts) > 2:
        new = [pts[0]]
        for i in range(1, len(pts) - 1):
            p = pts[i]
            a, b = pts[i - 1] - p, pts[i + 1] - p
            f = min(fillet, a.length * 0.45, b.length * 0.45)
            pa, pb = p + a.normalized() * f, p + b.normalized() * f
            for k in range(5):
                t = k / 4
                new.append((1 - t) ** 2 * pa + 2 * t * (1 - t) * p + t * t * pb)
        new.append(pts[-1])
        pts = new
    n = len(pts)
    tang = [(pts[min(i + 1, n - 1)] - pts[max(i - 1, 0)]).normalized() for i in range(n)]
    nrm = tang[0].orthogonal().normalized()
    rings = []
    for i in range(n):
        if i > 0:
            nrm = tang[i - 1].rotation_difference(tang[i]) @ nrm
        b = tang[i].cross(nrm).normalized()
        nrm = b.cross(tang[i]).normalized()
        rr = r[i] if isinstance(r, (list, tuple)) else r
        rings.append([pts[i] + rr * (cos(2 * pi * k / seg) * nrm + sin(2 * pi * k / seg) * b)
                      for k in range(seg)])
    return mk_loft(rings, cap)


def mk_lathe(prof, origin, axis, seg=16, closed=False, a0=None, a1=None, ref=None):
    """prof: (radius, along-axis) pairs. closed: the profile is a loop. a0..a1: partial sweep."""
    origin, axis = V(origin), V(axis).normalized()
    u = (V(ref) - axis * V(ref).dot(axis)).normalized() if ref else axis.orthogonal().normalized()
    w = axis.cross(u)
    full = a0 is None
    steps = seg if full else seg + 1
    bm = bmesh.new()
    grid = []
    for i in range(steps):
        a = 2 * pi * i / seg if full else a0 + (a1 - a0) * i / seg
        d = u * cos(a) + w * sin(a)
        grid.append([bm.verts.new(origin + axis * h + d * max(r, 4e-4)) for r, h in prof])
    m = len(prof)
    for i in range(steps if full else steps - 1):
        i2 = (i + 1) % steps
        for j in range(m if closed else m - 1):
            j2 = (j + 1) % m
            bm.faces.new((grid[i][j], grid[i2][j], grid[i2][j2], grid[i][j2]))
    if full and not closed:
        bm.faces.new([g[0] for g in grid])
        bm.faces.new([g[-1] for g in grid])
    if not full:
        bm.faces.new(grid[0])
        bm.faces.new(grid[-1])
    return bm


def mk_prism(poly, origin, au, av, d0, d1):
    origin = V(origin)
    an = au.cross(av)
    bm = bmesh.new()
    lo = [bm.verts.new(origin + au * p[0] + av * p[1] + an * d0) for p in poly]
    hi = [bm.verts.new(origin + au * p[0] + av * p[1] + an * d1) for p in poly]
    n = len(poly)
    bm.faces.new(lo)
    bm.faces.new(hi)
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new((lo[i], lo[j], hi[j], hi[i]))
    return bm


def mk_arc_shell(c, r_in, th, w, a0, a1, steps, skirt=0.05, ch=0.012):
    """A mudguard: an arc about the X axis through c, angle 0 = +Y (rear), 90 = up."""
    c = V(c)
    prof = [(-w, r_in - skirt), (-w, r_in + th - ch), (-w + ch, r_in + th), (w - ch, r_in + th),
            (w, r_in + th - ch), (w, r_in - skirt), (w - th, r_in - skirt), (w - th, r_in),
            (-w + th, r_in), (-w + th, r_in - skirt)]
    rings = []
    for i in range(steps + 1):
        a = radians(a0 + (a1 - a0) * i / steps)
        rings.append([c + X * x + (Y * cos(a) + Z * sin(a)) * rho for x, rho in prof])
    return mk_loft(rings)


class Part:
    def __init__(self):
        self.bm = bmesh.new()
        self.slots = []

    def add(self, bm, mat, flat=False):
        if mat not in self.slots:
            self.slots.append(mat)
        i = self.slots.index(mat)
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
        for f in bm.faces:
            f.material_index = i
            f.smooth = not flat
        me = bpy.data.meshes.new("tmp")
        bm.to_mesh(me)
        bm.free()
        self.bm.from_mesh(me)
        bpy.data.meshes.remove(me)

    def box(self, mat, c, size, rot=None, bevel=0.0):
        self.add(mk_box(c, size, rot, bevel), mat)

    def cyl(self, mat, p0, p1, r0, r1=None, seg=12, flat=False):
        self.add(mk_cyl(p0, p1, r0, r1, seg), mat, flat)

    def sphere(self, mat, c, r=1.0, scale=(1, 1, 1), u=12, v=8, rot=None):
        self.add(mk_sphere(c, r, scale, u, v, rot), mat)

    def tube(self, mat, pts, r, seg=8, fillet=0.0):
        self.add(mk_tube(pts, r, seg, fillet), mat)

    def beam(self, mat, p0, p1, wx, h, bevel=0.0):
        p0, p1 = V(p0), V(p1)
        d = p1 - p0
        y = d.normalized()
        z = X.cross(y).normalized()
        self.add(mk_box((p0 + p1) / 2, (wx, d.length, h), basis(y.cross(z), y, z), bevel), mat)

    def rivet(self, pos, normal, r=0.03, mat="mine_steel"):
        pos, normal = V(pos), V(normal).normalized()
        self.add(mk_cyl(pos - normal * 0.003, pos + normal * r * 0.6, r, r * 0.55, 6), mat)


WORLD = {}
COLL = None


def place(ob, world, parent):
    COLL.objects.link(ob)
    ob.parent = parent
    ob.matrix_parent_inverse = Matrix.Identity(4)
    ob.matrix_basis = (WORLD[parent.name].inverted() if parent else Matrix.Identity(4)) @ world
    WORLD[ob.name] = world.copy()
    return ob


def finish(part, name, world, parent, sharp=radians(50), shift=None):
    bm = part.bm
    if shift is not None:
        bmesh.ops.translate(bm, vec=shift, verts=bm.verts)
    bm.normal_update()
    for e in bm.edges:
        if len(e.link_faces) == 2:
            e.smooth = e.calc_face_angle(0.0) < sharp
    bmesh.ops.transform(bm, matrix=world.inverted(), verts=bm.verts)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    for s in part.slots:
        me.materials.append(MATS[s])
    return place(bpy.data.objects.new(name, me), world, parent)


def empty(name, world, parent, size=0.15, kind='PLAIN_AXES'):
    ob = bpy.data.objects.new(name, None)
    ob.empty_display_size = size
    ob.empty_display_type = kind
    return place(ob, world, parent)


def T(p):
    return Matrix.Translation(V(p))



def chamfer_poly(hx, hy, ch):
    return [(hx, hy - ch), (hx - ch, hy), (-hx + ch, hy), (-hx, hy - ch),
            (-hx, -hy + ch), (-hx + ch, -hy), (hx - ch, -hy), (hx, -hy + ch)]


def plate_box(part, mat, c, au, av, n, w, h, d, bevel=0.012):
    part.add(mk_box(c, (w, h, d), basis(au, av, n), bevel), mat, True)


def plates(part, o, au, av, n, u0, u1, v0, v1, cols, rows, mat="mine_gunmetal", rust=0.35, gap=0.06):
    """Raised riveted plates on a face. o lies on the face; au, av span it; n points out."""
    o, au, av, n = V(o), V(au), V(av), V(n)
    w, h = (u1 - u0) / cols, (v1 - v0) / rows
    for i in range(cols):
        for j in range(rows):
            c = o + au * (u0 + (i + 0.5) * w) + av * (v0 + (j + 0.5) * h)
            m = mat if mat != "mine_gunmetal" or random.random() < 0.6 else "mine_plate2"
            plate_box(part, m, c + n * 0.02, au, av, n, w - gap, h - gap, 0.04)
            hw, hh = w / 2 - gap / 2 - 0.07, h / 2 - gap / 2 - 0.07
            for su, sv in ((-1, -1), (1, -1), (-1, 1), (1, 1), (0, 1), (0, -1)):
                part.rivet(c + n * 0.04 + au * (su * hw) + av * (sv * hh), n, 0.025)
            if random.random() < rust:
                rw, rh = w * random.uniform(0.3, 0.75), h * random.uniform(0.2, 0.45)
                rc = c + au * random.uniform(-0.2, 0.2) * w + av * (-h / 2 + gap / 2 + rh / 2 + 0.03)
                plate_box(part, "mine_rust", rc + n * 0.042, au, av, n, rw, rh, 0.006, 0.0)


def hazard(part, o, au, av, n, length, width, stripe=0.17):
    """Black and yellow slanted stripes along au, width along av, laid on a face with normal n."""
    o, au, av, n = V(o), V(au), V(av), V(n)
    sign = 1 if au.cross(av).dot(n) > 0 else -1
    slant = width * 0.7
    k = -int(slant / stripe) - 1
    while k * stripe < length:
        u0 = k * stripe
        quad = [(u0, 0), (u0 + stripe, 0), (u0 + stripe + slant, width), (u0 + slant, width)]
        quad = [(min(max(u, 0.0), length), v) for u, v in quad]
        if max(u for u, v in quad) - min(u for u, v in quad) > 1e-3:
            part.add(mk_prism(quad, o, au, av, 0.002 * sign, 0.014 * sign),
                     "mine_hazard" if k % 2 == 0 else "mine_black", True)
        k += 1


def mk_vault(cx, cz, r, y0, y1, seg=12):
    """Half cylinder along Y, open underneath, closed at both ends."""
    bm = bmesh.new()
    rings = []
    for y in (y0, y1):
        rings.append([bm.verts.new((cx - r * cos(pi * i / seg), y, cz + r * sin(pi * i / seg)))
                      for i in range(seg + 1)])
    for i in range(seg):
        bm.faces.new((rings[0][i], rings[0][i + 1], rings[1][i + 1], rings[1][i]))
    bm.faces.new(rings[0])
    bm.faces.new(list(reversed(rings[1])))
    return bm


def arc(cx, cz, r, y, seg=12):
    return [(cx - r * cos(pi * i / seg), y, cz + r * sin(pi * i / seg)) for i in range(seg + 1)]

# ---------------------------------------------------------------- layout (metres)
B = 0.12                               # collar top
S = V((0.42, 0.22, 0))                 # shaft centre: the skip hangs here
SHAFT = 0.58                           # shaft opening, square
W = V((0.12, 0.22, 3.50))              # winding wheel (sheave) centre, axis along Y
W_R = 0.30                             # its rope groove radius: the right side drops into the shaft
SKIP_TOP = 2.45                        # the skip's top at rest (raised, ready to tip)
SKIP_H = 0.50
SKIP_W = 0.36
DRUM = V((-0.62, 0.22, 0.62))         # winch drum centre, axis along Y
DRUM_R = 0.20
DECK = (-0.24, 0.48, -0.08, 0.52, 3.20)   # top deck x0, x1, y0, y1, z
LEG_BASE = (-0.12, 0.86, -0.24, 0.68)     # leg feet x0, x1, y0, y1
SHED = (-0.90, -0.28, 0.46, 0.90)         # winch house x0, x1, y0, y1
SHED_H = 1.00
BIN = (0.32, 0.92, -0.90, -0.38)          # ore bin x0, x1, y0, y1
BIN_TOP, BIN_BOT = 1.05, 0.55
LAMP = V((-0.80, -0.80, B))
LAMP_TOP = 2.25

scene = bpy.context.scene
scene.name = "IronMine"
COLL = bpy.data.collections.new("iron_mine")
scene.collection.children.link(COLL)

root = empty("mine_root", Matrix.Identity(4), None, 0.5)

# ---------------------------------------------------------------- concrete collar round the shaft
p = Part()
p.box("mine_concrete", (0, 0, B / 2), (1.92, 1.92, B), bevel=0.02)
p.box("mine_concrete2", (S.x, S.y, B + 0.05), (SHAFT + 0.3, SHAFT + 0.3, 0.1), bevel=0.02)   # the raised shaft lip
p.box("mine_black", (S.x, S.y, B + 0.101), (SHAFT, SHAFT, 0.004))                          # the dark shaft mouth
hazard(p, (S.x - (SHAFT + 0.3) / 2, S.y - (SHAFT + 0.3) / 2 - 0.001, B + 0.1), X, -Z, -Y, SHAFT + 0.3, 0.1, 0.11)
hazard(p, (-0.9, -0.961, B), X, -Z, -Y, 1.8, B, 0.14)
for k in range(5):                     # cracks and stains
    c = V((random.uniform(-0.85, 0.85), random.uniform(-0.85, 0.85), B + 0.002))
    p.box("mine_stain", c, (random.uniform(0.1, 0.35), random.uniform(0.04, 0.14), 0.004), rot_z(random.uniform(0, pi)))
for x, y in ((-0.12, -0.24), (0.86, -0.24), (-0.12, 0.68), (0.86, 0.68)):      # leg footings
    p.box("mine_concrete2", (x, y, B + 0.04), (0.16, 0.16, 0.08), bevel=0.01)
collar = finish(p, "collar", T((0, 0, 0)), root)

# ---------------------------------------------------------------- the headframe: four leaning legs, braces, deck
p = Part()
x0, x1, y0, y1, zd = DECK
bx0, bx1, by0, by1 = LEG_BASE
feet = [V((bx0, by0, B + 0.08)), V((bx1, by0, B + 0.08)), V((bx1, by1, B + 0.08)), V((bx0, by1, B + 0.08))]
heads = [V((x0 + 0.04, y0 + 0.04, zd)), V((x1 - 0.04, y0 + 0.04, zd)), V((x1 - 0.04, y1 - 0.04, zd)), V((x0 + 0.04, y1 - 0.04, zd))]
for a, b in zip(feet, heads):
    p.beam("mine_steel", a, b, 0.07, 0.07, 0.008)
    p.box("mine_gunmetal", a + Z * 0.02, (0.13, 0.13, 0.04), bevel=0.008)       # base plates
for z in (1.10, 2.20):                 # ring girders, following the lean of the legs
    k = (z - feet[0].z) / (zd - feet[0].z)
    ring = [a.lerp(b, k) for a, b in zip(feet, heads)]
    for i in range(4):
        p.beam("mine_steel", ring[i], ring[(i + 1) % 4], 0.05, 0.05)
    if z == 1.10:
        lo = ring
    else:
        mid = ring
for face in range(4):                  # X braces on every face, between the girders
    for lower, upper in ((feet, lo), (lo, mid), (mid, heads)):
        a, b = lower[face], lower[(face + 1) % 4]
        c, d = upper[face], upper[(face + 1) % 4]
        p.beam("mine_rust", a, d, 0.03, 0.03)
        p.beam("mine_rust", b, c, 0.03, 0.03)
# the guide rails the skip runs in, down the shaft
for sy in (-1, 1):
    p.box("mine_gunmetal", (S.x, S.y + sy * (SKIP_W / 2 + 0.03), (B + zd) / 2), (0.06, 0.03, zd - B), bevel=0.005)
# the deck: a grated platform with a handrail, and the sheave's bearing frame
p.box("mine_gunmetal", ((x0 + x1) / 2, (y0 + y1) / 2, zd), (x1 - x0, y1 - y0, 0.06), bevel=0.01)
hazard(p, (x0, y0 - 0.001, zd + 0.03), X, -Z, -Y, x1 - x0, 0.06, 0.1)
for k in range(7):
    xx = x0 + 0.06 + k * (x1 - x0 - 0.12) / 6
    p.box("mine_black", (xx, (y0 + y1) / 2, zd + 0.031), (0.015, y1 - y0 - 0.08, 0.004))
rail = [V((x0, y0, zd + 0.42)), V((x1, y0, zd + 0.42)), V((x1, y1, zd + 0.42)), V((x0, y1, zd + 0.42))]
for i in range(4):
    p.beam("mine_hazard", rail[i], rail[(i + 1) % 4], 0.025, 0.025)
    p.beam("mine_steel", rail[i] - Z * 0.42, rail[i], 0.025, 0.025)
for sy in (-1, 1):                     # A-frames holding the sheave's axle
    yy = W.y + sy * 0.12
    p.beam("mine_steel", V((W.x - 0.24, yy, zd + 0.03)), V((W.x, yy, W.z)), 0.05, 0.05)
    p.beam("mine_steel", V((W.x + 0.24, yy, zd + 0.03)), V((W.x, yy, W.z)), 0.05, 0.05)
    p.cyl("mine_gunmetal", V((W.x, yy - 0.04 * sy, W.z)), V((W.x, yy + 0.04 * sy, W.z)), 0.07, seg=10)
# a red warning lamp on the deck rail, lit with the work lamp
p.cyl("mine_gunmetal", V((x1, y0, zd + 0.42)), V((x1, y0, zd + 0.5)), 0.03, seg=8)
headframe = finish(p, "headframe", T(S), root)
p = Part()
p.sphere("mine_red", V((x1, y0, zd + 0.54)), 0.045, u=8, v=6)
finish(p, "beacon", T(V((x1, y0, zd + 0.54))), headframe)

# ---------------------------------------------------------------- the sheave: a spoked winding wheel
p = Part()
p.add(mk_lathe([(W_R - 0.03, -0.035), (W_R + 0.05, -0.05), (W_R + 0.05, -0.03), (W_R, -0.012), (W_R, 0.012),
                (W_R + 0.05, 0.03), (W_R + 0.05, 0.05), (W_R - 0.03, 0.035)], W, Y, 36, closed=True), "mine_steel", True)
p.add(mk_lathe([(W_R - 0.002, -0.012), (W_R + 0.004, -0.012), (W_R + 0.004, 0.012), (W_R - 0.002, 0.012)], W, Y, 36, closed=True), "mine_hazard", True)
p.cyl("mine_gunmetal", W - Y * 0.08, W + Y * 0.08, 0.06, seg=12)
for k in range(8):
    a = 2 * pi * k / 8
    d = V((cos(a), 0, sin(a)))
    p.cyl("mine_steel", W + d * 0.05, W + d * (W_R - 0.03), 0.018, seg=6)
sheave = finish(p, "sheave", T(W), root)

# ---------------------------------------------------------------- the skip: a bucket that hangs in the shaft
SK = V((S.x, S.y, SKIP_TOP))           # the hanger at its top
p = Part()
body = [V((S.x + sx * SKIP_W / 2, S.y + sy * SKIP_W / 2, SKIP_TOP - 0.06)) for sx, sy in ((1, 1), (-1, 1), (-1, -1), (1, -1))]
foot = [V((S.x + sx * (SKIP_W / 2 - 0.05), S.y + sy * (SKIP_W / 2 - 0.05), SKIP_TOP - SKIP_H)) for sx, sy in ((1, 1), (-1, 1), (-1, -1), (1, -1))]
p.add(mk_loft([foot, body], cap=True), "mine_hazard", True)
p.add(mk_box(SK - Z * 0.07, (SKIP_W - 0.04, SKIP_W - 0.04, 0.02)), "mine_black", True)    # the open mouth
rim = rrect(SK - Z * 0.06, X, Y, SKIP_W / 2 + 0.01, SKIP_W / 2 + 0.01, 0.02, 1)
p.tube("mine_steel", rim + [rim[0]], 0.016, 5)
for sx in (-1, 1):                     # the bail and its hanger
    p.cyl("mine_steel", V((S.x + sx * (SKIP_W / 2 + 0.01), S.y, SKIP_TOP - 0.2)), V((S.x + sx * 0.03, S.y, SKIP_TOP + 0.08)), 0.014, seg=6)
p.cyl("mine_gunmetal", V((S.x, S.y, SKIP_TOP + 0.06)), V((S.x, S.y, SKIP_TOP + 0.12)), 0.035, seg=8)
for sy in (-1, 1):                     # guide shoes riding the rails
    p.box("mine_gunmetal", (S.x, S.y + sy * (SKIP_W / 2 + 0.005), SKIP_TOP - 0.15), (0.08, 0.03, 0.1))
    p.box("mine_gunmetal", (S.x, S.y + sy * (SKIP_W / 2 + 0.005), SKIP_TOP - SKIP_H + 0.08), (0.08, 0.03, 0.1))
for z in (0.18, 0.36):                 # bands
    ring = [V((S.x + sx * (SKIP_W / 2 - 0.02 * z / 0.36), S.y + sy * (SKIP_W / 2 - 0.02 * z / 0.36), SKIP_TOP - z)) for sx, sy in ((1, 1), (-1, 1), (-1, -1), (1, -1))]
    p.tube("mine_black", ring + [ring[0]], 0.01, 4)
skip = finish(p, "skip", T(SK), root)
p = Part()                             # a load of ore heaped in the skip
for k in range(6):
    q = SK + V((random.uniform(-0.1, 0.1), random.uniform(-0.1, 0.1), -0.05))
    p.add(mk_ico(q, random.uniform(0.05, 0.08), sub=1), "mine_ore", True)
finish(p, "skip_ore", T(SK - Z * 0.05), skip)

# ---------------------------------------------------------------- the hoist rope from the sheave down to the skip
ROPE_TOP = V((S.x, S.y, W.z))
ROPE_LEN = W.z - (SKIP_TOP + 0.12)
p = Part()
p.cyl("mine_black", ROPE_TOP, ROPE_TOP - Z * ROPE_LEN, 0.012, seg=6)
finish(p, "rope", T(ROPE_TOP), root)

# ---------------------------------------------------------------- the winch: house, drum and the rope back up to the sheave
p = Part()
sx0, sx1, sy0, sy1 = SHED
cx, cy = (sx0 + sx1) / 2, (sy0 + sy1) / 2
p.box("mine_wood", (cx, cy, B + SHED_H / 2), (sx1 - sx0, sy1 - sy0, SHED_H), bevel=0.012)
for k in range(6):                     # planks
    yy = sy0 + 0.05 + k * (sy1 - sy0 - 0.1) / 5
    p.box("mine_wood2", (sx1 + 0.004, yy, B + SHED_H / 2), (0.01, 0.025, SHED_H - 0.04))
for k in range(4):
    xx = sx0 + 0.06 + k * (sx1 - sx0 - 0.12) / 3
    p.box("mine_wood2", (xx, sy0 - 0.004, B + SHED_H / 2), (0.025, 0.01, SHED_H - 0.04))
p.box("mine_black", (cx + 0.06, sy0 - 0.008, B + 0.42), (0.26, 0.012, 0.6))       # the door
p.box("mine_steel", (cx + 0.06, sy0 - 0.012, B + 0.42), (0.3, 0.012, 0.03))
# a corrugated roof, its ridge along Y
ridge = B + SHED_H + 0.22
for sgn in (-1, 1):
    xa = cx + sgn * ((sx1 - sx0) / 2 + 0.06)
    poly = [V((cx, sy0 - 0.06, ridge)), V((cx, sy1 + 0.06, ridge)), V((xa, sy1 + 0.06, B + SHED_H - 0.02)), V((xa, sy0 - 0.06, B + SHED_H - 0.02))]
    up = [v + Z * 0.03 for v in poly]
    p.add(mk_loft([poly, up], cap=True), "mine_gunmetal", True)
    for k in range(9):                 # corrugation ribs
        yy = sy0 - 0.02 + k * (sy1 - sy0 + 0.04) / 8
        p.beam("mine_steel", V((cx, yy, ridge + 0.035)), V((xa, yy, B + SHED_H + 0.01)), 0.02, 0.012)
p.cyl("mine_gunmetal", V((cx - 0.15, sy1 - 0.2, ridge - 0.05)), V((cx - 0.15, sy1 - 0.2, ridge + 0.35)), 0.05, seg=8)   # stove pipe
# the drum's frame in front of the house
for sy in (-1, 1):
    yy = DRUM.y + sy * 0.2
    p.box("mine_gunmetal", (DRUM.x, yy, (B + DRUM.z) / 2), (0.12, 0.06, DRUM.z - B), bevel=0.01)
    p.cyl("mine_steel", V((DRUM.x, yy - 0.04, DRUM.z)), V((DRUM.x, yy + 0.04, DRUM.z)), 0.06, seg=10)
p.box("mine_gunmetal", (DRUM.x + 0.2, DRUM.y - 0.42, B + 0.18), (0.22, 0.2, 0.36), bevel=0.015)    # the motor
p.cyl("mine_copper", V((DRUM.x + 0.2, DRUM.y - 0.52, B + 0.3)), V((DRUM.x + 0.2, DRUM.y - 0.32, B + 0.3)), 0.09, seg=12)
winch = finish(p, "winch_house", T(V((cx, cy, 0))), root)
p = Part()                             # the back rope from the left of the sheave down to the top of the drum
BACK_TOP = V((W.x - W_R, W.y, W.z))
p.cyl("mine_black", BACK_TOP, V((DRUM.x, W.y, DRUM.z + DRUM_R + 0.02)), 0.012, seg=6)
finish(p, "back_rope", T(BACK_TOP), root)
p = Part()
p.cyl("mine_steel", DRUM - Y * 0.17, DRUM + Y * 0.17, DRUM_R, seg=20)
for sy in (-1, 1):
    p.cyl("mine_hazard", DRUM + Y * sy * 0.15, DRUM + Y * sy * 0.19, DRUM_R + 0.06, seg=20)
for k in range(7):                     # wound rope
    yy = -0.12 + k * 0.04
    p.cyl("mine_black", DRUM + Y * (yy - 0.016), DRUM + Y * (yy + 0.016), DRUM_R + 0.02, seg=20)
for k in range(4):                     # spokes on the flange, so its turning shows
    a = 2 * pi * k / 4
    d = V((cos(a), 0, sin(a)))
    p.box("mine_black", DRUM - Y * 0.195 + d * (DRUM_R * 0.55), (0.04 if k % 2 else DRUM_R * 0.9, 0.012, DRUM_R * 0.9 if k % 2 else 0.04))
drum = finish(p, "drum", T(DRUM), root)

# ---------------------------------------------------------------- the chute and the ore bin
p = Part()
bx0, bx1, by0, by1 = BIN
top = [V((bx1, by1, BIN_TOP)), V((bx0, by1, BIN_TOP)), V((bx0, by0, BIN_TOP)), V((bx1, by0, BIN_TOP))]
bot = [V((bx1 - 0.12, by1 - 0.1, BIN_BOT)), V((bx0 + 0.12, by1 - 0.1, BIN_BOT)), V((bx0 + 0.12, by0 + 0.1, BIN_BOT)), V((bx1 - 0.12, by0 + 0.1, BIN_BOT))]
p.add(mk_loft([bot, top], cap=True), "mine_steel", True)
plates(p, ((bx0 + bx1) / 2, by0 + 0.0, 0), X, Z, -Y, -(bx1 - bx0) / 2 + 0.1, (bx1 - bx0) / 2 - 0.1, BIN_BOT + 0.12, BIN_TOP - 0.04, 2, 1, "mine_gunmetal", 0.6, 0.04)
hazard(p, (bx0 + 0.02, by0 - 0.043, BIN_TOP - 0.02), X, -Z, -Y, bx1 - bx0 - 0.04, 0.09, 0.1)
rim = rrect(V(((bx0 + bx1) / 2, (by0 + by1) / 2, BIN_TOP)), X, Y, (bx1 - bx0) / 2, (by1 - by0) / 2, 0.02, 1)
p.tube("mine_gunmetal", rim + [rim[0]], 0.02, 5)
for xx in (bx0 + 0.08, bx1 - 0.08):
    for yy in (by0 + 0.08, by1 - 0.08):
        p.cyl("mine_gunmetal", V((xx, yy, B)), V((xx, yy, BIN_BOT + 0.15)), 0.03, seg=6)
p.cyl("mine_gunmetal", V(((bx0 + bx1) / 2, (by0 + by1) / 2, BIN_BOT)), V(((bx0 + bx1) / 2, (by0 + by1) / 2, BIN_BOT - 0.18)), 0.1, 0.08, seg=10)
p.box("mine_steel", ((bx0 + bx1) / 2, (by0 + by1) / 2 - 0.0, BIN_BOT - 0.2), (0.24, 0.24, 0.03))      # the gate
ore_bin = finish(p, "ore_bin", T(V(((bx0 + bx1) / 2, (by0 + by1) / 2, 0))), root)
p = Part()                             # the heap of ore in the bin
hc = V(((bx0 + bx1) / 2, (by0 + by1) / 2, BIN_TOP - 0.04))
p.add(mk_box(hc - Z * 0.03, (bx1 - bx0 - 0.08, by1 - by0 - 0.08, 0.04)), "mine_ore2", True)
for k in range(16):
    q = hc + V((random.uniform(-0.22, 0.22), random.uniform(-0.2, 0.2), 0.0))
    q.z += 0.1 * (1 - (q - hc).length / 0.32)
    p.add(mk_ico(q, random.uniform(0.05, 0.09), sub=1), "mine_ore" if k % 3 else "mine_ore2", True)
finish(p, "ore_heap", T(hc), ore_bin)
for k in range(3):                     # dust puffs, shown only while ore lands
    q = hc + V((0.0, 0.0, 0.1))
    p = Part()
    p.add(mk_ico(q, 0.16, sub=2), "mine_dust")
    finish(p, "dust_%d" % (k + 1), T(q), ore_bin)
# the chute from the tipped skip down into the bin
p = Part()
c0 = V((S.x + 0.02, S.y - SKIP_W / 2 - 0.08, SKIP_TOP - 0.28))
c1 = V(((bx0 + bx1) / 2 + 0.02, by1 - 0.12, BIN_TOP + 0.12))
d = (c1 - c0)
ax = d.normalized()
side = X.copy()
up = side.cross(ax).normalized()
if up.z < 0:
    up = -up
for sgn in (-1, 1):
    p.beam("mine_steel", c0 + side * sgn * 0.17 + up * 0.06, c1 + side * sgn * 0.17 + up * 0.06, 0.02, 0.12)
p.add(mk_box((c0 + c1) / 2, (0.36, d.length, 0.02), basis(side, ax, side.cross(ax).normalized() if side.cross(ax).z > 0 else -side.cross(ax).normalized()), 0.005), "mine_rust", True)
p.beam("mine_gunmetal", c1 + side * 0.17 - up * 0.02, V((c1.x + 0.17, c1.y, B)), 0.03, 0.03)
p.beam("mine_gunmetal", c1 - side * 0.17 - up * 0.02, V((c1.x - 0.17, c1.y, B)), 0.03, 0.03)
chute = finish(p, "chute", T(c0), root)

# ---------------------------------------------------------------- the work lamp
p = Part()
p.box("mine_concrete2", LAMP + Z * 0.05, (0.2, 0.2, 0.1), bevel=0.01)
p.cyl("mine_gunmetal", LAMP + Z * 0.1, LAMP + Z * LAMP_TOP, 0.035, 0.028, seg=8)
HEAD = LAMP + V((0.26, 0.04, LAMP_TOP - 0.02))
p.tube("mine_gunmetal", [LAMP + Z * (LAMP_TOP - 0.1), LAMP + Z * LAMP_TOP + X * 0.06, HEAD + Z * 0.08], 0.02, 6, 0.08)
p.cyl("mine_steel", HEAD + Z * 0.1, HEAD - Z * 0.04, 0.03, 0.12, seg=12)
p.box("mine_black", LAMP + V((0.0, -0.05, 0.9)), (0.12, 0.06, 0.16), bevel=0.01)      # a switch box
lamp_post = finish(p, "lamp_post", T(LAMP), root)
p = Part()
p.cyl("mine_lamp", HEAD - Z * 0.035, HEAD - Z * 0.05, 0.11, seg=12)
p.sphere("mine_lamp", HEAD - Z * 0.03, 0.06, u=10, v=6)
finish(p, "lamp", T(HEAD - Z * 0.04), lamp_post)

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
