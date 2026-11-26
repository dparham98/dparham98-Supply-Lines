"""Portrait sculpt, parted hair, plait and tied linen headscarf for the Forester."""

from math import asin, atan2, cos, exp, pi, sin, sqrt
import random

import bpy
import numpy as np
from mathutils import Vector

import art


def material(label, hex_color, roughness, metal=0):
    m = bpy.data.materials.get(label) or bpy.data.materials.new(label)
    m.use_nodes = True
    s = m.node_tree.nodes.get("Principled BSDF")
    m.diffuse_color = (*art.linear(hex_color), 1)
    s.inputs["Base Color"].default_value = m.diffuse_color
    s.inputs["Roughness"].default_value = roughness
    s.inputs["Metallic"].default_value = metal
    return m


def surface(name, vertices, faces, mat, part="Head"):
    obj = art.mesh(name, vertices, faces, mat)
    obj["part"] = part
    return obj


def rows(name, rings, mat, wrap=False, close=False, part="Head"):
    n, m = len(rings[0]), len(rings)
    faces = [(i*n+j,i*n+(j+1)%n,(i+1)*n+(j+1)%n,(i+1)*n+j)
             for i in range(m-1) for j in range(n if wrap else n-1)]
    if close:
        faces += [tuple(reversed(range(n))), tuple(range((m-1)*n,m*n))]
    return surface(name,[p for row in rings for p in row],faces,mat,part)


def g(x,r):
    return exp(-(x/r)**2)


def mix(a,b,t):
    return a+(b-a)*t


def spline(profile,z):
    # Nonuniform cubic through the crown, jaw angle and chin landmarks.
    i=next((j for j in range(len(profile)-1) if z<=profile[j+1][0]),len(profile)-2)
    a,b=profile[i:i+2]
    before,after=profile[max(0,i-1)],profile[min(i+2,len(profile)-1)]
    dt=b[0]-a[0]
    t=min(1,max(0,(z-a[0])/dt))
    return tuple((2*t**3-3*t*t+1)*a[k]+(t**3-2*t*t+t)*dt*(b[k]-before[k])/(b[0]-before[0])
                 +(-2*t**3+3*t*t)*b[k]+(t**3-t*t)*dt*(after[k]-a[k])/(after[0]-a[0])
                 for k in range(1,len(a)))


# Axial profile of the skull: height, width, front, occiput.
SKULL=[(1.493,.007,-.043,-.024),(1.497,.021,-.060,-.009),(1.503,.032,-.070,.011),
       (1.515,.043,-.077,.040),(1.531,.054,-.078,.061),(1.551,.063,-.080,.077),
       (1.573,.069,-.081,.087),(1.592,.074,-.081,.092),(1.611,.075,-.081,.096),
       (1.627,.073,-.082,.098),(1.647,.073,-.084,.099),(1.670,.071,-.077,.097),
       (1.689,.064,-.063,.090),(1.704,.047,-.042,.071),(1.713,.023,-.017,.048),
       (1.716,.005,.008,.024)]
NOSE=[(1.561,.001,.003),(1.565,.004,.0034),(1.569,.012,.0044),
      (1.573,.020,.0057),(1.577,.028,.0102),(1.581,.030,.0113),
      (1.587,.023,.0090),(1.598,.017,.0087),(1.608,.012,.0078),
      (1.620,.006,.0088),(1.632,.002,.0098),(1.638,0,.011)]


def mouth(x):
    t=min(1,abs(x)/.0256)
    roundness=max(0,1-t*t)**.75
    seam=1.5448+.00040*g(x,.007)-.0008*g(abs(x)-.016,.005)+.00062*x/.0256
    return (seam-.0060*roundness, seam,
            seam+(.0043+.0015*g(t-.29,.22))*roundness)


def relief(x,z):
    a=abs(x)
    # Zygomatic arch, buccal plane, glabella, socket and infraorbital rim.
    y=.0095*g(a-.043,.027)*g(z-1.596,.019)-.0034*g(a-.051,.016)*g(z-1.559,.020)
    y+=.0069*g(a-.027,.024)*g(z-(1.629+.055*a),.0083)-.0073*g(a-.030,.018)*g(z-1.617,.011)
    y+=.0018*g(a-.036,.021)*g(z-1.607,.0040)
    y+=.0058*g(a,.031)*g(z-1.548,.019)+.0055*g(a,.021)*g(z-1.515,.011)
    y-=.0018*g(a,.019)*g(z-1.532,.0051)
    if NOSE[0][0]<z<NOSE[-1][0]:
        depth,width=spline(NOSE,z)
        y+=depth*g(x+.0005*g(z-1.579,.010),width)
        y+=.0158*g(a-.0119,.0064)*g(z-1.574,.0054)
        y-=.0034*g(a-.0187,.0033)*g(z-1.575,.0057)
    y+=.0024*g(a-.0043,.0024)*g(z-1.558,.008)-.0016*g(x,.0028)*g(z-1.558,.007)
    y-=.0023*g(a-(.019+.35*(1.57-z)),.004)*g(z-1.558,.014)
    y-=.0014*g(a-.024,.0032)*g(z-1.545,.0033)
    lo,mid,hi=mouth(x)
    if lo<z<hi:
        weight=max(0,1-(x/.0256)**2)**.67
        f=(z-mid)/(hi-mid) if z>mid else (mid-z)/(mid-lo)
        y+=weight*((.0030 if z>mid else .0040)*max(0,sin(pi*f))**.84 + .0014*(1-f))
    return y


