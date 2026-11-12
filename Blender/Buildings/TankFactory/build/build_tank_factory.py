"""Builds TankFactory.blend from nothing: the static armoured vehicle plant.

Run in background Blender:
  blender --background --python build_tank_factory.py

Everything is rebuilt each run, so edits here never compound. The vehicle door faces -Y, Z up, base on
Z = 0. Animation and effects are added afterwards by animate_tank_factory.py. The game footprint is
8 x 8 m, so everything stays within +-3.9 m of the centre. The helpers are the Barracks' own
(Blender/Buildings/Barracks/build/build_barracks.py), so the two buildings share one look.
"""
import bpy, bmesh, math, os, random
from math import sin, cos, radians, pi
from mathutils import Vector as V, Matrix

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.normpath(os.path.join(HERE, "..", "TankFactory.blend"))
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


material("fac_armour", (0.090, 0.074, 0.046), 0.35, 0.68)      # dark olive-brown plate
material("fac_plate2", (0.105, 0.085, 0.050), 0.35, 0.66)
material("fac_gunmetal", (0.100, 0.092, 0.078), 0.45, 0.55)
material("fac_steel", (0.20, 0.185, 0.165), 0.55, 0.48)
material("fac_tank", (0.15, 0.13, 0.105), 0.5, 0.5)
material("fac_rust", (0.13, 0.052, 0.022), 0.2, 0.85)
material("fac_oxblood", (0.235, 0.030, 0.020), 0.15, 0.58)
material("fac_brass", (0.40, 0.25, 0.08), 0.70, 0.42)
material("fac_copper", (0.44, 0.185, 0.075), 0.70, 0.38)
material("fac_black", (0.020, 0.020, 0.022), 0.10, 0.70)
material("fac_hazard", (0.62, 0.42, 0.035), 0.05, 0.60)
material("fac_interior", (0.16, 0.15, 0.13), 0.30, 0.75, (0.55, 0.50, 0.42), 0.2)   # floodlit bay floor, so the well reads from above
material("fac_redglow", (0.30, 0.02, 0.01), 0.0, 0.5, (1.0, 0.06, 0.02), 2.2)
material("fac_amber", (0.45, 0.20, 0.04), 0.0, 0.5, (1.0, 0.45, 0.10), 2.0)
material("fac_hot", (0.55, 0.30, 0.10), 0.2, 0.45, (1.0, 0.50, 0.16), 1.2)
material("fac_glass", (0.55, 0.32, 0.10), 0.0, 0.08, alpha=0.28)
material("fac_primer", (0.30, 0.28, 0.22), 0.4, 0.6, (0.50, 0.42, 0.30), 0.25)   # the new vehicle shell
material("fac_turntable", (0.22, 0.21, 0.19), 0.5, 0.5, (0.45, 0.42, 0.36), 0.25)
material("fac_glowfloor", (0.30, 0.13, 0.03), 0.0, 0.6, (1.0, 0.42, 0.08), 0.7)


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

    def rivet(self, pos, normal, r=0.03, mat="fac_steel"):
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
    for m in FANG_MATS:             # the factory wears the fang black on red
        me.materials.append(MATS["fac_black"] if m.name.startswith("team_color") else m)
    return place(bpy.data.objects.new(name, me), Matrix.Identity(4), parent)


def chamfer_poly(hx, hy, ch):
    return [(hx, hy - ch), (hx - ch, hy), (-hx + ch, hy), (-hx, hy - ch),
            (-hx, -hy + ch), (-hx + ch, -hy), (hx - ch, -hy), (hx, -hy + ch)]


def plate_box(part, mat, c, au, av, n, w, h, d, bevel=0.012):
    part.add(mk_box(c, (w, h, d), basis(au, av, n), bevel), mat, True)


