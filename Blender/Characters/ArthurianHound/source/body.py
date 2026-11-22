"""Armor, anatomy and leg fittings for the Round Table's armored hound.

Coordinates are metres in the bind pose. Negative Y points forward.
Every piece carries a joint name for the exporter to skin rigidly.
"""
from math import cos, pi, sin
import bpy
import kit
from mathutils import Vector


def mesh(name, vertices, faces, material, joint):
    data = bpy.data.meshes.new(name)
    data.from_pydata(vertices, [], faces)
    data.update()
    obj = bpy.data.objects.new(name, data)
    bpy.context.scene.collection.objects.link(obj)
    data.materials.append(material)
    obj["joint"] = joint
    return obj


def ellipsoid(name, center, radii, material, joint, segments=12, rings=7):
    center = Vector(center)
    rx, ry, rz = radii
    vertices = [tuple(center + Vector((0, 0, -rz)))]
    for row in range(1, rings):
        phi = -pi / 2 + pi * row / rings
        for i in range(segments):
            angle = 2 * pi * i / segments
            vertices.append(tuple(center + Vector((rx*cos(phi)*cos(angle),
                                                    ry*cos(phi)*sin(angle), rz*sin(phi)))))
    vertices.append(tuple(center + Vector((0, 0, rz))))
    top = len(vertices) - 1
    faces = []
    for i in range(segments):
        j = (i + 1) % segments
        faces.append((0, 1+j, 1+i))
        faces.append((top, top-segments+i, top-segments+j))
        for row in range(rings-2):
            a = 1 + row * segments
            faces.append((a+i, a+j, a+segments+j, a+segments+i))
    return mesh(name, vertices, faces, material, joint)


def tapered(name, start, end, start_width, end_width, material, joint, sides=8):
    a, b = Vector(start), Vector(end)
    axis = (b-a).normalized()
    u = axis.cross(Vector((1, 0, 0)))
    if u.length < .01:
        u = axis.cross(Vector((0, 1, 0)))
    u.normalize()
    v = axis.cross(u).normalized()
    vertices = []
    for p, radius in ((a, start_width), (b, end_width)):
        vertices.extend(tuple(p + radius*(u*cos(2*pi*i/sides)+v*sin(2*pi*i/sides))) for i in range(sides))
    faces = [tuple(reversed(range(sides))), tuple(range(sides, sides*2))]
    faces.extend((i, (i+1)%sides, (i+1)%sides+sides, i+sides) for i in range(sides))
    return mesh(name, vertices, faces, material, joint)


def shell(name, sections, material, joint, n=16):
    # Y stations, x radius, z centre, z radius. The formed saddle is a
    # separate pressed sheet wrapped over the darker body.
    vertices = []
    for y, rx, z, rz in sections:
        for i in range(n):
            angle = 2*pi*i/n
            vertices.append((rx*cos(angle), y, z+rz*sin(angle)))
    faces = [tuple(reversed(range(n)))]
    for row in range(len(sections)-1):
        for i in range(n):
            j=(i+1)%n
            faces.append((row*n+i,row*n+j,(row+1)*n+j,(row+1)*n+i))
    faces.append(tuple((len(sections)-1)*n+i for i in range(n)))
    return mesh(name, vertices, faces, material, joint)


def panel(name, outline, material, joint):
    # Shallow plate with a visible return edge around the silhouette.
    points = [Vector(p) for p in outline]
    normal = (points[1]-points[0]).cross(points[2]-points[0]).normalized()
    depth = .009
    vertices = [tuple(p) for p in points] + [tuple(p-normal*depth) for p in points]
    n = len(points)
    faces = [tuple(range(n)), tuple(reversed(range(n, 2*n)))]
    faces.extend((i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n))
    return mesh(name, vertices, faces, material, joint)


def side_plate(name, side, coords, offset, plate, trim, joint):
    # Coordinates are Y,Z on a side of the body. An inset creates a thin
    # gold edge around each separately modeled blue armor face.
    center = Vector((sum(y for y,z in coords)/len(coords), sum(z for y,z in coords)/len(coords)))
    outer = [(side*offset,y,z) for y,z in coords]
    inner = []
    for y,z in coords:
        p = Vector((y,z))
        p += (center-p).normalized()*.012
        inner.append((side*(offset+.004),p.x,p.y))
    if side < 0:
        outer.reverse()
        inner.reverse()
    panel(name+" | gold rim", outer, trim, joint)
    panel(name+" | enamel", inner, plate, joint)


