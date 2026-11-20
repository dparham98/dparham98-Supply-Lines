"""Sculpted head in the infantry bind pose. Dimensions below are in facial millimetres."""
from math import ceil, cos, pi, sin
from field_helmet import build as build_helmet

from mathutils import Vector
from mathutils.geometry import tessellate_polygon


def _world(point):
    x, y, z = point
    return (x * .001, .03 + y * .001, 1.425 + z * .001)


class Assembly:
    def __init__(self, kit, name):
        self.kit, self.name = kit, name
        self.points, self.faces, self.mats, self.indices = [], [], [], []
        self.smooth_faces = []

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
        obj = self.kit.mesh(self.name, self.points, self.faces, self.mats, "head", self.indices)
        for index in self.smooth_faces:
            obj.data.polygons[index].use_smooth=True
        return obj


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


def face_skin(artist, cast, chassis, liner):
    rings,guard_rings=[],[]
    for z,front,back in ROWS:
        jaw_taper=min(1,.91+z/610)
        chin_taper=min(1,.79+z/550)
        cranium=max(.77,1-max(0,z-142)/360)
        lower_width=.77+.23*min(1,z/120)
        lower_lift=13*max(0,1-z/94)
        original=[]
        half=[]
        for i,(x,y,h) in enumerate(front):
            width=jaw_taper*(cranium if i==6 else 1)
            original.append((x*width,y,z+h))
            # Keep a broad cheekbone and draw the lower corners inward and up
            # toward the ear. The jaw pivots inside the padded nape guard.
            blend=max(0,min(1,(i-2)/3))
            narrowed=(1-blend)*chin_taper+blend*width*lower_width
            half.append((x*narrowed,y,z+h+lower_lift*blend))
        original.extend((x*cranium*jaw_taper,y*cranium,z) for x,y in back)
        half.extend((x*cranium*jaw_taper*lower_width,y*cranium,z+lower_lift) for x,y in back)
        def mirror(arc):
            return arc+[(-x,y,zz) for x,y,zz in arc[-2:0:-1]]
        rings.append(mirror(half))
        guard_rings.append(mirror(original))

    # The ivory mask ends along the moving jaw seam. Divide intersected
    # skin triangles at that line so the side casting is a continuous solid.
    cut=[(2,39),(19,51),(44,69),(63,79),(81,89),(96,99),(112,106),
         (135,112),(155,115),(180,120),(205,125),(280,111)]
    def mask_edge(v):
        x,_,z=v
        for (lo,a),(hi,b) in zip(cut,cut[1:]):
            if z<=hi:
                return abs(x)-(a+(b-a)*max(0,(z-lo)/(hi-lo)))
        return abs(x)-cut[-1][1]

    verts,faces,mats,index=[],[],[],{}
    def polygon(points,mat):
        indices=[]
        for p in points:
            key=tuple(round(c,5) for c in p)
            if key not in index:
                index[key]=len(verts)
                verts.append(p)
            indices.append(index[key])
        if len(set(indices))>=3:
            faces.append(indices)
            mats.append(mat)

    def split_triangle(points):
        inside,outside=[],[]
        for a,b in zip(points,points[1:]+points[:1]):
            da,db=mask_edge(a),mask_edge(b)
            (inside if da<=0 else outside).append(a)
            if (da<0<db) or (db<0<da):
                t=da/(da-db)
                seam=tuple(x+(y-x)*t for x,y in zip(a,b))
                inside.append(seam)
                outside.append(seam)
        polygon(inside,cast)
        polygon(outside,chassis)

    count=len(rings[0])
    polygon(rings[0][::-1],chassis)
    for lo,hi in zip(rings,rings[1:]):
        for i in range(count):
            j=(i+1)%count
            quad=[lo[i],lo[j],hi[j],hi[i]]
            if i<6 or i>=count-6:
                # Mirror the triangulation at the midline like the surface
                # sampler below, including the diagonal through the nose.
                if i<6:
                    split_triangle([quad[0],quad[1],quad[2]])
                    split_triangle([quad[0],quad[2],quad[3]])
                else:
                    split_triangle([quad[0],quad[1],quad[3]])
                    split_triangle([quad[1],quad[2],quad[3]])
            else:
                polygon(quad,liner if 7<=i<11 else chassis)
    polygon(rings[-1],chassis)
    artist.solid(verts,faces,mats)

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
    return front_y,guard_rings


