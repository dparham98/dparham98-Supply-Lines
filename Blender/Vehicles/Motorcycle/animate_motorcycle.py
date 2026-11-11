"""Stage 2 for Motorcycle.blend: the Die clip and the effect collections.

Run after build_motorcycle.py, on the saved file:
  blender Motorcycle.blend --background --python animate_motorcycle.py

It clears any animation and effects it made before, so it can be re-run. Everything is baked one
key a frame at 24 fps from the functions below, so the bike, the rider and the effects share one
timeline. Driving, steering, leaning, the stand and the gun are done in the game by
scripts/components/motorcycle_rig.gd, not here.
"""
import bpy, bmesh, math, random
from math import sin, cos, radians, pi, exp
from mathutils import Vector as V, Matrix, Quaternion

FPS = 24
FX_COLLS = ("motorcycle_death_fx", "motorcycle_fire_fx", "rail_spike_impact")
scene = bpy.context.scene
scene.render.fps = FPS
random.seed(11)
X, Y, Z = V((1, 0, 0)), V((0, 1, 0)), V((0, 0, 1))

# ---------------------------------------------------------------- start clean
scene.frame_set(0)
for ob in list(bpy.data.objects):
    if ob.animation_data:
        ob.animation_data_clear()
for name in FX_COLLS:
    c = bpy.data.collections.get(name)
    if c:
        for o in list(c.objects):
            bpy.data.objects.remove(o)
        bpy.data.collections.remove(c)
for a in list(bpy.data.actions):
    bpy.data.actions.remove(a)
for m in list(bpy.data.meshes):
    if m.users == 0:
        bpy.data.meshes.remove(m)
for m in list(bpy.data.materials):
    if m.name.startswith("moto_fx_"):
        bpy.data.materials.remove(m)
bpy.context.view_layer.update()
OB = bpy.data.objects


def sm(x):
    x = max(0.0, min(1.0, x))
    return x * x * (3 - 2 * x)


def ramp(t, a, b):
    return sm((t - a) / (b - a))


def Tm(p):
    return Matrix.Translation(V(p))


def Rx(a):
    return Matrix.Rotation(a, 4, 'X')


def Ry(a):
    return Matrix.Rotation(a, 4, 'Y')


def Rz(a):
    return Matrix.Rotation(a, 4, 'Z')


def push(ob, clip):
    ad = ob.animation_data
    act = ad.action
    act.name = clip + "_" + ob.name
    track = ad.nla_tracks.new()
    track.name = clip
    strip = track.strips.new(clip, 0, act)
    strip.name = clip
    ad.action = None


def bake(ob, clip, frames, fn):
    """fn(t) -> (location, quaternion, scale vector) in the object's parent space."""
    ob.rotation_mode = 'QUATERNION'
    rest = (ob.location.copy(), ob.rotation_quaternion.copy(), ob.scale.copy())
    prev = None
    for f in range(frames + 1):
        loc, q, sc = fn(f / FPS)
        q = Quaternion(q)
        if prev is not None and prev.dot(q) < 0:
            q.negate()
        prev = q.copy()
        ob.location, ob.rotation_quaternion, ob.scale = loc, q, sc
        ob.keyframe_insert("location", frame=f)
        ob.keyframe_insert("rotation_quaternion", frame=f)
        ob.keyframe_insert("scale", frame=f)
    push(ob, clip)
    ob.location, ob.rotation_quaternion, ob.scale = rest


def bake_matrix(ob, clip, frames, fn):
    def trs(t):
        return fn(t).decompose()
    bake(ob, clip, frames, trs)


# ================================================================= Die
DIE_END = 5.0
DIE_FRAMES = int(DIE_END * FPS)
SINK0 = 4.0
T_THROW = 0.22
HIP = OB["rider_torso"].matrix_world.translation.copy()
LIE = radians(80)


