"""Stage 1 of the Scout rework: bare head + retextured helmet, both on the `head` bone.
Run:  blender Scout.blend --background --python build_heads.py -- [--save]
Idempotent: rebuilds its own objects each run. Design units are centimetres:
(x, f, z) with f = forward, z = height above the chin; world = (x, CY - f, Z0 + z) / 100.
"""
import bpy, bmesh, sys, math, os
import numpy as np
from mathutils import Vector, Matrix

SAVE = "--save" in sys.argv
CY, Z0 = 0.0, 146.8
TEX = 1024
rng = np.random.default_rng(7)

# ------------------------------------------------------------------ helpers
def srgb2lin(c):
    c = np.asarray(c, dtype=np.float64)
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)

def sstep(a, b, x):
    t = np.clip((x - a) / (b - a), 0.0, 1.0)
    return t * t * (3 - 2 * t)

class Curve:
    def __init__(self, pts, sigma=0.35):
        xs = np.array([p[0] for p in pts], float); ys = np.array([p[1] for p in pts], float)
        self.x = np.arange(xs[0] - 2, xs[-1] + 2, 0.05)
        y = np.interp(self.x, xs, ys)
        k = np.exp(-0.5 * (np.arange(-30, 31) * 0.05 / sigma) ** 2); k /= k.sum()
        self.y = np.convolve(np.pad(y, 30, mode='edge'), k, mode='valid')
    def __call__(self, x):
        return np.interp(x, self.x, self.y)

ZC = 15.5          # above this the skull is an ellipsoid cap
ZTOP = 22.0
F_C = Curve([(-1, 6.0), (0, 6.5), (0.8, 7.8), (1.6, 8.2), (3.3, 7.9), (5.0, 8.2), (6.9, 8.1), (9.5, 8.15), (12.3, 8.2), (13.5, 8.8), (15.5, 9.1), (17, 9.1)])
B_C = Curve([(0, 1.0), (3.5, 3.0), (5, 4.6), (6.5, 6.0), (8, 7.6), (10, 8.9), (13, 9.5), (15.5, 9.6), (17, 9.6)])
W_C = Curve([(0, 2.9), (0.5, 3.4), (1.75, 4.3), (3.5, 5.3), (5, 5.9), (7, 6.35), (9.5, 6.6), (12, 6.95), (14, 7.25), (15.5, 7.35), (17, 7.35)])
NF_C = Curve([(0, 2.15), (3, 2.4), (14, 2.45), (15.5, 2.2), (17, 2.2)])
JAW_Z = 3.5
def jaw_fb(z):  # the jaw exists only in front of this line (side view)
    return 6.3 - (z / JAW_Z) * 6.8
NECK_C, NECK_RX, NECK_RF, NECK_TOP = -1.2, 4.5, 4.9, 9.0

def sections(z):
    z = np.asarray(z, float)
    s = np.sqrt(np.clip(1 - ((z - ZC) / (ZTOP - ZC)) ** 2, 0, 1))
    cap = z > ZC
    zz = np.minimum(z, ZC)
    F = F_C(zz) * np.where(cap, s ** 0.97, 1); B = B_C(zz) * np.where(cap, s ** 0.97, 1); W = W_C(zz) * np.where(cap, s ** 0.95, 1)
    nf = np.where(cap, 2.2 - 0.2 * (1 - s), NF_C(zz))
    return np.maximum(F, 1e-4), np.maximum(B, 1e-4), np.maximum(W, 1e-4), nf

def features(ax, z):
    """Forward displacement of the face, from |x| and z."""
    d = np.zeros_like(z)
    t = np.clip((12.4 - z) / 4.5, 0, 1)
    hN = np.where(z >= 7.9, 0.18 + 1.42 * t ** 2.0, 1.60 * np.clip(1 - ((7.9 - z) / 1.0) ** 2, 0, 1))
    hN = hN * sstep(13.2, 12.2, z) * (z > 6.8)
    sig = 0.58 + 0.80 * t ** 2
    d += hN * np.exp(-(ax / sig) ** 2.2)
    d += 0.42 * np.exp(-(((ax - 1.1) / 0.5) ** 2 + ((z - 7.6) / 0.5) ** 2))
    d += -0.55 * np.exp(-(((ax - 3.2) / 1.7) ** 2 + ((z - 11.9) / 1.0) ** 2))
    d += 0.30 * np.exp(-(((ax - 3.1) / 1.0) ** 2 + ((z - 11.75) / 0.62) ** 2))
    d += 0.30 * np.exp(-((z - 13.3) / 0.6) ** 2) * sstep(0.5, 1.6, ax) * (1 - sstep(5.0, 6.2, ax))
    d += 0.25 * np.exp(-((z - 5.0) / 1.8) ** 2 - (ax / 3.0) ** 2)
    d += 0.36 * np.exp(-((z - 5.72) / 0.42) ** 2 - (ax / 2.0) ** 2)
    d += 0.40 * np.exp(-((z - 4.3) / 0.5) ** 2 - (ax / 1.7) ** 2)
    d += -0.20 * np.exp(-((z - 5.02) / 0.15) ** 2) * (1 - sstep(2.0, 2.5, ax))
    d += -0.08 * np.exp(-((z - 6.3) / 0.4) ** 2 - (ax / 0.3) ** 2)
    d += 0.40 * np.exp(-((z - 1.7) / 1.0) ** 2 - (ax / 1.8) ** 2)
    d += 0.22 * np.exp(-(((ax - 4.7) / 1.4) ** 2 + ((z - 9.9) / 1.2) ** 2))
    return d

def surface(th, z, cut=True, neck=True, feat=True):
    """Head surface. th = 0 at the front, x = r sin th, f = r cos th. Returns x, f, is_neck."""
    th = np.asarray(th, float); z = np.asarray(z, float)
    th, z = np.broadcast_arrays(th, z)
    F, B, W, nf = sections(z)
    s, c = np.sin(th), np.cos(th)
    front = c >= 0
    D = np.where(front, F, B); n = np.where(front, nf, 2.1)
    r = ((np.abs(s) / W) ** n + (np.abs(c) / D) ** n) ** (-1.0 / n)
    r = np.where((z < -0.01) | (z > ZTOP), 0.0, r)
    x = r * s; f = r * c
    if feat:
        w = sstep(0.15, 0.55, c)
        f = f + features(np.abs(x), z) * w
    if False:
        gone = (z < JAW_Z) & (f < jaw_fb(z))
        x = np.where(gone, 0.0, x); f = np.where(gone, 0.0, f)
    isneck = np.zeros(z.shape, bool)
    if neck:
        a = (s / NECK_RX) ** 2 + (c / NECK_RF) ** 2
        b = -2 * NECK_C * c / NECK_RF ** 2
        cc = (NECK_C / NECK_RF) ** 2 - 1
        rn = (-b + np.sqrt(np.maximum(b * b - 4 * a * cc, 0))) / (2 * a)
        rn = np.where(z <= NECK_TOP, rn, 0.0)
        isneck = rn > np.hypot(x, f)
        x = np.where(isneck, rn * s, x); f = np.where(isneck, rn * c, f)
    return x, f, isneck

