"""Builds Generator.blend from nothing: the static armoured steam generator.

Run in background Blender:
  blender --background --python build_generator.py

Everything is rebuilt each run, so edits here never compound. The firebox door faces -Y, Z up, base on
Z = 0. Animation and effects are added afterwards by animate_generator.py. The game footprint is
3 x 3 m, so everything stays within +-1.45 m of the centre. The helpers are the Barracks' own
(Blender/Buildings/Barracks/build/build_barracks.py), so the buildings share one look.
"""
import bpy, bmesh, math, os, random
from math import sin, cos, radians, pi
from mathutils import Vector as V, Matrix

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.normpath(os.path.join(HERE, "..", "Generator.blend"))
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


material("gen_armour", (0.090, 0.074, 0.046), 0.35, 0.68)      # dark olive-brown plate
material("gen_plate2", (0.105, 0.085, 0.050), 0.35, 0.66)
material("gen_gunmetal", (0.100, 0.092, 0.078), 0.45, 0.55)
material("gen_steel", (0.20, 0.185, 0.165), 0.55, 0.48)
material("gen_tank", (0.15, 0.13, 0.105), 0.5, 0.5)
material("gen_rust", (0.13, 0.052, 0.022), 0.2, 0.85)
material("gen_oxblood", (0.235, 0.030, 0.020), 0.15, 0.58)
material("gen_brass", (0.40, 0.25, 0.08), 0.70, 0.42)
material("gen_copper", (0.44, 0.185, 0.075), 0.70, 0.38)
material("gen_black", (0.020, 0.020, 0.022), 0.10, 0.70)
material("gen_hazard", (0.62, 0.42, 0.035), 0.05, 0.60)
material("gen_redglow", (0.30, 0.02, 0.01), 0.0, 0.5, (1.0, 0.06, 0.02), 2.2)
material("gen_amber", (0.45, 0.20, 0.04), 0.0, 0.5, (1.0, 0.45, 0.10), 2.0)
material("gen_glass", (0.55, 0.32, 0.10), 0.0, 0.08, alpha=0.28)
material("gen_fire", (0.60, 0.20, 0.03), 0.0, 0.6, (1.0, 0.30, 0.04), 1.4)     # the firebox glow behind the grate
material("gen_coilhot", (0.55, 0.24, 0.08), 0.6, 0.4, (1.0, 0.36, 0.08), 0.9)   # coils lit while it runs
material("gen_arc", (0.55, 0.75, 1.0), 0.0, 0.3, (0.55, 0.80, 1.0), 6.0)        # the spark between the terminals
material("gen_white", (0.62, 0.60, 0.55), 0.0, 0.35)                            # porcelain insulators
material("gen_coal", (0.025, 0.024, 0.026), 0.1, 0.8)
material("gen_smoke", (0.16, 0.155, 0.15), 0.0, 0.95, alpha=0.8)


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

    def rivet(self, pos, normal, r=0.03, mat="gen_steel"):
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
    for m in FANG_MATS:             # the generator wears the fang black on red
        me.materials.append(MATS["gen_black"] if m.name.startswith("team_color") else m)
    return place(bpy.data.objects.new(name, me), Matrix.Identity(4), parent)


def chamfer_poly(hx, hy, ch):
    return [(hx, hy - ch), (hx - ch, hy), (-hx + ch, hy), (-hx, hy - ch),
            (-hx, -hy + ch), (-hx + ch, -hy), (hx - ch, -hy), (hx, -hy + ch)]


def plate_box(part, mat, c, au, av, n, w, h, d, bevel=0.012):
    part.add(mk_box(c, (w, h, d), basis(au, av, n), bevel), mat, True)


