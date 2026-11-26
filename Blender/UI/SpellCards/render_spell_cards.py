"""Renders the art for the Grail Sentinel's spell cards (docs/MIST_AND_SLOW.md) on a clear ground.

  blender --background --python render_spell_cards.py

Writes renders/<card>.png (256 px, transparent). scripts/tools/render_hud_images.gd (SPELL_CARDS, asked for with the
id "spell_cards") puts each one inside the card frame as sl_<card>.png:
  mist           a rolling swirl of pale mist with gold motes, under a small gold grail
  slow           the blue and gold ground sigil, seen at an angle, with an hourglass standing in it
  research_slow  an open book with the hourglass rising from it over a ring of the sigil
Everything is made here from primitives; change this script and re-run it rather than editing the renders.
"""
import bpy, bmesh, os
from math import radians, sin, cos, pi, atan2
from mathutils import Vector as V, Matrix

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "renders")
os.makedirs(OUT, exist_ok=True)
bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
try:
    scene.render.engine = 'BLENDER_EEVEE_NEXT'
except TypeError:
    scene.render.engine = 'BLENDER_EEVEE'
scene.view_settings.view_transform = 'Standard'
scene.render.film_transparent = True
scene.render.image_settings.file_format = 'PNG'
scene.render.image_settings.color_mode = 'RGBA'
scene.render.resolution_x = scene.render.resolution_y = 256
world = bpy.data.worlds.new("cards")
scene.world = world
world.use_nodes = True
bg = next(n for n in world.node_tree.nodes if n.type == 'BACKGROUND')
bg.inputs[0].default_value = (0.55, 0.53, 0.5, 1)
bg.inputs[1].default_value = 0.6

MATS = {}


