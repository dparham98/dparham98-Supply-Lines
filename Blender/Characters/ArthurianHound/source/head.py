"""Canine head, swept helmet and lit visor for the Round Table hound.

The figure faces -Y. The head pivots as a single rigid assembly around its
neck joint. Units are metres.
"""
from math import asin, cos, exp, pi, sin
import bpy
from mathutils import Vector

import kit


GROUP = "Head"


def form(name, rings, material, bevel=.003):
    """Loft equal sized polygonal rings in head coordinates."""
    n=len(rings[0])
    vertices=[p for ring in rings for p in ring]
    faces=[tuple(reversed(range(n)))]
    faces += [(j*n+i,j*n+(i+1)%n,(j+1)*n+(i+1)%n,(j+1)*n+i)
              for j in range(len(rings)-1) for i in range(n)]
    faces.append(tuple(range((len(rings)-1)*n,len(rings)*n)))
    return kit.mesh(name,vertices,faces,material,GROUP,bevel)


def ears():
    # Each ear is a single cupped shell. The recessed center and raised
    # perimeter are continuous geometry, so they remain attached while the
    # ear turns around its root. The brown inner cartilage is flush with the
    # surrounding dark rim and the rear of the shell is fully closed.
    cross=(-1.,-.88,-.73,-.52,-.26,0.,.26,.52,.73,.88,1.)
    # Height, half width, outward sweep, center Y, cup depth, rear thickness.
    sections=[
        (1.354,.050,-.005,-.706,.009,.032),
        (1.378,.058,-.004,-.707,.016,.034),
        (1.407,.060,-.001,-.702,.023,.032),
        (1.447,.057,.002,-.695,.025,.028),
        (1.488,.058,.006,-.683,.023,.024),
        (1.531,.046,.011,-.668,.018,.019),
        (1.572,.032,.016,-.652,.012,.014),
        (1.610,.017,.020,-.636,.006,.009),
        (1.640,.002,.022,-.620,.001,.004),
    ]
    for side in (-1,1):
        joint="Ear.L" if side>0 else "Ear.R"
        vertices=[]
        n=len(cross)
        for rear in (False,True):
            for z,width,sweep,y,depth,thickness in sections:
                for t in cross:
                    # Cup faces forward, with dark rolled edges raised toward
                    # the viewer. The back rounds around the same silhouette.
                    x=side*(.108+sweep)+width*t
                    if rear:
                        py=y+thickness*(1-t*t)**.5
                    else:
                        py=y+depth*(1-t*t)-.0015
                    vertices.append((x,py+side*t*width*.34,z))
        count=n*len(sections)
        faces=[]
        indices=[]
        for row in range(len(sections)-1):
            for col in range(n-1):
                a=row*n+col
                faces.append((a,a+1,a+n+1,a+n))
                # Five central columns form the warm inner bowl; the two
                # border bands are the raised charcoal cartilage.
                indices.append(1 if 2<=col<n-3 and row>=1 else 0)
                a+=count
                faces.append((a+n,a+n+1,a+1,a))
                indices.append(0)
        for row in range(len(sections)-1):
            for col in (0,n-1):
                a=row*n+col
                b=(row+1)*n+col
                faces.append((a,b,b+count,a+count))
                indices.append(0)
        for col in range(n-1):
            a=col
            faces.append((a+1,a,a+count,a+count+1))
            indices.append(0)
            a=(len(sections)-1)*n+col
            faces.append((a,a+1,a+count+1,a+count))
            indices.append(0)
        obj=kit.mesh("Ear | cupped cartilage",vertices,faces,"fur",joint,0)
        obj.data.materials.append(kit.material("muzzle"))
        for polygon,mat in zip(obj.data.polygons,indices):
            polygon.material_index=mat
            polygon.use_smooth=True

        # A continuous rolled lip follows each edge and tapers into the
        # point, giving the cup a tangible thickness in the portrait.
        for sign in (-1,1):
            centers=[Vector((side*(.108+sweep)+sign*width,y-.0015+side*sign*width*.34,z))
                     for z,width,sweep,y,depth,thickness in sections]
            rim=[]
            for row,centre in enumerate(centers):
                tangent=(centers[min(row+1,len(centers)-1)]-
                         centers[max(row-1,0)]).normalized()
                u=tangent.cross(Vector((0,1,0))).normalized()
                v=tangent.cross(u).normalized()
                radius=.0035*(1-.55*row/(len(centers)-1))
                rim.extend(centre+radius*(u*cos(2*pi*i/8)+v*sin(2*pi*i/8))
                           for i in range(8))
            faces=[(r*8+i,r*8+(i+1)%8,(r+1)*8+(i+1)%8,(r+1)*8+i)
                   for r in range(len(centers)-1) for i in range(8)]
            lip=kit.mesh("Ear | rolled outer lip",rim,faces,"black",joint,0)
            for polygon in lip.data.polygons:
                polygon.use_smooth=True


