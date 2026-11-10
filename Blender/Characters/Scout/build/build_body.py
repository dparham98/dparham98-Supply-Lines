"""Stage 2 of the Scout rework: body, armour, gear, skates, shotgun and ponytail on the existing rig.
Run on the stage 1 base:  blender Scout_stage1_base.blend --background --python build_body.py -- <repo> [--save <out.blend>]
World centimetres throughout: x (her left is +x), y (forward is -y), z up. Angles: 0 = front, +90 deg = +x.
"""
import bpy, bmesh, sys, math, os
import numpy as np
from mathutils import Vector, Matrix

ARGV = sys.argv[sys.argv.index("--") + 1:]
REPO = ARGV[0]
OUT = ARGV[ARGV.index("--save") + 1] if "--save" in ARGV else None
RAISE = 2.8        # taller skates lift everything above the wheels
bpy.context.preferences.filepaths.save_version = 0
O = bpy.data.objects
arm = O["Skater rig"]
coll = bpy.data.collections["Collection"]
rad = math.radians

def srgb2lin(c):
    c = np.asarray(c, dtype=np.float64)
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)
def sstep(a, b, x):
    t = np.clip((x - a) / (b - a), 0.0, 1.0)
    return t * t * (3 - 2 * t)
def unit(v):
    v = np.asarray(v, float); return v / (np.linalg.norm(v) + 1e-12)
class Curve:
    def __init__(self, pts, sigma=1.0):
        xs = np.array([p[0] for p in pts], float); ys = np.array([p[1] for p in pts], float)
        self.x = np.arange(xs[0] - 6, xs[-1] + 6, 0.1)
        y = np.interp(self.x, xs, ys)
        k = np.exp(-0.5 * (np.arange(-40, 41) * 0.1 / sigma) ** 2); k /= k.sum()
        self.y = np.convolve(np.pad(y, 40, mode='edge'), k, mode='valid')
    def __call__(self, x): return float(np.interp(x, self.x, self.y))

# ------------------------------------------------------------------ what the clips do with the gun, before the rig changes
CLIPS = ("idle", "run", "shoot")
SHOULDER_IN = 2.7     # the sheet's shoulders are narrower than the old rig's
scn = bpy.context.scene
OLD = {}
if not arm.get("scout_rework_raised"):
    arm.data.pose_position = 'POSE'
    for act in CLIPS:
        A = bpy.data.actions[act]; arm.animation_data.action = A
        for f in range(int(A.frame_range[0]), int(A.frame_range[1]) + 1):
            scn.frame_set(f)
            pb = arm.pose.bones
            g = pb["gun"].matrix.copy()
            OLD[(act, f)] = (pb["hand.R"].matrix.inverted() @ g, g.inverted() @ pb["hand.L"].matrix)
    arm.animation_data.action = bpy.data.actions["idle"]; scn.frame_set(1)

# ------------------------------------------------------------------ rig: raise everything above the wheels
if not arm.get("scout_rework_raised"):
    bpy.context.view_layer.objects.active = arm
    arm.data.pose_position = 'REST'
    bpy.ops.object.mode_set(mode='EDIT')
    for eb in arm.data.edit_bones:
        if eb.name == "root" or eb.name.startswith("wheel."): continue
        eb.head.z += RAISE / 100; eb.tail.z += RAISE / 100
        for sx, side in ((1, ".L"), (-1, ".R")):
            if eb.name.endswith(side) and eb.name.split(".")[0] in ("upper_arm", "forearm", "forearm_twist", "hand", "elbow"):
                eb.head.x -= sx * SHOULDER_IN / 100; eb.tail.x -= sx * SHOULDER_IN / 100
            if eb.name == "clavicle" + side:
                eb.tail.x -= sx * SHOULDER_IN / 100
    bpy.ops.object.mode_set(mode='OBJECT')
    arm["scout_rework_raised"] = True
arm.data.pose_position = 'REST'
bpy.context.view_layer.update()
def bone_head(n): return np.array(arm.data.bones[n].head_local[:]) * 100
def bone_tail(n): return np.array(arm.data.bones[n].tail_local[:]) * 100

# ------------------------------------------------------------------ materials
def material(name, rgb, metallic=0.0, rough=0.6, emission=None):
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = next(n for n in m.node_tree.nodes if n.type == 'BSDF_PRINCIPLED')
    lin = srgb2lin(rgb)
    if not bsdf.inputs['Base Color'].is_linked:
        bsdf.inputs['Base Color'].default_value = (*lin, 1)
    bsdf.inputs['Metallic'].default_value = metallic
    bsdf.inputs['Roughness'].default_value = rough
    if emission:
        bsdf.inputs['Emission Color'].default_value = (*srgb2lin(emission[:3]), 1); bsdf.inputs['Emission Strength'].default_value = emission[3]
    m.diffuse_color = (*lin, 1)
    return m
M = dict(
    suit=material("Scout bodysuit", (0.115, 0.115, 0.125), 0.0, 0.72),
    steel=material("Scout steel", (0.60, 0.61, 0.62), 0.55, 0.45),
    dark=material("Scout goggle housing", (0.19, 0.19, 0.20), 0.6, 0.5),
    red=material("Scout red trim", (0.60, 0.11, 0.08), 0.1, 0.55),
    leather=material("Scout leather", (0.50, 0.33, 0.17), 0.0, 0.7),
    leather_dark=material("Scout leather dark", (0.30, 0.19, 0.10), 0.0, 0.75),
    amber=material("Scout amber glow", (1.0, 0.50, 0.08), 0.0, 0.4, emission=(1.0, 0.45, 0.06, 2.6)),
    brass=material("Scout brass", (0.78, 0.55, 0.20), 1.0, 0.32),
    gun=material("Scout gun steel", (0.15, 0.155, 0.165), 0.65, 0.42),
    grip=material("Scout gun polymer", (0.07, 0.07, 0.075), 0.0, 0.6),
    wood=material("Scout pump brown", (0.40, 0.25, 0.13), 0.0, 0.6),
    rubber=material("Scout wheel rubber", (0.05, 0.05, 0.055), 0.0, 0.65),
    insignia=material("Scout insignia", (0.86, 0.85, 0.80), 0.0, 0.6),
    band=bpy.data.materials["Scout headband"],
    head=bpy.data.materials["Scout head"],
)
material("Scout helmet", (0.46, 0.475, 0.49), 0.55, 0.46)
MAT_ORDER = list(M.keys())

# ------------------------------------------------------------------ skinned mesh builder
class SK:
    def __init__(self): self.v = []; self.w = []; self.f = []; self.m = []; self.sm = []; self.uv = []; self.c = []
    def vert(self, p, w): self.v.append(tuple(float(x) for x in p)); self.w.append(w); return len(self.v) - 1
    def face(self, idx, mat, inside, smooth=True, uv=None):
        self.f.append(list(idx)); self.m.append(MAT_ORDER.index(mat)); self.sm.append(smooth); self.uv.append(uv); self.c.append(tuple(inside))
    def tris(self): return sum(len(f) - 2 for f in self.f)
    def write(self, name, sharp=None, bone=None):
        old = O.get(name)
        if old:
            me = old.data; O.remove(old)
            if me.users == 0: bpy.data.meshes.remove(me)
        V = np.array(self.v)
        faces = []
        for f, c in zip(self.f, self.c):
            p = V[f]; n = np.cross(p[1] - p[0], p[2] - p[0])
            if len(f) > 3: n = n + np.cross(p[2] - p[0], p[3] - p[0])
            if np.dot(n, p.mean(0) - np.array(c)) < 0: f = list(reversed(f)); flipped = True
            else: flipped = False
            faces.append((f, flipped))
        me = bpy.data.meshes.new(name)
        me.from_pydata([tuple(p / 100.0) for p in V], [], [f for f, _ in faces])
        used = sorted(set(self.m))
        for i in used: me.materials.append(M[MAT_ORDER[i]])
        me.polygons.foreach_set("material_index", [used.index(i) for i in self.m])
        me.polygons.foreach_set("use_smooth", self.sm)
        if any(u is not None for u in self.uv):
            uvl = me.uv_layers.new(name="UVMap")
            for p, u, (f, fl) in zip(me.polygons, self.uv, faces):
                if u is None: u = [(0.5, 0.05)] * len(f)
                if fl: u = list(reversed(u))
                for k in range(len(f)): uvl.data[p.loop_start + k].uv = u[k]
        me.update()
        if sharp is not None: me.set_sharp_from_angle(angle=rad(sharp))
        ob = O.new(name, me); coll.objects.link(ob)
        if bone:
            b = arm.data.bones[bone]
            pm = arm.matrix_world @ b.matrix_local @ Matrix.Translation((0, b.length, 0))
            ob.parent = arm; ob.parent_type = 'BONE'; ob.parent_bone = bone
            ob.matrix_parent_inverse = pm.inverted()
        else:
            groups = {}
            for i, w in enumerate(self.w):
                tot = sum(w.values())
                for b, x in w.items():
                    if x <= 0: continue
                    g = groups.get(b) or groups.setdefault(b, ob.vertex_groups.new(name=b))
                    g.add([i], x / tot, 'REPLACE')
            ob.parent = arm
            md = ob.modifiers.new("Armature", 'ARMATURE'); md.object = arm
        print("BUILT %-18s verts %5d tris %5d" % (name, len(self.v), self.tris()))
        return ob

