"""Sculpted head in the infantry bind pose. Dimensions below are in facial millimetres."""
from math import asin, cos, pi, sin

from mathutils import Vector


def _world(point):
    x, y, z = point
    return (x * .001, .03 + y * .001, 1.425 + z * .001)


class Assembly:
    def __init__(self, kit, name):
        self.kit, self.name = kit, name
        self.points, self.faces, self.mats, self.indices = [], [], [], []

    def solid(self, points, faces, material):
        start = len(self.points)
        self.points.extend([_world(point) for point in points])
        mats = material if isinstance(material, list) else [material] * len(faces)
        for face, mat in zip(faces, mats):
            if mat not in self.mats:
                self.mats.append(mat)
            self.faces.append(tuple(start + i for i in face))
            self.indices.append(self.mats.index(mat))

    def rings(self, rings, bands, caps):
        """Rings in CCW order when viewed from their last end."""
        n = len(rings[0])
        faces = [tuple(reversed(range(n)))]
        mats = [caps[0]]
        for j in range(len(rings) - 1):
            for i in range(n):
                k = (i + 1) % n
                faces.append((j*n+i, j*n+k, (j+1)*n+k, (j+1)*n+i))
                mats.append(bands(j, i))
        faces.append(tuple(range((len(rings)-1)*n, len(rings)*n)))
        mats.append(caps[1])
        self.solid([v for r in rings for v in r], faces, mats)

    def finish(self):
        return self.kit.mesh(self.name, self.points, self.faces, self.mats, "head", self.indices)


# The seven front columns follow the philtrum, nose wing, orbital rim, cheekbone,
# jaw corner, and temple. Each row continues around the cranium to the back seam.
# Head width changes at the cheekbone and the mandible instead of scaling a sphere.
ROWS = [
    # nominal z, front half-ring (x,y,z correction), then posterior half-ring (x,y)
    (2, [(0,-119,0),(19,-120,0),(38,-114,0),(56,-95,1),(72,-71,4),(87,-39,8),(92,-16,12)],
        [(87,28),(64,65),(0,82)]),
    (19,[(0,-136,0),(24,-135,0),(49,-126,0),(76,-106,1),(99,-81,6),(113,-51,11),(117,-16,17)],
        [(110,43),(78,91),(0,107)]),
    (44,[(0,-141,0),(25,-141,-1),(49,-135,0),(80,-118,4),(106,-95,8),(125,-60,12),(128,-13,16)],
        [(122,48),(84,101),(0,114)]),
    (63,[(0,-142,0),(23,-141,0),(42,-136,-2),(74,-121,3),(103,-100,10),(126,-64,10),(131,-12,12)],
        [(125,50),(87,106),(0,122)]),
    (81,[(0,-146,1),(17,-143,0),(36,-137,-2),(69,-125,-2),(104,-105,8),(127,-67,10),(132,-13,15)],
        [(128,53),(88,106),(0,122)]),
    (96,[(0,-156,-5),(17,-153,-3),(32,-146,-5),(61,-125,-3),(105,-110,12),(128,-66,21),(133,-13,19)],
        [(127,56),(90,109),(0,125)]),
    (111,[(0,-180,-5),(15,-170,-5),(28,-149,-9),(61,-128,0),(102,-111,8),(125,-69,13),(134,-13,12)],
        [(130,60),(92,114),(0,130)]),
    (135,[(0,-164,0),(14,-154,1),(27,-136,3),(60,-129,1),(103,-111,-4),(125,-74,2),(135,-17,4)],
        [(131,64),(94,117),(0,133)]),
    (154,[(0,-151,0),(17,-145,-2),(32,-135,0),(65,-130,-1),(99,-111,0),(123,-78,0),(136,-19,1)],
        [(132,64),(97,119),(0,134)]),
    (177,[(0,-149,-1),(17,-146,-3),(35,-148,-4),(69,-144,1),(98,-126,3),(124,-79,1),(137,-18,0)],
        [(133,66),(97,121),(0,137)]),
    (202,[(0,-144,0),(16,-145,0),(38,-145,0),(68,-140,0),(101,-122,0),(123,-79,0),(137,-18,0)],
        [(133,70),(97,124),(0,139)]),
    (235,[(0,-127,0),(21,-126,0),(37,-124,0),(69,-116,0),(91,-100,0),(116,-64,0),(127,-10,0)],
        [(125,61),(83,110),(0,129)]),
    (268,[(0,-96,0),(21,-95,0),(36,-92,0),(58,-87,0),(80,-73,0),(98,-44,0),(107,-5,0)],
        [(106,52),(73,93),(0,106)]),
]