def face_y(x,z):
    w,front,back=spline(SKULL,z)
    c=sqrt(max(0,1-(x/w)**2))
    mid=(front+back)/2
    return mid-(mid-front)*c**.79-relief(x,z)*c


def complexion():
    # One packed, portable pigment map: weathered cheeks, faint veins, warm
    # orbital and vermilion accents, fine grain, and individually placed freckles.
    size=1024
    u=(np.arange(size)+.5)/size
    v=(np.arange(size)+.5)/size
    zz=SKULL[0][0]+v*(SKULL[-1][0]-SKULL[0][0])
    aa=(u-.5)*2*pi
    widths=np.array([spline(SKULL,z)[0] for z in zz])
    x=widths[:,None]*np.sin(aa[None,:])
    z=zz[:,None]
    front=np.clip(np.cos(aa),0,1)[None,:]**.4
    ax=np.abs(x)
    array=np.empty((size,size,4),dtype=np.float32)
    array[:]=(.751,.547,.440,1)
    rgb=array[:,:,:3]
    def wash(tint,weight):
        rgb[:]+= (np.asarray(tint)-rgb)*np.clip(weight*front,0,1)[:,:,None]
    def spot(dx,dz):
        return np.exp(-dx*dx-dz*dz)
    wash((.735,.403,.324),.34*spot((ax-.046)/.028,(z-1.589)/.020))
    wash((.625,.372,.303),.46*spot((ax-.031)/.024,(z-1.619)/.012))
    wash((.532,.296,.232),.33*spot((ax-.0185)/.0037,(z-1.574)/.0064))
    wash((.547,.327,.279),.26*spot(x/.014,(z-1.567)/.0043))
    wash((.834,.642,.532),.18*spot((ax-.014)/.013,(z-1.556)/.013))
    wash((.748,.444,.347),.42*spot(x/.016,(z-1.576)/.012))
    # Soft follicle beds stay in the skin at the start and tail of the brow.
    bt=np.clip((ax-.0128)/.0427,0,1)
    bz=1.6288+.0057*np.sin(pi*np.maximum(0,bt-.12)*.97)-.0014*bt+(.0011+.0006*(1-bt))*(x<0)
    bw=.00275*np.clip(1-bt**2.3,.08,1)*np.clip(.35+bt/.13,.1,1)
    br=np.abs(z-bz)/(.00045+bw)
    fade=np.clip((ax-.0125)/.002,0,1)*np.clip((.0558-ax)/.0025,0,1)
    wisps=.65+.35*np.sin(ax*6900-(z-bz)*(1450+bt*8200))**2
    brow=np.exp(-br**3)*fade*wisps
    wash((.233,.154,.119),brow*.87)
    wash((.565,.348,.268),.28*spot((ax-.030)/.013,(z-1.622)/.0028))
    wash((.604,.364,.286),.29*spot((ax-.017)/.0032,(z-1.614)/.0038))
    t=np.minimum(1,ax/.0256)
    shape=np.maximum(0,1-t*t)**.75
    seam=1.5448+.00040*np.exp(-(x/.007)**2)-.0008*np.exp(-((ax-.016)/.005)**2)+.00062*x/.0256
    dist=z-seam
    reach=np.where(dist>0,(.0043+.0015*np.exp(-((t-.29)/.22)**2))*shape,.0060*shape)
    lip=np.clip((reach-np.abs(dist))/.0020+.52,0,1)*np.clip((1-t)*5,0,1)
    furrow=.88+.12*np.cos(x*4400+np.sin(x*630)+dist*150)**4
    wash((.548,.303,.269),lip*.94*furrow*(dist>=0))
    wash((.683,.369,.321),lip*.95*furrow*(dist<0))
    wash((.773,.505,.433),lip*.29*spot(x/.017,(dist+.0030)/.00125))
    wash((.372,.216,.193),.84*np.exp(-(dist/.00069)**2)*(1-t*t))
    wash((.561,.345,.282),.30*spot((ax-.024)/.0025,(z-1.545)/.0018))
    rng=np.random.default_rng(417)
    for side in (-1,1):
        for _ in range(124):
            xx=side*rng.uniform(.008,.063)
            zp=rng.normal(1.592-.09*abs(xx),.0067)
            if rng.random()<.22:
                zp+=rng.uniform(-.025,.018)
            w=spline(SKULL,zp)[0]
            if abs(xx)>=w*.97: continue
            a=asin(xx/w)
            X=(a/(2*pi)+.5)*size
            Y=(zp-SKULL[0][0])/(SKULL[-1][0]-SKULL[0][0])*size
            radius=rng.uniform(.00025,.00090)
            rx=max(.55,radius*size/(2*pi*w*cos(a)))
            ry=max(.65,radius*size/(SKULL[-1][0]-SKULL[0][0]))
            x0,x1=max(0,int(X-3*rx)),min(size,int(X+3*rx)+1)
            y0,y1=max(0,int(Y-3*ry)),min(size,int(Y+3*ry)+1)
            yy,xxs=np.mgrid[y0:y1,x0:x1]
            dot=np.exp(-((xxs-X)/rx)**2-((yy-Y)/ry)**2)*rng.uniform(.06,.33)
            region=rgb[y0:y1,x0:x1]
            region+=(np.array([.407,.226,.167])-region)*dot[:,:,None]
    noise=rng.normal(0,.0050,(size,size,1))
    rgb[:]=np.clip(rgb+noise,0,1)
    image=bpy.data.images.new("Forester | facial complexion",size,size,alpha=False)
    image.colorspace_settings.name="sRGB"
    image.pixels.foreach_set(array.ravel())
    image.pack()
    mat=material("Forester | living complexion","bf8b70",.52)
    node=mat.node_tree.nodes.new("ShaderNodeTexImage"); node.image=image
    shader=mat.node_tree.nodes["Principled BSDF"]
    mat.node_tree.links.new(node.outputs["Color"],shader.inputs["Base Color"])
    shader.inputs["Subsurface Weight"].default_value=.045
    shader.inputs["Subsurface Scale"].default_value=.009
    return mat


