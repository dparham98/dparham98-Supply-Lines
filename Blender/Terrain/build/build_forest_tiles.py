"""Builds the painted forest tiles: 2 x 2 m patches of fused, vertex-coloured trees.

Run from the repository root:
  blender --background --python Blender/Terrain/build/build_forest_tiles.py -- [--textured trees_color.glb] [--plain trees.glb]

forest_tile_05 comes from a textured Hunyuan3D tile and forest_tile_06 from an untextured one. Those two source files
are too large to keep in the repository, so without the arguments both tiles are taken as they were last saved in
Blender/Terrain/ForestTiles.blend. forest_tile_07 onward are scripted here in the same manner: simple painted shapes
fused into one skin and reduced, which is what gives every tile the same chunky cut.

Writes Blender/Terrain/ForestTiles.blend, assets/models/terrain/forest_tile_NN.obj, scenes/terrain/forest_tile_NN.tscn
and Blender/Previews/Terrain/forest_tiles_sheet.png. Colours are painted on the vertices; there is no texture.
"""
import math
import os
import random
import sys

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree

ROOT = os.getcwd()
BLEND = os.path.join(ROOT, "Blender", "Terrain", "ForestTiles.blend")
MODELS = os.path.join(ROOT, "assets", "models", "terrain")
SCENES = os.path.join(ROOT, "scenes", "terrain")
PREVIEW = os.path.join(ROOT, "Blender", "Previews", "Terrain", "forest_tiles_sheet.png")

# The tallest tree of a tile, in metres. A patch stands for 2 x 2 m of forest and overlaps its neighbours.
TILE_HEIGHT = 3.7
VOXEL = 0.03


def srgb(r, g, b):
    return tuple(((c / 255.0 + 0.055) / 1.055) ** 2.4 if c > 10 else c / 255.0 / 12.92 for c in (r, g, b))


def to_linear(values):
    return np.where(values > 0.04045, ((values + 0.055) / 1.055) ** 2.4, values / 12.92)


# Read off the textured tile, so scripted trees sit in the same palette.
NEEDLE_DEEP = srgb(38, 74, 34)
NEEDLE = srgb(62, 104, 44)
NEEDLE_LIGHT = srgb(104, 140, 58)
TIP = srgb(176, 178, 76)
LEAF_DEEP = srgb(52, 88, 30)
LEAF = srgb(86, 128, 42)
LEAF_LIGHT = srgb(140, 166, 60)
BIRCH_LEAF = srgb(128, 160, 58)
BIRCH_LIGHT = srgb(186, 190, 84)
BARK = srgb(92, 74, 56)
BARK_DARK = srgb(58, 46, 36)
BIRCH_BARK = srgb(206, 202, 186)
ROCK = srgb(138, 138, 124)
ROCK_DARK = srgb(92, 94, 86)
MOSS = srgb(110, 132, 52)
BRUSH = srgb(142, 160, 52)
BRUSH_LIGHT = srgb(196, 196, 82)
DEAD = srgb(120, 108, 92)


def mix(a, b, t):
    t = max(0.0, min(1.0, t))
    return tuple(a[i] + (b[i] - a[i]) * t for i in range(3))


def args():
    values = {}
    rest = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    for index, item in enumerate(rest):
        if item.startswith("--") and index + 1 < len(rest):
            values[item[2:]] = rest[index + 1]
    return values


# ---------------------------------------------------------------- shared steps

def new_object(name, mesh):
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    return obj


def activate(obj):
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj


def face_colours(mesh, attribute):
    """One colour for each face of a painted mesh, for carrying paint over to another mesh."""
    data = mesh.color_attributes[attribute]
    values = np.empty(len(data.data) * 4, dtype=np.float32)
    data.data.foreach_get("color", values)
    values = values.reshape(-1, 4)[:, :3]
    starts = np.empty(len(mesh.polygons), dtype=np.int64)
    totals = np.empty(len(mesh.polygons), dtype=np.int64)
    mesh.polygons.foreach_get("loop_start", starts)
    mesh.polygons.foreach_get("loop_total", totals)
    if data.domain == "POINT":
        loop_vertices = np.empty(len(mesh.loops), dtype=np.int64)
        mesh.loops.foreach_get("vertex_index", loop_vertices)
        values = values[loop_vertices]
    sums = np.add.reduceat(values, starts, axis=0)
    return sums / totals[:, None]


def tree_of(mesh):
    return BVHTree.FromPolygons([v.co.copy() for v in mesh.vertices], [tuple(p.vertices) for p in mesh.polygons])