def normal_at(th, z, e=0.02):
    x0, f0, _ = surface(th, z, cut=False, neck=False)
    x1, f1, _ = surface(th + e, z, cut=False, neck=False)
    x2, f2, _ = surface(th, z + e * 8, cut=False, neck=False)
    a = np.array([x1 - x0, f1 - f0, 0.0]); b = np.array([x2 - x0, f2 - f0, e * 8])
    n = np.cross(a, b); n /= np.linalg.norm(n)
    p = np.array([x0, f0, 0.0])
    if np.dot(n[:2], p[:2]) < 0 and n[2] < 0.9: n = -n
    return n

# hairline: hair covers z > H(theta)
_HL = Curve([(0, 17.3), (35, 17.0), (55, 15.9), (68, 14.9), (84, 14.9), (100, 11.5), (118, 8.2), (140, 7.2), (180, 6.9)], sigma=5.0)
def hairline(th):
    a = np.abs(np.degrees(np.arctan2(np.sin(th), np.cos(th))))
    return _HL(a)

# UV mapping shared by the head and the hair cap
UF, TF = 0.70, math.radians(60)
def th_to_u(th):
    a = np.abs(th)
    g = np.where(a <= TF, UF * a / TF, UF + (1 - UF) * (a - TF) / (math.pi - TF))
    return 0.5 + 0.5 * np.sign(th) * g
def u_to_th(u):
    g = (u - 0.5) * 2; a = np.abs(g)
    t = np.where(a <= UF, a / UF * TF, TF + (a - UF) / (1 - UF) * (math.pi - TF))
    return np.sign(g) * t
V0, V1, V2, V3 = 0.14, 0.19, 0.90, 1.0
ZS = 17.5
def z_to_v(z):
    return np.interp(z, [-8, 0, ZS, ZTOP], [V0, V1, V2, V3])
def v_to_z(v):
    return np.interp(v, [V0, V1, V2, V3], [-8, 0, ZS, ZTOP])
EAR_UV = (0.0, 0.0, 0.13, 0.13)      # u0, v0, u1, v1
STRAND_UV = (0.16, 0.01, 0.99, 0.125)

KFACE, ZPIV = 0.92, 13.3   # the face below the brow is built at full length, then shortened
def ZM(a): return a if a >= ZPIV else ZPIV - (ZPIV - a) * KFACE
def ZI(z): return z if z >= ZPIV else ZPIV - (ZPIV - z) / KFACE
def W3(x, f, z):
    return Vector((x / 100.0, CY - f / 100.0, (Z0 + ZM(z)) / 100.0))

# ------------------------------------------------------------------ blender plumbing
arm = bpy.data.objects["Skater rig"]
coll = bpy.data.collections["Collection"]

def bone_parent(obj, bone):
    b = arm.data.bones[bone]
    pm = arm.matrix_world @ b.matrix_local @ Matrix.Translation((0, b.length, 0))
    obj.parent = arm; obj.parent_type = 'BONE'; obj.parent_bone = bone
    obj.matrix_parent_inverse = pm.inverted()
    obj.matrix_basis = Matrix.Identity(4)

def fresh_object(name, bone):
    old = bpy.data.objects.get(name)
    if old:
        me = old.data; bpy.data.objects.remove(old)
        if me.users == 0: bpy.data.meshes.remove(me)
    me = bpy.data.meshes.new(name)
    ob = bpy.data.objects.new(name, me)
    coll.objects.link(ob)
    bone_parent(ob, bone)
    return ob

def material(name, rgb, metallic=0.0, rough=0.6, image=None, emission=None):
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    bsdf = next(n for n in nt.nodes if n.type == 'BSDF_PRINCIPLED')
    for n in [n for n in nt.nodes if n.type == 'TEX_IMAGE']: nt.nodes.remove(n)
    lin = srgb2lin(rgb)
    bsdf.inputs['Base Color'].default_value = (*lin, 1)
    bsdf.inputs['Metallic'].default_value = metallic
    bsdf.inputs['Roughness'].default_value = rough
    if emission:
        bsdf.inputs['Emission Color'].default_value = (*srgb2lin(emission[:3]), 1); bsdf.inputs['Emission Strength'].default_value = emission[3]
    if image:
        t = nt.nodes.new('ShaderNodeTexImage'); t.image = image; t.location = (-320, 300)
        nt.links.new(t.outputs['Color'], bsdf.inputs['Base Color'])
    m.diffuse_color = (*lin, 1)
    return m

def make_image(name, px):
    """px: (H, W, 3) sRGB floats, top row first."""
    h, w = px.shape[:2]
    img = bpy.data.images.get(name)
    if img and tuple(img.size) != (w, h):
        bpy.data.images.remove(img); img = None
    if img is None:
        img = bpy.data.images.new(name, w, h, alpha=False)
    rgba = np.ones((h, w, 4), np.float32); rgba[..., :3] = np.clip(px, 0, 1)
    img.colorspace_settings.name = 'sRGB'
    img.pixels.foreach_set(np.ascontiguousarray(rgba[::-1]).ravel())
    path = os.path.join(bpy.app.tempdir, name + ".png")
    img.filepath_raw = path; img.file_format = 'PNG'; img.save()
    img.pack()
    img.filepath = "//" + name + ".png"; img.filepath_raw = "//" + name + ".png"
    return img

class MB:
    """Tiny mesh builder: verts in design cm, per-loop UVs, per-face material."""
    def __init__(self): self.v = []; self.f = []; self.uv = []; self.m = []; self.smooth = []
    def vert(self, x, f, z): self.v.append((x, f, z)); return len(self.v) - 1
    def face(self, idx, uvs=None, mat=0, smooth=True):
        self.f.append(tuple(idx)); self.uv.append(uvs or [(0.5, 0.05)] * len(idx)); self.m.append(mat); self.smooth.append(smooth)
    def write(self, ob, mats, sharp_deg=None, flip=False):
        me = ob.data
        me.clear_geometry()
        faces = [tuple(reversed(f)) for f in self.f] if flip else self.f
        uvs = [list(reversed(u)) for u in self.uv] if flip else self.uv
        me.from_pydata([tuple(W3(*p)) for p in self.v], [], faces)
        uvl = me.uv_layers.new(name="UVMap")
        i = 0
        for p, u in zip(me.polygons, uvs):
            for k in range(len(u)):
                uvl.data[p.loop_start + k].uv = u[k]
        me.materials.clear()
        for m in mats: me.materials.append(m)
        me.polygons.foreach_set("material_index", self.m)
        me.polygons.foreach_set("use_smooth", self.smooth)
        me.update()
        bm = bmesh.new(); bm.from_mesh(me)
        bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-6)
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        bm.to_mesh(me); bm.free()
        if sharp_deg is not None:
            me.set_sharp_from_angle(angle=math.radians(sharp_deg))
        me.update()
        return me

