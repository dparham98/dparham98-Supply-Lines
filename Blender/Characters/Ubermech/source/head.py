"""Segmented field helmet and the Ubermech's articulated death mask."""
from math import cos, pi, radians, sin

import mech
from mathutils import Vector
from mathutils.geometry import tessellate_polygon


GROUP = "Head"
BASE_Z = 4.27


def point(x, y, z):
    """The head drawings use millimetres from the tip of the chin."""
    return Vector((x * .001, y * .001, BASE_Z + z * .001))


def solid(name, verts, faces, mat, radius=0):
    return mech.mesh(name, [point(*v) for v in verts], faces, mat, GROUP, radius*.001)


def bar(name, a, b, radius, mat, sides=16, bevel=1.2):
    return mech.rod(name, point(*a), point(*b), radius*.001, mat, GROUP, sides, bevel*.001)


def applique(name, points, mat, pad=5, bevel=1.5):
    # A face plate has a visible return along the black gaps between panels.
    n=len(points)
    area=sum(a[0]*b[2]-b[0]*a[2] for a,b in zip(points,points[1:]+points[:1]))
    points=list(points if area>0 else reversed(points))
    verts=points+[(x,y+pad,z) for x,y,z in points]
    faces=[tuple(range(n)),tuple(reversed(range(n,2*n)))]
    faces.extend((i+n,(i+1)%n+n,(i+1)%n,i) for i in range(n))
    return solid(name,verts,faces,mat,bevel)


# Width and front depth at each facial landmark. The front columns run from the
# sagittal plane through the nose ala, orbit, zygoma and hinge of the mandible.
COLS=(0,.20,.40,.64,.83,1.)
FACE=[
    ( 12,104,(-328,-326,-319,-300,-266,-219)),
    ( 40,136,(-353,-351,-342,-320,-282,-211)),
    ( 82,170,(-363,-360,-347,-319,-273,-197)),
    (126,193,(-365,-360,-343,-308,-259,-176)),
    (164,203,(-373,-369,-350,-310,-247,-161)),
    (189,213,(-380,-376,-352,-307,-245,-150)),
    (211,218,(-379,-375,-353,-309,-244,-140)),
    (252,228,(-387,-373,-343,-307,-253,-135)),
    (284,235,(-407,-376,-341,-314,-272,-129)),
    (312,243,(-433,-381,-342,-323,-282,-126)),
    (347,251,(-431,-378,-343,-332,-291,-121)),
    (391,259,(-412,-362,-323,-313,-279,-116)),
    (433,260,(-393,-345,-311,-301,-273,-114)),
    (473,259,(-379,-350,-332,-308,-267,-109)),
    (506,257,(-363,-354,-342,-319,-262,-103)),
    (550,257,(-354,-347,-332,-303,-239, -95)),
    (612,246,(-327,-320,-305,-271,-209, -82)),
]


def row_depth(row,x):
    u=min(abs(x)/row[1],1.)
    for i in range(len(COLS)-1):
        if u<=COLS[i+1]:
            f=(u-COLS[i])/(COLS[i+1]-COLS[i])
            return row[2][i]+f*(row[2][i+1]-row[2][i])
    return row[2][-1]


def skin(x,z,offset=0):
    for a,b in zip(FACE,FACE[1:]):
        if z<=b[0]:
            f=max(0,(z-a[0])/(b[0]-a[0]))
            return row_depth(a,x)*(1-f)+row_depth(b,x)*f-offset
    return row_depth(FACE[-1],x)-offset


def fitted(name,outline,mat,offset,bevel=1.6):
    # Tessellate before bending across the nose and cheeks. A single long
    # planar polygon would otherwise cut back through the cast mask.
    loop=[Vector((x,z,0)) for x,z in outline]
    triangles=tessellate_polygon([loop])
    verts=[]; faces=[]; cache={}
    def vertex(x,z,depth):
        key=(round(x,4),round(z,4),depth)
        if key not in cache:
            cache[key]=len(verts)
            verts.append((x,skin(x,z,depth),z))
        return cache[key]
    steps=4
    for ia,ib,ic in triangles:
        a,b,c=loop[ia],loop[ib],loop[ic]
        grid={}
        for i in range(steps+1):
            for j in range(steps+1-i):
                p=a+(b-a)*(i/steps)+(c-a)*(j/steps)
                grid[i,j]=vertex(p.x,p.y,offset)
        for i in range(steps):
            for j in range(steps-i):
                faces.append((grid[i,j],grid[i+1,j],grid[i,j+1]))
                if j<steps-i-1:
                    faces.append((grid[i+1,j],grid[i+1,j+1],grid[i,j+1]))
    for a,b in zip(loop,loop[1:]+loop[:1]):
        for i in range(steps):
            p=a.lerp(b,i/steps);q=a.lerp(b,(i+1)/steps)
            faces.append((vertex(p.x,p.y,offset),vertex(q.x,q.y,offset),
                          vertex(q.x,q.y,offset-5),vertex(p.x,p.y,offset-5)))
    obj=solid(name,verts,faces,mat)
    for poly in obj.data.polygons:
        if len(poly.vertices)==3:
            poly.use_smooth=True
    return obj