def bike_world(t):
    f = max(0.0, min(1.0, (t - 0.08) / 0.42)) ** 2
    roll = -LIE * f
    hop = 0.0
    if t > 0.5:
        roll += radians(5) * exp(-(t - 0.5) * 7) * sin((t - 0.5) * 16)
        hop = 0.07 * exp(-(t - 0.5) * 6) * abs(sin((t - 0.5) * 14))
    u = min(t / 1.8, 1.0)
    slide = 1 - (1 - u) ** 2.4
    z = 0.39 * sin(abs(roll)) / sin(LIE) + hop - 1.5 * ramp(t, SINK0, DIE_END)
    return Tm((-0.45 * slide, -3.4 * slide, z)) @ Rz(radians(38) * slide) @ Ry(roll)


B0 = bike_world(T_THROW)
P0 = B0 @ HIP
Q0 = B0.to_quaternion()
VEL = V((1.5, -4.6, 3.3))
GRAV = 9.8
REST_Z = 0.22
T_FLY = (VEL.z + math.sqrt(VEL.z ** 2 + 2 * GRAV * (P0.z - REST_Z - 0.02))) / GRAV
T_LAND = T_THROW + T_FLY
T_REST = T_LAND + 0.65
P_LAND = V((P0.x + VEL.x * T_FLY, P0.y + VEL.y * T_FLY, REST_Z + 0.02))
P_REST = P_LAND + V((0.3, -0.95, -0.02))
FACE_DOWN = radians(51.5 + 360)
YAW_REST = radians(35)
RT = (Rz(YAW_REST) @ Rx(FACE_DOWN)).to_3x3()


def rider_world(t):
    if t <= T_THROW:
        return bike_world(t) @ Tm(HIP)
    if t < T_LAND:
        s = t - T_THROW
        p = P0 + VEL * s + V((0, 0, -0.5 * GRAV * s * s))
        k = s / T_FLY
        pitch = radians(300) * k
        yaw = YAW_REST * 0.5 * k
        start = Quaternion().slerp(Q0, 1 - sm(k * 2))
    else:
        k = min((t - T_LAND) / (T_REST - T_LAND), 1.0)
        e = 1 - (1 - k) ** 2.2
        p = P_LAND.lerp(P_REST, e) + V((0, 0, 0.11 * sin(pi * k) * (1 - k)))
        pitch = radians(300) + (FACE_DOWN - radians(300)) * e
        yaw = YAW_REST * (0.5 + 0.5 * e)
        start = Quaternion()
    p = p - V((0, 0, 0.9 * ramp(t, SINK0, DIE_END)))
    return Tm(p) @ Rz(yaw) @ Rx(pitch) @ start.to_matrix().to_4x4()


def frame3(a, n):
    a = a.normalized()
    n = (n - a * n.dot(a)).normalized()
    return Matrix((a, n.cross(a), n)).transposed()


def sprawl(src_a, src_b, dst_a, prefer):
    """Local rotation that lays a bent limb flat on the ground once the torso has come to rest."""
    yawm = Rz(YAW_REST).to_3x3()
    dst_a, prefer = yawm @ V(dst_a), yawm @ V(prefer)
    S = frame3(src_a, src_a.cross(src_b))
    best = None
    for up in (Z, -Z):
        R = frame3(dst_a, up) @ S.transposed()
        score = (R @ src_b.normalized()).dot(prefer.normalized())
        if best is None or score > best[0]:
            best = (score, R)
    return (RT.inverted() @ best[1]).to_quaternion()


def limb(ob, q_a, q_b, q_rest):
    home = ob.location.copy()

    def fn(t):
        if t <= T_THROW:
            q = Quaternion()
        elif t < T_THROW + 0.3:
            q = Quaternion().slerp(q_a, sm((t - T_THROW) / 0.3))
        elif t < T_LAND:
            q = q_a.slerp(q_b, sm((t - T_THROW - 0.3) / (T_LAND - T_THROW - 0.3)))
        else:
            q = q_b.slerp(q_rest, sm((t - T_LAND) / (T_REST - T_LAND)))
        return home, q, V((1, 1, 1))
    bake(ob, "Die", DIE_FRAMES, fn)


def qe(x=0.0, y=0.0, z=0.0):
    return (Rz(radians(z)) @ Ry(radians(y)) @ Rx(radians(x))).to_quaternion()