def loft(sk, rings, weights, centres, mat, cap0=None, cap1=None, smooth=True, uvrect=None):
    """rings: list of point lists (same count). cap0/cap1: pole points or True for a flat fan."""
    n = len(rings[0]); idx = []
    for pts, w in zip(rings, weights):
        idx.append([sk.vert(p, w) for p in pts])
    nr = len(rings) - 1
    for k in range(nr):
        for i in range(n):
            j = (i + 1) % n
            uv = None
            if uvrect:
                u0, v0, u1, v1 = uvrect
                uv = [(u0 + (u1 - u0) * i / n, v0 + (v1 - v0) * k / nr), (u0 + (u1 - u0) * (i + 1) / n, v0 + (v1 - v0) * k / nr),
                      (u0 + (u1 - u0) * (i + 1) / n, v0 + (v1 - v0) * (k + 1) / nr), (u0 + (u1 - u0) * i / n, v0 + (v1 - v0) * (k + 1) / nr)]
            sk.face([idx[k][i], idx[k][j], idx[k + 1][j], idx[k + 1][i]], mat, (np.array(centres[k]) + np.array(centres[k + 1])) / 2, smooth, uv)
    for cap, k, inner in ((cap0, 0, 1), (cap1, nr, nr - 1)):
        if cap is None: continue
        pole = np.mean(rings[k], 0) if cap is True else np.array(cap)
        pi = sk.vert(pole, weights[k])
        for i in range(n):
            sk.face([idx[k][i], idx[k][(i + 1) % n], pi], mat, centres[inner], smooth, [(0.5, 0.05)] * 3 if uvrect else None)
    return idx

def box(sk, centre, axes, size, mat, w, smooth=False, taper=1.0):
    """axes: three vectors (normalised here). taper scales the +axis[2] face."""
    c = np.array(centre, float); A = [unit(a) for a in axes]
    vs = {}
    for i in (-1, 1):
        for j in (-1, 1):
            for k in (-1, 1):
                s = taper if k > 0 else 1.0
                vs[(i, j, k)] = sk.vert(c + A[0] * i * size[0] / 2 * s + A[1] * j * size[1] / 2 * s + A[2] * k * size[2] / 2, w)
    for axis in range(3):
        for sgn in (-1, 1):
            o = [a for a in range(3) if a != axis]
            quad = []
            for (p, q) in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
                key = [0, 0, 0]; key[axis] = sgn; key[o[0]] = p; key[o[1]] = q
                quad.append(vs[tuple(key)])
            sk.face(quad, mat, c, smooth)

def lathe(sk, c0, axis, profile, seg, mat, w, smooth=True, squash=(1.0, 1.0), ref=None, mats=None):
    """profile: (radius, distance along axis). squash scales the two cross axes. mats: per-band materials."""
    axis = unit(axis)
    r0 = np.array(ref, float) if ref is not None else (np.array([0, 0, 1.0]) if abs(axis[2]) < 0.9 else np.array([1.0, 0, 0]))
    u = unit(np.cross(axis, r0)); v = np.cross(axis, u)
    c0 = np.array(c0, float)
    rings = []
    for r, h in profile:
        if r <= 1e-6: rings.append([sk.vert(c0 + axis * h, w)])
        else: rings.append([sk.vert(c0 + axis * h + (u * math.cos(a) * squash[0] + v * math.sin(a) * squash[1]) * r, w) for a in np.linspace(0, 2 * math.pi, seg, endpoint=False)])
    for k, (a, b) in enumerate(zip(rings[:-1], rings[1:])):
        mt = mats[k] if mats else mat
        inside = c0 + axis * (profile[k][1] + profile[k + 1][1]) / 2
        if abs(profile[k][1] - profile[k + 1][1]) < 1e-6:      # a flat disc: face away from the body of the part
            inside = inside - axis * (0.5 if k > len(rings) / 2 - 1 else -0.5)
        for i in range(seg):
            j = (i + 1) % seg
            if len(a) == 1 and len(b) == 1: continue
            if len(b) == 1: sk.face([a[i], a[j], b[0]], mt, inside, smooth)
            elif len(a) == 1: sk.face([a[0], b[j], b[i]], mt, inside, smooth)
            else: sk.face([a[i], a[j], b[j], b[i]], mt, inside, smooth)

def with_normal(F, axis_pt, ea=0.03, et=0.2):
    def S(a, t):
        p = F(a, t); pa = F(a + ea, t); pt = F(a, t + et)
        n = np.cross(pa - p, pt - p); ln = np.linalg.norm(n)
        if ln < 1e-9: n = p - axis_pt(t)
        n = unit(n)
        if np.dot(n, p - axis_pt(t)) < 0: n = -n
        return p, n
    return S

def plate(sk, S, a0, a1, t0, t1, na, nt, off, thick, mat, w, shape=None, bevel=0.3, ridge=None, smooth=False, skirt=0.5, axis_pt=None):
    """A raised plate on surface S(a, t). shape(u, v) -> (a, t) lets the outline taper; w is a dict or w(a, t).
    The top face is inset by `bevel` (as a fraction of a cell) and chamfers down to the outline."""
    def at(u, v):
        return shape(u, v) if shape else (a0 + (a1 - a0) * u, t0 + (t1 - t0) * v)
    def wt(a, t): return w(a, t) if callable(w) else w
    us = np.linspace(0, 1, na + 1); vs = np.linspace(0, 1, nt + 1)
    bu, bv = bevel / na, bevel / nt
    def grid(height, inset):
        g = np.zeros((na + 1, nt + 1), int)
        for i, u in enumerate(us):
            for j, v in enumerate(vs):
                uu = min(max(u, bu), 1 - bu) if inset else u
                vv = min(max(v, bv), 1 - bv) if inset else v
                a, t = at(uu, vv)
                p, n = S(a, t)
                h = height + (ridge(uu, vv) if (ridge and inset) else 0.0)
                g[i, j] = sk.vert(p + n * h, wt(a, t))
        return g
    am, tm = at(0.5, 0.5)
    pm, nm = S(am, tm)
    inside = pm - nm * 4.0
    top = grid(off + thick, True)
    for i in range(na):
        for j in range(nt):
            sk.face([top[i, j], top[i + 1, j], top[i + 1, j + 1], top[i, j + 1]], mat, inside, smooth)
    # chamfer + skirt around the border
    border = [(i, 0) for i in range(na + 1)] + [(na, j) for j in range(1, nt + 1)] + [(i, nt) for i in range(na - 1, -1, -1)] + [(0, j) for j in range(nt - 1, 0, -1)]
    def rim(height):
        out = []
        for (i, j) in border:
            a, t = at(us[i], vs[j]); p, n = S(a, t)
            out.append(sk.vert(p + n * height, wt(a, t)))
        return out
    r1 = rim(off + thick * 0.45); r2 = rim(off - skirt)
    tb = [top[i, j] for (i, j) in border]
    nb = len(border)
    for k in range(nb):
        l = (k + 1) % nb
        sk.face([tb[k], tb[l], r1[l], r1[k]], mat, inside, smooth)
        sk.face([r1[k], r1[l], r2[l], r2[k]], mat, inside, smooth)