def cast_face():
    verts=[]; faces=[]
    for z,w,depths in FACE:
        ring=[(-u*w,y,z) for u,y in reversed(list(zip(COLS[1:],depths[1:])))]
        ring += [(u*w,y,z) for u,y in zip(COLS,depths)]
        verts.extend(ring)
    n=2*len(COLS)-1
    for j in range(len(FACE)-1):
        for i in range(n-1):
            k=j*n+i
            faces.append((k,k+1,k+n+1,k+n))
    face=solid("Face | cast cheekbones and mandible",verts,faces,"ivory")
    for poly in face.data.polygons:
        poly.use_smooth=True

    # The neutral cranial shell closes the profile aft of the cheek plates.
    levels=[]
    for z,w,depths in FACE[::2]:
        ring=[(-w,depths[-1]+1),(-w*.81,min(depths[-1]+2,-155)),(0,depths[0]+37),
              (w*.81,min(depths[-1]+2,-155)),(w,depths[-1]+1),(w*.99,18),
              (w*.80,114),(w*.44,168),(0,186),(-w*.44,168),(-w*.80,114),(-w*.99,18)]
        levels.append((BASE_Z+z*.001,[(x*.001,y*.001) for x,y in ring]))
    mech.shell("Face | cranium and jaw chassis",levels,"joint",GROUP,.002)

    # Origami-like forged bridge. Two inclined sides, two little flared alae
    # and a shaded underside produce a nose which also reads in silhouette.
    verts=[(-36,-361,475),(0,-401,485),(35,-360,474),(-35,-401,364),
           (0,-450,358),(34,-402,363),(-51,-396,302),(-26,-445,299),
           (0,-469,313),(25,-447,297),(49,-394,304),(0,-410,283)]
    solid("Face | forged bridge",verts,[(0,3,4,1),(1,4,5,2),(3,6,7,8,4),(4,8,9,10,5)],
          "ivory",1.5)
    solid("Face | nose undersides",verts,[(6,11,8,7),(8,11,10,9)],"bone_shadow",1)
    for s in (-1,1):
        applique("Face | nostril recess",[(s*19,-438,300),(s*38,-416,307),
                (s*35,-411,299),(s*22,-430,294)],"joint",3,.6)
        outline=[(s*x,z) for x,z in [(64,336),(107,375),(176,397),(216,368),
                                      (175,317),(115,274),(91,246),(111,303)]]
        fitted("Face | faceted cheek shield",outline,"ivory",5)
        # A dark slip joint follows the masseter rather than bisecting the
        # face. The hinge armour flares toward the ear and tapers at the chin.
        outline=[(220,384),(230,377),(222,316),(211,286),(196,237),
                 (175,199),(161,108),(121,62),(143,115),(156,192),
                 (181,252),(197,287),(209,330)]
        fitted("Face | mandibular slip joint",[(s*x,z) for x,z in outline],"joint",7)
        outline=[(231,365),(231,298),(215,241),(198,191),(177,105),
                 (129,49),(154,108),(171,185),(193,244),(209,288)]
        fitted("Face | lateral jaw armour",[(s*x,z) for x,z in outline],"bone_shadow",10)
        for x,z in ((204,264),(161,130)):
            x*=s; c=Vector((x,skin(x,z,11),z))
            axis=Vector((s*.66,-.75,0))
            bar("Face | jaw fastener",c,c+axis*3.5,4.5,"edge",8,.45)

    # The mouth line turns slightly down at the corners. The darker return and
    # lower lip break the face into a compressed, stern expression.
    lip=[(-106,180),(-81,198),(-34,211),(0,208),(33,211),(80,199),(106,180),
         (80,187),(32,197),(0,196),(-32,197),(-79,188)]
    fitted("Face | recessed mouth",lip,"black",10,1.2)
    fitted("Face | cast lower lip",[(-74,178),(-28,189),(26,189),(73,178),
           (48,169),(0,163),(-45,169)],"ivory",9,.9)
    fitted("Face | metal chin socket",[(-122,104),(-83,141),(78,141),(120,105),
           (108,49),(69,15),(0,6),(-72,15),(-108,44)],"graphite",10)
    for x in (-62,-21,21,62):
        fitted("Face | vented chin bar",[(x-13,108),(x-9,123),(x+9,123),
               (x+13,110),(x+12,43),(x+7,30),(x-10,39)],"edge",19,2)
    fitted("Face | chin lip",[(-112,100),(-79,142),(75,142),(112,104),
           (94,101),(66,127),(-67,127),(-92,100)],"edge",19)