bike = OB["bike_root"]
bake_matrix(bike, "Die", DIE_FRAMES, bike_world)
bake_matrix(OB["rider_torso"], "Die", DIE_FRAMES, lambda t: bike_world(t).inverted() @ rider_world(t))

for s, tag in ((1, "L"), (-1, "R")):
    SH = V((s * 0.25, -0.05, 1.37))
    E = V((s * 0.315, -0.30, 1.24))
    G = V((s * 0.3275, -0.55, 1.253))
    limb(OB["rider_arm_" + tag], qe(-75, 0, s * 35), qe(-20, s * 30, s * -50),
         sprawl(E - SH, G - E, (s * 0.8, -0.5, -0.2), (s * 0.2, -1, 0)))
    HP = V((s * 0.13, 0.27, 0.90))
    K = V((s * 0.30, -0.06, 0.835))
    A = V((s * 0.29, 0.22, 0.56))
    limb(OB["rider_leg_" + tag], qe(45 + 15 * s, 0, s * 20), qe(95 - 25 * s, s * 25, 0),
         sprawl(K - HP, A - K, (s * 0.38, 0.9, -0.2), (s * 0.9, 0.3, 0)))
limb(OB["rider_head"], qe(-25, 0, 15), qe(20, 10, -30), qe(12, 8, 42))

for name, radius in (("wheel_F", 0.37), ("wheel_R", 0.38)):
    w = OB[name]
    home = w.location.copy()
    w0 = 6.0 / radius

    def spin(t, home=home, w0=w0):
        return home, Quaternion(X, w0 * 0.9 * (1 - exp(-t / 0.9))), V((1, 1, 1))
    bake(w, "Die", DIE_FRAMES, spin)

steer = OB["steer_F"]
steer.rotation_mode = 'QUATERNION'
steer_home, steer_q = steer.location.copy(), steer.rotation_quaternion.copy()
bake(steer, "Die", DIE_FRAMES,
     lambda t: (steer_home, steer_q @ Quaternion(Z, radians(-32) * ramp(t, 0.15, 0.6)), V((1, 1, 1))))

# ================================================================= effect building blocks


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


M_STEAM = fx_material("moto_fx_steam", (0.86, 0.87, 0.90), 0.9, (0.9, 0.92, 0.95), 0.35, 0.55)
M_DUST = fx_material("moto_fx_dust", (0.26, 0.22, 0.19), 1.0, None, 0.0, 0.65)
M_SPARK = fx_material("moto_fx_spark", (0, 0, 0), 0.8, (1.0, 0.62, 0.18), 5.0)
M_FLASH = fx_material("moto_fx_flash", (0, 0, 0), 0.8, (1.0, 0.8, 0.4), 3.2)
M_FIRE = fx_material("moto_fx_fire", (0, 0, 0), 0.8, (1.0, 0.2, 0.02), 1.3)
M_CORE = fx_material("moto_fx_core", (0, 0, 0), 0.8, (1.0, 0.5, 0.08), 2.0)
M_SMOKE = fx_material("moto_fx_smoke", (0.05, 0.045, 0.045), 1.0)
M_OIL = fx_material("moto_fx_oil", (0.012, 0.011, 0.016), 0.07)
M_CABLE = fx_material("moto_fx_cable", (0.03, 0.029, 0.031), 0.7)
M_COPPER = bpy.data.materials["moto_copper"]


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


def flame_mesh(name, mat):
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=5, radius1=1.0, radius2=0.02, depth=1.0,
                          matrix=Tm((0, 0, 0.5)))
    return mesh_from(bm, name, [mat])


def disc_mesh(name, mat):
    bm = bmesh.new()
    ring = []
    for i in range(18):
        a = 2 * pi * i / 18
        r = 1.0 + 0.16 * sin(3 * a + 1.0) + 0.09 * sin(7 * a)
        ring.append(bm.verts.new((r * cos(a), r * sin(a), 0)))
    bm.faces.new(ring)
    return mesh_from(bm, name, [mat])


