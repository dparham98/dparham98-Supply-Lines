"""Cut and drape the Forester Maiden's linen, fitted bodice and shoulder mantle."""
from math import asin, atan2, cos, exp, pi, sin, sqrt

from mathutils import Vector
from mathutils.bvhtree import BVHTree

from art import cord, loops, mat, mesh


TAU = 2*pi


def mix(a,b,t):
    return a+(b-a)*t


def sections(count,lo=0.,hi=1.):
    return [mix(lo,hi,i/count) for i in range(count+1)]


def interp(rows,z):
    if z <= rows[0][0]:
        return rows[0][1:]
    for low,high in zip(rows,rows[1:]):
        if z <= high[0]:
            t=(z-low[0])/(high[0]-low[0])
            return tuple(mix(a,b,t) for a,b in zip(low[1:],high[1:]))
    return rows[-1][1:]


def panel(name,fn,xs,ys,finish,lining=None,thickness=.002):
    vertices=[fn(x,y) for y in ys for x in xs]
    n=len(xs)
    faces=[(j*n+i,j*n+i+1,(j+1)*n+i+1,(j+1)*n+i)
           for j in range(len(ys)-1) for i in range(n-1)]
    obj=mesh(name,vertices,faces,finish)
    if thickness:
        m=obj.modifiers.new("Cloth thickness","SOLIDIFY")
        m.offset=0
        m.thickness=thickness
        if lining:
            obj.data.materials.append(mat(lining))
            m.material_offset=1
            m.material_offset_rim=1
    return obj


def collider(obj):
    data=obj.data
    return BVHTree.FromPolygons([v.co for v in data.vertices],
                                [p.vertices[:] for p in data.polygons],all_triangles=False)


def surface_y(trees,x,z,front=True):
    direction=1 if front else -1
    origin=Vector((x,-direction,z))
    hits=[hit[0].y for tree in trees
          if (hit:=tree.ray_cast(origin,(0,direction,0),2))[0] is not None]
    if not hits:
        raise ValueError(f"No fabric under detail at x={x:.4f}, z={z:.4f}")
    return min(hits) if front else max(hits)


# Height, half-width, anterior and posterior depth. The upper rings narrow
# around the armholes and turn in to the base of the fitted neck facing.
TORSO=[
    (.984,.117,.079,.074),(1.010,.119,.081,.077),(1.041,.120,.082,.078),
    (1.058,.123,.083,.080),(1.081,.128,.087,.083),(1.106,.136,.094,.085),
    (1.142,.144,.102,.089),(1.180,.151,.113,.092),(1.215,.156,.120,.095),
    (1.247,.159,.124,.097),(1.268,.161,.125,.096),(1.289,.160,.122,.094),
    (1.314,.158,.113,.090),(1.343,.160,.101,.085),(1.367,.169,.086,.080),
    (1.385,.177,.072,.071),(1.399,.169,.064,.067),(1.411,.147,.060,.065),
    (1.424,.105,.061,.071),(1.436,.060,.057,.071),
]


def torso(a,z):
    rx,front,back=interp(TORSO,z)
    c,s=cos(a),sin(a)
    fullness=exp(-((z-1.251)/.075)**2)
    breast=.0065*fullness*(exp(-((abs(s)-.44)/.27)**2)-.60*exp(-(s/.22)**2))
    gathers=(.0016+.0060*exp(-((z-1.102)/.058)**2)+.0028*fullness)
    gathers*=min(1,max(0,(z-1.053)/.04))*min(1,max(0,(1.407-z)/.08))
    folds=gathers*(.64*sin(13*a+6*z+.8*cos(3*a))+.36*sin(21*a-14*z+.6))
    return Vector(((rx+folds)*s,.005-((front*c**.81+breast) if c>=0 else -back*(-c)**.86)-folds*c,z))