def eye_and_optic():
    # The natural eye is a recessed almond with a separate brow, lower lid,
    # iris and catchlight. Their depths follow the curved face rather than a decal.
    fitted("Eye | socket",[(43,442),(60,470),(182,493),(206,469),(180,425),
           (134,413),(76,421)],"black",11)
    fitted("Eye | sclera",[(60,447),(111,455),(177,467),(166,445),(137,430),
           (107,426),(81,433)],"white",17,.7)
    c=Vector((120,skin(120,446,18),446))
    normal=Vector((.25,-.969,.012))
    for name,rd,depth,mat in [("iris",13,4,"bone_shadow"),("pupil",9,6,"black")]:
        bar("Eye | "+name,c+normal*(depth-3),c+normal*depth,rd,mat,18,.4)
    glint=c+normal*7.5+Vector((-3.7,0,4.3))
    bar("Eye | catchlight",glint,glint+normal,1.8,"white",10,.15)
    fitted("Eye | upper brow return",[(35,441),(46,488),(178,512),(205,491),
           (174,471),(75,449)],"graphite",24,2)
    fitted("Eye | armoured brow",[(39,456),(47,495),(173,519),(199,495),
           (171,481),(84,462)],"ivory",27,2.5)
    fitted("Eye | lower orbital lip",[(70,423),(91,428),(126,425),(174,440),
           (156,420),(108,411)],"ivory",16)

    c=Vector((-129,-325,451))
    axis=Vector((-.245,-.966,.047)).normalized()
    u=Vector((1,0,0));u=(u-axis*u.dot(axis)).normalized()
    v=axis.cross(u).normalized()
    fitted("Optic | armoured orbital bracket",[(-29,433),(-49,492),(-144,523),
           (-213,495),(-225,436),(-183,375),(-99,358),(-62,382)],"graphite",21,3)
    for label,lo,hi,radius,mat,sides in [
        ("rear socket",0,43,101,"black",12),("flanged housing",30,66,96,"steel",16),
        ("guard collar",58,81,88,"graphite",16),("insulator",76,86,74,"black",32),
        ("red annulus",84,89,68,"glow_red",32),("floating lens mount",88,94,59,"enamel",32),
        ("dark iris",92,96,52,"black",32),("ruby glass",95,98,45,"glow_red",32),
        ("hot center",97,100,29,"glow_core",32)]:
        bar("Optic | "+label,c+axis*lo,c+axis*hi,radius,mat,sides,1.1)
    for a in (18,78,138,198,258,318):
        p=c+axis*78+(u*cos(radians(a))+v*sin(radians(a)))*82
        bar("Optic | keeper bolt",p,p+axis*4,5,"edge",6,.8)
    for a,b in [((-180,-289,375),(-220,-202,330)),
                ((-220,-202,330),(-242,-102,351))]:
        bar("Optic | return conduit",a,b,12,"black",12,1)


HELMET=[(548,337,301),(581,338,307),(634,329,295),(689,310,278),
        (741,276,248),(791,213,197),(826,135,124),(842,57,52),(845,17,16)]


def helm_pt(z,rx,ry,a,offset=0):
    a=radians(a)
    return ((rx+offset)*sin(a),-42-(ry+offset)*cos(a),z)


