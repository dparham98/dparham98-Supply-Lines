"""Editable faceted castings. Coordinates are across, forward, up in model metres."""
from math import cos, pi, sin

import bmesh
import bpy


def xyz(point):
    x, forward, height = point
    return (x, -forward, height)


class Forms:
    def __init__(self):
        self.points = []
        self.faces = []
        self.materials = []

    def face(self, indices, material):
        self.faces.append(tuple(indices))
        self.materials.append(material)

    def loft(self, rings, side, first=None, last=None):
        """Join equal-sided cross sections. A callable can assign individual panels."""
        count = len(rings[0])
        start = len(self.points)
        for ring in rings:
            assert len(ring) == count
            self.points.extend(xyz(point) for point in ring)
        if first:
            self.face(reversed(range(start, start + count)), first)
        for row in range(len(rings) - 1):
            for edge in range(count):
                next_edge = (edge + 1) % count
                lo = start + row * count
                hi = lo + count
                mat = side(row, edge) if callable(side) else side
                self.face((lo + edge, lo + next_edge, hi + next_edge, hi + edge), mat)
        end = start + (len(rings) - 1) * count
        if last:
            self.face(range(end, end + count), last)
        return end

    def tier(self, sections, material, top=None):
        rings = [plan(*section) for section in sections]
        self.loft(rings, material, material, top or material)

    def finish(self, name, parent, collection, palette, position=(0, 0, 0)):
        mesh = bpy.data.meshes.new(name)
        mesh.from_pydata(self.points, [], self.faces)
        keys = list(dict.fromkeys(self.materials))
        for key in keys:
            mesh.materials.append(palette[key])
        for poly, key in zip(mesh.polygons, self.materials, strict=True):
            poly.material_index = keys.index(key)
        editable = bmesh.new()
        editable.from_mesh(mesh)
        bmesh.ops.recalc_face_normals(editable, faces=list(editable.faces))
        editable.to_mesh(mesh)
        editable.free()
        mesh.update()
        obj = bpy.data.objects.new(name, mesh)
        collection.objects.link(obj)
        obj.parent = parent
        obj.location = xyz(position)
        return obj


def plan(x0, x1, rear, front, z, cx, cf):
    """Clipped rectangle in a horizontal plane, travelling around its eight corners."""
    return [(x0+cx,rear,z), (x1-cx,rear,z), (x1,rear+cf,z), (x1,front-cf,z),
            (x1-cx,front,z), (x0+cx,front,z), (x0,front-cf,z), (x0,rear+cf,z)]


def front_section(x, f, z, w, h, cx, cz):
    return [(x-w+cx,f,z-h), (x+w-cx,f,z-h), (x+w,f,z-h+cz), (x+w,f,z+h-cz),
            (x+w-cx,f,z+h), (x-w+cx,f,z+h), (x-w,f,z+h-cz), (x-w,f,z-h+cz)]


def round_section(axis, position, centre, radius, count):
    a, b = centre
    outline = [(a + radius*cos(2*pi*i/count), b + radius*sin(2*pi*i/count))
               for i in range(count)]
    if axis == 'f':
        return [(x, position, z) for x, z in outline]
    if axis == 'x':
        return [(position, f, z) for f, z in outline]
    return [(x, f, position) for x, f in outline]


def finish_palette():
    choices = {
        'armor': ('Bastion | graphite enamel', (.033,.032,.030), .19,.74),
        'edge': ('Bastion | iron edge', (.054,.054,.051), .35,.62),
        'skirt': ('Bastion | lower armor', (.023,.024,.023), .17,.79),
        'rubber': ('Bastion | rubber and gaskets', (.016,.018,.019), .04,.84),
        'gun': ('Bastion | barrel graphite', (.048,.049,.048), .42,.61),
        'steel': ('Bastion | service steel', (.202,.197,.184), .52,.55),
        'shade': ('Bastion | recessed steel', (.028,.031,.032), .36,.66),
        'bore': ('Bastion | cavity', (.007,.008,.009), .03,.92),
        'team': ('team_color', (.285,.030,.020), .08,.72),
        'optic': ('Bastion | vermilion optical glass', (.68,.025,.003), .08,.30),
        'lamp': ('Bastion | warm headlamp glass', (.84,.76,.59), .06,.35),
    }
    result = {}
    for key, (name, color, metal, roughness) in choices.items():
        mat = bpy.data.materials.new(name)
        mat.diffuse_color = (*color, 1)
        mat.use_nodes = True
        shader = mat.node_tree.nodes.get('Principled BSDF')
        shader.inputs['Base Color'].default_value = (*color, 1)
        shader.inputs['Metallic'].default_value = metal
        shader.inputs['Roughness'].default_value = roughness
        if key in ('optic', 'lamp'):
            shader.inputs['Emission Color'].default_value = (*color, 1)
            shader.inputs['Emission Strength'].default_value = .42 if key == 'optic' else .62
        result[key] = mat
    return result
