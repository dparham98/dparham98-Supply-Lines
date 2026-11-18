"""Articulated maglev shoes and recessed drawheads in Blender metres, forward -Y."""
from math import cos, pi, sin

import bpy
from mathutils import Vector


class PartMesh:
    """Keep editable closed armor sections and painted faces in one mesh per moving part."""
    def __init__(self):
        self.vertices = []
        self.faces = []
        self.materials = []

    def sections(self, rings, skin, cap):
        start = len(self.vertices)
        n = len(rings[0])
        points = [tuple(p) for ring in rings for p in ring]
        self.vertices.extend(points)
        centre = sum((Vector(p) for p in points), Vector()) / len(points)

        def face(indices, material):
            pts = [Vector(points[i]) for i in indices]
            normal = (pts[1] - pts[0]).cross(pts[2] - pts[0])
            mid = sum(pts, Vector()) / len(pts)
            if normal.dot(mid-centre) < 0:
                indices = list(reversed(indices))
            self.faces.append(tuple(start+i for i in indices))
            self.materials.append(material)

        face(list(range(n)), cap)
        for k in range(len(rings)-1):
            offset = k*n
            for i in range(n):
                j = (i+1) % n
                face([offset+i, offset+j, offset+n+j, offset+n+i],
                     skin if isinstance(skin, str) else skin[i])
        face(list(range((len(rings)-1)*n, len(rings)*n)), cap)

    def side_patch(self, side, x, yz, material):
        points = [(side*x, y, z) for y, z in yz]
        v = [Vector(p) for p in points[:3]]
        if (v[1]-v[0]).cross(v[2]-v[0]).x*side < 0:
            points.reverse()
        start = len(self.vertices)
        self.vertices.extend(points)
        self.faces.append(tuple(range(start, start+len(points))))
        self.materials.append(material)

    def mesh(self, name):
        mesh = bpy.data.meshes.new(name)
        mesh.from_pydata(self.vertices, [], self.faces)
        material_names = list(dict.fromkeys(self.materials))
        for mat in material_names:
            mesh.materials.append(bpy.data.materials[mat])
        for polygon, material in zip(mesh.polygons, self.materials):
            polygon.material_index = material_names.index(material)
        mesh.update()
        return mesh


def octagonal_section(x, z, w, h, bevel):
    """Clockwise eight-cornered transverse section in X,Z; sizes are half-extents."""
    return [(x+u, z+v) for u, v in
            ((-w+bevel,-h),(w-bevel,-h),(w,-h+bevel),(w,h-bevel),
             (w-bevel,h),(-w+bevel,h),(-w,h-bevel),(-w,-h+bevel))]


def beam(part, x, z, y0, y1, width, height, bevel, material, end=None):
    profile = octagonal_section(x, z, width/2, height/2, bevel)
    part.sections([[(px, y, pz) for px, pz in profile] for y in (y0, y1)],
                  material, end or material)