def plates(part, o, au, av, n, u0, u1, v0, v1, cols, rows, mat="gen_gunmetal", rust=0.35, gap=0.06):
    """Raised riveted plates on a face. o lies on the face; au, av span it; n points out."""
    o, au, av, n = V(o), V(au), V(av), V(n)
    w, h = (u1 - u0) / cols, (v1 - v0) / rows
    for i in range(cols):
        for j in range(rows):
            c = o + au * (u0 + (i + 0.5) * w) + av * (v0 + (j + 0.5) * h)
            m = mat if mat != "gen_gunmetal" or random.random() < 0.6 else "gen_plate2"
            plate_box(part, m, c + n * 0.02, au, av, n, w - gap, h - gap, 0.04)
            hw, hh = w / 2 - gap / 2 - 0.07, h / 2 - gap / 2 - 0.07
            for su, sv in ((-1, -1), (1, -1), (-1, 1), (1, 1), (0, 1), (0, -1)):
                part.rivet(c + n * 0.04 + au * (su * hw) + av * (sv * hh), n, 0.025)
            if random.random() < rust:
                rw, rh = w * random.uniform(0.3, 0.75), h * random.uniform(0.2, 0.45)
                rc = c + au * random.uniform(-0.2, 0.2) * w + av * (-h / 2 + gap / 2 + rh / 2 + 0.03)
                plate_box(part, "gen_rust", rc + n * 0.042, au, av, n, rw, rh, 0.006, 0.0)


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
                     "gen_hazard" if k % 2 == 0 else "gen_black", True)
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
B = 0.15                 # plinth top
FB = V((-0.30, -0.15, 0))              # firebox centre on the ground
FBW, FBD, FBH = 1.30, 1.30, 1.35       # firebox size, top at FBH
FRONT = FB.y - FBD / 2                 # firebox front face
BOIL = V((-0.30, 0.05, 1.90))          # boiler drum centre, axis along Y
BOIL_R, BOIL_L = 0.55, 0.80            # radius and half length
CHIM = V((-0.30, 0.55, BOIL.z + BOIL_R - 0.08))
CHIM_TOP = 4.10
CHIM_R = 0.16
HOP = V((-1.13, -0.15, 0))             # fuel hopper
HOP_TOP, HOP_BOT = 1.70, 0.95
DYN = V((0.62, -0.15, 0.95))           # dynamo, axis along X
DYN_R = 0.38
FW = V((1.05, -0.15, 0.95))            # flywheel centre, axis along X
FW_R = 0.72
CRANK = 0.28                           # crank pin radius
ROD = 0.70                             # connecting rod length
CX = 1.24                              # the crosshead's line, outside the flywheel
CYL = (0.92, 1.38)                     # steam cylinder along Y
MAST = V((0.55, 1.15, B))
MAST_TOP = 3.30

scene = bpy.context.scene
scene.name = "Generator"
COLL = bpy.data.collections.new("generator")
scene.collection.children.link(COLL)

root = empty("generator_root", Matrix.Identity(4), None, 0.5)

# ---------------------------------------------------------------- plinth
p = Part()
p.box("gen_armour", (0, 0, B / 2), (2.86, 2.86, B), bevel=0.025)
hazard(p, (-1.25, -1.43, B), X, Y, Z, 2.5, 0.16, 0.18)
for sx in (-1, 1):
    p.box("gen_steel", (sx * 1.3, 0.05, B + 0.005), (0.12, 2.4, 0.012))
p.box("gen_gunmetal", (FW.x, FW.y, B + 0.06), (0.5, 1.1, 0.12), bevel=0.02)      # flywheel pit cover
plinth = finish(p, "plinth", T((0, 0, 0)), root)

# ---------------------------------------------------------------- firebox: plated furnace with a grated door
p = Part()
c = FB + Z * (B + (FBH - B) / 2)
p.box("gen_armour", c, (FBW, FBD, FBH - B), bevel=0.03)
plates(p, (FB.x, FRONT, 0), X, Z, -Y, -FBW / 2 + 0.05, FBW / 2 - 0.05, B + 0.05, FBH - 0.05, 2, 2, "gen_gunmetal", 0.4)
plates(p, (FB.x, FB.y + FBD / 2, 0), -X, Z, Y, -FBW / 2 + 0.05, FBW / 2 - 0.05, B + 0.05, FBH - 0.05, 2, 2, rust=0.5)
plates(p, (FB.x + FBW / 2, FB.y, 0), Y, Z, X, -FBD / 2 + 0.05, FBD / 2 - 0.05, B + 0.05, FBH - 0.05, 2, 2, rust=0.5)
# the fire door: a frame round a grate, the glow sits behind it
GD = V((FB.x, FRONT - 0.04, 0.68))
p.box("gen_black", GD + Y * 0.02, (0.72, 0.04, 0.56))
for sx in (-1, 1):
    p.box("gen_steel", GD + X * sx * 0.38, (0.08, 0.1, 0.66), bevel=0.01)
for sz in (-1, 1):
    p.box("gen_steel", GD + Z * sz * 0.31, (0.84, 0.1, 0.08), bevel=0.01)