def fuse(source, name, triangles, voxel=VOXEL):
    """One closed skin around everything in the source, reduced to a triangle count and painted from it."""
    paint = face_colours(source.data, "Col")
    lookup = tree_of(source.data)
    low = new_object(name, source.data.copy())
    low.matrix_world = source.matrix_world
    activate(low)
    modifier = low.modifiers.new("fuse", "REMESH")
    modifier.mode = "VOXEL"
    modifier.voxel_size = voxel
    modifier.adaptivity = 0.0
    bpy.ops.object.modifier_apply(modifier=modifier.name)
    drop_floaters(low.data, 0.004)
    count = sum(len(p.vertices) - 2 for p in low.data.polygons)
    modifier = low.modifiers.new("reduce", "DECIMATE")
    modifier.ratio = min(1.0, triangles / max(1, count))
    bpy.ops.object.modifier_apply(modifier=modifier.name)
    mesh = low.data
    for attribute in list(mesh.color_attributes):
        mesh.color_attributes.remove(attribute)
    colours = []
    for vertex in mesh.vertices:
        hit = lookup.find_nearest(vertex.co)
        colours.extend(tuple(paint[hit[2]]) + (1.0,) if hit[2] is not None else (1.0, 0.0, 1.0, 1.0))
    mesh.color_attributes.new("Col", "FLOAT_COLOR", "POINT").data.foreach_set("color", colours)
    return low


def drop_floaters(mesh, share):
    """Removes loose pieces smaller than a share of the whole: specks the generator and the fusing leave behind."""
    bm = bmesh.new()
    bm.from_mesh(mesh)
    bm.verts.ensure_lookup_table()
    seen = set()
    doomed = []
    least = len(bm.verts) * share
    for start in bm.verts:
        if start.index in seen:
            continue
        island = [start]
        seen.add(start.index)
        cursor = 0
        while cursor < len(island):
            for edge in island[cursor].link_edges:
                other = edge.other_vert(island[cursor])
                if other.index not in seen:
                    seen.add(other.index)
                    island.append(other)
            cursor += 1
        if len(island) < least:
            doomed.extend(island)
    bmesh.ops.delete(bm, geom=doomed, context="VERTS")
    bm.to_mesh(mesh)
    bm.free()


def settle(obj, height=TILE_HEIGHT):
    """Stands a tile on the origin at its game size, Z up, a little sunk so no trunk floats."""
    mesh = obj.data
    mesh.transform(obj.matrix_world)
    obj.matrix_world = Matrix.Identity(4)
    points = np.empty(len(mesh.vertices) * 3, dtype=np.float32)
    mesh.vertices.foreach_get("co", points)
    points = points.reshape(-1, 3)
    low, high = points.min(axis=0), points.max(axis=0)
    scale = height / (high[2] - low[2])
    foot = points[points[:, 2] < low[2] + (high[2] - low[2]) * 0.25]
    centre = (foot.min(axis=0) + foot.max(axis=0)) * 0.5
    points = (points - (centre[0], centre[1], low[2])) * scale - (0.0, 0.0, 0.04)
    mesh.vertices.foreach_set("co", points.ravel())
    mesh.update()
    for polygon in mesh.polygons:
        polygon.use_smooth = True
    mesh.set_sharp_from_angle(angle=math.radians(48.0))


def bake_shade(objects, floor_share=0.3):
    """Darkens paint where the piece shades itself, for tiles whose colours carry no shading of their own."""
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 32
    world = bpy.data.worlds.new("bake")
    scene.world = world
    world.light_settings.distance = 1.6
    material = bpy.data.materials.new("tile_bake")
    for obj in objects:
        mesh = obj.data
        mesh.materials.clear()
        mesh.materials.append(material)
        base = np.empty(len(mesh.vertices) * 4, dtype=np.float32)
        mesh.color_attributes["Col"].data.foreach_get("color", base)
        ao = mesh.color_attributes.new("ao", "FLOAT_COLOR", "POINT")
        mesh.color_attributes.active_color = ao
        for other in bpy.data.objects:
            other.hide_render = other is not obj
        activate(obj)
        bpy.ops.object.bake(type="AO", target="VERTEX_COLORS")
        shade = np.empty(len(mesh.vertices) * 4, dtype=np.float32)
        mesh.color_attributes["ao"].data.foreach_get("color", shade)
        shade = floor_share + (1.0 - floor_share) * np.minimum(1.0, shade.reshape(-1, 4)[:, :1] * 1.3) ** 1.3
        base = base.reshape(-1, 4)
        base[:, :3] *= shade
        mesh.color_attributes.remove(mesh.color_attributes["ao"])
        mesh.color_attributes["Col"].data.foreach_set("color", base.ravel())
        mesh.color_attributes.active_color = mesh.color_attributes["Col"]
    for other in bpy.data.objects:
        other.hide_render = False


# ---------------------------------------------------------------- generated tiles