def plates(part, o, au, av, n, u0, u1, v0, v1, cols, rows, mat="fac_gunmetal", rust=0.35, gap=0.06):
    """Raised riveted plates on a face. o lies on the face; au, av span it; n points out."""
    o, au, av, n = V(o), V(au), V(av), V(n)
    w, h = (u1 - u0) / cols, (v1 - v0) / rows
    for i in range(cols):
        for j in range(rows):
            c = o + au * (u0 + (i + 0.5) * w) + av * (v0 + (j + 0.5) * h)
            m = mat if mat != "fac_gunmetal" or random.random() < 0.6 else "fac_plate2"
            plate_box(part, m, c + n * 0.02, au, av, n, w - gap, h - gap, 0.04)
            hw, hh = w / 2 - gap / 2 - 0.07, h / 2 - gap / 2 - 0.07
            for su, sv in ((-1, -1), (1, -1), (-1, 1), (1, 1), (0, 1), (0, -1)):
                part.rivet(c + n * 0.04 + au * (su * hw) + av * (sv * hh), n, 0.025)
            if random.random() < rust:
                rw, rh = w * random.uniform(0.3, 0.75), h * random.uniform(0.2, 0.45)
                rc = c + au * random.uniform(-0.2, 0.2) * w + av * (-h / 2 + gap / 2 + rh / 2 + 0.03)
                plate_box(part, "fac_rust", rc + n * 0.042, au, av, n, rw, rh, 0.006, 0.0)


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
                     "fac_hazard" if k % 2 == 0 else "fac_black", True)
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
B = 0.22                 # plinth top
WX, WY = 2.85, 3.05      # wall centre lines
WT = 0.22                # wall thickness
OX, OY = WX + WT / 2, WY + WT / 2      # outer wall faces
EAVE = 3.45              # wall top, where the sloped armour shoulder starts
RTOP = 4.05              # roof deck
INSET = 0.62             # how far the shoulder steps in
DX, DY_ = OX - INSET, OY - INSET       # deck half sizes
SLOPE = math.hypot(INSET, RTOP - EAVE)
DOOR_W, DOOR_TOP = 3.4, B + 3.0        # 3.0 m clear above the plinth
JX = 2.3                 # portal outer half width
PF = -3.55               # portal front face
PTOP = 4.15              # portal top
OPEN = (-1.45, 1.45, -2.05, 0.75)      # the assembly well in the roof: x0, x1, y0, y1
TT = V((0.0, -0.15, B))  # turntable centre, under the back of the well (the camera looks in from the front)
TT_R = 1.5
TT_TOP = B + 0.05
RAIL_X = 1.72            # crane rails along Y on the side strips
RAIL_Z = RTOP + 0.12
BRIDGE_Z = RTOP + 1.45   # crane bridge, high enough to carry parts over the roof
PARK_Y = 1.75            # the crane parks over the rear strip
PANEL = (-0.40, 1.45, 0.98, 2.36)
VB = 0.27
VENTS = [(-1.02, 1.28), (-1.02, 2.04)]
STACKS = [V((OX + 0.36, 1.45, 0)), V((OX + 0.36, 2.3, 0))]
STACK_R = 0.2
STACK_TOP = 5.6
TANK = V((-OX - 0.46, 0.25, 0.80))
TANK_R = 0.40
TANK_L = 1.25
BEACONS = [V((-1.95, PF + 0.32, PTOP)), V((1.95, PF + 0.32, PTOP))]

scene = bpy.context.scene
scene.name = "TankFactory"
COLL = bpy.data.collections.new("tank_factory")
scene.collection.children.link(COLL)

root = empty("tank_factory_root", Matrix.Identity(4), None, 0.8)


def shoulder_frame(side):
    out = {"+x": X, "-x": -X, "+y": Y, "-y": -Y}[side]
    au = Z.cross(out)
    half = OX if side in ("+x", "-x") else OY
    o = out * half + Z * EAVE
    av = (-out * INSET + Z * (RTOP - EAVE)).normalized()
    return o, au, av, au.cross(av)


# ---------------------------------------------------------------- plinth, apron and the floor
p = Part()
p.box("fac_armour", (0, 0.10, B / 2), (7.65, 7.40, B), bevel=0.03)
p.add(mk_prism([(-3.70, 0), (-3.70, B), (-3.90, 0)], (0, 0, 0), Y, Z, -1.75, 1.75), "fac_gunmetal", True)
s = V((0, -0.20, -B))
hazard(p, (-1.75, -3.70, B), X, s.normalized(), V((0, -B, 0.20)).normalized(), 3.5, s.length, 0.24)
p.box("fac_interior", (0, 0, B + 0.008), (2 * WX - WT, 2 * WY - WT, 0.016))
# the apron between the door and the ramp, with tread plates and guide lines
p.box("fac_steel", (0, -3.42, B + 0.008), (DOOR_W, 0.5, 0.016))
for x in (-1.15, 1.15):
    p.box("fac_hazard", (x, -1.6, B + 0.02), (0.08, 2.4, 0.01))
