"""Build the single powered streamliner. Local metres, Blender -Y nose and +Z up.

The section table drives the die-folded shell and its conformal paint masks.
Each editable assembly has its own object. Use export_streamliner.py separately
to export changes made by hand. Pass -- --shape for the internal blockout.
"""
from pathlib import Path
import sys
from math import floor
from types import SimpleNamespace
import bpy
from mathutils import Vector

HERE = Path(__file__).resolve().parent
BASE = HERE.parent
sys.path.insert(0, str(HERE))
sys.dont_write_bytecode = True
from export_streamliner import export_train

SHAPE = "--shape" in sys.argv
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.context.preferences.filepaths.save_version = 0
scene = bpy.context.scene
scene.unit_settings.system = 'METRIC'
scene.unit_settings.scale_length = 1


def metal(name, color, metallic, roughness, emission=0):
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (*color, 1)
    mat.use_nodes = True
    bs = mat.node_tree.nodes.get("Principled BSDF")
    bs.inputs['Base Color'].default_value = (*color, 1)
    bs.inputs['Metallic'].default_value = metallic
    bs.inputs['Roughness'].default_value = roughness
    if emission:
        bs.inputs['Emission Color'].default_value = (*color, 1)
        bs.inputs['Emission Strength'].default_value = emission
    return mat


gun = metal("gunmetal", (.081, .088, .093), .45, .46)
shell = metal("graphite_enamel", (.043, .046, .050), .38, .49)
frame = metal("underframe", (.017, .020, .023), .31, .55)
steel = metal("edge_steel", (.295, .31, .308), .65, .38)
ink = metal("service_ink", (.68, .65, .54), .12, .55)
glass = metal("armoured_glass", (.015, .027, .034), .35, .24)
wear = metal("exposed_alloy", (.27, .26, .235), .51, .47)
paint = metal("team_color", (.45, .036, .024), .27, .46)
white = metal("headlight_porcelain", (.91, .94, 1.0), .05, .28, 1.45)
amber = metal("amber", (.91, .35, .035), .14, .39, .18)
field = metal("field_ceramic", (.40, .74, .79), .24, .34, .45)
signal = metal("cargo_signal", (.96, .43, .048), .10, .31, .66)


def group(name):
    c = bpy.data.collections.new(name)
    scene.collection.children.link(c)
    return c


shells = group("01  /  Structure and cargo")
systems = group("02  /  Machinery and access")
livery = group("03  /  Paint, registration and signals")
bogies = group("04  /  Suspension and couplers")
root = bpy.data.objects.new("train_cargo_root", None)
shells.objects.link(root)
root.empty_display_type = 'PLAIN_AXES'
root.empty_display_size = .42


class Part:
    """Accumulate small details by assembly, retaining disconnected editable islands."""
    def __init__(self, name, collection, parent=root, origin=(0,0,0), bevel=0):
        self.name, self.collection, self.parent = name, collection, parent
        self.origin, self.bevel = Vector(origin), bevel
        self.vertices, self.faces, self.indices, self.mats = [], [], [], []

    def geo(self, verts, faces, material):
        start = len(self.vertices)
        self.vertices.extend([tuple(Vector(v) - self.origin) for v in verts])
        for face, mat in zip(faces, material if isinstance(material, list) else [material]*len(faces)):
            if mat not in self.mats:
                self.mats.append(mat)
            self.faces.append(tuple(i + start for i in face))
            self.indices.append(self.mats.index(mat))

    def face(self, verts, mat, normal):
        pts = []
        for vert in verts:
            point = Vector(vert)
            if all((point-other).length_squared > 1e-12 for other in pts):
                pts.append(point)
        if len(pts) < 3:
            return
        direction = sum(((p-pts[0]).cross(q-pts[0]) for p,q in zip(pts[1:-1],pts[2:])),Vector((0,0,0)))
        if direction.length_squared < 1e-16:
            return
        if direction.dot(Vector(normal)) < 0:
            pts.reverse()
        self.geo(pts, [range(len(pts))], mat)

    def finish(self):
        mesh = bpy.data.meshes.new(self.name)
        mesh.from_pydata(self.vertices, [], self.faces)
        for m in self.mats:
            mesh.materials.append(m)
        for polygon, index in zip(mesh.polygons, self.indices):
            polygon.material_index = index
        mesh.update()
        ob = bpy.data.objects.new(self.name, mesh)
        self.collection.objects.link(ob)
        ob.parent = self.parent
        ob.location = self.origin - self.parent.matrix_world.translation
        if self.bevel:
            mod = ob.modifiers.new("Machined edge radius", 'BEVEL')
            mod.width, mod.segments = self.bevel, 1
            mod.limit_method = 'ANGLE'
            mod.angle_limit = .32
            mod.harden_normals = True
            n = ob.modifiers.new("Panel normals", 'WEIGHTED_NORMAL')
            n.keep_sharp = True
        bpy.context.view_layer.update()
        return ob