# ------------------------------------------------------------------ body surfaces
T_W = Curve([(86.5, 5.0), (88, 10.0), (90, 12.6), (95, 15.2), (99, 15.6), (104, 13.7), (109, 10.6), (115, 8.8), (120, 9.4), (124, 10.6), (130, 11.6), (135, 12.6), (139, 14.4), (142.0, 14.0), (144.2, 10.5), (146, 7.0), (148.5, 5.2)])
T_F = Curve([(86.5, 4.0), (88, 6.3), (90, 7.4), (95, 8.0), (99, 8.1), (104, 7.7), (109, 7.1), (115, 6.7), (120, 7.2), (124, 8.2), (130, 9.0), (135, 8.6), (139, 7.4), (142.5, 6.0), (145, 5.0), (148.5, 4.4)])
T_B = Curve([(86.5, 5.0), (88, 8.0), (90, 10.0), (95, 11.2), (99, 10.6), (104, 8.8), (109, 7.3), (115, 6.7), (120, 7.1), (124, 7.8), (130, 8.6), (135, 9.0), (139, 8.6), (142.5, 7.4), (145, 6.0), (148.5, 5.4)])
T_CY = Curve([(86, 0.5), (140, 0.5), (148.5, 1.2)])
def F_torso(a, z):
    W, Fd, Bd = T_W(z), T_F(z), T_B(z)
    s, c = math.sin(a), math.cos(a)
    n = 2.35
    D = Fd if c >= 0 else Bd
    r = ((abs(s) / W) ** n + (abs(c) / D) ** n) ** (-1 / n)
    x = r * s; y = -r * c
    ax = abs(x)
    if c > 0:
        y -= 2.7 * math.exp(-((ax - 5.3) / 3.4) ** 2 - ((z - 130) / 4.6) ** 2) * min(1.0, c * 2.5)
    else:
        y += 3.6 * math.exp(-((ax - 6.6) / 4.4) ** 2 - ((z - 93.5) / 5.8) ** 2) * min(1.0, -c * 2.5)
    return np.array([x, y + T_CY(z), z])
S_torso = with_normal(F_torso, lambda z: np.array([0, T_CY(z), z]))
def w_torso(a, z):
    w = {}
    if z < 100: w["pelvis"] = 1.0
    elif z < 108: t = (z - 100) / 8; w["pelvis"] = 1 - t; w["spine"] = t
    elif z < 116: w["spine"] = 1.0
    elif z < 126: t = (z - 116) / 10; w["spine"] = 1 - t; w["chest"] = t
    elif z < 146: w["chest"] = 1.0
    else: t = min(1.0, (z - 146) / 3); w["chest"] = 1 - t; w["neck"] = t
    return {k: v for k, v in w.items() if v > 1e-4}

HIP, KNEE, ANK = bone_head("thigh.L"), bone_head("shin.L"), bone_head("foot.L")
L_R = Curve([(23, 3.4), (30, 3.6), (38, 4.4), (46, 5.0), (52, 4.7), (56, 4.8), (60, 4.9), (66, 5.5), (76, 6.3), (84, 6.9), (90, 7.3), (93, 7.2), (96, 6.6), (98.5, 4.8)])
L_F = Curve([(23, 3.6), (30, 3.8), (38, 4.4), (46, 4.8), (52, 5.0), (56, 5.6), (60, 5.6), (66, 6.2), (76, 7.1), (84, 7.9), (90, 8.2), (93, 8.2), (96, 7.2), (98.5, 5.0)])
L_B = Curve([(23, 3.8), (30, 4.0), (38, 5.4), (46, 6.2), (52, 5.3), (56, 5.0), (60, 5.2), (66, 5.8), (76, 6.9), (84, 8.0), (90, 8.8), (93, 8.8), (96, 7.6), (98.5, 5.0)])
L_CX = Curve([(ANK[2], ANK[0]), (KNEE[2], KNEE[0]), (HIP[2], 8.3), (99, 8.3)], sigma=2.0)
L_CY = Curve([(ANK[2], ANK[1]), (KNEE[2], KNEE[1]), (HIP[2], HIP[1]), (99, HIP[1])], sigma=2.0)
def leg_axis(sx): return lambda z: np.array([sx * L_CX(z), L_CY(z), z])
def F_leg(sx):
    def F(a, z):
        s, c = math.sin(a), math.cos(a)
        D = L_F(z) if c >= 0 else L_B(z)
        R = L_R(z) + (1.1 * math.exp(-((z - 84) / 9.0) ** 2) if s * sx < 0 else 0.0)
        r = ((abs(s) / R) ** 2.2 + (abs(c) / D) ** 2.2) ** (-1 / 2.2)
        return np.array([sx * L_CX(z) + r * s, L_CY(z) - r * c, z])
    return F
S_leg = {sx: with_normal(F_leg(sx), leg_axis(sx)) for sx in (-1, 1)}
def w_leg(side):
    T, Sh = "thigh." + side, "shin." + side
    def w(a, z):
        if z >= KNEE[2] + 4: return {T: 1.0}
        if z <= KNEE[2] - 4: return {Sh: 1.0}
        t = (KNEE[2] + 4 - z) / 8
        return {T: 1 - t, Sh: t}
    return w

SHO, ELB, WRI = bone_head("upper_arm.L"), bone_head("forearm.L"), bone_head("hand.L")
A_R = Curve([(-0.17, 2.6), (-0.08, 3.9), (0.0, 4.4), (0.15, 4.3), (0.5, 3.7), (0.85, 3.3), (1.0, 3.3), (1.2, 3.5), (1.5, 3.2), (1.85, 2.6), (2.0, 2.4)], sigma=0.04)
A_R.x = np.arange(-0.4, 2.4, 0.01); A_R.y = np.interp(A_R.x, [-0.2, -0.12, -0.05, 0.03, 0.15, 0.5, 0.85, 1.0, 1.2, 1.5, 1.85, 2.0], [2.8, 4.3, 4.9, 4.9, 4.4, 3.7, 3.3, 3.3, 3.5, 3.2, 2.6, 2.4])
def arm_frame(sx, t):
    m = np.array([sx, 1, 1.0])
    s, e, w = SHO * m, ELB * m, WRI * m
    d1, d2 = unit(e - s), unit(w - e)
    if t <= 1: c = s + (e - s) * t
    else: c = e + (w - e) * (t - 1)
    k = float(sstep(0.8, 1.2, t))
    d = unit(d1 * (1 - k) + d2 * k)
    fwd = np.array([0, -1.0, 0]); vf = unit(fwd - d * np.dot(d, fwd))
    out = np.array([sx, 0, 0.0]); vs = unit(out - d * np.dot(d, out) - vf * np.dot(vf, out))
    return c, d, vs, vf
def F_arm(sx):
    def F(a, t):
        c, d, vs, vf = arm_frame(sx, t)
        r = A_R(t)
        return c + r * (math.sin(a) * sx * vs + math.cos(a) * vf)
    return F
S_arm = {sx: with_normal(F_arm(sx), lambda t, sx=sx: arm_frame(sx, t)[0], ea=0.05, et=0.02) for sx in (-1, 1)}
def w_arm(side):
    U, Fo, Tw = "upper_arm." + side, "forearm." + side, "forearm_twist." + side
    def w(a, t):
        if t <= 0.8: return {U: 1.0}
        if t < 1.2: k = (t - 0.8) / 0.4; return {U: 1 - k, Fo: k}
        if t <= 1.45: return {Fo: 1.0}
        k = min(1.0, (t - 1.45) / 0.45); return {Fo: 1 - k, Tw: k}
    return w
