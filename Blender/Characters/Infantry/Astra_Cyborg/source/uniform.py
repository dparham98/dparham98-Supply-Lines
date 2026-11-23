"""Pattern-cut greatcoat, field belt, breeches and boots. Coordinates are rig rest metres."""
from math import sin,cos,pi
from mathutils import Vector


def mix(a,b,t): return a+(b-a)*t


def between(a,b,t):
    t=max(0,min(1,t))
    if t==0: return {a:1}
    if t==1: return {b:1}
    return {a:1-t,b:t}


def cloth_normals(obj):
    mesh=obj.data
    for face in mesh.polygons:
        face.use_smooth=True
    mesh.set_sharp_from_angle(angle=.82)


def faced_panel(pattern,rows,normal,weight,face=0,edge=1,thickness=.006):
    """Sew a continuous curved face to its backing with a turned, rounded edge."""
    normal=Vector(normal).normalized()
    h,w=len(rows),len(rows[0])
    top=[Vector(p) for row in rows for p in row]
    quads=[(i*w+j,i*w+j+1,(i+1)*w+j+1,(i+1)*w+j)
           for i in range(h-1) for j in range(w-1)]
    a,b,c,_=quads[len(quads)//2]
    reverse=(top[b]-top[a]).cross(top[c]-top[a]).dot(normal)<0
    if reverse:
        quads=[q[::-1] for q in quads]
    boundary=(list(range(w))+[i*w+w-1 for i in range(1,h)]
              +list(range(h*w-2,(h-1)*w-1,-1))
              +[i*w for i in range(h-2,0,-1)])
    if reverse:
        boundary.reverse()
    verts=top+[p-normal*thickness for p in top]
    faces=quads+[tuple(i+len(top) for i in q[::-1]) for q in quads]
    mats=[face]*len(quads)+[edge]*len(quads)
    rim=[]
    for j,id_ in enumerate(boundary):
        delta=top[boundary[(j+1)%len(boundary)]]-top[boundary[j-1]]
        rim.append(delta.normalized().cross(normal)*min(.0016,thickness*.3))
    previous=boundary
    for depth,bulge in [(.18,.71),(.47,1.),(.78,.71),(1.,0.)]:
        if depth==1:
            next_ring=[i+len(top) for i in boundary]
        else:
            next_ring=list(range(len(verts),len(verts)+len(boundary)))
            verts.extend(top[i]+r*bulge-normal*thickness*depth for i,r in zip(boundary,rim))
        for j in range(len(boundary)):
            jj=(j+1)%len(boundary)
            faces.append((previous[jj],previous[j],next_ring[j],next_ring[jj]))
            mats.append(face if depth<=.47 else edge)
        previous=next_ring
    pattern.add(verts,faces,mats,weight)


def interpolated_rows(stations,substeps=3):
    """Interpolate garment sections, including the ends of a collar roll."""
    controls=[Vector(p) for p in stations]
    result=[]
    for j,(b,c) in enumerate(zip(controls,controls[1:])):
        a=controls[max(0,j-1)]
        d=controls[min(j+2,len(controls)-1)]
        for step in range(substeps):
            t=step/substeps
            result.append(.5*(2*b+(c-a)*t+(2*a-5*b+4*c-d)*t*t+(3*b-a-3*c+d)*t**3))
    return result+[controls[-1]]


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
    cloth_normals(p.finish())

    # The ribbed throat seal opens into a high, padded collar. Its lowest
    # rib disappears under the coat and the narrow upper edge turns under the jaw.
    p=Pattern(k,'Collar stand and throat',[lining,k.wool_light,k.leather])
    collar=[(1.292,.115,.089,.078),(1.316,.123,.096,.084),(1.348,.125,.100,.090),
            (1.367,.120,.099,.092),(1.388,.115,.093,.093),(1.405,.110,.090,.093),
            (1.418,.098,.084,.085),(1.438,.083,.078,.078),(1.455,.079,.077,.076),
            (1.470,.079,.073,.073),(1.478,.076,.071,.071)]
    sealrows=[]
    for z,w,fr,bk in collar:
        ring=[]
        for j in range(40):
            angle=2*pi*j/40
            cx=cos(angle)
            ring.append((w*sin(angle),.050-(fr if cx>0 else bk)*cx,z))
        sealrows.append(ring)
    p.loft(sealrows,0,lambda v:between('chest','neck',.4))
    neckpiece=[]
    for z,w in interpolated_rows([(1.232,.008),(1.251,.034),(1.280,.064),
                                 (1.314,.088),(1.341,.103),(1.363,.103),
                                 (1.380,.097),(1.398,.091)],2):
        row=[]
        for i in range(13):
            t=i/6-1
            x=w*t
            h=z-.006*(1-t*t)*min(1,max(0,(z-1.353)/.045))
            # The insert wraps behind the rolled collar on either side.
            side_return=.039*max(0,(abs(t)-.56)/.44)**2*min(1,max(0,(z-1.348)/.038))
            row.append((x,surface(x,h)-.0095-.002*(1-t*t)+side_return,h))
        neckpiece.append(row)
    faced_panel(p,neckpiece,(0,-1,.10),'chest',0,0,.004)
    # Three shallow, curved tucks reinforce the insert where it bends. They
    # share the serge finish; highlights along their rounded crowns describe the weave.
    for z0,w in [(1.294,.071),(1.315,.086),(1.336,.094)]:
        tuck=[]
        for dz,rise in [(-.003,0),(-.002,.0010),(0,.0020),(.0015,.0020),(.003,.0003)]:
            row=[]
            for j in range(11):
                t=j/5-1
                x=w*t
                z=z0+dz+.0050*t*t
                row.append((x,surface(x,z)-.011-rise,z))
            tuck.append(row)
        faced_panel(p,tuck,(0,-1,.10),'chest',0,0,.0015)
    cloth_normals(p.finish())
    p=Pattern(k,'Greatcoat | faced lapels',[k.wool_light,lining,k.wool])
    # Both folds are cut from one undercollar across the nape.
    back=[]
    for i in range(19):
        t=i/9-1
        a=Vector((.083*t,.148-.022*t*t,1.424-.011*t*t))
        b=Vector((.126*t,.175-.039*t*t,1.365+.023*t*t))
        row=[]
        for j in range(7):
            f=j/6
            point=a.lerp(b,f)
            # Match the tangents and rounded crown of the two collar ends.
            point.y+=(.0035-.0075*t*t)*sin(pi*f)
            point.z+=.007*sin(pi*f)
            row.append(point)
        back.append(row)
    faced_panel(p,back,(0,.92,.40),'chest',2,1,.009)
    for side in (-1,1):
        inner=interpolated_rows([(.083,.126,1.413),(.097,.073,1.435),(.096,.027,1.435),
                                 (.083,-.023,1.415),(.072,-.062,1.375),(.089,-.089,1.330)])
        outer=interpolated_rows([(.126,.136,1.388),(.144,.082,1.406),(.158,.033,1.392),
                                 (.177,-.007,1.357),(.202,-.049,1.314),(.204,-.070,1.307)])
        # The undercollar rolls up from the gorge and turns around the neck.
        fold=[]
        for a,b in zip(inner,outer):
            row=[]
            for j in range(7):
                t=j/6
                x,y,z=a.lerp(b,t)
                row.append((side*x,y-.004*sin(pi*t),z+.007*sin(pi*t)))
            fold.append(row)
        faced_panel(p,fold,(side*.46,-.65,.60),'chest',2,1,.009)
        # The notch has two short straight cuts. Intermediate fabric sections
        # conform to the chest and roll over the break line before crossing it.
        stages=[(1.368,.069,.100),(1.354,.066,.110),(1.327,.055,.121),
                (1.307,.045,.160),(1.303,.043,.164),(1.284,.031,.137),
                (1.273,.023,.177),(1.269,.018,.179),(1.237,.001,.137)]
        if side==1:
            stages += [(1.192,-.025,.084),(1.136,-.052,.012),(1.077,-.071,-.067)]
        else:
            stages += [(1.212,-.008,.067),(1.185,-.016,-.011)]
        sections=[]
        for a,b in zip(stages,stages[1:]):
            steps=max(1,round((a[0]-b[0])/.015))
            sections.extend([tuple(mix(f,g,i/steps) for f,g in zip(a,b)) for i in range(steps)])
        sections.append(stages[-1])
        fold=[]
        for z,inside,outside in sections:
            row=[]
            for j in range(7):
                t=j/6
                x=side*mix(inside,outside,t)
                # Lay the diagonal gorge seam over the undercollar. The top
                # row must clear the cloth beneath even on the thinner overlap.
                h=z-.010*t*max(0,1-(1.368-z)/.026)
                seat=.013*min(1,max(0,(z-1.318)/.030))
                turn=.0075*sin(pi*t)*min(1,(outside-inside)/.045)
                y=surface(x,h)-(.024 if side==1 else .016)-turn-seat
                row.append((x,y,h))
            fold.append(row)
        faced_panel(p,fold,(0,-1,.13),core,0,1,.0075)
        if side==1:
            # A bound, narrow buttonhole follows the face of the lapel.
            def top_at(x,z):
                for a,b in zip(sections,sections[1:]):
                    if b[0]<=z<=a[0]:
                        u=(a[0]-z)/(a[0]-b[0])
                        left,right=mix(a[1],b[1],u),mix(a[2],b[2],u)
                        return surface(x,z)-.024-.0075*sin(pi*(x-left)/(right-left))
                raise ValueError('Buttonhole lies outside lapel')
            rows=[]
            for length,width,rise in [(.0153,.0020,.0001),(.0153,.0020,.0010),
                                      (.0146,.0017,.0013),(.0130,.0007,.0014)]:
                ring=[]
                for j in range(40):
                    angle=j*pi/20
                    dx=length*cos(angle)
                    dz=width*sin(angle)
                    x=.112+dx-.27*dz
                    z=1.263+.27*dx+dz
                    ring.append((x,top_at(x,z)-rise,z))
                rows.append(ring)
            p.loft(rows,2,core,caps=False)
            p.add(rows[-1],[tuple(range(len(rows[-1])))],1,core)
    cloth_normals(p.finish())
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