def lathe(mb, centre, axis, profile, seg, mat, uv=(0.5, 0.05), smooth=True, uvrect=None):
    """profile: list of (radius, height along axis). centre/axis in design cm."""
    axis = np.array(axis, float); axis /= np.linalg.norm(axis)
    ref = np.array([0, 0, 1.0]) if abs(axis[2]) < 0.9 else np.array([1.0, 0, 0])
    u = np.cross(axis, ref); u /= np.linalg.norm(u); w = np.cross(axis, u)
    rings = []
    for r, h in profile:
        if r <= 1e-6:
            rings.append([mb.vert(*(np.array(centre) + axis * h))])
        else:
            rings.append([mb.vert(*(np.array(centre) + axis * h + (u * math.cos(a) + w * math.sin(a)) * r)) for a in np.linspace(0, 2 * math.pi, seg, endpoint=False)])
    nr = len(rings) - 1
    for k, (a, b) in enumerate(zip(rings[:-1], rings[1:])):
        for i in range(seg):
            j = (i + 1) % seg
            if uvrect:
                u0, v0, u1, v1 = uvrect
                ua, ub = u0 + (u1 - u0) * i / seg, u0 + (u1 - u0) * (i + 1) / seg
                va, vb = v0 + (v1 - v0) * k / nr, v0 + (v1 - v0) * (k + 1) / nr
                q4 = [(ua, va), (ub, va), (ub, vb), (ua, vb)]
            else:
                q4 = [uv] * 4
            if len(a) == 1 and len(b) == 1: continue
            if len(b) == 1: mb.face([a[i], a[j], b[0]], [q4[0], q4[1], q4[2]], mat, smooth)
            elif len(a) == 1: mb.face([a[0], b[j], b[i]], [q4[0], q4[2], q4[3]], mat, smooth)
            else: mb.face([a[i], a[j], b[j], b[i]], q4, mat, smooth)

def box(mb, centre, ax_u, ax_v, ax_w, size, mat, smooth=False):
    c = np.array(centre, float); A = [np.array(a, float) / np.linalg.norm(a) for a in (ax_u, ax_v, ax_w)]
    vs = {}
    for i in (-1, 1):
        for j in (-1, 1):
            for k in (-1, 1):
                vs[(i, j, k)] = mb.vert(*(c + A[0] * i * size[0] / 2 + A[1] * j * size[1] / 2 + A[2] * k * size[2] / 2))
    for axis in range(3):
        for sgn in (-1, 1):
            o = [a for a in range(3) if a != axis]
            quad = []
            for (p, q) in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
                key = [0, 0, 0]; key[axis] = sgn; key[o[0]] = p; key[o[1]] = q
                quad.append(vs[tuple(key)])
            mb.face(quad, None, mat, smooth)

# ------------------------------------------------------------------ texture: head atlas
def noise1(x, seed, freqs=(3, 7, 13, 29, 53), amps=(1, 0.8, 0.6, 0.45, 0.3)):
    r = np.random.default_rng(seed)
    out = np.zeros_like(x, dtype=np.float64)
    for fq, a in zip(freqs, amps):
        out += a * np.sin(x * fq + r.uniform(0, 6.28))
    return 0.5 + 0.5 * out / sum(amps)

