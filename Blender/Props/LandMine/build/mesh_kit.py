"""Small mesh helpers shared by the land mine scripts (the same shapes as build_motorcycle.py's).

Every builder returns a bmesh in world metres; Part gathers them into one object with its
material slots. place() parents an object while keeping the world matrix it was built for.
"""
import bpy, bmesh
from math import sin, cos, pi
from mathutils import Vector as V, Matrix

X, Y, Z = V((1, 0, 0)), V((0, 1, 0)), V((0, 0, 1))
MATS = {}
WORLD = {}


def material(name, col, met, rough, emis=None, strength=0.0, alpha=1.0):
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
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


def T(p):
    return Matrix.Translation(V(p))


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


def mk_lathe(prof, origin=(0, 0, 0), axis=Z, seg=24):
    """prof: (radius, height) pairs from the axis outward and back; the sweep is closed at both ends."""
    origin, axis = V(origin), V(axis).normalized()
    u = axis.orthogonal().normalized()
    w = axis.cross(u)
    bm = bmesh.new()
    grid = []
    for i in range(seg):
        a = 2 * pi * i / seg
        d = u * cos(a) + w * sin(a)
        grid.append([bm.verts.new(origin + axis * h + d * max(r, 4e-4)) for r, h in prof])
    m = len(prof)
    for i in range(seg):
        i2 = (i + 1) % seg
        for j in range(m - 1):
            bm.faces.new((grid[i][j], grid[i2][j], grid[i2][j + 1], grid[i][j + 1]))
    bm.faces.new([g[0] for g in grid])
    bm.faces.new([g[-1] for g in grid])
    bmesh.ops.remove_doubles(bm, verts=bm.verts[:], dist=1e-5)
    return bm


def mk_annulus(c, r0, r1, h, a0=0.0, a1=2 * pi, seg=24):
    """A flat ring (or a sector of one) lying on Z, h thick."""
    c = V(c)
    rings = []
    for z in (0.0, h):
        lo = []
        for i in range(seg + 1):
            a = a0 + (a1 - a0) * i / seg
            lo.append(c + V((cos(a) * r0, sin(a) * r0, z)))
        hi = []
        for i in range(seg, -1, -1):
            a = a0 + (a1 - a0) * i / seg
            hi.append(c + V((cos(a) * r1, sin(a) * r1, z)))
        rings.append(lo + hi)
    return mk_loft(rings)


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
        self.add(mk_box(c, size, rot, bevel), mat, True)

    def cyl(self, mat, p0, p1, r0, r1=None, seg=12, flat=False):
        self.add(mk_cyl(p0, p1, r0, r1, seg), mat, flat)

    def rivet(self, pos, normal, r=0.011, mat="mine_brass"):
        pos, normal = V(pos), V(normal).normalized()
        self.add(mk_cyl(pos - normal * 0.003, pos + normal * r * 0.6, r, r * 0.55, 6), mat)


def place(coll, ob, world, parent):
    coll.objects.link(ob)
    ob.parent = parent
    ob.matrix_parent_inverse = Matrix.Identity(4)
    ob.matrix_basis = (WORLD[parent.name].inverted() if parent else Matrix.Identity(4)) @ world
    WORLD[ob.name] = world.copy()
    return ob


def finish(coll, part, name, world, parent, sharp=0.87):
    bm = part.bm
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
    return place(coll, bpy.data.objects.new(name, me), world, parent)


def empty(coll, name, world, parent, size=0.1):
    ob = bpy.data.objects.new(name, None)
    ob.empty_display_size = size
    return place(coll, ob, world, parent)


def load_fang(drone_blend):
    """The faction fang from the Drone, as 2D outline data (u across, v along the tip) plus faces."""
    with bpy.data.libraries.load(drone_blend) as (src, dst):
        dst.objects = ["faction_fang"]
    f = dst.objects[0]
    me = f.data
    n = V((0, 0, 0))
    for p in me.polygons:
        n += p.normal * p.area
    n.normalize()
    co = [v.co.copy() for v in me.vertices]
    cen = sum(co, V((0, 0, 0))) / len(co)
    tip = min(co, key=lambda v: v.y) - cen
    tip -= n * tip.dot(n)
    tip.normalize()
    lat = n.cross(tip)
    uv = [((v - cen).dot(lat), (v - cen).dot(tip), (v - cen).dot(n)) for v in co]
    ca = (max(u for u, _, _ in uv) + min(u for u, _, _ in uv)) / 2
    cb = (max(v for _, v, _ in uv) + min(v for _, v, _ in uv)) / 2
    uv = [(u - ca, v - cb, w) for u, v, w in uv]
    length = max(v for _, v, _ in uv) - min(v for _, v, _ in uv)
    polys = [(list(p.vertices), p.material_index) for p in me.polygons]
    mats = list(me.materials)
    for m in mats:
        m.use_fake_user = True
        MATS[m.name] = m
    bpy.data.objects.remove(f)
    return {"uv": uv, "len": length, "polys": polys, "mats": mats}


def fang(coll, data, name, centre, normal, tip_dir, height, parent):
    normal, tip_dir = V(normal).normalized(), V(tip_dir).normalized()
    lat = normal.cross(tip_dir)
    s = height / data["len"]
    bm = bmesh.new()
    vs = [bm.verts.new(V(centre) + lat * u * s + tip_dir * v * s + normal * w * s) for u, v, w in data["uv"]]
    for idx, mi in data["polys"]:
        f = bm.faces.new([vs[i] for i in idx])
        f.material_index = mi
    bm.normal_update()
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    for m in data["mats"]:
        me.materials.append(m)
    return place(coll, bpy.data.objects.new(name, me), Matrix.Identity(4), parent)