def textured_tile(path):
    """The textured tile: stray flat sheets removed, its texture carried over as paint."""
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    obj = next(o for o in bpy.data.objects if o not in before and o.type == "MESH")
    mesh = obj.data
    image = max((i for i in bpy.data.images if i.size[0] > 0), key=lambda i: (i.name == "Image_0", i.size[0]))
    for node in mesh.materials[0].node_tree.nodes:
        if node.type == "BSDF_PRINCIPLED" and node.inputs["Base Color"].links:
            image = node.inputs["Base Color"].links[0].from_node.image or image
    width, height = image.size
    pixels = np.empty(width * height * 4, dtype=np.float32)
    image.pixels.foreach_get(pixels)
    pixels = pixels.reshape(height, width, 4)
    uv = np.empty(len(mesh.loops) * 2, dtype=np.float32)
    mesh.uv_layers[0].data.foreach_get("uv", uv)
    uv = uv.reshape(-1, 2)
    column = np.clip((uv[:, 0] % 1.0) * width, 0, width - 1).astype(np.int32)
    row = np.clip((uv[:, 1] % 1.0) * height, 0, height - 1).astype(np.int32)
    colour = pixels[row, column].copy()
    display = colour[:, :3].copy()
    colour[:, :3] = to_linear(display)
    colour[:, 3] = 1.0
    mesh.color_attributes.new("Col", "FLOAT_COLOR", "CORNER").data.foreach_set("color", colour.ravel())

    # Loose pieces: the generator left large flat sheets of plain green standing among the trees.
    count = len(mesh.vertices)
    points = np.empty(count * 3, dtype=np.float32)
    mesh.vertices.foreach_get("co", points)
    points = points.reshape(-1, 3)
    edges = np.empty(len(mesh.edges) * 2, dtype=np.int64)
    mesh.edges.foreach_get("vertices", edges)
    parent = list(range(count))

    def find(a):
        while parent[a] != a:
            parent[a] = parent[parent[a]]
            a = parent[a]
        return a
    for a, b in edges.reshape(-1, 2).tolist():
        ra, rb = find(a), find(b)
        if ra != rb:
            parent[ra] = rb
    _, label = np.unique(np.array([find(i) for i in range(count)]), return_inverse=True)
    loop_vertices = np.empty(len(mesh.loops), dtype=np.int64)
    mesh.loops.foreach_get("vertex_index", loop_vertices)
    vertex_colour = np.zeros((count, 3))
    hits = np.zeros(count)
    np.add.at(vertex_colour, loop_vertices, display)
    np.add.at(hits, loop_vertices, 1)
    vertex_colour /= np.maximum(hits, 1)[:, None]
    order = np.argsort(label)
    bounds = np.searchsorted(label[order], np.arange(label.max() + 2))
    sheet = np.zeros(label.max() + 1, dtype=bool)
    for part in range(label.max() + 1):
        members = order[bounds[part]:bounds[part + 1]]
        if len(members) < 12:
            continue
        spread = np.sqrt(np.maximum(np.linalg.eigvalsh(np.cov((points[members] - points[members].mean(axis=0)).T.astype(np.float64))), 0.0))
        tone = vertex_colour[members].mean(axis=0)
        if spread[2] > 0.03 and spread[0] / max(spread[1], 1e-9) < 0.16 and tone[2] < 0.075 and tone[1] > 0.3:
            sheet[part] = True
    bm = bmesh.new()
    bm.from_mesh(mesh)
    bm.verts.ensure_lookup_table()
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if sheet[label[v.index]]], context="VERTS")
    bm.to_mesh(mesh)
    bm.free()
    print("textured tile: %d sheets removed, %d triangles left" % (int(sheet.sum()), len(mesh.polygons)))

    size = max(obj.dimensions)
    low = fuse(obj, "forest_tile_05", 12000, voxel=size * 0.0072)
    bpy.data.objects.remove(obj)
    settle(low)
    return low