SIDES = ((1, "L"), (-1, "R"))

# ------------------------------------------------------------------ hands, from the old meshes (their grip already fits the gun)
def old_world(o):
    for m in o.modifiers:
        if m.type == 'SUBSURF': m.show_viewport = False
    dg = bpy.context.evaluated_depsgraph_get()
    e = o.evaluated_get(dg); me = e.to_mesh()
    V = np.array([(e.matrix_world @ v.co)[:] for v in me.vertices]) * 100
    Fs = [list(p.vertices) for p in me.polygons]
    e.to_mesh_clear()
    return V, Fs
hands = None
if O.get("Body • armored female"):
    hands = SK()
    for name in ("Body • armored female", "Fingers • gloved"):
        V, Fs = old_world(O[name])
        V[:, 2] += RAISE
        V[:, 0] -= np.sign(V[:, 0]) * SHOULDER_IN
        keep = (V[:, 2] < WRI[2] + 1.2) & (np.abs(V[:, 0]) > 17)
        idx = {}
        for f in Fs:
            if all(keep[i] for i in f):
                for i in f:
                    if i not in idx: idx[i] = hands.vert(V[i], {"hand.L" if V[i][0] > 0 else "hand.R": 1.0})
                c = V[f].mean(0)
                hands.face([idx[i] for i in f], "dark", c * np.array([1, 1, 1]) + np.array([0, 0, 0]), True)
    # outward test needs a point inside each hand: use the hand bone middle
    HM = {s: (bone_head("hand." + n) + bone_tail("hand." + n)) / 2 for s, n in SIDES}
    hands.c = [tuple(HM[1] if c[0] > 0 else HM[-1]) for c in hands.c]

# ------------------------------------------------------------------ remove what is being replaced
for n in ("Body • armored female", "Armor • light plates", "Fingers • gloved", "Hair • blonde ponytail", "Skates • inline", "Shotgun • pump", "Shotgun pump", "collar_high"):
    o = O.get(n)
    if o:
        me = o.data; O.remove(o)
        if me.users == 0: bpy.data.meshes.remove(me)

# ------------------------------------------------------------------ bodysuit
suit = SK()
SEG_T = 20
zs = [86.5, 88, 90, 92.5, 95, 97.5, 100, 102.5, 105, 108, 111, 114, 117, 120, 123, 126, 129, 132, 135, 138, 140.5, 142.5, 144.5, 146.5, 148.5]
angs = [2 * math.pi * i / SEG_T for i in range(SEG_T)]
loft(suit, [[F_torso(a, z) for a in angs] for z in zs], [w_torso(0, z) for z in zs], [np.array([0, T_CY(z), z]) for z in zs], "suit", cap0=(0, 0.5, 85.6), cap1=True)
for sx, side in SIDES:
    zl = [98.5, 96, 93, 90, 86, 81, 76, 70, 65, 61, 58, 56, 54, 51, 46, 40, 34, 28, 23]
    A = [2 * math.pi * i / 12 for i in range(12)]
    Fl = F_leg(sx); wl = w_leg(side); axl = leg_axis(sx)
    loft(suit, [[Fl(a, z) for a in A] for z in zl], [wl(0, z) for z in zl], [axl(z) for z in zl], "suit", cap0=True, cap1=True)
    ts = [-0.2, -0.12, -0.05, 0.03, 0.15, 0.32, 0.5, 0.68, 0.82, 0.92, 1.0, 1.08, 1.2, 1.4, 1.6, 1.8, 2.0]
    A = [2 * math.pi * i / 10 for i in range(10)]
    Fa = F_arm(sx); wa = w_arm(side)
    loft(suit, [[Fa(a, t) for a in A] for t in ts], [wa(0, t) for t in ts], [arm_frame(sx, t)[0] for t in ts], "suit", cap0=True, cap1=True)
NK, HD = bone_head("neck"), bone_head("head")
def neck_w(z):
    if z < NK[2] + 1: return {"chest": 0.5, "neck": 0.5}
    if z < HD[2]: return {"neck": 1.0}
    return {"head": 1.0}
nz = [146.0, 148.0, 150.0, 152.0, 154.0, 156.5, 159.5]
nc = [np.array([0, 1.2 + 0.05 * (z - 146.0), z]) for z in nz]
NA = [2 * math.pi * i / 12 for i in range(12)]
loft(suit, [[c + np.array([4.15 * math.sin(a), -4.45 * math.cos(a), 0]) for a in NA] for c in nc], [neck_w(z) for z in nz], nc, "dark", cap1=True)
for z0 in (148.6, 151.4, 154.2):
    rr = [[np.array([0, 1.2 + 0.05 * (z - 146.0), z]) + np.array([(4.15 + o) * math.sin(a), -(4.45 + o) * math.cos(a), 0]) for a in NA] for z, o in ((z0, 0.0), (z0 + 0.3, 0.28), (z0 + 1.6, 0.28), (z0 + 1.9, 0.0))]
    loft(suit, rr, [neck_w(z0 + 1.0)] * 4, [np.array([0, 1.3, z0 + k * 0.6]) for k in range(4)], "steel")
suit.write("body_suit", sharp=70)

# ------------------------------------------------------------------ armour
ar = SK()
CH = {"chest": 1.0}
def red_under(S, a0, a1, t0, t1, na, nt, off, w, grow_a, grow_t, shape=None):
    if shape:
        def sh(u, v):
            a, t = shape(u, v); am, tm = shape(0.5, 0.5)
            return a + (grow_a if a > am else -grow_a) * abs(2 * u - 1), t + (grow_t if v > 0.5 else -grow_t) * abs(2 * v - 1)
        plate(ar, S, a0, a1, t0, t1, na, nt, off, 0.3, "red", w, shape=sh, bevel=0.1)
    else:
        lo, hi = min(a0, a1), max(a0, a1)
        plate(ar, S, lo - grow_a, hi + grow_a, t0 - grow_t, t1 + grow_t, na, nt, off, 0.3, "red", w, bevel=0.1)

