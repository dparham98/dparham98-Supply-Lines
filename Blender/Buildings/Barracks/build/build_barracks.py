"""Builds Barracks.blend from nothing: the static armoured print hall.

Run in background Blender:
  blender --background --python build_barracks.py

Everything is rebuilt each run, so edits here never compound. The bay door faces -Y, Z up, base on
Z = 0, left is +X when looking at the door from outside... (left of the viewer is -X). Animation and
effects are added afterwards by animate_barracks.py. The game footprint is 6 x 6 m, so everything
stays within +-3 m of the centre.
"""
import bpy, bmesh, math, os, random
from math import sin, cos, radians, pi
from mathutils import Vector as V, Matrix

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.normpath(os.path.join(HERE, "..", "Barracks.blend"))
DRONE = os.path.normpath(os.path.join(HERE, "..", "..", "..", "Vehicles", "Drone", "Drone.blend"))
X, Y, Z = V((1, 0, 0)), V((0, 1, 0)), V((0, 0, 1))
random.seed(11)

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


material("bar_armour", (0.090, 0.074, 0.046), 0.35, 0.68)      # dark olive-brown plate
material("bar_plate2", (0.105, 0.085, 0.050), 0.35, 0.66)
material("bar_gunmetal", (0.100, 0.092, 0.078), 0.45, 0.55)
material("bar_steel", (0.20, 0.185, 0.165), 0.55, 0.48)
material("bar_tank", (0.15, 0.13, 0.105), 0.5, 0.5)
material("bar_rust", (0.13, 0.052, 0.022), 0.2, 0.85)
material("bar_oxblood", (0.235, 0.030, 0.020), 0.15, 0.58)
material("bar_brass", (0.40, 0.25, 0.08), 0.70, 0.42)
material("bar_copper", (0.44, 0.185, 0.075), 0.70, 0.38)
material("bar_black", (0.020, 0.020, 0.022), 0.10, 0.70)
material("bar_hazard", (0.62, 0.42, 0.035), 0.05, 0.60)
material("bar_interior", (0.030, 0.026, 0.022), 0.30, 0.70)
material("bar_redglow", (0.30, 0.02, 0.01), 0.0, 0.5, (1.0, 0.06, 0.02), 2.2)
material("bar_amber", (0.45, 0.20, 0.04), 0.0, 0.5, (1.0, 0.45, 0.10), 2.0)
material("bar_hot", (0.55, 0.30, 0.10), 0.2, 0.45, (1.0, 0.50, 0.16), 1.2)
material("bar_glass", (0.55, 0.32, 0.10), 0.0, 0.08, alpha=0.28)
material("bar_glowfloor", (0.30, 0.13, 0.03), 0.0, 0.6, (1.0, 0.42, 0.08), 0.7)


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

    def rivet(self, pos, normal, r=0.03, mat="bar_steel"):
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
    for m in FANG_MATS:             # the Barracks wears the fang black on red
        me.materials.append(MATS["bar_black"] if m.name.startswith("team_color") else m)
    return place(bpy.data.objects.new(name, me), Matrix.Identity(4), parent)


def chamfer_poly(hx, hy, ch):
    return [(hx, hy - ch), (hx - ch, hy), (-hx + ch, hy), (-hx, hy - ch),
            (-hx, -hy + ch), (-hx + ch, -hy), (hx - ch, -hy), (hx, -hy + ch)]


def plate_box(part, mat, c, au, av, n, w, h, d, bevel=0.012):
    part.add(mk_box(c, (w, h, d), basis(au, av, n), bevel), mat, True)