def helmet():
    # The wide, sculpted brow is below the shell. Each ring is formed with a
    # fixed-width axial stripe, continuous over the crown and down the back.
    levels=[(1.290,.153,.155,-.703),(1.325,.156,.158,-.703),
            (1.360,.153,.155,-.703),(1.395,.142,.143,-.699),
            (1.426,.122,.124,-.695),(1.451,.092,.096,-.690),
            (1.468,.055,.061,-.687),(1.476,.023,.026,-.686)]
    arcs=7
    rings=[]
    for z,rx,ry,cy in levels:
        cut=asin(min(.96,.031/rx))
        quarter=[0,cut]+[cut+(pi/2-cut)*i/(arcs-1) for i in range(1,arcs)]
        angles=(quarter[:-1]+[pi-a for a in reversed(quarter[1:])]
                +[pi+a for a in quarter[:-1]]+[2*pi-a for a in reversed(quarter[1:])])
        rings.append([(rx*sin(a),cy-ry*cos(a),z) for a in angles])
    count=len(rings[0])
    verts=[p for r in rings for p in r]
    # The two stripe slivers at front and rear become a single top band.
    stripe={0,2*arcs-1,2*arcs,4*arcs-1}
    faces=[]
    indices=[]
    faces.append(tuple(reversed(range(count))))
    indices.append(0)
    for j in range(len(rings)-1):
        for i in range(count):
            faces.append((j*count+i,j*count+(i+1)%count,(j+1)*count+(i+1)%count,(j+1)*count+i))
            indices.append(1 if i in stripe and j>=1 else 0)
    faces.append(tuple(range((len(rings)-1)*count,len(rings)*count)))
    indices.append(1)
    obj=kit.mesh("Helmet | shell and blue axial stripe",verts,faces,"white",GROUP,0)
    obj.data.materials.append(kit.material("team_color"))
    for face,mat in zip(obj.data.polygons,indices):
        face.material_index=mat
        if len(face.vertices)==4:
            face.use_smooth=True

    # Side flaps turn down over the temple behind the eyes.
    for s in (-1,1):
        v=[(s*.143,-.767,1.328),(s*.158,-.706,1.331),
           (s*.148,-.655,1.292),(s*.118,-.645,1.244),
           (s*.119,-.716,1.243),(s*.146,-.762,1.278)]
        vv=v+[(x-s*.008,y,z) for x,y,z in v]
        n=len(v)
        f=[tuple(range(n)),tuple(reversed(range(n,n*2)))]
        f += [(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)]
        kit.mesh("Helmet | lower side guard",vv,f,"white",GROUP,.003)
        kit.rod("Helmet | dark hinge", (s*.150,-.690,1.303),(s*.166,-.690,1.303),.027,"black",GROUP,20,.002)
        kit.rod("Helmet | steel hinge", (s*.163,-.690,1.303),(s*.172,-.690,1.303),.021,"steel",GROUP,20,.001)
        kit.rod("Helmet | hinge inset", (s*.171,-.690,1.303),(s*.174,-.690,1.303),.014,"white",GROUP,20,.001)

    # The visor is a closed faceted plate just underneath the brow. Its center
    # sits above the bridge of the snout and the ends meet the hinge guards.
    angles=[-pi/2+i*pi/24 for i in range(25)]
    def brow(a,z,depth):
        return ((.151+depth)*sin(a),-.703-(.169+depth)*cos(a),z+.018*abs(sin(a)))
    upper=[brow(a,1.315,.005) for a in angles]
    lower=[brow(a,1.271+.018*abs(sin(a)),.006) for a in angles]
    white_verts=upper+lower
    n=len(angles)
    kit.mesh("Visor | ivory face plate",white_verts,
             [(i,i+1,n+i+1,n+i) for i in range(n-1)],"white",GROUP,0)

    # One continuous swept rail avoids visible joins between brow segments.
    def swept(label,z,depth,radius,material):
        rings=[]
        for a in angles:
            centre=Vector(brow(a,z,depth))
            outward=Vector((sin(a),-cos(a),0))
            rings.append([centre+radius*(outward*cos(2*pi*k/10)+Vector((0,0,sin(2*pi*k/10))))
                          for k in range(10)])
        form(label,rings,material,0)
    swept("Visor | dark brow gasket",1.321,.008,.009,"joint")
    swept("Visor | continuous gold brow",1.321,.011,.0065,"gold")
    swept("Visor | warm luminous band",1.320,.017,.0028,"glow")


