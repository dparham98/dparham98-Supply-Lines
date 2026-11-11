"""Builds Motorcycle.blend from nothing (Stage 1: the static model).

Run in background Blender:
  blender --background --python build_motorcycle.py

Everything is rebuilt each run, so edits here never compound. Faces -Y, Z up, tyres on Z = 0,
left is +X. Animation and effects are added afterwards by their own scripts.
"""
import bpy, bmesh, math, os, random
from math import sin, cos, radians, pi
from mathutils import Vector as V, Matrix

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "Motorcycle.blend")
DRONE = os.path.normpath(os.path.join(HERE, "..", "Drone", "Drone.blend"))
X, Y, Z = V((1, 0, 0)), V((0, 1, 0)), V((0, 0, 1))
random.seed(7)

bpy.ops.wm.read_factory_settings(use_empty=True)

# ---------------------------------------------------------------- faction fang (from the Drone)
with bpy.data.libraries.load(DRONE) as (src, dst):
    dst.objects = ["faction_fang"]
_f = dst.objects[0]
_me = _f.data
_n = V((0, 0, 0))
for p in _me.polygons:
    _n += p.normal * p.area
_n.normalize()
_co = [v.co.copy() for v in _me.vertices]
_cen = sum(_co, V((0, 0, 0))) / len(_co)
_tip = min(_co, key=lambda v: v.y) - _cen
_tip -= _n * _tip.dot(_n)
_tip.normalize()
_lat = _n.cross(_tip)
FANG_UV = [((v - _cen).dot(_lat), (v - _cen).dot(_tip)) for v in _co]
_a = [u for u, v in FANG_UV]
_b = [v for u, v in FANG_UV]
_ca, _cb = (max(_a) + min(_a)) / 2, (max(_b) + min(_b)) / 2
FANG_UV = [(u - _ca, v - _cb) for u, v in FANG_UV]
FANG_LEN = max(_b) - min(_b)
FANG_POLYS = [(list(p.vertices), p.material_index) for p in _me.polygons]
FANG_MATS = list(_me.materials)
for m in FANG_MATS:
    m.use_fake_user = True
for o in list(bpy.data.objects):
    bpy.data.objects.remove(o)
for m in list(bpy.data.meshes):
    bpy.data.meshes.remove(m)

# ---------------------------------------------------------------- materials (flat PBR, linear colour)
MATS = {}