for sx, side in SIDES:
    # chest plate, one half per side, with red edging
    def chest_shape(u, v, sx=sx):
        a = sx * rad(1.5 + 99 * u)
        zt = 140.2 - 7.0 * float(sstep(0.5, 1.0, u)) - 2.2 * float(sstep(0.25, 0.0, u))
        zb = 121.3 + 2.2 * float(sstep(0.55, 1.0, u))
        return a, zb + (zt - zb) * v
    plate(ar, S_torso, 0, 0, 0, 0, 6, 5, 0.45, 0.7, "steel", CH, shape=chest_shape, smooth=True, bevel=0.25)
    red_under(S_torso, 0, 0, 0, 0, 6, 5, 0.3, CH, rad(2.2), 0.9, shape=chest_shape)
    # back plate
    def back_shape(u, v, sx=sx):
        a = sx * rad(103 + 76 * u)
        return a, 121.5 + (140.0 - 6.0 * float(sstep(0.5, 0.0, u)) - 121.5) * v
    plate(ar, S_torso, 0, 0, 0, 0, 4, 4, 0.4, 0.6, "steel", CH, shape=back_shape, smooth=True)
    # waist: red piping either side of a dark centre strip, and side panels
    plate(ar, S_torso, sx * rad(22), sx * rad(27), 106, 121, 1, 5, 0.1, 0.3, "red", w_torso, bevel=0.1)
    plate(ar, S_torso, sx * rad(150), sx * rad(156), 106, 121, 1, 5, 0.1, 0.3, "red", w_torso, bevel=0.1)
    plate(ar, S_torso, sx * rad(62), sx * rad(112), 107.5, 119.5, 3, 3, 0.2, 0.45, "dark", w_torso, bevel=0.3)
    plate(ar, S_torso, sx * rad(2), sx * rad(100), 118.6, 120.3, 5, 1, 0.3, 0.45, "dark", w_torso, bevel=0.1)
    # pauldron: a faceted shell over the shoulder, with a lame below and red edging
    PC = SHO * np.array([sx, 1, 1]) + np.array([sx * -0.9, 0.0, 0.2])
    def F_pauld(ph, th, PC=PC, sx=sx, grow=0.0):
        flare = 0.9 * float(sstep(0.0, -0.6, th))
        rh = 7.3 + grow + flare
        return PC + rh * math.cos(th) * (math.cos(ph) * np.array([sx, 0, 0]) + math.sin(ph) * np.array([0, -1.05, 0])) + (7.0 + grow) * math.sin(th) * np.array([sx * 0.18, 0, 1.0])
    S_p = with_normal(F_pauld, lambda th, PC=PC: PC, ea=0.05, et=0.05)
    wp = {"upper_arm." + side: 0.55, "clavicle." + side: 0.45}
    plate(ar, S_p, rad(-128), rad(128), rad(-30), rad(78), 6, 4, 0.0, 0.8, "steel", wp, bevel=0.2, skirt=1.2, ridge=lambda u, v: 0.3 * (1 - abs(2 * u - 1)) ** 2)
    plate(ar, S_p, rad(-134), rad(134), rad(-37), rad(82), 6, 4, -0.15, 0.35, "red", wp, bevel=0.08, skirt=0.8)
    plate(ar, S_p, rad(-92), rad(92), rad(-62), rad(-30), 5, 1, -0.5, 0.7, "steel", {"upper_arm." + side: 0.85, "clavicle." + side: 0.15}, bevel=0.2, skirt=1.0)
    PAULD = (S_p, wp)
    if sx == 1: PAULDS = {}
    PAULDS[sx] = PAULD
    # arms
    Sa = S_arm[sx]; wa = w_arm(side)
    U = {"upper_arm." + side: 1.0}
    plate(ar, Sa, rad(28), rad(152), 0.34, 0.80, 3, 3, 0.25, 0.7, "steel", U, bevel=0.3)
    red_under(Sa, rad(28), rad(152), 0.34, 0.80, 3, 3, 0.1, U, rad(7), 0.035)
    plate(ar, Sa, rad(55), rad(215), 0.88, 1.13, 3, 2, 0.45, 0.8, "steel", {"elbow." + side: 1.0}, bevel=0.3, ridge=lambda u, v: 0.5 * (1 - abs(2 * u - 1)))
    plate(ar, Sa, rad(15), rad(255), 1.20, 1.86, 5, 3, 0.35, 1.0, "steel", wa, bevel=0.25)
    red_under(Sa, rad(15), rad(255), 1.20, 1.86, 5, 3, 0.12, wa, rad(6), 0.03)
    plate(ar, Sa, rad(0), rad(360), 1.88, 1.99, 8, 1, 0.2, 0.45, "dark", {"forearm_twist." + side: 1.0}, bevel=0.0)
    # legs
    Sl = S_leg[sx]; wl = w_leg(side)
    TH, SHN = {"thigh." + side: 1.0}, {"shin." + side: 1.0}
    def thigh_shape(u, v, sx=sx):
        a = sx * rad(-32 + 84 * u + 10 * (1 - v) * (0.5 - u))
        return a, 62.5 + 11.5 * v
    plate(ar, Sl, 0, 0, 0, 0, 4, 2, 0.25, 0.7, "steel", TH, shape=thigh_shape, bevel=0.3)
    plate(ar, Sl, sx * rad(40), sx * rad(72), 79, 90.5, 2, 2, 0.25, 0.6, "steel", TH, bevel=0.3)
    plate(ar, Sl, sx * rad(104), sx * rad(150), 78, 90, 2, 2, 0.25, 0.6, "steel", TH, bevel=0.3)
    plate(ar, Sl, sx * rad(76), sx * rad(100), 60, 91, 1, 6, 0.1, 0.35, "red", TH, bevel=0.1)
    plate(ar, Sl, sx * rad(-52), sx * rad(-74), 64, 88, 1, 4, 0.1, 0.3, "red", TH, bevel=0.1)
    def knee_shape(u, v, sx=sx):
        k = 1 - abs(2 * u - 1)
        return sx * rad(-64 + 128 * u), (KNEE[2] - 2.5 - 4.5 * k) + (9.5 + 9.0 * k) * v
    plate(ar, Sl, 0, 0, 0, 0, 4, 3, 0.7, 1.0, "steel", {"thigh." + side: 0.5, "shin." + side: 0.5}, shape=knee_shape, bevel=0.3, ridge=lambda u, v: 0.9 * (1 - abs(2 * u - 1)) * (1 - abs(2 * v - 1)))
    for a in (90, -90):
        p, n = Sl(rad(a), KNEE[2])
        lathe(ar, p - n * 0.4, n, [(2.3, 0.0), (2.3, 1.1), (1.5, 1.5), (0.0, 1.5)], 8, "dark", {"thigh." + side: 0.5, "shin." + side: 0.5}, smooth=False)
    def shin_shape(u, v, sx=sx):
        k = 1 - abs(2 * u - 1)
        return sx * rad(-80 + 160 * u), 25.5 + (20.5 + 4.5 * k) * v
    plate(ar, Sl, 0, 0, 0, 0, 6, 4, 0.5, 1.0, "steel", SHN, shape=shin_shape, bevel=0.25, ridge=lambda u, v: 0.45 * (1 - abs(2 * u - 1)) ** 2)
    plate(ar, Sl, sx * rad(84), sx * rad(106), 27, 47.5, 1, 4, 0.35, 0.45, "red", SHN, bevel=0.1)
    plate(ar, Sl, rad(118), rad(242), 30, 47, 4, 3, 0.35, 0.7, "steel", SHN, bevel=0.3)
    # boot cuff with a red strap
    plate(ar, Sl, rad(0), rad(360), 23.0, 36.0, 10, 2, 1.2, 1.0, "steel", SHN, bevel=0.0, skirt=1.6)
    plate(ar, Sl, rad(0), rad(360), 29.5, 32.5, 10, 1, 2.25, 0.3, "red", SHN, bevel=0.0, skirt=0.5)
    p, n = Sl(sx * rad(80), 31.0)
    box(ar, p + n * 2.8, (np.cross(n, [0, 0, 1.0]), [0, 0, 1.0], n), (2.6, 3.4, 0.9), "steel", SHN)

# plain badge and collar
p, n = S_torso(0.0, 137.5)
box(ar, p + n * 1.35, ([1, 0, 0], np.cross(n, [1, 0, 0]), n), (3.6, 1.6, 0.5), "steel", CH)
def collar():
    nseg = 26; gap = rad(15)
    rows = []
    for a in np.linspace(gap, 2 * math.pi - gap, nseg):
        frontness = (math.cos(a) + 1) / 2
        ztop = 150.7 - 4.4 * frontness ** 2.5; zbot = 140.6
        def pt(r_add, z):
            flare = 1.0 + 0.042 * (z - zbot)
            return ar.vert((math.sin(a) * (5.9 + r_add) * flare, 1.3 - math.cos(a) * (6.2 + r_add) * flare, z), CH)
        rows.append([pt(0.0, zbot), pt(0.0, ztop - 0.15), pt(0.75, ztop), pt(0.8, ztop - 0.8), pt(0.8, zbot)])
    ins = lambda z: (0, 1.3, z)
    for j in range(nseg - 1):
        a, b = rows[j], rows[j + 1]
        cen = np.mean([ar.v[a[1]], ar.v[b[3]]], 0)
        ringc = np.array([cen[0] * 0.93, 1.3 + (cen[1] - 1.3) * 0.93, cen[2] - 3])   # a point inside the collar wall
        wallc = np.array([(ar.v[a[0]][0] + ar.v[a[4]][0]) / 2, (ar.v[a[0]][1] + ar.v[a[4]][1]) / 2, 146.0])
        sk_in = wallc
        ar.face([a[0], a[1], b[1], b[0]], "suit", sk_in)
        ar.face([a[1], a[2], b[2], b[1]], "red", sk_in)
        ar.face([a[2], a[3], b[3], b[2]], "red", sk_in)
        ar.face([a[3], a[4], b[4], b[3]], "suit", sk_in)
    for r, nb in ((rows[0], rows[1]), (rows[-1], rows[-2])):
        ar.face([r[0], r[1], r[2], r[3], r[4]], "red", np.mean([ar.v[i] for i in nb], 0), smooth=False)
