"""Stage 2 for LandMine.blend: the blast's Impact clip.

  blender LandMine.blend --background --python animate_land_mine.py

Clears any animation it made before, so it can be re-run. The mine itself has no keyed clip: its
arming, armed and spotted states are driven in the game by scripts/components/land_mine_model.gd.

Impact runs 1.6 s at 24 fps and is sized to the mine's 3 m splash (assets/combat/mine_rules.tres):
a flash and fireball, a ring of dust that rolls out to exactly 3 m, clods of dirt thrown up to
about 3 m high, casing shards flung out to the splash edge, and a scorch that stays until the end.
Every piece is keyed down to nothing (a thousandth) on the last frame, as burst_effect.gd expects.
"""
import bpy, random
from math import sin, cos, radians, pi, exp
from mathutils import Vector as V, Quaternion, Euler

FPS = 24
FRAMES = 38                     # 1.58 s
SPLASH = 3.0
GRAV = 9.8
scene = bpy.context.scene
scene.render.fps = FPS
random.seed(23)
OB = bpy.data.objects
for ob in list(bpy.data.objects):
    if ob.animation_data:
        ob.animation_data_clear()
for a in list(bpy.data.actions):
    bpy.data.actions.remove(a)


def sm(x):
    x = max(0.0, min(1.0, x))
    return x * x * (3 - 2 * x)


def ramp(t, a, b):
    return sm((t - a) / (b - a))


def push(ob, clip):
    ad = ob.animation_data
    act = ad.action
    act.name = clip + "_" + ob.name
    track = ad.nla_tracks.new()
    track.name = clip
    strip = track.strips.new(clip, 0, act)
    strip.name = clip
    ad.action = None


def bake(ob, fn, clip="Impact"):
    """fn(t) -> (location, quaternion, scale)."""
    ob.rotation_mode = 'QUATERNION'
    rest = (ob.location.copy(), ob.rotation_quaternion.copy(), ob.scale.copy())
    prev = None
    for f in range(FRAMES + 1):
        loc, q, sc = fn(f / FPS)
        q = Quaternion(q)
        if prev is not None and prev.dot(q) < 0:
            q.negate()
        prev = q.copy()
        sc = V([max(c, 0.001) for c in sc]) if f < FRAMES else V((0.001, 0.001, 0.001))   # never exactly 0
        ob.location, ob.rotation_quaternion, ob.scale = V(loc), q, sc
        for path in ("location", "rotation_quaternion", "scale"):
            ob.keyframe_insert(path, frame=f)
    push(ob, clip)
    ob.location, ob.rotation_quaternion, ob.scale = rest


END = FRAMES / FPS
ID = Quaternion()

# flash: a sharp pop, gone by 0.25 s (its scale also drives the light)
bake(OB["Impact_Flash"], lambda t: ((0, 0, 0.35 + t * 1.5), ID,
                                    V((1, 1, 1)) * (ramp(t, 0.0, 0.03) * (1 - ramp(t, 0.06, 0.25)) * 1.4)))
# fireball: swells and climbs, then shrinks into the smoke
bake(OB["blast_fire"], lambda t: ((0, 0, 0.4 + 1.6 * (1 - exp(-t * 4))), ID,
                                  V((1, 1, 1)) * (ramp(t, 0.0, 0.08) * (1 - ramp(t, 0.18, 0.55)) * 2.0 + 0.001)))
# scorch: spreads at once and stays to the end
bake(OB["blast_scorch"], lambda t: ((0, 0, 0.006), Quaternion(V((0, 0, 1)), 0.3),
                                    V((1.6, 1.6, 1)) * ramp(t, 0.0, 0.12) * (1 - ramp(t, END - 0.25, END))))
# dust ring: rolls out to the splash radius and settles
bake(OB["blast_ring"], lambda t: ((0, 0, 0.05), ID,
                                  V((SPLASH * (1 - exp(-t * 7)) / (1 - exp(-7 * 0.6)) if t < 0.6 else SPLASH,) * 2
                                    + (1.0 + 4 * ramp(t, 0.0, 0.3),)) * (1 - ramp(t, 0.7, 1.3))))
# dust puffs: out to the splash edge on a slowing roll, growing and thinning
for i in range(12):
    ob = OB["blast_dust_%02d" % i]
    a = 2 * pi * i / 12 + random.uniform(-0.2, 0.2)
    reach = random.uniform(0.6, 1.0) * SPLASH * 0.85
    rise = random.uniform(0.2, 0.9)
    late = random.uniform(0.0, 0.08)

    def dust(t, a=a, reach=reach, rise=rise, late=late):
        s = max(0.0, t - late)
        r = reach * (1 - exp(-s * 5))
        return ((cos(a) * r, sin(a) * r, 0.2 + rise * (1 - exp(-s * 3))), ID,
                V((1, 1, 1)) * (ramp(s, 0.0, 0.12) * (0.7 + 1.1 * s) * (1 - ramp(t, 0.8, END))))
    bake(ob, dust)
# clods: thrown up in a cone, falling back inside the splash
for i in range(16):
    ob = OB["blast_clod_%02d" % i]
    a = random.uniform(0, 2 * pi)
    vz = random.uniform(5.0, 8.0)
    vr = random.uniform(0.6, 2.2)
    spin = V((random.uniform(-1, 1), random.uniform(-1, 1), random.uniform(-1, 1))).normalized()
    rate = random.uniform(6, 14)

    def clod(t, a=a, vz=vz, vr=vr, spin=spin, rate=rate):
        z = max(0.05, 0.1 + vz * t - 0.5 * GRAV * t * t)
        r = vr * t
        return ((cos(a) * r, sin(a) * r, z), Quaternion(spin, rate * t),
                V((1, 1, 1)) * ramp(t, 0.0, 0.04) * (1 - ramp(t, END - 0.3, END)))
    bake(ob, clod)
# shards: flung out low and fast, landing near the splash edge
for i in range(18):
    ob = OB["blast_shard_%02d" % i]
    a = 2 * pi * i / 18 + random.uniform(-0.15, 0.15)
    land = random.uniform(0.75, 1.05) * SPLASH
    tf = random.uniform(0.35, 0.55)
    vz = 0.5 * GRAV * tf
    spin = V((random.uniform(-1, 1), random.uniform(-1, 1), random.uniform(-1, 1))).normalized()

    def shard(t, a=a, land=land, tf=tf, vz=vz, spin=spin):
        s = min(t, tf)
        r = land * s / tf
        z = max(0.02, 0.12 + vz * s - 0.5 * GRAV * s * s)
        return ((cos(a) * r, sin(a) * r, z), Quaternion(spin, 20 * s),
                V((1, 1, 1)) * ramp(t, 0.0, 0.03) * (1 - ramp(t, END - 0.35, END)))
    bake(ob, shard)

scene.frame_start, scene.frame_end = 0, FRAMES
scene.frame_set(0)
bpy.context.preferences.filepaths.save_version = 0
bpy.ops.wm.save_mainfile()
print("SAVED Impact", FRAMES, "frames")
