"""Armor, anatomy and leg fittings for the Round Table's armored hound.

Coordinates are metres in the bind pose. Negative Y points forward.
Every piece carries a joint name for the exporter to skin rigidly.
"""
from math import cos, pi, sin
import bpy
import bmesh
import kit
from mathutils import Vector


def mesh(name, vertices, faces, material, joint):
    data = bpy.data.meshes.new(name)
    data.from_pydata(vertices, [], faces)
    data.update()
    bm=bmesh.new()
    bm.from_mesh(data)
    bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces))
    bm.to_mesh(data)
    bm.free()
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


def collar_ring(name, start, end, radius_start, radius_end, material, joint):
    """Turn a continuous open ring around the sloping neck."""
    a,b=Vector(start),Vector(end)
    axis=(b-a).normalized()
    u=Vector((1,0,0))
    v=axis.cross(u).normalized()
    count=32
    vertices=[]
    for center,radius in ((a,radius_start),(b,radius_end)):
        vertices.extend(tuple(center+radius*(u*cos(2*pi*i/count)+v*sin(2*pi*i/count)))
                        for i in range(count))
    faces=[(i,(i+1)%count,(i+1)%count+count,i+count) for i in range(count)]
    return mesh(name,vertices,faces,material,joint)


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


def plate_x(y, z, hip):
    # Pressed plate follows the animal around the withers, brisket and flank.
    cy, cz, wy, wz = (.452,.856,.188,.175) if hip else (-.326,.874,.274,.23)
    u,v = (y-cy)/wy, (z-cz)/wz
    return (.331 if hip else .347) - .047*u*u - .026*v*v - .107*max(0.,v)**1.8


def side_plate(name, side, coords, hip, plate, trim, joint):
    cy=sum(y for y,z in coords)/len(coords)
    cz=sum(z for y,z in coords)/len(coords)
    vertices=[]
    n=len(coords)
    for scale, thickness in ((1,-.014),(1,0),(.953,.005),(.66,.007),(.34,.008)):
        for y,z in coords:
            y=cy+(y-cy)*scale
            z=cz+(z-cz)*scale
            vertices.append((side*(plate_x(y,z,hip)+thickness),y,z))
    vertices.append((side*(plate_x(cy,cz,hip)+.009),cy,cz))
    faces=[tuple(reversed(range(n)))]
    indices=[0]
    for r in range(4):
        for i in range(n):
            faces.append((r*n+i,r*n+(i+1)%n,(r+1)*n+(i+1)%n,(r+1)*n+i))
            edge=(coords[i][1]+coords[(i+1)%n][1])/2
            painted_lip=(edge>.956 if hip else edge<.861)
            indices.append(0 if r<=1 and painted_lip else 1)
    for i in range(n):
        faces.append((4*n+i,4*n+(i+1)%n,len(vertices)-1))
        indices.append(1)
    obj=mesh(name,vertices,faces,trim,joint)
    obj.data.materials.append(plate)
    for face,index in zip(obj.data.polygons,indices):
        face.material_index=index


def insignia(name, side, y, z, gold, joint):
    # Slightly arched heraldic inlay follows the face of the shoulder plate.
    def point(yy,zz):
        return Vector((side*(plate_x(yy,zz,False)+.012), yy, zz))
    def mark(label, outline):
        rim=[point(y+dy,z+dz) for dy,dz in outline]
        cy=sum(v.y for v in rim)/len(rim)
        cz=sum(v.z for v in rim)/len(rim)
        verts=rim+[point(cy,cz)+Vector((side*.002,0,0))]
        mesh(name+" | "+label,verts,[(i,(i+1)%len(rim),len(rim)) for i in range(len(rim))],gold,joint)
    mark("blade", [(-.009,-.01),(.009,-.01),(.007,-.130),(0,-.16),(-.007,-.13)])
    mark("crossguard", [(-.029,-.009),(-.009,-.003),(.009,-.003),(.029,-.009),(.028,-.015),(-.028,-.015)])
    mark("star", [((.049 if i%2==0 else .012)*cos(pi/2+i*pi/8),
                   .034+(.055 if i%2==0 else .012)*sin(pi/2+i*pi/8)) for i in range(16)])