def bodice(q,z):
    width,=interp([(1.002,.53),(1.078,.60),(1.18,.66),(1.26,.71),(1.36,.585),(1.4,.55)],z)
    a=q*width
    p=torso(a,z)
    lift=.0046+.0011*(1-q*q)+.0009*cos(4*pi*q)*exp(-((z-1.09)/.09)**2)
    return p+Vector((sin(a)*lift,-cos(a)*lift,0))


def breast_panel(q,t):
    return bodice(q,mix(1.006,1.357+.031*abs(q)**1.7,t))


def upper_layers():
    shell=loops("Linen shift • gathered upper body",
                [[torso(a,z) for a in sections(80,0,TAU)[:-1]] for z,*_ in TORSO],"linen")
    # Finish the open throat between the two blue collar leaves. The bound
    # opening sits proud of the neck so the cropped portrait has a clean edge.
    cord("Bound linen neckline",[torso(a,TORSO[-1][0]) for a in sections(96,0,TAU)],
         .00165,"linen_shadow",8)
    chest=panel("Indigo fitted kirtle • breast panel",breast_panel,
                sections(27,-1,1),sections(28),"navy","navy_shadow",.0026)
    for side,word in [(-1,"right"),(1,"left")]:
        for q,name,radius,finish in [(side*.992,"Folded binding",.0021,"navy_shadow"),
                                      (side*.961,"Bodice braid",.00095,"gold")]:
            cord(name+" • "+word,[breast_panel(q,t)+Vector((0,-.0016,0)) for t in sections(36)],
                 radius,finish)
    # A narrow textile waistband continues beneath the worker's tool belt.
    def waist(a,v):
        z=1.038+.040*v+.003*cos(a*2)
        p=torso(a,z)
        r=.0034+.0012*sin(v*pi)
        return p+Vector((r*sin(a),-r*cos(a),0))
    panel("Indigo woven waist facing",waist,sections(64,0,TAU),sections(5),"navy_shadow",None,.002)
    return collider(shell),collider(chest)


SKIRT=[(.595,.223,.141,.149),(.632,.219,.142,.147),(.70,.209,.137,.144),
       (.78,.194,.130,.138),(.851,.177,.120,.128),(.916,.160,.109,.114),
       (.957,.146,.099,.103),(.988,.132,.089,.092),(1.030,.119,.080,.080)]


def skirt(a,z,lift=0):
    x,dy,back=interp(SKIRT,z)
    h=min(1,max(0,(z-.60)/.43))
    # Gentle twisting of the fold lines prevents the hanging linen from
    # turning into straight radial fluting. Their high points flatten at belt.
    width=.0178*(1-h)**.69+.0018
    wrinkle=width*(.64*cos(10*a+1.05*h+.45*sin(3*a))+.29*cos(16*a-1.6*h+.7)
                  +.23*cos(6*a+2.3*h-.3))
    # The linen is taken up at the hips and releases in biased hanging folds.
    # Separate lip and trough profiles give the cloth a pinched fold rather than a flute.
    angle=atan2(sin(a),cos(a))
    for side in (-1,1):
        band=side*angle
        offset=.04 if side>0 else -.05
        for center,strength,spread in [(.61+.33*h+offset,.008,.068),
                                       (1.16-.30*h+offset,.006,.09),
                                       (2.54-.21*h,.005,.12)]:
            wake=exp(-((band-center)/spread)**2)-.78*exp(-((band-center-.105)/(.9*spread))**2)
            wrinkle+=strength*wake*(.56+.44*sin(pi*h))*(1-h**3)
    c,s=cos(a),sin(a)
    return Vector(((x+wrinkle+lift)*s+.003*(1-h),.005-(dy if c>=0 else back)*c-(wrinkle+lift)*c,z))


def skirt_hem(a):
    return .605+.0071*cos(a*4+.54)+.0038*sin(9*a-.28)+.008*max(0,cos(a))**8


def skirt_piece(kind,q,t):
    vent=max(0,1-t/.32)**1.65
    center=.029+.082*max(0,1-t/.62)**1.15
    if kind=="Left fore":
        a=mix(center,1.57-.072*vent,q)
    elif kind=="Right fore":
        a=mix(-1.57+.065*vent,-center-.008,q)
    else:
        a=mix(1.57+.049*vent,TAU-1.57-.058*vent,q)
    return skirt(a,mix(skirt_hem(a),1.027,t))