def vnoise(shape, cell, seed):
    r = np.random.default_rng(seed)
    h, w = shape
    g = r.random((h // cell + 3, w // cell + 3))
    yy, xx = np.mgrid[0:h, 0:w]
    fy, fx = yy / cell, xx / cell
    iy, ix = fy.astype(int), fx.astype(int)
    ty, tx = fy - iy, fx - ix
    ty = ty * ty * (3 - 2 * ty); tx = tx * tx * (3 - 2 * tx)
    return (g[iy, ix] * (1 - tx) + g[iy, ix + 1] * tx) * (1 - ty) + (g[iy + 1, ix] * (1 - tx) + g[iy + 1, ix + 1] * tx) * ty

HAIR_D, HAIR_M, HAIR_L = np.array([0.50, 0.35, 0.15]), np.array([0.80, 0.63, 0.34]), np.array([0.95, 0.83, 0.56])
def hair_col(n):
    n = n[..., None]
    return np.where(n < 0.5, HAIR_D + (HAIR_M - HAIR_D) * (n * 2), HAIR_M + (HAIR_L - HAIR_M) * (n * 2 - 1))

PT = np.array([0.0, -8.3, 18.6])       # where the hair gathers (design cm)
HC = np.array([0.0, 0.0, 13.0])        # rough head centre

PLATE = [(0.9, 10.7), (2.4, 10.9), (2.9, 8.6), (3.7, 7.0), (5.3, 3.9), (5.8, 2.5), (5.3, 0.6), (2.5, 1.0), (-1.1, 2.8), (-1.3, 7.0), (0.2, 8.4)]
def in_poly(px, py, poly):
    inside = np.zeros(px.shape, bool)
    n = len(poly)
    for i in range(n):
        x1, y1 = poly[i]; x2, y2 = poly[(i + 1) % n]
        cond = ((y1 > py) != (y2 > py)) & (px < (x2 - x1) * (py - y1) / (y2 - y1 + 1e-12) + x1)
        inside ^= cond
    return inside

def paint_head():
    N = TEX
    vv, uu = np.mgrid[0:N, 0:N]
    u = (uu + 0.5) / N; v = 1 - (vv + 0.5) / N
    th = u_to_th(u); z = v_to_z(v)
    x, f, isneck = surface(th, z, cut=False, neck=False)
    X = np.abs(x)
    frontw = sstep(0.1, 0.5, np.cos(th))
    col = np.empty((N, N, 3)); col[:] = (0.925, 0.775, 0.675)
    def mix(target, a):
        nonlocal col
        a = np.clip(a, 0, 1)[..., None]
        col = col * (1 - a) + np.array(target) * a
    SH = (0.74, 0.53, 0.46)
    # broad skin variation
    mix((0.95, 0.80, 0.70), 0.5 * np.exp(-((z - 15.3) / 1.6) ** 2 - (X / 4.0) ** 2))               # forehead light
    mix((0.90, 0.60, 0.55), 0.20 * np.exp(-(((X - 4.3) / 1.7) ** 2 + ((z - 8.7) / 1.5) ** 2)) * frontw)   # blush
    mix(SH, 0.30 * np.exp(-(((X - 5.6) / 1.2) ** 2 + ((z - 6.6) / 1.8) ** 2)))                     # under cheekbone
    mix(SH, 0.25 * sstep(5.2, 7.2, X) * (z < 15))                                                   # face sides fall off
    mix(SH, 0.35 * np.exp(-(((X - 2.9) / 1.6) ** 2 + ((z - 12.3) / 0.85) ** 2)))                   # eye socket
    mix(SH, 0.22 * np.exp(-(((X - 1.6) / 0.6) ** 2 + ((z - 11.6) / 1.0) ** 2)))                    # inner corner
    # nose
    win = sstep(8.0, 8.8, z) * sstep(12.6, 11.6, z)
    mix(SH, 0.26 * np.exp(-((X - 0.95) / 0.33) ** 2) * win)
    mix((1.0, 0.90, 0.83), 0.30 * np.exp(-(X / 0.27) ** 2) * sstep(8.2, 8.9, z) * sstep(12.4, 11.3, z))
    mix((1.0, 0.92, 0.86), 0.35 * np.exp(-(X / 0.35) ** 2 - ((z - 8.25) / 0.35) ** 2))
    mix(SH, 0.30 * np.exp(-(((X - 1.45) / 0.3) ** 2 + ((z - 7.75) / 0.6) ** 2)))                    # alar crease
    mix((0.56, 0.37, 0.33), 0.55 * (1 - sstep(0.5, 1.1, np.hypot((X - 0.55) / 0.28, (z - 7.12) / 0.12))))  # nostril
    # lips
    zl = 5.02 - 0.10 * (X / 2.35) ** 2
    lipw = np.clip(1 - (X / 2.35) ** 2, 0, 1)
    zt = zl + 0.85 * lipw ** 0.8 * (1 - 0.20 * np.exp(-(X / 0.33) ** 2))
    zb = zl - 1.05 * np.clip(1 - (X / 2.1) ** 2, 0, 1) ** 0.7
    e = 0.07
    up = sstep(-e, e, zt - z) * sstep(-e, e, z - zl) * (X < 2.35)
    lo = sstep(-e, e, z - zb) * sstep(-e, e, zl - z) * (X < 2.1)
    mix((0.70, 0.40, 0.37), 0.92 * up)
    mix((0.79, 0.48, 0.44), 0.92 * lo)
    mix((0.90, 0.64, 0.60), 0.5 * lo * np.exp(-(X / 0.9) ** 2 - ((z - 4.55) / 0.22) ** 2))
    mix((0.36, 0.16, 0.15), 0.9 * (1 - sstep(0.035, 0.085, np.abs(z - zl))) * (1 - sstep(2.25, 2.5, X)))
    mix(SH, 0.35 * np.exp(-(((X - 2.5) / 0.3) ** 2 + ((z - 4.95) / 0.3) ** 2)))                    # corners
    mix(SH, 0.33 * np.exp(-(X / 1.5) ** 2 - ((z - 3.55) / 0.33) ** 2))                             # under lower lip
    mix((0.97, 0.84, 0.76), 0.25 * np.exp(-(X / 1.1) ** 2 - ((z - 1.9) / 0.7) ** 2))               # chin light
    # brows
    bx = np.clip((X - 1.15) / 4.5, 0, 1)
    zbr = 12.78 + 1.25 * bx - 1.00 * bx ** 2.2
    bth = 0.33 * (1 - 0.62 * sstep(0.45, 1.0, bx)) * sstep(0.0, 0.08, bx)
    ba = (1 - sstep(bth * 0.75, bth * 1.25 + 0.03, np.abs(z - zbr))) * (X > 1.1) * (X < 5.68)
    ba *= 0.72 + 0.28 * noise1(X * 9 + z * 22, 3, freqs=(1, 2.3, 4.1), amps=(1, 0.7, 0.5))
    mix((0.37, 0.26, 0.15), 0.93 * ba)
    # eyes
    ex0, ex1, ez0, ez1 = 1.55, 4.75, 11.56, 11.94
    eu = (X - ex0) / (ex1 - ex0)
    zbl = ez0 + (ez1 - ez0) * eu
    arc = np.clip(4 * eu * (1 - eu), 0, 1)
    zu = zbl + 0.70 * arc ** 0.72
    zlo = zbl - 0.40 * arc ** 0.85
    ine = (eu > 0) & (eu < 1)
    e2 = 0.035
    eye = sstep(-e2, e2, zu - z) * sstep(-e2, e2, z - zlo) * ine
    scl = np.array([0.93, 0.91, 0.88])
    lidsh = sstep(0.0, 0.45, zu - z)
    sclc = scl[None, None, :] * (0.62 + 0.38 * lidsh[..., None])
    a = eye[..., None]; col = col * (1 - a) + sclc * a
    icx, icz = 3.10, ez0 + (ez1 - ez0) * ((3.10 - ex0) / (ex1 - ex0)) + 0.12
    ir = np.hypot(X - icx, z - icz)
    iris = np.array([0.38, 0.55, 0.66])[None, None, :] * (0.75 + 0.45 * sstep(0.60, 0.22, ir))[..., None]
    iris = iris * (1 - 0.60 * sstep(0.50, 0.66, ir))[..., None]
    iris = iris * (0.60 + 0.40 * lidsh[..., None])
    a = (eye * (1 - sstep(0.63, 0.68, ir)))[..., None]; col = col * (1 - a) + iris * a
    mix((0.04, 0.04, 0.05), eye * (1 - sstep(0.23, 0.28, ir)))
    hx = np.sign(x) * icx - 0.20
    mix((1, 1, 1), 0.95 * eye * (1 - sstep(0.07, 0.12, np.hypot(x - hx, z - (icz + 0.20)))))
    mix((0.80, 0.50, 0.47), 0.6 * eye * (1 - sstep(0.0, 0.25, eu * (ex1 - ex0))))                  # caruncle
    # lashes / lids
    lash_th = 0.11 + 0.07 * sstep(0.3, 1.0, eu)
    la = (1 - sstep(lash_th * 0.7, lash_th * 1.2 + 0.02, np.abs(z - (zu + 0.03)))) * (eu > 0.02) * (eu < 1.0)
    wing_u = (X - ex1)
    wz = ez1 + wing_u * 0.55
    la2 = (1 - sstep(0.05, 0.11, np.abs(z - wz))) * (wing_u >= 0) * (wing_u < 0.42) * (1 - wing_u / 0.5)
    mix((0.10, 0.07, 0.06), 0.95 * np.maximum(la, la2))
    mix((0.45, 0.28, 0.25), 0.65 * (1 - sstep(0.02, 0.06, np.abs(z - (zlo - 0.02)))) * (eu > 0.3) * (eu < 1.0))
    mix((0.56, 0.37, 0.32), 0.55 * (1 - sstep(0.03, 0.08, np.abs(z - (zu + 0.30 + 0.08 * arc)))) * (eu > 0.08) * (eu < 1.06))
    # shadow where the jaw turns under, then the steel neck with its segments
    mix((0.50, 0.33, 0.29), 0.75 * sstep(0.7, 0.0, z))
    _, _, nk = surface(th, z, cut=True, neck=True)
    nk = nk | (z < 0)
    seg = 1 - 0.55 * sstep(0.0, 0.05, np.abs(((z + 8.0) / 1.35) % 1.0 - 0.5) - 0.44)
    steel = np.array([0.40, 0.41, 0.42])[None, None, :] * seg[..., None] * (0.6 + 0.4 * sstep(3.0, -2.0, z))[..., None]
    col = np.where(nk[..., None], steel, col)
    # hair above the hairline: streaks converge on the gather point
    P = np.stack([x, f, z], -1)
    ax = (PT - HC) / np.linalg.norm(PT - HC)
    e1 = np.cross(ax, [1.0, 0, 0]); e1 /= np.linalg.norm(e1); e2v = np.cross(ax, e1)
    d = P - HC
    phi = np.arctan2(d @ e2v, d @ e1)
    along = (d @ ax) / (np.linalg.norm(d, axis=-1) + 1e-6)
    n = 0.55 * noise1(phi, 11, freqs=(7, 17, 31, 61, 113)) + 0.45 * noise1(phi + 0.15 * along, 12, freqs=(23, 47, 89, 151, 211))
    n = np.clip((n - 0.5) * 2.2 + 0.52, 0, 1)
    hl = hairline(th)
    ha = sstep(-0.25, 0.1, z - hl)
    hc = hair_col(n) * (0.82 + 0.18 * sstep(0, 3.0, z - hl))[..., None]
    a = ha[..., None]; col = col * (1 - a) + hc * a
    # baby hairs: a soft warm shadow just under the hairline
    mix((0.78, 0.60, 0.42), 0.35 * sstep(-1.1, -0.2, z - hl) * (1 - ha))
    # ear patch
    u0, v0, u1, v1 = EAR_UV
    m = (u < u1 + 0.01) & (v < v1 + 0.008)
    eu_, ev_ = (u - u0) / (u1 - u0) * 2 - 1, (v - v0) / (v1 - v0) * 2 - 1     # -1..1, eu_ = back..front, ev_ = bottom..top
    ear = np.empty((N, N, 3)); ear[:] = (0.90, 0.72, 0.63)
    rr = np.hypot(eu_, ev_)
    ear = ear * (1 - 0.30 * sstep(0.75, 0.45, rr))[..., None]
    conch = 1 - sstep(0.6, 1.0, np.hypot((eu_ - 0.20) / 0.36, (ev_ + 0.12) / 0.42))
    ear = ear * (1 - conch[..., None]) + np.array([0.68, 0.46, 0.41]) * conch[..., None]
    col = np.where(m[..., None], ear, col)
    # strand patch: streaks across u
    u0, v0, u1, v1 = STRAND_UV
    m = (u >= u0 - 0.01) & (v < v1 + 0.008)
    sn = 0.6 * noise1((u - u0) / (u1 - u0) * 6.283, 21, freqs=(5, 11, 23, 47, 97)) + 0.4 * noise1((u - u0) / (u1 - u0) * 6.283 + v * 3, 22, freqs=(31, 67, 131, 197, 263))
    sn = np.clip((sn - 0.5) * 2.2 + 0.52, 0, 1)
    col = np.where(m[..., None], hair_col(sn), col)
    return col

# ------------------------------------------------------------------ meshes
def build_head(mats):
    cols = []
    K = 18
    front = [TF * 4 / 3 * (k / K) ** 1.2 for k in range(K + 1)]          # 0..80 deg, denser at the nose
    back = list(np.linspace(front[-1], math.pi, 8)[1:])
    half = front + back
    ths = [-t for t in reversed(half[1:-1])] + half                         # -pi excluded .. +pi
    ths = [-math.pi] + ths                                                  # seam column duplicated
    zs = [-8, -4.5, -1.5, -0.05, 0.0, 0.35, 0.8, 1.3, 1.8, 2.3, 2.8, 3.3] + list(np.arange(3.75, 14.6, 0.43)) + [15.2, 16.0, 17.0, 18.0, 19.0, 20.0, 20.8, 21.4, 21.8]
    mb = MB()
    grid = np.zeros((len(zs), len(ths)), int); neckf = np.zeros((len(zs), len(ths)), bool)
    for i, z in enumerate(zs):
        for j, t in enumerate(ths):
            if j == len(ths) - 1 and False: pass
            x, f, nk = surface(t, z)
            grid[i, j] = mb.vert(float(x), float(f), z); neckf[i, j] = bool(nk)
    for i in range(len(zs) - 1):
        for j in range(len(ths) - 1):
            zmid = (zs[i] + zs[i + 1]) / 2; tmid = (ths[j] + ths[j + 1]) / 2
            if zs[i] > hairline(np.array(tmid)) + 1.3:      # hidden under the hair cap
                continue
            idx = [grid[i, j], grid[i, j + 1], grid[i + 1, j + 1], grid[i + 1, j]]
            uv = [(float(th_to_u(np.array(ths[jj]))) if not (jj == 0) else 0.0, float(z_to_v(zs[ii]))) for ii, jj in ((i, j), (i, j + 1), (i + 1, j + 1), (i + 1, j))]
            nk = sum(bool(neckf[ii, jj]) for ii, jj in ((i, j), (i, j + 1), (i + 1, j + 1), (i + 1, j)))
            mb.face(idx, uv, 0)
    # ears
    for sx in (-1, 1):
        c = np.array([sx * 7.05, -0.9, 11.9])
        R = (Matrix.Rotation(math.radians(sx * 22), 3, 'Z') @ Matrix.Rotation(math.radians(-12), 3, 'X'))
        nu, nv = 8, 6
        ring = []
        for a in range(1, nv):
            la = -math.pi / 2 + math.pi * a / nv
            row = []
            for b in range(nu):
                lo = 2 * math.pi * b / nu
                # local: lx = outward thickness, lf = front/back, lz = up
                lf = 1.75 * math.cos(la) * math.cos(lo) * (1.0 if math.sin(la) > 0 else 0.8)
                lx = 0.85 * math.cos(la) * math.sin(lo)
                lz = 3.0 * math.sin(la)
                p = R @ Vector((sx * lx, lf, lz))
                u0, v0, u1, v1 = EAR_UV
                uvp = (u0 + (u1 - u0) * (0.5 + 0.47 * lf / 1.75), v0 + (v1 - v0) * (0.5 + 0.47 * lz / 3.0))
                row.append((mb.vert(c[0] + p.x, c[1] + p.y, c[2] + p.z), uvp))
            ring.append(row)
        u0, v0, u1, v1 = EAR_UV
        bot = (mb.vert(*(c + np.array(R @ Vector((0, 0, -3.0))))), (u0 + (u1 - u0) * 0.5, v0 + (v1 - v0) * 0.03))
        tp = (mb.vert(*(c + np.array(R @ Vector((0, 0, 3.0))))), (u0 + (u1 - u0) * 0.5, v0 + (v1 - v0) * 0.97))
        for a in range(len(ring) - 1):
            for b in range(nu):
                q = [ring[a][b], ring[a][(b + 1) % nu], ring[a + 1][(b + 1) % nu], ring[a + 1][b]]
                mb.face([p[0] for p in q], [p[1] for p in q], 0)
        for b in range(nu):
            mb.face([bot[0], ring[0][(b + 1) % nu][0], ring[0][b][0]], [bot[1], ring[0][(b + 1) % nu][1], ring[0][b][1]], 0)
            mb.face([tp[0], ring[-1][b][0], ring[-1][(b + 1) % nu][0]], [tp[1], ring[-1][b][1], ring[-1][(b + 1) % nu][1]], 0)
    ob = fresh_object("head_bare", "head")
    mb.write(ob, mats, sharp_deg=62)
    return ob

def plate_x(f, z):
    """Half-width of the uncut head at side-view point (f, z), plus its outward normal."""
    F, B, W, nf = sections(np.array(z))
    D = F if f >= 0 else B; n = float(nf) if f >= 0 else 2.1
    q = min(abs(f) / float(D), 0.985)
    x = float(W) * (1 - q ** n) ** (1 / n)
    nx = (x ** (n - 1)) / float(W) ** n; nfv = (abs(f) ** (n - 1)) / float(D) ** n * (1 if f >= 0 else -1)
    l = math.hypot(nx, nfv)
    return x, nx / l, nfv / l

def build_jaw_plates(head_ob, steel_index):
    """Steel plates along the jaw, added into head_bare as flat-shaded geometry."""
    bm = bmesh.new()
    vs = [bm.verts.new((p[0], p[1], 0)) for p in PLATE]
    face = bm.faces.new(vs)
    bmesh.ops.triangulate(bm, faces=[face])
    bmesh.ops.subdivide_edges(bm, edges=bm.edges[:], cuts=2, use_grid_fill=True)
    bmesh.ops.triangulate(bm, faces=bm.faces[:])
    bm.verts.index_update(); bm.edges.index_update(); bm.faces.index_update()
    out = bmesh.new(); out.from_mesh(head_ob.data)
    uvl = out.loops.layers.uv.verify()
    for sx in (-1, 1):
        vmap = {}
        layers = []
        for off in (0.15, 0.50):
            lay = {}
            for v in bm.verts:
                f, z = v.co.x, v.co.y
                x, nx, nfv = plate_x(f, z)
                p = W3(sx * (x + nx * off), f + nfv * off, z)
                lay[v.index] = out.verts.new(p)
            layers.append(lay)
        inner, outer = layers
        newf = []
        for fc in bm.faces:
            idx = [v.index for v in fc.verts]
            newf.append(out.faces.new([outer[i] for i in idx]))
        for e in bm.edges:
            if len(e.link_faces) == 1:
                a, b = e.verts[0].index, e.verts[1].index
                newf.append(out.faces.new([inner[a], inner[b], outer[b], outer[a]]))
        for fc in newf:
            fc.material_index = steel_index; fc.smooth = False
            for l in fc.loops: l[uvl].uv = (0.5, 0.05)
    bmesh.ops.recalc_face_normals(out, faces=[f for f in out.faces if not f.smooth])
    out.to_mesh(head_ob.data); out.free(); bm.free()
    head_ob.data.update()

def build_hair(mats):
    mb = MB()
    ncol = 40
    ths = np.linspace(-math.pi, math.pi, ncol + 1)
    srow = [0.0, 0.05, 0.22, 0.42, 0.62, 0.80, 0.93]
    thick = [0.03, 0.5, 1.1, 1.4, 1.35, 1.15, 1.0]
    lock = lambda t: 0.16 * math.sin(9 * t) * (1 - abs(math.cos(t / 2)) ** 6)
    grid = np.zeros((len(srow), ncol + 1), int)
    for j, t in enumerate(ths):
        h0 = float(hairline(np.array(t)))
        for i, s in enumerate(srow):
            z = h0 + (ZTOP - 0.25 - h0) * s
            x, f, _ = surface(t, z, cut=False, neck=False, feat=False)
            p = np.array([float(x), float(f), z])
            n = p - HC; n /= np.linalg.norm(n)
            off = thick[i] * (1.0 + (lock(t) if i > 1 else 0))
            p = p + n * off
            grid[i, j] = mb.vert(*p)
    top = mb.vert(0, 0, ZTOP + 0.95)
    def uvof(i, j, seam_hi):
        t = ths[j]
        uu = 1.0 if (j == ncol) else (0.0 if j == 0 else float(th_to_u(np.array(t))))
        h0 = float(hairline(np.array(t))); z = h0 + (ZTOP - 0.25 - h0) * srow[i]
        return (uu, float(z_to_v(z)))
    for i in range(len(srow) - 1):
        for j in range(ncol):
            mb.face([grid[i, j], grid[i, j + 1], grid[i + 1, j + 1], grid[i + 1, j]], [uvof(i, j, 0), uvof(i, j + 1, 0), uvof(i + 1, j + 1, 0), uvof(i + 1, j, 0)], 0)
    for j in range(ncol):
        mb.face([grid[-1, j], grid[-1, j + 1], top], [uvof(len(srow) - 1, j, 0), uvof(len(srow) - 1, j + 1, 0), ((uvof(0, j, 0)[0] + uvof(0, j + 1, 0)[0]) / 2, 1.0)], 0)
    su0, sv0, su1, sv1 = STRAND_UV
    # the gather: a cone from the cap to the existing ponytail clasp
    clasp = np.array([0.0, CY * 100 - 12.9, 164.7 - Z0])
    gc = np.array([0.0, -9.9, 18.25])
    gax = clasp - gc; gax /= np.linalg.norm(gax)
    lathe(mb, gc, gax, [(0.0, -3.4), (1.6, -2.9), (2.5, -1.8), (2.8, -0.5), (2.6, 0.9), (2.2, 2.2), (1.8, 3.4)], 12, 0, uvrect=STRAND_UV)
    # loose strands at the temples
    def strand(sx, path, r0, uband):
        pts = []
        for (deg, z, off) in path:
            t = math.radians(deg) * sx
            x, f, _ = surface(t, z, cut=False, neck=False, feat=False)
            p = np.array([float(x), float(f), z]); n = p - np.array([0, 0, z]); n /= np.linalg.norm(n)
            pts.append((p + n * off, n))
        # resample smoothly
        P = np.array([p for p, _ in pts]); Nn = np.array([n for _, n in pts])
        tt = np.linspace(0, len(P) - 1, 9)
        Pi = np.stack([np.interp(tt, np.arange(len(P)), P[:, k]) for k in range(3)], 1)
        Ni = np.stack([np.interp(tt, np.arange(len(P)), Nn[:, k]) for k in range(3)], 1)
        k3 = np.array([0.25, 0.5, 0.25])
        for k in range(3):
            Pi[1:-1, k] = np.convolve(Pi[:, k], k3, mode='valid')
        rings = []
        for q in range(len(Pi)):
            tan = Pi[min(q + 1, len(Pi) - 1)] - Pi[max(q - 1, 0)]; tan /= np.linalg.norm(tan)
            n = Ni[q] - tan * np.dot(Ni[q], tan); n /= np.linalg.norm(n); b = np.cross(tan, n)
            s = q / (len(Pi) - 1)
            rad = r0 * (1 - s) ** 0.8 + 0.06
            rings.append([mb.vert(*(Pi[q] + b * math.cos(a) * rad * 1.5 + n * math.sin(a) * rad * 0.55)) for a in np.linspace(0, 2 * math.pi, 6, endpoint=False)])
        for q, (a, bq) in enumerate(zip(rings[:-1], rings[1:])):
            for i in range(6):
                j = (i + 1) % 6
                ua = su0 + (su1 - su0) * (uband + 0.12 * i / 6); ub = su0 + (su1 - su0) * (uband + 0.12 * (i + 1) / 6)
                va = sv0 + (sv1 - sv0) * q / 8; vb = sv0 + (sv1 - sv0) * (q + 1) / 8
                mb.face([a[i], a[j], bq[j], bq[i]], [(ua, va), (ub, va), (ub, vb), (ua, vb)], 0)
        tip = mb.vert(*(Pi[-1] + (Pi[-1] - Pi[-2]) * 0.6))
        for i in range(6):
            mb.face([rings[-1][i], rings[-1][(i + 1) % 6], tip], None, 0)
            mb.uv[-1] = [(su0 + 0.02, sv0 + 0.01)] * 3
    for sx in (-1, 1):
        strand(sx, [(52, 16.4, 0.5), (60, 14.2, 1.0), (61, 11.5, 1.15), (57, 8.6, 0.95), (52, 6.0, 0.8), (49, 4.4, 0.9)], 0.42, 0.1 if sx > 0 else 0.5)
        strand(sx, [(40, 16.9, 0.45), (49, 15.0, 0.85), (54, 12.6, 0.9), (55, 10.6, 0.75), (53, 9.2, 0.8)], 0.28, 0.3 if sx > 0 else 0.7)
    ob = fresh_object("head_bare_hair", "head")
    mb.write(ob, mats, sharp_deg=75)
    return ob

def band_z(t):
    return 15.7 + 1.7 * math.cos(t)

def build_goggles(mats):
    """mats: 0 band, 1 band blue, 2 housing, 3 brass, 4 lens."""
    mb = MB()
    ncol = 36
    ths = np.linspace(-math.pi, math.pi, ncol + 1)
    prof = [(-1.0, 0.55), (-1.0, 1.28), (-0.42, 1.34), (0.42, 1.34), (1.0, 1.28), (1.0, 0.55)]   # (dz, offset)
    pm = [0, 0, 1, 0, 0]
    rows = []
    for t in ths[:-1]:
        zc = band_z(t)
        wsc = 1.0 + 0.25 * math.cos(t) if math.cos(t) > 0 else 1.0
        row = []
        for dz, off in prof:
            z = zc + dz * wsc
            x, f, _ = surface(t, z, cut=False, neck=False, feat=False)
            p = np.array([float(x), float(f), z]); n = p - HC; n[2] *= 0.5; n /= np.linalg.norm(n)
            row.append(mb.vert(*(p + n * (off + 0.55 * (1 - math.cos(t)) / 2 + 0.25 * abs(math.sin(t))))))
        rows.append(row)
    for j in range(ncol):
        a, b = rows[j], rows[(j + 1) % ncol]
        for k in range(len(prof) - 1):
            mb.face([a[k], b[k], b[k + 1], a[k + 1]], None, pm[k], smooth=(k not in (0, 4)))
    # goggles
    cents = []
    for sx in (-1, 1):
        t = math.radians(22) * sx; z = 18.55
        x, f, _ = surface(t, z, cut=False, neck=False, feat=False)
        n = normal_at(t, z)
        ax = n * 0.72 + np.array([0, 0.62, 0.30]); ax /= np.linalg.norm(ax)
        c = np.array([float(x), float(f), z]) + n * 1.25
        cents.append((c, ax))
        lathe(mb, c, ax, [(2.05, -1.5), (2.55, -1.1), (2.6, 0.25), (2.38, 0.8)], 16, 2)
        lathe(mb, c, ax, [(2.38, 0.8), (2.52, 1.05), (2.32, 1.3), (2.02, 1.12)], 16, 3)
        lathe(mb, c, ax, [(2.02, 1.12), (1.2, 1.26), (0.0, 1.32)], 16, 4)
        # strap lug on the outside
        side = np.cross(ax, [0, 0, 1.0]); side /= np.linalg.norm(side)
        if side[0] * sx < 0: side = -side
        box(mb, c + side * 2.75 + ax * -0.35, side, np.cross(ax, side), ax, (1.0, 1.5, 1.1), 2)
    (c0, a0), (c1, a1) = cents
    mid = (c0 + c1) / 2; am = (a0 + a1); am /= np.linalg.norm(am)
    box(mb, mid + am * -0.1, [1, 0, 0], np.cross(am, [1, 0, 0]), am, (1.5, 1.3, 1.3), 2)
    ob = fresh_object("head_bare_goggles", "head")
    mb.write(ob, mats, sharp_deg=50)
    return ob

def build_collar(mats):
    """Provisional high collar on the chest bone (stage 2 rebuilds the torso under it)."""
    mb = MB()
    n = 28
    gap = math.radians(15)
    angs = np.linspace(gap, 2 * math.pi - gap, n)
    cx, cf = 0.0, -1.3
    rows = []
    for a in angs:
        frontness = (math.cos(a) + 1) / 2
        ztop = ZI(0.9 - 4.3 * frontness ** 2.5)
        zbot = ZI(-8.5)
        def pt(r_add, z):
            flare = 1.0 + 0.045 * (ZM(z) - ZM(zbot))
            rx, rf = (6.1 + r_add) * flare, (6.4 + r_add) * flare
            return mb.vert(cx + rx * math.sin(a), cf + rf * math.cos(a), z)
        rows.append([pt(0.0, zbot), pt(0.0, ztop - 0.15), pt(0.75, ztop), pt(0.8, ztop - 0.75), pt(0.8, zbot)])
    for j in range(n - 1):
        a, b = rows[j], rows[j + 1]
        mb.face([a[0], a[1], b[1], b[0]], None, 0)              # inner wall
        mb.face([a[1], a[2], b[2], b[1]], None, 1)              # top edge, red
        mb.face([a[2], a[3], b[3], b[2]], None, 1)              # outer piping, red
        mb.face([a[3], a[4], b[4], b[3]], None, 0)              # outer wall
    for r in (rows[0], rows[-1]):                                # front edges, red
        mb.face([r[0], r[1], r[2], r[3], r[4]], None, 1, smooth=False)
    ob = fresh_object("collar_high", "chest")
    mb.write(ob, mats, sharp_deg=45)
    return ob

# ------------------------------------------------------------------ helmet retexture
VIS0, VIS1 = 1.9, 2.7
def paint_helmet(helm):
    me = helm.data
    N = TEX
    uvd = me.uv_layers[0].data
    S = 15.1   # helmet local units -> cm
    pos = np.zeros((N, N, 3)); mask = np.zeros((N, N), bool); glass = np.zeros((N, N), bool)
    nrm = np.zeros((N, N, 3))
    for p in me.polygons:
        ls = list(p.loop_indices)
        uv = np.array([uvd[l].uv[:] for l in ls]); co = np.array([me.vertices[me.loops[l].vertex_index].co[:] for l in ls]) * S
        for k in range(1, len(ls) - 1):
            tri_uv = uv[[0, k, k + 1]] * N; tri_co = co[[0, k, k + 1]]
            mn = np.floor(tri_uv.min(0)).astype(int) - 2; mx = np.ceil(tri_uv.max(0)).astype(int) + 2
            mn = np.clip(mn, 0, N - 1); mx = np.clip(mx, 0, N - 1)
            gx, gy = np.meshgrid(np.arange(mn[0], mx[0] + 1) + 0.5, np.arange(mn[1], mx[1] + 1) + 0.5)
            d = (tri_uv[1, 1] - tri_uv[2, 1]) * (tri_uv[0, 0] - tri_uv[2, 0]) + (tri_uv[2, 0] - tri_uv[1, 0]) * (tri_uv[0, 1] - tri_uv[2, 1])
            if abs(d) < 1e-9: continue
            w0 = ((tri_uv[1, 1] - tri_uv[2, 1]) * (gx - tri_uv[2, 0]) + (tri_uv[2, 0] - tri_uv[1, 0]) * (gy - tri_uv[2, 1])) / d
            w1 = ((tri_uv[2, 1] - tri_uv[0, 1]) * (gx - tri_uv[2, 0]) + (tri_uv[0, 0] - tri_uv[2, 0]) * (gy - tri_uv[2, 1])) / d
            w2 = 1 - w0 - w1
            eps = -0.08
            ins = (w0 >= eps) & (w1 >= eps) & (w2 >= eps)
            P = w0[..., None] * tri_co[0] + w1[..., None] * tri_co[1] + w2[..., None] * tri_co[2]
            ys = (gy - 0.5).astype(int); xs = (gx - 0.5).astype(int)
            pos[ys[ins], xs[ins]] = P[ins]; mask[ys[ins], xs[ins]] = True
            glass[ys[ins], xs[ins]] = (p.material_index == 1)
            nrm[ys[ins], xs[ins]] = np.array(p.normal[:])
    # open boundary edges (the neck opening and the back port)
    from collections import Counter
    ec = Counter()
    for p in me.polygons:
        for ek in p.edge_keys: ec[ek] += 1
    bnd = [ek for ek, c in ec.items() if c == 1 and not (abs(me.vertices[ek[0]].co.x) < 1e-4 and abs(me.vertices[ek[1]].co.x) < 1e-4)]
    dist = np.full((N, N), 1e9)
    for a, b in bnd:
        A = np.array(me.vertices[a].co[:]) * S; B = np.array(me.vertices[b].co[:]) * S
        ab = B - A; t = np.clip(((pos - A) @ ab) / (ab @ ab + 1e-12), 0, 1)
        dd = np.linalg.norm(pos - (A + t[..., None] * ab), axis=-1)
        dist = np.minimum(dist, dd)
    print("helmet boundary edges", len(bnd), "cm range", pos[mask].min(0), pos[mask].max(0))
    x, y, z = np.abs(pos[..., 0]), pos[..., 1], pos[..., 2]      # y: 0 front .. 21 back, z: up
    n1 = vnoise((N, N), 96, 1); n2 = vnoise((N, N), 24, 2); n3 = vnoise((N, N), 6, 3); n4 = vnoise((N, N), 2, 4)
    grime = 0.5 * n1 + 0.3 * n2 + 0.2 * n3
    base = np.array([0.46, 0.475, 0.49])
    col = base[None, None, :] * (0.86 + 0.26 * grime)[..., None]
    col *= (0.975 + 0.05 * n4)[..., None]
    wear = sstep(0.62, 0.74, 0.6 * n2 + 0.4 * n3)                       # brushed bright patches
    col = col * (1 - 0.30 * wear[..., None]) + np.array([0.66, 0.67, 0.67]) * 0.30 * wear[..., None]
    pits = sstep(0.27, 0.20, 0.5 * n3 + 0.5 * n4)                       # a few dark chips
    col = col * (1 - 0.35 * pits[..., None])
    col *= (0.82 + 0.18 * sstep(-10, 0, z))[..., None]                  # dirtier low down
    red = np.array([0.58, 0.11, 0.08])
    chip = sstep(0.68, 0.80, 0.5 * n3 + 0.5 * n4)
    redv = red[None, None, :] * (0.85 + 0.30 * grime)[..., None]
    redv = redv * (1 - 0.7 * chip[..., None]) + base * 0.7 * chip[..., None]
    # distance to the visor opening
    gb = Counter()
    for p in me.polygons:
        if p.material_index == 1:
            for ek in p.edge_keys: gb[ek] += 1
    gd = np.full((N, N), 1e9)
    for (a_, b_), c in gb.items():
        if c != 1: continue
        A = np.array(me.vertices[a_].co[:]) * S; B = np.array(me.vertices[b_].co[:]) * S
        if abs(A[0]) < 1e-3 and abs(B[0]) < 1e-3: continue
        ab = B - A; t = np.clip(((pos - A) @ ab) / (ab @ ab + 1e-12), 0, 1)
        gd = np.minimum(gd, np.linalg.norm(pos - (A + t[..., None] * ab), axis=-1))
    back = y > 12
    crest = (x < 0.95) & ((z > 7.6) | back)
    ring = (gd > VIS0) & (gd < VIS1) & (y < 9) & ~((x < 2.2) & (z < 1.0))
    trim = (crest | ring) & ~glass
    col = np.where(trim[..., None], redv, col)
    edge = (((np.abs(x - 0.95) < 0.09) & ((z > 7.6) | back)) | (((np.abs(gd - VIS0) < 0.08) | (np.abs(gd - VIS1) < 0.08)) & (y < 9) & ~((x < 2.2) & (z < 1.0)))) & ~glass
    col = np.where(edge[..., None], col * 0.4, col)
    # texture bleed past the island borders
    filled = mask.copy(); out = col.copy()
    out[~filled] = 0
    for _ in range(10):
        acc = np.zeros_like(out); cnt = np.zeros((N, N))
        for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            acc += np.roll(out * filled[..., None], (dy, dx), (0, 1)); cnt += np.roll(filled, (dy, dx), (0, 1))
        new = (~filled) & (cnt > 0)
        out[new] = acc[new] / cnt[new][..., None]
        filled |= new
    out[~filled] = base * 0.9
    return out[::-1]      # v up -> top row first

# ------------------------------------------------------------------ build
bpy.context.preferences.filepaths.save_version = 0

head_px = paint_head()
head_img = make_image("scout_head_basecolor", head_px)
M_head = material("Scout head", (0.9, 0.75, 0.65), 0.0, 0.58, image=head_img)
M_steel = material("Scout steel", (0.62, 0.63, 0.63), 0.8, 0.40)
M_band = material("Scout headband", (0.085, 0.085, 0.095), 0.0, 0.8)
M_blue = material("Scout band blue", (0.24, 0.37, 0.50), 0.2, 0.55)
M_house = material("Scout goggle housing", (0.17, 0.17, 0.18), 0.7, 0.5)
M_brass = material("Scout brass", (0.78, 0.55, 0.20), 1.0, 0.32)
M_lens = material("Scout lens amber", (1.0, 0.52, 0.06), 0.35, 0.08)
M_collar = material("Scout collar", (0.06, 0.06, 0.065), 0.0, 0.85)
M_red = material("Scout red trim", (0.56, 0.11, 0.08), 0.1, 0.55)

head = build_head([M_head, M_steel])
build_jaw_plates(head, 1)
hair = build_hair([M_head])
gog = build_goggles([M_band, M_blue, M_house, M_brass, M_lens])
collar = build_collar([M_collar, M_red])

helm = bpy.data.objects.get("head_helmet") or bpy.data.objects["Head • angular tapered helmet"]
helm.name = "head_helmet"; helm.data.name = "head_helmet"
helm_img = make_image("scout_helmet_basecolor", paint_helmet(helm))
M_helm = material("Scout helmet", (0.46, 0.475, 0.49), 0.75, 0.46, image=helm_img)
M_visor = material("Scout visor", (0.80, 0.42, 0.07), 0.9, 0.14)
helm.data.materials[0] = M_helm; helm.data.materials[1] = M_visor

for o in (head, hair, gog, collar):
    tris = sum(len(p.vertices) - 2 for p in o.data.polygons)
    print("BUILT", o.name, "verts", len(o.data.vertices), "tris", tris)
print("names clash with bones:", [o.name for o in bpy.data.objects if o.name in arm.data.bones])
if SAVE:
    bpy.ops.wm.save_mainfile()
    print("SAVED", bpy.data.filepath)