def plates(part, o, au, av, n, u0, u1, v0, v1, cols, rows, mat="bar_gunmetal", rust=0.35, gap=0.06):
    """Raised riveted plates on a face. o lies on the face; au, av span it; n points out."""
    o, au, av, n = V(o), V(au), V(av), V(n)
    w, h = (u1 - u0) / cols, (v1 - v0) / rows
    for i in range(cols):
        for j in range(rows):
            c = o + au * (u0 + (i + 0.5) * w) + av * (v0 + (j + 0.5) * h)
            m = mat if mat != "bar_gunmetal" or random.random() < 0.6 else "bar_plate2"
            plate_box(part, m, c + n * 0.02, au, av, n, w - gap, h - gap, 0.04)
            hw, hh = w / 2 - gap / 2 - 0.07, h / 2 - gap / 2 - 0.07
            for su, sv in ((-1, -1), (1, -1), (-1, 1), (1, 1), (0, 1), (0, -1)):
                part.rivet(c + n * 0.04 + au * (su * hw) + av * (sv * hh), n, 0.025)
            if random.random() < rust:
                rw, rh = w * random.uniform(0.3, 0.75), h * random.uniform(0.2, 0.45)
                rc = c + au * random.uniform(-0.2, 0.2) * w + av * (-h / 2 + gap / 2 + rh / 2 + 0.03)
                plate_box(part, "bar_rust", rc + n * 0.042, au, av, n, rw, rh, 0.006, 0.0)


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
                     "bar_hazard" if k % 2 == 0 else "bar_black", True)
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
B = 0.20                 # plinth top
WX, WY = 2.15, 2.60      # wall centre lines
WT = 0.20                # wall thickness
OX, OY = WX + WT / 2, WY + WT / 2      # outer wall faces
EAVE = 2.35              # wall top, where the sloped armour shoulder starts
RTOP = 3.15              # roof deck
INSET = 0.72             # how far the shoulder steps in
DX, DY_ = OX - INSET, OY - INSET       # deck half sizes
SLOPE = math.hypot(INSET, RTOP - EAVE)  # shoulder slope length
DOOR_W, DOOR_TOP = 2.2, 2.60           # 2.4 m clear above the plinth
JX = 1.55                # portal outer half width
PF = -2.93               # portal front face
SKY = (-1.38, -0.06, -1.75, 1.30)      # skylight x0, x1, y0, y1
SKX = (SKY[0] + SKY[1]) / 2
SKR = (SKY[1] - SKY[0]) / 2
SKY_C = (SKY[2] + SKY[3]) / 2
CRADLE = V((SKX, SKY_C, B))
VB = 0.29
VENTS = [(0.42, 0.42), (1.10, 0.42), (0.42, 1.12), (1.10, 1.12)]
PANEL = (0.10, 1.42, -1.82, -0.12)
MAST = V((-1.15, 1.68, RTOP))
TANK = V((-2.62, 0.0, 0.78))
TANK_R = 0.34

scene = bpy.context.scene
scene.name = "Barracks"
COLL = bpy.data.collections.new("barracks")
scene.collection.children.link(COLL)

root = empty("barracks_root", Matrix.Identity(4), None, 0.6)


def shoulder_frame(side):
    """o, au, av, n for one sloped side of the shoulder: o on its lower edge, av up the slope."""
    out = {"+x": X, "-x": -X, "+y": Y, "-y": -Y}[side]
    au = Z.cross(out)
    half = OX if side in ("+x", "-x") else OY
    o = out * half + Z * EAVE
    av = (-out * INSET + Z * (RTOP - EAVE)).normalized()
    return o, au, av, au.cross(av)


# ---------------------------------------------------------------- plinth and ramp
p = Part()
p.box("bar_armour", (0, 0.075, B / 2), (5.70, 5.55, B), bevel=0.03)
p.add(mk_prism([(-OY, 0), (-OY, B), (-2.99, 0)], (0, 0, 0), Y, Z, -1.1, 1.1), "bar_gunmetal", True)
s = V((0, -(2.99 - OY), -B))
hazard(p, (-1.1, -OY, B), X, s.normalized(), V((0, -B, 2.99 - OY)).normalized(), 2.2, s.length, 0.2)
p.box("bar_interior", (0, 0, B + 0.01), (2 * WX - WT, 2 * WY - WT, 0.02))
p.box("bar_glowfloor", (SKX, SKY_C, B + 0.025), (SKY[1] - SKY[0] + 0.5, SKY[3] - SKY[2] + 0.3, 0.02))
for x in (-2.58, 2.58):            # grip strips along the plinth edges
    p.box("bar_steel", (x, 0.075, B + 0.005), (0.16, 5.0, 0.012))