# a glowing ring round the turntable pit
p.add(mk_lathe([(TT_R + 0.04, 0.012), (TT_R + 0.14, 0.012), (TT_R + 0.14, 0.03), (TT_R + 0.04, 0.03)],
               TT, Z, 40, closed=True), "fac_amber", True)
for x in (-3.55, 3.55):            # grip strips along the plinth edges
    p.box("fac_steel", (x, 0.10, B + 0.005), (0.16, 6.8, 0.012))
plinth = finish(p, "plinth", T((0, 0, 0)), root)

# ---------------------------------------------------------------- frame: buttresses, portal, bands
p = Part()
for sx in (-1, 1):
    for sy in (-1, 1):
        c = (sx * 2.92, sy * 3.12, 0)
        p.add(mk_prism(chamfer_poly(0.36, 0.36, 0.13), c, X, Y, 0.0, 0.42), "fac_gunmetal", True)
        p.add(mk_prism(chamfer_poly(0.31, 0.31, 0.11), c, X, Y, 0.42, EAVE + 0.25), "fac_armour", True)
        p.add(mk_prism(chamfer_poly(0.34, 0.34, 0.12), c, X, Y, EAVE + 0.25, EAVE + 0.38), "fac_gunmetal", True)
        for z in (1.1, 2.3):
            p.add(mk_prism(chamfer_poly(0.33, 0.33, 0.115), c, X, Y, z, z + 0.13), "fac_steel", True)
        d = V((sx, sy, 0)).normalized()
        for z in (0.8, 1.7, 2.9):
            p.rivet(V(c) + d * 0.36 + Z * z, d, 0.032)
# the portal round the vehicle door
for sx in (-1, 1):
    poly = [(1.75, 0), (JX, 0), (JX, PTOP - 0.32), (JX - 0.32, PTOP), (1.75, PTOP)]
    poly = [(sx * u, v) for u, v in poly]
    p.add(mk_prism(poly, (0, 0, 0), X, Z, -PF, WY - 0.1), "fac_gunmetal", True)
    plates(p, (sx * (1.75 + JX) / 2, PF, 0), X, Z, -Y, -0.22, 0.22, 0.4, PTOP - 0.45, 1, 3, "fac_armour", 0.5)
    for z in (0.5, 1.6, 2.7):      # hazard bands on the door jambs
        q = V((sx * 1.73, -WY - 0.25, z))
        p.box("fac_hazard", q, (0.05, 0.45, 0.24))
        p.box("fac_black", q + Z * 0.24, (0.05, 0.45, 0.24))
p.box("fac_gunmetal", (0, (PF - WY + 0.1) / 2, (DOOR_TOP + PTOP) / 2), (3.5, -WY + 0.1 - PF, PTOP - DOOR_TOP))
p.box("fac_black", (0, PF - 0.03, (DOOR_TOP + PTOP) / 2), (2.0, 0.06, 0.34), bevel=0.01)
p.box("fac_redglow", (0, PF - 0.05, (DOOR_TOP + PTOP) / 2), (1.84, 0.03, 0.15))
for x in (-1.2, 1.2):
    p.rivet((x, PF, DOOR_TOP + 0.15), -Y, 0.032)
    p.rivet((x, PF, PTOP - 0.15), -Y, 0.032)
for b in BEACONS:                  # beacon bases on the portal
    p.cyl("fac_gunmetal", b - Z * 0.02, b + Z * 0.1, 0.17, 0.15, seg=12)
# skirting band and eave trim
for z0, z1 in ((B, 0.5), (EAVE - 0.08, EAVE + 0.02)):
    zc, h = (z0 + z1) / 2, z1 - z0
    p.box("fac_gunmetal", (0, OY + 0.035, zc), (2 * WX - 0.45, 0.07, h), bevel=0.01)
    for sx in (-1, 1):
        p.box("fac_gunmetal", (sx * (OX + 0.035), 0, zc), (0.07, 2 * WY - 0.45, h), bevel=0.01)
frame = finish(p, "frame", T((0, 0, 0)), root)

# ---------------------------------------------------------------- walls: plates, slot lights, pipes
p = Part()
H = EAVE - B
p.box("fac_armour", (0, WY, B + H / 2), (2 * WX, WT, H))
for sx in (-1, 1):
    p.box("fac_armour", (sx * WX, 0, B + H / 2), (WT, 2 * WY, H))
    p.box("fac_armour", (sx * (1.75 + OX) / 2, -WY, B + H / 2), (OX - 1.75, WT, H))