def cable_mesh(name):
    """A severed cable 0.4 long, hanging off its origin along -Y with a curl, copper at the cut."""
    bm = bmesh.new()
    pts = [V((0.02 * sin(i * 1.3), -0.4 * i / 6, 0.05 * sin(i * 0.9))) for i in range(7)]
    rings = []
    for i, p in enumerate(pts):
        r = 0.016
        rings.append([bm.verts.new(p + V((r * cos(k * pi / 2), 0, r * sin(k * pi / 2)))) for k in range(4)])
    for i in range(6):
        for k in range(4):
            j = (k + 1) % 4
            f = bm.faces.new((rings[i][k], rings[i][j], rings[i + 1][j], rings[i + 1][k]))
            f.material_index = 1 if i == 5 else 0
    bm.faces.new(rings[0])
    bm.faces.new(rings[-1]).material_index = 1
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    return mesh_from(bm, name, [M_CABLE, M_COPPER])


NIL = V((0.001, 0.001, 0.001))
IDQ = Quaternion()


def fx(coll, name, mesh, clip, frames, fn):
    """fn(t) -> (location, quaternion or None, scale as float or vector) or None while unseen."""
    ob = bpy.data.objects.new(name, mesh)
    coll.objects.link(ob)
    last = [V((0, 0, 0))]

    def trs(t):
        r = fn(t)
        if r is None:
            return last[0], IDQ, NIL
        loc, q, sc = r
        last[0] = V(loc)
        if not isinstance(sc, V):
            sc = V((sc, sc, sc))
        sc = V((max(sc.x, 0.001), max(sc.y, 0.001), max(sc.z, 0.001)))
        return V(loc), q or IDQ, sc
    bake(ob, clip, frames, trs)
    ob.location, ob.scale = (0, 0, 0), NIL
    return ob


def collection(name):
    c = bpy.data.collections.new(name)
    scene.collection.children.link(c)
    return c


def ballistic(p0, v, s, g=GRAV):
    return V(p0) + V(v) * s + V((0, 0, -0.5 * g * s * s))


def rnd(a, b):
    return random.uniform(a, b)


# ================================================================= death effects (Die's timeline)
C = collection("motorcycle_death_fx")
PUFF_SMOKE = ico_mesh("fxm_smoke", M_SMOKE, 2, 0.1, True)
SHARD = shard_mesh("fxm_shard", M_SPARK)
DROP = ico_mesh("fxm_drop", M_OIL, 1, 0.1, True)
FLAME = flame_mesh("fxm_flame", M_FIRE)
FLAME_CORE = flame_mesh("fxm_flame_core", M_CORE)
POOL = disc_mesh("fxm_pool", M_OIL)
CORE = ico_mesh("fxm_core", M_FLASH, 1, 0.0, False, 0.12)
CABLE = cable_mesh("fxm_cable")
FIREBOX = V((0.24, -0.22, 0.46))            # the firebox window that ends up facing the sky
FADE0, FADE1 = SINK0 + 0.15, DIE_END - 0.15


def fade(t):
    return 1 - ramp(t, FADE0, FADE1)


def burning(t):
    return ramp(t, 1.5, 2.0) * fade(t)


def spark_main(t):
    hit = 0.9 * exp(-(t - 0.48) * 9) if t >= 0.48 else 0.0
    glow = burning(t) * (0.55 + 0.12 * sin(t * 23) + 0.08 * sin(t * 37))
    return bike_world(t) @ FIREBOX, None, max(hit, glow)


# The flash mesh's scale drives the light in the scene, so it comes first in the collection.
fx(C, "Spark_Main", CORE, "Death", DIE_FRAMES, spark_main)

for i in range(18):
    te = 0.44 + 1.1 * i / 17 + rnd(-0.02, 0.02)
    life = rnd(0.22, 0.36)
    side = rnd(-0.5, 0.9)
    vel = V((rnd(-1.0, 1.0), rnd(1.2, 3.4), rnd(1.2, 3.2)))
    size = rnd(0.10, 0.2)

    def spark(t, te=te, life=life, side=side, vel=vel, size=size):
        if t < te or t > te + life:
            return None
        b = bike_world(te)
        start = b @ V((-0.2, side, 0.3))
        start.z = 0.03
        s = t - te
        v_now = vel + V((0, 0, -GRAV * s))
        return ballistic(start, vel, s), v_now.to_track_quat('Y', 'Z'), size * (1 - s / life)
    fx(C, "Skid_Spark_%d" % (i + 1), SHARD, "Death", DIE_FRAMES, spark)