collar()

# faction fang on both pauldrons
def fang():
    with bpy.data.libraries.load(os.path.join(REPO, "Blender", "Vehicles", "Drone", "Drone.blend")) as (src, dst):
        dst.objects = [n for n in src.objects if n == "faction_fang"]
    fo = dst.objects[0]; me = fo.data
    co = np.array([v.co[:] for v in me.vertices]); cen = co.mean(0)
    _, _, vt = np.linalg.svd(co - cen)
    P = (co - cen) @ vt[:2].T                       # flatten to its own plane
    ext = P.max(0) - P.min(0)
    if ext[0] > ext[1]: P = P[:, ::-1]              # long axis vertical
    P = P - (P.max(0) + P.min(0)) / 2
    # the tip (narrow end) points down
    top_w = np.ptp(P[P[:, 1] > 0][:, 0]); bot_w = np.ptp(P[P[:, 1] < 0][:, 0])
    if bot_w > top_w: P[:, 1] *= -1
    P = P / np.ptp(P[:, 1]) * 6.2
    polys = [(list(p.vertices), me.materials[p.material_index].name) for p in me.polygons]
    bpy.data.objects.remove(fo)
    for sx, side in SIDES:
        S_p, wp = PAULDS[sx]
        base, n = S_p(0.0, rad(14))
        up = unit(np.array([0, 0, 1.0]) - n * n[2]); right = np.cross(up, n)
        ids = [ar.vert(base + n * 1.75 + right * q[0] + up * q[1], wp) for q in P]
        for f, mn in polys:
            ar.face([ids[i] for i in f], "red" if "red" in mn else "insignia", base - n * 3, smooth=False)
fang()
ar.write("armor", sharp=38)

# ------------------------------------------------------------------ gear: belt, pouches, holster, backpack
gr = SK()
PV = {"pelvis": 1.0}
plate(gr, S_torso, rad(-180), rad(180), 101.3, 105.5, 18, 1, 0.45, 0.6, "leather", PV, bevel=0.0, skirt=0.8)
p, n = S_torso(0.0, 103.4)
box(gr, p + n * 1.3, ([1, 0, 0], [0, 0, 1.0], n), (4.4, 3.6, 0.8), "steel", PV)
box(gr, p + n * 1.75, ([1, 0, 0], [0, 0, 1.0], n), (2.6, 2.0, 0.3), "dark", PV)
def pouch(S, a, z, size, w, body="leather", flap="leather_dark", drop=0.0):
    p, n = S(a, z)
    n = unit(n * np.array([1, 1, 0.0])); up = np.array([0, 0, 1.0]); tan = np.cross(up, n)
    c = p + n * (size[2] / 2 + 0.3) + up * drop
    box(gr, c, (tan, up, n), size, body, w, taper=0.92)
    box(gr, c + up * (size[1] * 0.27) + n * 0.25, (tan, up, n), (size[0] * 1.06, size[1] * 0.5, size[2] * 1.0), flap, w, taper=0.95)
    box(gr, c + up * (size[1] * 0.02) + n * (size[2] / 2 + 0.3), (tan, up, n), (0.9, 0.9, 0.35), "brass", w)
for a in (50, -50, 128, -128):
    pouch(S_torso, rad(a), 100.4, (7.6, 8.6, 3.8), PV)
for a in (88, -88):
    pouch(S_torso, rad(a), 100.9, (4.6, 6.4, 2.6), PV)
# holster on the right thigh, small pouch on the left, with straps
TR, TL = {"thigh.R": 1.0}, {"thigh.L": 1.0}
for z in (83.0, 76.8):
    plate(gr, S_leg[-1], rad(0), rad(360), z - 1.0, z + 1.0, 10, 1, 1.0, 0.3, "leather_dark", TR, bevel=0.0, skirt=1.2)
p, n = S_leg[-1](rad(-88), 77.5)
n = unit(n * np.array([1, 1, 0.0])); up = np.array([0, 0, 1.0]); tan = np.cross(up, n)
box(gr, p + n * 2.3, (tan, up, n), (5.2, 13.5, 3.2), "leather", TR, taper=0.9)
box(gr, p + n * 2.4 + up * 8.6 - tan * 1.2, (tan + up * 0.45, up - tan * 0.45, n), (3.0, 5.0, 2.2), "grip", TR)
box(gr, p + n * 2.4 + up * 6.0, (tan, up, n), (4.6, 2.2, 2.8), "gun", TR)
plate(gr, S_leg[1], rad(0), rad(360), 78.0, 80.0, 10, 1, 0.75, 0.3, "leather_dark", TL, bevel=0.0, skirt=0.9)
p, n = S_leg[1](rad(80), 78.5)
n = unit(n * np.array([1, 1, 0.0])); tan = np.cross(up, n)
box(gr, p + n * 1.9, (tan, up, n), (5.0, 6.4, 2.6), "leather", TL, taper=0.92)
box(gr, p + n * 2.1 + up * 1.7, (tan, up, n), (5.3, 3.0, 2.6), "leather_dark", TL)
# backpack on the chest
X, Y, Z = np.array([1.0, 0, 0]), np.array([0, 1.0, 0]), np.array([0, 0, 1.0])
BY = 10.3
box(gr, (0, BY + 3.6, 130.6), (X, Z, Y), (12.6, 17.6, 7.2), "steel", CH, taper=0.86)
box(gr, (0, BY + 1.0, 130.6), (X, Z, Y), (14.2, 14.0, 2.0), "dark", CH)
box(gr, (0, BY + 3.2, 140.2), (X, Y, Z), (10.2, 5.6, 1.8), "dark", CH, taper=0.8)
box(gr, (0, BY + 3.0, 121.0), (X, Y, -Z), (9.0, 5.0, 2.4), "dark", CH, taper=0.8)
box(gr, (0, BY + 7.25, 130.8), (X, Z, Y), (4.6, 13.0, 0.5), "dark", CH)
box(gr, (0, BY + 7.55, 130.8), (X, Z, Y), (2.7, 10.8, 0.5), "amber", CH)
for sx in (-1, 1):
    lathe(gr, (sx * 8.3, BY + 3.2, 122.6), Z, [(0.0, 0.0), (2.0, 0.0), (2.15, 0.6), (2.15, 8.6), (1.5, 9.4), (1.5, 10.2), (0.0, 10.2)], 10, "dark", CH, mats=["dark", "dark", "steel", "dark", "brass", "brass"])
    box(gr, (sx * 6.9, BY + 3.2, 127.0), (X, Y, Z), (1.4, 2.4, 1.6), "dark", CH)
gr.write("gear", sharp=35)

# ------------------------------------------------------------------ hands
if hands:
    hands.write("hands", sharp=60)
    hands_ob = O["hands"]
elif not O.get("hands"):
    raise SystemExit("hands missing: run from the stage 1 base")