def face_skin(artist, skin, liner):
    rings = []
    for z, front, back in ROWS:
        jaw_taper = min(1, .91 + z / 610)
        cranium_taper = max(.77, 1 - max(0,z-142) / 360)
        half = [(x*jaw_taper*(cranium_taper if i==6 else 1),y,z+h)
                for i,(x,y,h) in enumerate(front)]
        half += [(x*cranium_taper*jaw_taper,y*cranium_taper,z) for x,y in back]
        rings.append(half + [(-x,y,zz) for x,y,zz in half[-2:0:-1]])
    artist.rings(rings,lambda j,i:liner if 7<=i<11 else skin,(skin,skin))

    # Fit facial details to the real, triangulated skin surface from either side.
    tris = []
    for lo, hi in zip(rings, rings[1:]):
        for i in range(6):
            for tri in [(lo[i],lo[i+1],hi[i+1]), (lo[i],hi[i+1],hi[i])]:
                tris.append(tri)

    def front_y(x, z):
        x = abs(x)
        for a,b,c in tris:
            det = (b[2]-c[2])*(a[0]-c[0]) + (c[0]-b[0])*(a[2]-c[2])
            if abs(det) < .000001:
                continue
            u=((b[2]-c[2])*(x-c[0])+(c[0]-b[0])*(z-c[2]))/det
            v=((c[2]-a[2])*(x-c[0])+(a[0]-c[0])*(z-c[2]))/det
            if min(u,v,1-u-v) >= -.0001:
                return u*a[1]+v*b[1]+(1-u-v)*c[1]
        raise ValueError(f"Face marking outside the forehead, cheek or jaw at {x}, {z}")
    return front_y,rings


def nape_guard(k,skin_rings):
    # Tapered suspension curtain. Its front ends tuck under the ear guards;
    # the lowered centre edge covers the neck at the back of the greatcoat.
    artist=Assembly(k,"helmet_nape_guard")
    leather=k.leather
    welt=k.mat("helmet_liner_welt",(.044,.041,.039),.11,.63)
    heights=[87,45,18,1,-5,1,18,45,87]
    def at_height(column,z):
        if z<=skin_rings[0][column][2]:
            x,y,_=skin_rings[0][column]
            return Vector((x,y,z))
        for a,b in zip(skin_rings,skin_rings[1:]):
            a,b=Vector(a[column]),Vector(b[column])
            if z<=b.z:
                return a.lerp(b,(z-a.z)/(b.z-a.z))
        return Vector(skin_rings[-1][column])

    verts,faces,mats=[],[],[]
    steps=[(0,0),(.032,1),(.16,1),(.30,1.1),(.43,1.3),(.59,.8),(.77,.4),(1,0)]
    cols=len(heights)
    last=len(steps)-1
    outside=cols*len(steps)
    for depth in (-2.5,4.4):
        for t,padding in steps:
            for j,bottom in enumerate(heights):
                z=bottom+(170-bottom)*t
                point=at_height(j+5,z)
                normal=Vector((point.x,point.y,0)).normalized()
                ear_return = 3.0 if depth>0 and j in (0,1,7,8) else 0
                verts.append(point+normal*(depth+padding+ear_return))
    # Make both sidewalls, lower rolled lip and the forward cutout editable.
    for layer in (0,1):
        for row in range(last):
            for j in range(cols-1):
                a=layer*outside+row*cols+j
                face=(a,a+1,a+cols+1,a+cols)
                faces.append(face if layer else face[::-1])
                mats.append(welt if row==0 and layer else leather)
    for j in range(cols-1):
        upper=j+cols*last
        faces.extend([(j,j+1,j+outside+1,j+outside),
                      (upper,upper+outside,upper+outside+1,upper+1)])
        mats.extend([welt,leather])
    for row in range(last):
        a=row*cols
        b=a+cols-1
        faces.extend([(a,a+outside,a+outside+cols,a+cols),
                      (b,b+cols,b+cols+outside,b+outside)])
        mats.extend([welt,welt])
    artist.solid(verts,faces,mats)
    artist.finish()


def relief(artist, surface, xz, mat, lift=2.0):
    # Fan around a surface-fitted centre, keeping eyelids and lips flush across facets.
    cx = sum(x for x,z in xz)/len(xz)
    cz = sum(z for x,z in xz)/len(xz)
    ring = list(xz)
    if sum(x*z2-z*x2 for (x,z),(x2,z2) in zip(ring,ring[1:]+ring[:1])) < 0:
        ring.reverse()
    points = [(cx,surface(cx,cz)-lift,cz)]
    points.extend((x,surface(x,z)-lift,z) for x,z in ring)
    artist.solid(points,[(0,i+1,(i+1)%len(ring)+1) for i in range(len(ring))],mat)