NECK_LOCAL = V((0, -0.40, 0.55))
for i in range(14):
    first = i < 7
    te = (T_THROW + 0.03 + 0.05 * i) if first else (T_LAND - 0.02 + 0.04 * (i - 7))
    vel = V((rnd(-1.6, 1.6), rnd(-1.6, 1.2), rnd(1.4, 3.6))) + (VEL * 0.5 if first else V((0.3, -1.0, 0)))
    size = rnd(0.03, 0.06)
    src = NECK_LOCAL + V((rnd(-0.2, 0.2), rnd(-0.05, 0.3), rnd(-0.2, 0.05)))

    def drop(t, te=te, vel=vel, size=size, src=src):
        if t < te:
            return None
        p0 = rider_world(te) @ src
        s = t - te
        fall = (vel.z + math.sqrt(vel.z ** 2 + 2 * GRAV * max(p0.z - 0.015, 0.0))) / GRAV
        if s < fall:
            return ballistic(p0, vel, s), None, size
        p = ballistic(p0, vel, fall)
        p.z = 0.015 - 0.9 * ramp(t, SINK0, DIE_END)
        spread = 1 + 1.8 * ramp(s, fall, fall + 0.25)
        return p, None, V((size * spread, size * spread, size * 0.2)) * fade(t)
    fx(C, "Rider_Oil_%d" % (i + 1), DROP, "Death", DIE_FRAMES, drop)

for i, (anchor, lean) in enumerate(((V((0.0, -0.36, 0.52)), 0.0), (V((0.22, -0.3, 0.46)), 50.0),
                                    (V((-0.2, -0.26, 0.44)), -60.0), (V((0.05, 0.05, 0.38)), 150.0))):
    ph = rnd(0, 6)

    def cable(t, anchor=anchor, lean=lean, ph=ph):
        if t < T_THROW:
            return None
        grow = ramp(t, T_THROW, T_THROW + 0.1)
        calm = exp(-max(t - T_REST, 0.0) * 3.0)
        whip = Rz(radians(lean + 70 * calm * sin(t * 17 + ph))) @ Rx(radians(-60 + 55 * calm * sin(t * 13 + ph * 2)))
        m = rider_world(t) @ Tm(anchor) @ whip
        loc, q, _ = m.decompose()
        return loc, q, grow * fade(t)
    fx(C, "Rider_Cable_%d" % (i + 1), CABLE, "Death", DIE_FRAMES, cable)

BIKE_REST = bike_world(3.0)
for name, centre, size, t0, t1 in (("Oil_Pool_Rider", V((P_REST.x, P_REST.y - 0.15, 0)), 0.72, T_REST - 0.05, T_REST + 1.7),
                                   ("Oil_Pool_Bike", V(((BIKE_REST @ V((0, 0.1, 0))).x, (BIKE_REST @ V((0, 0.1, 0))).y, 0)),
                                    0.95, 1.7, 3.6)):
    spin = rnd(0, 6)

    def pool(t, centre=centre, size=size, t0=t0, t1=t1, spin=spin):
        if t < t0:
            return None
        grow = 1 - (1 - min((t - t0) / (t1 - t0), 1.0)) ** 2.5
        r = size * grow * fade(t)
        return centre + V((0, 0, 0.014)), Quaternion(Z, spin), V((r, r, 1.0))
    fx(C, name, POOL, "Death", DIE_FRAMES, pool)