plates(p, (0, OY, 0), -X, Z, Y, -2.5, 2.5, 0.55, EAVE - 0.1, 4, 3, rust=0.5)
plates(p, (OX, 0, 0), Y, Z, X, -2.75, 2.75, 0.55, EAVE - 0.1, 5, 3, rust=0.5)
plates(p, (-OX, 0, 0), -Y, Z, -X, -2.75, 2.75, 0.55, EAVE - 0.1, 5, 3, rust=0.5)
for sx in (-1, 1):
    plates(p, (sx * (JX + OX) / 2, -OY, 0), X, Z, -Y, -(OX - JX) / 2 + 0.05, (OX - JX) / 2 - 0.05,
           0.55, EAVE - 0.1, 1, 3, rust=0.6)
# the sloped armour shoulder, with the assembly well cut out of the deck afterwards
outer = rrect((0, 0, EAVE), X, Y, OX + 0.02, OY + 0.02, 0.32, 1)
top = rrect((0, 0, RTOP), X, Y, DX, DY_, 0.16, 1)
inner = rrect((0, 0, EAVE), X, Y, DX, DY_, 0.16, 1)
p.add(mk_loft([outer, top, inner, outer], cap=False), "fac_armour", True)
for side, cols in (("+x", 5), ("-x", 5), ("+y", 4)):
    o, au, av, n = shoulder_frame(side)
    half = (OY if side in ("+x", "-x") else OX) - 0.5
    plates(p, o, au, av, n, -half, half, 0.04, SLOPE - 0.04, cols, 1, rust=0.55)
o, au, av, n = shoulder_frame("-y")
for u0, u1 in ((-2.45, -2.05), (2.05, 2.45)):
    plates(p, o, au, av, n, u0, u1, 0.04, SLOPE - 0.04, 1, 1, rust=0.6)
# red slot lights
for sx in (-1, 1):
    for y in (-1.5, 0.0, 1.5):
        q = V((sx * (OX + 0.06), y, EAVE - 0.45))
        p.box("fac_gunmetal", q, (0.12, 0.8, 0.26), bevel=0.02)
        p.box("fac_black", q + X * sx * 0.06, (0.02, 0.66, 0.15))
        p.box("fac_redglow", q + X * sx * 0.07, (0.02, 0.58, 0.08))
# the exhaust stacks' manifold and the pipes along the +X side
PX = OX + 0.14
p.tube("fac_copper", [(PX, -2.4, B), (PX, -2.4, 1.2), (PX, 0.9, 1.2), (STACKS[0].x - 0.05, 0.9, 1.2)], 0.07, 10, 0.2)
p.tube("fac_brass", [(PX + 0.02, -1.4, B), (PX + 0.02, -1.4, 2.2), (OX, -1.4, 2.2)], 0.05, 8, 0.15)
for y in (-1.9, -0.8, 0.3):
    p.box("fac_steel", (PX - 0.06, y, 1.2), (0.14, 0.06, 0.17))
p.cyl("fac_brass", (PX, -0.25, 1.2), (PX + 0.08, -0.25, 1.2), 0.11, seg=10)
p.cyl("fac_steel", (PX + 0.08, -0.25, 1.2), (PX + 0.11, -0.25, 1.2), 0.16, seg=12)
# a service hatch at the back
hc = V((-1.0, OY + 0.07, B + 0.95))
p.box("fac_gunmetal", hc, (1.0, 0.1, 1.9), bevel=0.02)
p.box("fac_oxblood", hc + Y * 0.055, (0.8, 0.02, 1.7))
p.box("fac_steel", hc + Y * 0.07 + X * 0.28 + Z * 0.1, (0.06, 0.04, 0.3))
walls = finish(p, "walls", T((0, 0, 0)), root)