plinth = finish(p, "plinth", T((0, 0, 0)), root)

# ---------------------------------------------------------------- frame: buttresses, portal, bands
p = Part()
for sx in (-1, 1):
    for sy in (-1, 1):
        c = (sx * 2.2, sy * 2.65, 0)
        p.add(mk_prism(chamfer_poly(0.33, 0.33, 0.12), c, X, Y, 0.0, 0.38), "bar_gunmetal", True)
        p.add(mk_prism(chamfer_poly(0.29, 0.29, 0.10), c, X, Y, 0.38, EAVE + 0.25), "bar_armour", True)
        p.add(mk_prism(chamfer_poly(0.32, 0.32, 0.11), c, X, Y, EAVE + 0.25, EAVE + 0.37), "bar_gunmetal", True)
        p.add(mk_prism(chamfer_poly(0.2, 0.2, 0.07), c, X, Y, EAVE + 0.37, EAVE + 0.44), "bar_gunmetal", True)
        for z in (0.9, 1.75):
            p.add(mk_prism(chamfer_poly(0.31, 0.31, 0.105), c, X, Y, z, z + 0.12), "bar_steel", True)
        d = V((sx, sy, 0)).normalized()
        for z in (0.7, 1.35, 2.2):
            p.rivet(V(c) + d * 0.338 + Z * z, d, 0.03)
# the gatehouse portal around the bay door
for sx in (-1, 1):
    poly = [(1.1, 0), (JX, 0), (JX, 2.78), (JX - 0.27, 3.08), (1.1, 3.08)]
    poly = [(sx * u, v) for u, v in poly]
    p.add(mk_prism(poly, (0, 0, 0), X, Z, -PF, 2.25), "bar_gunmetal", True)
    plates(p, (sx * (1.1 + JX) / 2, PF, 0), X, Z, -Y, -0.17, 0.17, 0.35, 2.55, 1, 2, "bar_armour", 0.5)
    q = V((sx * (JX + 0.05), -2.78, 1.55))
    p.box("bar_black", q, (0.1, 0.16, 0.3))
    p.box("bar_amber", q + X * sx * 0.03, (0.06, 0.1, 0.22))
p.box("bar_gunmetal", (0, (PF - 2.25) / 2, (DOOR_TOP + 3.08) / 2), (2.2, -2.25 - PF, 3.08 - DOOR_TOP))
p.box("bar_black", (0, PF - 0.03, 2.84), (1.1, 0.06, 0.26), bevel=0.01)
p.box("bar_redglow", (0, PF - 0.05, 2.84), (0.96, 0.03, 0.13))
p.box("bar_gunmetal", (0, PF + 0.06, 3.1), (2 * JX - 0.5, 0.16, 0.05))
for x in (-0.75, 0.75):
    p.rivet((x, PF, 2.68), -Y, 0.03)
    p.rivet((x, PF, 3.0), -Y, 0.03)
# skirting band and eave trim
for z0, z1 in ((B, 0.46), (EAVE - 0.07, EAVE + 0.02)):
    zc, h = (z0 + z1) / 2, z1 - z0
    p.box("bar_gunmetal", (0, OY + 0.035, zc), (2 * WX - 0.4, 0.07, h), bevel=0.01)
    for sx in (-1, 1):
        p.box("bar_gunmetal", (sx * (OX + 0.035), 0, zc), (0.07, 2 * WY - 0.4, h), bevel=0.01)
        p.box("bar_gunmetal", (sx * (JX + 1.9) / 2, -OY - 0.035, zc), (1.9 - JX, 0.07, h), bevel=0.01)
frame = finish(p, "frame", T((0, 0, 0)), root)