FIRE_AT = BIKE_REST @ FIREBOX
for i in range(5):
    off = V((rnd(-0.1, 0.1), rnd(-0.12, 0.12), rnd(-0.03, 0.02)))
    w, h, rate, ph = rnd(0.07, 0.12), rnd(0.28, 0.5), rnd(15, 26), rnd(0, 6)
    core = i < 2

    def flame(t, off=off, w=w, h=h, rate=rate, ph=ph, core=core):
        b = burning(t)
        if b <= 0.0:
            return None
        lick = 0.75 + 0.25 * sin(t * rate + ph)
        k = 0.6 if core else 1.0
        return (bike_world(t) @ FIREBOX + off, Quaternion(Y, 0.18 * sin(t * rate * 0.6 + ph)),
                V((w * k * b, w * k * b, h * k * b * lick)))
    fx(C, "Fire_%d" % (i + 1), FLAME_CORE if core else FLAME, "Death", DIE_FRAMES, flame)

for i in range(10):
    te = 1.55 + 0.27 * i
    life = 1.35
    drift = V((rnd(-0.25, 0.35), rnd(-0.2, 0.2), rnd(1.3, 1.8)))
    size = rnd(0.26, 0.4)

    def smoke(t, te=te, life=life, drift=drift, size=size):
        if t < te or t > te + life or te > FADE0:
            return None
        k = (t - te) / life
        s = size * (0.3 + 0.7 * sm(k * 1.6)) * (1 - ramp(k, 0.65, 1.0)) * fade(t)
        return FIRE_AT + V((0, 0, 0.25)) + drift * k, Quaternion(Z, k * 2 + te), s
    fx(C, "Wreck_Smoke_%d" % (i + 1), PUFF_SMOKE, "Death", DIE_FRAMES, smoke)

# ================================================================= muzzle steam (clip Fire, origin on the muzzle)
C = collection("motorcycle_fire_fx")
FIRE_FRAMES = 48
STEAM = ico_mesh("fxm_steam", M_STEAM, 1, 0.1, True)
MUZZLE_W = OB["muzzle"].matrix_world.translation
VENT_TOP = V((0, 0.62, 1.99)) - MUZZLE_W          # the valve block on the receiver
VENT_SIDE = V((0, 0.93, 1.89)) - MUZZLE_W         # the brass pressure cylinder


def jet(t):
    k = ramp(t, 0.0, 0.04) * (1 - ramp(t, 0.07, 0.32))
    return V((0, -0.18 - 1.5 * min(t, 0.3), 0)), None, V((0.10 * k + 0.05 * sm(t * 4) * k, 0.36 * k, 0.10 * k + 0.05 * sm(t * 4) * k))


# The first object is the one burst_effect.gd watches.
fx(C, "Steam_Jet", STEAM, "Fire", FIRE_FRAMES, jet)
for i in range(5):
    a = 2 * pi * i / 5 + 0.4

    def ring(t, a=a):
        if t > 0.5:
            return None
        k = t / 0.5
        out = 0.06 + 0.24 * (1 - (1 - k) ** 2)
        s = 0.11 * sm(k * 5) * (1 - ramp(k, 0.45, 1.0))
        return V((out * cos(a), -0.05 - 0.38 * k, out * sin(a))), None, s
    fx(C, "Steam_Ring_%d" % (i + 1), STEAM, "Fire", FIRE_FRAMES, ring)
for s_, tag in ((1, "L"), (-1, "R")):
    def side(t, s_=s_):
        k = ramp(t, 0.0, 0.04) * (1 - ramp(t, 0.14, 0.45))
        reach = 0.12 + 0.3 * sm(t / 0.25)
        return VENT_SIDE + V((s_ * reach, 0.03, 0.03 + 0.1 * t)), None, V((0.26 * k, 0.07 * k, 0.07 * k))
    fx(C, "Vent_Jet_" + tag, STEAM, "Fire", FIRE_FRAMES, side)
for i in range(3):
    te = 0.02 + 0.07 * i
    drift = V((rnd(-0.08, 0.08), 0.12 + 0.08 * i, 0.5 + 0.08 * i))

    def vent(t, te=te, drift=drift):
        if t < te or t > te + 0.85:
            return None
        k = (t - te) / 0.85
        return VENT_TOP + drift * (1 - (1 - k) ** 2), None, 0.17 * sm(k * 4) * (1 - ramp(k, 0.4, 1.0))
    fx(C, "Vent_Puff_%d" % (i + 1), STEAM, "Fire", FIRE_FRAMES, vent)
