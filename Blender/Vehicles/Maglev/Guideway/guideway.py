"""Cross sections and hardware shared by the four maglev pieces. Blender metres; forward -Y."""
from math import ceil, cos, sin
import bpy


class Path:
    """Map distance along a piece, lateral offset and height to Blender XYZ."""
    def __init__(self, turn=0, length=8):
        self.turn = turn
        self.length = length

    def at(self, s, u, z):
        if not self.turn:
            return (u, -s, z)
        radius = 20.0
        angle = s / radius
        return (
            self.turn * radius * (1 - cos(angle)) + u * cos(angle),
            -radius * sin(angle) + self.turn * u * sin(angle),
            z,
        )


PALETTE = {
    'bed':   ('Cast aggregate', (.207,.205,.185), .02,.89),
    'edge':  ('Basalt facing', (.093,.105,.111), .12,.75),
    'iron':  ('Guideway graphite', (.047,.055,.060), .43,.52),
    'steel': ('Burnished guide rail', (.34,.367,.375), .71,.36),
    'pad':   ('Induction ceramic', (.061,.092,.107), .30,.52),
    'alloy': ('Contact bronze', (.283,.164,.089), .60,.46),
    'amber': ('Ochre inspection paint', (.54,.305,.073), .09,.64),
}


def material(key):
    name,col,metallic,roughness=PALETTE[key]
    name='Rail / '+name
    mat=bpy.data.materials.get(name)
    if mat is None:
        mat=bpy.data.materials.new(name)
        mat.use_nodes=True
    mat.diffuse_color=(*col,1)
    shader=mat.node_tree.nodes['Principled BSDF']
    shader.inputs['Base Color'].default_value=(*col,1)
    shader.inputs['Metallic'].default_value=metallic
    shader.inputs['Roughness'].default_value=roughness
    return mat


class Builder:
    """Accumulate editable mesh islands into one exported object per runtime part."""
    def __init__(self):
        self.verts,self.faces,self.materials=[],[],[]

    def add(self, verts, faces, mat):
        first = len(self.verts)
        self.verts.extend(verts)
        self.faces.extend(tuple(first + index for index in face) for face in faces)
        self.materials.extend([mat] * len(faces) if isinstance(mat, str) else mat)

    def face(self,verts,mat):
        self.add(verts,[tuple(range(len(verts)))],mat)

    def sweep(self, path, s0, s1, profile, materials, cap=None, step=1.31):
        """Sweep a CCW transverse profile. Even sampling preserves the analytical ends."""
        if s1 - s0 < 1e-5:
            return
        width = len(profile)
        count = max(1, ceil((s1 - s0) / step)) if path.turn else 1
        sides = [materials] * width if isinstance(materials, str) else materials
        cap = cap or sides[0]
        verts = [path.at(s0 + (s1 - s0) * j / count, u, z)
                 for j in range(count + 1) for u, z in profile]
        faces = [tuple(reversed(range(width))), tuple(range(count * width, (count + 1) * width))]
        face_materials = [cap, cap]
        for j in range(count):
            start = j * width
            end = (j + 1) * width
            for i in range(width):
                k = (i + 1) % width
                faces.append((start + i, start + k, end + k, end + i))
                face_materials.append(sides[i])
        self.add(verts, faces, face_materials)

    def block(self,path,s0,s1,u0,u1,z0,z1,mat,cut=.05,bevel=.025):
        """Low chamfered tile; values u0 and u1 are signed lateral bounds."""
        u0,u1=sorted((u0,u1))
        if min(s1-s0,u1-u0,z1-z0)<1e-6: return
        bevel=min(bevel,.29*(u1-u0),.29*(s1-s0),.75*(z1-z0))
        def course(inset,z):
            l,r=u0+inset,u1-inset
            a,b=s0+inset,s1-inset
            c=max(0,min(cut,(b-a)*.46,(r-l)*.46))
            contour=[(l+c,a),(l,a+c),(l,b-c),(l+c,b),(r-c,b),(r,b-c),(r,a+c),(r-c,a)]
            if c<1e-7: contour=[(l,a),(l,b),(r,b),(r,a)]
            return [path.at(s,u,z) for u,s in contour]
        rings=[course(0,z0),course(0,z1-bevel),course(bevel,z1)] if bevel else [course(0,z0),course(0,z1)]
        n=len(rings[0])
        faces=[tuple(reversed(range(n))),tuple(range((len(rings)-1)*n,len(rings)*n))]
        for j in range(len(rings)-1):
            for i in range(n):
                k=(i+1)%n
                faces.append((j*n+i,j*n+k,(j+1)*n+k,(j+1)*n+i))
        self.add([v for row in rings for v in row],faces,mat)

    def inlay(self,path,s0,s1,u0,u1,z,mat):
        """A thin marking on an existing flat face needs only its visible surface."""
        left,right=sorted((u0,u1))
        self.face([path.at(s0,left,z),path.at(s1,left,z),
                   path.at(s1,right,z),path.at(s0,right,z)],mat)