def eyebrow(artist,surface,brow):
    # A bevelled ridge keeps the eyebrow attached at every change of forehead slope.
    sections=[(25,161,167),(32,160,173),(49,165,178),(66,169,182),
              (82,171,183),(93,173,180),(103,174,176)]
    verts=[]
    for x,bottom,top in sections:
        for z,lift in ((bottom,3.8),(top-1.0,5),(top,.8)):
            verts.append((x,surface(x,z)-lift,z))
    faces=[]
    for i in range(len(sections)-1):
        a=3*i
        faces.extend([(a,a+3,a+4,a+1),(a+1,a+4,a+5,a+2)])
    artist.solid(verts,faces,brow)


def finish_face(artist, skin_polygons):
    # Blend the broad cheek and forehead planes while retaining the angular cut
    # across the brow and underside of the mandible. Detail shares no vertices.
    mesh=artist.finish().data
    adjacent=[[] for _ in mesh.vertices]
    for poly in list(mesh.polygons)[:skin_polygons]:
        for point in poly.vertices:
            adjacent[point].append(poly.normal.copy())
    normals=[(0,0,0)]*len(mesh.loops)
    for poly in mesh.polygons:
        if poly.index >= skin_polygons:
            for i in poly.loop_indices:
                normals[i]=tuple(poly.normal)
            continue
        poly.use_smooth=True
        for i in poly.loop_indices:
            local=adjacent[mesh.loops[i].vertex_index]
            avg=sum((n for n in local if n.dot(poly.normal)>.89),Vector()).normalized()
            normals[i]=tuple(poly.normal.lerp(avg,.65).normalized())
    mesh.normals_split_custom_set(normals)


def helmet(k):
    artist=Assembly(k,"helmet_shell_and_colourband")
    shell=k.mat("helmet_graphite",(.045,.047,.046),.32,.51)
    rim=k.mat("helmet_rolled_edge",(.068,.071,.069),.48,.42)
    liner=k.mat("helmet_gasket",(.019,.018,.016),.03,.78)
    # True flared brim: the visor clears the eyebrow while the sides cover the ears.
    # Fixed-width axial paint continues continuously across the dome and down its back.
    sections=[
        (168,159,192,134,124,-3),(183,177,193,131,121,-5),
        (187,180,198,137,128,-5),(168,161,213,169,161,-1),
        (154,150,226,204,198,3),(152,147,249,240,236,5),
        (140,137,285,280,277,8),(118,116,319,319,315,9),
        (89,87,345,345,342,9),(57,56,360,360,359,9),
        (32,32,365,365,365,9)]
    rings=[]
    qcount=7
    for rx,ry,nose,side,back,shift in sections:
        cut=asin(min(.976,32/rx))
        quadrant=[0,cut]+[cut+(pi/2-cut)*i/(qcount-1) for i in range(1,qcount)]
        angles=(quadrant[:-1] + [pi-a for a in reversed(quadrant[1:])] +
                [pi+a for a in quadrant[:-1]] + [2*pi-a for a in reversed(quadrant[1:])])
        ring=[]
        for a in angles:
            cs=cos(a)
            z=side+(nose-side)*max(0,cs)**2.2+(back-side)*max(0,-cs)**1.65
            ring.append((rx*sin(a),shift-ry*cs,z))
        rings.append(ring)
    on_axis={0,2*qcount-1,2*qcount,4*qcount-1}
    def band(j,i):
        if j>=6 and i in on_axis:
            return k.team
        return liner if j==0 else rim if j==1 else shell
    artist.rings(rings,band,(liner,k.team))
    return artist.finish()


def local_rings(artist, centre, right, up, profiles, bands, caps):
    u, v = Vector(right).normalized(), Vector(up).normalized()
    n = u.cross(v).normalized()
    rings=[]
    for depth,xz in profiles:
        rings.append([Vector(centre)+u*x+v*z+n*depth for x,z in xz])
    artist.rings(rings,bands,caps)


def octagon(hw,hh,clip):
    return [(-hw+clip,-hh),(hw-clip,-hh),(hw,-hh+clip),(hw,hh-clip),
            (hw-clip,hh),(-hw+clip,hh),(-hw,hh-clip),(-hw,-hh+clip)]


def circle(rx,rz,n=16):
    return [(rx*cos(2*pi*i/n),rz*sin(2*pi*i/n)) for i in range(n)]