def bridge(part, rings, mats, capmat=None):
    """Rings advance in +Y, each wound CCW as seen from the nose."""
    size = len(rings[0])
    faces = [tuple(range(size)), tuple(reversed(range((len(rings)-1)*size, len(rings)*size)))]
    capmat = capmat or mats[0]
    materials = [capmat, capmat]
    for j in range(len(rings)-1):
        for i in range(size):
            k = (i+1) % size
            faces.append((j*size+i, (j+1)*size+i, (j+1)*size+k, j*size+k))
            materials.append(mats[i])
    part.geo([p for r in rings for p in r], faces, materials)


def vault(part, section, materials, capmat=None):
    """Closed chamfered machine pod: station, half-width, floor, crown, bevel width."""
    rings = []
    for y,w,b,t,c in section:
        c = min(c, (t-b)*.45, w*.45)
        coords = [(w-c,b), (w,b+c), (w,t-c), (w-c,t),
                  (-w+c,t), (-w,t-c), (-w,b+c), (-w+c,b)]
        rings.append([(x,y,z) for x,z in coords])
    bridge(part,rings,materials,capmat)


# y, maximum half-width, keel, lower chine, side-to-shoulder break, roof.
STATIONS = [
    (-5.02,.87,1.52,1.61,1.90,2.04), (-4.63,1.08,1.42,1.62,1.99,2.26),
    (-3.70,1.47,1.37,1.63,2.16,2.70), (-2.36,1.74,1.35,1.65,2.53,3.19),
    (-1.72,1.78,1.35,1.66,2.69,3.34), (-.65,1.79,1.35,1.66,2.73,3.37),
    (1.00,1.79,1.35,1.66,2.73,3.37), (1.36,1.77,1.35,1.66,2.69,3.29),
    (4.34,1.77,1.35,1.66,2.69,3.29), (4.68,1.70,1.39,1.66,2.62,3.18),
    (4.93,1.48,1.52,1.68,2.51,2.99),
]


def profile(y):
    for a,b in zip(STATIONS, STATIONS[1:]):
        if y <= b[0]+1e-7:
            f = max(0,min(1,(y-a[0])/(b[0]-a[0])))
            w,keel,low,chine,top = [u+(v-u)*f for u,v in zip(a[1:],b[1:])]
            return [(w*.79,keel),(w*.93,keel+.075),(w,low),
                    (w*.975,chine),(w*.912,chine+(top-chine)*.26),
                    (w*.635,top-.065),(w*.56,top),(0,top)]
    return profile(STATIONS[-1][0])


def skin(y, v, side=1, offset=0):
    """Map a transverse crease coordinate to a point on the shell."""
    row = profile(y)
    i = min(6,max(0,floor(v)))
    f = max(0,min(1,v-i))
    x,z = row[i]
    dx,dz = row[i+1][0]-x, row[i+1][1]-z
    # Shared offset at creases avoids hairline splits between joined mask panels.
    normal = Vector((.95 if v < 4 else max(0, (6.0-v)/2), 0, .12 if v < 3 else min(1,(v-2)/3))).normalized()
    offset *= .38
    return (side*(x+dx*f+offset*normal.x), y, z+dz*f+offset*normal.z)


def jacket(name,a,b,mat):
    p = Part(name,shells, origin=(0,0,2.5) if name=='cargo_body' else (0,(a+b)/2,2.2),bevel=.012)
    stations = [a]+[s[0] for s in STATIONS if a<s[0]<b]+[b]
    rings = [[skin(y,i,1) for i in range(7)] + [skin(y,i,-1) for i in reversed(range(7))] for y in stations]
    bridge(p,rings,[frame,gun,mat,gun,mat,gun,mat,gun,mat,gun,mat,gun,frame,frame],mat)
    return p.finish()