# ---------------------------------------------------------------- roof deck round the assembly well
p = Part()
zc, h = (EAVE + RTOP) / 2, RTOP - EAVE
p.box("fac_armour", ((-DX + OPEN[0]) / 2, 0, zc), (OPEN[0] + DX, 2 * DY_, h))
p.box("fac_armour", ((OPEN[1] + DX) / 2, 0, zc), (DX - OPEN[1], 2 * DY_, h))
p.box("fac_armour", (0, (OPEN[2] - DY_) / 2, zc), (OPEN[1] - OPEN[0], OPEN[2] + DY_, h))
p.box("fac_armour", (0, (OPEN[3] + DY_) / 2, zc), (OPEN[1] - OPEN[0], DY_ - OPEN[3], h))
plates(p, (0, 0, RTOP), X, Y, Z, -DX + 0.04, OPEN[0] - 0.06, -DY_ + 0.04, DY_ - 0.04, 1, 4, rust=0.3)
plates(p, (0, 0, RTOP), X, Y, Z, OPEN[1] + 0.06, DX - 0.04, -DY_ + 0.04, DY_ - 0.04, 1, 4, rust=0.3)
plates(p, (0, 0, RTOP), X, Y, Z, OPEN[0], PANEL[0] - 0.08, OPEN[3] + 0.06, DY_ - 0.04, 1, 2, rust=0.3)
# hazard trim round the well's lip
for y0, sgn in ((OPEN[2], -1), (OPEN[3], 1)):
    hazard(p, (OPEN[0], y0, RTOP), X, Y * sgn, Z, OPEN[1] - OPEN[0], 0.16, 0.2)
for x0, sgn in ((OPEN[0], -1), (OPEN[1], 1)):
    hazard(p, (x0, OPEN[2], RTOP), Y, X * sgn, Z, OPEN[3] - OPEN[2], 0.16, 0.2)
# the red fang panel
pc = V(((PANEL[0] + PANEL[1]) / 2, (PANEL[2] + PANEL[3]) / 2, RTOP + 0.03))
p.box("fac_steel", pc, (PANEL[1] - PANEL[0] + 0.1, PANEL[3] - PANEL[2] + 0.1, 0.06), bevel=0.015)
p.box("fac_oxblood", pc + Z * 0.02, (PANEL[1] - PANEL[0], PANEL[3] - PANEL[2], 0.05), bevel=0.008)
for u in (-1, 0, 1):
    for v in (-1, 1):
        p.rivet(pc + V((u * 0.85, v * (PANEL[3] - PANEL[2] + 0.05) / 2, 0.03)), Z, 0.025)
# crane rails on sleepers along both side strips
for sx in (-1, 1):
    x = sx * RAIL_X
    p.box("fac_steel", (x, 0, RAIL_Z), (0.12, 2 * DY_ - 0.2, 0.1), bevel=0.01)
    p.box("fac_gunmetal", (x, 0, RTOP + 0.035), (0.26, 2 * DY_ - 0.2, 0.07))
    for k in range(9):
        y = -DY_ + 0.3 + k * (2 * DY_ - 0.6) / 8
        p.box("fac_gunmetal", (x, y, RTOP + 0.05), (0.4, 0.12, 0.1))
    for y in (-DY_ + 0.12, DY_ - 0.12):          # end stops
        p.box("fac_hazard", (x, y, RAIL_Z + 0.08), (0.2, 0.1, 0.22))
roof = finish(p, "roof", T((0, 0, 0)), root)
fang("roof_fang", pc + Z * 0.052, Z, -Y, 1.25, roof)

# ---------------------------------------------------------------- vehicle door, origin on its top edge
p = Part()
DY = -WY
N = 22
SL = (DOOR_TOP - B) / N
p.box("fac_black", (0, DY + 0.06, (B + DOOR_TOP) / 2), (DOOR_W + 0.1, 0.02, DOOR_TOP - B))
for k in range(N):
    z = DOOR_TOP - (k + 0.5) * SL
    p.add(mk_box((0, DY, z), (DOOR_W + 0.12, 0.08, SL + 0.004), None, 0.015), "fac_gunmetal", True)
p.add(mk_box((0, DY - 0.01, B + 0.07), (DOOR_W + 0.12, 0.11, 0.14), None, 0.015), "fac_steel", True)
hazard(p, (-DOOR_W / 2 - 0.06, DY - 0.041, B + 0.15), X, Z, -Y, DOOR_W + 0.12, 0.28, 0.24)
for x in (-1.0, 0.0, 1.0):
    p.box("fac_steel", (x, DY - 0.05, B + 0.75), (0.36, 0.03, 0.07))
door = finish(p, "bay_door", T((0, DY, DOOR_TOP)), root)

# ---------------------------------------------------------------- turntable
p = Part()
p.cyl("fac_turntable", TT - Z * 0.04, TT + Z * 0.05, TT_R, seg=40)
p.cyl("fac_steel", TT + Z * 0.05, TT + Z * 0.06, 0.45, seg=20)
for k in range(8):                 # tread spokes
    a = 2 * pi * k / 8
    d = V((cos(a), sin(a), 0))
    p.add(mk_box(TT + d * 0.95 + Z * 0.055, (1.0, 0.1, 0.012), rot_z(a)), "fac_steel", True)