def tabard(q,t):
    hem=.619+.036*(abs(q)**.85)+.003*sin(q*4)
    z=mix(hem,1.019,t)
    half=mix(.077,.050,t)+.0009*sin(9*t)
    x=half*q+.003*sin(4*t)
    rx=interp(SKIRT,z)[0]
    a=asin(x/rx)
    p=skirt(a,z,.0048)
    # Accentuate a central lap fold while letting the side edges rest back.
    p.y-=.0022+.0045*(1-q*q)+.0025*cos(2.7*pi*q+.55*t)*(1-.40*t)
    return p


def make_skirt():
    for kind,pieces in [("Left fore",35),("Rear",68),("Right fore",35)]:
        shape=lambda q,t:skirt_piece(kind,q,t)
        panel("Linen skirt • "+kind,shape,sections(pieces),sections(26),
              "linen","linen_shadow",.0026)
        # A turned hem, a line of flax above it, and the cut edges of the vents.
        def turn(q,v):
            p=shape(q,.012+.015*v)
            n=Vector((p.x,p.y-.005,0)).normalized()
            return p+n*.0019
        panel("Turned linen hem • "+kind,turn,sections(pieces),[0,1],
              "linen_shadow",None,.001)
        for edge in [0,1]:
            cord("Bound vent • "+kind+str(edge),[shape(edge,t) for t in sections(14,0,.31)],
                 .00145,"linen_shadow")
    for side,word in [(-1,"right"),(1,"left")]:
        def rear(q,t):
            a=side*mix(1.68+.13*t,2.31+.06*t,q)
            bottom=.626+.019*q+.006*sin(a*6)
            return skirt(a,mix(bottom,1.016,t),.0047)
        panel("Indigo side gore • "+word,rear,sections(18),sections(24),"navy","navy_shadow")
        cord("Gore hem braid • "+word,[rear(q,.021) for q in sections(25)],.00175,"gold")
    apron=panel("Forester's heraldic apron",tabard,sections(27,-1,1),sections(32),
                "navy","navy_shadow",.0030)
    for side in [-1,1]:
        cord("Tabard rolled selvedge "+str(side),[tabard(side,t) for t in sections(28)],.0018,"navy_shadow")
        cord("Tabard gilt stitch "+str(side),[tabard(side*.957,t)+Vector((0,-.002,0)) for t in sections(35)],
             .0009,"gold")
    def broad(q,t):
        return tabard(q,t)+Vector((0,-.0025,0))
    panel("Chevron hem embroidery",broad,sections(32,-.974,.974),[.009,.020,.032],
          "gold",None,.00085)
    cord("Fine thread above chevron",[broad(q,.043) for q in sections(32,-.96,.96)],.00075,"gold")
    return collider(apron)


MANTLE=[
    (0,.062,.058,.060,1.448,1.429,1.438),
    (.13,.085,.066,.071,1.450,1.418,1.430),
    (.28,.118,.078,.086,1.445,1.407,1.417),
    (.43,.155,.092,.104,1.434,1.397,1.399),
    (.57,.185,.104,.117,1.418,1.389,1.377),
    (.70,.211,.117,.127,1.397,1.383,1.349),
    (.80,.231,.125,.135,1.373,1.378,1.323),
    (.90,.251,.130,.139,1.340,1.372,1.292),
    (1,.266,.131,.139,1.304,1.365,1.263),
]