def coated_mesh(name, vertices, faces, colors, finish):
    material = bpy.data.materials.new(name)
    material.use_nodes = True
    material.diffuse_color = tuple(colors[0]) + (1,)
    bsdf = material.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Roughness"].default_value = finish
    tint = material.node_tree.nodes.new("ShaderNodeVertexColor")
    tint.layer_name = "Coat"
    material.node_tree.links.new(tint.outputs["Color"], bsdf.inputs["Base Color"])
    obj = kit.mesh(name, vertices, faces, material, GROUP)
    attribute = obj.data.color_attributes.new(name="Coat", type='BYTE_COLOR', domain='POINT')
    for swatch, rgb in zip(attribute.data, colors):
        swatch.color_srgb = (*rgb, 1)
    for face in obj.data.polygons:
        face.use_smooth = True
    return obj


def sable_mask():
    # Row stations follow the nasal bone, brow stop, cheek arch and occiput.
    # The lip line turns up behind the whisker pad and falls back under the cheek.
    stations = [
        (-1.064,.041,1.200,1.151,1.130), (-1.037,.058,1.208,1.144,1.114),
        (-1.002,.072,1.217,1.136,1.102), (-.955,.085,1.236,1.138,1.093),
        (-.905,.096,1.250,1.147,1.089), (-.868,.104,1.268,1.159,1.089),
        (-.837,.108,1.295,1.164,1.086), (-.807,.116,1.329,1.157,1.081),
        (-.770,.128,1.353,1.138,1.067), (-.718,.141,1.379,1.124,1.050),
        (-.660,.142,1.378,1.118,1.049), (-.605,.125,1.345,1.119,1.065),
        (-.556,.087,1.294,1.148,1.098), (-.528,.047,1.251,1.156,1.133),
    ]
    verts, colors, faces = [], [], []
    def mix(a, b, amount):
        return tuple(u+(v-u)*amount for u,v in zip(a,b))
    for y, width, top, lip, chin in stations:
        h = top-lip
        # The fuller upper lip turns inward at the seam before reaching the chin.
        section = [(0, top), (.40,top-.035*h), (.72,top-.14*h), (.91,top-.34*h),
                   (.992,top-.59*h), (1.015,lip+.15*h), (.992,lip+.003),
                   (.951,lip-.001), (.928,lip-.004), (.949,lip-.007),
                   (.91,lip-.011), (.81,chin+.38*(lip-chin)), (.49,chin+.09*(lip-chin)),
                   (0,chin)]
        circuit = section + [(-x,z) for x,z in reversed(section[1:-1])]
        width_count = len(circuit)
        for j,(x,z) in enumerate(circuit):
            # A black-and-rust Doberman mask darkens over the nasal bridge and
            # disappears under the helmet towards the throat.
            key = min(1.,max(0.,(-y-.740)/.185 + .15*abs(x) - .23*(z-lip)/h))
            tone = mix((.175,.201,.229),(.391,.290,.263),key)
            row_index = min(j,width_count-j)
            if row_index in (7,8,9):
                crease = min(1.,max(0.,(-y-.775)/.065))
                tone = mix(tone,(.071,.056,.059),crease*(.98 if row_index==8 else .62))
            if row_index>=10:
                tone = mix(tone,(.190,.153,.148),key*.69)
            verts.append((width*x,y,z))
            colors.append(tone)
    for i in range(len(stations)-1):
        for j in range(width_count):
            a=i*width_count+j
            b=i*width_count+(j+1)%width_count
            faces.append((a,b,b+width_count,a+width_count))
    faces.extend([tuple(reversed(range(width_count))),tuple(range(len(verts)-width_count,len(verts)))])
    coated_mesh("Head | sable mask and flews",verts,faces,colors,.79)

    for side in (-1,1):
        # Small whisker roots and a slim lid under the visor add scale up close.
        for x,y,z in [(.094,-.911,1.172),(.088,-.934,1.165),(.084,-.953,1.163),
                      (.083,-.948,1.177),(.089,-.929,1.180)]:
            kit.ellipsoid("Muzzle | whisker root",(side*x,y,z),(.0021,.0027,.0021),"muzzle",GROUP,8,5)
        kit.ellipsoid("Eye | orbital rim",(side*.115,-.786,1.273),(.011,.024,.011),"black",GROUP,24,12)
        kit.ellipsoid("Eye | dark amber iris",(side*.125,-.792,1.272),(.0026,.007,.005),"leather",GROUP,16,8)