for k in range(6):
    p.box("gen_black", GD + X * (-0.28 + k * 0.112) - Y * 0.03, (0.04, 0.03, 0.54))
for sx in (-1, 1):                     # hinges
    p.cyl("gen_steel", GD + X * sx * 0.45 + Z * 0.18, GD + X * sx * 0.45 - Z * 0.18, 0.035, seg=8)
# an ash drawer under it and a band round the top
p.box("gen_gunmetal", (FB.x, FRONT - 0.03, B + 0.14), (0.7, 0.08, 0.18), bevel=0.01)
p.box("gen_steel", (FB.x, FRONT - 0.035, B + 0.14), (0.25, 0.04, 0.04))
p.box("gen_gunmetal", FB + Z * (FBH - 0.05), (FBW + 0.06, FBD + 0.06, 0.1), bevel=0.015)
# the boiler saddles on top
for y in (-0.45, 0.55):
    p.box("gen_gunmetal", (BOIL.x, BOIL.y + y, FBH + 0.12), (0.9, 0.16, 0.24), bevel=0.02)
firebox = finish(p, "firebox", T(FB), root)
p = Part()
p.box("gen_fire", GD + Y * 0.005, (0.64, 0.02, 0.5))
finish(p, "fire_glow", T(GD + Y * 0.005), firebox)
p = Part()                             # the pilot lamp, top left of the door
PL = V((FB.x - 0.48, FRONT - 0.03, 1.12))
p.box("gen_gunmetal", PL + Y * 0.03, (0.14, 0.06, 0.14), bevel=0.01)
p.sphere("gen_amber", PL - Y * 0.01, 0.045, u=8, v=6)
finish(p, "pilot", T(PL), firebox)

# ---------------------------------------------------------------- boiler drum, gauge, safety valve
p = Part()
p.cyl("gen_tank", BOIL - Y * BOIL_L, BOIL + Y * BOIL_L, BOIL_R, seg=22)
for sy in (-1, 1):
    p.sphere("gen_tank", BOIL + Y * BOIL_L * sy, BOIL_R, scale=(1, 0.35, 1), u=22, v=10)
for y in (-0.55, 0.0, 0.55):
    p.cyl("gen_copper", BOIL + Y * (y - 0.04), BOIL + Y * (y + 0.04), BOIL_R + 0.018, seg=22)
for sy in (-1, 1):
    p.cyl("gen_rust", BOIL + Y * sy * (BOIL_L - 0.04), BOIL + Y * sy * (BOIL_L + 0.03), BOIL_R + 0.004, seg=22)
for k in range(10):                    # rivet rows along the seam
    a = 2 * pi * k / 10
    for y in (-0.6, 0.6):
        d = V((cos(a), 0, sin(a)))
        p.rivet(BOIL + Y * y + d * (BOIL_R + 0.02), d, 0.02)
# the pressure gauge on the front cap
GC = BOIL - Y * (BOIL_L + BOIL_R * 0.35 + 0.02) + Z * 0.05
p.cyl("gen_brass", GC + Y * 0.06, GC - Y * 0.02, 0.15, seg=16)
p.cyl("gen_glass", GC - Y * 0.02, GC - Y * 0.03, 0.12, seg=16)
p.box("gen_redglow", GC - Y * 0.03 + V((0.07, 0, 0.06)), (0.05, 0.005, 0.02), rot_y(radians(-40)))
p.tube("gen_copper", [BOIL + V((0.35, -0.5, 0.35)), BOIL + V((0.62, -0.5, 0.35)), BOIL + V((0.62, -0.5, -0.6)),
                      DYN + V((-0.1, -0.1, 0.35))], 0.04, 8, 0.1)
boiler = finish(p, "boiler", T(BOIL), root)
p = Part()
p.box("gen_black", GC - Y * 0.035 + Z * 0.04, (0.015, 0.005, 0.1))
finish(p, "gauge_needle", T(GC - Y * 0.035), boiler)
VV = BOIL + V((0.05, -0.3, BOIL_R))
p = Part()
p.cyl("gen_brass", VV, VV + Z * 0.16, 0.06, seg=10)
p.cyl("gen_steel", VV + Z * 0.16, VV + Z * 0.2, 0.09, seg=10)
p.box("gen_steel", VV + Z * 0.21 + X * 0.16, (0.32, 0.03, 0.03))
p.sphere("gen_gunmetal", VV + Z * 0.21 + X * 0.34, 0.06, u=8, v=6)
finish(p, "valve", T(VV + Z * 0.16), boiler)