for sx in (-1, 1):                 # guide rails the vehicle sits on
    p.box("fac_hazard", TT + V((sx * 0.62, 0, 0.06)), (0.06, 2.4, 0.015))
turntable = finish(p, "turntable", T(TT), root)
# The turntable is also a lift: the vehicle is assembled up near the roof, where the camera sees into the
# well, then lowered to the floor. The ram is one metre long from the floor: its Z scale is the lift height.
p = Part()
p.cyl("fac_steel", TT, TT + Z * 1.0, 0.22, seg=14)
p.cyl("fac_gunmetal", TT, TT + Z * 0.08, 0.42, seg=14)
finish(p, "lift_ram", T(TT), root)

# ---------------------------------------------------------------- the vehicle shell being assembled
VO = V((TT.x, TT.y, TT_TOP))       # its origin sits on the turntable, front toward -Y
vehicle = empty("vehicle", T(VO), root, 0.4)
p = Part()                         # lower hull with a sloped glacis
hull = [(-0.62, 0.95), (0.62, 0.95), (0.62, -0.75), (0.45, -1.08), (-0.45, -1.08), (-0.62, -0.75)]
p.add(mk_prism(hull, VO + Z * 0.22, X, Y, 0.0, 0.5), "fac_primer", True)
p.add(mk_prism([(-0.05, 0.0), (0.42, 0.0), (0.0, 0.5)], VO + V((0, -1.08, 0.22)), -Y, Z, -0.45, 0.45), "fac_primer", True)
p.box("fac_hot", VO + V((0, -0.82, 0.62)), (0.7, 0.06, 0.05))           # fresh weld seams
p.box("fac_hot", VO + V((0, 0.4, 0.73)), (1.1, 0.05, 0.03))
finish(p, "veh_hull", T(VO), vehicle)
for side in (-1, 1):
    p = Part()
    tx = side * 0.84
    p.add(mk_box(VO + V((tx, -0.05, 0.33)), (0.34, 2.15, 0.5), None, 0.08), "fac_black", True)
    for k in range(5):
        y = -0.85 + k * 0.4
        p.cyl("fac_steel", VO + V((tx - 0.18, y, 0.25)), VO + V((tx + 0.18, y, 0.25)), 0.16, seg=10)
    p.box("fac_primer", VO + V((tx, -0.05, 0.6)), (0.4, 2.2, 0.06))
    finish(p, "veh_track_%s" % ("l" if side < 0 else "r"), T(VO + V((tx, 0, 0))), vehicle)
p = Part()                         # upper deck and engine grille
p.add(mk_box(VO + V((0, 0.25, 0.86)), (1.22, 1.35, 0.3), None, 0.05), "fac_primer", True)
for k in range(5):
    p.box("fac_black", VO + V((-0.35 + k * 0.175, 0.62, 1.015)), (0.1, 0.5, 0.02))
p.box("fac_hot", VO + V((0, -0.42, 0.72)), (1.0, 0.04, 0.03))
finish(p, "veh_deck", T(VO + Z * 0.72), vehicle)
p = Part()                         # turret with a stub barrel
p.add(mk_prism(chamfer_poly(0.42, 0.45, 0.16), VO + V((0, 0.05, 0)), X, Y, 1.01, 1.33), "fac_primer", True)
p.cyl("fac_gunmetal", VO + V((0, -0.38, 1.17)), VO + V((0, -1.25, 1.17)), 0.07, seg=10)
p.cyl("fac_gunmetal", VO + V((0, -1.2, 1.17)), VO + V((0, -1.32, 1.17)), 0.1, seg=10)
p.box("fac_hot", VO + V((0, 0.05, 1.335)), (0.5, 0.04, 0.01))
finish(p, "veh_turret", T(VO + Z * 1.01), vehicle)

# ---------------------------------------------------------------- the crane: gantry, trolley, hook
GO = V((0.0, PARK_Y, RAIL_Z + 0.05))
p = Part()
for sx in (-1, 1):
    x = sx * RAIL_X
    p.box("fac_gunmetal", (x, PARK_Y, RAIL_Z + 0.16), (0.3, 0.9, 0.22), bevel=0.02)        # end truck
    for sy in (-1, 1):
        p.cyl("fac_steel", (x - 0.16, PARK_Y + sy * 0.3, RAIL_Z + 0.1), (x + 0.16, PARK_Y + sy * 0.3, RAIL_Z + 0.1), 0.09, seg=10)
        p.beam("fac_hazard", (x, PARK_Y + sy * 0.35, RAIL_Z + 0.26), (x, PARK_Y + sy * 0.08, BRIDGE_Z - 0.1), 0.12, 0.12)