def mantle(q,t):
    start=.385+.025*sin(pi*t)-.028*t
    a=mix(start,TAU-start,q)
    rx,dy,back,sidez,frontz,backz=interp(MANTLE,t)
    c,s=cos(a),sin(a)
    z=mix(sidez,frontz if c>0 else backz,abs(c)**1.65)
    fullness=(.0007+.0042*t)*(.80*sin(10*a+.85*t+.37*cos(2*a))+.38*sin(17*a-.7*t))
    arc=min(a,TAU-a)-start
    turn=.028 if a>pi else -.014
    fan=min(1,max(0,(arc+.015)/.21))*exp(-((arc-.74)/1.14)**2)
    pleat=0
    for band,height,width in [(.77-.34*sin(1.42*arc+turn),.0090,.065),
                              (.91-.19*sin(1.82*arc+turn),.0065,.051),
                              (.49-.20*sin(1.24*arc+turn),.0052,.064)]:
        pleat+=height*(exp(-((t-band)/width)**2)-.48*exp(-((t-band-.066)/(.82*width))**2))
    fullness+=fan*pleat
    # The pleats change from horizontal on the shoulder to vertical at the hem.
    z+=fullness*(1-.48*t)+.004*t*sin(3*a-.53)
    # Ease cut into the outer panels lets the mantle clear the gathered sleeve.
    ease=exp(-((min(a,TAU-a)-1.36)/.65)**4)*min(1,max(0,(t-.58)/.25))
    z+=.013*ease
    return Vector(((rx+fullness*t+.0045*ease)*s,
                   .005-((dy if c>=0 else back)+fullness*t+.0030*ease)*c,z))


def collar(q,t):
    gap=mix(.45,.78,t)
    a=mix(gap,TAU-gap,q)
    rx=mix(.071,.065,t)
    y=mix(.063,.059,t)
    z=mix(1.422+.010*abs(sin(a)),1.464+.009*max(0,-cos(a))+.004*abs(sin(a)),t)
    return Vector((rx*sin(a),.004-y*cos(a),z))


def shoulder_cloth():
    cape=panel("Short indigo shoulder mantle",mantle,sections(120),sections(26),
               "navy","navy_shadow",.0032)
    cord("Mantle hem • gilt piping",[mantle(q,1) for q in sections(115)],.00235,"gold",8)
    for side in [0,1]:
        cord("Front mantle turn "+str(side),[mantle(side,t) for t in sections(23)],
             .0020,"navy_shadow")
        cord("Front mantle welt "+str(side),[mantle(.0019 if not side else .9981,t) for t in sections(23)],
             .0011,"gold")
    panel("Split standing collar",collar,sections(68),sections(7),"navy_shadow","linen_shadow",.0030)
    cord("Collar upper piping",[collar(q,1) for q in sections(66)],.00155,"gold")
    for q in [0,1]:
        cord("Collar leaf piping "+str(q),[collar(q,t) for t in sections(8)],.00105,"gold")
    return collider(cape)


def applied_leaf(name,outline,depth,base,finish):
    # A stitched metal-thread leaf has a shallow ridge down its face.
    x0=sum(p[0] for p in outline)/len(outline)
    z0=sum(p[1] for p in outline)/len(outline)
    vs=[base(x,z,0) for x,z in outline]+[base(x,z,.0009) for x,z in outline]
    n=len(outline)
    ridge=len(vs)
    vs.append(base(x0,z0,depth))
    fs=[tuple(reversed(range(n)))]
    for i in range(n):
        j=(i+1)%n
        fs.extend([(i,j,j+n,i+n),(i+n,j+n,ridge)])
    return mesh(name,vs,fs,finish,False)