# ---------------------------------------------------------------- chimney, rain cap and smoke puffs
p = Part()
p.cyl("gen_gunmetal", CHIM, CHIM + Z * 0.35, CHIM_R + 0.1, CHIM_R + 0.05, seg=14)
p.cyl("gen_black", CHIM - Z * 0.012, CHIM - Z * 0.002, CHIM_R + 0.06, seg=14)      # the bore, seen once it is torn off
p.cyl("gen_steel", CHIM + Z * 0.35, V((CHIM.x, CHIM.y, CHIM_TOP)), CHIM_R, CHIM_R * 0.9, seg=14)
p.cyl("gen_black", V((CHIM.x, CHIM.y, CHIM_TOP - 0.3)), V((CHIM.x, CHIM.y, CHIM_TOP)), CHIM_R * 0.93, seg=14)
for z in (2.95, 3.55):
    p.cyl("gen_copper", V((CHIM.x, CHIM.y, z - 0.04)), V((CHIM.x, CHIM.y, z + 0.04)), CHIM_R + 0.025, seg=14)
for k in range(3):                     # guy wires down to the firebox corners
    a = radians(90 + 120 * k)
    foot = V((FB.x + cos(a) * 0.62, CHIM.y + sin(a) * 0.62 - 0.1, FBH))
    p.cyl("gen_steel", V((CHIM.x, CHIM.y, 3.2)), foot, 0.008, seg=4)
chimney = finish(p, "chimney", T(CHIM), root)
CH = V((CHIM.x, CHIM.y + CHIM_R, CHIM_TOP))
p = Part()
p.add(mk_box(V((CHIM.x, CHIM.y, CHIM_TOP + 0.03)), (CHIM_R * 2.4, CHIM_R * 2.4, 0.035), None, 0.01), "gen_gunmetal", True)
p.cyl("gen_steel", CH - X * 0.1, CH + X * 0.1, 0.025, seg=6)
finish(p, "chimney_cap", T(CH), chimney)
for k in range(3):                     # smoke puffs, shown only while it runs
    q = V((CHIM.x, CHIM.y, CHIM_TOP + 0.2))
    p = Part()
    p.add(mk_ico(q, 0.22, sub=2), "gen_smoke")
    finish(p, "puff_%d" % (k + 1), T(q), chimney)

# ---------------------------------------------------------------- fuel hopper with the fang
p = Part()
top = [HOP + V((sx * 0.28, sy * 0.48, HOP_TOP)) for sx, sy in ((1, 1), (-1, 1), (-1, -1), (1, -1))]
bot = [HOP + V((sx * 0.16, sy * 0.26, HOP_BOT)) for sx, sy in ((1, 1), (-1, 1), (-1, -1), (1, -1))]
p.add(mk_loft([bot, top], cap=True), "gen_armour", True)
p.add(mk_box(HOP + Z * (HOP_TOP - 0.06), (0.5, 0.86, 0.04)), "gen_coal", True)
for k in range(9):                     # coal lumps heaped in the mouth
    q = HOP + V((random.uniform(-0.18, 0.18), random.uniform(-0.32, 0.32), HOP_TOP - 0.04))
    p.add(mk_ico(q, random.uniform(0.05, 0.09), sub=1), "gen_coal", True)
rim = rrect(HOP + Z * HOP_TOP, X, Y, 0.29, 0.49, 0.03, 1)
p.tube("gen_steel", rim + [rim[0]], 0.025, 5)
for sx in (-1, 1):
    for sy in (-1, 1):
        p.cyl("gen_gunmetal", HOP + V((sx * 0.2, sy * 0.33, B)), HOP + V((sx * 0.2, sy * 0.33, HOP_BOT + 0.25)), 0.035, seg=6)
p.cyl("gen_gunmetal", HOP + Z * HOP_BOT + Z * 0.02, HOP + Z * 0.6, 0.12, 0.1, seg=10)       # chute into the firebox
p.tube("gen_gunmetal", [HOP + Z * 0.62, HOP + Z * 0.62 + X * 0.3, V((FB.x - FBW / 2, HOP.y, 0.62))], 0.1, 10, 0.12)
# a red panel on the sloped outer face, the fang on it
slope = V((-(0.28 - 0.16), 0, HOP_TOP - HOP_BOT)).normalized()
nrm = slope.cross(Y).normalized()
if nrm.x > 0:
    nrm = -nrm