def material(name, color, metal=0.0, rough=0.5, emit=None, strength=0.0, alpha=1.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = next(n for n in m.node_tree.nodes if n.type == 'BSDF_PRINCIPLED')
    b.inputs["Base Color"].default_value = (*color, 1)
    b.inputs["Metallic"].default_value = metal
    b.inputs["Roughness"].default_value = rough
    if emit:
        b.inputs["Emission Color"].default_value = (*emit, 1)
        b.inputs["Emission Strength"].default_value = strength
    if alpha < 1.0:
        b.inputs["Alpha"].default_value = alpha
        try:
            m.surface_render_method = 'BLENDED'
        except AttributeError:
            m.blend_method = 'BLEND'
    MATS[name] = m
    return m


material("mist", (0.86, 0.88, 0.88), 0.0, 0.9, (0.75, 0.78, 0.8), 0.35)
material("mist_shade", (0.55, 0.6, 0.66), 0.0, 0.9, (0.4, 0.44, 0.5), 0.2)
material("gold", (0.95, 0.66, 0.16), 0.85, 0.25, (1.0, 0.62, 0.15), 0.5)
material("mote", (1.0, 0.7, 0.15), 0.3, 0.3, (1.0, 0.6, 0.1), 1.6)
material("sigil_blue", (0.12, 0.35, 0.95), 0.0, 0.4, (0.2, 0.5, 1.0), 1.4)
material("sigil_gold", (1.0, 0.72, 0.25), 0.5, 0.3, (1.0, 0.65, 0.2), 0.9)
material("sigil_ground", (0.03, 0.07, 0.2), 0.0, 0.8, (0.05, 0.12, 0.35), 0.25)
material("glass", (0.7, 0.85, 1.0), 0.0, 0.05, (0.3, 0.5, 0.9), 0.15, 0.3)
material("sand", (0.85, 0.65, 0.3), 0.0, 0.6, (1.0, 0.7, 0.3), 0.6)
material("ivory", (0.9, 0.86, 0.72), 0.0, 0.6, (0.9, 0.85, 0.7), 0.35)
material("cover", (0.06, 0.12, 0.42), 0.1, 0.55)
material("timber", (0.25, 0.13, 0.06), 0.0, 0.8)


def light(name, rot, energy, col=(1, 1, 1)):
    d = bpy.data.lights.new(name, 'SUN')
    d.energy = energy
    d.color = col
    o = bpy.data.objects.new(name, d)
    o.rotation_euler = [radians(a) for a in rot]
    scene.collection.objects.link(o)


light("key", (40, 10, -40), 3.6, (1.0, 0.95, 0.88))
light("rim", (-60, 0, 150), 2.2, (0.8, 0.88, 1.0))
cam_d = bpy.data.cameras.new("cam")
cam_d.type = 'ORTHO'
cam = bpy.data.objects.new("cam", cam_d)
scene.collection.objects.link(cam)
scene.camera = cam
cam.location = (0, -10, 0)
cam.rotation_euler = (radians(90), 0, 0)     # looking +Y; X right, Z up on the card


class Part:
    """Collects objects for one card; every mesh is made from bmesh and linked to the card's collection."""
    def __init__(self, coll):
        self.coll = coll

    def mesh(self, name, bm, mat, smooth=False, matrix=None):
        if matrix is not None:
            bmesh.ops.transform(bm, matrix=matrix, verts=bm.verts)
        me = bpy.data.meshes.new(name)
        bm.to_mesh(me)
        bm.free()
        for poly in me.polygons:
            poly.use_smooth = smooth
        me.materials.append(MATS[mat])
        ob = bpy.data.objects.new(name, me)
        self.coll.objects.link(ob)
        return ob

    def sphere(self, mat, at, r, squash=(1, 1, 1), subdiv=3):
        bm = bmesh.new()
        bmesh.ops.create_icosphere(bm, subdivisions=subdiv, radius=r)
        m = Matrix.Translation(V(at)) @ Matrix.Diagonal((*squash, 1))
        return self.mesh("sphere", bm, mat, True, m)

    def torus(self, mat, at, r, tube, tilt=0.0, seg=64):
        bm = bmesh.new()
        ring = []
        for i in range(seg):
            a = 2 * pi * i / seg
            c = V((cos(a) * r, sin(a) * r, 0))
            out = V((cos(a), sin(a), 0))
            ring.append([bm.verts.new(c + out * cos(b) * tube + V((0, 0, sin(b) * tube))) for b in (k * 2 * pi / 8 for k in range(8))])
        for i in range(seg):
            a, b = ring[i], ring[(i + 1) % seg]
            for k in range(8):
                bm.faces.new((a[k], b[k], b[(k + 1) % 8], a[(k + 1) % 8]))
        return self.mesh("torus", bm, mat, True, Matrix.Translation(V(at)) @ Matrix.Rotation(tilt, 4, 'X'))

    def lathe(self, mat, at, profile, seg=32, tilt=0.0):
        """Revolves (radius, height) points about Z."""
        bm = bmesh.new()
        rings = [[bm.verts.new((cos(2 * pi * i / seg) * r, sin(2 * pi * i / seg) * r, h)) for i in range(seg)] for r, h in profile]
        for a, b in zip(rings, rings[1:]):
            for i in range(seg):
                bm.faces.new((a[i], a[(i + 1) % seg], b[(i + 1) % seg], b[i]))
        return self.mesh("lathe", bm, mat, True, Matrix.Translation(V(at)) @ Matrix.Rotation(tilt, 4, 'X'))

    def star(self, mat, at, r_out, r_in, points, thick, tilt=0.0, spin=0.0):
        bm = bmesh.new()
        n = points * 2
        top = [bm.verts.new(((r_out if i % 2 == 0 else r_in) * cos(spin + pi * i / points),
                             (r_out if i % 2 == 0 else r_in) * sin(spin + pi * i / points), thick / 2)) for i in range(n)]
        bot = [bm.verts.new((v.co.x, v.co.y, -thick / 2)) for v in top]
        # A star outline only: a thin band along each edge, so it reads as a drawn line.
        bm.faces.new(top)
        bm.faces.new(list(reversed(bot)))
        for i in range(n):
            bm.faces.new((top[i], bot[i], bot[(i + 1) % n], top[(i + 1) % n]))
        return self.mesh("star", bm, mat, False, Matrix.Translation(V(at)) @ Matrix.Rotation(tilt, 4, 'X'))

    def box(self, mat, at, size, rot=None, frame=None):
        bm = bmesh.new()
        bmesh.ops.create_cube(bm, size=1.0)
        m = Matrix.Translation(V(at)) @ (rot if rot is not None else Matrix.Identity(4)) @ Matrix.Diagonal((*size, 1))
        if frame is not None:
            m = frame @ m
        return self.mesh("box", bm, mat, False, m)


def card(name, build, ortho=3.6):
    coll = bpy.data.collections.new(name)
    scene.collection.children.link(coll)
    for c in scene.collection.children:
        bpy.context.view_layer.layer_collection.children[c.name].exclude = c is not coll
    build(Part(coll))
    cam_d.ortho_scale = ortho
    scene.render.filepath = os.path.join(OUT, name + ".png")
    bpy.ops.render.render(write_still=True)
    print("WROTE", scene.render.filepath)


def grail(P, at, s=1.0, tilt=0.0):
    x, y, z = at
    P.lathe("gold", (x, y, z), [(0.0, 0.0), (0.36 * s, 0.0), (0.3 * s, 0.06 * s), (0.08 * s, 0.14 * s), (0.06 * s, 0.42 * s),
                                (0.14 * s, 0.5 * s), (0.08 * s, 0.56 * s), (0.18 * s, 0.62 * s), (0.42 * s, 0.82 * s),
                                (0.48 * s, 1.08 * s), (0.44 * s, 1.1 * s), (0.36 * s, 0.86 * s), (0.0, 0.7 * s)], tilt=tilt)


def hourglass(P, at, s=1.0):
    x, y, z = at
    for dz in (-0.78 * s, 0.78 * s):
        P.lathe("gold", (x, y, z + dz), [(0.0, -0.05 * s), (0.46 * s, -0.05 * s), (0.46 * s, 0.05 * s), (0.0, 0.05 * s)])
    for k in range(3):
        a = 2 * pi * k / 3 + 0.4
        P.box("timber", (x + cos(a) * 0.4 * s, y + sin(a) * 0.4 * s, z), (0.06 * s, 0.06 * s, 1.5 * s))
    P.lathe("glass", (x, y, z - 0.73 * s), [(0.0, 0.0), (0.32 * s, 0.02 * s), (0.3 * s, 0.3 * s), (0.06 * s, 0.68 * s),
                                             (0.06 * s, 0.78 * s), (0.3 * s, 1.16 * s), (0.32 * s, 1.44 * s), (0.0, 1.46 * s)])
    # Sand: a heap in the lower bulb and a little left in the top, with a falling thread.
    P.lathe("sand", (x, y, z - 0.71 * s), [(0.0, 0.0), (0.28 * s, 0.02 * s), (0.2 * s, 0.22 * s), (0.0, 0.34 * s)])
    P.lathe("sand", (x, y, z + 0.18 * s), [(0.0, 0.0), (0.12 * s, 0.1 * s), (0.22 * s, 0.26 * s), (0.0, 0.26 * s)])
    P.lathe("sand", (x, y, z - 0.4 * s), [(0.015 * s, 0.0), (0.015 * s, 0.6 * s)], seg=8)


def sigil(P, at, s=1.0, tilt=radians(68), spin=0.2):
    x, y, z = at
    P.torus("sigil_gold", (x, y, z), 1.25 * s, 0.045 * s, tilt)
    P.torus("sigil_gold", (x, y, z), 1.1 * s, 0.025 * s, tilt)
    P.torus("sigil_blue", (x, y, z), 0.42 * s, 0.03 * s, tilt)
    P.torus("sigil_blue", (x, y, z), 0.9 * s, 0.02 * s, tilt)
    # The eight-pointed star, as two crossed squares' outlines, and rune ticks between the gold rings: laid out
    # flat, then tilted with the rings.
    frame = Matrix.Translation(V((x, y, z))) @ Matrix.Rotation(tilt, 4, 'X')
    for k in range(2):
        for i in range(4):
            a0 = spin + k * pi / 4 + i * pi / 2
            p0 = V((cos(a0), sin(a0), 0)) * 0.9 * s
            p1 = V((cos(a0 + pi / 2), sin(a0 + pi / 2), 0)) * 0.9 * s
            d = p1 - p0
            P.box("sigil_blue", (p0 + p1) / 2, (d.length, 0.04 * s, 0.02 * s), Matrix.Rotation(atan2(d.y, d.x), 4, 'Z'), frame)
    for i in range(28):
        a = 2 * pi * i / 28
        P.box("sigil_gold", V((cos(a), sin(a), 0)) * 1.175 * s, (0.11 * s, 0.025 * s, 0.015 * s),
              Matrix.Rotation(a + (0.5 if i % 3 == 0 else 0.0), 4, 'Z'), frame)
    # A faint disc so the sigil reads as one shape on the card.
    P.lathe("sigil_ground", (x, y, z), [(0.0, -0.01), (1.24 * s, -0.01)], seg=64, tilt=tilt)


def mist(P):
    # Puffs on a spiral, larger and paler outward, flattened into a low rolling bank.
    for i in range(22):
        t = i / 21
        a = 0.6 + t * 4.2 * pi / 2
        r = 0.25 + 1.0 * t
        at = (cos(a) * r, -0.2 + sin(a) * r * 0.25, -0.55 + sin(a) * r * 0.35)
        P.sphere("mist" if i % 3 else "mist_shade", at, 0.28 + 0.22 * t, (1.35, 1.0, 0.7))
    for i in range(14):
        a = i * 2.39996
        r = 0.3 + 1.1 * ((i * 37) % 14) / 14
        P.sphere("mote", (cos(a) * r, -1.6, -0.3 + sin(a) * r * 0.5 + 0.2), 0.06 + 0.025 * (i % 3), subdiv=2)
    grail(P, (0.0, -0.6, 0.15), 0.95)


def slow(P):
    sigil(P, (0, 0, -0.55), 1.15)
    hourglass(P, (0, -0.4, 0.4), 0.82)


def research_slow(P):
    # An open book, pages fanned, the hourglass rising out of it over a ring of the sigil.
    for sx in (-1, 1):
        rot = Matrix.Rotation(radians(-58), 4, 'X') @ Matrix.Rotation(sx * radians(10), 4, 'Y')
        P.box("cover", (sx * 0.62, 0.0, -0.95), (1.22, 0.86, 0.05), rot)
        P.box("ivory", (sx * 0.58, -0.04, -0.92), (1.12, 0.8, 0.07), rot)
    P.torus("sigil_gold", (0, 0, -0.5), 0.95, 0.04, radians(68))
    P.torus("sigil_blue", (0, 0, -0.5), 0.78, 0.025, radians(68))
    hourglass(P, (0, -0.5, 0.35), 0.78)
    for i in range(8):
        a = i * 2.39996
        P.sphere("mote", (cos(a) * 0.9, -1.2, 0.35 + sin(a) * 0.7), 0.04 + 0.015 * (i % 3), subdiv=2)


card("mist", mist, 3.5)
card("slow", slow, 3.3)
card("research_slow", research_slow, 3.4)