p.box("fac_hazard", (0, PARK_Y - 0.2, BRIDGE_Z), (2 * RAIL_X + 0.3, 0.16, 0.26), bevel=0.02)   # twin girders
p.box("fac_hazard", (0, PARK_Y + 0.2, BRIDGE_Z), (2 * RAIL_X + 0.3, 0.16, 0.26), bevel=0.02)
for k in range(7):
    x = -RAIL_X + 0.25 + k * (2 * RAIL_X - 0.5) / 6
    p.box("fac_black", (x, PARK_Y - 0.2, BRIDGE_Z), (0.06, 0.17, 0.27))
    p.box("fac_black", (x, PARK_Y + 0.2, BRIDGE_Z), (0.06, 0.17, 0.27))
p.box("fac_gunmetal", (-RAIL_X + 0.1, PARK_Y, BRIDGE_Z + 0.2), (0.4, 0.5, 0.25), bevel=0.02)  # winch motor
p.sphere("fac_redglow", (-RAIL_X + 0.1, PARK_Y, BRIDGE_Z + 0.36), 0.05, u=8, v=5)
gantry = finish(p, "gantry", T(GO), root)
TO = V((0.0, PARK_Y, BRIDGE_Z + 0.13))
p = Part()
p.box("fac_gunmetal", TO + Z * 0.05, (0.6, 0.62, 0.2), bevel=0.03)
p.cyl("fac_steel", TO + V((-0.25, 0, -0.08)), TO + V((0.25, 0, -0.08)), 0.11, seg=12)
trolley = finish(p, "trolley", T(TO), gantry)
HO = TO - Z * 0.2
p = Part()                         # the cable, one metre long from its top: its Z scale is the drop
p.cyl("fac_black", HO, HO - Z * 1.0, 0.025, seg=6)
finish(p, "hook_cable", T(HO), trolley)
HOOK_REST = 0.25
p = Part()
HB = HO - Z * HOOK_REST
p.box("fac_hazard", HB - Z * 0.12, (0.26, 0.2, 0.24), bevel=0.03)
p.beam("fac_steel", HB - Z * 0.25 - X * 0.45, HB - Z * 0.25 + X * 0.45, 0.07, 0.07)          # spreader bar
for sx in (-1, 1):
    p.cyl("fac_steel", HB - Z * 0.25 + X * 0.43 * sx, HB - Z * 0.45 + X * 0.43 * sx, 0.02, seg=5)
finish(p, "hook", T(HB), trolley)

# ---------------------------------------------------------------- roof vents, each with a turning fan
for i, (vx, vy) in enumerate(VENTS):
    c = V((vx, vy, RTOP))
    p = Part()
    p.add(mk_lathe([(VB - 0.05, 0.02), (VB + 0.02, 0.0), (VB, 0.40), (VB + 0.045, 0.42), (VB + 0.045, 0.48),
                    (VB - 0.03, 0.48), (VB - 0.03, 0.06)], c, Z, 18, closed=True), "fac_gunmetal")
    p.cyl("fac_copper", c + Z * 0.16, c + Z * 0.22, VB + 0.012, seg=18)
    p.cyl("fac_black", c + Z * 0.08, c + Z * 0.1, VB - 0.03, seg=16)
    for a in (0, pi / 2):
        d = V((cos(a), sin(a), 0))
        p.beam("fac_steel", c + Z * 0.48 - d * VB, c + Z * 0.48 + d * VB, 0.03, 0.03)
    vent = finish(p, "vent_%02d" % (i + 1), T(c), root)
    p = Part()
    fc = c + Z * 0.3
    p.cyl("fac_gunmetal", fc - Z * 0.04, fc + Z * 0.04, 0.06, seg=10)
    for k in range(5):
        R = rot_z(2 * pi * k / 5)
        p.box("fac_brass", fc + R.to_3x3() @ V((0.15, 0, 0)), (0.2, 0.1, 0.014), R @ rot_x(radians(28)))
    finish(p, "vent_fan_%02d" % (i + 1), T(fc), vent)