def skull():
    n=160
    levels=[mix(lo,hi,j/ct) for lo,hi,ct in [(1.493,1.529,17),(1.529,1.638,104),
             (1.638,1.690,21),(1.690,1.716,12)] for j in range(ct)]+[1.716]
    rings=[]
    for z in levels:
        w,front,back=spline(SKULL,z)
        mid=(front+back)/2
        row=[]
        for i in range(n):
            a=-pi+2*pi*i/n
            x=w*sin(a)
            y=face_y(x,z) if cos(a)>=0 else mid-(back-mid)*cos(a)
            row.append((x,y,z))
        rings.append(row)
    obj=rows("01 | sculpted face and cranium",rings,complexion(),True,True)
    uv=obj.data.uv_layers.new(name="Portrait pigment")
    for poly in obj.data.polygons:
        ids=[obj.data.loops[li].vertex_index for li in poly.loop_indices]
        wrap=min(i%n for i in ids)==0 and max(i%n for i in ids)==n-1
        for li,idx in zip(poly.loop_indices,ids):
            j,i=divmod(idx,n)
            uv.data[li].uv=((n if wrap and i==0 else i)/n,(levels[j]-levels[0])/(levels[-1]-levels[0]))
    return obj


def catmull(points,count):
    pts=list(map(Vector,points))
    result=[]
    for j in range(count):
        f=j*(len(pts)-1)/(count-1); i=min(int(f),len(pts)-2); t=f-i
        a,b,c,d=pts[max(0,i-1)],pts[i],pts[i+1],pts[min(i+2,len(pts)-1)]
        result.append((2*b+(-a+c)*t+(2*a-5*b+4*c-d)*t*t+(-a+3*b-3*c+d)*t**3)*.5)
    return result


def tube(name,path,radii,mat,sides=8,part="Head"):
    rings=[]; nrm=Vector((1,0,0))
    for i,pos in enumerate(path):
        p=Vector(pos)
        t=(Vector(path[min(i+1,len(path)-1)])-Vector(path[max(0,i-1)])).normalized()
        if abs(t.dot(nrm))>.975: nrm=Vector((0,1,0))
        nrm=(nrm-t*t.dot(nrm)).normalized(); b=t.cross(nrm)
        r=radii[i] if isinstance(radii,list) else radii
        rings.append([p+r*(nrm*cos(2*pi*j/sides)+b*sin(2*pi*j/sides)) for j in range(sides)])
    return rows(name,rings,mat,True,True,part)


def neck_ears(skin):
    n=44; rings=[]
    for i in range(34):
        z=mix(1.400,1.561,i/33)
        w,front,back=spline([(1.400,.079,-.052,.070),(1.425,.063,-.049,.066),
            (1.455,.047,-.044,.060),(1.481,.041,-.039,.054),(1.512,.041,-.035,.058),
            (1.540,.046,-.032,.062),(1.561,.050,-.029,.064)],z)
        row=[]
        for j in range(n):
            a=2*pi*j/n;x=w*sin(a);c=cos(a)
            y=(front+back)/2-(back-front)/2*c
            if c>0:
                y-=c*.0043*g(abs(x)-(.013+.26*(z-1.42)),.0065)*g(z-1.477,.059)
            row.append((x,y,z))
        rings.append(row)
    rows("02 | neck and throat",rings,skin,True,True)
    earwarm=material("Forester | auricle warmth","ba8068",.57)
    for side in (-1,1):
        rings=[]
        for r in (.025,.19,.36,.53,.65,.76,.85,.94,1):
            row=[]
            for j in range(40):
                a=2*pi*j/40
                y=.005+r*(.0127*sin(a)+.005*cos(a))
                z=1.592+r*(.0237*cos(a)-.0015*sin(a))
                helix=.0056*g(r-.84,.115)
                x=.0728+.0026*r+helix+.0017*cos(a)-.0021*g(r,.43)
                row.append((side*x,y,z))
            rings.append(row)
        ear=rows("Auricle | "+str(side),rings,skin,True)
        ear.data.materials.append(earwarm)
        for p in ear.data.polygons:
            if p.index<4*40:p.material_index=1
        for name,curve,rad in [
            ("Antihelix",[(.076,.001,1.577),(.078,.007,1.586),(.078,.009,1.598),(.078,.008,1.607)],.0019),
            ("Crus",[(.078,.008,1.596),(.078,.002,1.602),(.077,-.001,1.604)],.0014),
            ("Tragus",[(.076,-.004,1.583),(.078,-.005,1.589),(.076,-.004,1.594)],.0019)]:
            path=catmull([(x*side,y,z) for x,y,z in curve],14)
            tube(name+" | "+str(side),path,[rad*(.30+.7*max(0,sin(pi*i/13))**.5) for i in range(14)],skin)