def plain_tile(path):
    """The untextured tile: already one fused skin, so it is only reduced, then painted by what each part is."""
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    obj = next(o for o in bpy.data.objects if o not in before and o.type == "MESH")
    obj.name = "forest_tile_06"
    obj.data.materials.clear()
    settle(obj, TILE_HEIGHT * 0.95)
    activate(obj)
    # Rebuilt as a clean skin first: the generator's own mesh does not reduce.
    modifier = obj.modifiers.new("fuse", "REMESH")
    modifier.mode = "VOXEL"
    modifier.voxel_size = 0.036
    modifier.adaptivity = 0.0
    bpy.ops.object.modifier_apply(modifier=modifier.name)
    drop_floaters(obj.data, 0.002)
    modifier = obj.modifiers.new("reduce", "DECIMATE")
    modifier.ratio = 13000 / sum(len(p.vertices) - 2 for p in obj.data.polygons)
    bpy.ops.object.modifier_apply(modifier=modifier.name)
    for attribute in list(obj.data.color_attributes):
        obj.data.color_attributes.remove(attribute)
    settle(obj, TILE_HEIGHT * 0.95)
    mesh = obj.data
    lookup = tree_of(mesh)
    count = len(mesh.vertices)
    top = max(v.co.z for v in mesh.vertices)

    # Wood: a wall that runs straight up and down for a good way, and is thin through.
    wood = np.zeros(count)
    for vertex in mesh.vertices:
        normal = vertex.normal
        if abs(normal.z) > 0.4 or vertex.co.z > top * 0.8:
            continue
        straight = all(lookup.find_nearest(vertex.co + Vector((0.0, 0.0, step)))[3] < 0.06 for step in (-0.22, -0.12, 0.12, 0.22))
        if not straight:
            continue
        through = lookup.ray_cast(vertex.co - normal * 0.01, -normal, 0.45)
        if through[0] is not None:
            wood[vertex.index] = 1.0
    neighbours = [[] for _ in range(count)]
    for edge in mesh.edges:
        a, b = edge.vertices
        neighbours[a].append(b)
        neighbours[b].append(a)
    for _ in range(2):
        wood = np.array([0.5 * wood[i] + 0.5 * (sum(wood[j] for j in neighbours[i]) / max(1, len(neighbours[i]))) for i in range(count)])

    rng = random.Random(6)
    colours = []
    for vertex in mesh.vertices:
        around = neighbours[vertex.index]
        centre = sum((mesh.vertices[j].co for j in around), Vector()) / max(1, len(around))
        bulge = (vertex.co - centre).dot(vertex.normal) / 0.11
        height = vertex.co.z / top
        up = vertex.normal.z
        # Boughs: deep underneath, lighter on top, yellow where a tip sticks out.
        leaf = mix(NEEDLE_DEEP, NEEDLE, up * 0.5 + 0.5)
        leaf = mix(leaf, NEEDLE_LIGHT, max(0.0, up) * 0.35 + height * 0.15)
        leaf = mix(leaf, TIP, max(0.0, bulge - 0.6) * 0.6 * (0.4 + height))
        if height < 0.1:
            leaf = mix(mix(MOSS, BRUSH, max(0.0, bulge)), leaf, height / 0.1)
        colour = mix(leaf, mix(BARK_DARK, BARK, rng.random()), min(1.0, wood[vertex.index] * 1.8))
        colours.extend(colour + (1.0,))
    mesh.color_attributes.new("Col", "FLOAT_COLOR", "POINT").data.foreach_set("color", colours)
    print("plain tile: %d triangles, %d wood vertices" % (len(mesh.polygons), int((wood > 0.5).sum())))
    return obj


# ---------------------------------------------------------------- scripted tiles