def shin_guard(side,label,white,black):
    x=side*.23
    joint="FrontLower."+label
    # The forged greave wraps across the front and around both sides.
    sections=[(.13,.052,.057),(.16,.059,.064),(.31,.072,.078),
              (.37,.076,.083),(.39,.064,.075)]
    angles=[-pi*.53+i*pi*1.06/16 for i in range(17)]
    verts=[]
    for z,rx,ry in sections:
        for angle in angles:
            verts.append((x+rx*sin(angle),-.40-ry*cos(angle),z))
    faces=[]
    n=len(angles)
    for row in range(len(sections)-1):
        for i in range(n-1):
            a=row*n+i
            faces.append((a,a+1,a+n+1,a+n))
    guard=mesh("Front | shaped greave "+label,verts,faces,white,joint)
    for face in guard.data.polygons:
        face.use_smooth=True
    for z in (.17,.30):
        tapered("Front | rear strap "+label,(x,-.385,z-.009),(x,-.385,z+.009),
                .061,.061,black,joint,12)

    # Separate arched plate on the paw rises to meet the greave.
    sections=[(.082,.045,.062),(.100,.057,.069),(.132,.055,.060),(.147,.047,.051)]
    verts=[]
    for z,rx,ry in sections:
        for angle in angles:
            verts.append((x+rx*sin(angle),-.421-ry*cos(angle),z))
    faces=[]
    for row in range(len(sections)-1):
        for i in range(n-1):
            a=row*n+i
            faces.append((a,a+1,a+n+1,a+n))
    plate=mesh("Front | sculpted pastern "+label,verts,faces,white,"FrontPaw."+label)
    for face in plate.data.polygons:
        face.use_smooth=True


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

    # Each curved segment belongs to its matching joint. The rounded ends
    # overlap at the actual pivots so the outline remains continuous in motion.
    def limb(name,sections,material,joint):
        count=12
        vertices=[]
        for y,z,width,depth in sections:
            for i in range(count):
                a=2*pi*i/count
                vertices.append((x+width*cos(a),y+depth*sin(a),z))
        faces=[tuple(reversed(range(count)))]
        for j in range(len(sections)-1):
            for i in range(count):
                a=j*count+i
                b=j*count+(i+1)%count
                faces.append((a,b,b+count,a+count))
        faces.append(tuple(range((len(sections)-1)*count,len(sections)*count)))
        part=mesh(name,vertices,faces,material,joint)
        for face in part.data.polygons:
            if len(face.vertices)==4:
                face.use_smooth=True

    for side,label in ((-1,"R"),(1,"L")):
        x=side*.23
        upper="FrontUpper."+label
        lower="FrontLower."+label
        paw="FrontPaw."+label
        limb("Front | sculpted upper "+label,[
            (-.40,.79,.068,.106),(-.40,.74,.090,.135),(-.405,.66,.087,.11),
            (-.408,.54,.076,.084),(-.41,.43,.068,.071),(-.41,.39,.060,.060)],coat,upper)
        limb("Front | sculpted lower "+label,[
            (-.41,.44,.057,.060),(-.41,.41,.068,.071),(-.406,.34,.062,.065),
            (-.404,.23,.054,.055),(-.40,.13,.047,.052),(-.40,.085,.042,.047)],coat,lower)
        ellipsoid("Front | paw "+label,(x,-.447,.065),(.067,.100,.065),coat_dark,paw,12,7)
        for toe in (-1,0,1):
            ellipsoid("Front | toe "+label+str(toe),(x+toe*.038,-.516,.039),
                      (.019,.040,.032),coat_dark,paw,12,7)
            ellipsoid("Front | nail "+label+str(toe),(x+toe*.038,-.548,.031),
                      (.011,.016,.014),kit.material("graphite"),paw,10,6)
        shin_guard(side,label,white,black)

        upper="HindUpper."+label
        lower="HindLower."+label
        hock="HindHock."+label
        paw="HindPaw."+label
        limb("Rear | sculpted thigh "+label,[
            (.46,.81,.072,.115),(.46,.75,.105,.15),(.43,.67,.110,.145),
            (.39,.58,.091,.107),(.34,.51,.070,.075),(.33,.48,.057,.058)],coat,upper)
        limb("Rear | shaped shin "+label,[
            (.335,.558,.060,.077),(.348,.515,.074,.107),(.40,.465,.074,.118),
            (.49,.40,.069,.110),(.58,.335,.061,.091),(.657,.290,.054,.069),
            (.676,.258,.048,.049)],coat,lower)
        limb("Rear | tapered hock "+label,[
            (.661,.322,.047,.058),(.67,.285,.055,.060),(.65,.23,.050,.053),
            (.625,.16,.046,.046),(.60,.105,.044,.044),(.60,.08,.039,.041)],coat,hock)
        ellipsoid("Rear | paw "+label,(x,.548,.061),(.063,.094,.061),coat_dark,paw,12,7)
        for toe in (-1,0,1):
            ellipsoid("Rear | toe "+label+str(toe),(x+toe*.035,.477,.035),
                      (.018,.038,.031),coat_dark,paw,12,7)
            ellipsoid("Rear | nail "+label+str(toe),(x+toe*.035,.447,.029),
                      (.010,.014,.013),kit.material("graphite"),paw,10,6)

    tapered("Tail | root",(0,.57,.78),(-.035,.80,.54),.073,.057,coat,"Tail",10)
    tapered("Tail | middle",(-.035,.80,.54),(-.085,1.06,.40),.057,.038,coat,"TailMid",9)
    tapered("Tail | tip",(-.085,1.06,.40),(-.14,1.27,.43),.038,.014,coat,"TailTip",8)

    # Neck collar, armor saddle and segmented back plates.
    # A continuous muscular throat fills the neck opening beneath the jaw.
    neck_axis=Vector((0,-.48,.88)).normalized()
    across=Vector((1,0,0))
    depth=neck_axis.cross(across)
    neck_rings=[]
    for y,z,rx,ry in [(-.466,.826,.191,.192),(-.537,.905,.180,.177),
                       (-.601,.987,.164,.158),(-.634,1.054,.150,.149),
                       (-.658,1.114,.141,.143),(-.671,1.183,.122,.127)]:
        center=Vector((0,y,z))
        neck_rings.append([center+rx*cos(i*pi/12)*across+ry*sin(i*pi/12)*depth for i in range(24)])
    skin=kit.mesh("Neck | throat and nape",[p for ring in neck_rings for p in ring],
                  [(j*24+i,j*24+(i+1)%24,(j+1)*24+(i+1)%24,(j+1)*24+i)
                   for j in range(len(neck_rings)-1) for i in range(24)],coat,"Neck")
    for face in skin.data.polygons:
        face.use_smooth=True
    collar_ring("Collar | sculpted ivory base",(0,-.523,.862),(0,-.576,.968),.216,.185,white,"Neck")
    collar_ring("Collar | rolled gold edge",(0,-.576,.968),(0,-.581,.977),.186,.185,gold,"Neck")
    for n in range(4):
        t=n*.019
        collar_ring("Collar | neck rib "+str(n),(0,-.583-t*.68,.981+t*.98),
                    (0,-.588-t*.68,.992+t*.98),.183-n*.006,.181-n*.006,black,"Neck")
    shell("Armor | ivory saddle", [(-.40,.229,.91,.18),(-.28,.25,.94,.17),
          (.10,.233,.94,.16),(.33,.215,.91,.16)], white,"Body")
    # The girth lies over both saddle and ribcage, whose widest points sit
    # at different heights. Fit the strap to their combined outer profile.
    girth=[(.000,.540),(.080,.551),(.154,.584),(.211,.649),(.244,.726),
           (.248,.789),(.248,.838),(.243,.884),(.241,.928),(.243,.953),
           (.235,.985),(.207,1.026),(.155,1.064),(.083,1.098),(0,1.110)]
    girth+= [(-x,z) for x,z in reversed(girth[1:-1])]
    n=len(girth)
    belt=kit.mesh("Harness | saddle girth",[(x,y,z) for y in (.143,.205) for x,z in girth],
                  [(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)],leather,"Body")
    for face in belt.data.polygons:
        face.use_smooth=True
    shell("Armor | white rear pack",[(.255,.185,1.055,.075),(.48,.17,1.04,.071)],white,"Body",12)
    # Flexible black ribs are visible underneath the saddle.
    for y in (-.19,-.145,-.10,-.055,-.01,.035,.08):
        shell("Harness | floating rib",[(y,.258,.755,.245),(y+.014,.257,.755,.244)],black,"Body",16)

    for side,label in ((-1,"R"),(1,"L")):
        shoulder=[(-.575,.938),(-.502,1.045),(-.368,1.108),(-.226,1.086),
                  (-.126,1.017),(-.097,.933),(-.113,.822),(-.160,.738),
                  (-.247,.687),(-.348,.685),(-.488,.748),(-.573,.842)]
        # These shields hang from the saddle. The limbs swing beneath them.
        side_plate("Armor | shoulder "+label,side,shoulder,False,blue,gold,"Body")
        insignia("Insignia | shoulder "+label,side,-.309,.913,kit.material("white"),"Body")
        rear=[(.280,.917),(.321,.982),(.423,1.036),(.503,1.014),(.576,.947),
              (.610,.826),(.598,.730),(.555,.681),(.409,.704),(.351,.758)]
        side_plate("Armor | rear hip "+label,side,rear,True,blue,gold,"Body")
        ellipsoid("Harness | gold shoulder stud "+label,
                  (side*(plate_x(-.546,.877,False)+.012),-.546,.877),(.029,.036,.036),gold,"Body",16,8)
        # Gold buckle around a dark inset on the leather band.
        for a,b in [((.139,.80),(.139,.88)),((.139,.88),(.207,.88)),
                    ((.207,.88),(.207,.80)),((.207,.80),(.139,.80))]:
            tapered("Harness | buckle "+label,(side*.262,a[0],a[1]),(side*.262,b[0],b[1]),
                    .006,.006,gold,"Body",8)
    # Pectoral armor follows the keel of the chest and meets both pauldrons.
    bib_rows=[(.548,.075,-.540,-.497),(.606,.141,-.610,-.458),
              (.719,.199,-.650,-.429),(.833,.223,-.657,-.416),
              (.935,.197,-.631,-.400),(.989,.138,-.569,-.391)]
    bib_vertices=[]
    for z,width,front,back in bib_rows:
        for i in range(13):
            a=-pi*.5+i*pi/12
            bib_vertices.append((width*sin(a),back+(front-back)*cos(a),z+.013*(1-cos(a))))
    kit.mesh("Chest | formed ivory peytral",bib_vertices,
             [(row*13+i,row*13+i+1,(row+1)*13+i+1,(row+1)*13+i)
              for row in range(len(bib_rows)-1) for i in range(12)],white,"Body")
    # Center tabard with border sits on the front of the chest.
    outer=[(-.090,-.665,.93),(.090,-.665,.93),(.088,-.661,.57),(0,-.647,.48),(-.088,-.661,.57)]
    panel("Chest | tabard gold border",outer,gold,"Body")
    inner=[(-.076,-.674,.915),(.076,-.674,.915),(.075,-.670,.58),(0,-.656,.50),(-.075,-.670,.58)]
    panel("Chest | blue tabard",inner,blue,"Body")
    # Front-facing gold sword and star.
    panel("Chest insignia | sword",[(-.006,-.688,.69),(.006,-.688,.69),(.005,-.683,.56),
          (0,-.682,.54),(-.005,-.683,.56)],kit.material("white"),"Body")
    star=[(.032*cos(pi/2+i*pi/8)*(1 if i%2==0 else .35),-.691,
           .735+.032*sin(pi/2+i*pi/8)*(1 if i%2==0 else .35)) for i in range(16)]
    panel("Chest insignia | star",star,kit.material("white"),"Body")
    tapered("Saddle | aerial mount",(.035,-.230,1.091),(.035,-.258,1.161),.048,.023,coat_dark,"Body",8)
    tapered("Saddle | antenna",(.035,-.258,1.161),(.035,-.370,1.379),.012,.005,coat_dark,"Body",10)