def details(skin):
    nostril=material("Forester | nostril recess","673d31",.73)
    for s in (-1,1):
        rings=[]
        for r in (.02,.45,.78,1):
            row=[]
            for i in range(22):
                a=2*pi*i/22
                x=s*(.00955+r*.0037*cos(a))
                z=1.57165+r*(.00117*sin(a)+.00110*cos(a))
                row.append((x,face_y(x,z)-.00036*(1-r*.59),z))
            rings.append(row)
        rows("Shaped nostril | "+str(s),rings,nostril,True)
    mat=material("Forester | lip parting","74483e",.56)
    data=[]
    for f in (-1,1):
        row=[]
        for i in range(55):
            t=mix(-1,1,i/54);x=.0253*t
            z=mouth(x)[1]+f*.00029*max(0,1-t*t)**.79
            row.append((x,face_y(x,z)-.00022,z))
        data.append(row)
    rows("Relaxed mouth | parted lip line",data,mat)


def eye_material():
    size=384
    Y,X=np.mgrid[0:size,0:size].astype(np.float32)
    u=(X+.5)/size-.5; v=(Y+.5)/size-.5
    # UVs represent a 32 mm square on the front of the globe.
    xx=u*.032; zz=v*.032
    r=np.sqrt(xx*xx+zz*zz)/.00685
    a=np.arctan2(zz,xx)
    out=np.ones((size,size,4),dtype=np.float32)
    ivory=np.array((.728,.699,.626))
    pink=np.array((.652,.461,.394))
    corners=np.clip(abs(xx/.014)**2.6+.15*(zz/.009)**2,0,.83)
    out[:,:,:3]=ivory+(pink-ivory)*corners[:,:,None]
    fibers=.55*np.sin(53*a+.9*np.sin(13*a)+4.2*r)+.25*np.sin(103*a-6*r)+.20*np.cos(24*a+9*r)
    golden=np.clip((1-r)*.93+.30*fibers,0,1)
    base=np.array((.285,.287,.184))+golden[:,:,None]*np.array((.191,.094,.006))
    rays=(np.cos(37*a+2*np.sin(10*a)-10*r)*.5+.5)**6*np.clip(1.2-r,0,1)
    base+=rays[:,:,None]*np.array((.126,.094,.048))
    border=np.clip((r-.81)/.17,0,1)
    base+=((.161,.144,.112)-base)*border[:,:,None]
    pupil=np.clip((.559-r)/.040,0,1)
    base+=((.067,.052,.044)-base)*pupil[:,:,None]
    iris=np.clip((1-r)/.034+.35,0,1)
    out[:,:,:3]+=(base-out[:,:,:3])*iris[:,:,None]
    lid_shadow=np.clip((zz+.0003)/.0047,0,1)*.095
    out[:,:,:3]*=1-lid_shadow[:,:,None]
    # Soft reflected window within the cornea, kept small for overcast light.
    glint=np.exp(-((xx+.00165)/.00072)**2-((zz-.0022)/.00084)**2)*.86
    out[:,:,:3]+=((.98,.94,.86)-out[:,:,:3])*glint[:,:,None]
    image=bpy.data.images.new("Forester | hazel irises",size,size,alpha=False)
    image.colorspace_settings.name="sRGB"; image.pixels.foreach_set(out.ravel()); image.pack()
    mat=material("Forester | hazel eyes","645239",.34)
    sh=mat.node_tree.nodes["Principled BSDF"]
    sh.inputs["Specular IOR Level"].default_value=.19
    sh.inputs["Coat Weight"].default_value=.055;sh.inputs["Coat Roughness"].default_value=.20
    tex=mat.node_tree.nodes.new("ShaderNodeTexImage");tex.image=image
    mat.node_tree.links.new(tex.outputs["Color"],sh.inputs["Base Color"])
    return mat