# ------------------------------------------------------------------ skates
skt = SK()
for sx, side in SIDES:
    FT = {"foot." + side: 1.0}
    cx = sx * 7.9
    secs = [(9.6, 3.6, 9.0, 22.0), (6.5, 4.7, 8.6, 25.5), (0.4, 5.1, 8.6, 26.5), (-6.0, 5.2, 8.6, 23.0), (-12.0, 5.2, 8.6, 18.5), (-17.5, 4.9, 8.6, 15.6), (-21.5, 3.8, 8.9, 13.2)]
    rings, cens = [], []
    for (y, hw, zb, zt) in secs:
        zc, hh = (zb + zt) / 2, (zt - zb) / 2
        ring = []
        for k in range(10):
            a = 2 * math.pi * k / 10 + math.pi / 10
            s, c = math.sin(a), math.cos(a)
            r = ((abs(s)) ** 3.2 + (abs(c)) ** 3.2) ** (-1 / 3.2)
            ring.append(np.array([cx + hw * r * s, y, zc + hh * r * c]))
        rings.append(ring); cens.append(np.array([cx, y, zc]))
    loft(skt, rings, [FT] * len(rings), cens, "steel", cap0=True, cap1=(cx, -23.4, 11.0))
    box(skt, (cx, -6.0, 8.2), (X, Y, Z), (10.2, 31.5, 1.6), "dark", FT)                       # sole
    box(skt, (cx, -16.5, 14.7), (X, Y + Z * 0.33, Z - Y * 0.33), (10.4, 6.0, 1.3), "dark", FT)  # toe strap
    box(skt, (cx, -7.5, 20.6), (X, Y + Z * 0.75, Z - Y * 0.75), (10.9, 3.2, 1.3), "red", FT)    # instep strap
    box(skt, (cx + sx * 5.4, -7.5, 20.6), (Y + Z * 0.75, X, Z - Y * 0.75), (3.6, 1.0, 2.2), "steel", FT)
    box(skt, (sx * 8.0, -6.3, 7.2), (X, Y, Z), (5.6, 30.0, 1.6), "dark", FT)                 # frame spine
    for off in (-2.6, 2.6):
        box(skt, (sx * 8.0 + off, -6.3, 5.0), (X, Y, Z), (0.8, 31.0, 3.4), "steel", FT)        # frame cheeks
    for off in (-5.3, 5.3):
        box(skt, (cx + off, 1.5, 12.6), (X, Y, Z), (0.6, 7.0, 2.2), "amber", FT)              # light bars
    box(skt, (cx, 10.0, 13.6), (X, Y, Z), (4.0, 0.6, 2.2), "amber", FT)                       # heel light
skt.write("skates", sharp=45)

# wheels: same objects and bones, new meshes with amber hubs (axis = local x, metres)
def wheel_mesh(name):
    sk = SK()
    Wd = {}
    prof = [(0.0, -2.0), (1.9, -2.0), (1.9, -1.75), (2.6, -1.75), (3.1, -2.0), (3.45, -1.1), (3.45, 1.1), (3.1, 2.0), (2.6, 1.75), (1.9, 1.75), (1.9, 2.0), (0.0, 2.0)]
    mats = ["amber", "amber", "steel", "rubber", "rubber", "rubber", "rubber", "rubber", "steel", "amber", "amber"]
    lathe(sk, (0, 0, 0), (1, 0, 0), prof, 14, "rubber", Wd, mats=mats)
    V = np.array(sk.v) / 100
    faces = []
    for f, c in zip(sk.f, sk.c):
        p = V[f]; n = np.cross(p[1] - p[0], p[2] - p[0])
        cc = p.mean(0); out = cc - np.array([np.clip(cc[0], -0.012, 0.012), 0, 0])
        faces.append(f if np.dot(n, out) >= 0 else list(reversed(f)))
    me = bpy.data.meshes.new(name)
    me.from_pydata([tuple(p) for p in V], [], faces)
    used = sorted(set(sk.m))
    for i in used: me.materials.append(M[MAT_ORDER[i]])
    me.polygons.foreach_set("material_index", [used.index(i) for i in sk.m])
    me.polygons.foreach_set("use_smooth", [True] * len(faces))
    me.update(); me.set_sharp_from_angle(angle=rad(40))
    return me
wm = wheel_mesh("skate_wheel")
for o in list(O):
    if o.name.startswith("Skate wheel "):
        old = o.data; o.data = wm
        o.name = "skate_wheel_" + o.name.split(" ")[-1]
        if old.users == 0: bpy.data.meshes.remove(old)
print("BUILT skate wheels: 8 x", sum(len(p.vertices) - 2 for p in wm.polygons), "tris")

# ------------------------------------------------------------------ shotgun, in the gun bone's own space (barrel along -y, tip at the flash bone)
GB = arm.data.bones["gun"]
GM = np.array(arm.matrix_world @ GB.matrix_local)
FL = (np.linalg.inv(GM) @ np.append(bone_head("flash") / 100, 1))[:3] * 100
PB = (np.linalg.inv(GM) @ np.append(bone_head("pump") / 100, 1))[:3] * 100
print("gun space: flash", FL.round(2), "pump", PB.round(2))
class GunSK(SK):
    def vert(self, p, w):
        q = GM @ np.array([p[0] / 100, p[1] / 100, p[2] / 100, 1.0])
        return SK.vert(self, q[:3] * 100, w)
def gpt(p): return (GM @ np.array([p[0] / 100, p[1] / 100, p[2] / 100, 1.0]))[:3] * 100
class GunBuilder:
    """Builds in gun space; inside-points are converted for the outward test."""
    def __init__(self): self.sk = SK()
    def box(self, c, size, mat, axes=(X, Y, Z), taper=1.0):
        R = GM[:3, :3]
        box(self.sk, gpt(c), [R @ unit(a) for a in axes], size, mat, {}, taper=taper)
    def lathe(self, c0, axis, profile, seg, mat, squash=(1, 1), mats=None, smooth=True):
        R = GM[:3, :3]
        lathe(self.sk, gpt(c0), R @ unit(axis), profile, seg, mat, {}, smooth=smooth, squash=squash, ref=R @ Z, mats=mats)
BZ = FL[2]           # barrel height
g = GunBuilder()
g.box((0, -1.0, BZ - 1.6), (3.6, 22.0, 7.0), "gun")                                         # receiver
g.box((0, -1.0, BZ + 2.3), (1.9, 20.0, 0.9), "gun")                                         # top rail
for k in range(6):
    g.box((0, -9.5 + k * 3.4, BZ + 2.95), (1.9, 1.5, 0.5), "gun")
g.box((0, -9.8, BZ + 3.4), (0.5, 1.6, 1.3), "gun")                                          # rear sight
g.lathe((0, -12.0, BZ), -Y, [(1.05, 0.0), (1.05, FL[1] * -1 - 12.0 - 3.4), (1.45, FL[1] * -1 - 12.0 - 3.4), (1.45, FL[1] * -1 - 12.0), (0.75, FL[1] * -1 - 12.0), (0.75, FL[1] * -1 - 15.0)], 10, "gun")   # barrel + muzzle
g.lathe((0, -12.0, BZ - 2.6), -Y, [(0.95, 0.0), (0.95, 39.5), (0.0, 39.9)], 8, "gun")       # magazine tube
g.box((0, -50.0, BZ - 1.3), (2.6, 1.5, 5.0), "gun")                                         # barrel band
g.box((0, -33.0, BZ + 1.45), (2.4, 21.0, 0.5), "gun")                                       # heat shield
for k in range(5):
    g.box((0, -41.0 + k * 4.0, BZ + 1.8), (1.6, 2.0, 0.3), "grip")
g.box((0, 3.9, 1.5), (2.7, 3.7, 11.0), "grip", axes=(X, Y - Z * 0.27, Z + Y * 0.27))       # pistol grip
g.box((0, -2.4, 4.4), (0.9, 6.0, 0.5), "gun"); g.box((0, -5.2, 5.6), (0.9, 0.5, 2.6), "gun")  # trigger guard
g.box((0, -1.2, 5.6), (0.5, 0.6, 1.8), "gun", axes=(X, Y - Z * 0.3, Z + Y * 0.3))          # trigger
g.box((0, 19.5, BZ + 0.2), (2.2, 19.5, 1.6), "gun", axes=(X, Y - Z * 0.05, Z + Y * 0.05))  # stock, upper strut
g.box((0, 19.3, 4.6), (1.8, 20.0, 1.4), "gun", axes=(X, Y - Z * 0.27, Z + Y * 0.27))       # stock, lower strut
g.box((0, 20.0, 8.3), (1.4, 1.2, 6.4), "gun")                                               # stock brace
g.box((0, 29.9, 6.9), (2.8, 1.8, 11.6), "grip")                                             # butt pad
g.box((-1.85, PB[1] + 19.0, BZ - 0.6), (0.3, 5.0, 1.8), "grip")                            # ejection port
shot = g.sk.write("shotgun", sharp=40, bone="gun")
g = GunBuilder()
ribs = []
y0 = -PB[1] - 2.5       # 2.5 cm behind the pump bone, running forward
for k in range(7):
    ribs += [(2.05, k * 2.1), (2.05, k * 2.1 + 1.3), (1.75, k * 2.1 + 1.45), (1.75, k * 2.1 + 1.95)]