class Paint:
    """Simple painted shapes, later fused into one skin."""

    def __init__(self, seed):
        self.rng = random.Random(seed)
        self.bm = bmesh.new()
        self.layer = self.bm.verts.layers.float_color.new("Col")

    def tube(self, path, radii, colours, sides=6, flat=None, closed=True):
        """A run of rings. radii are (across, thick) pairs; flat is the direction the thin side faces."""
        rings = []
        for index, point in enumerate(path):
            ahead = (path[min(index + 1, len(path) - 1)] - path[max(index - 1, 0)]).normalized()
            side = ahead.cross(flat if flat is not None else Vector((0.0, 0.0, 1.0)))
            if side.length < 1e-4:
                side = ahead.cross(Vector((1.0, 0.0, 0.0)))
            side.normalize()
            lift = side.cross(ahead).normalized()
            across, thick = radii[index]
            ring = []
            for step in range(sides):
                angle = math.tau * step / sides
                vertex = self.bm.verts.new(point + side * math.cos(angle) * across + lift * math.sin(angle) * thick)
                vertex[self.layer] = tuple(colours[index]) + (1.0,)
                ring.append(vertex)
            rings.append(ring)
        for a, b in zip(rings, rings[1:]):
            for step in range(sides):
                self.bm.faces.new((a[step], a[(step + 1) % sides], b[(step + 1) % sides], b[step]))
        if closed:
            self.bm.faces.new(list(reversed(rings[0])))
            self.bm.faces.new(rings[-1])

    def paddle(self, root, heading, length, width, droop, base, tip, thick=0.045, lobes=2, twist=0.0):
        """A drooping pointed bough or leaf spray, with smaller ones off its sides."""
        rng = self.rng
        heading = Vector((heading.x, heading.y, 0.0)).normalized()
        steps = 5
        path, radii, colours = [], [], []
        for index in range(steps + 1):
            t = index / steps
            path.append(root + heading * length * t + Vector((0.0, 0.0, -droop * length * t * t + twist * length * t)))
            profile = math.sin(math.pi * min(1.0, t * 0.94 + 0.06) ** 0.75)
            radii.append((max(0.012, width * profile), max(0.012, thick * (1.0 - 0.6 * t))))
            colours.append(mix(base, tip, t ** 1.6))
        self.tube(path, radii, colours, sides=6, flat=Vector((0.0, 0.0, 1.0)))
        for lobe in range(lobes):
            t = 0.3 + 0.45 * (lobe // 2 + rng.random() * 0.5) / max(1, lobes // 2)
            start = root + heading * length * t + Vector((0.0, 0.0, -droop * length * t * t + twist * length * t))
            turn = (1 if lobe % 2 else -1) * rng.uniform(0.55, 0.95)
            side = Vector((heading.x * math.cos(turn) - heading.y * math.sin(turn), heading.x * math.sin(turn) + heading.y * math.cos(turn), 0.0))
            self.paddle(start, side, length * rng.uniform(0.34, 0.5), width * 0.6, droop * 1.3, mix(base, tip, t * 0.6), tip, thick * 0.8, lobes=0)

    def trunk(self, foot, height, radius, bark, lean=None, top=0.25, dark=BARK_DARK):
        rng = self.rng
        lean = lean or Vector((rng.uniform(-0.05, 0.05), rng.uniform(-0.05, 0.05), 0.0))
        path, radii, colours = [], [], []
        for index in range(7):
            t = index / 6
            path.append(foot + Vector((lean.x * t * height, lean.y * t * height, height * t - 0.08)))
            flare = 1.0 + 0.35 * max(0.0, 1.0 - t * 7.0)
            r = radius * flare * (1.0 - (1.0 - top) * t)
            radii.append((r, r))
            colours.append(mix(dark, bark, 0.35 + 0.65 * rng.random()))
        self.tube(path, radii, colours, sides=7)
        return path

    def spruce(self, foot, height, girth, tone=0.0):
        rng = self.rng
        path = self.trunk(foot, height * 0.9, height * 0.022, BARK, top=0.25)
        tiers = max(7, int(height * 4.2))
        for tier in range(tiers):
            t = tier / (tiers - 1)
            z = height * (0.2 + 0.68 * t)
            reach = girth * (1.0 - 0.8 * t) * rng.uniform(0.85, 1.1)
            boughs = max(5, int(9 - 4 * t))
            offset = rng.random() * math.tau
            centre = foot + (path[-1] - path[0]) * (z / (height * 0.9)) * Vector((1.0, 1.0, 0.0)) + Vector((0.0, 0.0, z))
            for bough in range(boughs):
                angle = offset + math.tau * bough / boughs + rng.uniform(-0.25, 0.25)
                base = mix(mix(NEEDLE_DEEP, NEEDLE, 0.35 + 0.5 * t + tone), NEEDLE_LIGHT, rng.random() * 0.3)
                tip = mix(NEEDLE_LIGHT, TIP, 0.15 + 0.45 * t * t + rng.random() * 0.15)
                self.paddle(centre + Vector((0.0, 0.0, rng.uniform(-0.05, 0.05))), Vector((math.cos(angle), math.sin(angle), 0.0)), reach, reach * 0.17, rng.uniform(0.55, 0.95), base, tip, thick=0.04, lobes=2 if reach > 0.22 else 0)
        # The leader: a pale spike with a ruff of short shoots, as on the generated spruces.
        crown = foot + Vector((path[-1].x - path[0].x, path[-1].y - path[0].y, height * 0.84))
        self.tube([crown, crown + Vector((0.0, 0.0, height * 0.09)), crown + Vector((0.0, 0.0, height * 0.16))], [(0.05, 0.05), (0.032, 0.032), (0.012, 0.012)], [NEEDLE_LIGHT, TIP, TIP], sides=5)
        for shoot in range(5):
            angle = math.tau * shoot / 5 + rng.random()
            self.paddle(crown + Vector((0.0, 0.0, height * 0.04)), Vector((math.cos(angle), math.sin(angle), 0.0)), girth * 0.2, girth * 0.07, 0.4, NEEDLE_LIGHT, TIP, thick=0.035, lobes=0)

    def spray(self, centre, radius, base, light, count=12, upward=0.45):
        """A clump of pointed leaf sprays about a point: a broadleaf's crown is several of these."""
        rng = self.rng
        for index in range(count):
            angle = math.tau * index / count + rng.uniform(-0.3, 0.3)
            lift = rng.uniform(-0.25, upward)
            self.paddle(centre + Vector((0.0, 0.0, radius * lift * 0.6)), Vector((math.cos(angle), math.sin(angle), 0.0)), radius * rng.uniform(0.75, 1.05), radius * 0.15, rng.uniform(0.25, 0.7), mix(base, light, 0.2 + rng.random() * 0.3 + lift), mix(light, TIP, rng.random() * 0.25), thick=0.045, lobes=2, twist=lift * 0.7)
        self.ball(centre, radius * 0.5, base, squash=0.75, detail=1, light=light)

    def ball(self, centre, radius, colour, squash=1.0, detail=2, light=None, jitter=0.18):
        rng = self.rng
        made = bmesh.ops.create_icosphere(self.bm, subdivisions=detail, radius=radius)
        for vertex in made["verts"]:
            offset = Vector(vertex.co) * (1.0 + rng.uniform(-jitter, jitter))
            up = offset.z / radius
            offset.z *= squash
            vertex.co = centre + offset
            vertex[self.layer] = tuple(mix(colour, light, max(0.0, up)) if light else colour) + (1.0,)

    def broadleaf(self, foot, height, crown, bark=BARK, base=LEAF, light=LEAF_LIGHT, deep=LEAF_DEEP, trunk=0.026, clumps=6):
        rng = self.rng
        path = self.trunk(foot, height * 0.62, height * trunk, bark, top=0.55, dark=mix(bark, BARK_DARK, 0.5))
        fork = path[-1]
        for index in range(clumps):
            angle = math.tau * index / clumps + rng.uniform(-0.4, 0.4)
            out = crown * (0.0 if index == 0 else rng.uniform(0.35, 0.68))
            centre = Vector((fork.x + math.cos(angle) * out, fork.y + math.sin(angle) * out, height * (0.86 if index == 0 else rng.uniform(0.55, 0.78))))
            limb = [fork + Vector((0.0, 0.0, -0.25)), fork.lerp(centre, 0.55) + Vector((0.0, 0.0, 0.04)), centre]
            self.tube(limb, [(max(0.04, height * trunk * 0.6),) * 2, (max(0.035, height * trunk * 0.45),) * 2, (0.03,) * 2], [bark, bark, mix(bark, BARK_DARK, 0.5)], sides=5)
            tone = mix(deep, base, 0.3 + rng.random() * 0.5)
            self.spray(centre, crown * rng.uniform(0.34, 0.44), tone, light)
            self.ball(centre, crown * 0.3, tone, squash=0.8, detail=2, light=mix(tone, light, 0.6), jitter=0.3)
            for extra in range(2):
                turn = rng.random() * math.tau
                self.spray(centre + Vector((math.cos(turn), math.sin(turn), rng.uniform(-0.5, 0.3))) * crown * 0.36, crown * rng.uniform(0.24, 0.32), mix(tone, light, rng.random() * 0.3), light, count=7)

    def birch(self, foot, height, crown):
        self.broadleaf(foot, height, crown, bark=BIRCH_BARK, base=BIRCH_LEAF, light=BIRCH_LIGHT, deep=LEAF, trunk=0.016, clumps=5)

    def snag(self, foot, height):
        rng = self.rng
        path = self.trunk(foot, height, height * 0.045, DEAD, top=0.3, dark=BARK_DARK)
        for index in range(4):
            start = path[2 + index % 4]
            angle = rng.random() * math.tau
            end = start + Vector((math.cos(angle), math.sin(angle), rng.uniform(0.1, 0.5))) * rng.uniform(0.3, 0.6)
            self.tube([start, start.lerp(end, 0.6) + Vector((0.0, 0.0, 0.05)), end], [(0.045, 0.045), (0.03, 0.03), (0.012, 0.012)], [DEAD, DEAD, BARK_DARK], sides=5)

    def rock(self, centre, size):
        rng = self.rng
        self.ball(centre + Vector((0.0, 0.0, size * 0.25)), size, mix(ROCK_DARK, ROCK, rng.random()), squash=rng.uniform(0.55, 0.8), detail=1, light=mix(ROCK, MOSS, rng.random() * 0.8), jitter=0.3)

    def brush(self, centre, size, count=8):
        rng = self.rng
        for index in range(count):
            angle = math.tau * index / count + rng.uniform(-0.4, 0.4)
            self.paddle(centre + Vector((0.0, 0.0, size * 0.1)), Vector((math.cos(angle), math.sin(angle), 0.0)), size * rng.uniform(0.7, 1.1), size * 0.2, rng.uniform(0.5, 0.9), mix(LEAF, BRUSH, rng.random()), mix(BRUSH, BRUSH_LIGHT, rng.random()), thick=0.04, lobes=2 if index % 2 else 0, twist=rng.uniform(0.9, 1.5))
        self.ball(centre + Vector((0.0, 0.0, size * 0.25)), size * 0.45, mix(LEAF_DEEP, BRUSH, 0.4), squash=0.8, detail=1, light=BRUSH)

    def log(self, centre, length, radius, angle):
        along = Vector((math.cos(angle), math.sin(angle), 0.0))
        lift = Vector((0.0, 0.0, radius * 0.8))
        path = [centre - along * length * 0.5 + lift, centre + lift * 1.1, centre + along * length * 0.5 + lift]
        self.tube(path, [(radius, radius), (radius * 0.95, radius * 0.95), (radius * 0.8, radius * 0.8)], [BARK, mix(BARK, MOSS, 0.6), BARK_DARK], sides=7)

    def finish(self, name, triangles):
        mesh = bpy.data.meshes.new(name + "_paint")
        bmesh.ops.triangulate(self.bm, faces=self.bm.faces[:])
        self.bm.to_mesh(mesh)
        self.bm.free()
        source = new_object(name + "_paint", mesh)
        low = fuse(source, name, triangles)
        bpy.data.objects.remove(source)
        bpy.data.meshes.remove(mesh)
        settle(low, max(v.co.z for v in low.data.vertices) + 0.04)
        return low


def ring(rng, count, radius, jitter=0.22):
    start = rng.random() * math.tau
    return [Vector((math.cos(start + math.tau * i / count) * radius + rng.uniform(-jitter, jitter), math.sin(start + math.tau * i / count) * radius + rng.uniform(-jitter, jitter), 0.0)) for i in range(count)]


def mixed_stand():
    """Spruce over beech, with brush between: the ordinary wood."""
    paint = Paint(71)
    rng = paint.rng
    spots = ring(rng, 6, 0.95)
    paint.spruce(spots[0], 3.6, 0.72)
    paint.broadleaf(spots[1], 2.9, 0.78)
    paint.spruce(spots[2], 3.0, 0.62, tone=0.1)
    paint.broadleaf(spots[3], 2.6, 0.7)
    paint.spruce(spots[4], 2.3, 0.5)
    paint.birch(spots[5], 2.8, 0.55)
    paint.spruce(Vector((0.1, -0.05, 0.0)), 3.3, 0.66, tone=-0.05)
    for spot in ring(rng, 7, 1.15, 0.3):
        paint.brush(spot, rng.uniform(0.2, 0.3))
    paint.rock(Vector((0.45, 0.35, 0.0)), 0.2)
    paint.rock(Vector((-0.55, -0.3, 0.0)), 0.15)
    return paint.finish("forest_tile_07", 13000)


def beech_grove():
    """Broadleaves and birch with a light floor: the brighter wood."""
    paint = Paint(83)
    rng = paint.rng
    spots = ring(rng, 5, 0.9)
    paint.broadleaf(spots[0], 3.3, 0.9, clumps=7)
    paint.birch(spots[1], 3.0, 0.6)
    paint.broadleaf(spots[2], 2.8, 0.8)
    paint.birch(spots[3], 2.5, 0.5)
    paint.broadleaf(spots[4], 3.0, 0.82)
    paint.broadleaf(Vector((0.0, 0.1, 0.0)), 3.5, 0.85, clumps=7)
    for spot in ring(rng, 8, 1.1, 0.35):
        paint.brush(spot, rng.uniform(0.2, 0.32))
    paint.rock(Vector((0.3, -0.6, 0.0)), 0.18)
    paint.log(Vector((-0.5, 0.45, 0.0)), 0.8, 0.07, 0.6)
    return paint.finish("forest_tile_08", 13000)


def old_spruce():
    """Few, tall spruces around a snag, a fallen trunk and boulders: the old wood."""
    paint = Paint(97)
    rng = paint.rng
    spots = ring(rng, 5, 0.92)
    paint.spruce(spots[0], 3.7, 0.8)
    paint.spruce(spots[1], 3.2, 0.7, tone=0.1)
    paint.snag(spots[2], 2.2)
    paint.spruce(spots[3], 3.5, 0.74, tone=-0.08)
    paint.spruce(spots[4], 2.0, 0.48, tone=0.12)
    paint.spruce(Vector((0.05, 0.0, 0.0)), 2.7, 0.6)
    paint.rock(Vector((0.4, -0.35, 0.0)), 0.3)
    paint.rock(Vector((0.62, -0.1, 0.0)), 0.17)
    paint.rock(Vector((-0.5, 0.5, 0.0)), 0.2)
    paint.log(Vector((-0.3, -0.55, 0.0)), 1.0, 0.08, 2.4)
    for spot in ring(rng, 6, 1.15, 0.3):
        paint.brush(spot, rng.uniform(0.18, 0.28))
    return paint.finish("forest_tile_09", 13000)


# ---------------------------------------------------------------- output

def export(tiles):
    os.makedirs(MODELS, exist_ok=True)
    for obj in tiles:
        activate(obj)
        obj.data.materials.clear()
        obj.data.color_attributes.active_color = obj.data.color_attributes["Col"]
        obj.data.color_attributes.render_color_index = obj.data.color_attributes.find("Col")
        bpy.ops.wm.obj_export(filepath=os.path.join(MODELS, obj.name + ".obj"), export_selected_objects=True, export_materials=False, export_colors=True, export_uv=False, export_normals=True, export_triangulated_mesh=True, forward_axis="NEGATIVE_Z", up_axis="Y")
        number = obj.name.rsplit("_", 1)[1]
        with open(os.path.join(SCENES, obj.name + ".tscn"), "w", newline="\n") as handle:
            handle.write("\n".join([
                "[gd_scene format=3]",
                '[ext_resource type="Mesh" path="res://assets/models/terrain/%s.obj" id="mesh"]' % obj.name,
                '[ext_resource type="Material" path="res://assets/materials/terrain/forest_tile_painted.tres" id="material"]',
                '[node name="ForestTile%s" type="Node3D"]' % number,
                '[node name="Trees" type="MeshInstance3D" parent="."]',
                'material_override = ExtResource("material")',
                'mesh = ExtResource("mesh")']) + "\n")
        size = obj.dimensions
        print("%s %6d triangles  %.2f x %.2f x %.2f m" % (obj.name, len(obj.data.polygons), size.x, size.y, size.z))


def contact_sheet(tiles):
    scene = bpy.context.scene
    for index, obj in enumerate(tiles):
        obj.location = ((index - (len(tiles) - 1) * 0.5) * 3.9, 0.0, 0.0)
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.display.shading.light = "STUDIO"
    scene.display.shading.color_type = "VERTEX"
    scene.display.shading.show_shadows = True
    scene.display.shading.shadow_intensity = 0.35
    scene.display.shading.show_cavity = True
    scene.view_settings.view_transform = "Standard"
    scene.render.resolution_x = 2600
    scene.render.resolution_y = 760
    scene.render.film_transparent = False
    scene.world = bpy.data.worlds.new("sheet")
    scene.world.color = (0.16, 0.17, 0.15)
    camera = bpy.data.objects.new("sheet_camera", bpy.data.cameras.new("sheet_camera"))
    scene.collection.objects.link(camera)
    scene.camera = camera
    camera.data.type = "ORTHO"
    camera.data.ortho_scale = len(tiles) * 3.9 + 0.6
    # The game's view: looking down at 50 degrees.
    pitch = math.radians(50.0)
    camera.location = (0.0, -40.0 * math.cos(pitch), 1.6 + 40.0 * math.sin(pitch))
    camera.rotation_euler = (math.radians(90.0) - pitch, 0.0, 0.0)
    scene.render.filepath = PREVIEW
    bpy.ops.render.render(write_still=True)
    for obj in tiles:
        obj.location = (0.0, 0.0, 0.0)
    bpy.data.objects.remove(camera)


def kept(name):
    """A generated tile as it was last saved, for runs without its source file."""
    if not os.path.exists(BLEND):
        return None
    with bpy.data.libraries.load(BLEND) as (source, target):
        if name not in source.objects:
            return None
        target.objects = [name]
    obj = target.objects[0]
    bpy.context.scene.collection.objects.link(obj)
    obj.location = (0.0, 0.0, 0.0)
    return obj


def main():
    options = args()
    bpy.ops.wm.read_factory_settings(use_empty=True)
    only = options.get("only", "")
    tiles = []
    textured = textured_tile(options["textured"]) if "textured" in options else kept("forest_tile_05")
    plain = plain_tile(options["plain"]) if "plain" in options else kept("forest_tile_06")
    scripted = [build() for build in (mixed_stand, beech_grove, old_spruce)]
    to_shade = scripted + ([plain] if plain is not None and "plain" in options else [])
    bake_shade(to_shade)
    tiles = [tile for tile in [textured, plain] + scripted if tile is not None]
    for image in list(bpy.data.images):
        bpy.data.images.remove(image)
    for material in list(bpy.data.materials):
        bpy.data.materials.remove(material)
    export(tiles)
    contact_sheet(tiles)
    for index, obj in enumerate(tiles):
        obj.location = ((index - (len(tiles) - 1) * 0.5) * 3.9, 0.0, 0.0)
    bpy.ops.outliner.orphans_purge(do_local_ids=True, do_linked_ids=True, do_recursive=True)
    bpy.ops.wm.save_as_mainfile(filepath=BLEND, compress=True)
    if os.path.exists(BLEND + "1"):
        os.remove(BLEND + "1")
    print("FOREST_TILES_BUILT")


main()