def eyes(skin):
    eye=eye_material(); lash=material("Forester | chestnut lashes","30241e",.74)
    brow_light=material("Forester | eyebrow hairs","483328",.80)
    wet=material("Forester | waterline","b7806c",.40)
    crease=material("Forester | lid crease","a27260",.67)
    rng=random.Random(43)
    for s,suf in [(-1,"R"),(1,"L")]:
        cx=s*.0293; cz=1.6167+(.00055 if s<0 else 0)
        hw=.0141
        def aperture(t):
            swell=max(0,1-t*t)**.71
            mid=cz+.00160*t
            return mid-.00365*swell*(1+.18*t), mid+.00420*swell*(1-.19*t)
        def globe(x,z):
            t=s*(x-cx)/hw
            cap=sqrt(max(0,1-(t/.9999)**2-((z-cz)/.0135)**2))
            return face_y(x,cz)-.00066-.0049*cap
        ts=[s*mix(-1,1,i/48) for i in range(49)]
        xs=[cx+s*t*hw for t in ts]
        aperture_z=[aperture(t) for t in ts]
        rings=[]
        for j in range(17):
            row=[]
            for x,(lo,hi) in zip(xs,aperture_z):
                z=mix(lo,hi,j/16);row.append((x,globe(x,z),z))
            rings.append(row)
        obj=rows("Cornea and iris | "+suf,rings,eye)
        uv=obj.data.uv_layers.new(name="Iris projection")
        for p in obj.data.polygons:
            for li in p.loop_indices:
                x,y,z=obj.data.vertices[obj.data.loops[li].vertex_index].co
                uv.data[li].uv=(.5+(x-(cx+.00100))/.032,.5+(z-(cz+.00066))/.032)
        for upper in (False,True):
            def lid(t,x,frac):
                lo,hi=aperture(t); edge=hi if upper else lo
                swell=max(0,1-t*t)**.68
                span=(.0080 if upper else -.0049)*swell
                z=edge+span*frac
                easing=frac*frac*(3-2*frac)
                y=mix(globe(x,edge)-.00027,face_y(x,z)+.00080,easing)
                y-=(.00135 if upper else .00078)*sin(pi*frac)*swell
                return x,y,z
            rings=[[lid(t,x,f) for t,x in zip(ts,xs)]
                   for f in (0,.10,.24,.41,.59,.76,.90,1)]
            lid_mesh=rows(("Upper" if upper else "Lower")+" mobile eyelid | "+suf,rings,
                          bpy.data.materials["Forester | living complexion"])
            uv=lid_mesh.data.uv_layers.new(name="Portrait pigment")
            for poly in lid_mesh.data.polygons:
                for li in poly.loop_indices:
                    x,_,z=lid_mesh.data.vertices[lid_mesh.data.loops[li].vertex_index].co
                    w=spline(SKULL,z)[0]
                    uv.data[li].uv=(.5+asin(x/w)/(2*pi),(z-SKULL[0][0])/(SKULL[-1][0]-SKULL[0][0]))
            rings=[]
            for f in (0,.35,.71,1):
                row=[]
                for t,x,(lo,hi) in zip(ts,xs,aperture_z):
                    z=(hi if upper else lo)+(-1 if upper else 1)*(.00086 if upper else .00058)*f*max(0,1-t*t)
                    row.append((x,globe(x,z)-.00040-.00032*sin(pi*f),z))
                rings.append(row)
            rows("Lacrimal margin | "+suf+str(upper),rings,lash if upper else wet)
            if upper:
                path=[Vector(lid(t,x,.67)) for t,x in zip(ts,xs)]
                path=[Vector((p.x,min(p.y,face_y(p.x,p.z))-.00008,p.z)) for p in path]
                tube("Faint upper crease | "+suf,path,[.00016*max(.04,1-t*t) for t in ts],crease,6)
                # Individual tapered lash tips follow the outer turn of the rim.
                tips=[];faces=[]
                for i in range(22):
                    t=mix(-.62,.94,i/21);x=cx+s*t*hw;_,z=aperture(t)
                    origin=Vector((x,globe(x,z)-.00066,z))
                    reach=.0016+.0018*(t+.62)/1.56
                    end=origin+Vector((s*(.0006+.0010*t),-.90*reach,.65*reach))
                    mid=(origin+end)/2+Vector((0,-.00028,-.00016))
                    idx=len(tips)
                    tips.extend([origin+Vector((-.00024,0,0)),origin+Vector((.00024,0,0)),
                                 mid+Vector((.00012,0,0)),mid+Vector((-.00012,0,0)),end])
                    faces.extend([(idx,idx+1,idx+2,idx+3),(idx+3,idx+2,idx+4)])
                surface("Upper lashes | "+suf,tips,faces,lash)
        def brow(t,f):
            x=s*mix(.0128,.0555,t)
            z=1.6288+.0057*sin(pi*max(0,t-.12)*.97)-.0014*t+(.0011+.0006*(1-t))*(s<0)
            width=.0050*max(.025,1-t**2.2)*min(1,.28+t/.12)
            z+=(f-.5)*width
            return Vector((x,face_y(x,z)-.00018-.00025*sin(pi*f),z))
        pts=[];fs=[]
        for i in range(83):
            t=mix(.012,.973,i/82)+rng.uniform(-.004,.004)
            f=rng.uniform(-.16,.45)
            start=brow(t,f); end=brow(min(1,t+.022+.049*t),min(1.18,f+rng.uniform(.50,.99)))
            mid=(start+end)/2; mid.y-=.00033
            end.y-=.00025;start.y-=.00025
            idx=len(pts)
            pts.extend([start+Vector((0,0,-.00017)),mid+Vector((0,-.00015,-.00012)),
                        end,mid+Vector((0,-.00015,.00012)),start+Vector((0,0,.00017))])
            fs.append(tuple(range(idx,idx+5)))
        surface("Individual brow hairs | "+suf,pts,fs,brow_light)


def hair_lock(name,path,width,depth,mat,normal_fn,tip=True):
    # Elliptical flattened sections, gently fluted across the broad face of
    # each lock. The local width follows the surface rather than the camera.
    rings=[]; crest=[]
    for i,p in enumerate(path):
        f=i/(len(path)-1)
        tangent=(path[min(i+1,len(path)-1)]-path[max(i-1,0)]).normalized()
        normal=normal_fn(p,f)
        normal=(normal-tangent*normal.dot(tangent)).normalized()
        sideways=tangent.cross(normal).normalized()
        taper=(.035+.965*max(0,sin(pi*f))**.48) if tip else 1
        w=width(f)*taper if callable(width) else width*taper
        d=depth(f)*taper if callable(depth) else depth*taper
        corners=[]
        for k in range(12):
            a=2*pi*k/12
            corners.append(p+sideways*(w*sin(a))+normal*(d*cos(a)*(1+.09*cos(3*a))))
        rings.append(corners)
        crest.append((p,normal,sideways,w,d))
    obj=rows(name,rings,mat,True,True,"Hair")
    grid_uv(obj,12,len(path),True)
    return crest