def nape_guard(k,skin_rings):
    # A leather suspension curtain with a turned lower hem. The longitudinal
    # channels let the curtain bend behind the ears as the head turns.
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
    steps=[(0,0),(.009,.8),(.020,1.6),(.031,1.7),(.041,1.1),(.052,.75),
           (.11,.8),(.22,1.1),(.37,1.4),(.53,1.6),(.68,1.0),(.83,.6),(1,0)]
    per_span=4
    cols=(len(heights)-1)*per_span+1
    last=len(steps)-1
    outside=cols*len(steps)
    for depth in (-2.5,4.4):
        for t,padding in steps:
            guides=[at_height(j+5,bottom+(170-bottom)*t) for j,bottom in enumerate(heights)]
            for col in range(cols):
                j=min(col//per_span,len(guides)-2)
                u=col/per_span-j
                a,b,c,d=guides[max(0,j-1)],guides[j],guides[j+1],guides[min(j+2,len(guides)-1)]
                point=.5*((2*b)+(c-a)*u+(2*a-5*b+4*c-d)*u*u+(3*b-a-3*c+d)*u**3)
                normal=Vector((point.x,point.y,0)).normalized()
                ear_return=3*max(0,1-min(col,cols-1-col)/(per_span*2)) if depth>0 else 0
                relief=1.1*cos((col/(cols-1)-.5)*5*pi)**5*sin(pi*t)
                verts.append(point+normal*(depth+padding+ear_return+relief))
    # Make both sidewalls, lower rolled lip and the forward cutout editable.
    for layer in (0,1):
        for row in range(last):
            for j in range(cols-1):
                a=layer*outside+row*cols+j
                face=(a,a+1,a+cols+1,a+cols)
                faces.append(face if layer else face[::-1])
                mats.append(welt if row<4 and layer else leather)
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
    artist.smooth_faces.extend(range(2*last*(cols-1)))
    artist.finish()


def plate(artist, surface, outline, material, lift, edge=None, bevel=1.5):
    """A pressed face plate, with a bevel and a dark return against the casting.

    Project the outline and subdivided front onto the actual cheek surface.
    This keeps the mouth and the jaw seams attached around the facial planes.
    """
    loop = [Vector((x,z,0)) for x,z in outline]
    if sum(a.x*b.y-b.x*a.y for a,b in zip(loop,loop[1:]+loop[:1])) < 0:
        loop.reverse()
    # The inner lip rolls in toward the plate's centre without moving the
    # outside silhouette. Small eye parts can use a zero-width bevel.
    centre = sum(loop,Vector())/len(loop)
    inner = [v+(centre-v).normalized()*bevel for v in loop]
    verts,faces,mats,indices = [],[],[],{}
    def vertex(p,depth):
        key=(round(p.x,4),round(p.y,4),round(depth,3))
        if key not in indices:
            indices[key]=len(verts)
            verts.append((p.x,surface(p.x,p.y)-depth,p.y))
        return indices[key]

    def face(points,mat):
        faces.append(points)
        mats.append(mat)

    # Shared sampling across every boundary keeps adjacent triangles joined
    # where the plate bends around the cheekbone.
    steps=min(5,max(1,ceil(max((p-centre).length for p in loop)/11)))
    for a,b,c in tessellate_polygon([inner]):
        a,b,c=inner[a],inner[b],inner[c]
        grid={(i,j): vertex(a+(b-a)*(i/steps)+(c-a)*(j/steps),lift)
              for i in range(steps+1) for j in range(steps+1-i)}
        for i in range(steps):
            for j in range(steps-i):
                face((grid[i,j],grid[i+1,j],grid[i,j+1]),material)
                if i+j+1<steps:
                    face((grid[i+1,j],grid[i+1,j+1],grid[i,j+1]),material)
    # The stamped front follows one continuous curve. Its rim and returns
    # keep their hard edges so the plate still reads at gameplay distance.
    artist.smooth_faces.extend(range(len(artist.faces),len(artist.faces)+len(faces)))
    for i,a in enumerate(loop):
        j=(i+1)%len(loop)
        b=loop[j]
        count=steps
        for n in range(count):
            t,u=n/count,(n+1)/count
            p,q=a.lerp(b,t),a.lerp(b,u)
            low=lift-max(1.2,bevel)
            rim=lift if bevel==0 else low
            if bevel:
                face((vertex(p,rim),vertex(q,rim),
                      vertex(inner[i].lerp(inner[j],u),lift),vertex(inner[i].lerp(inner[j],t),lift)),edge or material)
            face((vertex(p,.2),vertex(q,.2),vertex(q,rim),vertex(p,rim)),edge or material)
    artist.solid(verts,faces,mats)


def finish_face(artist):
    # Blend the broad cheek and forehead planes while retaining the angular cut
    # across the brow and underside of the mandible.
    mesh=artist.finish().data
    adjacent=[[] for _ in mesh.vertices]
    for poly in mesh.polygons:
        vertices=list(poly.vertices)
        for i,point in enumerate(vertices):
            centre=mesh.vertices[point].co
            a=mesh.vertices[vertices[i-1]].co-centre
            b=mesh.vertices[vertices[(i+1)%len(vertices)]].co-centre
            adjacent[point].append((poly.normal.copy(),a.angle(b,0)))
    normals=[(0,0,0)]*len(mesh.loops)
    for poly in mesh.polygons:
        poly.use_smooth=True
        for i in poly.loop_indices:
            local=adjacent[mesh.loops[i].vertex_index]
            avg=sum((n*angle for n,angle in local if n.dot(poly.normal)>.70),Vector())
            normals[i]=tuple(avg.normalized()) if avg.length_squared else tuple(poly.normal)
    mesh.normals_split_custom_set(normals)




def local_rings(artist, centre, right, up, profiles, bands, caps, smooth=False):
    u, v = Vector(right).normalized(), Vector(up).normalized()
    n = u.cross(v).normalized()
    rings=[]
    for depth,xz in profiles:
        rings.append([Vector(centre)+u*x+v*z+n*depth for x,z in xz])
    first=len(artist.faces)
    artist.rings(rings,bands,caps)
    if smooth:
        artist.smooth_faces.extend(range(first+1,len(artist.faces)-1))


def octagon(hw,hh,clip):
    return [(-hw+clip,-hh),(hw-clip,-hh),(hw,-hh+clip),(hw,hh-clip),
            (hw-clip,hh),(-hw+clip,hh),(-hw,hh-clip),(-hw,-hh+clip)]


def circle(rx,rz,n=16):
    return [(rx*cos(2*pi*i/n),rz*sin(2*pi*i/n)) for i in range(n)]


def temple_and_optic(k, surface):
    armor=Assembly(k,"orbital_implant_and_helmet_pads")
    metal=k.gunmetal
    dark=k.mat("Optic • graphite insulator",(.015,.016,.019),.38,.39)
    enamel=k.mat("Optic • oxide red enamel",(.30,.028,.015),.55,.36)
    lamp=k.mat("ocular_vermilion",(.83,.027,.008),.19,.24,1.20)
    glass=k.mat("Optic • ruby objective",(.48,.021,.008),.20,.18,.36)
    hot=k.mat("Optic • hot glass",(.99,.30,.09),.11,.17,1.38)
    for side in (-1,1):
        # Original padded ear defenders, with an exposed communication hinge.
        u=(0,side,0)
        local_rings(armor,(side*122,0,145),u,(0,0,1),
            [(-3,octagon(48,42,13)),(8,octagon(50,42,12)),(15,octagon(44,36,12))],
            lambda j,i:k.leather,(k.leather,k.leather))
        local_rings(armor,(side*136,-10,140),u,(0,0,1),
            [(0,circle(26,26)),(4,circle(27,27)),(7,circle(24,24)),
             (8,circle(18.5,18.5)),(6,circle(15,15))],
            lambda j,i:(dark,metal,k.blacksteel,k.steel)[j],(dark,k.blacksteel))

    plate(armor,surface,[(-15,156),(-26,176),(-68,188),(-98,180),
                         (-110,158),(-102,138),(-80,119),(-53,117),(-29,134)],
          k.blacksteel,5,metal,2.5)
    # Build every optical surface about the same tilted axis. The outer steel
    # flange sits under the helmet; the annular lamp and bore sit inside it.
    centre=(-62,-139,152)
    u=Vector((1,-.27,0)).normalized()
    v=Vector((0,0,1))
    axis=u.cross(v)
    local_rings(armor,centre,u,v,[
        (-15,circle(38,38,56)),(-2,circle(40,40,56)),(3,circle(39,39,56)),
        (5,circle(35.5,35.5,56)),(9,circle(34,34,56)),(11,circle(28.5,28.5,56))],
        lambda j,i:(dark,metal,k.steel,k.blacksteel,metal)[j],(dark,dark),smooth=True)
    for a in range(0,360,60):
        angle=(a+18)*pi/180
        p=Vector(centre)+axis*5+36*(cos(angle)*u+sin(angle)*v)
        local_rings(armor,p,u,v,[(0,circle(2.1,2.1,8)),(1.8,circle(1.8,1.8,8))],
                    lambda j,i:k.steel,(metal,k.steel))
    armor.finish()

    lens=Assembly(k,"eye_lens_rig")
    # The ruby objective bulges forward of a recessed black retaining ring.
    # The change in curvature reflects the portrait lights across the glass.
    profile=[(27.8,10.7),(26.8,11.8),(25.2,12.1),(23.1,12.2),(21.6,11.8),
             (19.1,11.7),(18.5,12.3),(17.8,13.3),(15.7,15.9),(12.7,17.9),
             (9.2,19.4),(6.4,20.2),(3.4,20.7),(1,20.9)]
    coatings=[enamel,lamp,lamp,enamel,dark,metal,dark,glass,glass,lamp,lamp,hot,hot]
    local_rings(lens,centre,u,v,[(d,circle(r,r,64)) for r,d in profile],
                lambda j,i:coatings[j],(dark,hot),smooth=True)
    lens.finish()


def natural_eye(artist,surface,eye,iris,pupil):
    # A convex exposed eye sits under the existing metal lids. Intersect the
    # iris with the aperture so its upper edge actually disappears under the brow.
    def bounds(x):
        t=max(0.,min(1.,(x-33.)/61.))
        arc=max(0.,sin(pi*t))**.78
        middle=151.1+11.7*t
        return middle-7.45*arc,middle+7.8*arc
    def on_eye(x,z,offset=0):
        lo,hi=bounds(x)
        z=max(lo,min(hi,z))
        h=2*(z-lo)/max(.001,hi-lo)-1
        bulge=5.6*max(0,sin(pi*(x-33)/61))**.76*max(0,1-h*h)
        return (x,surface(x,z)-6.9-bulge-offset,z)

    verts=[on_eye(33,151.1)]
    faces=[]
    columns=28
    rows=8
    for col in range(1,columns):
        x=33+61*col/columns
        lo,hi=bounds(x)
        verts.extend(on_eye(x,lo+(hi-lo)*j/rows) for j in range(rows+1))
    tip=len(verts)
    verts.append(on_eye(94,162.8))
    for j in range(rows):
        faces.append((0,1+j,2+j))
        faces.append((tip,tip-rows+j,tip-rows+j-1))
    for col in range(columns-2):
        for j in range(rows):
            a=1+col*(rows+1)+j
            faces.append((a,a+rows+1,a+rows+2,a+1))
    first=len(artist.faces)
    artist.solid(verts,faces,eye)
    artist.smooth_faces.extend(range(first,len(artist.faces)))

    def disc(cx,cz,profile,materials):
        vs=[]
        fs=[]
        mats=[]
        count=40
        for radius,depth in profile:
            for i in range(count):
                a=2*pi*i/count
                vs.append(on_eye(cx+radius*cos(a),cz+1.06*radius*sin(a),depth))
        for row,mat in enumerate(materials[:-1]):
            for i in range(count):
                j=(i+1)%count
                a=row*count
                fs.append((a+i,a+j,a+count+j,a+count+i))
                mats.append(mat)
        centre=len(vs)
        vs.append(on_eye(cx,cz,profile[-1][1]+.015))
        for i in range(count):
            fs.append((centre-count+i,centre-count+(i+1)%count,centre))
            mats.append(materials[-1])
        first=len(artist.faces)
        artist.solid(vs,fs,mats)
        artist.smooth_faces.extend(range(first,len(artist.faces)))
    disc(59.5,157.3,[(8.2,.22),(7.55,.39),(5,.56),(3.45,.65),(2.85,.69)],
         [pupil,iris,iris,pupil,pupil])
    disc(57.25,159.6,[(.95,.90),(.64,1.02)],[eye,eye])


def nose_bridge(artist,surface,cast,shadow):
    # Round the center ridge and tip while preserving the pressed side planes.
    profiles=[(194,3,-.65),(186,4.3,.4),(178,6.2,1.3),(171,7.4,2.8),
              (162,8.1,4.5),(149,9.0,5.7),(137,10.2,6.9),
              (126,11.2,7.8),(116,12.7,8.1),(110,15.3,7.1),(106,16,4.8),
              (103.5,13.9,4.0),(100.5,8.4,2.7),(98.5,3.2,-.4)]
    fractions=(-1,-.90,-.56,-.21,0,.21,.56,.90,1)
    verts=[]
    faces=[]
    mats=[]
    for z,w,depth in profiles:
        mid=surface(0,z)-depth
        side=surface(w,z)+.32
        for t in fractions:
            x=w*t
            y=min(mid+(side-mid)*abs(t)**1.57,surface(x,z)+.32)
            verts.append((x,y,z))
    stride=len(fractions)
    for r in range(len(profiles)-1):
        for i in range(stride-1):
            a=r*stride+i
            faces.append((a,a+stride,a+stride+1,a+1))
            mats.append(cast if profiles[r][0]>104 else shadow)
    first=len(artist.faces)
    artist.solid(verts,faces,mats)
    artist.smooth_faces.extend(range(first,len(artist.faces)))


def build(k):
    artist=Assembly(k,"sculpted_head")
    cast=k.mat("Face • satin ivory alloy",(.53,.415,.315),.39,.45)
    polished=k.mat("Face • honed cheek edges",(.59,.49,.39),.54,.38)
    shadow=k.mat("Face • recessed bronze cast",(.245,.183,.143),.48,.51)
    seam=k.mat("Face • joint gasket",(.016,.016,.018),.13,.62)
    eye=k.mat("Eye • sclera",(.66,.61,.53),.02,.28)
    iris=k.mat("Eye • smoke amber",(.14,.086,.044),.09,.24)
    pupil=k.mat("Eye • pupil",(.011,.010,.011),.02,.22)
    chassis=k.mat("Face • graphite jaw casting",(.093,.089,.086),.51,.46)
    surface,skin_rings=face_skin(artist,cast,chassis,k.leather)
    finish_face(artist)

    jaw=Assembly(k,"mandible_cheeks_and_chin")
    for side in (-1,1):
        def cheek(outline, mat, lift, edge=None, bevel=1.5):
            plate(jaw,surface,[(side*x,z) for x,z in outline],mat,lift,edge,bevel)
        # Cheek shield with a pressed lower return, a slender shadow break
        # at the masseter and an articulated outer rail fading into the chin.
        cheek([(31,123),(50,137),(89,143),(103,131),(83,115),
               (56,93),(49,83),(52,103)],cast,4.6,polished,1.6)
        cheek([(107,138),(116,128),(113,106),(102,87),(85,66),(72,39),
               (49,21),(61,41),(72,69),(91,91),(101,111)],seam,6.5,bevel=.8)
        cheek([(114,127),(121,119),(113,96),(96,73),(81,42),(53,18),
               (67,39),(77,67),(96,91),(108,113)],shadow,8.2,k.gunmetal,1.8)
        cheek([(110,107),(113,106),(114,103),(112,101),(109,102),(108,105)],
              k.steel,10.4,bevel=.45)
        # A secondary link emerges from the cheek hinge and passes beneath
        # the rail. The axis of the pin follows the curved side of the jaw.
        cheek([(113,99),(118,93),(113,79),(95,63),(78,39),(69,32),
               (80,53),(94,72),(105,83)],k.gunmetal,4.1,k.blacksteel,1.1)
        x,z=side*112,94
        slope=(surface(x+1,z)-surface(x-1,z))/2
        tangent=(1,slope,0)
        local_rings(jaw,(x,surface(x,z),z),tangent,(0,0,1),
                    [(1,circle(9.3,9.3,16)),(4,circle(9.7,9.7,16)),(5.5,circle(8.2,8.2,16)),
                     (6,circle(5.4,5.4,16)),(5.2,circle(3.6,3.6,16))],
                    lambda j,i:(seam,k.gunmetal,k.steel,k.blacksteel)[j],(seam,k.blacksteel))
    # A dark, lightly downturned articulation line replaces the flesh lips.
    plate(jaw,surface,[(-43,54),(-34,60),(-16,65),(0,64),(16,65),(34,60),
                       (43,54),(29,57),(12,60),(0,59),(-15,60),(-30,57)],seam,3.7,bevel=.65)
    plate(jaw,surface,[(-30,53),(-14,57),(13,57),(30,53),(18,50),(0,48),(-17,50)],
          cast,3.7,shadow,.85)
    # The chin is independently cast around a recessed four-rib breather.
    plate(jaw,surface,[(-46,30),(-33,40),(31,40),(46,31),(40,13),
                       (25,5),(-24,5),(-40,13)],k.blacksteel,5.1,seam,2)
    for x in (-23,-8,8,23):
        drop=2 if abs(x)>15 else 0
        plate(jaw,surface,[(x-5.7,29-drop),(x-4,35-drop),(x+3.8,35-drop),(x+5.3,30-drop),
                           (x+4.0,12+drop),(x+1,8+drop),(x-4.5,12+drop)],
              k.gunmetal,8.5,k.steel,1.05)
    plate(jaw,surface,[(-42,28),(-32,40),(31,40),(43,30),(37,30),(28,35),(-28,35),(-37,27)],
          k.gunmetal,8.8,k.steel,1)
    jaw.finish()

    bridge=Assembly(k,"brow_and_bridge")
    nose_bridge(bridge,surface,cast,shadow)
    for s in (-1,1):
        plate(bridge,surface,[(s*10,98),(s*18,102),(s*23,101),(s*19,97),(s*13,95)],
              seam,2,bevel=.55)

    plate(bridge,surface,[(24,149),(37,166),(77,174),(102,169),(92,152),(71,142),(48,142)],
          seam,5.3,k.blacksteel,1.4)
    natural_eye(bridge,surface,eye,iris,pupil)
    plate(bridge,surface,[(21,153),(27,173),(83,185),(105,176),(87,164),(45,156)],
          k.blacksteel,10.2,seam,1.2)
    plate(bridge,surface,[(23,159),(29,176),(82,187),(104,178),(85,169),(42,160)],
          cast,13,polished,2)
    plate(bridge,surface,[(36,145),(49,147),(67,145),(94,155),(83,146),(63,140),(47,140)],
          cast,5.9,shadow,1.4)
    bridge.finish()
    nape_guard(k,skin_rings)
    build_helmet(k,_world)
    temple_and_optic(k,surface)