def sword_badge(name,base,cx,cz,size):
    def leaf(label,shape,depth=.0019,finish="gold"):
        return applied_leaf(name+" • "+label,[(cx+size*x,cz+size*z) for x,z in shape],depth,base,finish)
    leaf("blade",[(-.0039,.015),(.0039,.015),(.00325,-.012),(.0016,-.0415),(0,-.047),
                  (-.0026,-.037),(-.00325,-.012)])
    for sign,end in [(-1,"R"),(1,"L")]:
        for i,pts in enumerate([
            [(.006,.015),(.016,.0155),(.027,.018),(.046,.029),(.040,.019),(.029,.014),(.017,.011),(.008,.012)],
            [(.008,.009),(.020,.010),(.035,.015),(.030,.008),(.020,.004),(.012,.005)],
            [(.008,.003),(.019,.002),(.027,.005),(.021,-.0015),(.013,-.004),(.008,-.002)],
        ]):
            leaf(f"wing quill {end}{i+1}",[(x*sign,z) for x,z in pts],.0021)
        leaf("guard "+end,[(sign*x,z) for x,z in [(0,.017),(.011,.017),(.015,.025),
                         (.012,.026),(.009,.022),(0,.022)]])
    leaf("hilt",[(-.0020,.018),(.0020,.018),(.0024,.032),(.004,.035),(0,.041),
                 (-.004,.035),(-.0024,.031)],.0025)
    cord(name+" • blade fillet",[base(cx,cz+size*z,.00195) for z in [.015,.005,-.013,-.028,-.040]],
         .00050*size,"gold",5)


def little_stud(name,p,radius,finish="gold",front=True):
    d=-1 if front else 1
    rings=[]
    for offset,r in [(0,radius*.80),(.0006,radius),(.0018,radius*.88),(.0024,radius*.45)]:
        rings.append([(p.x+r*cos(a),p.y+offset*d,p.z+r*sin(a)) for a in sections(16,0,TAU)[:-1]])
    return loops(name,rings,finish,True)


def doublet_details(body,apron,cape):
    def chest(x,z,relief):
        return Vector((x,surface_y([body[1]],x,z)-.0021-relief,z))
    sword_badge("Round Table • winged sword",chest,0,1.282,1.0)
    def tab(x,z,relief):
        return Vector((x,surface_y([apron],x,z)-.0022-relief,z))
    sword_badge("Apron • woven sword",tab,.002, .859,.57)
    # A small barley sprig recalls the quieter agricultural embroidery low on the apron.
    for sign in [-1,1]:
        pts=[(sign*.003,.701),(sign*.010,.708),(sign*.017,.711),(sign*.023,.719)]
        cord("Harvest sprig • stem "+str(sign),[tab(x,z,.0008) for x,z in pts],.0007,"gold",5)
        for i in range(3):
            x=sign*(.008+i*.005)
            z=.707+i*.003
            applied_leaf("Harvest sprig • ear",[(x,z),(x+sign*.006,z+.010),(x+sign*.007,z+.004)],
                         .0014,tab,"gold")
    # The small yoke lies across the base of the throat, behind the mantle clasps.
    def yoke(q,v):
        z=mix(1.363+.020*abs(q)**1.6,1.396+.006*abs(q),v)
        x=q*mix(.076,.092,v)
        return Vector((x,surface_y(body,x,z)-.0030-.003*sin(pi*v),z))
    panel("Leather throat yoke",yoke,sections(30,-1,1),sections(6),"leather_dark",None,.0025)
    def plate(q,v):
        p=yoke(q*.965,.09+.82*v)
        p.y-=.0019+.0014*sin(pi*v)
        return p
    panel("Chased steel throat facing",plate,sections(30,-1,1),sections(7),"iron",None,.0012)
    cord("Throat facing • burnished lip",[plate(q,.07)+Vector((0,-.0007,0)) for q in sections(31,-.92,.92)],.0008,"brass_dark",6)
    for sign in [-1,1]:
        for z in [.29,.74]:
            little_stud("Gorget rivet",plate(sign*.875,z),.00215)
        # Two bronze rosettes pin the mantle at its front shoulders.
        q=.017 if sign>0 else .983
        p=mantle(q,.79)
        tangent=mantle(q+.003,.79)-mantle(q-.003,.79)
        across=mantle(q,.806)-mantle(q,.774)
        n=across.cross(tangent).normalized()
        if n.z<0:
            n.negate()
        p+=n*.0047
        u=Vector((1,0,0))
        u=(u-u.dot(n)*n).normalized()
        v=n.cross(u)
        rings=[]
        for lift,r in [(-.004,.015),(.0001,.019),(.0026,.019),(.0042,.0163),(.0037,.0148)]:
            rings.append([p+n*lift+r*(u*cos(a)+v*sin(a)) for a in sections(32,0,TAU)[:-1]])
        loops("Mantle clasp • chased mount",rings,"brass_dark")
        for rad,lift,material,thick in [(.0175,.0032,"gold",.0015),(.0123,.0041,"gold",.00065)]:
            circle=[p+n*lift+rad*(u*cos(a)+v*sin(a)) for a in sections(32,0,TAU)]
            cord("Clasp beading",circle,thick,material)
        for i in range(6):
            a=i*pi/3
            mid=p+n*.0043
            cord("Clasp ray",[mid+.003*(u*cos(a)+v*sin(a)),mid+.0096*(u*cos(a+.20)+v*sin(a+.20))],
                 .001,"gold",5)