# ---------------------------------------------------------------- walls: plates, slot lights, pipes, hatch
p = Part()
H = EAVE - B
p.box("bar_armour", (0, WY, B + H / 2), (2 * WX, WT, H))
for sx in (-1, 1):
    p.box("bar_armour", (sx * WX, 0, B + H / 2), (WT, 2 * WY, H))
    p.box("bar_armour", (sx * (1.1 + OX) / 2, -WY, B + H / 2), (OX - 1.1, WT, H))
plates(p, (0, OY, 0), -X, Z, Y, -1.88, 1.88, 0.5, EAVE - 0.08, 3, 2, rust=0.55)
plates(p, (OX, 0, 0), Y, Z, X, -2.33, 2.33, 0.5, EAVE - 0.08, 4, 2, rust=0.55)
plates(p, (-OX, 0, 0), -Y, Z, -X, -2.33, 2.33, 0.5, EAVE - 0.08, 4, 2, rust=0.55)
for sx in (-1, 1):
    plates(p, (sx * (JX + 1.9) / 2, -OY, 0), X, Z, -Y, -0.17, 0.17, 0.5, EAVE - 0.08, 1, 2, rust=0.6)
# the sloped armour shoulder: a solid ring, lower outer edge, top edge, lower inner edge
outer = rrect((0, 0, EAVE), X, Y, OX + 0.02, OY + 0.02, 0.3, 1)
top = rrect((0, 0, RTOP), X, Y, DX, DY_, 0.16, 1)
inner = rrect((0, 0, EAVE), X, Y, DX, DY_, 0.16, 1)
p.add(mk_loft([outer, top, inner, outer], cap=False), "bar_armour", True)
for side, cols in (("+x", 4), ("-x", 4), ("+y", 3)):
    o, au, av, n = shoulder_frame(side)
    half = (OY if side in ("+x", "-x") else OX) - 0.45
    plates(p, o, au, av, n, -half, half, 0.04, SLOPE - 0.04, cols, 1, rust=0.6)
o, au, av, n = shoulder_frame("-y")
for u0, u1 in ((-1.9, -1.6), (1.6, 1.9)):
    plates(p, o, au, av, n, u0, u1, 0.04, SLOPE - 0.04, 1, 1, rust=0.6)
# red slot lights in armoured housings
for sx in (-1, 1):
    for y in (-1.2, 1.2):
        q = V((sx * (OX + 0.06), y, EAVE - 0.4))
        p.box("bar_gunmetal", q, (0.12, 0.8, 0.26), bevel=0.02)
        p.box("bar_black", q + X * sx * 0.06, (0.02, 0.66, 0.15))
        p.box("bar_redglow", q + X * sx * 0.07, (0.02, 0.58, 0.08))
for sx in (-1, 1):
    q = V((sx * 1.86, -OY - 0.06, EAVE - 0.5))
    p.box("bar_gunmetal", q, (0.34, 0.12, 0.3), bevel=0.02)
    p.box("bar_redglow", q - Y * 0.07, (0.24, 0.02, 0.12))
# pipes on the far (+X) side
PX = OX + 0.14
p.tube("bar_brass", [(PX, 1.95, B), (PX, 1.95, 1.6), (PX, -2.05, 1.6), (PX, -2.05, 0.75),
                     (PX - 0.14, -2.05, 0.75)], 0.065, 10, 0.18)
p.tube("bar_copper", [(PX + 0.02, 1.70, B), (PX + 0.02, 1.70, EAVE - 0.2), (OX, 1.70, EAVE - 0.2)], 0.05, 8, 0.15)
for y in (-1.6, -0.5, 0.6, 1.5):
    p.box("bar_steel", (PX - 0.06, y, 1.6), (0.14, 0.06, 0.16))
for z in (0.7, 1.15, 1.95 - 0.2):
    p.box("bar_steel", (PX - 0.05, 1.82, z), (0.12, 0.42, 0.06))