ribs = [(0.0, 0.0)] + ribs[:-1] + [(0.0, ribs[-2][1])]
g.lathe((0, PB[1] + 2.5, BZ - 2.75), -Y, ribs, 10, "wood", squash=(1.0, 0.9))
g.sk.write("shotgun_pump", sharp=40, bone="pump")

# ------------------------------------------------------------------ ponytail, textured from the head atlas
STRAND_UV = (0.16, 0.01, 0.99, 0.125)
pt = SK()
H1, H2, H3, H3T = bone_head("hair1"), bone_head("hair2"), bone_head("hair3"), bone_tail("hair3")
path = [(7.0, 166.6, 1.7, 1.7), (11.6, 167.8, 2.0, 2.0), (13.6, 168.6, 2.3, 2.2), (16.6, 170.0, 4.0, 3.2), (20.4, 168.6, 4.9, 3.7), (22.8, 163.5, 5.2, 3.9),
        (23.6, 157.0, 4.9, 3.7), (23.4, 150.5, 4.2, 3.2), (22.6, 144.5, 3.2, 2.5), (21.6, 139.8, 1.9, 1.5)]
segp = 12
rings, cens, ws = [], [], []
for k, (y, z, rx, rd) in enumerate(path):
    y0_, z0_ = path[max(k - 1, 0)][:2]; y1_, z1_ = path[min(k + 1, len(path) - 1)][:2]
    tan = unit([0, y1_ - y0_, z1_ - z0_]); nrm = np.cross([1.0, 0, 0], tan)
    ring = []
    for i in range(segp):
        a = 2 * math.pi * i / segp
        lump = 1 + (0.10 * math.sin(5 * a + k * 0.9) if k > 2 else 0.0)
        ring.append(np.array([0, y, z]) + np.array([1.0, 0, 0]) * rx * lump * math.cos(a) + nrm * rd * lump * math.sin(a))
    rings.append(ring); cens.append(np.array([0, y, z]))
    if z > 160 or k < 5: w = {"hair1": 1.0}
    elif z > 152: t = (160 - z) / 8; w = {"hair1": 1 - t, "hair2": t}
    elif z > 144: t = (152 - z) / 8; w = {"hair2": 1 - t, "hair3": t}
    else: w = {"hair3": 1.0}
    ws.append(w)
loft(pt, rings, ws, cens, "head", cap0=True, cap1=(20.9, 136.2) and (0, 20.9, 136.2), uvrect=STRAND_UV)
lathe(pt, (0, 11.2, 167.7), unit([0, 2.0, 0.8]), [(0.0, 0.0), (2.55, 0.0), (2.7, 0.4), (2.7, 1.5), (2.55, 1.9), (0.0, 1.9)], 10, "band", {"hair1": 1.0})
for f in range(len(pt.f)):
    if pt.uv[f] is None: pt.uv[f] = [(0.5, 0.05)] * len(pt.f[f])
pt.write("ponytail", sharp=70)

# ------------------------------------------------------------------ clips: the gun stays in the right hand, the left hand stays on the pump
def refit_clips():
    arm.data.pose_position = 'POSE'
    pb = arm.pose.bones
    worst = -1.0
    for act in CLIPS:
        A = bpy.data.actions[act]; arm.animation_data.action = A
        frames = list(range(int(A.frame_range[0]), int(A.frame_range[1]) + 1))
        snap = {}
        for f in frames:
            scn.frame_set(f)
            snap[f] = (pb["upper_arm.L"].matrix.copy(), pb["forearm.L"].matrix.copy(), pb["hand.L"].matrix.copy())
        for f in frames:
            scn.frame_set(f)
            C, L = OLD[(act, f)]
            G = pb["hand.R"].matrix @ C
            pb["gun"].matrix = G
            H = G @ L
            up0, fo0, ha0 = snap[f]
            Sp = up0.translation.copy(); E0 = fo0.translation.copy(); T = H.translation.copy()
            l1 = (fo0.translation - up0.translation).length; l2 = (ha0.translation - fo0.translation).length
            worst = max(worst, (T - Sp).length - (l1 + l2))
            d = min(max((T - Sp).length, abs(l1 - l2) + 1e-4), l1 + l2 - 1e-4)
            n = (T - Sp).normalized()
            a_ = (l1 * l1 - l2 * l2 + d * d) / (2 * d); h = math.sqrt(max(l1 * l1 - a_ * a_, 0.0))
            pole = (E0 - Sp) - n * (E0 - Sp).dot(n)
            pole = pole.normalized() if pole.length > 1e-6 else Vector((0, 1, 0))
            E = Sp + n * a_ + pole * h
            q1 = (E0 - Sp).rotation_difference(E - Sp)
            pb["upper_arm.L"].matrix = Matrix.Translation(Sp) @ (q1.to_matrix() @ up0.to_3x3()).to_4x4()
            bpy.context.view_layer.update()
            cur = pb["forearm.L"].matrix.copy()
            base = q1.to_matrix() @ fo0.to_3x3()
            q2 = (q1.to_matrix() @ (ha0.translation - fo0.translation)).rotation_difference(Sp + n * d - E)
            pb["forearm.L"].matrix = Matrix.Translation(cur.translation) @ (q2.to_matrix() @ base).to_4x4()
            bpy.context.view_layer.update()
            Hm = H.copy(); Hm.translation = pb["hand.L"].matrix.translation
            pb["hand.L"].matrix = Hm
            bpy.context.view_layer.update()
            pb["gun"].keyframe_insert("location", frame=f, group="gun"); pb["gun"].keyframe_insert("rotation_quaternion", frame=f, group="gun")
            for b in ("upper_arm.L", "forearm.L", "hand.L"):
                pb[b].keyframe_insert("rotation_quaternion", frame=f, group=b)
        err_r = err_l = 0.0; low = 1e9; hi = -1e9
        for f in frames:
            scn.frame_set(f)
            C, L = OLD[(act, f)]
            g = pb["gun"].matrix
            err_r = max(err_r, ((pb["hand.R"].matrix @ C).translation - g.translation).length)
            err_l = max(err_l, ((g @ L).translation - pb["hand.L"].matrix.translation).length)
            wl = min((o.matrix_world @ Vector(c)).z for o in O if o.name.startswith("skate_wheel") for c in o.bound_box)
            low = min(low, wl); hi = max(hi, wl)
        print("CLIP %-5s frames %d  gun-to-right-hand error %.1f mm, left-hand error %.1f mm, lowest wheel %.1f..%.1f mm" % (act, len(frames), err_r * 1000, err_l * 1000, low * 1000, hi * 1000))
    print("left arm reach beyond full length (m, negative is fine): %.4f" % worst)
    arm.animation_data.action = bpy.data.actions["idle"]; scn.frame_set(1)
if OLD: refit_clips()

# ------------------------------------------------------------------ tidy: unused old materials and meshes
for m in list(bpy.data.materials):
    if m.users == 0 and not m.use_fake_user: bpy.data.materials.remove(m)
total = 0
for o in coll.objects:
    if o.type == 'MESH':
        t = sum(len(p.vertices) - 2 for p in o.data.polygons)
        if any(md.type == 'MIRROR' for md in o.modifiers): t *= 2
        total += t
print("TOTAL export triangles (subdivision off):", total)
print("names clash with bones:", [o.name for o in O if o.name in arm.data.bones or o.name.replace(".", "_") in [b.name.replace(".", "_") for b in arm.data.bones]])
arm.data.pose_position = 'POSE'
if OUT:
    bpy.ops.wm.save_as_mainfile(filepath=OUT)
    print("SAVED", OUT)
