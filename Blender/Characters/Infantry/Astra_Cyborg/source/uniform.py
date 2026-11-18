"""Pattern-cut greatcoat, field belt, breeches and boots. Coordinates are rig rest metres."""
from math import sin,cos,pi
from mathutils import Vector


def mix(a,b,t): return a+(b-a)*t


def between(a,b,t):
    t=max(0,min(1,t))
    if t==0: return {a:1}
    if t==1: return {b:1}
    return {a:1-t,b:t}


def core(v):
    z=v[2]
    if z<.91: return {'hips':1}
    if z<1.035: return between('hips','spine',(z-.91)/.125)
    return between('spine','chest',(z-1.035)/.14)


class Pattern:
    def __init__(self,k,name,mats):
        self.k,self.name,self.mats=k,name,mats
        self.v,self.f,self.m,self.w=[],[],[],[]

    def add(self,verts,faces,material,bones):
        n=len(self.v)
        self.v.extend(verts)
        self.f.extend(tuple(n+i for i in f) for f in faces)
        self.m.extend(material if isinstance(material,list) else [material]*len(faces))
        self.w.extend(bones(v) if callable(bones) else bones for v in verts)

    def loft(self,rings,material,bones,closed=True,caps=True):
        count=len(rings[0]); faces=[]; mats=[]
        for j in range(len(rings)-1):
            for i in range(count if closed else count-1):
                ii=(i+1)%count
                faces.append((j*count+i,j*count+ii,(j+1)*count+ii,(j+1)*count+i))
                mats.append(material(j,i) if callable(material) else material)
        if caps:
            faces += [tuple(reversed(range(count))),tuple(range((len(rings)-1)*count,len(rings)*count))]
            mats += [0,0]
        self.add([v for r in rings for v in r],faces,mats,bones)

    def plate(self,outline,outer_normal,thickness,bones,mat=0,edge=1):
        n=Vector(outer_normal).normalized()
        points=[Vector(v) for v in outline]
        # Use the area vector to support concave lapel outlines.
        area=sum((a.cross(b) for a,b in zip(points,points[1:]+points[:1])),Vector())
        if area.dot(n)<0: points.reverse()
        k=len(points)
        verts=points+[p-n*thickness for p in points]
        faces=[tuple(range(k)),tuple(reversed(range(k,2*k)))]
        faces += [(i,i+k,(i+1)%k+k,(i+1)%k) for i in range(k)]
        self.add(verts,faces,[mat,edge]+[edge]*k,bones)

    def finish(self):
        return self.k.mesh(self.name,self.v,self.f,self.mats,self.w,self.m)


# From front centre round the right half to the back centre. Full sections
# use flat chest and back planes, with a broader, faceted turn on the flanks.
HALF=[(0,-1),(.41,-.994),(.69,-.91),(.86,-.76),(.974,-.42),(1,-.04),
      (.97,.47),(.82,.80),(.57,.94),(0,1)]


def outline(w,cy,front,back,z):
    one=[(x*w,cy+y*(front if y<0 else back),z) for x,y in HALF]
    return one+[(-x,y,h) for x,y,h in reversed(one[1:-1])]


# z, half-width, sagittal centre, front / back half-depth.
BODY=[(.777,.204,.045,.136,.127),(.853,.215,.046,.145,.139),
      (.923,.212,.047,.150,.143),(1.015,.224,.052,.158,.151),
      (1.143,.259,.059,.180,.164),(1.240,.279,.064,.188,.173),
      (1.300,.274,.065,.166,.164),(1.337,.236,.066,.131,.142),
      (1.380,.122,.064,.108,.105)]


def spec(z):
    if z<=BODY[0][0]: return BODY[0][1:]
    for a,b in zip(BODY,BODY[1:]):
        if z<=b[0]:
            t=(z-a[0])/(b[0]-a[0])
            return tuple(mix(u,v,t) for u,v in zip(a[1:],b[1:]))
    return BODY[-1][1:]


def surface(x,z,rear=False):
    w,cy,fr,bk=spec(z)
    curve=list(reversed(HALF[5:])) if rear else HALF[:6]
    u=abs(x)/w
    for (x0,y0),(x1,y1) in zip(curve,curve[1:]):
        if u<=x1:
            return cy+mix(y0,y1,(u-x0)/(x1-x0))*(bk if rear else fr)
    return cy


def front(points,raise_by=.007):
    return [(x,surface(x,z)-raise_by,z) for x,z in points]