p.cyl("bar_brass", (PX, -0.9, 1.6), (PX + 0.08, -0.9, 1.6), 0.1, seg=10)
p.cyl("bar_steel", (PX + 0.08, -0.9, 1.6), (PX + 0.11, -0.9, 1.6), 0.15, seg=12)
# the back: a service hatch and a copper run
hc = V((0.75, OY + 0.07, B + 0.85))
p.box("bar_gunmetal", hc, (0.9, 0.1, 1.7), bevel=0.02)
p.box("bar_oxblood", hc + Y * 0.055, (0.7, 0.02, 1.5))
p.box("bar_steel", hc + Y * 0.07 + X * -0.25 + Z * 0.1, (0.06, 0.04, 0.3))
p.tube("bar_copper", [(-1.75, OY + 0.13, B), (-1.75, OY + 0.13, 1.25), (0.15, OY + 0.13, 1.25),
                      (0.15, OY + 0.13, B)], 0.055, 8, 0.15)
walls = finish(p, "walls", T((0, 0, 0)), root)

# ---------------------------------------------------------------- roof deck
p = Part()
zc, h = (EAVE + RTOP) / 2, RTOP - EAVE
p.box("bar_armour", ((-DX + SKY[0]) / 2, 0, zc), (SKY[0] + DX, 2 * DY_, h))
p.box("bar_armour", ((SKY[1] + DX) / 2, 0, zc), (DX - SKY[1], 2 * DY_, h))
p.box("bar_armour", (SKX, (SKY[2] - DY_) / 2, zc), (SKY[1] - SKY[0], SKY[2] + DY_, h))
p.box("bar_armour", (SKX, (SKY[3] + DY_) / 2, zc), (SKY[1] - SKY[0], DY_ - SKY[3], h))
plates(p, (0, 0, RTOP), X, Y, Z, SKY[1] + 0.06, DX - 0.04, 0.0, DY_ - 0.04, 2, 2, rust=0.3)
plates(p, (0, 0, RTOP), X, Y, Z, -DX + 0.04, SKY[0] - 0.06, -DY_ + 0.04, SKY[3] + 0.06, 1, 3, rust=0.3)
# the red fang panel
pc = V(((PANEL[0] + PANEL[1]) / 2, (PANEL[2] + PANEL[3]) / 2, RTOP + 0.03))
p.box("bar_steel", pc, (PANEL[1] - PANEL[0] + 0.1, PANEL[3] - PANEL[2] + 0.1, 0.06), bevel=0.015)
p.box("bar_oxblood", pc + Z * 0.02, (PANEL[1] - PANEL[0], PANEL[3] - PANEL[2], 0.05), bevel=0.008)
for u in (-1, 1):
    for v in (-1, 0, 1):
        p.rivet(pc + V((u * (PANEL[1] - PANEL[0] + 0.05) / 2, v * 0.9, 0.03)), Z, 0.025)
# the skylight frame and ribs
for x in SKY[:2]:
    p.box("bar_steel", (x, SKY_C, RTOP + 0.05), (0.12, SKY[3] - SKY[2] + 0.12, 0.1), bevel=0.01)
for y in SKY[2:]:
    p.box("bar_steel", (SKX, y, RTOP + 0.05), (SKY[1] - SKY[0] + 0.12, 0.12, 0.1), bevel=0.01)
for i in range(6):
    y = SKY[2] + (SKY[3] - SKY[2]) * i / 5
    p.tube("bar_steel", arc(SKX, RTOP, SKR + 0.02, y, 10), 0.038, 6)
p.tube("bar_steel", [(SKX, SKY[2], RTOP + SKR + 0.03), (SKX, SKY[3], RTOP + SKR + 0.03)], 0.04, 6)
roof = finish(p, "roof", T((0, 0, 0)), root)
fang("roof_fang", pc + Z * 0.052, Z, -Y, 1.45, roof)

p = Part()
p.add(mk_vault(SKX, RTOP + 0.02, SKR - 0.03, SKY[2], SKY[3], 14), "bar_glass")
skylight = finish(p, "skylight", T((SKX, SKY_C, RTOP)), roof)

