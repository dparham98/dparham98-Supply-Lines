# Builds the landscape kit (docs/LANDSCAPE_LOOKDEV.md): free-form cliffs, boulders, stones, trees and plants.
# Writes Blender/Terrain/LandscapeKit.blend, one OBJ per piece in assets/models/terrain/kit, a wrapper scene per piece
# in scenes/terrain/kit and a contact sheet in Blender/Previews/Terrain. Run from the repository root:
#   blender --background --python Blender/Terrain/build/build_landscape_kit.py
# Pieces are 1 unit = 1 m, standing on Z = 0, and face Blender -Y (Godot +Z). Colour is in the vertex colours with
# baked ambient shading; UV.x is how far a vertex sways in the wind. Rock gets its surface from the game's rock
# shader, so its vertex colour only carries the shading.
import math
import os
import random

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Vector, noise

ROOT = os.getcwd()
BLEND = os.path.join(ROOT, "Blender", "Terrain", "LandscapeKit.blend")
MODELS = os.path.join(ROOT, "assets", "models", "terrain", "kit")
SCENES = os.path.join(ROOT, "scenes", "terrain", "kit")
PREVIEWS = os.path.join(ROOT, "Blender", "Previews", "Terrain")

ROCK = "rock"
FOLIAGE = "foliage"
# Thin leaves and grass: same material as foliage, but no baked shading, which only blackens them.
BLADES = "blades"
# Leaf and needle sprays: flat cards cut out by assets/textures/terrain/leaf_atlas.png, exported beside their tree
# as <tree>_leaves and drawn by the leaves material.
LEAVES = "leaves"
ATLAS = os.path.join(ROOT, "assets", "textures", "terrain", "leaf_atlas.png")
pieces = []  # (object, material kind, casts shadows)