def grid_uv(obj,columns,levels,wrap,repeat=1):
    uv=obj.data.uv_layers.new(name="Flow of hair")
    for p in obj.data.polygons:
        ids=[obj.data.loops[li].vertex_index for li in p.loop_indices]
        seam=wrap and min(i%columns for i in ids)==0 and max(i%columns for i in ids)==columns-1
        for li,i in zip(p.loop_indices,ids):
            row,col=divmod(i,columns)
            col=columns if seam and col==0 else col
            uv.data[li].uv=(repeat*col/(columns if wrap else columns-1),row/(levels-1))


def hair_pigment():
    size=384
    v,u=(np.arange(size)+.5)[:,None]/size,(np.arange(size)+.5)[None,:]/size
    shift=.008*np.sin(2*pi*(v+2*u))+.003*np.sin(2*pi*(3*v+7*u))
    a=2*pi*(u+shift)
    broad=.24*np.cos(5*a+.5*np.cos(2*pi*v))+.21*np.sin(12*a+.38*np.cos(4*pi*v))
    fine=.11*np.cos(43*a)+.115*np.cos(67*a+.4*np.cos(2*pi*v))+.069*np.sin(122*a+v*4*pi)
    brightness=np.clip(.50+broad+fine,0,1)
    pixels=np.ones((size,size,4),np.float32)
    pixels[:,:,:3]=np.array([.186,.121,.096])+brightness[:,:,None]*np.array([.177,.119,.086])
    im=bpy.data.images.new("Forester | chestnut strands",size,size,alpha=False)
    im.colorspace_settings.name="sRGB";im.pixels.foreach_set(pixels.ravel());im.pack()
    mat=material("Forester | combed chestnut hair","493126",.56)
    sh=mat.node_tree.nodes["Principled BSDF"]
    sh.inputs["Specular IOR Level"].default_value=.22
    node=mat.node_tree.nodes.new("ShaderNodeTexImage");node.image=im
    mat.node_tree.links.new(node.outputs["Color"],sh.inputs["Base Color"])
    return mat


def scalp_point(a,z):
    w,front,back=spline(SKULL,min(z,1.7148))
    mid=(front+back)/2
    f=cos(a)
    depth=(.0038+(back-front)/2)*(f**.79 if f>0 else f)
    return Vector(((w+.0035)*sin(a),mid-depth,
                   z+.0054*max(0,(z-1.655)/.061)))