# ---------------------------------------------------------------- bay door, origin on its top edge
p = Part()
DY = -WY
N = 20
SL = (DOOR_TOP - B) / N
p.box("bar_black", (0, DY + 0.05, (B + DOOR_TOP) / 2), (DOOR_W + 0.1, 0.02, DOOR_TOP - B))
for k in range(N):
    z = DOOR_TOP - (k + 0.5) * SL
    p.add(mk_box((0, DY, z), (DOOR_W + 0.12, 0.07, SL + 0.004), None, 0.014), "bar_gunmetal", True)
p.add(mk_box((0, DY - 0.01, B + 0.06), (DOOR_W + 0.12, 0.10, 0.12), None, 0.015), "bar_steel", True)
hazard(p, (-DOOR_W / 2 - 0.06, DY - 0.036, B + 0.13), X, Z, -Y, DOOR_W + 0.12, 0.24, 0.2)
for x in (-0.55, 0.55):
    p.box("bar_steel", (x, DY - 0.045, B + 0.55), (0.32, 0.03, 0.06))
bay_door = finish(p, "bay_door", T((0, DY, DOOR_TOP)), root)

# ---------------------------------------------------------------- print cradle
p = Part()
p.cyl("bar_gunmetal", CRADLE, CRADLE + Z * 0.16, 0.66, 0.62, seg=20)
p.cyl("bar_amber", CRADLE + Z * 0.16, CRADLE + Z * 0.18, 0.5, seg=20)
p.tube("bar_steel", [CRADLE + V((0.55 * cos(a), 0.55 * sin(a), 0.17)) for a in
                     [2 * pi * i / 20 for i in range(21)]], 0.03, 6)
for i in range(4):
    a = pi / 4 + i * pi / 2
    q = CRADLE + V((0.54 * cos(a), 0.54 * sin(a), 0))
    p.cyl("bar_gunmetal", q, q + Z * 2.1, 0.05, seg=8)
    p.box("bar_amber", q - V((cos(a), sin(a), 0)) * 0.05 + Z * 1.12, (0.03, 0.03, 1.7), rot_z(a))
p.tube("bar_steel", [CRADLE + V((0.54 * cos(a), 0.54 * sin(a), 2.1)) for a in
                     [2 * pi * i / 20 for i in range(21)]], 0.045, 6)
for i in range(4):                 # cables up to the deck
    a = i * pi / 2
    q = CRADLE + V((0.54 * cos(a), 0.54 * sin(a), 2.1))
    p.tube("bar_black", [q, q + Z * 0.12 + V((cos(a), sin(a), 0)) * 0.06,
                         CRADLE + V((0.62 * cos(a), 0.62 * sin(a), EAVE - B + 0.02))], 0.025, 5)
cradle = finish(p, "cradle", T(CRADLE), root)

p = Part()
HZ = CRADLE + Z * 0.3
p.tube("bar_brass", [HZ + V((0.47 * cos(a), 0.47 * sin(a), 0)) for a in
                     [2 * pi * i / 24 for i in range(25)]], 0.05, 6)
for i in range(4):
    a = i * pi / 2
    q = HZ + V((0.41 * cos(a), 0.41 * sin(a), 0))
    p.box("bar_amber", q, (0.1, 0.1, 0.05), rot_z(a))
print_head = finish(p, "print_head", T(HZ), cradle)

p = Part()
F = CRADLE + Z * 0.18
for sx in (-1, 1):
    p.box("bar_hot", F + V((sx * 0.11, -0.02, 0.05)), (0.13, 0.26, 0.10), bevel=0.02)
    p.box("bar_hot", F + V((sx * 0.11, 0, 0.47)), (0.14, 0.16, 0.78), bevel=0.03)
    p.box("bar_hot", F + V((sx * 0.30, 0, 1.12)), (0.11, 0.12, 0.66), bevel=0.03)
    p.sphere("bar_hot", F + V((sx * 0.27, 0, 1.44)), 0.1, u=8, v=6)