class Builder:
    """Collects triangles and quads with a colour, a sway weight and an optional normal per vertex."""

    def __init__(self):
        self.bm = bmesh.new()
        self.color = self.bm.verts.layers.float_color.new("base")
        self.sway = self.bm.verts.layers.float.new("sway")
        self.normal = self.bm.verts.layers.float_vector.new("soft_normal")
        self.tex = self.bm.verts.layers.float_vector.new("tex")

    def vert(self, position, color, sway=0.0, normal=None):
        v = self.bm.verts.new(position)
        v[self.color] = (color[0], color[1], color[2], 1.0)
        v[self.sway] = sway
        v[self.normal] = normal if normal is not None else (0.0, 0.0, 0.0)
        return v

    def card(self, centre, across, up, tile, inner, outer, normal, crown_centre):
        """A flat spray of leaves: one square cut out by a tile of the leaf atlas (tiles are 2 x 2)."""
        corners = []
        for u, w in ((0, 0), (1, 0), (1, 1), (0, 1)):
            position = Vector(centre) + across * (u - 0.5) * 2.0 + up * (w - 0.5) * 2.0
            # Leaves nearer the middle of the crown sit in its shade.
            reach = (position - crown_centre).length
            near = (Vector(centre) - crown_centre).length
            color = mix(inner, outer, max(0.0, min(1.0, 0.5 + (reach - near) / max(across.length, 0.01) * 0.5)))
            v = self.vert(position, color, 0.0, normal)
            v[self.tex] = ((tile % 2 + u * 0.96 + 0.02) * 0.5, 1.0 - (tile // 2 + w * 0.96 + 0.02) * 0.5, 0.0)
            corners.append(v)
        self.face(corners)

    def face(self, verts):
        try:
            return self.bm.faces.new(verts)
        except ValueError:
            return None

    def finish(self, name, kind, shadows=True, sharp_angle=None, triangles=None):
        bm = self.bm
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces) if kind == ROCK else None
        bmesh.ops.triangulate(bm, faces=bm.faces)
        bm.normal_update()
        for face in bm.faces:
            face.smooth = True
        if sharp_angle is not None:
            for edge in bm.edges:
                if len(edge.link_faces) == 2 and edge.calc_face_angle(0.0) > sharp_angle:
                    edge.smooth = False
        mesh = bpy.data.meshes.new(name)
        bm.to_mesh(mesh)
        bm.free()
        obj = bpy.data.objects.new(name, mesh)
        bpy.context.scene.collection.children["landscape_kit"].objects.link(obj)
        if triangles is not None and len(mesh.polygons) > triangles:
            # Thin the lumps down to a budget; colours, sway and soft normals are carried across.
            modifier = obj.modifiers.new("decimate", "DECIMATE")
            modifier.ratio = triangles / len(mesh.polygons)
            with bpy.context.temp_override(object=obj, active_object=obj, selected_objects=[obj]):
                bpy.ops.object.modifier_apply(modifier="decimate")
            mesh = obj.data
        # Soft normals: a canopy lit as one round shape rather than as separate facets.
        soft = mesh.attributes.get("soft_normal")
        if soft is not None and any(Vector(item.vector).length > 0.0 for item in soft.data):
            normals = []
            for loop in mesh.loops:
                wanted = Vector(soft.data[loop.vertex_index].vector)
                normals.append(wanted.normalized() if wanted.length > 0.0 else Vector(mesh.corner_normals[loop.index].vector))
            mesh.normals_split_custom_set(normals)
        uv = mesh.uv_layers.new(name="sway")
        sway = mesh.attributes["sway"]
        tex = mesh.attributes["tex"]
        for loop in mesh.loops:
            if kind == LEAVES:
                uv.data[loop.index].uv = (tex.data[loop.vertex_index].vector[0], tex.data[loop.vertex_index].vector[1])
            else:
                uv.data[loop.index].uv = (sway.data[loop.vertex_index].value, tex.data[loop.vertex_index].vector[0])
        pieces.append((obj, kind, shadows))
        return obj


def lerp(a, b, t):
    return a + (b - a) * t


def mix(a, b, t):
    return tuple(lerp(a[i], b[i], t) for i in range(3))


def shade(color, amount):
    return tuple(c * amount for c in color)


# ---------------------------------------------------------------- rock

def chunk(builder, rng, centre, size, points=16, boxy=4.0, tilt=0.0):
    """One block of rock: the convex hull of points on a rounded box."""
    turn = Matrix.Rotation(rng.uniform(0.0, math.tau), 3, "Z") @ Matrix.Rotation(rng.uniform(-tilt, tilt), 3, "X")
    verts = []
    for _ in range(points):
        d = Vector((rng.gauss(0, 1), rng.gauss(0, 1), rng.gauss(0, 1)))
        norm = (abs(d.x) ** boxy + abs(d.y) ** boxy + abs(d.z) ** boxy) ** (1.0 / boxy)
        d = d / max(norm, 1e-6) * rng.uniform(0.82, 1.0)
        p = turn @ Vector((d.x * size[0], d.y * size[1], d.z * size[2]))
        verts.append(builder.vert(Vector(centre) + p, (1.0, 1.0, 1.0)))
    result = bmesh.ops.convex_hull(builder.bm, input=verts)
    spare = [g for g in result["geom_interior"] + result["geom_unused"] if isinstance(g, bmesh.types.BMVert)]
    bmesh.ops.delete(builder.bm, geom=list(set(spare)), context="VERTS")


def bevel(obj, width):
    modifier = obj.modifiers.new("bevel", "BEVEL")
    modifier.width = width
    modifier.segments = 1
    modifier.limit_method = "ANGLE"
    modifier.angle_limit = math.radians(25)
    weighted = obj.modifiers.new("weighted", "WEIGHTED_NORMAL")
    weighted.keep_sharp = True
    with bpy.context.temp_override(object=obj, active_object=obj, selected_objects=[obj]):
        bpy.ops.object.modifier_apply(modifier="bevel")
        bpy.ops.object.modifier_apply(modifier="weighted")


def erode(obj, seed, voxel, triangles, beds=0.5, cracks=1.0, moss=None, ore=None):
    """Fuses a pile of blocks into one weathered rock: remeshed, cut into beds, cracked, then thinned to a budget."""
    remesh = obj.modifiers.new("remesh", "REMESH")
    remesh.mode = "VOXEL"
    remesh.voxel_size = voxel
    with bpy.context.temp_override(object=obj, active_object=obj, selected_objects=[obj]):
        bpy.ops.object.modifier_apply(modifier="remesh")
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.smooth_vert(bm, verts=bm.verts, factor=0.5, use_axis_x=True, use_axis_y=True, use_axis_z=True)
    bm.normal_update()
    shift = Vector((seed * 3.1, seed * 1.7, seed * 0.9))
    moved = []
    for v in bm.verts:
        p = v.co
        # Beds: level layers, each set in or out a little, with a groove where two meet.
        level = (p.z + 0.18 * noise.noise(Vector((p.x * 0.5, p.y * 0.5, 0.0)) + shift)) / max(beds, 0.01)
        layer = math.floor(level)
        inset = (noise.noise(Vector((layer * 7.3, seed * 1.0, 0.5))) * 0.5 + 0.5) * 0.11
        within = level - layer
        groove = 0.07 * (1.0 - min(1.0, min(within, 1.0 - within) / 0.12))
        # Cracks: the seams between cells of a stretched cellular pattern, so they run mostly up and down.
        distances, _ = noise.voronoi(Vector((p.x * 1.3, p.y * 1.3, p.z * 0.45)) + shift)
        seam = 1.0 - min(1.0, (distances[1] - distances[0]) / 0.14)
        rough = 0.05 * noise.noise(p * 2.3 + shift)
        steep = 1.0 - abs(v.normal.z)
        moved.append(p - v.normal * ((inset + groove) * steep + 0.14 * seam * seam * cracks) + v.normal * rough)
    for v, p in zip(bm.verts, moved):
        v.co = p
    # Nothing below the ground: the base is buried anyway.
    bmesh.ops.bisect_plane(bm, geom=bm.verts[:] + bm.edges[:] + bm.faces[:], plane_co=(0, 0, -0.35), plane_no=(0, 0, -1), clear_outer=True)
    bm.to_mesh(obj.data)
    bm.free()
    decimate = obj.modifiers.new("decimate", "DECIMATE")
    decimate.ratio = min(1.0, triangles / max(len(obj.data.polygons) * 2, 1))
    with bpy.context.temp_override(object=obj, active_object=obj, selected_objects=[obj]):
        bpy.ops.object.modifier_apply(modifier="decimate")
    mesh = obj.data
    for polygon in mesh.polygons:
        polygon.use_smooth = True
    mesh.set_sharp_from_angle(angle=math.radians(42))
    # The remesh drops the builder's data; rock is plain white with no sway.
    for name in ("base", "sway"):
        if mesh.attributes.get(name):
            mesh.attributes.remove(mesh.attributes[name])
    base = mesh.attributes.new("base", "FLOAT_COLOR", "POINT")
    for index, item in enumerate(base.data):
        color = (1.0, 1.0, 1.0)
        vertex = mesh.vertices[index]
        patch = noise.noise(vertex.co * 2.2 + shift) * 0.5 + 0.5
        if ore is not None:
            # Seams of ore through the rock, with darker metal where they are richest.
            vein = noise.noise(Vector((vertex.co.x * 1.4, vertex.co.y * 1.4, vertex.co.z * 3.0)) + shift * 2.0) * 0.5 + 0.5
            amount = max(0.0, min(1.0, (vein - 0.3) / 0.25))
            color = mix(color, mix(ore[0], ore[1], max(0.0, min(1.0, (patch - 0.45) / 0.2))), amount)
        if moss is not None:
            # Moss on whatever faces up, thinning towards the sides.
            cover = max(0.0, min(1.0, (vertex.normal.z - 0.15) / 0.5)) * max(0.0, min(1.0, (patch - 0.15) / 0.3))
            color = mix(color, shade(moss, 0.75 + patch * 0.5), cover)
        item.color = (color[0], color[1], color[2], 1.0)
    while mesh.uv_layers:
        mesh.uv_layers.remove(mesh.uv_layers[0])
    layer = mesh.uv_layers.new(name="sway_uv")
    for loop in layer.data:
        loop.uv = (0.0, 0.0)
    return obj


def boulder(name, seed, size, lumps=2):
    rng = random.Random(seed)
    builder = Builder()
    chunk(builder, rng, (0, 0, size[2] * 0.42), size, points=30, boxy=2.6, tilt=0.3)
    for _ in range(lumps):
        s = rng.uniform(0.4, 0.62)
        angle = rng.uniform(0.0, math.tau)
        offset = (math.cos(angle) * size[0] * 0.75, math.sin(angle) * size[1] * 0.75, size[2] * s * 0.4)
        chunk(builder, rng, offset, (size[0] * s, size[1] * s, size[2] * s), points=20, boxy=2.6, tilt=0.5)
    obj = builder.finish(name, ROCK, sharp_angle=math.radians(38))
    return erode(obj, seed, 0.07, 360, beds=0.4, cracks=0.7)


def stones(name, seed, count, spread, size):
    rng = random.Random(seed)
    builder = Builder()
    for _ in range(count):
        s = size * rng.uniform(0.45, 1.0)
        angle = rng.uniform(0.0, math.tau)
        reach = spread * math.sqrt(rng.random())
        chunk(builder, rng, (math.cos(angle) * reach, math.sin(angle) * reach, s * 0.22), (s, s * rng.uniform(0.7, 1.0), s * rng.uniform(0.45, 0.7)), points=10, boxy=2.6, tilt=0.4)
    return builder.finish(name, ROCK, shadows=False, sharp_angle=math.radians(38))


def shore_rock(name, seed, size):
    rng = random.Random(seed)
    builder = Builder()
    chunk(builder, rng, (0, 0, size[2] * 0.3), size, points=22, boxy=2.4, tilt=0.2)
    s = rng.uniform(0.45, 0.6)
    chunk(builder, rng, (size[0] * 0.8, rng.uniform(-0.4, 0.4) * size[1], size[2] * 0.12), (size[0] * s, size[1] * s, size[2] * s * 0.8), points=14, boxy=2.4, tilt=0.3)
    obj = builder.finish(name, ROCK, sharp_angle=math.radians(40))
    return erode(obj, seed, 0.06, 240, beds=0.9, cracks=0.4)


def block(builder, rng, x0, x1, y_front, y_back, z0, z1, lean=0.0, crown=0.0):
    """One rib of a rock face: a prism with a keeled front, knocked-about corners and a broken, sloping top."""
    width = x1 - x0
    yaw = Matrix.Rotation(rng.uniform(-0.16, 0.16), 3, "Z")
    pivot = Vector(((x0 + x1) * 0.5, (y_front + y_back) * 0.5, 0.0))
    keel = lerp(x0, x1, rng.uniform(0.3, 0.7))
    points = []
    levels = 3
    for level in range(levels + 1):
        t = level / levels
        z = lerp(z0, z1, t)
        back = lean * (z - z0)
        # The rib narrows a little as it rises and its front edge wanders.
        pinch = width * 0.06 * t
        front = y_front + back + rng.uniform(-0.1, 0.1)
        top = level == levels
        for x, y in ((x0 + pinch, front + rng.uniform(0.1, 0.3)), (keel + rng.uniform(-0.1, 0.1), front - rng.uniform(0.1, 0.32)), (x1 - pinch, front + rng.uniform(0.1, 0.3)), (x0, y_back), (x1, y_back)):
            # The top breaks off unevenly, higher at the back where the rib joins the hill.
            rise = (rng.uniform(-crown, crown * 0.4) + (crown * 0.5 if y == y_back else 0.0)) if top else 0.0
            points.append(pivot + yaw @ (Vector((x, y, z + rise)) - pivot))
    verts = [builder.vert(p, (1.0, 1.0, 1.0)) for p in points]
    result = bmesh.ops.convex_hull(builder.bm, input=verts)
    spare = [g for g in result["geom_interior"] + result["geom_unused"] if isinstance(g, bmesh.types.BMVert)]
    bmesh.ops.delete(builder.bm, geom=list(set(spare)), context="VERTS")


def cliff(name, seed, width, height, columns):
    """A rock face of jointed ribs, each stepping back as it rises. Faces -Y; its back is buried in the hill."""
    rng = random.Random(seed)
    builder = Builder()
    edges = sorted([-width * 0.5, width * 0.5] + [rng.uniform(-width * 0.5 + 0.4, width * 0.5 - 0.4) for _ in range(columns - 1)])
    # Keep ribs from getting too thin.
    kept = [edges[0]]
    for edge in edges[1:-1]:
        if edge - kept[-1] > 0.5 and edges[-1] - edge > 0.5:
            kept.append(edge)
    edges = kept + [edges[-1]]
    back = 1.7
    for index in range(len(edges) - 1):
        x0, x1 = edges[index] - 0.04, edges[index + 1] + 0.04
        # Ribs stand proud or sit back, taller towards the middle of the piece.
        middle = 1.0 - abs((x0 + x1) / width) ** 2 * 0.25
        top = height * middle * rng.uniform(0.72, 1.0)
        front = rng.uniform(-1.0, 0.0)
        z = -0.4
        steps = rng.choice((1, 2, 2, 3))
        for step in range(steps):
            last = step == steps - 1
            z1 = top if last else lerp(z, top, rng.uniform(0.3, 0.6))
            block(builder, rng, x0, x1, front, back, z, z1, lean=rng.uniform(0.03, 0.16), crown=0.55 if last else 0.2)
            # The next block up sits back on a ledge and is a little narrower.
            front += rng.uniform(0.25, 0.6)
            x0 += rng.uniform(0.0, 0.12)
            x1 -= rng.uniform(0.0, 0.12)
            z = z1 - 0.3
            if front > back - 0.5:
                break
        # Fallen blocks at the foot of some ribs.
        if rng.random() < 0.45:
            s = rng.uniform(0.22, 0.4)
            chunk(builder, rng, (lerp(x0, x1, rng.random()), front - rng.uniform(1.0, 1.5), s * 0.5), (s * 1.3, s, s), points=10, boxy=3.0, tilt=0.5)
    obj = builder.finish(name, ROCK, sharp_angle=math.radians(32))
    return erode(obj, seed, 0.1, 900, beds=0.55, cracks=1.0)


# ---------------------------------------------------------------- trees

BARK = (0.13, 0.092, 0.06)
MOSS = (0.07, 0.15, 0.03)
NEEDLE_DARK = (0.006, 0.03, 0.024)
NEEDLE_LIGHT = (0.03, 0.09, 0.055)
LEAF_DARK = (0.006, 0.03, 0.01)
LEAF_LIGHT = (0.055, 0.135, 0.028)


def tube(builder, path, radii, sides, color, sway, lobes=0.0, seed=0.0):
    """A limb along a path: a ring of vertices at each point, joined into a tapering tube."""
    rings = []
    for index, point in enumerate(path):
        ahead = (path[min(index + 1, len(path) - 1)] - path[max(index - 1, 0)]).normalized()
        side = ahead.cross(Vector((0.3, 0.9, 0.2))).normalized()
        up = ahead.cross(side).normalized()
        t = index / max(len(path) - 1, 1)
        ring = []
        for step in range(sides):
            a = math.tau * step / sides
            # Lobes: buttress roots at the foot of a trunk.
            spread = 1.0 if index == 0 else 0.25 if index == 1 else 0.0
            bulge = 1.0 + lobes * (noise.noise(Vector((step * 1.9, seed, index * 0.7))) * 0.5 + 0.5) * spread
            v = builder.vert(point + (side * math.cos(a) + up * math.sin(a)) * radii[index] * bulge, color(t, point), sway(t))
            v[builder.tex] = (1.0, 0.0, 0.0)
            ring.append(v)
        rings.append(ring)
    for index in range(len(rings) - 1):
        for step in range(sides):
            builder.face([rings[index][step], rings[index][(step + 1) % sides], rings[index + 1][(step + 1) % sides], rings[index + 1][step]])
    tip = builder.vert(path[-1] + (path[-1] - path[-2]).normalized() * radii[-1], color(1.0, path[-1]), sway(1.0))
    tip[builder.tex] = (1.0, 0.0, 0.0)
    for step in range(sides):
        builder.face([rings[-1][step], rings[-1][(step + 1) % sides], tip])


def bark(mossy):
    def color(t, point):
        # Moss climbs the foot of the trunk; bark lightens a little with height.
        moss = max(0.0, 1.0 - point.z / 1.1) * mossy
        return mix(shade(BARK, 0.8 + 0.35 * t), MOSS, moss * 0.55)
    return color


def spruce(name, seed, height, radius, tiers):
    """A tall dark conifer: a bare lower trunk with dead stubs, then tiers of long drooping boughs up to a spire."""
    rng = random.Random(seed)
    builder = Builder()
    leaves = Builder()
    lean = Vector((rng.uniform(-0.25, 0.25), rng.uniform(-0.25, 0.25), 0.0))
    path = [Vector((0, 0, -0.2)), lean * 0.2 + Vector((0, 0, height * 0.3)), lean * 0.6 + Vector((0, 0, height * 0.65)), lean + Vector((0, 0, height * 0.97))]
    girth = 0.11 + height * 0.016
    tube(builder, path, [girth * 1.25, girth, girth * 0.6, girth * 0.18], 8, bark(0.6), lambda t: 0.3 * t * t, lobes=0.5, seed=seed)
    first = height * rng.uniform(0.3, 0.36)
    for stub in range(4):
        a = rng.uniform(0.0, math.tau)
        start = Vector((0, 0, first * rng.uniform(0.45, 0.95)))
        tube(builder, [start, start + Vector((math.cos(a), math.sin(a), 0.15)) * rng.uniform(0.3, 0.6)], [0.035, 0.012], 3, bark(0.0), lambda t: 0.1)
    rise = (height - first) / tiers
    for tier in range(tiers):
        t = tier / max(tiers - 1, 1)
        centre = lean * (0.3 + 0.7 * t)
        z = first + rise * tier
        r = radius * (1.0 - t) ** 0.7 * rng.uniform(0.85, 1.1) + 0.2
        tone = lerp(0.75, 1.25, t) * rng.uniform(0.9, 1.1)
        # A dark core close to the trunk, so the tree is never seen through.
        core_top = builder.vert(centre + Vector((0, 0, z + rise * 1.6)), shade(NEEDLE_DARK, 0.9 * tone), 0.3 * t, (0, 0, 1))
        ring = []
        for point in range(6):
            a = math.tau * point / 6
            ring.append(builder.vert(centre + Vector((math.cos(a) * r * 0.42, math.sin(a) * r * 0.42, z - rise * 0.1)), shade(NEEDLE_DARK, 0.6 * tone), 0.3 * t, (math.cos(a), math.sin(a), 0.4)))
        for point in range(6):
            builder.face([core_top, ring[point], ring[(point + 1) % 6]])
        # Boughs: flat sprays that leave the trunk level and hang towards their tips.
        boughs = 7 if t < 0.7 else 5
        offset = rng.uniform(0.0, math.tau)
        for bough in range(boughs):
            a = offset + math.tau * bough / boughs + rng.uniform(-0.2, 0.2)
            out = Vector((math.cos(a), math.sin(a), 0.0))
            reach = r * rng.uniform(0.8, 1.2)
            start = centre + Vector((0, 0, z + rise * rng.uniform(0.3, 0.7)))
            end = start + out * reach + Vector((0, 0, -reach * rng.uniform(0.3, 0.55)))
            along = (end - start) * 0.5
            across = along.cross(Vector((0, 0, 1))).normalized() * reach * 0.45
            normal = (Vector((0, 0, 1)) + out * 0.5).normalized()
            leaves.card((start + end) * 0.5, across, -along, 2, shade(NEEDLE_DARK, 1.4 * tone), shade(NEEDLE_LIGHT, tone * rng.uniform(0.85, 1.15)), normal, start)
    # The leader: two crossed sprays standing up.
    top = lean + Vector((0, 0, height * 0.86))
    for a in (0.0, math.pi * 0.5):
        leaves.card(top, Vector((math.cos(a), math.sin(a), 0.0)) * radius * 0.3, Vector((0, 0, -height * 0.14)), 2, shade(NEEDLE_DARK, 1.6), shade(NEEDLE_LIGHT, 1.2), (math.sin(a), math.cos(a), 0.6), top)
    leaves.finish(name + "_leaves", LEAVES)
    return builder.finish(name, FOLIAGE)


def leaf_spray(builder, leaves, rng, centre, radius, crown_centre, crown_radius, tone, hue):
    """A bunch of leaves at the end of a limb: a small dark heart and several cut-out cards around it."""
    result = bmesh.ops.create_icosphere(builder.bm, subdivisions=1, radius=radius * 0.55)
    for v in result["verts"]:
        v.co = Vector(centre) + Vector((v.co.x, v.co.y, v.co.z * 0.6))
        v[builder.color] = (LEAF_DARK[0] * 0.8, LEAF_DARK[1] * 0.8, LEAF_DARK[2] * 0.8, 1.0)
        v[builder.sway] = 0.4
        v[builder.normal] = (v.co - crown_centre).normalized()
    outward = (Vector(centre) - crown_centre)
    rim = max(0.0, min(1.0, outward.length / crown_radius))
    high = max(0.0, min(1.0, outward.z / crown_radius * 0.5 + 0.5))
    light = max(0.0, min(1.0, 0.15 + 0.55 * high ** 1.3 + 0.3 * rim ** 2))
    for card in range(6):
        facing = (outward.normalized() * 0.6 + Vector((rng.gauss(0, 1), rng.gauss(0, 1), rng.gauss(0, 1))) * 0.7 + Vector((0, 0, 0.45))).normalized()
        across = facing.cross(Vector((0.13, 0.21, 1.0))).normalized()
        up = facing.cross(across).normalized()
        turn = rng.uniform(0.0, math.tau)
        size = radius * rng.uniform(1.1, 1.6)
        a = (across * math.cos(turn) + up * math.sin(turn)) * size
        b = (up * math.cos(turn) - across * math.sin(turn)) * size
        place = Vector(centre) + Vector((rng.gauss(0, 1), rng.gauss(0, 1), rng.gauss(0, 0.6))) * radius * 0.45
        shade_card = tone * rng.uniform(0.85, 1.15)
        outer = mix(LEAF_DARK, LEAF_LIGHT, min(1.0, light * 1.25 + 0.2))
        inner = mix(LEAF_DARK, LEAF_LIGHT, light * 0.3)
        tint = lambda c: (c[0] * shade_card * (1.0 + hue), c[1] * shade_card, c[2] * shade_card * (1.0 - hue))
        normal = (facing * 0.35 + outward.normalized() * 0.4 + Vector((0, 0, 0.45))).normalized()
        leaves.card(place, a, b, rng.choice((0, 0, 1, 3)), tint(inner), tint(outer), normal, crown_centre)


def old_tree(name, seed, height, crown, limbs):
    """An old broadleaf: a leaning, moss-footed trunk that forks into heavy limbs, each carrying sprays of leaves."""
    rng = random.Random(seed)
    builder = Builder()
    leaves = Builder()
    fork = height * rng.uniform(0.42, 0.52)
    lean = Vector((rng.uniform(-0.5, 0.5), rng.uniform(-0.5, 0.5), 0.0))
    foot = 0.2 + height * 0.022
    path = [Vector((0, 0, -0.2)), lean * 0.15 + Vector((0, 0, fork * 0.3)), lean * 0.5 + Vector((0, 0, fork * 0.7)), lean + Vector((0, 0, fork))]
    tube(builder, path, [foot * 1.3, foot, foot * 0.88, foot * 0.78], 10, bark(1.0), lambda t: 0.08 * t, lobes=0.6, seed=seed)
    crown_centre = lean * 1.2 + Vector((0, 0, fork + (height - fork) * 0.5))
    tree_hue = rng.uniform(-0.08, 0.14)
    ends = []
    for limb in range(limbs):
        a = math.tau * limb / limbs + rng.uniform(-0.45, 0.45)
        reach = crown * rng.uniform(0.5, 0.85)
        end = lean + Vector((math.cos(a) * reach, math.sin(a) * reach, fork + (height - fork) * rng.uniform(0.25, 0.7)))
        start = path[-1] + Vector((0, 0, -0.25))
        middle = start.lerp(end, 0.5) + Vector((rng.uniform(-0.25, 0.25), rng.uniform(-0.25, 0.25), (end.z - start.z) * rng.uniform(0.1, 0.28)))
        tube(builder, [start, middle, end], [foot * 0.55, foot * 0.36, foot * 0.14], 5, bark(0.0), lambda t: 0.1 + 0.3 * t)
        ends.append(end)
        # A side branch off the middle of the limb fills the crown between limbs.
        side = middle + Vector((rng.uniform(-1, 1), rng.uniform(-1, 1), rng.uniform(0.3, 0.9))) * crown * 0.35
        tube(builder, [middle, side], [foot * 0.22, foot * 0.08], 4, bark(0.0), lambda t: 0.2 + 0.3 * t)
        ends.append(side)
    # The leader carries the top of the crown.
    top = lean * 1.3 + Vector((0, 0, height - crown * 0.3))
    tube(builder, [path[-1], top], [foot * 0.6, foot * 0.12], 5, bark(0.0), lambda t: 0.1 + 0.3 * t)
    ends.append(top)
    for end in ends:
        for spray in range(rng.choice((2, 3, 3))):
            offset = Vector((rng.gauss(0, 1), rng.gauss(0, 1), rng.gauss(0, 0.5))) * crown * 0.24
            leaf_spray(builder, leaves, rng, end + offset, crown * rng.uniform(0.3, 0.42), crown_centre, crown * 1.1, rng.uniform(0.8, 1.15), tree_hue + rng.uniform(-0.08, 0.08))
    leaves.finish(name + "_leaves", LEAVES)
    return builder.finish(name, FOLIAGE)


def blob(builder, rng, centre, radius, squash, crown_centre, crown_radius, tone, sway, subdivisions=2):
    result = bmesh.ops.create_icosphere(builder.bm, subdivisions=subdivisions, radius=1.0)
    hue = rng.uniform(-0.12, 0.12)
    turn = Matrix.Rotation(rng.uniform(0.0, math.tau), 3, "Z") @ Matrix.Rotation(rng.uniform(0.0, math.tau), 3, "X")
    shift = Vector((rng.uniform(0, 50), rng.uniform(0, 50), rng.uniform(0, 50)))
    for v in result["verts"]:
        direction = (turn @ v.co).normalized()
        lump = 1.0 + 0.3 * noise.noise(direction * 1.7 + shift) + 0.12 * noise.noise(direction * 4.3 + shift)
        v.co = Vector(centre) + Vector((direction.x * radius * lump, direction.y * radius * lump, direction.z * radius * squash * lump))
        outward = (v.co - crown_centre)
        height_share = max(0.0, min(1.0, (outward.z / crown_radius) * 0.5 + 0.5))
        light = max(0.0, min(1.0, 0.1 + 0.9 * height_share ** 1.2 + 0.25 * noise.noise(direction * 3.1 + shift)))
        color = mix(LEAF_DARK, LEAF_LIGHT, light)
        color = (color[0] * (1.0 + hue), color[1], color[2] * (1.0 - hue))
        v[builder.color] = (color[0] * tone, color[1] * tone, color[2] * tone, 1.0)
        v[builder.sway] = sway * (0.6 + 0.4 * height_share)
        soft = (direction * 0.6 + outward.normalized() * 0.4)
        v[builder.normal] = soft.normalized()


def fallen_log(name, seed, length, radius):
    rng = random.Random(seed)
    builder = Builder()

    def color(t, point):
        return mix(shade(BARK, 0.9), MOSS, 0.75 * (noise.noise(point * 1.3) * 0.5 + 0.5))
    path = [Vector((-length * 0.5, 0, radius * 0.7)), Vector((-length * 0.15, rng.uniform(-0.1, 0.1), radius * 0.75)), Vector((length * 0.2, rng.uniform(-0.1, 0.1), radius * 0.7)), Vector((length * 0.5, 0, radius * 0.6))]
    tube(builder, path, [radius * 1.1, radius, radius * 0.9, radius * 0.75], 7, color, lambda t: 0.0)
    for stub in range(2):
        start = path[1 + stub] + Vector((0, 0, radius * 0.5))
        tube(builder, [start, start + Vector((rng.uniform(-0.2, 0.2), rng.uniform(-0.3, 0.3), rng.uniform(0.3, 0.5)))], [radius * 0.3, radius * 0.1], 4, color, lambda t: 0.0)
    return builder.finish(name, FOLIAGE)


def mossy_rock(name, seed, size):
    rng = random.Random(seed)
    builder = Builder()
    chunk(builder, rng, (0, 0, size[2] * 0.35), size, points=24, boxy=2.4, tilt=0.3)
    obj = builder.finish(name, ROCK, sharp_angle=math.radians(38))
    return erode(obj, seed, 0.06, 220, beds=0.6, cracks=0.4, moss=(0.3, 0.75, 0.2))


def ore_outcrop(name, seed, size, lumps):
    """Iron ore breaking the surface: low, blocky rock shot through with rust-red seams and dark metal."""
    rng = random.Random(seed)
    builder = Builder()
    for lump in range(lumps):
        s = rng.uniform(0.5, 1.0)
        a = rng.uniform(0.0, math.tau)
        reach = 0.0 if lump == 0 else rng.uniform(0.35, 0.7) * size[0]
        chunk(builder, rng, (math.cos(a) * reach, math.sin(a) * reach, size[2] * s * 0.3), (size[0] * s * 0.6, size[1] * s * 0.6, size[2] * s), points=16, boxy=4.0, tilt=0.35)
    obj = builder.finish(name, ROCK, sharp_angle=math.radians(36))
    return erode(obj, seed, 0.05, 260, beds=0.3, cracks=0.8, ore=((0.42, 0.13, 0.06), (0.13, 0.14, 0.19)))


# ---------------------------------------------------------------- plants

def blade(builder, rng, root, direction, length, width, bottom, tip, lean, segments=1, sway=1.0, lit=None):
    """A leaf: a strip that leans away from the plant's centre and narrows to a point."""
    side = Vector((-direction.y, direction.x, 0.0)) * width * 0.5
    normal = lit if lit is not None else (0.0, 0.0, 1.0)
    previous = [builder.vert(Vector(root) - side, bottom, 0.0, normal), builder.vert(Vector(root) + side, bottom, 0.0, normal)]
    for segment in range(1, segments + 1):
        t = segment / (segments + 1)
        out = lean * t * t * length
        centre = Vector(root) + Vector((direction.x * out, direction.y * out, length * t))
        narrow = side * (1.0 - t * 0.6)
        ring = [builder.vert(centre - narrow, mix(bottom, tip, t), sway * t * t, normal), builder.vert(centre + narrow, mix(bottom, tip, t), sway * t * t, normal)]
        builder.face([previous[0], previous[1], ring[1], ring[0]])
        previous = ring
    end = Vector(root) + Vector((direction.x * lean * length, direction.y * lean * length, length))
    builder.face([previous[0], previous[1], builder.vert(end, tip, sway, normal)])


def tuft(name, seed, blades, height, spread, bottom, tip, flowers=None, lean=0.45, width=0.07, segments=1):
    rng = random.Random(seed)
    builder = Builder()
    for index in range(blades):
        a = math.tau * index / blades + rng.uniform(-0.5, 0.5)
        direction = Vector((math.cos(a), math.sin(a), 0.0))
        reach = spread * rng.uniform(0.1, 1.0)
        blade(builder, rng, (direction.x * reach, direction.y * reach, 0.0), direction, height * rng.uniform(0.6, 1.0), width * rng.uniform(0.8, 1.3), bottom, shade(tip, rng.uniform(0.85, 1.15)), lean * rng.uniform(0.3, 1.2), segments)
    if flowers:
        for index in range(flowers[1]):
            a = rng.uniform(0.0, math.tau)
            reach = spread * rng.uniform(0.2, 1.3)
            h = height * rng.uniform(0.9, 1.35)
            centre = Vector((math.cos(a) * reach, math.sin(a) * reach, h))
            size = rng.uniform(0.055, 0.085)
            quad = [builder.vert(centre + Vector(o) * size, shade(flowers[0], rng.uniform(0.85, 1.1)), 1.0, (0, 0, 1)) for o in ((-1, -1, 0), (1, -1, 0), (1, 1, 0), (-1, 1, 0))]
            builder.face(quad)
            stem = [builder.vert((centre.x - 0.012, centre.y, 0.0), bottom, 0.0, (0, 0, 1)), builder.vert((centre.x + 0.012, centre.y, 0.0), bottom, 0.0, (0, 0, 1)), builder.vert(centre, tip, 1.0, (0, 0, 1))]
            builder.face(stem)
    return builder.finish(name, BLADES, shadows=False)


def reeds(name, seed, stems, height):
    rng = random.Random(seed)
    builder = Builder()
    bottom = (0.05, 0.1, 0.03)
    tip = (0.26, 0.33, 0.1)
    for index in range(stems):
        a = rng.uniform(0.0, math.tau)
        direction = Vector((math.cos(a), math.sin(a), 0.0))
        reach = rng.uniform(0.0, 0.35)
        root = (direction.x * reach, direction.y * reach, 0.0)
        h = height * rng.uniform(0.6, 1.0)
        blade(builder, rng, root, direction, h, 0.06, bottom, tip, rng.uniform(0.05, 0.3), segments=2, sway=0.8)
        if index % 3 == 0:
            # A seed head: a short dark spindle.
            top = Vector(root) + Vector((0.0, 0.0, h * 1.02))
            ring = [builder.vert(top + Vector((math.cos(math.tau * i / 4) * 0.035, math.sin(math.tau * i / 4) * 0.035, 0.0)), (0.12, 0.065, 0.03), 0.8, (math.cos(math.tau * i / 4), math.sin(math.tau * i / 4), 0.4)) for i in range(4)]
            low = builder.vert(top + Vector((0, 0, -0.1)), (0.1, 0.055, 0.03), 0.8, (0, 0, -1))
            high = builder.vert(top + Vector((0, 0, 0.14)), (0.14, 0.08, 0.04), 0.8, (0, 0, 1))
            for i in range(4):
                builder.face([high, ring[i], ring[(i + 1) % 4]])
                builder.face([low, ring[(i + 1) % 4], ring[i]])
    return builder.finish(name, BLADES, shadows=False)


def bush(name, seed, lumps, radius, dark, light):
    rng = random.Random(seed)
    builder = Builder()
    global LEAF_DARK, LEAF_LIGHT
    keep = (LEAF_DARK, LEAF_LIGHT)
    LEAF_DARK, LEAF_LIGHT = dark, light
    centre = Vector((0, 0, radius * 0.55))
    for index in range(lumps):
        a = math.tau * index / lumps + rng.uniform(-0.5, 0.5)
        reach = radius * (0.0 if index == 0 else rng.uniform(0.45, 0.75))
        size = radius * (0.7 if index == 0 else rng.uniform(0.42, 0.58))
        blob(builder, rng, Vector((math.cos(a) * reach, math.sin(a) * reach, size * 0.62)), size, 0.78, centre, radius, rng.uniform(0.88, 1.08), 0.5)
    LEAF_DARK, LEAF_LIGHT = keep
    return builder.finish(name, FOLIAGE, triangles=70)


def dry_bush(name, seed, twigs, radius):
    rng = random.Random(seed)
    builder = Builder()
    for index in range(twigs):
        a = rng.uniform(0.0, math.tau)
        direction = Vector((math.cos(a), math.sin(a), 0.0))
        blade(builder, rng, (direction.x * 0.04, direction.y * 0.04, 0.0), direction, radius * rng.uniform(0.5, 1.0), 0.09, (0.11, 0.085, 0.045), shade((0.4, 0.34, 0.16), rng.uniform(0.8, 1.15)), rng.uniform(0.5, 1.6), segments=1, sway=0.4)
    return builder.finish(name, BLADES, shadows=False)


def fern(name, seed, fronds, length):
    rng = random.Random(seed)
    builder = Builder()
    for index in range(fronds):
        a = math.tau * index / fronds + rng.uniform(-0.3, 0.3)
        direction = Vector((math.cos(a), math.sin(a), 0.0))
        blade(builder, rng, (direction.x * 0.05, direction.y * 0.05, 0.0), direction, length * rng.uniform(0.35, 0.6), 0.24, (0.025, 0.09, 0.02), shade((0.13, 0.33, 0.07), rng.uniform(0.8, 1.15)), rng.uniform(1.2, 2.0), segments=2, sway=0.5)
    return builder.finish(name, BLADES, shadows=False)


# ---------------------------------------------------------------- build, shade, export

def _stamp(canvas, x0, y0, shape, value):
    """Paints value where shape is set, into a tile-sized RGBA canvas at an integer offset."""
    h, w = shape.shape
    x1, y1 = x0 + w, y0 + h
    cx0, cy0 = max(x0, 0), max(y0, 0)
    cx1, cy1 = min(x1, canvas.shape[1]), min(y1, canvas.shape[0])
    if cx0 >= cx1 or cy0 >= cy1:
        return
    part = shape[cy0 - y0:cy1 - y0, cx0 - x0:cx1 - x0]
    light = value[cy0 - y0:cy1 - y0, cx0 - x0:cx1 - x0]
    target = canvas[cy0:cy1, cx0:cx1]
    target[..., 0] = np.where(part, light, target[..., 0])
    target[..., 3] = np.where(part, 1.0, target[..., 3])


def _leaf(canvas, rng, x, y, length, angle, light):
    half = int(length * 0.6) + 2
    ys, xs = np.mgrid[-half:half + 1, -half:half + 1].astype(np.float32)
    u = xs * math.cos(angle) + ys * math.sin(angle)
    v = -xs * math.sin(angle) + ys * math.cos(angle)
    t = np.clip(u / length + 0.5, 0.0, 1.0)
    # A pointed oval, widest a little behind its middle.
    width = length * 0.26 * np.sin(math.pi * t ** 0.8) ** 0.9
    inside = (np.abs(v) < width) & (np.abs(u) < length * 0.5)
    edge = np.clip(np.abs(v) / np.maximum(width, 0.01), 0.0, 1.0)
    value = light * (1.0 - 0.3 * edge ** 2) + 0.12 * (np.abs(v) < 0.9)
    _stamp(canvas, int(x) - half, int(y) - half, inside, np.clip(value, 0.0, 1.0))


def _stroke(canvas, ax, ay, bx, by, width, light):
    pad = int(width) + 2
    x0, x1 = int(min(ax, bx)) - pad, int(max(ax, bx)) + pad + 1
    y0, y1 = int(min(ay, by)) - pad, int(max(ay, by)) + pad + 1
    ys, xs = np.mgrid[y0:y1, x0:x1].astype(np.float32)
    dx, dy = bx - ax, by - ay
    t = np.clip(((xs - ax) * dx + (ys - ay) * dy) / max(dx * dx + dy * dy, 1e-6), 0.0, 1.0)
    distance = np.hypot(xs - (ax + dx * t), ys - (ay + dy * t))
    _stamp(canvas, x0, y0, distance < width, np.full(distance.shape, light, dtype=np.float32))


def leaf_tile(seed, size, leaves, spread):
    """A spray of broad leaves, darker ones underneath, thinning to single leaves at its rim."""
    rng = random.Random(seed)
    canvas = np.zeros((size, size, 4), dtype=np.float32)
    items = []
    for _ in range(leaves):
        r = min(abs(rng.gauss(0, spread)), 0.44) * size
        a = rng.uniform(0.0, math.tau)
        items.append((rng.uniform(0.45, 1.0), size * 0.5 + math.cos(a) * r, size * 0.5 + math.sin(a) * r, a + rng.uniform(-0.9, 0.9)))
    for light, x, y, angle in sorted(items):
        _leaf(canvas, rng, x, y, size * rng.uniform(0.06, 0.095), angle, light)
    return canvas


def bough_tile(seed, size):
    """A spruce bough: a twig running up the tile with side twigs, all fringed with needles."""
    rng = random.Random(seed)
    canvas = np.zeros((size, size, 4), dtype=np.float32)

    def twig(ax, ay, bx, by, needles, light):
        length = math.hypot(bx - ax, by - ay)
        direction = math.atan2(by - ay, bx - ax)
        for index in range(needles):
            t = (index + rng.random()) / needles
            px, py = ax + (bx - ax) * t, ay + (by - ay) * t
            for side in (-1, 1):
                a = direction + side * rng.uniform(0.6, 1.0)
                reach = size * rng.uniform(0.028, 0.045) * (1.0 - 0.4 * t)
                _stroke(canvas, px, py, px + math.cos(a) * reach, py + math.sin(a) * reach, size * 0.006, light * rng.uniform(0.7, 1.0))
        _stroke(canvas, ax, ay, bx, by, size * 0.006, 0.35)
        return length
    spine_x = size * 0.5
    for index in range(13):
        t = index / 13
        y = size * (0.97 - 0.88 * t)
        reach = size * 0.4 * (1.0 - t * 0.75) * rng.uniform(0.8, 1.0)
        for side in (-1, 1):
            twig(spine_x, y, spine_x + side * reach, y - reach * rng.uniform(0.25, 0.5), int(8 + 14 * (1 - t)), rng.uniform(0.6, 1.0))
    twig(spine_x, size * 0.98, spine_x, size * 0.05, 40, 0.9)
    return canvas


def build_leaf_atlas():
    """Four 512 px tiles: 0 and 1 full leaf sprays, 2 a spruce bough, 3 a thin leaf spray. R is light, A the cut-out."""
    size = 512
    tiles = [leaf_tile(301, size, 300, 0.2), leaf_tile(302, size, 240, 0.22), bough_tile(303, size), leaf_tile(304, size, 130, 0.24)]
    atlas = np.zeros((size * 2, size * 2, 4), dtype=np.float32)
    for index, tile in enumerate(tiles):
        row, column = index // 2, index % 2
        atlas[row * size:(row + 1) * size, column * size:(column + 1) * size] = tile
    # Colour under the cut-out stays the leaf's own light, so no dark fringe shows when the texture is shrunk.
    atlas[..., 0] = np.where(atlas[..., 3] > 0.0, atlas[..., 0], 0.6)
    atlas[..., 1] = atlas[..., 0]
    atlas[..., 2] = atlas[..., 0]
    image = bpy.data.images.new("leaf_atlas", size * 2, size * 2, alpha=True)
    image.colorspace_settings.name = "Non-Color"
    # Blender's rows run bottom to top.
    image.pixels.foreach_set(atlas[::-1].ravel())
    image.filepath_raw = ATLAS
    image.file_format = "PNG"
    image.save()


def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    kit = bpy.data.collections.new("landscape_kit")
    bpy.context.scene.collection.children.link(kit)


def bake_shading():
    """Ambient shading into the vertex colours, each piece standing alone on the ground."""
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 48
    world = bpy.data.worlds.new("bake")
    scene.world = world
    world.light_settings.distance = 2.5
    bpy.ops.mesh.primitive_plane_add(size=400.0, location=(0.0, 0.0, -0.02))
    floor = bpy.context.active_object
    floor.name = "bake_floor"
    material = bpy.data.materials.new("kit_bake")
    for obj, kind, _ in pieces:
        mesh = obj.data
        mesh.materials.append(material)
        ao = mesh.color_attributes.new("ao", "FLOAT_COLOR", "POINT")
        mesh.color_attributes.active_color = ao
        for other, _, _ in pieces:
            other.hide_render = other is not obj
        bpy.ops.object.select_all(action="DESELECT")
        obj.select_set(True)
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.bake(type="AO", target="VERTEX_COLORS")
        # Read both before adding the result: adding an attribute invalidates the others' handles.
        ao_values = [item.color[0] for item in mesh.color_attributes["ao"].data]
        base_values = [tuple(item.color) for item in mesh.attributes["base"].data]
        final = mesh.color_attributes.new("Col", "FLOAT_COLOR", "POINT")
        floor_share = 0.45 if kind == ROCK else 0.18
        for index in range(len(mesh.vertices)):
            shading = 1.0 if kind in (BLADES, LEAVES) else lerp(floor_share, 1.0, min(1.0, ao_values[index] * 1.25) ** 1.4)
            b = base_values[index]
            final.data[index].color = (b[0] * shading, b[1] * shading, b[2] * shading, 1.0)
        mesh.color_attributes.remove(mesh.color_attributes["ao"])
        mesh.color_attributes.active_color = mesh.color_attributes["Col"]
        mesh.color_attributes.render_color_index = mesh.color_attributes.find("Col")
    for obj, _, _ in pieces:
        obj.hide_render = False
    bpy.data.objects.remove(floor)


def export():
    os.makedirs(MODELS, exist_ok=True)
    os.makedirs(SCENES, exist_ok=True)
    report = []
    names = {obj.name for obj, _, _ in pieces}
    for obj, kind, shadows in pieces:
        bpy.ops.object.select_all(action="DESELECT")
        obj.select_set(True)
        bpy.context.view_layer.objects.active = obj
        place = obj.location.copy()
        obj.location = (0.0, 0.0, 0.0)
        bpy.ops.wm.obj_export(filepath=os.path.join(MODELS, obj.name + ".obj"), export_selected_objects=True, export_materials=False, export_colors=True, export_uv=True, export_normals=True, export_triangulated_mesh=True, forward_axis="NEGATIVE_Z", up_axis="Y")
        obj.location = place
        report.append("%-22s %5d triangles" % (obj.name, len(obj.data.polygons)))
        if kind == LEAVES:
            continue
        resources = ['[ext_resource type="Mesh" path="res://assets/models/terrain/kit/%s.obj" id="mesh"]' % obj.name, '[ext_resource type="Material" path="res://assets/materials/terrain/landscape_%s.tres" id="material"]' % (ROCK if kind == ROCK else FOLIAGE)]
        nodes = ['[node name="%s" type="Node3D"]' % "".join(part.capitalize() for part in obj.name.split("_")), '[node name="Mesh" type="MeshInstance3D" parent="."]', 'material_override = ExtResource("material")']
        if not shadows:
            nodes.append("cast_shadow = 0")
        nodes.append('mesh = ExtResource("mesh")')
        if obj.name + "_leaves" in names:
            resources += ['[ext_resource type="Mesh" path="res://assets/models/terrain/kit/%s_leaves.obj" id="leaves"]' % obj.name, '[ext_resource type="Material" path="res://assets/materials/terrain/landscape_leaves.tres" id="leaf_material"]']
            nodes += ['[node name="Leaves" type="MeshInstance3D" parent="."]', 'material_override = ExtResource("leaf_material")', 'mesh = ExtResource("leaves")']
        with open(os.path.join(SCENES, obj.name + ".tscn"), "w", newline="\n") as handle:
            handle.write("\n".join(["[gd_scene format=3]"] + resources + nodes) + "\n")
    print("\n".join(report))


def contact_sheet():
    """Lays the kit out in rows and renders it with the vertex colours, for review."""
    scene = bpy.context.scene
    x = 0.0
    z_row = 0.0
    for obj, kind, _ in pieces:
        width = max(obj.dimensions.x, 1.0) + 1.0
        if x + width > 44.0:
            x = 0.0
            z_row -= 9.0
        obj.location = (x + width * 0.5, z_row, 0.0)
        x += width
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.display.shading.light = "STUDIO"
    scene.display.shading.color_type = "VERTEX"
    scene.display.shading.show_shadows = True
    scene.display.shading.show_cavity = True
    scene.display.shadow_shift = 0.2
    scene.render.resolution_x = 2200
    scene.render.resolution_y = 1300
    scene.render.film_transparent = False
    scene.world.color = (0.2, 0.22, 0.2)
    camera_data = bpy.data.cameras.new("kit_camera")
    camera_data.type = "ORTHO"
    camera_data.ortho_scale = 46.0
    camera = bpy.data.objects.new("kit_camera", camera_data)
    scene.collection.objects.link(camera)
    centre = Vector((22.0, z_row * 0.5, 2.0))
    camera.rotation_euler = (math.radians(50.0), 0.0, 0.0)
    camera.location = centre + Vector((0.0, -60.0 * math.sin(math.radians(50.0)), 60.0 * math.cos(math.radians(50.0))))
    scene.camera = camera
    os.makedirs(PREVIEWS, exist_ok=True)
    scene.render.filepath = os.path.join(PREVIEWS, "kit_sheet.png")
    bpy.ops.render.render(write_still=True)


def main():
    reset_scene()
    build_leaf_atlas()
    # All 4.5 m tall: scripts/tools/landscape_baker.gd stretches them to the wall they stand in.
    cliff("cliff_01", 11, 5.0, 4.5, 5)
    cliff("cliff_02", 12, 4.0, 4.5, 4)
    cliff("cliff_03", 13, 6.0, 4.5, 6)
    boulder("boulder_01", 21, (1.3, 1.0, 1.0))
    boulder("boulder_02", 22, (1.7, 1.2, 0.9), lumps=3)
    boulder("boulder_03", 23, (0.9, 0.8, 1.3), lumps=1)
    stones("stones_01", 31, 5, 0.7, 0.24)
    stones("stones_02", 32, 3, 0.45, 0.3)
    stones("stones_03", 33, 7, 1.0, 0.18)
    shore_rock("shore_rock_01", 41, (1.0, 0.8, 0.5))
    shore_rock("shore_rock_02", 42, (0.7, 0.6, 0.45))
    spruce("conifer_01", 51, 9.0, 1.45, 9)
    spruce("conifer_02", 52, 7.8, 1.3, 8)
    spruce("conifer_03", 53, 6.0, 1.1, 6)
    old_tree("broadleaf_01", 61, 7.4, 1.6, 4)
    old_tree("broadleaf_02", 62, 6.4, 1.4, 3)
    old_tree("broadleaf_03", 63, 7.8, 1.5, 4)
    fallen_log("log_01", 64, 2.4, 0.2)
    mossy_rock("mossy_rock_01", 65, (0.55, 0.45, 0.4))
    ore_outcrop("ore_01", 121, (1.3, 1.3, 1.2), 4)
    ore_outcrop("ore_02", 122, (1.1, 1.1, 1.6), 3)
    ore_outcrop("ore_03", 123, (1.5, 1.2, 0.9), 5)
    bush("bush_01", 71, 3, 0.55, (0.03, 0.075, 0.012), (0.15, 0.24, 0.035))
    bush("bush_02", 72, 2, 0.42, (0.035, 0.08, 0.012), (0.17, 0.25, 0.035))
    fern("fern_01", 81, 9, 1.5)
    fern("fern_02", 82, 7, 1.2)
    tuft("tuft_01", 91, 9, 0.42, 0.14, (0.04, 0.11, 0.02), (0.24, 0.4, 0.08))
    tuft("tuft_02", 92, 6, 0.3, 0.1, (0.04, 0.11, 0.02), (0.2, 0.36, 0.07))
    tuft("flower_01", 93, 5, 0.3, 0.16, (0.04, 0.11, 0.02), (0.2, 0.36, 0.07), flowers=((0.9, 0.72, 0.1), 5))
    tuft("flower_02", 94, 5, 0.3, 0.16, (0.04, 0.11, 0.02), (0.2, 0.36, 0.07), flowers=((0.85, 0.85, 0.8), 6))
    tuft("flower_03", 95, 5, 0.34, 0.16, (0.04, 0.11, 0.02), (0.2, 0.36, 0.07), flowers=((0.45, 0.2, 0.6), 5))
    tuft("tall_grass_01", 98, 15, 0.8, 0.34, (0.03, 0.09, 0.02), (0.24, 0.36, 0.1), lean=0.3, width=0.09, segments=2)
    tuft("tall_grass_02", 99, 11, 0.62, 0.3, (0.03, 0.09, 0.02), (0.2, 0.33, 0.08), lean=0.4, width=0.09, segments=2)
    tuft("dry_tuft_01", 96, 8, 0.36, 0.12, (0.2, 0.15, 0.06), (0.62, 0.5, 0.22))
    tuft("dry_tuft_02", 97, 5, 0.26, 0.09, (0.2, 0.15, 0.06), (0.55, 0.46, 0.2))
    dry_bush("dry_bush_01", 101, 16, 0.6)
    dry_bush("dry_bush_02", 102, 11, 0.45)
    reeds("reeds_01", 111, 9, 1.3)
    reeds("reeds_02", 112, 6, 1.0)
    bake_shading()
    export()
    contact_sheet()
    for attribute in ("soft_normal", "tex"):
        for obj, _, _ in pieces:
            if obj.data.attributes.get(attribute):
                obj.data.attributes.remove(obj.data.attributes[attribute])
    bpy.ops.wm.save_as_mainfile(filepath=BLEND)
    print("LANDSCAPE_KIT_BUILT %d pieces" % len(pieces))


main()