zm = (HOP_TOP + HOP_BOT) / 2 + 0.04
o = HOP + V((-(0.16 + 0.12 * (zm - HOP_BOT) / (HOP_TOP - HOP_BOT)), 0, zm)) + nrm * 0.012
p.add(mk_box(o, (0.025, 0.66, 0.5), Matrix.Rotation(-math.atan2(0.12, HOP_TOP - HOP_BOT), 4, 'Y'), 0.008), "gen_oxblood", True)
hopper = finish(p, "hopper", T(HOP), root)
fang("hopper_fang", o + nrm * 0.016, nrm, -Y, 0.42, hopper)

# ---------------------------------------------------------------- dynamo, shaft and spark terminals
p = Part()
p.cyl("gen_gunmetal", DYN - X * 0.24, DYN + X * 0.24, DYN_R, seg=20)
for x in (-0.15, -0.05, 0.05, 0.15):
    p.cyl("gen_copper", DYN + X * (x - 0.03), DYN + X * (x + 0.03), DYN_R + 0.025, seg=20)
for sx in (-1, 1):
    p.cyl("gen_steel", DYN + X * sx * 0.24, DYN + X * sx * 0.28, DYN_R * 0.8, seg=16)
p.box("gen_armour", V((DYN.x, DYN.y, (B + 0.66) / 2)), (0.6, 0.7, 0.66 - B), bevel=0.02)
p.cyl("gen_steel", DYN + X * 0.28, V((FW.x - 0.08, FW.y, FW.z)), 0.07, seg=10)      # shaft to the flywheel
p.box("gen_gunmetal", V((FW.x - 0.2, FW.y, B + 0.4)), (0.12, 0.3, 0.8 - 0.0), bevel=0.02)  # bearing pedestal
for y in (-0.22, 0.12):                # insulators and copper balls on top
    q = DYN + V((-0.05, y, DYN_R))
    p.cyl("gen_white", q, q + Z * 0.22, 0.045, 0.035, seg=8)
    for z in (0.06, 0.12, 0.18):
        p.cyl("gen_white", q + Z * (z - 0.01), q + Z * (z + 0.01), 0.07, seg=8)
    p.sphere("gen_copper", q + Z * 0.3, 0.075, u=10, v=8)
dynamo = finish(p, "dynamo", T(DYN), root)
p = Part()                             # the coils lit while it runs
for x in (-0.15, -0.05, 0.05, 0.15):
    p.cyl("gen_coilhot", DYN + X * (x - 0.032), DYN + X * (x + 0.032), DYN_R + 0.03, seg=20)
finish(p, "coil_glow", T(DYN), dynamo)
p = Part()                             # the arc between the balls: a zigzag, shown while running
a0 = DYN + V((-0.05, -0.22 + 0.07, DYN_R + 0.3))
a1 = DYN + V((-0.05, 0.12 - 0.07, DYN_R + 0.3))
pts = [a0.lerp(a1, k / 6) + Z * (0.035 * (1 if k % 2 else -1) if 0 < k < 6 else 0) for k in range(7)]
p.tube("gen_arc", pts, 0.012, 5)
finish(p, "arc", T((a0 + a1) / 2), dynamo)

# ---------------------------------------------------------------- flywheel, crank, rod, crosshead, cylinder
p = Part()
p.add(mk_lathe([(FW_R - 0.1, -0.07), (FW_R, -0.07), (FW_R, 0.07), (FW_R - 0.1, 0.07)], FW, X, 36, closed=True), "gen_steel", True)
p.add(mk_lathe([(FW_R - 0.1, 0.07), (FW_R - 0.04, 0.07), (FW_R - 0.04, 0.075), (FW_R - 0.1, 0.075)], FW, X, 36, closed=True), "gen_hazard", True)
p.cyl("gen_gunmetal", FW - X * 0.09, FW + X * 0.09, 0.13, seg=14)
for k in range(6):
    a = 2 * pi * k / 6
    d = V((0, cos(a), sin(a)))
    p.cyl("gen_gunmetal", FW + d * 0.12, FW + d * (FW_R - 0.08), 0.035, 0.028, seg=6)