def hair():
    woven=hair_pigment()
    glints=[material("Forester | strand "+k,c,.64) for k,c in
            [("umber","4c3024"),("copper","654330"),("bronze","593b2c")]]
    rings=[]
    N=96
    for j in range(29):
        v=j/28
        row=[]
        for i in range(N):
            a=-pi+2*pi*i/N
            front=max(0,cos(a))
            line=1.559+.111*front**1.31+.022*abs(sin(a))**2
            line-=.0042*g(a-.09,.095)*front
            z=mix(line,1.7148,v)
            row.append(scalp_point(a,z))
        rings.append(row)
    scalp=rows("Scalp | hairline and nape",rings,woven,True,True,"Hair")
    grid_uv(scalp,N,len(rings),True,8)
    rng=random.Random(125)
    normal=lambda p,f: Vector((p.x/.084,(p.y-.005)/.103,(p.z-1.622)/.096))
    def filament(name,crest,fraction,radius,mat):
        path=[];rr=[]
        for i,(p,n,s,w,d) in enumerate(crest):
            t=i/(len(crest)-1)
            side=max(-.88,min(.88,fraction+.055*sin(t*5.5+fraction)))
            path.append(p+s*(w*side)+n*(d*sqrt(1-side*side)*1.07))
            rr.append(radius*(.06+.94*max(0,sin(pi*t))**.6))
        tube(name,path,rr,mat,5,"Hair")
    # An off-centre part opens just above the forehead. Broad sweeping masses
    # are interleaved with narrower temple locks in several chestnut shades.
    def sweep(s,q,t):
        # Bundles fan from the sagittal part onto the skull before turning
        # behind the ear, with the hairline swept up from the forehead.
        theta=.002+2.16*t**.91
        phi=.53+1.55*q+.06*sin(pi*t)-.46*t+.095*s*sin(pi*t)
        x=.077*sin(theta)*s+(.004+.0017*sin(pi*q*2))*(1-t)
        y=-.093*cos(phi)*cos(theta)
        z=min(1.7145,1.619+.0960*sin(phi)*cos(theta))
        a=atan2(x/.077,-y/.093)
        p=scalp_point(a,z)
        outward=normal(p,t).normalized()
        return p+outward*(.00065+.0029*sin(pi*t)*g(q-.14,.45))
    for s,suffix in [(-1,"R"),(1,"L")]:
        rings=[[sweep(s,i/51,j/50) for i in range(52)] for j in range(51)]
        base=rows("Raked hair | "+suffix,rings,woven,part="Hair")
        grid_uv(base,52,51,False,3.8)
        for j in range(13):
            f=j/12
            path=[sweep(s,f,i/42) for i in range(43)]
            for i,p in enumerate(path):
                t=i/(len(path)-1)
                p+=normal(p,t).normalized()*(.00070+.00065*sin(3*pi*t+f*2)*sin(t*pi))
            crest=hair_lock("Swept lock "+suffix+f" {j+1:02}",path,.0071+.0015*sin(f*pi),
                            .0010+.0010*(1-f),woven,normal)
            for k,t in enumerate((-.51,.30)):
                filament("Hair fibre "+suffix+f" {j+1}.{k}",crest,t,
                         rng.uniform(.00013,.00024),glints[(j+k)%3])
        # Broad dark root behind the ear and a pair of wind-loosened temple
        # curls, one reaching the chin. Their tapered tips do not mask the eyes.
        curves=[
            [(s*.028,-.077,1.670),(s*.044,-.078,1.660),(s*.057,-.070,1.647),
             (s*.064,-.067,1.635),(s*.059,-.072,1.612),
             (s*.065,-.065,1.590),(s*.062,-.061,1.569),(s*.054,-.065,1.551)],
            [(s*.063,-.056,1.635),(s*.072,-.051,1.613),(s*.070,-.052,1.593),
             (s*.073,-.042,1.573),(s*.066,-.046,1.550),(s*.071,-.045,1.536)],
            [(s*.066,-.020,1.626),(s*.073,-.018,1.610),(s*.074,-.013,1.598),
             (s*.067,-.016,1.574),(s*.071,-.011,1.557)],
        ]
        for j,curve in enumerate(curves):
            p=catmull(curve,29)
            crest=hair_lock("Temple curl "+suffix+str(j+1),p,
                            [.0039,.0017,.0055][j],[.0018,.00078,.0024][j],woven,normal)
            filament("Temple fine strand "+suffix+str(j),crest,.23,.00016,glints[2])
        # Broken fringe and sideburns soften the outline of the tucked hair.
        # Their roots begin on different locks on her left and right sides.
        offset=.0048 if s>0 else -.0017
        sizes=(.0022,.0011,.00066,.0024)
        tendrils=[
            [(.019,-.078,1.675),(.036,-.079,1.665),(.046,-.076,1.652),
             (.048,-.075,1.639),(.055,-.071,1.628),(.054,-.068,1.619)],
            [(.039,-.076,1.662),(.051,-.071,1.650),(.053,-.072,1.637),
             (.059,-.069,1.626),(.058,-.068,1.615),(.057,-.065,1.608)],
            [(.053,-.068,1.645),(.064,-.063,1.626),(.064,-.061,1.611),
             (.070,-.055,1.595),(.068,-.052,1.578),(.065,-.049,1.567)],
            [(.061,-.047,1.625),(.071,-.040,1.617),(.074,-.029,1.605),
             (.073,-.025,1.596),(.071,-.023,1.585)],
        ]
        for j,curve in enumerate(tendrils):
            points=[(s*(x+offset*sin(pi*k/(len(curve)-1))),y,
                     z+.0025*s*k/(len(curve)-1)) for k,(x,y,z) in enumerate(curve)]
            p=catmull(points,26)
            crest=hair_lock("Loose bang "+suffix+str(j),p,sizes[j],sizes[j]*.48,woven,normal)
            if j in (0,3):
                filament("Loose bang fibre "+suffix+str(j),crest,-.22,.00013,glints[1])
        for j in range(5):
            q=j/4
            p=catmull([(s*(.065+.007*q),.022+.038*q,1.628-.007*q),
                (s*(.071-.005*q),.039+.027*q,1.610-.008*q),
                (s*(.064-.011*q),.053+.025*q,1.592-.009*q),
                (s*(.050-.015*q),.063+.014*q,1.573-.011*q),
                (s*(.029-.013*q)-.013,.071,1.558+.006*q)],23)
            hair_lock("Gathered nape "+suffix+str(j),p,.0069,.0032,woven,normal)
    # Each braid lock follows a figure-eight cross-section. Three phases
    # alternate in front and behind each other as in a real three-strand plait.
    braid=catmull([(-.017,.084,1.589),(-.043,.075,1.557),(-.057,.055,1.526),
        (-.062,.032,1.502),(-.069,.006,1.482),(-.086,-.042,1.461),
        (-.107,-.091,1.417),(-.114,-.116,1.363),(-.109,-.127,1.315)],118)
    def braid_normal(p,t):
        return Vector((-.60,mix(.82,-.94,min(1,t*1.85)),.55*(1-t)))
    for j in range(3):
        points=[]
        for i,p in enumerate(braid):
            t=i/(len(braid)-1)
            tangent=(braid[min(len(braid)-1,i+1)]-braid[max(0,i-1)]).normalized()
            norm=braid_normal(p,t);norm=(norm-tangent*tangent.dot(norm)).normalized()
            side=tangent.cross(norm).normalized()
            phase=t*2*pi*3.45+j*2*pi/3
            width=mix(.0157,.0069,t)
            points.append(p+side*(width*sin(phase))+norm*(width*.41*sin(2*phase+.12)))
        crest=hair_lock("Plait | interwoven section "+str(j+1),points,lambda t:mix(.0125,.0067,t),
                        lambda t:mix(.0089,.0048,t),woven,braid_normal,False)
        for k,frac in enumerate((-.54,.0,.48)):
            filament(f"Plait fibre {j}.{k}",crest,frac,.00035 if k==1 else .00024,glints[(j+k)%3])
    tip=braid[-1]
    for i in range(7):
        off=(i-3)*.0017
        p=catmull([tuple(tip+Vector((off,-.001,0))),(-.109+off,-.127,1.306),
                   (-.106+off*1.4,-.131+.001*i,1.296),
                   (-.110+off*2,-.130+.0012*i,1.284+.003*(i%3))],16)
        hair_lock("Loose braid end "+str(i),p,.0039,.0021,woven,braid_normal)
    for k in range(3):
        p=[Vector((tip.x+.0084*cos(2*pi*i/24),tip.y+.0068*sin(2*pi*i/24),
                   tip.z+.0055-k*.0027+.0013*sin(2*pi*i/24))) for i in range(25)]
        tube("Plait | cord wrap "+str(k),p,.0017,art.mat("leather_dark"),7,"Hair")