p.box("bar_hot", F + V((0, 0, 1.17)), (0.44, 0.26, 0.62), bevel=0.05)
p.box("bar_hot", F + V((0, 0.0, 1.55)), (0.08, 0.08, 0.1))
p.sphere("bar_hot", F + V((0, 0, 1.68)), 0.12, scale=(1, 1.05, 1.15), u=10, v=8)
print_figure = finish(p, "print_figure", T(F), cradle)

# ---------------------------------------------------------------- roof vents, each with a turning fan
for i, (vx, vy) in enumerate(VENTS):
    c = V((vx, vy, RTOP))
    p = Part()
    p.add(mk_lathe([(VB - 0.05, 0.02), (VB + 0.02, 0.0), (VB, 0.40), (VB + 0.045, 0.42), (VB + 0.045, 0.48),
                    (VB - 0.03, 0.48), (VB - 0.03, 0.06)], c, Z, 18, closed=True), "bar_gunmetal")
    p.cyl("bar_copper", c + Z * 0.16, c + Z * 0.22, VB + 0.012, seg=18)
    p.cyl("bar_black", c + Z * 0.08, c + Z * 0.1, VB - 0.03, seg=16)
    for a in (0, pi / 2):
        d = V((cos(a), sin(a), 0))
        p.beam("bar_steel", c + Z * 0.48 - d * VB, c + Z * 0.48 + d * VB, 0.03, 0.03)
    for k in range(6):
        a = 2 * pi * k / 6
        p.rivet(c + V((cos(a), sin(a), 0)) * (VB + 0.045) + Z * 0.45, V((cos(a), sin(a), 0)), 0.018)
    vent = finish(p, "vent_%02d" % (i + 1), T(c), root)
    p = Part()
    fc = c + Z * 0.3
    p.cyl("bar_gunmetal", fc - Z * 0.04, fc + Z * 0.04, 0.06, seg=10)
    for k in range(5):
        R = rot_z(2 * pi * k / 5)
        p.box("bar_brass", fc + R.to_3x3() @ V((0.16, 0, 0)), (0.22, 0.1, 0.014), R @ rot_x(radians(28)))
    finish(p, "vent_fan_%02d" % (i + 1), T(fc), vent)

# ---------------------------------------------------------------- comms mast on its turret
p = Part()
legs = []
for k in range(3):
    a = pi / 2 + 2 * pi * k / 3
    legs.append((V((cos(a), sin(a), 0)) * 0.2 + Z * 0.3, V((cos(a), sin(a), 0)) * 0.05))
TOPZ = 2.75
p.cyl("bar_gunmetal", MAST, MAST + Z * 0.22, 0.33, 0.3, seg=16)
p.cyl("bar_steel", MAST + Z * 0.22, MAST + Z * 0.3, 0.26, 0.22, seg=16)
for k in range(8):
    a = 2 * pi * k / 8
    p.rivet(MAST + V((cos(a), sin(a), 0)) * 0.325 + Z * 0.12, V((cos(a), sin(a), 0)), 0.02)
for lo, hi in legs:
    p.cyl("bar_gunmetal", MAST + lo, MAST + hi + Z * TOPZ, 0.032, 0.02, seg=6)
LV = 6
for j in range(LV):
    t0, t1 = j / LV, (j + 1) / LV
    for k in range(3):
        L0, L1 = legs[k], legs[(k + 1) % 3]
        a0 = L0[0].lerp(L0[1] + Z * TOPZ, t0)
        b0 = L1[0].lerp(L1[1] + Z * TOPZ, t0)
        b1 = L1[0].lerp(L1[1] + Z * TOPZ, t1)
        p.cyl("bar_steel", MAST + a0, MAST + b1, 0.011, seg=4)
        p.cyl("bar_steel", MAST + a0, MAST + b0, 0.013, seg=4)
