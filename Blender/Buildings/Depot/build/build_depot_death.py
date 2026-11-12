"""Builds DepotDeath.blend and DepotTruckDeath.blend and exports the Depot's and the Depot Truck's deaths
(docs/DEPOT_MODEL.md).

  blender Depot.blend --background --python build/build_depot_death.py

Depot.blend is only read: depot.glb and depot_truck.glb carry clips assembled from three working files,
so they are not re-exported to add a death. Instead, as with the Tank's deaths, each death is an effect
GLB holding stand-in empties named Drive_<part>, one for each part that moves, nested as the parts are.
Their rest pose is the part's own (the finished warehouse at frame 240 for the Depot, the closed truck
at frame 1 for the truck), and scripts/components/driven_death.gd copies their keyed transforms onto the
real parts each frame. Drive_Scorch carries how burnt the model looks in its keyed scale. The fire,
smoke and debris are ordinary keyed meshes, as in the other death effects.

The script starts new files each run, so it can be re-run. Each death gets its own file beside Depot.blend,
as the stand-ins of both are named after the same parts: DepotDeath.blend (collection depot_death_fx) and
DepotTruckDeath.blend (collection depot_truck_death_fx). It writes assets/models/effects/depot_death_fx.glb
and depot_truck_death_fx.glb. Both clips are named Death, at 24 fps, starting at frame 0.
"""
import bpy, bmesh, math, os, random
from math import sin, cos, pi, exp, sqrt
from mathutils import Vector as V, Matrix, Quaternion

HERE = os.path.dirname(os.path.abspath(__file__))
DEPOT_DIR = os.path.normpath(os.path.join(HERE, ".."))
ASSETS = os.path.normpath(os.path.join(HERE, "..", "..", "..", "..", "assets", "models", "effects"))
FPS = 24
X, Y, Z = V((1, 0, 0)), V((0, 1, 0)), V((0, 0, 1))
NIL = V((0.001, 0.001, 0.001))
IDQ = Quaternion()
GRAV = 9.8


