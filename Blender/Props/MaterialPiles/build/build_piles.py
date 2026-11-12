"""Builds MaterialPiles.blend from nothing: the iron, wood and coal piles left on the map.

Run in background Blender:
  blender --background --python build_piles.py

Everything is rebuilt each run, so edits here never compound. Each pile stands on one 1 x 1 m cell, so
everything stays within +-0.45 m of the centre and below about 0.55 m. The front faces -Y, Z up, base on
Z = 0. Each kind is its own collection (pile_iron, pile_wood, pile_coal), exported by export_piles.py.

The game shows a pile's size by how many of its pieces are visible (scripts/components/pile_rig.gd):
  <kind>_piece_NN  shown in order from 01, so 01 is the first ingot, log or coal layer laid down
  <kind>_base      always shown: the pallet, the chocks, the dust patch
"""
import bpy, bmesh, math, os, random
from math import sin, cos, radians, pi
from mathutils import Vector as V, Matrix, noise

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.normpath(os.path.join(HERE, "..", "MaterialPiles.blend"))
random.seed(11)

bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene

MATS = {}


def material(name, col, met, rough):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = next(n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    b.inputs["Base Color"].default_value = (*col, 1)
    b.inputs["Metallic"].default_value = met
    b.inputs["Roughness"].default_value = rough
    m.diffuse_color = (*col, 1)
    MATS[name] = m


material("pile_steel", (0.30, 0.31, 0.33), 0.8, 0.38)
material("pile_steel2", (0.22, 0.23, 0.25), 0.8, 0.45)
material("pile_pallet", (0.30, 0.21, 0.12), 0.0, 0.85)
material("pile_pallet2", (0.19, 0.13, 0.07), 0.0, 0.9)
material("pile_hazard", (0.62, 0.42, 0.035), 0.05, 0.6)
material("pile_black", (0.025, 0.025, 0.027), 0.1, 0.7)
material("pile_bark", (0.13, 0.08, 0.045), 0.0, 0.95)
material("pile_bark2", (0.09, 0.06, 0.035), 0.0, 0.95)
material("pile_cut", (0.55, 0.40, 0.22), 0.0, 0.8)
material("pile_ring", (0.40, 0.27, 0.13), 0.0, 0.8)
material("pile_coal", (0.022, 0.021, 0.022), 0.15, 0.45)
material("pile_coal2", (0.035, 0.033, 0.034), 0.2, 0.35)
material("pile_dust", (0.16, 0.145, 0.13), 0.0, 1.0)


def mk_box(c, size, rot=None):
    bm = bmesh.new()
    M = Matrix.Translation(V(c)) @ (rot if rot else Matrix.Identity(4)) @ Matrix.Diagonal((*size, 1))
    bmesh.ops.create_cube(bm, size=1.0, matrix=M)
    return bm


def mesh_from(name, parts):
    me = bpy.data.meshes.new(name)
    out = bmesh.new()
    names = []
    for bm, mat in parts:
        if mat not in names:
            names.append(mat)
        idx = names.index(mat)
        tmp = bpy.data.meshes.new("_tmp")
        bm.to_mesh(tmp)
        bm.free()
        for p in tmp.polygons:
            p.material_index = idx
        out.from_mesh(tmp)
        bpy.data.meshes.remove(tmp)
    out.to_mesh(me)
    out.free()
    for mat in names:
        me.materials.append(MATS[mat])
    for p in me.polygons:
        p.use_smooth = False
    return me


def place(coll, name, me, parent):
    o = bpy.data.objects.new(name, me)
    o.parent = parent
    coll.objects.link(o)
    return o


def new_pile(kind):
    coll = bpy.data.collections.new("pile_" + kind)
    scene.collection.children.link(coll)
    root = bpy.data.objects.new(kind + "_root", None)
    coll.objects.link(root)
    return coll, root


# ---------------------------------------------------------------- iron: ingots on a pallet
def ingot(c, along_x, mat):
    """A trapezoid ingot, 0.6 long, 0.13 wide at the foot and 0.09 at the top, 0.07 tall."""
    L, wb, wt, h = 0.6, 0.13, 0.09, 0.07
    bm = bmesh.new()
    pts = []
    for z, w, l in ((0, wb, L), (h, wt, L - 0.04)):
        for sx, sy in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
            x, y = sx * l / 2, sy * w / 2
            if not along_x:
                x, y = y, x
            pts.append(bm.verts.new(V(c) + V((x, y, z))))
    b, t = pts[:4], pts[4:]
    bm.faces.new(list(reversed(b)))
    bm.faces.new(t)
    for i in range(4):
        j = (i + 1) % 4
        bm.faces.new((b[i], b[j], t[j], t[i]))
    return (bm, mat)


def build_iron():
    coll, root = new_pile("iron")
    base = []
    # Pallet: three runners, five deck boards, a hazard tag on the front.
    for x in (-0.34, 0, 0.34):
        base.append((mk_box((x, 0, 0.04), (0.08, 0.84, 0.08)), "pile_pallet2"))
    for k in range(5):
        y = -0.34 + k * 0.17
        base.append((mk_box((0, y, 0.095), (0.84, 0.14, 0.03)), "pile_pallet"))
    base.append((mk_box((0.24, -0.425, 0.05), (0.14, 0.008, 0.06)), "pile_hazard"))
    base.append((mk_box((0.24, -0.43, 0.05), (0.10, 0.004, 0.012)), "pile_black"))
    place(coll, "iron_base", mesh_from("iron_base", base), root)
    # Four courses of four ingots, crosswise, bottom first; 16 pieces in all.
    n = 0
    for layer in range(4):
        along_x = layer % 2 == 0
        z = 0.11 + layer * 0.072
        for k in range(4):
            off = (k - 1.5) * 0.15
            c = (0, off, z) if along_x else (off, 0, z)
            n += 1
            mat = "pile_steel" if (k + layer) % 3 else "pile_steel2"
            place(coll, "iron_piece_%02d" % n, mesh_from("iron_piece_%02d" % n, [ingot(c, along_x, mat)]), root)


# ---------------------------------------------------------------- wood: a log stack between chocks
def log(c, r, length, rot_z=0.0, seg=8):
    """A log along Y (cut ends to the camera): bark round the side, pale end grain with a ring."""
    parts = []
    bm = bmesh.new()
    M = Matrix.Translation(V(c)) @ Matrix.Rotation(rot_z, 4, 'Z') @ Matrix.Rotation(pi / 2, 4, 'X')
    bmesh.ops.create_cone(bm, cap_ends=False, segments=seg, radius1=r, radius2=r, depth=length, matrix=M)
    # Roughen the bark a little so the logs are not perfect tubes.
    for v in bm.verts:
        v.co.z += noise.noise(v.co * 9.0 + V(c) * 3.0) * 0.008
    parts.append((bm, "pile_bark" if random.random() < 0.6 else "pile_bark2"))
    # End caps: a circle's face points along the matrix's Z, which the X quarter turn sends to -Y (the front).
    turn = Matrix.Rotation(rot_z, 4, 'Z')
    for s in (-1, 1):
        for radius, push, mat, segs in ((r * 0.97, 0.0, "pile_cut", seg), (r * 0.35, 0.002, "pile_ring", 6)):
            end = V(c) + turn @ V((0, s * (length / 2 + push), 0))
            e = bmesh.new()
            bmesh.ops.create_circle(e, cap_ends=True, segments=segs, radius=radius,
                                    matrix=Matrix.Translation(end) @ turn @ Matrix.Rotation(pi / 2, 4, 'X'))
            if s > 0:
                bmesh.ops.reverse_faces(e, faces=e.faces[:])
            parts.append((e, mat))
    return parts


def build_wood():
    coll, root = new_pile("wood")
    r = 0.072
    length = 0.84
    base = []
    # Two chocks either side of the bottom row, at front and back, and two bearers under it.
    for y in (-0.3, 0.3):
        base.append((mk_box((0, y, 0.015), (0.74, 0.07, 0.03)), "pile_pallet2"))
        for s in (-1, 1):
            base.append((mk_box((s * 0.335, y, 0.07), (0.05, 0.07, 0.08)), "pile_pallet"))
    place(coll, "wood_base", mesh_from("wood_base", base), root)
    rows = (4, 3, 2, 1)
    n = 0
    z = 0.03 + r
    for row, count in enumerate(rows):
        for k in range(count):
            x = (k - (count - 1) / 2) * (2 * r + 0.006)
            jitter = random.uniform(-0.03, 0.03)
            n += 1
            parts = log((x, jitter, z + row * r * 1.72), r * random.uniform(0.94, 1.03), length - abs(jitter) * 2,
                        radians(random.uniform(-2.5, 2.5)))
            place(coll, "wood_piece_%02d" % n, mesh_from("wood_piece_%02d" % n, parts), root)


# ---------------------------------------------------------------- coal: a heap that grows in layers
def heap(radius, height, seed, rings=6, seg=16):
    """A lumpy cone of coal: faceted rings with noise, flat bottom."""
    bm = bmesh.new()
    grid = []
    for i in range(rings + 1):
        t = i / rings
        rr = radius * (1 - t) ** 1.1
        zz = height * t ** 0.85
        ring = []
        for k in range(seg):
            a = 2 * pi * k / seg + (0.21 * i)
            jitter = 1 + 0.22 * noise.noise(V((cos(a) * 3.3, sin(a) * 3.3, t * 4 + seed))) + 0.08 * random.uniform(-1, 1)
            reach = min(rr * jitter, 0.43)
            p = V((cos(a) * reach, sin(a) * reach, max(0.0, zz + 0.02 * random.uniform(-1, 1) * (0 < i))))
            ring.append(bm.verts.new(p) if i < rings else None)
        grid.append(ring)
    top = bm.verts.new((0.01 * noise.noise(V((seed, 0, 0))), 0, height))
    for i in range(rings - 1):
        for k in range(seg):
            j = (k + 1) % seg
            bm.faces.new((grid[i][k], grid[i][j], grid[i + 1][j], grid[i + 1][k]))
    for k in range(seg):
        j = (k + 1) % seg
        bm.faces.new((grid[rings - 1][k], grid[rings - 1][j], top))
    bm.faces.new(list(reversed(grid[0])))
    return bm


def lump(c, r, seed):
    bm = bmesh.new()
    R = Matrix.Rotation(seed, 4, 'Z') @ Matrix.Rotation(seed * 0.7, 4, 'X')
    bmesh.ops.create_icosphere(bm, subdivisions=1, radius=r,
                               matrix=Matrix.Translation(V(c)) @ R @ Matrix.Diagonal((1.2, 0.9, 0.75, 1)))
    return bm


def build_coal():
    coll, root = new_pile("coal")
    base = []
    # The dust patch, irregular, just above the ground, and a few stray lumps round the edge.
    bm = bmesh.new()
    seg = 18
    ring = []
    for k in range(seg):
        a = 2 * pi * k / seg
        rr = 0.40 * (1 + 0.09 * noise.noise(V((cos(a) * 3, sin(a) * 3, 0.5))))
        ring.append(bm.verts.new((cos(a) * min(rr, 0.445), sin(a) * min(rr, 0.445), 0.004)))
    bm.faces.new(ring)
    base.append((bm, "pile_dust"))
    for k, (x, y) in enumerate(((-0.36, -0.12), (0.30, -0.27), (0.36, 0.18), (-0.22, 0.33))):
        base.append((lump((x, y, 0.022), 0.026, k + 1.3), "pile_coal2"))
    place(coll, "coal_base", mesh_from("coal_base", base), root)
    # Five heaps, each taller than the last; piece k is the heap at stage k with lumps on its slopes.
    for n in range(1, 6):
        radius = 0.18 + 0.045 * n
        height = 0.06 + 0.07 * n
        parts = [(heap(radius, height, n * 1.7), "pile_coal")]
        count = 14 + 8 * n
        for k in range(count):
            a = 2 * pi * k / count * 2.618 + n
            t = random.uniform(0.0, 0.92)
            rr = radius * (1 - t) ** 1.1 * 0.93
            zz = height * t ** 0.85
            parts.append((lump((cos(a) * rr, sin(a) * rr, max(zz, 0.03)), random.uniform(0.022, 0.04), k * 1.7 + n), "pile_coal2" if k % 3 else "pile_coal"))
        place(coll, "coal_piece_%02d" % n, mesh_from("coal_piece_%02d" % n, parts), root)


build_iron()
build_wood()
build_coal()
for i, kind in enumerate(("iron", "wood", "coal")):
    bpy.data.objects[kind + "_root"].location = (i * 1.5, 0, 0)
report = []
for kind in ("iron", "wood", "coal"):
    coll = bpy.data.collections["pile_" + kind]
    pieces = [o for o in coll.objects if "_piece_" in o.name]
    tris = sum(sum(len(p.vertices) - 2 for p in o.data.polygons) for o in coll.objects if o.type == 'MESH')
    report.append((kind, len(pieces), tris))
bpy.ops.wm.save_as_mainfile(filepath=OUT)
for kind, pieces, tris in report:
    print("PILE %s: %d pieces, %d triangles" % (kind, pieces, tris))
print("SAVED", OUT)