p.cyl("bar_steel", MAST + Z * TOPZ, MAST + Z * (TOPZ + 0.5), 0.016, 0.007, seg=6)
p.beam("bar_gunmetal", MAST + Z * (TOPZ - 0.4) - X * 0.28, MAST + Z * (TOPZ - 0.4) + X * 0.28, 0.04, 0.04)
for sx in (-1, 1):
    p.cyl("bar_steel", MAST + Z * (TOPZ - 0.4) + X * 0.28 * sx, MAST + Z * (TOPZ - 0.8) + X * 0.28 * sx, 0.011, seg=4)
for sx in (-1, 1):
    p.sphere("bar_redglow", MAST + Z * (TOPZ - 0.4) + X * 0.3 * sx + Z * 0.04, 0.035, u=6, v=4)
p.add(mk_lathe([(0.0, 0.0), (0.14, 0.04), (0.19, 0.1)], MAST + Z * 1.7 + Y * 0.12, Y, 14), "bar_steel")
mast = finish(p, "mast", T(MAST), root)
p = Part()
p.sphere("bar_redglow", MAST + Z * (TOPZ + 0.07), 0.07, u=10, v=6)
p.cyl("bar_black", MAST + Z * (TOPZ - 0.02), MAST + Z * (TOPZ + 0.02), 0.055, seg=10)
finish(p, "mast_light", T(MAST + Z * TOPZ), mast)

# ---------------------------------------------------------------- coolant tank
p = Part()
TL = 1.2
p.cyl("bar_tank", TANK - Y * TL, TANK + Y * TL, TANK_R, seg=18)
for sy in (-1, 1):
    p.sphere("bar_tank", TANK + Y * TL * sy, TANK_R, scale=(1, 0.5, 1), u=18, v=10)
for y in (-0.95, 0.95):
    p.cyl("bar_copper", TANK + Y * (y - 0.06), TANK + Y * (y + 0.06), TANK_R + 0.02, seg=18)
p.add(mk_lathe([(TANK_R - 0.005, -0.32), (TANK_R + 0.02, -0.32), (TANK_R + 0.02, 0.32), (TANK_R - 0.005, 0.32)],
               TANK, Y, 6, closed=True, a0=-0.75, a1=0.75, ref=-X), "bar_oxblood", True)
for y in (-0.62, 0.62):            # saddles with hazard faces
    p.box("bar_gunmetal", (TANK.x, y, 0.22), (0.6, 0.16, 0.44), bevel=0.02)
    p.box("bar_armour", (TANK.x, y, 0.03), (0.74, 0.3, 0.06), bevel=0.01)
    hazard(p, (TANK.x - 0.3, y - 0.08, 0.06), X, Z, -Y, 0.6, 0.3, 0.12)
for sy in (-1, 1):                 # rust streaks at the ends
    p.cyl("bar_rust", TANK + Y * sy * (TL - 0.05), TANK + Y * sy * (TL + 0.04), TANK_R + 0.004, seg=18)
for y, mat in ((-0.42, "bar_copper"), (0.42, "bar_brass")):
    q = TANK + Y * y
    p.tube(mat, [q + Z * (TANK_R - 0.02), q + Z * (TANK_R + 0.5), q + Z * (TANK_R + 0.5) + X * 0.3,
                 V((-OX + 0.02, q.y, q.z + TANK_R + 0.5))], 0.055, 8, 0.12)
    p.cyl("bar_steel", q + Z * (TANK_R + 0.2), q + Z * (TANK_R + 0.26), 0.08, seg=10)
p.tube("bar_copper", [TANK + Y * (TL + 0.12), TANK + Y * (TL + 0.4), TANK + Y * (TL + 0.4) + X * 0.36,
                      V((-OX + 0.02, TANK.y + TL + 0.4, TANK.z))], 0.05, 8, 0.1)
tank = finish(p, "tank", T(TANK), root)
fang("tank_fang", TANK + V((-TANK_R - 0.03, 0.0, 0.0)), -X, -Y, 0.5, tank)

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