# ---------------------------------------------------------------- read the parts from Depot.blend
def snapshot(frame):
    """name -> (parent name or None, world matrix, world bbox min, world bbox max) for the visible parts."""
    scene = bpy.context.scene
    scene.frame_set(frame)
    bpy.context.view_layer.update()
    col = bpy.data.collections["depot_warehouse"]
    parts = {}
    for ob in col.all_objects:
        w = ob.matrix_world.copy()
        if max(w.to_scale()) < 0.01:      # shrunk to nothing; flattened parts are still there
            continue
        if ob.type == 'MESH':
            pts = [w @ V(c) for c in ob.bound_box]
        else:
            pts = [w.translation]
        lo = V((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
        hi = V((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
        parts[ob.name] = (ob.parent.name if ob.parent else None, w, lo, hi)
    # A part whose parent is hidden is not in the GLB either.
    while True:
        gone = [n for n, p in parts.items() if p[0] is not None and p[0] not in parts]
        if not gone:
            return parts
        for n in gone:
            del parts[n]


DEPOT = snapshot(240)
TRUCK = snapshot(1)

# ---------------------------------------------------------------- a new file
bpy.ops.wm.read_homefile(use_empty=True)
scene = bpy.context.scene
scene.render.fps = FPS
random.seed(11)


def sm(x):
    x = max(0.0, min(1.0, x))
    return x * x * (3 - 2 * x)


def ramp(t, a, b):
    return sm((t - a) / (b - a))


def lin(t, a, b):
    return max(0.0, min(1.0, (t - a) / (b - a)))


def fall(t, a, b):
    """Accelerating from rest at a, landing at b with a small bounce."""
    k = lin(t, a, b)
    land = k * k
    after = max(0.0, t - b)
    return land - 0.06 * exp(-after * 9) * sin(after * 22) * (1 if t > b else 0)


def Tm(p):
    return Matrix.Translation(V(p))


def Rx(a):
    return Matrix.Rotation(a, 4, 'X')


def Ry(a):
    return Matrix.Rotation(a, 4, 'Y')


def Rz(a):
    return Matrix.Rotation(a, 4, 'Z')


def Sc(v):
    return Matrix.Diagonal((*V(v), 1))


def about(pivot, R):
    return Tm(pivot) @ R @ Tm(-V(pivot))


def rnd(a, b):
    return random.uniform(a, b)


def collection(name):
    c = bpy.data.collections.new(name)
    scene.collection.children.link(c)
    return c


def push(ob, clip):
    ad = ob.animation_data
    act = ad.action
    act.name = clip + "_" + ob.name
    track = ad.nla_tracks.new()
    track.name = clip
    strip = track.strips.new(clip, 0, act)
    strip.name = clip
    ad.action = None


def bake(ob, frames, fn):
    """fn(t) -> matrix in the object's parent space."""
    ob.rotation_mode = 'QUATERNION'
    rest = ob.matrix_basis.copy()
    prev = None
    for f in range(frames + 1):
        loc, q, sc = fn(f / FPS).decompose()
        sc = V((max(sc.x, 0.001), max(sc.y, 0.001), max(sc.z, 0.001)))
        if prev is not None and prev.dot(q) < 0:
            q.negate()
        prev = q.copy()
        ob.location, ob.rotation_quaternion, ob.scale = loc, q, sc
        ob.keyframe_insert("location", frame=f)
        ob.keyframe_insert("rotation_quaternion", frame=f)
        ob.keyframe_insert("scale", frame=f)
    push(ob, "Death")
    ob.matrix_basis = rest


# ---------------------------------------------------------------- materials and meshes for the effects
def fx_material(name, col, rough=0.8, emis=None, strength=0.0, alpha=1.0, met=0.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = next(n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    b.inputs["Base Color"].default_value = (*col, 1)
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = met
    if emis:
        b.inputs["Emission Color"].default_value = (*emis, 1)
        b.inputs["Emission Strength"].default_value = strength
    if alpha < 1.0:
        b.inputs["Alpha"].default_value = alpha
        m.blend_method = 'BLEND'
        m.surface_render_method = 'BLENDED'
    m.diffuse_color = (*col, alpha)
    return m


def mesh_from(bm, name, mats, smooth=False):
    for f in bm.faces:
        f.smooth = smooth
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    for m in mats:
        me.materials.append(m)
    return me


def ico_mesh(name, mat, sub=1, jitter=0.0, smooth=False, radius=1.0):
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=sub, radius=radius)
    for v in bm.verts:
        v.co *= 1 + random.uniform(-jitter, jitter)
    return mesh_from(bm, name, [mat], smooth)


def shard_mesh(name, mat):
    """A thin diamond lying along Y, one unit long."""
    bm = bmesh.new()
    a, b = bm.verts.new((0, -0.5, 0)), bm.verts.new((0, 0.5, 0))
    ring = [bm.verts.new((0.12 * cos(i * pi / 2), -0.15, 0.12 * sin(i * pi / 2))) for i in range(4)]
    for i in range(4):
        j = (i + 1) % 4
        bm.faces.new((a, ring[j], ring[i]))
        bm.faces.new((b, ring[i], ring[j]))
    return mesh_from(bm, name, [mat])


def plate_mesh(name, mats, bend=0.18):
    """A bent sheet about one unit across, two faces coloured differently."""
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0, matrix=Sc((1.0, 0.7, 0.05)))
    bmesh.ops.subdivide_edges(bm, edges=[e for e in bm.edges if abs((e.verts[0].co - e.verts[1].co).x) > 0.5], cuts=3)
    for v in bm.verts:
        v.co.z += bend * v.co.x * v.co.x + random.uniform(-0.03, 0.03)
    for f in bm.faces:
        f.material_index = 1 if f.normal.z > 0.5 else 0
    return mesh_from(bm, name, mats)


def flame_mesh(name, mat):
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=5, radius1=1.0, radius2=0.02, depth=1.0, matrix=Tm((0, 0, 0.5)))
    return mesh_from(bm, name, [mat])


def disc_mesh(name, mat):
    bm = bmesh.new()
    ring = []
    for i in range(24):
        a = 2 * pi * i / 24
        r = 1.0 + 0.14 * sin(3 * a + 1.0) + 0.08 * sin(7 * a)
        ring.append(bm.verts.new((r * cos(a), r * sin(a), 0)))
    bm.faces.new(ring)
    return mesh_from(bm, name, [mat])


def fx(coll, name, mesh, frames, fn):
    """fn(t) -> (location, quaternion or None, scale as float or vector) or None while unseen."""
    ob = bpy.data.objects.new(name, mesh)
    coll.objects.link(ob)
    last = [V((0, 0, 0))]

    def mat(t):
        r = fn(t)
        if r is None:
            return Tm(last[0]) @ Sc(NIL)
        loc, q, sc = r
        last[0] = V(loc)
        if not isinstance(sc, V):
            sc = V((sc, sc, sc))
        sc = V((max(sc.x, 0.001), max(sc.y, 0.001), max(sc.z, 0.001)))
        return Tm(loc) @ (q or IDQ).to_matrix().to_4x4() @ Sc(sc)
    bake(ob, frames, mat)
    ob.location, ob.scale = (0, 0, 0), NIL
    return ob


def ballistic(p0, v, s, g=GRAV):
    return V(p0) + V(v) * s + V((0, 0, -0.5 * g * s * s))


def setup():
    """The effects' materials and meshes, made afresh in each file."""
    global M_BALL, FIREBALL, M_SPARK, M_EMBER, M_FLASH, M_FIRE, M_SMOKE, M_SOOT, M_OIL, M_CANVAS, M_BURNT, M_SCRAP, M_OLIVE, SPARK, EMBER, PUFF, FLAME, CORE, SHRED, SCRAP, SOOT, POOL
    M_SPARK = fx_material("depot_fx_spark", (0, 0, 0), 0.8, (1.0, 0.62, 0.18), 5.0)
    M_EMBER = fx_material("depot_fx_ember", (0, 0, 0), 0.8, (1.0, 0.4, 0.1), 4.0)
    M_FLASH = fx_material("depot_fx_flash", (0, 0, 0), 0.8, (1.0, 0.8, 0.4), 3.2)
    M_FIRE = fx_material("depot_fx_fire", (0, 0, 0), 0.8, (1.0, 0.24, 0.03), 1.4)
    M_SMOKE = fx_material("depot_fx_smoke", (0.05, 0.045, 0.045), 1.0)
    M_SOOT = fx_material("depot_fx_soot", (0.02, 0.018, 0.016), 1.0)
    M_OIL = fx_material("depot_fx_oil", (0.012, 0.011, 0.016), 0.07)
    M_CANVAS = fx_material("depot_fx_canvas", (0.30, 0.28, 0.17), 0.95)
    M_BURNT = fx_material("depot_fx_burnt", (0.06, 0.05, 0.04), 1.0)
    M_SCRAP = fx_material("depot_fx_scrap", (0.13, 0.13, 0.14), 0.5, None, 0.0, 1.0, 0.6)
    M_OLIVE = fx_material("depot_fx_olive", (0.20, 0.21, 0.12), 0.7)
    M_BALL = fx_material("depot_fx_fireball", (0.85, 0.3, 0.04), 0.9, (1.0, 0.38, 0.06), 1.1)
    SPARK = shard_mesh("fxm_spark", M_SPARK)
    EMBER = shard_mesh("fxm_ember", M_EMBER)
    PUFF = ico_mesh("fxm_smoke", M_SMOKE, 2, 0.1, True)
    FLAME = flame_mesh("fxm_flame", M_FIRE)
    CORE = ico_mesh("fxm_core", M_FLASH, 1, 0.0, False, 0.6)
    SHRED = plate_mesh("fxm_shred", [M_CANVAS, M_BURNT], 0.3)
    SCRAP = plate_mesh("fxm_scrap", [M_SCRAP, M_OLIVE])
    SOOT = disc_mesh("fxm_soot", M_SOOT)
    POOL = disc_mesh("fxm_pool", M_OIL)
    FIREBALL = ico_mesh("fxm_fireball", M_BALL, 2, 0.12, True)


setup()


# ---------------------------------------------------------------- the stand-ins
def drives(coll, parts, frames, motion, sink):
    """One Drive_<part> empty per part, nested as the parts are. motion(name, t) -> a world-space change
    for that part (None: it moves with its parent), sink(t) -> the whole model's drop. Each empty is keyed
    in its parent's space, so the game can copy it straight onto the real part."""
    home = {n: p[1] for n, p in parts.items()}

    def world(name, t, memo):
        if name in memo:
            return memo[name]
        parent = parts[name][0]
        d = motion(name, t)
        if d is not None:
            w = sink(t) @ d @ home[name]
        elif parent is None:
            w = sink(t) @ home[name]
        else:
            w = world(parent, t, memo) @ (home[parent].inverted() @ home[name])
        memo[name] = w
        return w
    empties = {}
    for name in sorted(parts, key=lambda n: (len(_chain(parts, n)), n)):
        e = bpy.data.objects.new("Drive_" + name, None)
        e.empty_display_size = 0.3
        coll.objects.link(e)
        parent = parts[name][0]
        if parent is not None:
            e.parent = empties[parent]
            e.matrix_parent_inverse = Matrix.Identity(4)
        empties[name] = e
    cache = {}

    def at(t):
        if t not in cache:
            cache[t] = {}
        return cache[t]
    for name, e in empties.items():
        parent = parts[name][0]

        def local(t, name=name, parent=parent):
            memo = at(t)
            w = world(name, t, memo)
            return w if parent is None else world(parent, t, memo).inverted() @ w
        e.matrix_basis = local(0.0)
        bake(e, frames, local)
    return empties


def _chain(parts, n):
    out = []
    while n is not None:
        out.append(n)
        n = parts[n][0]
    return out


def scorch(coll, frames, fn):
    e = bpy.data.objects.new("Drive_Scorch", None)
    coll.objects.link(e)
    bake(e, frames, lambda t: Sc(V((1, 1, 1)) * max(fn(t), 0.001)))


def bbox(parts, name):
    return parts[name][2], parts[name][3]


def centre(parts, name):
    lo, hi = bbox(parts, name)
    return (lo + hi) * 0.5


def hidden_at(name, t0):
    """A part that is blown away at t0: shrunk to nothing where it is."""
    return lambda t: Sc(V((1, 1, 1))) if t < t0 else None


# ================================================================= the Depot
D_END = 6.0
D_FRAMES = int(D_END * FPS)
TB = 0.35                              # the stored crates go up
SINK0, SINK = 4.3, 9.5
C = collection("depot_death_fx")
P = DEPOT
FLOOR_TOP = max(bbox(P, "warehouse_floor_L1")[1].z, bbox(P, "warehouse_deck")[1].z)


def d_sink(t):
    return Tm(-Z * SINK * ramp(t, SINK0, D_END))


def sunk(p, t):
    return V(p) - Z * SINK * ramp(t, SINK0, D_END)


def fade(t):
    return 1 - ramp(t, SINK0 + 0.2, D_END - 0.1)


def tarp_fall(side, t):
    """A roof half sags in about its outer eave and drops onto the floor, then burns down to its frame."""
    lo, hi = bbox(P, "warehouse_tarp_" + side)
    sgn = 1 if side == "L" else -1
    pivot = V((hi.x if sgn > 0 else lo.x, 0.0, lo.z))
    k = fall(t, TB + 0.15, 1.45)
    heave = 0.7 * sin(pi * lin(t, TB, TB + 0.4))
    swing = about(pivot, Ry(-sgn * (0.72 * k - 0.06 * heave)))
    drop = Tm(Z * heave - Z * 2.9 * k)
    burn = 1 - 0.45 * ramp(t, 1.8, 4.2)
    shrink = about(pivot - Z * 2.9 * k, Sc((burn, 1, burn)))
    return shrink @ drop @ swing


# The front end wall falls in onto the floor, the back one out over the ramp.
GABLE = {"F": (TB + 0.15, TB + 1.05, -1.15, 2.9), "B": (TB + 0.55, TB + 1.75, -1.35, 5.0)}


def gable_fall(side, t):
    lo, hi = bbox(P, "warehouse_tarp_gable_" + side)
    t0, t1, ang, drop = GABLE[side]
    pivot = V((0.0, (lo.y + hi.y) * 0.5, lo.z))
    wobble = 0.05 * sin(max(0.0, t - TB) * 30) * (1 - lin(t, TB, t0)) if t > TB else 0.0
    k = fall(t, t0, t1)
    return Tm(-Z * drop * k) @ about(pivot, Rx(ang * k + wobble))


def ridge_fall(t):
    lo, hi = bbox(P, "warehouse_ridge")
    k = fall(t, TB + 0.1, 1.2)
    front = V((0.0, lo.y, hi.z))
    heave = 1.0 * sin(pi * lin(t, TB, TB + 0.4))
    return Tm(Z * heave - Z * (hi.z - FLOOR_TOP - 0.9) * k) @ about(front, Rx(0.06 * k) @ Ry(0.1 * k))


def wing_tip(side, t):
    lo, hi = bbox(P, "warehouse_floor_%s2" % side)
    sgn = 1 if side == "L" else -1
    hinge = V((lo.x if sgn > 0 else hi.x, 0.0, hi.z))
    k = ramp(t, TB, TB + 0.3)
    return about(hinge, Ry(sgn * 0.16 * k) @ Rx(0.03 * sgn * k))


def eave_drop(side, t):
    """The eave rails come down with the roof, onto the tipped wing."""
    k = fall(t, TB + 0.2, 1.3)
    c = centre(P, "warehouse_eave_" + side)
    return wing_tip(side, t) @ Tm(-Z * (c.z - FLOOR_TOP - 0.4) * k) @ about(c, Rx(0.05 * k))


CRATES = sorted(n for n in P if n.startswith("warehouse_crate_"))
CRATE_MID = sorted(centre(P, n).z for n in CRATES)[len(CRATES) // 2]
THROWN = {}
for i, n in enumerate(CRATES):
    c = centre(P, n)
    half = (bbox(P, n)[1].z - bbox(P, n)[0].z) * 0.5
    if c.z > CRATE_MID - 0.01:         # the top of each stack is blown off the floor
        out = V((c.x, c.y * 0.4, 0)).normalized() if abs(c.x) > 0.1 else V((rnd(-1, 1), 0.3, 0)).normalized()
        vel = out * rnd(2.5, 4.5) + Z * rnd(4.5, 7.0)
        spin_ax = V((rnd(-1, 1), rnd(-1, 1), rnd(-1, 1))).normalized()
        # Where it lands: on the ground beside the floor.
        ground = half
        s_land = (vel.z + sqrt(vel.z ** 2 + 2 * GRAV * (c.z - ground))) / GRAV
        land_q = Quaternion(Z, rnd(0, 6)) @ Quaternion(X, rnd(-0.2, 0.2))
        THROWN[n] = ("thrown", c, vel, spin_ax, rnd(5, 9), s_land, land_q, ground)
    else:                              # jolted, then lying askew
        THROWN[n] = ("jolt", c, rnd(-0.25, 0.25), rnd(0.15, 0.4))


def crate_motion(n, t):
    d = THROWN[n]
    if d[0] == "jolt":
        _, c, yaw, h = d
        k = ramp(t, TB, TB + 0.2)
        hop = 4 * lin(t, TB, TB + 0.45) * (1 - lin(t, TB, TB + 0.45)) * h
        return Tm(Z * hop) @ about(c, Rz(yaw * k) @ Rx(0.1 * yaw * k))
    _, c, vel, ax, spin, s_land, land_q, ground = d
    te = TB + 0.02
    if t < te:
        return Matrix.Identity(4)
    s = t - te
    if s < s_land:
        p = ballistic(c, vel, s)
        return Tm(p) @ Quaternion(ax, spin * s).to_matrix().to_4x4() @ Tm(-c)
    p = ballistic(c, vel, s_land)
    p.z = ground
    return Tm(p) @ land_q.to_matrix().to_4x4() @ Tm(-c)


LIGHTS = [n for n in P if n.startswith("warehouse_light_")]


def depot_motion(name, t):
    if name in ("warehouse_tarp_L", "warehouse_tarp_R"):
        return tarp_fall(name[-1], t)
    if name.startswith("warehouse_rafters_"):
        side = "L" if centre(P, name).x >= 0 else "R"
        return tarp_fall(side, t) if abs(centre(P, name).x) > 0.2 else ridge_fall(t)
    if name.startswith("warehouse_tarp_gable_"):
        return gable_fall(name[-1], t)
    if name == "warehouse_ridge":
        return ridge_fall(t)
    if name in ("warehouse_floor_L2", "warehouse_floor_R2"):
        return wing_tip(name[-2], t)
    if name in ("warehouse_eave_L", "warehouse_eave_R"):
        return eave_drop(name[-1], t)
    if name in THROWN:
        return crate_motion(name, t)
    if name in LIGHTS:
        return None if t < TB + 0.15 else about(P[name][1].translation, Sc(NIL))
    return None


# The tractor may be away building a truck when the Depot dies, so it is not driven: it goes down with
# the root wherever it stands. The rafters are one mesh each side or one across; both cases are covered.
DRIVEN = {n: p for n, p in P.items() if n != "warehouse_power_unit" and not (p[0] == "warehouse_power_unit" and n not in LIGHTS)}
# Lights hang off the tractor: they are driven in its space, so it needs a stand-in too, held still.
DRIVEN["warehouse_power_unit"] = P["warehouse_power_unit"]


def depot_motion_held(name, t):
    if name == "warehouse_power_unit":
        return None
    return depot_motion(name, t)


drives(C, DRIVEN, D_FRAMES, depot_motion_held, d_sink)
scorch(C, D_FRAMES, lambda t: 0.1 + 0.75 * ramp(t, TB, 2.4))

HEART = V((0.0, 0.0, FLOOR_TOP + 1.2))


ROOF_TOP = V((0.0, 0.0, bbox(P, "warehouse_ridge")[1].z + 1.0))


def d_flash(t):
    burst = 2.4 * exp(-((t - TB - 0.06) / 0.12) ** 2) if t > TB - 0.1 else 0.0
    glow = d_burning(t) * (0.5 + 0.1 * sin(t * 23) + 0.06 * sin(t * 37))
    at = ROOF_TOP if burst > glow else sunk(HEART, t)
    return at, None, max(burst, glow)


def d_burning(t):
    return ramp(t, TB + 0.4, TB + 1.2) * fade(t)


fx(C, "Flash", CORE, D_FRAMES, d_flash)


def fireballs(coll, frames, n, src_at, t0, rise, radius, spread, prefix="Fireball"):
    """A fireball: hot puffs boiling up from src_at(t) and swelling, then gone into the smoke."""
    for i in range(n):
        d = V((rnd(-1, 1) * spread, rnd(-1, 1) * spread, 1.0)).normalized()
        te, life = t0 + rnd(0.0, 0.08), rnd(0.7, 1.1)
        r = radius * rnd(0.6, 1.0)
        up = rise * rnd(0.6, 1.0)

        def ball(t, d=d, te=te, life=life, r=r, up=up):
            if t < te or t > te + life:
                return None
            k = (t - te) / life
            p = src_at(te) + d * up * (1 - (1 - k) ** 2)
            return p, Quaternion(Z, k * 3 + te), r * sm(k * 5) * (1 - ramp(k, 0.5, 1.0))
        fx(coll, "%s_%d" % (prefix, i + 1), FIREBALL, frames, ball)


fireballs(C, D_FRAMES, 14, lambda t: ROOF_TOP - Z * 2.0, TB, 7.0, 3.4, 0.7)

for i in range(26):                    # the blast
    vel = V((rnd(-7, 7), rnd(-6, 6), rnd(3, 9)))
    life, size, te = rnd(0.35, 0.7), rnd(0.3, 0.55), TB + rnd(-0.02, 0.08)

    def spark(t, vel=vel, life=life, size=size, te=te):
        if t < te or t > te + life:
            return None
        s = t - te
        return ballistic(HEART, vel, s), (vel + V((0, 0, -GRAV * s))).to_track_quat('Y', 'Z'), size * (1 - s / life)
    fx(C, "Blast_Spark_%d" % (i + 1), SPARK, D_FRAMES, spark)

for i in range(16):                    # shreds of tarp thrown up, fluttering down
    src = V((rnd(-5, 5), rnd(-7, 7), rnd(7, 10)))
    out = V((src.x, src.y * 0.5, 0)).normalized()
    vel = out * rnd(1.5, 3.5) + Z * rnd(3, 6)
    te, size = TB + rnd(0.0, 0.1), rnd(0.9, 1.6)
    ax = V((rnd(-1, 1), rnd(-1, 1), rnd(-1, 1))).normalized()
    drag = 1.6                         # canvas falls slowly
    land_q = Quaternion(Z, rnd(0, 6)) @ Quaternion(X, rnd(-0.15, 0.15))

    def shred(t, src=src, vel=vel, te=te, size=size, ax=ax, land_q=land_q, drag=drag):
        if t < te:
            return None
        s = t - te
        # Rises, then drifts down at a steady pace while it tumbles.
        up = min(s, vel.z / GRAV)
        p = ballistic(src, vel, up)
        p += V((vel.x, vel.y, 0)) * max(0.0, s - up) * 0.4
        p.z -= drag * max(0.0, s - up) ** 1.3
        ground = FLOOR_TOP + 0.05 if abs(p.x) < 6.5 and abs(p.y) < 8.0 else 0.05
        if p.z <= ground:
            p.z = ground
            return sunk(p, t), land_q, size * (1 - 0.5 * ramp(t, 2.5, 4.5))
        return p, Quaternion(ax, s * 4) @ Quaternion(Z, sin(s * 6) * 0.6), size
    fx(C, "Shred_%d" % (i + 1), SHRED, D_FRAMES, shred)

FIRES = [V((rnd(-5.5, 5.5), rnd(-7, 7), FLOOR_TOP + 0.1)) for _ in range(14)]
for i, at in enumerate(FIRES):         # the stock and the fallen canvas burning
    w, h, rate, ph = rnd(0.5, 0.85), rnd(2.4, 4.2), rnd(10, 18), rnd(0, 6)
    start = TB + 0.3 + 0.06 * i

    def flame(t, at=at, w=w, h=h, rate=rate, ph=ph, start=start):
        b = ramp(t, start, start + 0.6) * fade(t)
        if b <= 0.0:
            return None
        lick = 0.7 + 0.3 * sin(t * rate + ph)
        return sunk(at, t), Quaternion(Y, 0.15 * sin(t * rate * 0.6 + ph)), V((w * b, w * b, h * b * lick))
    fx(C, "Fire_%d" % (i + 1), FLAME, D_FRAMES, flame)

for i in range(20):                    # a column of smoke
    te = TB + 0.4 + 0.2 * i
    life = 2.4
    src = FIRES[i % len(FIRES)] + Z * 1.5
    drift = V((rnd(-0.6, 1.0), rnd(-0.4, 0.4), rnd(6.0, 8.0)))
    size = rnd(1.0, 1.7)

    def smoke(t, te=te, life=life, src=src, drift=drift, size=size):
        if t < te or t > te + life or te > SINK0 + 0.5:
            return None
        k = (t - te) / life
        s = size * (0.3 + 0.7 * sm(k * 1.6)) * (1 - ramp(k, 0.65, 1.0)) * fade(t)
        return src + drift * k, Quaternion(Z, k * 2 + te), s
    fx(C, "Smoke_%d" % (i + 1), PUFF, D_FRAMES, smoke)

for i in range(14):                    # embers rising off the fires
    te = TB + 0.8 + 0.25 * i
    src = FIRES[(i * 5) % len(FIRES)] + Z * 0.6
    drift = V((rnd(-1, 1), rnd(-1, 1), rnd(4, 6)))

    def ember(t, te=te, src=src, drift=drift):
        if t < te or t > te + 1.2 or te > SINK0:
            return None
        k = (t - te) / 1.2
        return src + drift * k + V((sin(k * 9) * 0.3, 0, 0)), Quaternion(Z, k * 5), 0.25 * (1 - k)
    fx(C, "Ember_%d" % (i + 1), EMBER, D_FRAMES, ember)


def soot(t):
    if t < TB + 0.1:
        return None
    k = 1 - (1 - min((t - TB - 0.1) / 2.0, 1.0)) ** 2.5
    r = 10.5 * k * (1 - ramp(t, D_END - 0.6, D_END))
    return V((0, 0, 0.04)), Quaternion(Z, 0.4), V((r * 0.85, r, 1.0))


fx(C, "Scorch_Ground", SOOT, D_FRAMES, soot)

# ================================================================= save and export, one file each
# Each death is its own file: the stand-ins of both are named after the same parts.
def export(collection, name):
    bpy.ops.object.select_all(action='DESELECT')
    objects = list(bpy.data.collections[collection].all_objects)
    for ob in objects:
        ob.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    target = os.path.join(ASSETS, name)
    bpy.ops.export_scene.gltf(filepath=target, export_format='GLB', use_selection=True, export_yup=True,
                              export_apply=True, export_cameras=False, export_lights=False, export_extras=False,
                              export_animations=True, export_animation_mode='NLA_TRACKS',
                              export_force_sampling=True, export_optimize_animation_size=False,
                              export_optimize_animation_keep_anim_object=True)
    print("EXPORTED", name, len(objects), "objects", os.path.getsize(target), "bytes")


def save_and_export(blend, collection, glb):
    scene = bpy.context.scene
    scene.frame_start, scene.frame_end = 0, T_FRAMES if "T_FRAMES" in globals() else D_FRAMES
    scene.frame_set(0)
    bpy.context.preferences.filepaths.save_version = 0
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(DEPOT_DIR, blend))
    print("SAVED", blend)
    export(collection, glb)

save_and_export("DepotDeath.blend", "depot_death_fx", "depot_death_fx.glb")
bpy.ops.wm.read_homefile(use_empty=True)
scene = bpy.context.scene
scene.render.fps = FPS
setup()


# ================================================================= the Depot Truck
T_END = 5.0
T_FRAMES = int(T_END * FPS)
TT = 0.3                               # the tractor's fuel goes up
T_SINK0, T_SINK = 3.6, 7.5
CT = collection("depot_truck_death_fx")
Q = TRUCK
TR = "warehouse_power_unit"
TR_LO, TR_HI = bbox(Q, TR)
TR_C = (TR_LO + TR_HI) * 0.5
DECK_LO, DECK_HI = bbox(Q, "warehouse_deck")
KINGPIN = V((0.0, DECK_LO.y + 0.6, DECK_LO.z))


def t_sink(t):
    return Tm(-Z * T_SINK * ramp(t, T_SINK0, T_END))


def t_sunk(p, t):
    return V(p) - Z * T_SINK * ramp(t, T_SINK0, T_END)


def t_fade(t):
    return 1 - ramp(t, T_SINK0 + 0.2, T_END - 0.1)


def tractor(t):
    """Bucks up on the blast, nose high, and comes down nose first without its front wheels, slewed."""
    s = t - TT
    hop = 0.0
    if 0 < s < 0.75:
        hop = 4 * (s / 0.75) * (1 - s / 0.75) * 1.4
    pitch = -0.32 * (4 * lin(t, TT, TT + 0.75) * (1 - lin(t, TT, TT + 0.75))) + 0.13 * fall(t, TT + 0.6, TT + 0.9)
    yaw = 0.3 * ramp(t, TT, TT + 0.9)
    roll = 0.08 * ramp(t, TT + 0.6, TT + 1.0)
    rear = V((TR_C.x, TR_HI.y - 1.0, TR_LO.z))
    return Tm(Z * hop) @ about(rear, Rz(yaw) @ Rx(pitch) @ Ry(roll))


def trailer(t):
    """Jackknifes behind the tractor, then rolls over onto its side."""
    yaw = -0.4 * ramp(t, TT + 0.15, TT + 1.0)
    k = fall(t, TT + 0.7, TT + 1.6)
    edge = V((DECK_HI.x + 0.2, 0.0, 0.0))
    return about(KINGPIN, Rz(yaw)) @ about(edge, Ry(1.2 * k))


WHEELS_OFF = {}
for n in ("warehouse_wheel_FL", "warehouse_wheel_FR"):
    if n in Q:
        c = centre(Q, n)
        sgn = 1 if c.x > 0 else -1
        vel = V((sgn * rnd(3.0, 4.0), rnd(-2.5, -1.0), rnd(5.0, 6.5)))
        r = (bbox(Q, n)[1].z - bbox(Q, n)[0].z) * 0.5
        half_w = (bbox(Q, n)[1].x - bbox(Q, n)[0].x) * 0.5
        s_land = (vel.z + sqrt(vel.z ** 2 + 2 * GRAV * (c.z - half_w))) / GRAV
        WHEELS_OFF[n] = (c, vel, s_land, half_w, sgn)


def wheel_off(n, t):
    c, vel, s_land, half_w, sgn = WHEELS_OFF[n]
    te = TT + 0.02
    if t < te:
        return None
    s = t - te
    if s < s_land:
        return Tm(ballistic(c, vel, s)) @ Rx(-s * 12) @ Ry(sgn * s * 2.2) @ Tm(-c)
    p = ballistic(c, vel, s_land)
    p.z = half_w
    # Lying flat where it came down.
    return Tm(p) @ Rz(sgn * 0.5) @ Ry(sgn * pi / 2) @ Tm(-c)


T_LIGHTS = [n for n in Q if n.startswith("warehouse_light_")]


def truck_motion(name, t):
    if name == TR:
        return tractor(t)
    if name == "warehouse_deck":
        return trailer(t)
    if name in WHEELS_OFF:
        d = wheel_off(name, t)
        return d if d is not None else tractor(t)
    if name in T_LIGHTS:
        return tractor(t) if t < TT + 0.1 else tractor(t) @ about(Q[name][1].translation, Sc(NIL))
    if Q[name][0] == "warehouse_root":
        return trailer(t)
    return None


drives(CT, Q, T_FRAMES, truck_motion, t_sink)
scorch(CT, T_FRAMES, lambda t: 0.1 + 0.8 * ramp(t, TT, 2.0))

TANK_AT = V((TR_C.x, TR_C.y + 1.2, TR_LO.z + 2.2))


def t_burning(t):
    return ramp(t, TT + 0.3, TT + 0.9) * t_fade(t)


CAB_TOP = V((TR_C.x, TR_C.y, TR_HI.z + 0.8))


def t_flash(t):
    burst = 2.0 * exp(-((t - TT - 0.05) / 0.12) ** 2) if t > TT - 0.1 else 0.0
    glow = t_burning(t) * (0.45 + 0.08 * sin(t * 25) + 0.05 * sin(t * 39))
    at = tractor(t) @ CAB_TOP if burst > glow else t_sunk(tractor(t) @ TANK_AT, t)
    return at, None, max(burst, glow)


fx(CT, "Flash", CORE, T_FRAMES, t_flash)
fireballs(CT, T_FRAMES, 10, lambda t: tractor(t) @ (CAB_TOP - Z * 1.0), TT, 5.0, 2.4, 0.7)

for i in range(20):
    vel = V((rnd(-6, 6), rnd(-6, 4), rnd(3, 8)))
    life, size, te = rnd(0.3, 0.6), rnd(0.25, 0.45), TT + rnd(-0.02, 0.06)

    def spark(t, vel=vel, life=life, size=size, te=te):
        if t < te or t > te + life:
            return None
        s = t - te
        return ballistic(TANK_AT, vel, s), (vel + V((0, 0, -GRAV * s))).to_track_quat('Y', 'Z'), size * (1 - s / life)
    fx(CT, "Blast_Spark_%d" % (i + 1), SPARK, T_FRAMES, spark)

for i in range(9):                     # panels off the tractor
    src = TANK_AT + V((rnd(-1.2, 1.2), rnd(-1.5, 1.5), rnd(0, 1.0)))
    out = V((src.x - TANK_AT.x + rnd(-0.5, 0.5), src.y - TANK_AT.y + rnd(-0.5, 0.5), 0)).normalized()
    vel = out * rnd(2.0, 4.0) + Z * rnd(4.0, 6.5)
    te, size = TT + rnd(0.0, 0.05), rnd(0.6, 1.0)
    ax = V((rnd(-1, 1), rnd(-1, 1), rnd(-1, 1))).normalized()
    spin = rnd(8, 15)
    land_q = Quaternion(Z, rnd(0, 6)) @ Quaternion(X, rnd(-0.25, 0.25))
    s_land = (vel.z + sqrt(vel.z ** 2 + 2 * GRAV * (src.z - 0.05))) / GRAV

    def panel(t, src=src, vel=vel, te=te, size=size, ax=ax, spin=spin, land_q=land_q, s_land=s_land):
        if t < te:
            return None
        s = t - te
        if s < s_land:
            return ballistic(src, vel, s), Quaternion(ax, spin * s), size
        p = ballistic(src, vel, s_land)
        p.z = 0.05
        return t_sunk(p, t), land_q, size
    fx(CT, "Panel_%d" % (i + 1), SCRAP, T_FRAMES, panel)

T_FIRES = [V((rnd(-1.4, 1.4), rnd(-1.8, 1.8), 2.4)) for _ in range(5)]
for i, off in enumerate(T_FIRES):      # the tractor burning, carried with it
    w, h, rate, ph = rnd(0.35, 0.55), rnd(1.4, 2.4), rnd(11, 19), rnd(0, 6)

    def flame(t, off=off, w=w, h=h, rate=rate, ph=ph):
        b = t_burning(t)
        if b <= 0.0:
            return None
        lick = 0.7 + 0.3 * sin(t * rate + ph)
        base = t_sunk(tractor(t) @ (V((TR_C.x, TR_C.y, TR_LO.z)) + off), t)
        return base, Quaternion(Y, 0.15 * sin(t * rate * 0.6 + ph)), V((w * b, w * b, h * b * lick))
    fx(CT, "Fire_%d" % (i + 1), FLAME, T_FRAMES, flame)

for i in range(4):                     # and the trailer's load catching
    off = V((rnd(-1.2, 1.2), rnd(-6.0, 6.0), DECK_HI.z - DECK_LO.z))
    w, h, rate, ph = rnd(0.3, 0.5), rnd(1.0, 1.8), rnd(11, 19), rnd(0, 6)
    start = TT + 1.4 + 0.15 * i

    def load_fire(t, off=off, w=w, h=h, rate=rate, ph=ph, start=start):
        b = ramp(t, start, start + 0.5) * t_fade(t)
        if b <= 0.0:
            return None
        lick = 0.7 + 0.3 * sin(t * rate + ph)
        p = trailer(t) @ (V((0, 0, DECK_LO.z)) + off)
        return t_sunk(V((p.x, p.y, max(p.z, 0.3))), t), None, V((w * b, w * b, h * b * lick))
    fx(CT, "Load_Fire_%d" % (i + 1), FLAME, T_FRAMES, load_fire)

for i in range(14):
    te = TT + 0.3 + 0.2 * i
    life = 2.0
    drift = V((rnd(-0.4, 0.8), rnd(-0.3, 0.3), rnd(4.5, 6.0)))
    size = rnd(0.8, 1.3)

    def smoke(t, te=te, life=life, drift=drift, size=size):
        if t < te or t > te + life or te > T_SINK0 + 0.3:
            return None
        k = (t - te) / life
        src = tractor(te) @ TANK_AT
        s = size * (0.3 + 0.7 * sm(k * 1.6)) * (1 - ramp(k, 0.65, 1.0)) * t_fade(t)
        return src + drift * k, Quaternion(Z, k * 2 + te), s
    fx(CT, "Smoke_%d" % (i + 1), PUFF, T_FRAMES, smoke)

POOL_AT = V((TR_C.x + 0.8, TR_C.y + 0.5, 0.05))


def t_pool(t):
    if t < TT + 0.2:
        return None
    k = 1 - (1 - min((t - TT - 0.2) / 2.2, 1.0)) ** 2.5
    r = 3.2 * k * t_fade(t)
    return t_sunk(POOL_AT, t), Quaternion(Z, 0.6), V((r * 1.3, r, 1.0))


fx(CT, "Oil_Pool", POOL, T_FRAMES, t_pool)

save_and_export("DepotTruckDeath.blend", "depot_truck_death_fx", "depot_truck_death_fx.glb")