def scarf():
    # A broad linen triangle folds around the crown. The loose rear falls wrap
    # back to the nape instead of yielding a tight cap silhouette.
    profiles=[
        (0,.083,-.052,.006,1.607,.102,.0007),
        (.18,.087,-.019,.034,1.608,.118,.0019),
        (.38,.090,.034,.068,1.603,.128,.0030),
        (.60,.092,.083,.094,1.592,.120,.0054),
        (.79,.094,.111,.104,1.579,.101,.0072),
        (1,.076,.115,.091,1.559,.065,.0093)]
    def outside_hair(p):
        # Fit the cloth to the actual skull envelope including the swept hair.
        # This also makes its folded hem lie on the head around the temples.
        z=p.z-.0055*max(0,(p.z-1.655)/.061)-.0025
        if z>1.7148 or z<1.577:
            return True
        w,f,b=spline(SKULL,z)
        w+=.0112
        if abs(p.x)>=w:
            return True
        c=sqrt(1-(p.x/w)**2);mid=(f+b)/2
        return p.y<mid-((b-f)/2+.0113)*c**.79 or p.y>mid+((b-f)/2+.0113)*c
    def point(a,t):
        w,yc,ys,zc,h,fold=spline(profiles,t)
        side=abs(sin(a))
        rib=fold*(.65*sin(7.5*a+.6*t)+.35*sin(13*a-1.6*t))
        x=(w+rib)*sin(a)
        y=mix(yc,ys,side**1.3)+.0026*side*sin(a*6+t*5)
        z=zc+h*cos(a)+.43*abs(sin(a))*rib
        # The loose corners hike up to a knot on the rear of the neck.
        if t>.7:
            q=(t-.7)/.3
            z+=.022*q**2*side**3
            y+=.009*q*side*sin(3*a)**2
        p=Vector((x,y,z))
        direction=Vector((p.x,.78*(p.y-.007),1.18*(p.z-1.613))).normalized()
        for _ in range(64):
            if outside_hair(p):break
            p+=direction*.00040
        return p
    angles=[mix(-1.91,1.91,i/64) for i in range(65)]
    rings=[[point(a,j/26) for a in angles] for j in range(27)]
    obj=rows("Kerchief | draped linen triangle",rings,art.mat("linen"),part="Hair")
    mod=obj.modifiers.new("Double linen thickness","SOLIDIFY");mod.thickness=.0017
    seam=material("Forester | kerchief hem","cbb79b",.89)
    soft=material("Forester | cream topstitch","e3d3b8",.91)
    for name,t in [("Brow",.005),("Rear",.991)]:
        p=[point(a,t) for a in angles]
        tube(name+" | folded linen edge",p,.0017,seam,8,"Hair")
    for a in (angles[0],angles[-1]):
        path=[point(a,j/33) for j in range(34)]
        tube("Side | turned kerchief hem",path,.0015,seam,7,"Hair")
    # Individually sewn dashes on the turned-under brow edge.
    verts=[];fs=[]
    for i in range(82):
        start=mix(-1.87,1.87,i/82);end=start+.022
        idx=len(verts)
        for a,t in [(start,.027),(end,.027),(end,.034),(start,.034)]:
            p=point(a,t)
            p+=Vector((sin(a)*.00055,-.00065,cos(a)*.00063))
            verts.append(p)
        fs.append((idx,idx+1,idx+2,idx+3))
    surface("Kerchief | hand-worked seam",verts,fs,soft,"Hair")
    # Cinched ties at the nape finish in two irregular leaf-shaped tails.
    for s in (-1,1):
        rings=[]
        for j in range(19):
            t=j/18
            row=[]
            for i in range(7):
                u=mix(-1,1,i/6); taper=(.11+.89*max(0,sin(pi*t))**.67)
                x=mix(.005*s,.031*s,t)+.013*taper*u
                y=.114+.013*sin(pi*t)+.005*cos(u*pi)*taper
                z=mix(1.623,1.558+(s>0)*.007,t)+.006*u*t
                row.append((x,y,z))
            rings.append(row)
        tail=rows("Kerchief | knotted tail "+str(s),rings,art.mat("linen"),part="Hair")
        mod=tail.modifiers.new("Fold thickness","SOLIDIFY");mod.thickness=.001
    for i in range(2):
        path=catmull([(-.013,.115,1.624+i*.003),(-.007,.125,1.620+i*.003),
                     (.005,.127,1.623+i*.003),(.015,.116,1.628+i*.003)],15)
        tube("Kerchief | soft knot "+str(i),path,.0053,art.mat("linen"),10,"Hair")


def build():
    skin=art.mat("skin")
    skull()
    neck_ears(skin)
    details(skin)
    eyes(skin)
    hair()
    scarf()