# ---------------------------------------------------------------- exhaust stacks with flapping rain caps
p = Part()
for k, s in enumerate(STACKS):
    p.cyl("fac_gunmetal", s, s + Z * 0.5, STACK_R + 0.1, STACK_R + 0.06, seg=14)
    p.cyl("fac_steel", s + Z * 0.5, s + Z * STACK_TOP, STACK_R, STACK_R * 0.9, seg=14)
    p.cyl("fac_black", s + Z * (STACK_TOP - 0.35), s + Z * STACK_TOP, STACK_R * 0.93, seg=14)
    for z in (1.5, 2.6, 3.7, 4.7):
        p.cyl("fac_copper", s + Z * (z - 0.05), s + Z * (z + 0.05), STACK_R + 0.03, seg=14)
    for z in (1.5, 3.0):           # brackets back to the wall
        p.box("fac_steel", V((OX + 0.12, s.y, z)), (0.24, 0.08, 0.08))
    p.box("fac_steel", V((OX + 0.12, s.y, 4.4)), (0.24, 0.08, 0.08))
p.box("fac_steel", ((STACKS[0].x), (STACKS[0].y + STACKS[1].y) / 2, 4.7), (0.06, STACKS[1].y - STACKS[0].y, 0.06))
stacks = finish(p, "stacks", T((STACKS[0] + STACKS[1]) / 2), root)
for k, s in enumerate(STACKS):
    hinge = s + Z * STACK_TOP + Y * STACK_R
    p = Part()
    p.add(mk_box(s + Z * (STACK_TOP + 0.03), (STACK_R * 2.3, STACK_R * 2.3, 0.04), None, 0.01), "fac_gunmetal", True)
    p.cyl("fac_steel", hinge - X * 0.12, hinge + X * 0.12, 0.03, seg=6)
    finish(p, "stack_cap_%02d" % (k + 1), T(hinge), stacks)

# ---------------------------------------------------------------- fuel tank on the -X side
p = Part()
p.cyl("fac_tank", TANK - Y * TANK_L, TANK + Y * TANK_L, TANK_R, seg=20)
for sy in (-1, 1):
    p.sphere("fac_tank", TANK + Y * TANK_L * sy, TANK_R, scale=(1, 0.5, 1), u=20, v=10)
for y in (-1.0, 0.0, 1.0):
    p.cyl("fac_copper", TANK + Y * (y - 0.06), TANK + Y * (y + 0.06), TANK_R + 0.02, seg=20)
p.add(mk_lathe([(TANK_R - 0.005, -0.42), (TANK_R + 0.02, -0.42), (TANK_R + 0.02, 0.42), (TANK_R - 0.005, 0.42)],
               TANK, Y, 6, closed=True, a0=-0.75, a1=0.75, ref=-X), "fac_oxblood", True)
for y in (-0.75, 0.75):
    p.box("fac_gunmetal", (TANK.x, TANK.y + y, 0.22), (0.66, 0.16, 0.44), bevel=0.02)
    p.box("fac_armour", (TANK.x, TANK.y + y, 0.03), (0.8, 0.3, 0.06), bevel=0.01)
    hazard(p, (TANK.x - 0.33, TANK.y + y - 0.08, 0.06), X, Z, -Y, 0.66, 0.3, 0.12)
for sy in (-1, 1):
    p.cyl("fac_rust", TANK + Y * sy * (TANK_L - 0.05), TANK + Y * sy * (TANK_L + 0.04), TANK_R + 0.004, seg=20)
for y, mat in ((-0.5, "fac_copper"), (0.5, "fac_brass")):
    q = TANK + Y * y
    p.tube(mat, [q + Z * (TANK_R - 0.02), q + Z * (TANK_R + 0.45), q + Z * (TANK_R + 0.45) + X * 0.3,
                 V((-OX + 0.02, q.y, q.z + TANK_R + 0.45))], 0.055, 8, 0.12)
tank = finish(p, "tank", T(TANK), root)
fang("tank_fang", TANK + V((-TANK_R - 0.03, 0.0, 0.0)), -X, -Y, 0.55, tank)

# ---------------------------------------------------------------- rotating amber beacons on the portal
for k, b in enumerate(BEACONS):
    p = Part()
    c = b + Z * 0.1
    p.cyl("fac_glass", c, c + Z * 0.22, 0.12, 0.11, seg=12)
    p.add(mk_box(c + Z * 0.11 + X * 0.05, (0.06, 0.16, 0.16)), "fac_amber", True)
    p.cyl("fac_gunmetal", c + Z * 0.22, c + Z * 0.26, 0.13, seg=12)
    finish(p, "beacon_%02d" % (k + 1), T(c), root)

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