CP = FW + X * 0.14 + Y * CRANK         # crank pin at angle 0 (toward +Y)
p.box("gen_gunmetal", FW + X * 0.11 + Y * CRANK / 2, (0.05, CRANK + 0.18, 0.14), bevel=0.02)
p.cyl("gen_steel", CP - X * 0.03, CP + X * 0.07, 0.045, seg=8)
flywheel = finish(p, "flywheel", T(FW), root)


def crosshead_y(angle):
    pin_y = FW.y + CRANK * cos(angle)
    pin_z = FW.z + CRANK * sin(angle)
    return pin_y + math.sqrt(ROD * ROD - (pin_z - FW.z) ** 2)


XH0 = V((CX, crosshead_y(0.0), FW.z))
p = Part()                             # the crosshead and its piston rod into the cylinder
p.box("gen_brass", XH0, (0.1, 0.16, 0.14), bevel=0.015)
p.cyl("gen_steel", XH0, XH0 + Y * 0.55, 0.03, seg=8)
finish(p, "crosshead", T(XH0), root)
p = Part()                             # the connecting rod, pointing -Y from the crosshead pin
p.add(mk_box(XH0 + V((-0.07, -ROD / 2, 0)), (0.04, ROD, 0.07), None, 0.015), "gen_steel", True)
p.cyl("gen_gunmetal", XH0 + V((-0.1, 0, 0)), XH0 + V((-0.04, 0, 0)), 0.05, seg=8)
p.cyl("gen_gunmetal", XH0 + V((-0.1, -ROD, 0)), XH0 + V((-0.04, -ROD, 0)), 0.06, seg=8)
finish(p, "con_rod", T(XH0), root)
p = Part()                             # the steam cylinder and the slide bars it sits on
p.cyl("gen_gunmetal", V((CX, CYL[0], FW.z)), V((CX, CYL[1], FW.z)), 0.17, seg=14)
for y in CYL:
    p.cyl("gen_steel", V((CX, y - 0.03, FW.z)), V((CX, y + 0.03, FW.z)), 0.2, seg=14)
for sz in (-1, 1):
    p.box("gen_steel", V((CX, (CYL[0] + 0.15) / 2, FW.z + sz * 0.09)), (0.06, CYL[0] - 0.15, 0.025))
p.box("gen_gunmetal", V((CX, (CYL[0] + CYL[1]) / 2, (B + FW.z - 0.17) / 2)), (0.2, 0.3, FW.z - 0.17 - B), bevel=0.02)
p.tube("gen_copper", [V((CX, (CYL[0] + CYL[1]) / 2, FW.z + 0.17)), V((CX, (CYL[0] + CYL[1]) / 2, 1.75)),
                      V((BOIL.x + 0.45, (CYL[0] + CYL[1]) / 2, 1.75)), V((BOIL.x + 0.45, BOIL.y + 0.5, BOIL.z + 0.3))], 0.045, 8, 0.12)
cylinder = finish(p, "cylinder", T(V((CX, (CYL[0] + CYL[1]) / 2, FW.z))), root)

# ---------------------------------------------------------------- power mast with insulators and cables
p = Part()
p.cyl("gen_gunmetal", MAST, MAST + Z * 0.3, 0.18, 0.14, seg=10)
p.cyl("gen_steel", MAST + Z * 0.3, MAST + Z * MAST_TOP, 0.07, 0.05, seg=8)
ARM = MAST + Z * (MAST_TOP - 0.25)
p.box("gen_gunmetal", ARM - X * 0.05, (0.74, 0.06, 0.06), bevel=0.01)
for x in (-0.36, 0.0, 0.26):
    q = ARM + X * x + Z * 0.03
    p.cyl("gen_white", q, q + Z * 0.18, 0.035, 0.025, seg=8)
    for z in (0.05, 0.1, 0.15):
        p.cyl("gen_white", q + Z * (z - 0.008), q + Z * (z + 0.008), 0.055, seg=8)
for x, end in ((-0.36, DYN + V((-0.05, -0.22, DYN_R + 0.3))), (0.0, DYN + V((-0.05, 0.12, DYN_R + 0.3)))):
    q = ARM + X * x + Z * 0.21
    mid = (q + end) / 2 - Z * 0.35
    p.tube("gen_black", [q, mid, end], 0.012, 4, 0.3)
p.sphere("gen_redglow", MAST + Z * (MAST_TOP + 0.03), 0.05, u=8, v=6)
mast = finish(p, "mast", T(MAST), root)

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