def patch(part, side, rows, mat, offset=.022):
    """Longitudinal strips: (crease coordinate, front Y, rear Y).

    Keep panel edges on the folded shell, adding samples at the armour stations.
    A small gap between adjacent access panels remains visible in silhouette light.
    """
    for (v,a,b),(w,c,d) in zip(rows,rows[1:]):
        cuts = {0.,1.}
        for ya,yb in [(a,b),(c,d)]:
            if abs(yb-ya) > 1e-5:
                cuts.update(round((r[0]-ya)/(yb-ya),6) for r in STATIONS if ya<r[0]<yb)
        # Match breaks on both rows even along a strongly raked painted edge.
        if abs(a-c) + abs(b-d) > .2:
            cuts.add(.5)
        pieces=sorted(cuts)
        for u0,u1 in zip(pieces,pieces[1:]):
            pts = [skin(a+(b-a)*u0,v,side,offset),skin(a+(b-a)*u1,v,side,offset),
                   skin(c+(d-c)*u1,w,side,offset),skin(c+(d-c)*u0,w,side,offset)]
            part.face(pts,mat,(side,0,1 if v>=3 else .08))


def rect_patch(p, side, v0,v1, a,b,mat,offset=.022, rake=0):
    levels = [v0]+[i for i in range(1,7) if v0<i<v1]+[v1]
    patch(p,side,[(v,a+rake*(v-v0)/(v1-v0),b+rake*(v-v0)/(v1-v0)) for v in levels],mat,offset)


def top_band(p, y0,y1,width, mat, offset):
    for side in [-1,1]:
        rect_patch(p,side,7-width,7,y0,y1,mat,offset)


# Single car understructure and split shells over an inset continuous chassis.
p=Part("load_bearing_keel",shells,bevel=.028)
vault(p,[(-4.90,.68,1.44,1.92,.13),(-3.70,1.32,1.255,2.06,.16),
         (3.98,1.40,1.255,2.17,.16),(4.83,1.25,1.43,2.10,.11)],
      [gun,frame,gun,frame,gun,frame,gun,frame])
p.finish()
for name,a,b,m in [
    ("integrated_nose",-5.02,-2.38,gun),("cab_shoulders",-2.363,-.663,shell),
    ("cargo_body",-.644,1.063,shell),("cargo_access_shell",1.126,4.315,gun),
    ("tail_armour",4.339,4.93,shell)]:
    jacket(name,a,b,m)

p=Part("machinery_spine",systems,bevel=.024)
vault(p,[(-1.97,.49,3.18,3.27,.055),(-1.16,.83,3.255,3.87,.105),
         (-.94,.87,3.27,3.955,.10),(.71,.87,3.27,3.955,.10),
         (1.07,.75,3.255,3.68,.085),(1.22,.57,3.23,3.48,.05)],
      [frame,shell,gun,gun,gun,shell,frame,frame])
p.finish()
p=Part("cargo_roof_spine",systems,bevel=.023)
vault(p,[(1.35,.58,3.22,3.355,.04),(1.70,.74,3.23,3.59,.08),
         (3.04,.74,3.23,3.59,.08),(3.28,.56,3.23,3.43,.05),
         (3.88,.56,3.20,3.43,.05),(4.38,.58,3.19,3.48,.05),
         (4.66,.49,3.08,3.32,.04)], [frame,shell,gun,gun,gun,shell,frame,frame])
p.finish()