def implants(k):
    case = Assembly(k,"orbital_implant_and_helmet_pads")
    graphite=k.blacksteel
    steel=k.gunmetal
    dark=k.mat("optic_recess",(.012,.014,.014),.36,.36)
    warm=k.mat("optic_copper_ring",(.23,.080,.035),.58,.40)
    for side in (-1,1):
        # The helmet suspension terminates in a separate pair of leather ear guards.
        centre=(side*122,0,145)
        u=(0,side,0)
        local_rings(case,centre,u,(0,0,1),
            [(-3,octagon(48,42,13)),(8,octagon(50,42,12)),(15,octagon(44,36,12))],
            lambda j,i:k.leather,(k.leather,k.leather))
        local_rings(case,(side*139,-9,151),u,(0,0,1),
            [(0,circle(17,17,12)),(3,circle(17,17,12)),(5,circle(13,13,12))],
            lambda j,i:graphite,(graphite,steel))
    # Orbital implant follows the slope of the temple and has a one-sided bridge.
    centre=(-68,-133,155)
    u=(1,-.29,0)
    v=(0,0,1)
    local_rings(case,centre,u,v,
        [(-13,octagon(47,34,9)),(4,octagon(48,34,9)),(12,octagon(44,31,8))],
        lambda j,i:graphite if j==0 else steel,(graphite,graphite))
    local_rings(case,centre,u,v,
        [(11,circle(24.5,24.5)),(16,circle(25.5,25.5)),(20,circle(22.5,22.5)),
         (21,circle(18,18)),(17,circle(15,15))],
        lambda j,i:(graphite,steel,dark,warm)[j],(graphite,dark))
    # Rear link/temple wiring follows the outside of the cheek and tucks under the cap.
    local_rings(case,(-122,-68,157),(0,-1,0),v,
        [(0,octagon(35,12,6)),(9,octagon(34,12,5)),(11,octagon(32,10,4))],
        lambda j,i:graphite,(graphite,steel))
    case.finish()
    lens=Assembly(k,"eye_lens_rig")
    lamp=k.mat("ocular_vermilion",(.77,.039,.010),.12,.28,.60)
    local_rings(lens,centre,u,v,
        [(17.2,circle(15,15)),(21.4,circle(16,16)),(24.5,circle(11.8,11.8))],
        lambda j,i:lamp,(lamp,lamp))
    lens.finish()


def build(k):
    artist=Assembly(k,"sculpted_head")
    skin=k.mat("skin_warm_ochre",(.51,.286,.154),.0,.77)
    lid=k.mat("skin_lid",(.35,.188,.102),0,.79)
    lip=k.mat("skin_lip",(.42,.232,.146),0,.70)
    shadow=k.mat("face_crease",(.086,.049,.031),.0,.81)
    brow=k.mat("brows",(.039,.029,.022),0,.79)
    eye=k.mat("eye_ivory",(.57,.48,.35),0,.40)
    iris=k.mat("eye_iris",(.065,.059,.043),0,.42)
    surface,skin_rings=face_skin(artist,skin,k.leather)
    skin_polygons=len(artist.faces)
    # A hooded human eye with an uninterrupted brow; the opposite eye is prosthetic.
    relief(artist,surface,[(31,146),(39,156),(69,164),(93,163),(86,153),(60,145),(37,144)],shadow,2.3)
    relief(artist,surface,[(35,147),(43,155),(68,159),(88,160),(82,153),(57,146)],eye,3.8)
    relief(artist,surface,[(53,156),(67,159),(66,151),(62,147),(54,147),(50,151)],iris,4.9)
    relief(artist,surface,[(55,157),(62,158),(60,150),(55,150)],brow,5.6)
    relief(artist,surface,[(36,143),(57,142),(78,147),(84,150),(62,145),(44,145)],lid,2.3)
    eyebrow(artist,surface,brow)
    # Distinct upper lip, downturned seam, lower lip and a small cut beneath the nose.
    relief(artist,surface,[(-40,54),(-25,62),(-8,66),(0,64),(8,66),(25,62),(40,54),
                            (15,58),(0,57),(-17,58)],lip,2.3)
    relief(artist,surface,[(-41,53),(-23,59),(-9,61),(0,60),(9,61),(23,59),(41,53),
                            (29,54),(12,57),(-12,57),(-29,54)],shadow,3.7)
    relief(artist,surface,[(-26,52),(-12,55),(11,55),(26,52),(12,48),(-10,48)],lip,1.7)
    for s in (-1,1):
        relief(artist,surface,[(s*11,93),(s*19,96),(s*25,95),(s*20,92)],shadow,1.7)
    finish_face(artist,skin_polygons)
    nape_guard(k,skin_rings)
    helmet(k)
    implants(k)