def nose_leather():
    # A single rounded triangular plane folds around the bridge. Both nares
    # are concave and shaded along the wing, with a shallow median groove.
    vertices, colors, faces = [], [], []
    count, rings = 64, 14
    def sample(dx,dz,r):
        u = dx*(.91+.19*dz)
        v = dz - .15*(1-dz*dz)*(1-abs(dx))**2
        nostril = exp(-((abs(dx)-.49)/.25)**2 - ((dz-.12-.30*(abs(dx)-.49))/.205)**2)
        groove = exp(-(dx/.075)**2)*max(0.,-dz)
        y = -1.068 - .025*(1-r*r) - .008*dz + .012*nostril + .004*groove
        shade = .145+.027*dz-.081*nostril-.035*groove
        return (.065*u,y,1.182+.039*v), (shade*.91,shade*.94,shade)
    p,c=sample(0,0,0)
    vertices.append(p)
    colors.append(c)
    for row in range(1,rings+1):
        r=row/rings
        for i in range(count):
            angle=2*pi*i/count
            p,c=sample(r*cos(angle),r*sin(angle),r)
            vertices.append(p)
            colors.append(c)
    for i in range(count):
        faces.append((0,1+i,1+(i+1)%count))
    for row in range(rings-1):
        for i in range(count):
            a=1+row*count+i
            b=1+row*count+(i+1)%count
            faces.append((a,b,b+count,a+count))
    first=1+(rings-1)*count
    tail=len(vertices)
    for i in range(count):
        x,y,z=vertices[first+i]
        vertices.append((x*.93,-1.043,1.182+(z-1.182)*.87))
        colors.append(colors[first+i])
        faces.append((first+i,first+(i+1)%count,tail+(i+1)%count,tail+i))
    faces.append(tuple(range(tail,tail+count)))
    coated_mesh("Head | nose leather",vertices,faces,colors,.43)


def build():
    sable_mask()
    nose_leather()
    ears()
    helmet()