# The wisp: smaller and smaller puffs until the next shot is ready.
for i in range(9):
    te = 0.3 + 0.166 * i
    life = 0.36
    size = 0.085 * (1 - i / 9.5)
    sway = rnd(-0.05, 0.05)

    def wisp(t, te=te, life=life, size=size, sway=sway):
        if t < te or t > te + life:
            return None
        k = (t - te) / life
        return VENT_TOP + V((sway * k, 0.06 * k, 0.03 + 0.3 * k)), None, size * sm(k * 3) * (1 - ramp(k, 0.5, 1.0))
    fx(C, "Steam_Wisp_%d" % (i + 1), STEAM, "Fire", FIRE_FRAMES, wisp)

# ================================================================= spike impact (clip Impact, shooter toward -Y)
C = collection("rail_spike_impact")
IMPACT_FRAMES = 26
DUST = ico_mesh("fxm_dust", M_DUST, 1, 0.14, True)
SPIKE_SCALE = 1.5
SPIKE_IN = Quaternion(Z, pi)                       # the spike's tip toward +Y, into the target
fx(C, "Impact_Flash", CORE, "Impact", IMPACT_FRAMES,
   lambda t: (V((0, -0.04, 0)), None, 0.95 * exp(-t * 13) if t < 0.3 else 0.0))
for i in range(12):
    vel = V((rnd(-2.6, 2.6), rnd(-5.5, -1.5), rnd(-0.5, 3.6)))
    life = rnd(0.24, 0.42)
    size = rnd(0.12, 0.22)

    def spark(t, vel=vel, life=life, size=size):
        if t > life:
            return None
        v_now = vel + V((0, 0, -GRAV * t))
        return ballistic((0, -0.03, 0), vel, t), v_now.to_track_quat('Y', 'Z'), size * (1 - t / life)
    fx(C, "Impact_Spark_%d" % (i + 1), SHARD, "Impact", IMPACT_FRAMES, spark)
for i in range(6):
    drift = V((rnd(-0.3, 0.3), rnd(-0.55, -0.15), rnd(-0.05, 0.35)))
    size = rnd(0.1, 0.17)

    def dust(t, drift=drift, size=size):
        if t > 0.8:
            return None
        k = t / 0.8
        return drift * (1 - (1 - k) ** 2.5), None, size * sm(k * 5) * (1 - ramp(k, 0.4, 1.0))
    fx(C, "Impact_Dust_%d" % (i + 1), DUST, "Impact", IMPACT_FRAMES, dust)


def stuck(t):
    home = V((0, 0.10 - 0.26 * SPIKE_SCALE, 0))
    if t < 0.5:
        shake = radians(7) * exp(-t * 14) * sin(t * 60)
        return home, Quaternion(X, radians(-6) + shake) @ SPIKE_IN, SPIKE_SCALE
    s = t - 0.5
    gone = 1 - ramp(s, 0.32, 0.5)
    return (home + V((0, -0.5 * s, -0.5 * GRAV * s * s)), Quaternion(X, radians(-6) - radians(260) * s) @ SPIKE_IN,
            SPIKE_SCALE * gone)


fx(C, "Impact_Spike", OB["rail_spike"].data, "Impact", IMPACT_FRAMES, stuck)

# ================================================================= finish
lc = bpy.context.view_layer.layer_collection.children
for name in FX_COLLS:
    lc[name].exclude = True
scene.frame_start, scene.frame_end = 0, DIE_FRAMES
scene.frame_set(0)
print("DIE frames", DIE_FRAMES, "throw", round(T_THROW, 2), "land", round(T_LAND, 2), "rest", round(T_REST, 2))
print("RIDER rest", [round(v, 2) for v in P_REST], "BIKE rest", [round(v, 2) for v in BIKE_REST.translation])
print("FIRE at", [round(v, 2) for v in FIRE_AT])
bpy.context.preferences.filepaths.save_version = 0
bpy.ops.wm.save_mainfile()
print("SAVED")