def ribbons():
    p = Part("team_livery",livery)
    stripe = [
        (-4.88,2.39,2.72),(-4.37,2.36,2.97),(-3.98,2.37,3.28),
        (-2.82,2.37,3.28),(-2.31,2.63,4.44),(-1.89,2.63,4.85),
        (.22,2.63,4.85),(.49,2.63,5.37),(.57,2.63,6.40),(1.03,2.64,6.40)]
    if SHAPE:
        stripe = [(-4.88,2.48,2.66),(-4.37,2.49,2.84),(-3.98,2.59,3.02),
                  (-2.82,2.59,2.96),(-2.31,2.83,3.50),(-1.89,2.86,3.56),
                  (.43,2.88,3.56),(.73,2.88,4.03),(.98,2.90,5.32)]
    # Each stripe segment follows the actual crease, including the high shoulder return.
    for s in (-1,1):
        for (a,l,h),(b,ll,hh) in zip(stripe,stripe[1:]):
            steps = sorted({0.,1., *[round((r[0]-a)/(b-a),6) for r in STATIONS if a<r[0]<b],
                            .25,.5,.75})
            for u,v in zip(steps,steps[1:]):
                rows = []
                for t in (u,v):
                    y,lo,hi = a+(b-a)*t, l+(ll-l)*t,h+(hh-h)*t
                    rows.append((y,lo,hi))
                y0,l0,h0=rows[0]
                y1,l1,h1=rows[1]
                for k in (2,3,4,5,6):
                    lo0,hi0=max(k,l0),min(k+1,h0)
                    lo1,hi1=max(k,l1),min(k+1,h1)
                    if hi0<=lo0 and hi1<=lo1: continue
                    lo0=min(lo0,k+1);lo1=min(lo1,k+1)
                    hi0=max(lo0,hi0);hi1=max(lo1,hi1)
                    verts=[skin(y0,lo0,s,.026),skin(y1,lo1,s,.026),skin(y1,hi1,s,.026),skin(y0,hi0,s,.026)]
                    p.face(verts,paint,(s,0,.5))
        # Rear lifting frame has two short accent bands across both shoulders.
        if SHAPE:
            for y,wid in [(1.40,.34),(3.95,.38)]:
                patch(p,s,[(2.88,y+.12,y+wid+.12),(3,y+.1,y+wid+.1),
                           (4,y,y+wid),(5,y-.13,y+wid-.13),(6.26,y-.15,y+wid-.15)],paint,.028)
        else:
            # Freight shoulder straps descend beside the door, with a clipped end at the sill.
            for y,wid,foot in [(1.29,.54,-.12),(3.99,.56,.19)]:
                patch(p,s,[(2.03,y+foot+.10,y+wid+foot-.10),(2.25,y+foot,y+wid+foot),
                           (3,y+.08,y+wid+.08),(4,y,y+wid),(5,y-.13,y+wid-.13),
                           (6,y-.16,y+wid-.16),(6.49,y-.16,y+wid-.16)],paint,.028)
            p.face([(s*.30,-5.024,1.64),(s*.69,-5.024,1.64),(s*.76,-5.024,1.83),
                    (s*.37,-5.024,1.83)],paint,(0,-1,0))
        # Wide ownership return high on the powered segment, readable from above.
        if SHAPE:
            patch(p,s,[(3.01,.68,1.045),(4,.63,1.045),(5,.38,1.03),(6.28,.31,1.01)],paint,.032)
    top_band(p,-4.97,-4.68,.94,paint,.029)
    top_band(p,-4.31,-4.19,.94,paint,.025)
    return p.finish()


ribbons()


def simple_shoes():
    for name,y in [('sled_cargo_front',-3),('sled_cargo_rear',3)]:
        p=Part(name,bogies,origin=(0,y,1),bevel=.035)
        vault(p,[(y-1.38,.91,.78,1.18,.12),(y-.97,1.19,.69,1.29,.15),
                 (y+.97,1.19,.69,1.29,.15),(y+1.38,.91,.78,1.18,.12)],[gun]*8)
        p.finish()


if SHAPE:
    simple_shoes()
else:
    import running_gear
    running_gear.build(root)


def finish_source():
    for ob in root.children_recursive:
        if ob.name.startswith(("sled_cargo","cargo_coupler")) or ob.parent.name.startswith(("sled_cargo","cargo_coupler")):
            for c in list(ob.users_collection):
                if c != bogies:
                    c.objects.unlink(ob)
            if ob.name not in bogies.objects:
                bogies.objects.link(ob)
    bpy.ops.object.select_all(action='DESELECT')
    bpy.context.view_layer.objects.active = root
    for screen in bpy.data.screens:
        for area in screen.areas:
            if area.type == 'VIEW_3D':
                space = area.spaces.active
                space.shading.color_type = 'MATERIAL'
                space.shading.light = 'STUDIO'
                space.shading.show_cavity = True
                space.shading.cavity_type = 'WORLD'
                space.overlay.show_overlays = False
                reg = space.region_3d
                reg.view_perspective = 'ORTHO'
                reg.view_location = (0,0,2.1)
                reg.view_distance = 16
                reg.view_rotation = Vector((12, -8, 7)).to_track_quat('Z','Y')
    if SHAPE:
        export_train(BASE / 'validation' / 'shape' / 'blockout.glb')
    else:
        bpy.ops.wm.save_as_mainfile(filepath=str(HERE / 'Industrial_Streamliner.blend'),compress=True)
        export_train(BASE / 'export' / 'maglev_train_cargo.glb')


if not SHAPE:
    import finish_detail
    finish_detail.build(SimpleNamespace(**globals()))
finish_source()