def install(obj,builder,offset=(0,0,0)):
    """Relink preview instances sharing the old mesh as well as the exported root."""
    old=obj.data
    mesh=bpy.data.meshes.new(obj.name+' / guideway')
    dx,dy,dz=offset
    verts=[(x-dx,y-dy,z-dz) for x,y,z in builder.verts]
    mesh.from_pydata(verts,[],builder.faces)
    keys = dict.fromkeys(builder.materials)
    material_index = {key: index for index, key in enumerate(keys)}
    for key in keys:
        mesh.materials.append(material(key))
    for poly, key in zip(mesh.polygons, builder.materials, strict=True):
        poly.material_index = material_index[key]
    mesh.update()
    name=old.name
    old.user_remap(mesh)
    bpy.data.meshes.remove(old)
    mesh.name=name


def deck(b,path,s0,s1):
    # The staggered reveals run through the slab but leave a continuous dark sub-base.
    b.sweep(path,s0,s1,[(-2.12,.01),(2.12,.01),(2.20,.08),(2.20,.17),
                         (2.12,.215),(-2.12,.215),(-2.20,.17),(-2.20,.08)],'edge')
    sections=max(1,round((s1-s0)/4))
    for i in range(sections):
        a=s0+(s1-s0)*i/sections+.027
        end=s0+(s1-s0)*(i+1)/sections-.027
        b.sweep(path,a,end,[(-2.20,.125),(2.20,.125),(2.32,.20),(2.32,.262),
                          (2.22,.325),(-2.22,.325),(-2.32,.262),(-2.32,.20)],
                ['edge','edge','bed','bed','bed','bed','bed','edge'],cap='edge')


def guide(b,path,s0,s1,side):
    # Pair of continuous bearing rails with a broad worn face and a darker outer rim.
    base=[(1.265,.297),(1.914,.297),(1.914,.384),(1.823,.443),(1.797,.683),
          (1.734,.790),(1.454,.790),(1.386,.702),(1.355,.431),(1.265,.374)]
    cap=[(1.391,.760),(1.791,.760),(1.812,.822),(1.788,.912),(1.733,.928),
         (1.468,.928),(1.396,.899),(1.371,.822)]
    def profile(points,materials):
        if side>0: return points,materials
        mirrored=[(-u,z) for u,z in reversed(points)]
        return mirrored,[materials[(len(points)-2-i)%len(points)] for i in range(len(points))]
    pts,mats=profile(base,['iron','edge','edge','iron','iron','iron','iron','iron','edge','edge'])
    b.sweep(path,s0,s1,pts,mats,cap='iron')
    pts,mats=profile(cap,['iron','iron','edge','steel','steel','steel','edge','iron'])
    b.sweep(path,s0,s1,pts,mats,cap='edge')


def pad(b,path,s0,s1):
    """Inset induction cassette with dark ceramic crown and its two bronze contacts."""
    b.block(path,s0,s1,-.495,.495,.298,.419,'iron',cut=.119,bevel=0)
    b.block(path,s0+.09,s1-.09,-.393,.393,.409,.496,'pad',cut=.081,bevel=.033)
    for side in (-1,1):
        b.inlay(path,s0+.22,s1-.22,side*.29,side*.345,.499,'alloy')


def outrigger(b,path,s,side):
    """Shoulder anchor with a recessed keeper; kept below the rail contact face."""
    def anchor(a,c,u,v,z0,z1,mat,cut,bevel):
        b.block(path,s+a,s+c,side*u,side*v,z0,z1,mat,cut,bevel)
    anchor(-.42,.42,1.73,2.475,.015,.258,'edge',.105,.047)
    anchor(-.255,.255,1.712,2.30,.249,.398,'iron',.064,0)
    anchor(-.142,.142,1.741,2.095,.389,.469,'steel',.050,.022)
    anchor(-.083,.083,2.12,2.257,.390,.436,'alloy',.030,0)


def status(b,path,s,side=-1):
    """Black gasket and a cast-in status window. The game supplies the lit glass."""
    u=side*2.095
    b.block(path,s-.735,s+.735,u-.32,u+.32,.10,.394,'edge',cut=.110,bevel=.046)
    b.block(path,s-.655,s+.655,u-.285,u+.285,.385,.502,'iron',cut=.080,bevel=.026)
    b.block(path,s-.552,s+.552,u-.244,u+.244,.496,.536,'pad',cut=.040,bevel=.010)
    for a in (-.60,.60):
        b.inlay(path,s+a-.021,s+a+.021,u-.18,u+.18,.505,'amber')


def lane(b,path):
    total=path.length
    deck(b,path,0,total)
    for side in (-1,1): guide(b,path,0,total,side)
    # End clearances make the same hardware rhythm continue through snapped joints.
    count=max(2,round(total/2))
    pitch=total/count
    for i in range(count):
        mid=(i+.5)*pitch
        pad(b,path,mid-pitch*.413,mid+pitch*.413)
    for i in range(max(1,round(total/4))):
        mid=(i+.5)*total/max(1,round(total/4))
        for side in (-1,1): outrigger(b,path,mid,side)
    status(b,path,total*.5,-1)