def insignia(name, side, y, z, x, gold, joint):
    # Eight-point star over a narrow upright sword, raised above the armor.
    def pt(yy,zz):
        return (side*x, yy, zz)
    blade = [pt(y-.006,z-.105),pt(y-.010,z-.008),pt(y,z+.002),
             pt(y+.010,z-.008),pt(y+.006,z-.105),pt(y,z-.125)]
    if side < 0: blade.reverse()
    panel(name+" | blade", blade, gold, joint)
    cross = [pt(y-.023,z-.017),pt(y+.023,z-.017),pt(y+.023,z-.023),pt(y-.023,z-.023)]
    if side < 0: cross.reverse()
    panel(name+" | guard", cross, gold, joint)
    star=[]
    for i in range(16):
        angle=pi/2+2*pi*i/16
        radius=.028 if i%2==0 else .008
        star.append(pt(y+radius*cos(angle),z+.027+radius*sin(angle)))
    if side<0: star.reverse()
    panel(name+" | star",star,gold,joint)


def build():
    coat = kit.material("fur")
    coat_dark = kit.material("black")
    white = kit.material("white")
    blue = kit.material("team_color")
    gold = kit.material("gold")
    leather = kit.material("leather")
    black = kit.material("black")

    shell("Body | athletic barrel",
          [(-.49,.235,.78,.23),(-.34,.275,.79,.26),(-.03,.245,.77,.23),
           (.24,.22,.76,.20),(.48,.235,.75,.22),(.57,.195,.73,.185)],
          coat,"Body")
    ellipsoid("Chest | sternum", (0,-.43,.73),(.23,.19,.25),coat,"Body")
    ellipsoid("Hindquarters | haunch",(0,.44,.75),(.235,.20,.22),coat,"Body")

    # Segmented articulated legs are individually skinned to their own bones.
    for side, label in ((-1,"R"),(1,"L")):
        x=side*.23
        upper="FrontUpper."+label
        lower="FrontLower."+label
        paw="FrontPaw."+label
        ellipsoid("Front | shoulder "+label,(side*.205,-.40,.74),(.095,.14,.19),coat,upper,12,8)
        tapered("Front | upper "+label,(side*.210,-.40,.70),(x,-.41,.41),.087,.068,coat,upper)
        ellipsoid("Front | elbow "+label,(x,-.41,.41),(.07,.075,.074),coat_dark,lower)
        tapered("Front | lower "+label,(x,-.41,.40),(x,-.40,.105),.068,.052,coat,lower)
        ellipsoid("Front | paw "+label,(x,-.455,.060),(.067,.119,.061),coat_dark,paw,10,6)
        for toe in (-1,0,1):
            ellipsoid("Front | toe "+label+str(toe),(x+toe*.035,-.523,.039),
                      (.022,.041,.035),coat_dark,paw,8,5)
        tapered("Front | white greave "+label,(x,-.425,.375),(x,-.425,.142),.076,.058,white,lower,8)
        ellipsoid("Front | ankle guard "+label,(x,-.43,.112),(.062,.067,.052),white,paw,8,5)

        upper="HindUpper."+label
        lower="HindLower."+label
        paw="HindPaw."+label
        ellipsoid("Rear | muscular thigh "+label,(side*.205,.46,.70),(.11,.17,.20),coat,upper,12,8)
        tapered("Rear | upper leg "+label,(side*.210,.48,.68),(x,.67,.39),.10,.064,coat,upper)
        ellipsoid("Rear | hock "+label,(x,.67,.39),(.066,.072,.075),coat_dark,lower)
        tapered("Rear | shin "+label,(x,.67,.39),(x,.53,.10),.063,.047,coat,lower)
        ellipsoid("Rear | paw "+label,(x,.47,.055),(.061,.108,.054),coat_dark,paw,10,6)
        for toe in (-1,0,1):
            ellipsoid("Rear | toe "+label+str(toe),(x+toe*.031,.407,.035),
                      (.02,.038,.031),coat_dark,paw,8,5)

    tapered("Tail | root",(0,.57,.78),(-.035,.80,.54),.073,.057,coat,"Tail",10)
    tapered("Tail | middle",(-.035,.80,.54),(-.085,1.06,.40),.057,.038,coat,"Tail",9)
    tapered("Tail | tip",(-.085,1.06,.40),(-.14,1.27,.43),.038,.014,coat,"Tail",8)

    # Neck collar, armor saddle and segmented back plates.
    tapered("Collar | black neck seal",(0,-.52,.83),(0,-.73,1.09),.175,.138,black,"Neck",16)
    tapered("Collar | ivory lower rim",(0,-.55,.90),(0,-.61,.98),.188,.168,white,"Neck",16)
    tapered("Collar | gold binding",(0,-.61,.98),(0,-.625,.996),.169,.166,gold,"Neck",16)
    shell("Armor | ivory saddle", [(-.40,.229,.91,.18),(-.28,.25,.94,.17),
          (.10,.233,.94,.16),(.33,.215,.91,.16)], white,"Body")
    # Broad leather strap forms a complete loop on top of the saddle.
    shell("Harness | leather belt",[(.145,.243,.935,.173),(.198,.242,.933,.172)],leather,"Body")
    shell("Armor | white rear pack",[(.255,.185,1.055,.075),(.48,.17,1.04,.071)],white,"Body",12)
    # Flexible black ribs are visible underneath the saddle.
    for y in (-.19,-.145,-.10,-.055,-.01,.035,.08):
        shell("Harness | floating rib",[(y,.258,.755,.245),(y+.014,.257,.755,.244)],black,"Body",16)

    for side,label in ((-1,"R"),(1,"L")):
        shoulder=[(-.51,.94),(-.46,1.01),(-.32,1.05),(-.18,.99),
                  (-.13,.85),(-.18,.74),(-.28,.70),(-.43,.74),(-.51,.82)]
        side_plate("Armor | shoulder "+label,side,shoulder,.307,blue,gold,"FrontUpper."+label)
        insignia("Insignia | shoulder "+label,side,-.32,.89,.316,gold,"FrontUpper."+label)
        rear=[(.31,.98),(.43,1.01),(.54,.94),(.58,.79),(.54,.69),(.40,.71),(.31,.82)]
        side_plate("Armor | rear hip "+label,side,rear,.322,blue,gold,"HindUpper."+label)
        ellipsoid("Harness | gold shoulder stud "+label,(side*.315,-.49,.89),(.027,.026,.027),gold,"FrontUpper."+label,12,6)
        # Gold buckle around a dark inset on the leather band.
        side_plate("Harness | buckle "+label,side,[(.139,.80),(.139,.88),(.207,.88),(.207,.80)],
                   .255,leather,gold,"Body")
    # Center tabard with border sits on the front of the chest.
    outer=[(-.083,-.586,.90),(.083,-.586,.90),(.082,-.604,.56),(0,-.61,.48),(-.082,-.604,.56)]
    panel("Chest | tabard gold border",outer,gold,"Body")
    inner=[(-.070,-.594,.887),(.070,-.594,.887),(.069,-.612,.568),(0,-.618,.50),(-.069,-.612,.568)]
    panel("Chest | blue tabard",inner,blue,"Body")
    # Front-facing gold sword and star.
    panel("Chest insignia | sword",[(-.006,-.624,.72),(.006,-.624,.72),(.005,-.630,.59),
          (0,-.630,.57),(-.005,-.630,.59)],gold,"Body")
    star=[(.022*cos(pi/2+i*pi/8)*(1 if i%2==0 else .33),-.626,
           .76+.022*sin(pi/2+i*pi/8)*(1 if i%2==0 else .33)) for i in range(16)]
    panel("Chest insignia | star",star,gold,"Body")
    tapered("Saddle | aerial mount",(.13,.04,1.09),(.13,.06,1.15),.045,.027,coat_dark,"Body",8)
    tapered("Saddle | antenna",(.13,.06,1.15),(.13,.14,1.39),.012,.006,coat_dark,"Body",8)