def torso(k):
    lining=k.mat('Coal serge lining',(.020,.022,.024),0,.84)
    p=Pattern(k,'Greatcoat | fitted bodice and saddle',[k.wool,k.wool_light,k.team])
    # The saddle is sewn into the back of the bodice. Using the same vertices
    # keeps its lower edge flush during shoulder twists, even at oblique views.
    levels=sorted({r[0] for r in BODY}|{1.247,1.357})
    rows=[outline(*spec(z),z) for z in levels]
    p.loft(rows,lambda j,i:2 if 1.247<=levels[j]<1.357 and 6<=i<=11 else 0,core)
    p.finish()

    # A dark stand collar behind two folded lapels leaves a crisp V at the throat.
    p=Pattern(k,'Collar stand and throat',[lining,k.wool_light])
    collar=[(1.303,.119,.088,.076),(1.360,.122,.101,.091),(1.409,.109,.089,.092),
            (1.418,.092,.082,.085),(1.455,.079,.077,.076),(1.478,.078,.073,.073)]
    p.loft([outline(w,.050,fr,bk,z) for z,w,fr,bk in collar],0,lambda v:between('chest','neck',.4))
    p.plate(front([(-.092,1.366),(.092,1.366),(.051,1.272),(.0,1.222),
                   (-.061,1.273)],.006),(0,-1,0),.006,'chest',0,0)
    p.finish()
    p=Pattern(k,'Greatcoat | faced lapels',[k.wool_light,lining,k.wool])
    for side in (-1,1):
        # Crease line divides the narrow undercollar from the broad notched lapel.
        def sym(coords): return [(side*x,z) for x,z in coords]
        def proj(coords,offset): return front(sym(coords),offset)
        roll=[(.080,-.022,1.421),(.111,.054,1.444),(.152,.055,1.404),
              (.208,-.042,1.310),(.149,-.085,1.327),(.101,-.086,1.307)]
        p.plate([(side*x,y,z) for x,y,z in roll],(side*.48,-1,.23),.014,'chest',2,1)
        low=(-.071,1.074) if side==1 else (-.014,1.185)
        fold=[(.085,1.385),(.113,1.327),(.166,1.302),(.135,1.281),(.181,1.272),
              (.132,1.229),low,(.058,1.292)]
        p.plate(proj(fold,.023 if side==1 else .016),(0,-1,.15),.012,core,0,1)
    p.finish()
    p=Pattern(k,'Fly and button stand',[k.wool,lining])
    p.plate(front([(-.074,.858),(-.074,1.081),(.039,1.181),(.066,1.159),
                   (-.063,1.064),(-.063,.858)],.006),(0,-1,0),.005,core,0,1)
    p.finish()


def skirts(k):
    lining=k.mat('Coal serge lining',(.020,.022,.024),0,.84)
    # A continuous inner lining at the waist gives way to two independent coat
    # tails. Deep movement uses the two original skirt animation controls.
    for side,suffix in [(-1,'R'),(1,'L')]:
        p=Pattern(k,'Greatcoat | '+suffix+' skirt',[k.wool,lining,k.wool_light])
        rows=[(.398,.335,.193,.186),(.411,.334,.193,.185),
              (.544,.304,.183,.171),(.725,.257,.165,.151),(.853,.215,.146,.140),
              (.888,.213,.147,.140)]
        rr=[]
        for z,w,fr,bk in rows:
            weight=max(0,min(1,(.80-z)/.40))
            ring=[]
            for i,(xf,yf) in enumerate(HALF):
                x=side*xf*w
                y=.047+yf*(fr if yf<0 else bk)
                h=z
                if i==0:
                    # Slight asymmetry of the overlapping front fly and a split hem.
                    x=-.048+side*(-.012+.021*weight)
                    y-=.010 if side==1 else 0
                    h+=.016*weight*(side==-1)
                if i==1:
                    x-=.015
                    y+=.005*weight
                if i==3: y-=.011*weight
                if i==4: x-=side*.011*weight
                if i==7: y-=.013*weight
                if i==len(HALF)-1: x=side*.023*weight
                ring.append((x,y,h))
            if side<0: ring.reverse()
            rr.append(ring)
        def weights(v):
            t=min(1,max(0,(.88-v[2])/.31))
            return between('hips','skirt.'+suffix,t*t*(3-2*t))
        # Cloth has a physical inner face so the open skirt stays lined in Run and Hack.
        n=len(HALF)
        for j in range(len(rr)):
            inner=[(x*.978,.047+(y-.047)*.968,z+.002) for x,y,z in reversed(rr[j])]
            rr[j]+=inner
        p.loft(rr,lambda j,i:1 if i>=n-1 else 0,weights)
        p.finish()


def ellipse(cx,cy,z,rx,ry,count=12):
    return [(cx+rx*sin(2*pi*i/count),cy-ry*cos(2*pi*i/count),z) for i in range(count)]