def harness(body,cape):
    # The front stays outside the breast panel. The back straps cross once over the mantle.
    for side,word in [(-1,"right"),(1,"left")]:
        def front(q,t):
            z=mix(1.036,1.381,t)
            center,=interp([(1.036,.099),(1.084,.113),(1.170,.132),(1.248,.141),
                            (1.306,.129),(1.353,.111),(1.381,.101)],z)
            x=side*(center+q*.0094)
            return Vector((x,surface_y([*body,cape],x,z)-.0025,z))
        panel("Front shoulder harness • "+word,front,sections(4,-1,1),sections(43),
              "leather_dark",None,.0027)
        for q in [-.78,.78]:
            cord("Raised leather harness edge • "+word,[front(q,t)+Vector((0,-.0016,0)) for t in sections(35)],
                 .00075,"leather")
        # Low-weight forged slide, just beneath the top of the shoulder harness.
        corners=[(-1.09,.745),(1.09,.745),(1.09,.795),(-1.09,.795),(-1.09,.745)]
        cord("Harness rectangular buckle • "+word,[front(q,t)+Vector((0,-.0035,0)) for q,t in corners],.00170,"gold",7)
        cord("Buckle tongue • "+word,[front(0,t)+Vector((0,-.0046,0)) for t in [.74,.792]],.0011,"gold",6)

        def back(q,t):
            z=mix(1.035,1.421,t)
            ctr,=interp([(1.035,-.095),(1.101,-.079),(1.19,-.041),(1.257,.002),
                         (1.328,.055),(1.383,.098),(1.421,.121)],z)
            x=side*(ctr+q*.0103)
            # One strap passes over the other at the crossing.
            lift=.0028+(.0033 if side==1 else 0)*exp(-((z-1.253)/.042)**2)
            return Vector((x,surface_y([body[0],cape],x,z,False)+lift,z))
        panel("Back cross strap • "+word,back,sections(4,-1,1),sections(59),"leather",None,.0028)
        clasp=mantle(.017 if side>0 else .983,.79)
        def shoulder(q,t):
            rear=back(q,1)
            x=mix(rear.x,clasp.x+side*q*.0096,t)
            y=mix(rear.y,clasp.y,t)
            hit=cape.ray_cast((x,y,2),(0,0,-1),1)[0]
            z=hit.z+.0029 if hit is not None else mix(rear.z,clasp.z,t)
            return Vector((x,y,z))
        panel("Over-shoulder harness • "+word,shoulder,sections(4,-1,1),sections(30),"leather",None,.0028)
        for q in [-.79,.79]:
            cord("Pressed back strap edge",[back(q,t)+Vector((0,.0017,0)) for t in sections(44)],
                 .00060,"leather_dark",5)
            cord("Pressed shoulder strap edge",[shoulder(q,t)+Vector((0,0,.0016)) for t in sections(30)],
                 .00060,"leather_dark",5)
        if side==1:
            little_stud("Back harness • crossing rivet",back(0,.566)+Vector((0,.0012,0)),.0031,front=False)


def build():
    body=upper_layers()
    apron=make_skirt()
    cape=shoulder_cloth()
    doublet_details(body,apron,cape)
    harness(body,cape)