def dome():
    n=32
    levels=[(BASE_Z+z*.001,[(x*.001,y*.001) for x,y,_ in
             (helm_pt(z,rx,ry,i*360/n) for i in range(n))]) for z,rx,ry in HELMET]
    base=mech.shell("Helmet | pressed graphite crown",levels,"graphite",GROUP,.002)
    for poly in base.data.polygons:
        if len(poly.vertices)==4:
            poly.use_smooth=True
    # Independently formed petals leave a thin dark break between the crown plates.
    for low,high,mat in [(-29,13,"plate"),(15,60,"graphite"),(62,112,"plate"),
                         (115,164,"graphite"),(166,211,"plate"),(214,260,"graphite"),
                         (263,328,"graphite")]:
        angles=[low+(high-low)*j/5 for j in range(6)]
        verts=[helm_pt(z,rx,ry,a,3.5) for z,rx,ry in HELMET[:-1] for a in angles]
        faces=[(r*6+j,r*6+j+1,(r+1)*6+j+1,(r+1)*6+j)
               for r in range(len(HELMET)-2) for j in range(5)]
        plate=solid("Helmet | rolled crown plate",verts,faces,mat)
        for poly in plate.data.polygons:
            poly.use_smooth=True
    # Field-helmet flange kicks lower toward the ears and nape. Its undercut is
    # a distinct black shadow line over the eye, even when seen from below.
    def flared(spec):
        z,rx,ry,sag=spec
        return [(rx*sin(a),-45-ry*cos(a),z-sag*(1-cos(a))*.5-15*sin(a)**2)
                for a in [2*pi*i/n for i in range(n)]]
    profile=[(538,399,402,87),(547,405,408,89),(558,405,408,89),
             (570,387,390,81),(590,348,336,63),(583,334,304,25)]
    for i,(a,b) in enumerate(zip(profile,profile[1:])):
        verts=flared(a)+flared(b)
        faces=[(j,(j+1)%n,(j+1)%n+n,j+n) for j in range(n)]
        solid("Helmet | flared brim",verts,faces,("black","edge","graphite","plate","graphite")[i])
    inner=flared((552,324,291,33))
    solid("Helmet | shadow under brim",flared(profile[0])+inner,
          [(j,j+n,(j+1)%n+n,(j+1)%n) for j in range(n)],"black")
    for side in (-1,1):
        # A visible fastener on either side, high enough to clear the brim.
        a=side*47
        p=Vector(helm_pt(614,335,301,a,3))
        norm=Vector((sin(radians(a)),-cos(radians(a)),.12)).normalized()
        bar("Helmet | crown rivet",p,p+norm*3.7,8,"edge",10,.7)


def rear_and_hinges():
    for s in (-1,1):
        def sideplate(label,outline,x,mat):
            pts=[(s*x,y,z) for y,z in outline]; n=len(pts)
            pts += [(s*(x-18),y,z) for y,z in outline]
            faces=[tuple(range(n)),tuple(reversed(range(n,n*2)))]
            faces += [(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)]
            if s<0: faces=[tuple(reversed(f)) for f in faces]
            solid(label,pts,faces,mat,3)
        sideplate("Ear | upper hinge armour",[(-169,514),(-25,546),(81,495),
                  (64,314),(-8,285),(-107,323)],261,"graphite")
        for label,lo,hi,r,mat in [("gasket",245,273,116,"black"),("casting",269,296,107,"steel"),
                ("face",294,307,88,"graphite"),("rim",304,312,66,"edge"),
                ("hinge",310,317,56,"joint"),("cap",316,322,38,"graphite")]:
            bar("Ear | "+label,(s*lo,-66,374),(s*hi,-66,374),r,mat,24,1.3)
        for theta in (35,155,275):
            y=-66+78*cos(radians(theta));z=374+78*sin(radians(theta))
            bar("Ear | socket screw",(s*306,y,z),(s*310,y,z),5.3,"black",6,.65)
        sideplate("Jaw | hinge link",[(-116,290),(-139,273),(-118,158),(-78,97),
                  (-52,107),(-66,186)],225,"edge")
        bar("Jaw | receiver",(s*224,-92,262),(s*195,-140,166),19,"black",12,1.5)
        bar("Jaw | ram",(s*197,-136,171),(s*150,-210,71),10,"steel",16,1.3)
        for y in (35,63):
            path=[(s*256,y,341),(s*233,y+15,244),(s*182,y+51,157),(s*135,y+60,85)]
            for a,b in zip(path,path[1:]):
                bar("Nape | flexible loom",a,b,13,"black",12,1.3)
    for idx,(z,w) in enumerate([(187,97),(223,124),(259,141),(295,156),(331,159),(367,165),(403,170)]):
        mech.box("Nape | lapped vertebra",point(0,170+idx*1.5,z),(w*.002,.058,.039),
                 "plate" if idx%2 else "graphite",GROUP,.009)
    bar("Neck | rotating spindle",(0,-12,-36),(0,-12,119),109,"joint",24,4)
    for z,r in ((-22,126),(1,119),(24,119),(53,116)):
        bar("Neck | bearing race",(0,-12,z),(0,-12,z+10),r,"steel",24,2)


def build():
    cast_face()
    eye_and_optic()
    rear_and_hinges()
    dome()