def hardware(k):
    p=Pattern(k,'Field belt and keepers',[k.leather,k.blacksteel])
    p.loft([outline(w,.047,fr,bk,z) for z,w,fr,bk in
            [(.858,.216,.152,.144),(.861,.221,.157,.149),(.929,.222,.158,.150),
             (.935,.217,.153,.144)]],lambda j,i:0 if j==1 else 1,'hips')
    p.finish()
    p=Pattern(k,'Belt buckle and coat buttons',[k.blacksteel,k.gunmetal,k.leather])
    def rect(w,h,c): return [(-w+c,-h),(w-c,-h),(w,-h+c),(w,h-c),
                             (w-c,h),(-w+c,h),(-w,h-c),(-w,-h+c)]
    # Through-hole buckle with a dark leather return beneath it.
    ext=rect(.056,.043,.009); ins=rect(.032,.024,.003)
    rings=[[(x,y,.898+z) for x,z in row] for row,y in
           [(ext,-.110),(ext,-.126),(ins,-.127),(ins,-.113)]]
    for a,b,mi in [(0,1,0),(1,2,1),(2,3,0)]:
        for i in range(8):
            j=(i+1)%8
            # Winding is reversed for the front ring facing -Y.
            p.add([rings[a][i],rings[a][j],rings[b][j],rings[b][i]],[(0,1,2,3)],mi,'hips')
    for x in (-.087,.079):
        for z in (1.142,1.022,.771):
            y=surface(x,z)-.010 if z>.80 else -.116
            # Beveled dome, sitting in a dark stitched washer.
            r=.022 if z>1 else .021
            sections=[]
            for radius,yy in [(r*.91,y+.003),(r,y-.002),(r*.92,y-.008),(r*.74,y-.011)]:
                sections.append([(x+radius*cos(2*pi*i/12),yy,z+radius*sin(2*pi*i/12))
                                 for i in range(12)])
            p.loft(sections,0,core if z>.8 else 'hips')
    p.finish()


def legs(k):
    trouser=k.mat('Field breeches',(.045,.046,.048),0,.92)
    sole=k.mat('Boot tread',(.018,.018,.019),.01,.81)
    for side,suf in [(-1,'R'),(1,'L')]:
        thigh=k.rig.data.bones['thigh.'+suf]
        shin=k.rig.data.bones['shin.'+suf]
        ankle=k.rig.data.bones['foot.'+suf].head_local.copy()
        knee=shin.head_local.copy()
        def axis(z):
            if z<=knee.z: a,b=ankle,knee
            else: a,b=knee,thigh.head_local
            return a.lerp(b,(z-a.z)/(b.z-a.z))
        def legweight(v):
            return between('shin.'+suf,'thigh.'+suf,(v[2]-.335)/.11)
        p=Pattern(k,'Breeches | '+suf,[trouser,k.wool])
        rings=[]
        for z,rx,ry in [(.295,.067,.072),(.303,.081,.087),(.341,.086,.095),
                        (.364,.095,.099),(.388,.100,.101),(.44,.099,.108),
                        (.55,.108,.112),(.70,.107,.121),(.802,.096,.111)]:
            c=axis(z)
            rings.append(ellipse(c.x,c.y,z,rx,ry))
        p.loft(rings,lambda j,i:1 if j==1 else 0,legweight)
        p.finish()
        p=Pattern(k,'Jackboot | '+suf,[k.leather,sole,k.blacksteel])
        rings=[]
        for z,rx,ry in [(.103,.066,.072),(.123,.065,.075),(.164,.056,.062),
                        (.245,.061,.070),(.295,.071,.080),(.311,.077,.085),(.317,.076,.084)]:
            c=axis(z)
            rings.append(ellipse(c.x,c.y,z,rx,ry))
        p.loft(rings,lambda j,i:2 if j==5 else 0,'shin.'+suf)
        forward=k.rig.data.bones['foot.'+suf].tail_local-ankle
        forward.z=0; forward.normalize()
        right=Vector((-forward.y,forward.x,0))
        # Ground plan, winding counterclockwise when viewed from above.
        footprint=[(-.052,-.085),(-.067,-.061),(-.068,.058),(-.078,.111),
                   (-.076,.177),(-.051,.218),(-.021,.231),(.045,.227),
                   (.077,.20),(.083,.145),(.067,.047),(.061,-.063),(.045,-.084)]
        def shoe(x,t,z):
            return (ankle.x+right.x*x+forward.x*t,ankle.y+right.y*x+forward.y*t,z)
        shoe_rings=[]
        for scale,z in [(.97,.0),(1,.008),(1,.032),(.977,.037),(.96,.046)]:
            shoe_rings.append([shoe(x*scale,t*scale,z) for x,t in footprint])
        # Above the skirt of the sole the toe stays broad; the vamp rises over the ankle.
        shoe_rings.append([shoe(x*.94,t*.97,.089+.034*max(0,1-abs(t-.03)/.14)) for x,t in footprint])
        shoe_rings.append([shoe(x*.66,t*.75,.113+.042*max(0,1-abs(t)/.15)) for x,t in footprint])
        p.loft(shoe_rings,lambda j,i:1 if j<3 else 0,'foot.'+suf)
        p.finish()


def build(k):
    torso(k)
    skirts(k)
    hardware(k)
    legs(k)