def build_sled_mesh():
    p = PartMesh()
    for side in (-1, 1):
        # Full-length induction shoe. The lower edge steps under the rail lip, the end caps
        # pull inward on both axes, and the dark recessed sidewall carries the field strip.
        profile = [(0.70,-0.32), (1.04,-0.32), (1.153,-0.218), (1.153,-0.078),
                   (1.172,-0.052), (1.172,0.040), (1.064,0.088), (0.700,0.088),
                   (0.593,0.045), (0.593,-0.194)]
        stations = [(-1.4, .55), (-1.28, .81), (-1.07, 1), (1.07, 1), (1.28, .81), (1.4, .55)]
        rings = [[(side*(.882+(x-.882)*s), y, -.02+(z+.02)*s) for x,z in profile]
                 for y,s in stations]
        p.sections(rings, ["underframe","gunmetal","underframe","edge_steel","gunmetal",
                           "gunmetal","gunmetal","underframe","underframe","underframe"],
                   "underframe")
        # Each end has a removable tapered cheek; the central shoe surface stays recessed.
        for end in (-1, 1):
            cheek = [(end*y,z) for y,z in
                     ((.59,-.235),(1.10,-.235),(1.29,-.093),(1.24,.008),
                      (1.04,.089),(.69,.089),(.57,.040))]
            p.sections([[(side*x, y, z) for y,z in cheek] for x in (1.018, 1.19)],
                       "gunmetal", "gunmetal")
            # A painted inspection plate bridges the fastener zone on the outer cheek.
            lamp = [(end*y,z) for y,z in ((.69,-.11),(.97,-.11),(1.04,.082),(.76,.082))]
            p.side_patch(side, 1.191, lamp, "underframe")
            for start in (.701, .805, .909):
                stripe = [(end*y,z) for y,z in ((start,-.098),(start+.054,-.098),
                                                (start+.113,.071),(start+.059,.071))]
                p.side_patch(side, 1.194, stripe, "amber")
        p.side_patch(side, 1.155, [(-.565,-.213),(.494,-.213),(.558,-.120),
                                   (-.494,-.120)], "underframe")
        p.side_patch(side, 1.157, [(-.505,-.197),(.485,-.197),(.520,-.148),
                                   (-.470,-.148)], "field_ceramic")
        # Compact outboard hanger brackets climb around the rail status block.
        # The inductors pass below the power plate while the transfer saddle passes above.
        for y in (-.48, .48):
            beam(p, side*1.155, .051, y-.11, y+.11, .308, .073, .022, "gunmetal")
            beam(p, side*1.276, .163, y-.105, y+.105, .066, .214, .023, "underframe")
    for y in (-.57, .57):
        beam(p, 0, .274, y-.13, y+.13, 2.616, .052, .019, "underframe")
    beam(p, 0, .275, -.62, .62, .52, .050, .017, "underframe")
    # Shallow bearing plate bolts directly to the car keel, leaving the centre open.
    ring = [(0.34*cos(2*pi*i/12), .42*sin(2*pi*i/12)) for i in range(12)]
    p.sections([[(x*s, y*s, z) for x,y in ring] for z,s in ((.247,.83),(.256,1),(.289,1),(.30,.83))],
               "gunmetal", "underframe")
    return p.mesh("Articulated induction truck")


def build_drawhead_mesh():
    # Mesh origin is the original coupling marker. Positive local Y points inboard.
    p = PartMesh()
    beam(p, 0, 0, .22, .75, .27, .16, .045, "underframe")
    beam(p, 0, 0, .345, .43, .38, .24, .055, "gunmetal")
    beam(p, 0, 0, .54, .70, .47, .32, .075, "underframe")
    beam(p, 0, 0, .153, .255, .50, .245, .060, "gunmetal")
    for side in (-1, 1):
        rings = []
        for y, centre, width, height in ((.05,.169,.125,.13),(.10,.164,.161,.23),(.20,.150,.175,.24)):
            rings.append([(x, y, z) for x,z in octagonal_section(side*centre, 0, width/2, height/2, .026)])
        p.sections(rings, "gunmetal", "edge_steel")
    return p.mesh("Recessed drawhead and draft gear")


def build(root):
    collection = root.users_collection[0]
    def child(name, data, parent, location):
        obj = bpy.data.objects.new(name, data)
        collection.objects.link(obj)
        obj.parent = parent
        obj.location = location
        return obj

    sled = build_sled_mesh()
    drawhead = build_drawhead_mesh()
    for label, sign, suffix in (("front",-1,"F"), ("rear",1,"R")):
        child("sled_cargo_" + label, sled, root, (0, sign*3, 1))
        marker = child("cargo_coupler_" + suffix, None, root, (0, sign*5.5, 1.67))
        marker.empty_display_type = "ARROWS"
        marker.empty_display_size = .20
        head = child("drawhead_" + label, drawhead, marker, (0, 0, 0))
        if sign > 0:
            head.rotation_euler.z = pi