def material(name, col, met, rough, emis=None, strength=0.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = next(n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    b.inputs["Base Color"].default_value = (*col, 1)
    b.inputs["Metallic"].default_value = met
    b.inputs["Roughness"].default_value = rough
    if emis:
        b.inputs["Emission Color"].default_value = (*emis, 1)
        b.inputs["Emission Strength"].default_value = strength
    m.diffuse_color = (*col, 1)
    MATS[name] = m
    return m


material("moto_gunmetal", (0.155, 0.147, 0.138), 0.40, 0.52)
material("moto_charcoal", (0.058, 0.055, 0.054), 0.25, 0.62)
material("moto_steel", (0.33, 0.32, 0.30), 0.50, 0.42)
material("moto_oxblood", (0.235, 0.028, 0.020), 0.15, 0.58)
material("moto_brass", (0.40, 0.25, 0.08), 0.70, 0.42)
material("moto_copper", (0.44, 0.185, 0.075), 0.70, 0.38)
material("moto_rubber", (0.022, 0.022, 0.024), 0.0, 0.85)
material("moto_joint", (0.030, 0.029, 0.031), 0.1, 0.70)
material("moto_hopper", (0.10, 0.06, 0.038), 0.35, 0.66)
material("moto_coal", (0.012, 0.012, 0.015), 0.0, 0.45)
material("moto_iron", (0.20, 0.19, 0.185), 0.60, 0.45)
material("moto_amber", (0.30, 0.08, 0.012), 0.0, 0.40, (1.0, 0.2, 0.02), 1.8)
material("moto_trail", (0.8, 0.8, 0.8), 0.0, 0.5, (1.0, 0.9, 0.7), 1.5)
for m in FANG_MATS:
    MATS[m.name] = m

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

    def rivet(self, pos, normal, r=0.011, mat="moto_brass"):
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


def fang(name, centre, normal, tip_dir, height, parent):
    normal, tip_dir = V(normal), V(tip_dir)
    lat = normal.cross(tip_dir)
    s = height / FANG_LEN
    bm = bmesh.new()
    vs = [bm.verts.new(V(centre) + lat * u * s + tip_dir * v * s) for u, v in FANG_UV]
    for idx, mi in FANG_POLYS:
        f = bm.faces.new([vs[i] for i in idx])
        f.material_index = mi
    bm.normal_update()
    for f in bm.faces:
        if f.normal.dot(normal) < 0:
            f.normal_flip()
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    for m in FANG_MATS:
        me.materials.append(m)
    return place(bpy.data.objects.new(name, me), Matrix.Identity(4), parent)


# ---------------------------------------------------------------- layout (metres)
RF, WF = 0.37, 0.17            # front tyre radius, half width
RR, WR = 0.38, 0.21            # rear tyre
FKX = 0.255                    # fork tube offset
SAX = 0.245                    # swing arm offset
EXX = 0.35                     # exhaust can offset
FA = V((0, -0.91, RF))         # front axle
RA = V((0, 0.90, RR))          # rear axle
RAKE = radians(18)
U = V((0, sin(RAKE), cos(RAKE)))       # steering axis, up and back
FW = V((0, -cos(RAKE), sin(RAKE)))     # square to it, forward
HEAD = FA + U * 0.88                   # top of the steering head
RAKE_M = rot_x(-RAKE)

# The gun and the rider are written in their own drafting coordinates and shifted into place.
GD = V((0, 0.04, 0.115))               # gun shift
RD = V((0, 0.04, 0.11))                # rider shift
POST = V((0, 0.56, 0))                 # gun post axis
SW = V((0, 0.52, 1.585))               # swivel bearing (before GD)
TRUN = V((0, 0.52, 1.715))             # gun trunnion (before GD)
BORE_Z = 1.76
BARREL_ROOT = V((0, 0.31, BORE_Z))
MUZZLE = V((0, -0.25, BORE_Z))

HIP_C = V((0, 0.25, 0.80))             # rider points (before RD)
WAIST = V((0, 0.10, 1.03))
SHOULDER_C = V((0, -0.09, 1.27))
NECK = V((0, -0.15, 1.355))
HELM = V((0, -0.215, 1.47))
SHX = 0.25                             # shoulder offset
PEG = V((0.29, 0.26, 0.455))           # left foot peg, under the boot

scene = bpy.context.scene
scene.name = "Motorcycle"
COLL = bpy.data.collections.new("motorcycle")
scene.collection.children.link(COLL)

root = empty("bike_root", Matrix.Identity(4), None, 0.4)

# ---------------------------------------------------------------- wheels


def wheel(name, c, R, w, parent, world, spoked):
    P = Part()
    sec = 0.17 if spoked else 0.18                    # tyre section height
    rim = R - sec
    prof = [(p.z, p.x) for p in rrect(V((0, 0, R - sec / 2 - 0.012)), X, Z, w, sec / 2, 0.065, 3)]
    P.add(mk_lathe(prof, c, X, 28, closed=True, ref=Z), "moto_rubber")
    n = 16
    for i in range(n):
        for row, off in ((1, 0.0), (-1, 0.5)):
            a = 2 * pi * (i + off) / n
            rad = Y * cos(a) + Z * sin(a)
            R_m = rot_x(a - pi / 2)
            # centre blocks
            P.box("moto_rubber", c + X * row * w * 0.42 + rad * (R - 0.021), (w * 0.72, 0.095, 0.036), R_m)
            # shoulder lugs wrapping onto the sidewall
            P.box("moto_rubber", c + X * row * (w - 0.004) + rad * (R - 0.058), (0.034, 0.08, 0.10), R_m)
    # rim barrel and lips
    barrel = [(rim - 0.03, -w * 0.8), (rim + 0.012, -w * 0.8), (rim + 0.012, w * 0.8), (rim - 0.03, w * 0.8)]
    P.add(mk_lathe(barrel, c, X, 20, closed=True, ref=Z), "moto_charcoal")
    for s in (1, -1):
        lip = [(rim - 0.022, s * w * 0.74), (rim + 0.022, s * w * 0.74), (rim + 0.022, s * w * 0.92),
               (rim - 0.022, s * w * 0.92)]
        P.add(mk_lathe(lip, c, X, 20, closed=True, ref=Z), "moto_brass" if spoked else "moto_gunmetal")
    if spoked:
        P.cyl("moto_gunmetal", c - X * 0.11, c + X * 0.11, 0.065, seg=10)
        for s in (1, -1):
            P.cyl("moto_brass", c + X * s * 0.11, c + X * s * 0.135, 0.05, 0.032, seg=10)
            P.cyl("moto_charcoal", c + X * s * 0.09, c + X * s * 0.10, 0.15, seg=14)   # brake disc
        for i in range(8):
            a = 2 * pi * i / 8
            rad = Y * cos(a) + Z * sin(a)
            P.box("moto_steel", c + rad * (rim * 0.5 + 0.02), (0.04, 0.034, rim - 0.03), rot_x(a - pi / 2), 0.006)
    else:
        P.cyl("moto_gunmetal", c - X * 0.06, c + X * 0.06, rim, seg=20)
        for s in (1, -1):
            P.cyl("moto_charcoal", c + X * s * 0.06, c + X * s * 0.11, rim * 0.74, 0.09, seg=16)
            P.cyl("moto_brass", c + X * s * 0.11, c + X * s * 0.145, 0.062, 0.04, seg=10)
            for i in range(8):
                a = 2 * pi * (i + 0.5) / 8
                P.rivet(c + X * s * 0.06 + (Y * cos(a) + Z * sin(a)) * rim * 0.87, X * s, 0.014)
    return finish(P, name, world, parent)


# ---------------------------------------------------------------- frame
P = Part()

# tank: rounded-box sections along Y, flat sides for the emblem
TANK = [(-0.62, 0.970, 0.08, 0.09, 0.04), (-0.59, 0.955, 0.15, 0.15, 0.06),
        (-0.50, 0.930, 0.20, 0.19, 0.07), (-0.22, 0.905, 0.20, 0.18, 0.07),
        (-0.08, 0.880, 0.17, 0.15, 0.06), (0.00, 0.850, 0.11, 0.10, 0.04)]


def tank_at(y):
    for a, b in zip(TANK, TANK[1:]):
        if a[0] <= y <= b[0]:
            t = (y - a[0]) / (b[0] - a[0])
            return [a[i] + (b[i] - a[i]) * t for i in range(5)]


P.add(mk_loft([rrect((0, y, zc), X, Z, w, h, rc, 4) for y, zc, w, h, rc in TANK]), "moto_oxblood")
for ys in (-0.548, -0.145):
    rings = []
    for y in (ys - 0.022, ys + 0.022):
        _, zc, w, h, rc = tank_at(y)
        rings.append(rrect((0, y, zc), X, Z, w + 0.008, h + 0.008, rc + 0.008, 4))
    P.add(mk_loft(rings), "moto_gunmetal")
    _, zc, w, h, rc = tank_at(ys)
    for s in (1, -1):
        for dz in (-0.085, 0.0, 0.085):
            P.rivet((s * (w + 0.008), ys, zc + dz), X * s, 0.011)
        P.rivet((s * 0.075, ys, zc + h + 0.008), Z, 0.011)
P.cyl("moto_brass", (0, -0.42, 1.105), (0, -0.42, 1.15), 0.055, seg=12)
P.cyl("moto_gunmetal", (0, -0.42, 1.15), (0, -0.42, 1.165), 0.032, seg=8)

# seat
SEAT = [(0.04, 0.800, 0.13, 0.035), (0.12, 0.800, 0.16, 0.040), (0.38, 0.805, 0.17, 0.040),
        (0.46, 0.840, 0.16, 0.060), (0.51, 0.860, 0.12, 0.045)]
P.add(mk_loft([rrect((0, y, zc), X, Z, w, h, 0.03, 3) for y, zc, w, h in SEAT]), "moto_joint")
P.box("moto_charcoal", (0, 0.27, 0.735), (0.30, 0.52, 0.08), None, 0.015)
for s in (1, -1):
    P.box("moto_oxblood", (s * 0.165, 0.29, 0.70), (0.024, 0.40, 0.115), None, 0.007)
    for k in (-1, 1):
        P.rivet((s * 0.177, 0.29 + 0.16 * k, 0.70), X * s, 0.010)

# engine
P.box("moto_charcoal", (0, -0.01, 0.42), (0.36, 0.82, 0.36), None, 0.04)
P.box("moto_charcoal", (0, -0.02, 0.228), (0.30, 0.74, 0.03), None, 0.008)
P.box("moto_charcoal", (0, 0.06, 0.655), (0.30, 0.52, 0.13), None, 0.02)
P.box("moto_gunmetal", (0, -0.42, 0.67), (0.24, 0.12, 0.17), None, 0.012)
for i in range(5):
    P.box("moto_gunmetal", (0, -0.42, 0.60 + 0.034 * i), (0.31, 0.16, 0.013))
P.box("moto_gunmetal", (0, 0.45, 0.46), (0.32, 0.20, 0.34), None, 0.03)
# boiler drum under the seat
P.cyl("moto_brass", (-0.16, 0.24, 0.50), (0.16, 0.24, 0.50), 0.125, seg=14)
for s in (1, -1):
    P.cyl("moto_gunmetal", (s * 0.145, 0.24, 0.50), (s * 0.172, 0.24, 0.50), 0.132, seg=14)
    P.cyl("moto_gunmetal", (s * 0.172, 0.24, 0.50), (s * 0.188, 0.24, 0.50), 0.05, seg=8)

# firebox: octagonal housing right across the engine, a barred glowing window on each side
FB = V((0, -0.22, 0.46))
FBR, FBX = 0.185, 0.225
octo = [(FBR * cos(radians(22.5 + 45 * k)), FBR * sin(radians(22.5 + 45 * k))) for k in range(8)]
P.add(mk_prism(octo, FB, Y, Z, -FBX, FBX), "moto_gunmetal", flat=True)
for s in (1, -1):
    P.box("moto_charcoal", FB + X * s * (FBX + 0.001), (0.014, 0.225, 0.20), None, 0.004)
    P.box("moto_amber", FB + X * s * (FBX + 0.007), (0.012, 0.19, 0.165))
    for k in range(5):
        P.box("moto_charcoal", FB + X * s * (FBX + 0.014) + Y * (-0.076 + 0.038 * k), (0.012, 0.014, 0.17))
    P.box("moto_charcoal", FB + X * s * (FBX + 0.014), (0.012, 0.195, 0.012))
    for k in range(8):
        a = radians(45 * k)
        P.rivet(FB + X * s * FBX + (Y * cos(a) + Z * sin(a)) * 0.155, X * s, 0.012)
# flue from the firebox into the tank's underside
P.cyl("moto_gunmetal", FB + Z * 0.16, FB + Z * 0.28, 0.065, 0.05, seg=10)

# steering head, down tubes, cradle
P.cyl("moto_gunmetal", FA + U * 0.61, FA + U * 0.805, 0.052, seg=12)
P.box("moto_gunmetal", (0, -0.655, 1.0), (0.07, 0.13, 0.16), RAKE_M, 0.012)
hd = FA + U * 0.68
for s in (1, -1):
    P.tube("moto_charcoal", [hd + X * s * 0.035, (s * 0.16, -0.40, 0.25), (s * 0.16, 0.46, 0.245),
                             (s * 0.175, 0.54, 0.52)], 0.025, 8, 0.07)
    # rear subframe rails and struts
    P.tube("moto_charcoal", [(s * 0.14, 0.04, 0.74), (s * 0.17, 0.50, 0.80), (s * 0.18, 1.10, 0.84)], 0.022, 8, 0.06)
    P.cyl("moto_charcoal", (s * 0.19, 0.52, 0.52), (s * 0.18, 0.86, 0.825), 0.018, seg=8)
    # swing arm, shock
    P.beam("moto_gunmetal", (s * SAX, 0.42, 0.435), (s * SAX, 0.93, 0.38), 0.026, 0.08, 0.008)
    P.cyl("moto_brass", (s * SAX, 0.44, 0.432), (s * (SAX + 0.02), 0.44, 0.432), 0.036, seg=10)
    a_, b_ = V((s * SAX, 0.76, 0.445)), V((s * 0.20, 0.64, 0.80))
    P.cyl("moto_steel", a_, b_, 0.014, seg=8)
    P.cyl("moto_brass", a_ + (b_ - a_) * 0.1, a_ + (b_ - a_) * 0.82, 0.03, seg=10)
    for k in range(4):
        q = a_ + (b_ - a_) * (0.12 + 0.21 * k)
        P.cyl("moto_gunmetal", q, q + (b_ - a_) * 0.06, 0.035, seg=10)
    # foot pegs
    P.cyl("moto_joint", (s * 0.19, PEG.y, PEG.z), (s * 0.37, PEG.y, PEG.z), 0.018, seg=8)
    P.box("moto_gunmetal", (s * 0.178, PEG.y, PEG.z - 0.05), (0.04, 0.05, 0.15), None, 0.008)
    # rear axle nuts
    P.cyl("moto_brass", RA + X * s * (SAX + 0.013), RA + X * s * (SAX + 0.045), 0.03, 0.022, seg=8)
P.cyl("moto_gunmetal", RA - X * (SAX + 0.015), RA + X * (SAX + 0.015), 0.024, seg=8)
P.cyl("moto_charcoal", (-SAX, 0.42, 0.435), (SAX, 0.42, 0.435), 0.03, seg=8)

# rear mudguard, bands, tail light
RFW = WR + 0.05
P.add(mk_arc_shell(RA, RR + 0.035, 0.022, RFW, -8, 140, 16, 0.10), "moto_oxblood")
for a in (-5, 48, 100, 137):
    P.add(mk_arc_shell(RA, RR + 0.031, 0.031, RFW + 0.005, a - 3, a + 3, 2, 0.104), "moto_gunmetal")
    ar = radians(a)
    rd = Y * cos(ar) + Z * sin(ar)
    for s in (1, -1):
        P.rivet(RA + X * s * (RFW + 0.005) + rd * (RR + 0.02), X * s, 0.011)
        P.rivet(RA + X * s * (RFW + 0.005) + rd * (RR - 0.04), X * s, 0.011)
        P.rivet(RA + X * s * 0.12 + rd * (RR + 0.062), rd, 0.011)
ta = radians(20)
td_ = Y * cos(ta) + Z * sin(ta)
tl = RA + td_ * (RR + 0.066)
P.box("moto_gunmetal", tl, (0.24, 0.05, 0.12), rot_x(ta), 0.01)
for k in (-1, 0, 1):
    P.box("moto_amber", tl + td_ * 0.024 + (Z * cos(ta) - Y * sin(ta)) * 0.033 * k, (0.19, 0.014, 0.019), rot_x(ta))

# gun platform, fixed post, braces, coiled line
P.box("moto_gunmetal", (0, POST.y + 0.03, 0.83), (0.40, 0.27, 0.05), None, 0.012)
post = [(0.0, 0.85), (0.125, 0.85), (0.125, 0.885), (0.085, 0.93), (0.066, 0.985), (0.058, 1.585),
        (0.075, 1.62), (0.098, 1.645), (0.098, 1.70), (0.0, 1.70)]
P.add(mk_lathe(post, POST, Z, 14), "moto_gunmetal")
for z0 in (1.10, 1.52):
    P.cyl("moto_brass", POST + Z * z0, POST + Z * (z0 + 0.05), 0.076, seg=14)
for k in range(6):
    a = radians(60 * k)
    P.rivet(POST + Z * 0.885 + (X * cos(a) + Y * sin(a)) * 0.105, Z, 0.013)
for s in (1, -1):
    P.cyl("moto_charcoal", (s * 0.18, POST.y + 0.12, 0.85), (s * 0.04, POST.y + 0.03, 1.27), 0.02, seg=8)
helix = []
for i in range(37):
    t = i / 36
    a = 2 * pi * 3 * t + pi / 2
    helix.append(POST + Z * (1.20 + 0.29 * t) + (X * cos(a) + Y * sin(a)) * 0.082)
P.tube("moto_copper", helix, 0.016, 6)

# coal hopper
HOP, HZ0, HZ1 = 0.945, 0.87, 1.25
TAPER = 0.075 / (HZ1 - HZ0)


def hop_half(z):
    return 0.17 + (z - HZ0) * TAPER


P.add(mk_loft([rrect((0, HOP, z), X, Y, hop_half(z), hop_half(z), 0.05, 1) for z in (HZ0, HZ1)]),
      "moto_hopper", flat=True)
P.add(mk_loft([rrect((0, HOP, z), X, Y, hop_half(z) + 0.012, hop_half(z) + 0.012, 0.058, 1)
               for z in (HZ1 - 0.04, HZ1 + 0.012)]), "moto_gunmetal", flat=True)
P.add(mk_loft([rrect((0, HOP, z), X, Y, hop_half(z) + 0.01, hop_half(z) + 0.01, 0.055, 1)
               for z in (HZ0 - 0.005, HZ0 + 0.04)]), "moto_gunmetal", flat=True)
for sx, sy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
    n_ = X * sx + Y * sy
    t_ = Z.cross(n_)
    for k in (-1, 0, 1):
        P.rivet(V((0, HOP, HZ1 - 0.014)) + n_ * (hop_half(HZ1) + 0.011) + t_ * 0.12 * k, n_, 0.012)
    for zz in (HZ0 + 0.13, HZ0 + 0.25):
        P.box("moto_gunmetal", V((0, HOP, zz)) + n_ * (hop_half(zz) + 0.003), (hop_half(zz) * 1.7, 0.012, 0.024),
              basis(t_, n_, Z))
P.box("moto_charcoal", (0, HOP, HZ0 - 0.018), (0.38, 0.30, 0.035), None, 0.008)
P.sphere("moto_coal", (0, HOP, HZ1 - 0.015), 1.0, (0.225, 0.225, 0.075), 10, 6)
for i in range(30):
    a, rr = random.uniform(0, 2 * pi), random.uniform(0, 0.19) ** 0.9
    r_ = random.uniform(0.035, 0.06)
    z_ = HZ1 + 0.015 + 0.075 * (1 - (rr / 0.2) ** 2) + random.uniform(-0.01, 0.015)
    rot = rot_z(random.uniform(0, 6)) @ rot_x(random.uniform(0, 6))
    bm_ = mk_ico((rr * cos(a), HOP + rr * sin(a), z_), r_,
                 (random.uniform(0.8, 1.3), random.uniform(0.8, 1.3), random.uniform(0.6, 1.0)), rot)
    P.add(bm_, "moto_coal", flat=True)

# copper: feed lines from the firebox to the hopper, exhaust headers
for s in (1, -1):
    P.tube("moto_copper", [(s * 0.10, 0.02, 0.665), (s * 0.19, 0.06, 0.668), (s * 0.19, 0.42, 0.72),
                           (s * 0.19, 0.70, 0.845), (s * 0.13, 0.82, 0.88)], 0.019, 8, 0.05)
    P.cyl("moto_brass", (s * 0.148, 0.038, 0.666), (s * 0.166, 0.044, 0.667), 0.029, seg=8)
    P.tube("moto_copper", [(s * 0.13, -0.42, 0.66), (s * 0.24, -0.46, 0.54), (s * 0.27, -0.43, 0.27),
                           (s * 0.28, 0.0, 0.24), (s * EXX, 0.39, 0.30)], 0.03, 8, 0.06)
    # lower exhaust can
    P.cyl("moto_gunmetal", (s * EXX, 0.39, 0.30), (s * EXX, 0.46, 0.303), 0.032, 0.085, seg=12)
    P.cyl("moto_gunmetal", (s * EXX, 0.46, 0.303), (s * EXX, 1.06, 0.33), 0.085, seg=12)
    for y0 in (0.51, 0.99):
        z0 = 0.303 + (y0 - 0.46) * 0.045
        P.cyl("moto_brass", (s * EXX, y0, z0), (s * EXX, y0 + 0.035, z0 + 0.0016), 0.09, seg=12)
    P.cyl("moto_copper", (s * EXX, 1.06, 0.33), (s * EXX, 1.15, 0.334), 0.062, 0.055, seg=12)
    P.cyl("moto_coal", (s * EXX, 1.145, 0.3338), (s * EXX, 1.152, 0.3341), 0.044, seg=10)
    # upper exhaust can
    ux = EXX - 0.02
    P.tube("moto_copper", [(s * 0.16, 0.45, 0.50), (s * ux, 0.58, 0.50), (s * ux, 0.80, 0.514)], 0.036, 8, 0.05)
    P.cyl("moto_gunmetal", (s * ux, 0.74, 0.51), (s * ux, 0.79, 0.513), 0.036, 0.068, seg=12)
    P.cyl("moto_gunmetal", (s * ux, 0.79, 0.513), (s * ux, 1.10, 0.53), 0.068, seg=12)
    P.cyl("moto_brass", (s * ux, 1.04, 0.527), (s * ux, 1.07, 0.5285), 0.073, seg=12)
    P.cyl("moto_copper", (s * ux, 1.10, 0.53), (s * ux, 1.17, 0.534), 0.05, 0.045, seg=10)
    P.cyl("moto_coal", (s * ux, 1.165, 0.5337), (s * ux, 1.172, 0.5341), 0.035, seg=10)

# stand bracket and its hydraulic ram on the frame (left)
HINGE = V((0.20, 0.02, 0.25))
P.box("moto_gunmetal", HINGE + V((-0.02, 0, 0.01)), (0.06, 0.07, 0.06), None, 0.01)
P.cyl("moto_brass", (0.18, 0.22, 0.29), (0.20, 0.06, 0.255), 0.016, seg=8)

frame = finish(P, "frame", Matrix.Identity(4), root)
fang("faction_fang_L", (0.2045, -0.36, 0.915), X, -Z, 0.22, frame)
fang("faction_fang_R", (-0.2045, -0.36, 0.915), -X, -Z, 0.22, frame)

# ---------------------------------------------------------------- steering assembly
steer_w = T(HEAD) @ RAKE_M
steer = empty("steer_F", steer_w, root, 0.2, 'ARROWS')
FFW = WF + 0.05
P = Part()
for s in (1, -1):
    b = FA + X * s * FKX
    P.cyl("moto_gunmetal", b - U * 0.055, b + U * 0.40, 0.05, seg=10)
    P.cyl("moto_brass", b + U * 0.37, b + U * 0.42, 0.057, seg=10)
    P.cyl("moto_brass", b + U * 0.17, b + U * 0.20, 0.055, seg=10)
    P.cyl("moto_steel", b + U * 0.40, b + U * 0.86, 0.03, seg=10)
    P.cyl("moto_charcoal", b + U * 0.60, b + U * 0.81, 0.046, seg=10)
    P.cyl("moto_brass", b + X * s * 0.035, b + X * s * 0.065, 0.03, 0.022, seg=8)
    P.cyl("moto_gunmetal", b + FW * 0.02 + U * 0.10, b + FW * 0.045 + U * 0.10, 0.03, seg=8)
    P.cyl("moto_amber", b + FW * 0.04 + U * 0.10, b + FW * 0.058 + U * 0.10, 0.023, seg=8)
    # mudguard stays
    for a in (60, 150):
        ar = radians(a)
        P.cyl("moto_steel", b, FA + X * s * FFW + (Y * cos(ar) + Z * sin(ar)) * (RF + 0.0), 0.012, seg=6)
P.cyl("moto_gunmetal", FA - X * (FKX + 0.035), FA + X * (FKX + 0.035), 0.022, seg=8)
P.box("moto_gunmetal", FA + U * 0.575, (FKX * 2 + 0.09, 0.10, 0.05), RAKE_M, 0.012)
P.box("moto_gunmetal", FA + U * 0.83, (FKX * 2 + 0.09, 0.11, 0.045), RAKE_M, 0.012)
P.cyl("moto_brass", HEAD - U * 0.035, HEAD + U * 0.012, 0.04, seg=10)
# front mudguard
P.add(mk_arc_shell(FA, RF + 0.035, 0.022, FFW, 45, 165, 13, 0.09), "moto_oxblood")
for a in (48, 105, 162):
    P.add(mk_arc_shell(FA, RF + 0.031, 0.031, FFW + 0.005, a - 3, a + 3, 2, 0.094), "moto_gunmetal")
    ar = radians(a)
    rd = Y * cos(ar) + Z * sin(ar)
    for s in (1, -1):
        P.rivet(FA + X * s * (FFW + 0.005) + rd * (RF + 0.02), X * s, 0.011)
        P.rivet(FA + X * s * (FFW + 0.005) + rd * (RF - 0.035), X * s, 0.011)
        P.rivet(FA + X * s * 0.10 + rd * (RF + 0.062), rd, 0.011)
# headlight
HL = FA + U * 0.66 + FW * 0.19
P.cyl("moto_gunmetal", HL + Y * 0.11, HL - Y * 0.06, 0.08, 0.128, seg=8, flat=True)
P.cyl("moto_brass", HL - Y * 0.06, HL - Y * 0.088, 0.14, seg=8, flat=True)
P.cyl("moto_amber", HL - Y * 0.088, HL - Y * 0.095, 0.113, seg=8, flat=True)
for a in (45, -45):
    P.box("moto_charcoal", HL - Y * 0.097, (0.228, 0.010, 0.016), rot_y(radians(a)))
for s in (1, -1):
    P.box("moto_gunmetal", HL + X * s * 0.17 + Y * 0.075, (0.17, 0.03, 0.045), None, 0.006)
# shield under the headlight
P.box("moto_oxblood", FA + U * 0.50 + FW * 0.075, (0.42, 0.014, 0.15), RAKE_M, 0.004)
P.box("moto_gunmetal", FA + U * 0.50 + FW * 0.079, (0.44, 0.012, 0.03), RAKE_M)
for s in (1, -1):
    for k in (-1, 1):
        P.rivet(FA + U * (0.50 + 0.055 * k) + FW * 0.083 + X * s * 0.17, FW, 0.011)
fork = finish(P, "fork_F", steer_w, steer)
# handlebars: their own object on the steering pivot
P = Part()
BAR = [V((0.0, -0.62, 1.262)), V((0.13, -0.62, 1.272)), V((0.26, -0.575, 1.262)), V((0.385, -0.53, 1.245))]
for s in (1, -1):
    pts = [V((p.x * s, p.y, p.z)) for p in BAR]
    P.tube("moto_gunmetal", pts, 0.016, 8, 0.045)
    g0 = pts[2] + (pts[3] - pts[2]) * 0.08
    P.cyl("moto_joint", g0, pts[3], 0.025, seg=10)
    P.cyl("moto_brass", pts[3], pts[3] + (pts[3] - pts[2]).normalized() * 0.018, 0.028, seg=10)
    P.cyl("moto_gunmetal", HEAD + X * s * 0.075 - U * 0.03, V((s * 0.075, -0.62, 1.267)), 0.018, seg=8)
    P.cyl("moto_gunmetal", pts[2] + V((0, -0.01, 0.0)), pts[2] + V((s * 0.09, -0.075, -0.012)), 0.008, seg=6)
P.cyl("moto_brass", (0, -0.62, 1.274), (0, -0.605, 1.314), 0.042, seg=10)
P.cyl("moto_steel", (0, -0.605, 1.314), (0, -0.6035, 1.318), 0.034, seg=10)
GRIP = (BAR[2] + (BAR[3] - BAR[2]) * 0.54)
GRIP_DIR = (BAR[3] - BAR[2]).normalized()
finish(P, "handlebar_F", steer_w, steer)
wheel("wheel_F", FA, RF, WF, steer, T(FA) @ RAKE_M, True)
wheel("wheel_R", RA, RR, WR, root, T(RA), False)

# ---------------------------------------------------------------- parking stand (modelled down)
FOOT = V((0.43, -0.02, 0.045))
d1 = (FOOT - HINGE).normalized()
d2 = V((0.04, 0.95, 0.02)).normalized()
hinge_axis = d1.cross(d2).normalized()
STAND_ANGLE = math.degrees(d1.angle(d2))
P = Part()
P.cyl("moto_brass", HINGE - hinge_axis * 0.03, HINGE + hinge_axis * 0.03, 0.026, seg=8)
P.cyl("moto_gunmetal", HINGE, HINGE + d1 * 0.20, 0.023, seg=8)
P.cyl("moto_brass", HINGE + d1 * 0.185, HINGE + d1 * 0.21, 0.027, seg=8)
P.cyl("moto_steel", HINGE + d1 * 0.20, FOOT, 0.012, seg=6)
P.cyl("moto_gunmetal", FOOT - Z * 0.012, FOOT + Z * 0.006, 0.045, 0.035, seg=8)
sz = -d1
sy = sz.cross(hinge_axis).normalized()
stand = finish(P, "stand", T(HINGE) @ basis(hinge_axis, sy, sz), root)
stand["stow_degrees"] = STAND_ANGLE

# ---------------------------------------------------------------- gun
P = Part()
P.cyl("moto_brass", SW, SW + Z * 0.035, 0.105, seg=14)
P.box("moto_gunmetal", SW + Z * 0.05, (0.235, 0.15, 0.035), None, 0.008)
for s in (1, -1):
    P.box("moto_gunmetal", SW + X * s * 0.105 + Z * 0.095, (0.024, 0.13, 0.12), None, 0.008)
swivel = finish(P, "gun_swivel", T(SW + GD), root, shift=GD)

P = Part()
P.box("moto_gunmetal", (0, 0.50, BORE_Z), (0.165, 0.38, 0.17), None, 0.018)
P.cyl("moto_brass", TRUN - X * 0.13, TRUN + X * 0.13, 0.024, seg=8)
P.cyl("moto_charcoal", (0, 0.315, BORE_Z), (0, 0.13, BORE_Z), 0.066, seg=10)
P.cyl("moto_brass", (0, 0.145, BORE_Z), (0, 0.112, BORE_Z), 0.073, seg=10)
# brass pressure cylinder
CY = 1.775
P.cyl("moto_brass", (0, 0.68, CY), (0, 1.02, CY), 0.09, seg=14)
for y0 in (0.68, 0.835, 0.99):
    P.cyl("moto_gunmetal", (0, y0, CY), (0, y0 + 0.03, CY), 0.096, seg=14)
P.sphere("moto_brass", (0, 1.02, CY), 1.0, (0.083, 0.055, 0.083), 12, 6)
P.cyl("moto_gunmetal", (0, 1.065, CY), (0, 1.095, CY), 0.026, seg=8)
# valve block and gauge on top
P.box("moto_gunmetal", (0, 0.58, 1.862), (0.07, 0.11, 0.04), None, 0.008)
P.cyl("moto_brass", (0, 0.58, 1.875), (0, 0.58, 1.925), 0.032, seg=8)
P.tube("moto_copper", [(0, 0.625, 1.88), (0, 0.69, 1.90), (0, 0.76, 1.862)], 0.013, 6, 0.02)
# rear sight
P.box("moto_charcoal", (0, 0.36, 1.86), (0.024, 0.035, 0.04))
# feed hose, pressure cylinder to receiver
P.tube("moto_joint", [(-0.05, 0.98, 1.70), (-0.09, 0.94, 1.615), (-0.075, 0.78, 1.63), (-0.04, 0.685, 1.69)],
       0.017, 6, 0.04)
# spike magazine on the left of the receiver, above the yoke
P.box("moto_charcoal", (0.135, 0.49, 1.80), (0.10, 0.25, 0.10), None, 0.008)
P.box("moto_gunmetal", (0.135, 0.49, 1.85), (0.11, 0.26, 0.012))
for k in range(5):
    y0 = 0.40 + 0.045 * k
    P.cyl("moto_iron", (0.135, y0, 1.83), (0.14, y0, 1.905), 0.015, seg=4)
    P.cyl("moto_iron", (0.14, y0, 1.905), (0.141, y0, 1.925), 0.027, 0.021, seg=6)
for k in (-1, 1):
    P.rivet((0.186, 0.49 + 0.09 * k, 1.80), X, 0.011)
gun_body = finish(P, "gun_body", T(TRUN + GD), swivel, shift=GD)

P = Part()
P.cyl("moto_gunmetal", (0, 0.46, BORE_Z), (0, -0.17, BORE_Z), 0.044, seg=10)
P.cyl("moto_brass", (0, 0.02, BORE_Z), (0, -0.015, BORE_Z), 0.05, seg=10)
P.cyl("moto_charcoal", (0, -0.165, BORE_Z), (0, -0.25, BORE_Z), 0.064, seg=10)
P.cyl("moto_brass", (0, -0.152, BORE_Z), (0, -0.172, BORE_Z), 0.069, seg=10)
P.cyl("moto_coal", (0, -0.246, BORE_Z), (0, -0.2515, BORE_Z), 0.04, seg=10)
barrel = finish(P, "gun_barrel", T(BARREL_ROOT + GD), gun_body, shift=GD)
empty("muzzle", T(MUZZLE + GD), barrel, 0.08, 'SINGLE_ARROW')

# ---------------------------------------------------------------- rider (rigid parts)
S_AX = (SHOULDER_C - WAIST).normalized()      # along the spine
F_AX = V((0, -S_AX.z, S_AX.y))                # out of the chest
L = (SHOULDER_C - WAIST).length
CM = basis(X, -F_AX, S_AX)
BELT = V((0, 0.245, 0.89))
P = Part()
P.box("moto_charcoal", (0, 0.26, 0.79), (0.34, 0.25, 0.19), None, 0.045)
P.box("moto_joint", (0, 0.25, 0.885), (0.35, 0.255, 0.04), None, 0.01)
P.box("moto_brass", (0, 0.12, 0.885), (0.07, 0.02, 0.05), None, 0.006)
for s in (1, -1):
    P.sphere("moto_joint", (s * 0.13, 0.23, 0.79), 0.095, u=10, v=6)
    P.sphere("moto_joint", (s * SHX, SHOULDER_C.y, 1.26), 0.085, u=10, v=6)
    # hip plates
    P.box("moto_oxblood", (s * 0.178, 0.27, 0.80), (0.03, 0.20, 0.15), None, 0.01)
# bellows waist
for t in (0.15, 0.55, 0.95):
    P.sphere("moto_joint", BELT + (WAIST - BELT) * t, 1.0, (0.185, 0.165, 0.075), 12, 6, CM)
# chest
chest = []
for t, hu, hv in ((0.0, 0.175, 0.145), (0.3, 0.215, 0.175), (0.7, 0.24, 0.185), (0.95, 0.225, 0.16), (1.12, 0.14, 0.11)):
    chest.append(rrect(WAIST + S_AX * L * t, X, F_AX, hu, hv, 0.07, 3))
P.add(mk_loft(chest), "moto_charcoal")
P.box("moto_oxblood", WAIST + S_AX * L * 0.58 + F_AX * 0.18, (0.30, 0.03, 0.20), CM, 0.01)
P.box("moto_gunmetal", WAIST + S_AX * L * 0.55 - F_AX * 0.18, (0.34, 0.05, 0.27), CM, 0.015)
P.box("moto_oxblood", WAIST + S_AX * L * 0.88 - F_AX * 0.198, (0.27, 0.03, 0.055), CM, 0.006)
P.box("moto_charcoal", WAIST + S_AX * L * 0.42 - F_AX * 0.23, (0.19, 0.08, 0.20), CM, 0.015)
for s in (1, -1):
    a_ = WAIST + S_AX * L * 0.10 - F_AX * 0.255 + X * s * 0.13
    P.cyl("moto_brass", a_, a_ + S_AX * 0.21, 0.042, seg=10)
    P.sphere("moto_brass", a_ + S_AX * 0.21, 0.042, u=10, v=6)
    P.cyl("moto_gunmetal", a_ + S_AX * 0.09, a_ + S_AX * 0.115, 0.046, seg=10)
    for k in (-1, 1):
        P.rivet(WAIST + S_AX * L * (0.58 + 0.25 * k) + F_AX * 0.195 + X * s * 0.125, F_AX, 0.011)
        P.rivet(WAIST + S_AX * L * (0.55 + 0.34 * k) - F_AX * 0.205 + X * s * 0.14, -F_AX, 0.011)
# collar: high at the back and sides, open at the throat
col_ax = (S_AX + Z).normalized()
collar = [(0.115, 0.0), (0.14, 0.0), (0.16, 0.055), (0.146, 0.058)]
P.add(mk_lathe(collar, SHOULDER_C + S_AX * 0.03, col_ax, 12, closed=True, a0=radians(-115), a1=radians(115),
               ref=Y), "moto_oxblood")
P.cyl("moto_joint", SHOULDER_C + V((0, 0.0, -0.01)), HELM + V((0, 0.03, -0.03)), 0.066, seg=10)
torso = finish(P, "rider_torso", T(HIP_C + RD), root, shift=RD)

# head
P = Part()
HY = HELM.y
HS = (0.125, 0.145, 0.135)
P.sphere("moto_gunmetal", HELM, 1.0, HS, 14, 9)
skirt = [(0.108, -0.045), (0.142, -0.125), (0.132, -0.132), (0.10, -0.05)]
P.add(mk_lathe(skirt, HELM + Y * 0.01, Z, 10, closed=True, a0=radians(-105), a1=radians(105), ref=Y), "moto_gunmetal")
crest = []
for a in range(15, 166, 15):
    ar = radians(a)
    crest.append((HY + HS[1] * 1.09 * cos(ar), HELM.z + HS[2] * 1.11 * sin(ar)))
for a in range(165, 14, -15):
    ar = radians(a)
    crest.append((HY + HS[1] * 0.97 * cos(ar), HELM.z + HS[2] * 0.97 * sin(ar)))
P.add(mk_prism(crest, (0, 0, 0), Y, Z, -0.018, 0.018), "moto_charcoal")
for a in (40, 65, 90, 115, 140):
    ar = radians(a)
    for s in (1, -1):
        P.rivet(V((s * 0.038, HY + HS[1] * 0.96 * cos(ar), HELM.z + HS[2] * 0.97 * sin(ar))),
                V((s * 0.28, cos(ar), sin(ar))), 0.010)
# face mask: an angular wedge narrowing to the chin
face = [(-0.095, 0.05), (-0.142, 0.022), (-0.155, -0.035), (-0.122, -0.135), (-0.05, -0.135), (-0.015, -0.055),
        (-0.035, 0.05)]
bm_ = mk_prism([(HY + a, HELM.z + b) for a, b in face], (0, 0, 0), Y, Z, -0.094, 0.094)
for v in bm_.verts:
    if v.co.z < HELM.z - 0.08:
        v.co.x *= 0.5
    elif v.co.y > HY - 0.05:
        v.co.x *= 1.12
bmesh.ops.bevel(bm_, geom=bm_.edges[:], offset=0.012, segments=1, profile=0.5, affect='EDGES')
P.add(bm_, "moto_steel")
P.box("moto_charcoal", (0, HY - 0.142, HELM.z - 0.004), (0.16, 0.014, 0.044))
for s in (1, -1):
    P.box("moto_amber", (s * 0.043, HY - 0.143, HELM.z - 0.003), (0.056, 0.022, 0.018), rot_y(radians(s * 14)))
    # cheek port and breather hose, all on the head
    P.cyl("moto_brass", (s * 0.10, HY - 0.04, 1.425), (s * 0.142, HY - 0.04, 1.425), 0.038, 0.032, seg=10)
    P.cyl("moto_charcoal", (s * 0.142, HY - 0.04, 1.425), (s * 0.147, HY - 0.04, 1.425), 0.021, seg=8)
    P.tube("moto_joint", [(s * 0.13, HY - 0.025, 1.425), (s * 0.172, HY + 0.02, 1.412), (s * 0.16, HY + 0.11, 1.405),
                          (s * 0.08, HY + 0.155, 1.412), (s * 0.03, HY + 0.12, 1.435)], 0.021, 6, 0.04)
head = finish(P, "rider_head", T(NECK + RD), torso, shift=RD)

# arms, modelled reaching the grips
for s, tag in ((1, "L"), (-1, "R")):
    SH = V((s * SHX, SHOULDER_C.y, 1.26))
    G = V((s * GRIP.x, GRIP.y, GRIP.z)) - RD
    gd = V((s * GRIP_DIR.x, GRIP_DIR.y, GRIP_DIR.z))
    D = G - SH
    e = V((s * 0.35, 0.0, -0.94))
    e = (e - D.normalized() * e.dot(D.normalized())).normalized()
    up_len = 0.27
    E = (SH + G) / 2 + e * math.sqrt(max(up_len ** 2 - (D.length / 2) ** 2, 0.0))
    fd = (G - E).normalized()
    Wr = G - fd * 0.06
    P = Part()
    tilt = rot_y(radians(s * 22))
    P.sphere("moto_charcoal", SH + V((s * 0.04, 0, 0.045)), 1.0, (0.135, 0.15, 0.082), 12, 7, tilt)
    P.sphere("moto_oxblood", SH + V((s * 0.085, 0, -0.012)), 1.0, (0.115, 0.135, 0.07), 12, 7, rot_y(radians(s * 40)))
    P.rivet(SH + V((s * 0.01, 0, 0.118)), V((-s * 0.37, 0, 0.93)), 0.013)
    P.cyl("moto_charcoal", SH, E, 0.074, 0.064, seg=8)
    P.sphere("moto_joint", E, 0.07, u=10, v=6)
    P.sphere("moto_gunmetal", E + e * 0.035, 0.064, u=8, v=5)
    P.cyl("moto_gunmetal", E, Wr, 0.072, 0.06, seg=8)
    P.cyl("moto_oxblood", Wr - fd * 0.11, Wr - fd * 0.035, 0.077, 0.069, seg=8)
    hz = gd.cross(fd).normalized()
    hy = hz.cross(gd).normalized()
    P.box("moto_joint", G, (0.10, 0.085, 0.09), basis(gd, hy, hz), 0.016)
    P.box("moto_gunmetal", G + hy * 0.014, (0.094, 0.08, 0.102), basis(gd, hy, hz), 0.012)
    finish(P, "rider_arm_" + tag, T(SH + RD), torso, shift=RD)

# legs, feet on the pegs
for s, tag in ((1, "L"), (-1, "R")):
    HP = V((s * 0.13, 0.23, 0.79))
    K = V((s * 0.30, -0.10, 0.725))
    A = V((s * PEG.x, PEG.y - 0.04, PEG.z + 0.105)) - RD
    td = (K - HP).normalized()
    P = Part()
    P.cyl("moto_charcoal", HP, K, 0.10, 0.08, seg=10)
    tz = (Z - td * Z.dot(td)).normalized()
    tx = td.cross(tz)
    P.box("moto_oxblood", (HP + K) / 2 + tz * 0.072, (0.135, 0.27, 0.045), basis(tx, td, tz), 0.012)
    P.sphere("moto_joint", K, 0.08, u=10, v=6)
    P.sphere("moto_gunmetal", K + V((s * 0.012, -0.04, 0.025)), 1.0, (0.08, 0.082, 0.086), 10, 6)
    P.cyl("moto_gunmetal", K, A, 0.082, 0.06, seg=10)
    sd = (A - K).normalized()
    sf = V((0, -1, 0))
    sf = (sf - sd * sf.dot(sd)).normalized()
    P.box("moto_oxblood", (K + A) / 2 + sf * 0.062, (0.08, 0.03, 0.23), basis(sf.cross(sd), sf, sd), 0.01)
    P.sphere("moto_joint", A, 0.058, u=8, v=5)
    P.box("moto_charcoal", V((s * PEG.x, PEG.y - 0.095, PEG.z + 0.05)) - RD, (0.12, 0.30, 0.10), None, 0.024)
    P.box("moto_gunmetal", V((s * PEG.x, PEG.y - 0.22, PEG.z + 0.053)) - RD, (0.126, 0.08, 0.106), None, 0.024)
    finish(P, "rider_leg_" + tag, T(HP + RD), torso, shift=RD)

# ---------------------------------------------------------------- the rail spike (faces -Y)
COLL = bpy.data.collections.new("motorcycle_projectile")
scene.collection.children.link(COLL)
P = Part()
sq = [(-0.26, 0.0015), (-0.19, 0.012), (-0.02, 0.020), (0.065, 0.022)]
P.add(mk_loft([rrect((0, y, 0), X, Z, h, h, h * 0.25, 1) for y, h in sq]), "moto_iron", flat=True)
head_prof = [(0.0, 0.06), (0.024, 0.06), (0.031, 0.072), (0.024, 0.084), (0.034, 0.096), (0.026, 0.108),
             (0.038, 0.12), (0.03, 0.132), (0.048, 0.146), (0.052, 0.158), (0.042, 0.168), (0.0, 0.168)]
P.add(mk_lathe(head_prof, (0, 0, 0), Y, 10), "moto_iron")
spike = finish(P, "rail_spike", Matrix.Identity(4), None)
# the streak behind it; the game repaints any mesh with "trail" in its name in the team colour
P = Part()
P.add(mk_loft([rrect((0, y, 0), X, Z, h, h, h * 0.3, 1) for y, h in ((0.17, 0.016), (0.5, 0.012), (1.25, 0.002))]),
      "moto_trail", flat=True)
finish(P, "rail_spike_trail", Matrix.Identity(4), spike)

# ---------------------------------------------------------------- scene, save
scene.unit_settings.system = 'METRIC'
scene.render.fps = 24
scene.frame_start, scene.frame_end = 0, 48
scene.render.engine = 'BLENDER_EEVEE_NEXT'
world = bpy.data.worlds.new("World")
scene.world = world
bpy.context.view_layer.update()

tris = 0
for o in bpy.data.objects:
    if o.type == 'MESH' and not o.name.startswith("rail_spike"):
        o.data.calc_loop_triangles()
        tris += len(o.data.loop_triangles)
        print("TRIS", o.name, len(o.data.loop_triangles))
print("TRIS total (bike, rider, gun)", tris)
print("STAND stow angle", round(STAND_ANGLE, 2))
lo = V((9, 9, 9))
hi = V((-9, -9, -9))
for o in bpy.data.collections["motorcycle"].objects:
    if o.type == 'MESH':
        for v in o.data.vertices:
            w = o.matrix_world @ v.co
            lo = V((min(lo.x, w.x), min(lo.y, w.y), min(lo.z, w.z)))
            hi = V((max(hi.x, w.x), max(hi.y, w.y), max(hi.z, w.z)))
print("BOUNDS", [round(v, 3) for v in lo], [round(v, 3) for v in hi])
names = [o.name for o in bpy.data.objects] + [m.name for m in bpy.data.meshes]
print("NAMES unique", len(set(o.name for o in bpy.data.objects)) == len(bpy.data.objects))

bpy.context.preferences.filepaths.save_version = 0
bpy.ops.wm.save_as_mainfile(filepath=OUT)
print("SAVED", OUT)
