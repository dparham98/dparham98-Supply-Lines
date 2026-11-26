"""Sculpted sleeves, fingerless forestry gloves and the woodcutting axe."""
from math import cos, exp, pi, radians, sin

import bpy
import numpy as np
from mathutils import Vector

from art import bevel, cord, linear, loops, mat, mesh


V = Vector
ORIGIN = V((-.390,-.250,1.360))
AXIS = V((.70,-.010,-.555)).normalized()
WING = V((AXIS.z,0,-AXIS.x)).normalized()
FRONT = WING.cross(AXIS).normalized()
TAU = 2*pi


def tint(name, hex_color, metallic, roughness, glow=0):
    material = bpy.data.materials.get(name)
    if material:
        return material
    material = bpy.data.materials.new(name)
    material.use_nodes = True
    color = (*linear(hex_color),1)
    shader = material.node_tree.nodes.get("Principled BSDF")
    shader.inputs["Base Color"].default_value = color
    shader.inputs["Metallic"].default_value = metallic
    shader.inputs["Roughness"].default_value = roughness
    if glow:
        shader.inputs["Emission Color"].default_value = color
        shader.inputs["Emission Strength"].default_value = glow
    material.diffuse_color = color
    return material


def workpiece(t,w=0,f=0):
    return ORIGIN + AXIS*t + WING*w + FRONT*f


def centerline(t):
    return workpiece(t,.007*sin(pi*t/.900)**2)


def normal(axis, radial):
    v = V(radial)
    return (v-axis*v.dot(axis)).normalized()


def haft_ring(t,radius,depth=None,n=24):
    depth = radius*.85 if depth is None else depth
    return [centerline(t)+WING*(radius*cos(TAU*i/n))+FRONT*(depth*sin(TAU*i/n)) for i in range(n)]


def ring_mesh(name,rows,finish,smooth=True,edge=0):
    obj=loops(name,rows,finish,smooth)
    if edge:
        bevel(obj,edge)
    return obj


def skin_tube(name,path,radii,side,finish,n=14,smooth=True):
    rows=[]
    radial=V(side)
    for i,(p,(width,depth)) in enumerate(zip(path,radii)):
        axis=(path[min(i+1,len(path)-1)]-path[max(0,i-1)]).normalized()
        radial=normal(axis,radial)
        cross=axis.cross(radial)
        rows.append([p+radial*(width*cos(j*TAU/n))+cross*(depth*sin(j*TAU/n)) for j in range(n)])
    return ring_mesh(name,rows,finish,smooth)


def closed_sheet(name,rows,thickness,finish,edge=0):
    """Join the sculpted front, back and rolled rim of a curved strip."""
    width=len(rows[0])
    count=width*len(rows)
    front=[p for row in rows for p in row]
    back=[p-thickness for p in front]
    faces=[]
    for i in range(len(rows)-1):
        for j in range(width-1):
            v=i*width+j
            face=(v,v+1,v+1+width,v+width)
            faces.extend([face,tuple(k+count for k in reversed(face))])
    rim=list(range(width))+[i*width+width-1 for i in range(1,len(rows))]
    rim+=list(range(count-2,count-width-1,-1))+[i*width for i in range(len(rows)-2,0,-1)]
    faces.extend([(a,b,b+count,a+count) for a,b in zip(rim,rim[1:]+rim[:1])])
    obj=mesh(name,front+back,faces,finish,False)
    if edge:
        bevel(obj,edge)
    return obj


def ash_grain(obj,sections,material):
    """Pack longitudinal ash figuring into the game material, using a seam on the rear."""
    width,height=240,512
    v,u=np.mgrid[0:height,0:width].astype(np.float32)
    u=u/width*TAU
    v=v/height
    wave=13*u+.95*np.sin(2*u+v*7)+.42*np.sin(5*u-v*11)
    latewood=np.exp(-((np.cos(wave)-.82)/.14)**2)
    fine=np.cos(49*u+1.1*np.sin(3*u+v*13))**16
    noise=np.random.default_rng(4164).random((height,width),dtype=np.float32)
    luminance=1.04-.24*latewood-.13*fine +.055*np.cos(4*u+4*v)+.04*(noise-.5)
    pixels=np.ones((height,width,4),dtype=np.float32)
    pixels[:,:,:3]=np.array(linear("875a37"),dtype=np.float32)*luminance[:,:,None]
    tex=bpy.data.images.new("Forester | waxed ash figuring",width,height,alpha=False)
    tex.pixels.foreach_set(pixels.ravel())
    tex.pack()
    sampler=material.node_tree.nodes.new("ShaderNodeTexImage")
    sampler.image=tex
    material.node_tree.links.new(sampler.outputs["Color"],material.node_tree.nodes["Principled BSDF"].inputs["Base Color"])
    data=obj.data
    uv=data.uv_layers.new(name="UVMap")
    n=24
    for face in data.polygons:
        seam=0 in {v%n for v in face.vertices} and n-1 in {v%n for v in face.vertices}
        for loop in face.loop_indices:
            index=data.loops[loop].vertex_index
            angle=index%n
            uu=(angle+n if seam and angle==0 else angle)/n
            uv.data[loop].uv=(uu,(sections[index//n][0]+.045)/.947)


def axe():
    ash=tint("Waxed ashwood","86582f",.01,.45)
    grain=tint("Dark ash grain","694528",.015,.49)
    face=tint("Forged blue steel","71828c",.76,.31)
    bright=tint("Honed silver edge","d2dee1",.84,.22)
    cyan=tint("Forestry crystal","21b9fa",.30,.26,1.30)
    shaft=[(-.045,.017),(.006,.023),(.058,.025),(.110,.023),(.17,.020),
           (.255,.020),(.37,.0205),(.50,.021),(.605,.0195),(.719,.020),(.807,.022),
           (.864,.0235),(.894,.027),(.902,.022)]
    handle=ring_mesh("Axe | waxed ash haft",[haft_ring(t,r) for t,r in shaft],ash)
    ash_grain(handle,shaft,ash)
    # Long, tapering streaks follow the grain along the exposed middle of the ash.
    for i,angle in enumerate([-.71,.36,1.31,2.30,3.66,4.48]):
        path=[]
        for j in range(10):
            t=.316+j*.020
            a=angle+.05*sin(j*.65+i)
            r=.0205+.00025*j/9
            path.append(centerline(t)+WING*(r*cos(a))+FRONT*(r*.85*sin(a)))
        cord("Axe | ash figuring "+str(i+1),path,.00038,grain,5)
    for i,(start,end) in enumerate([(.187,.300),(.572,.713)]):
        rows=[haft_ring(t,r) for t,r in [
            (start,.0201),(start+.004,.0221),(start+.013,.0228),
            (end-.014,.0228),(end-.004,.0221),(end,.0203)]]
        ring_mesh(f"Axe | leather grip {i+1}",rows,"leather_dark")
        for j in range(6):
            t=start+.006+j*(end-start-.020)/6
            rows=[]
            for length,r in [(0,.0223),(.0018,.0234),(.004,.0226)]:
                pts=[]
                for k in range(24):
                    a=k*TAU/24
                    tt=t+.0035*sin(a)+length
                    pts.append(centerline(tt)+WING*(r*cos(a))+FRONT*(r*.87*sin(a)))
                rows.append(pts)
            ring_mesh(f"Axe | grip {i+1} binding {j+1}",rows,"leather",True)
    for name,start,end,r in [("head ferrule",.057,.100,.027),("heel shoe",.862,.900,.0275)]:
        ring_mesh("Axe | "+name,[haft_ring(t,rr,n=12) for t,rr in [
            (start,r-.003),(start+.002,r),(end-.004,r),(end,r-.002)]],"gold",False,.00065)
    for t in [.102,.111,.849,.858]:
        ring_mesh("Axe | bronze wire",[haft_ring(t,.0237),haft_ring(t+.0021,.0238)],"brass_dark")
    # Narrow raised spiral windings protect the exposed wood between the palms.
    for k,(a,b,turns,r) in enumerate([(.320,.489,3.30,.0220),(.732,.832,2.15,.0234)]):
        rows=[]
        for i in range(90):
            u=i/89
            theta=TAU*(.22+turns*u)
            t=a+(b-a)*u
            width=.005*min(1,.21+u*15,.21+(1-u)*15)
            rows.append([centerline(t+dx)+WING*(rr*cos(theta))+FRONT*(rr*.87*sin(theta))
                         for dx,rr in [(-width,r),(-.78*width,r+.0007),
                                       (.78*width,r+.0007),(width,r)]])
        # This slender leather ribbon winds around the timber; its dark return
        # makes the cut edges readable at gameplay scale.
        faces=[]
        for i in range(len(rows)-1):
            for j in range(3):
                v=i*4+j
                faces.append((v,v+1,v+5,v+4))
        ribbon=mesh("Axe | spiral binding "+str(k+1),[p for row in rows for p in row],faces,"leather_dark")
        solid=ribbon.modifiers.new("Leather thickness","SOLIDIFY")
        solid.thickness=.001
        solid.offset=-1
        for t in (a-.002,b-.0015):
            ring_mesh("Axe | binding keeper", [haft_ring(t,r+.0015,n=20),
                      haft_ring(t+.0045,r+.0015,n=20)],"brass_dark",False,.00035)

    # Consecutive stations describe the honed arc and the backed return edge.
    # A broad steel field separates the bright edge from the narrow crystal inlay.
    stations=[
        ((-.111,.051),(-.066,.034)), ((-.112,.080),(-.045,.011)),
        ((-.104,.114),(-.013,.009)), ((-.086,.146),(.018,.014)),
        ((-.059,.176),(.041,.037)), ((-.027,.202),(.047,.083)),
        ((.014,.225),(.068,.131)), ((.059,.240),(.092,.170)),
        ((.112,.250),(.124,.216)), ((.148,.254),(.147,.250)),
    ]
    fractions=(0,.125,.225,.66,1)
    depth=(.0018,.0085,.0120,.0140,.0100)
    rows=[]
    for i,(cut,poll) in enumerate(stations):
        tip=.22 if i==len(stations)-1 else (.66 if i==len(stations)-2 else 1)
        rows.append([workpiece(cut[0]+(poll[0]-cut[0])*u,cut[1]+(poll[1]-cut[1])*u,d*tip)
                     for u,d in zip(fractions,depth)])
    front=[v for row in rows for v in row]
    back=[p-FRONT*(2*(p-ORIGIN).dot(FRONT)) for p in front]
    n=len(front)
    faces=[]
    slots=[]
    for i in range(len(rows)-1):
        for j in range(4):
            v=i*5+j; poly=(v,v+1,v+6,v+5)
            faces += [poly,tuple(p+n for p in reversed(poly))]
            slot=(0,1,2,2)[j]
            slots.extend([slot,slot])
    rim=list(range(5))+[5*i+4 for i in range(1,len(rows))]
    rim+=list(range(n-2,n-6,-1))+[5*i for i in range(len(rows)-2,0,-1)]
    faces += [(a,b,b+n,a+n) for a,b in zip(rim,rim[1:]+rim[:1])]
    slots += [1]*len(rim)
    blade=mesh("Axe | crescent felling blade",front+back,faces,bright,False)
    blade.data.materials.append(mat("steel")); blade.data.materials.append(face)
    for poly,slot in zip(blade.data.polygons,slots): poly.material_index=slot
    bevel(blade,.0009)

    for side in (-1,1):
        f=side*FRONT
        # An inset channel follows the lower beard. It is deliberately interrupted.
        for q,(first,last) in enumerate([(2,4),(5,8)]):
            for inner in (False,True):
                strip=[]
                for j in range(first,last+1):
                    cut,poll=stations[j]
                    center=.315 if j<5 else .33
                    half=(.023 if inner else .042)*(1 if j not in [first,last] else .59)
                    h=.0130+(.0013 if inner else .0005)
                    strip.append([workpiece(cut[0]+(poll[0]-cut[0])*x,cut[1]+(poll[1]-cut[1])*x,side*h)
                                  for x in (center-half,center+half)])
                closed_sheet(f"Axe | {'crystal' if inner else 'inlay seat'} {q+1} {side}",strip,f*.001,
                             cyan if inner else "iron",.00022)
    shape=[(-.062,-.041),(.040,-.047),(.061,-.030),(.061,.019),(.024,.052),(-.020,.057),
           (-.053,.033),(-.068,.007)]
    def plaque(name,outline,sidedepth,material,base=0):
        # Convex-sided socket cast in one piece around the haft.
        rings=[[workpiece(t,w,z) for t,w in outline] for z in (base,sidedepth)]
        return ring_mesh(name,rings,material,False,min(.0011,.22*abs(sidedepth-base)))
    plaque("Axe | forged eye",shape,.024, "iron",-.024)
    cap=[(-.077,-.050),(-.065,-.063),(.036,-.062),(.058,-.052),(.051,-.036),(-.053,-.037)]
    plaque("Axe | burnished poll cap",cap,.0282,"steel",-.0282)
    for s in (-1,1):
        side_shape=[(t*.94,w*.91) for t,w in shape]
        plaque("Axe | gilt cheek "+str(s),side_shape,s*.0268,"gold",s*.0235)
        shield=[(-.040,-.014),(.025,-.017),(.037,.006),(.004,.033),(-.027,.020)]
        plaque("Axe | inset escutcheon "+str(s),shield,s*.0284,"iron",s*.0267)
        lunette=[(-.051,-.029),(-.040,-.036),(.029,-.036),(.044,-.029),(.030,-.020),(-.041,-.020)]
        plaque("Axe | crystal bezel "+str(s),lunette,s*.0289,"iron",s*.0261)
        stone=[(-.044,-.029),(-.038,-.0325),(.027,-.0325),(.035,-.029),(.027,-.025),(-.037,-.025)]
        plaque("Axe | eye crystal "+str(s),stone,s*.02935,cyan,s*.0287)
        # A simple star in brass relief on the cheek, sized for the close-up.
        marks=[(-.004+( .011 if i%2==0 else .0035)*cos(i*pi/6),
                 .006+(.011 if i%2==0 else .0035)*sin(i*pi/6)) for i in range(12)]
        plaque("Axe | cheek sun "+str(s),marks,s*.0294,"gold",s*.0282)
        for j,(t,w) in enumerate([(-.048,-.023),(.039,-.018),(-.022,.041)]):
            washer=[(t+.0036*cos(k*TAU/12),w+.0036*sin(k*TAU/12)) for k in range(12)]
            plaque(f"Axe | cheek rivet {s} {j}",washer,s*.0282,"steel",s*.0264)
    ring_mesh("Axe | exposed end grain",[haft_ring(-.053,.014,n=16),
              haft_ring(-.043,.018,n=16)],ash,False,.00055)


def hands(side,t):
    word="right" if side<0 else "left"
    grip=centerline(t)
    # The operator's wrists approach opposite radial faces of the handle. Each
    # digit wraps the haft itself; the distal two joints emerge from the gauntlet.
    radial=normal(AXIS,WING*(-side)-FRONT*.54)
    tangent=normal(AXIS,FRONT)
    tangent=(tangent-radial*radial.dot(tangent)).normalized()
    wrist=grip+radial*.057-tangent*.034+AXIS*.012
    knuckle=grip+radial*.030+tangent*.010
    path=[wrist, wrist.lerp(knuckle,.28)+radial*.007,
          wrist.lerp(knuckle,.56)+radial*.009, wrist.lerp(knuckle,.83)+radial*.005,knuckle]
    skin_tube("Glove | "+word+" palm",path,[(.025,.017),(.030,.019),(.039,.018),
              (.041,.015),(.037,.0115)],AXIS,"leather_dark",18)
    # A shaped overlay, fitted to the dorsum rather than a freestanding badge.
    shield=[]
    travel=(knuckle-wrist).normalized()
    dome=normal(travel,radial)
    breadth=normal(travel,AXIS)
    for u,w,h in [(.08,.018,.014),(.25,.026,.017),(.57,.032,.018),(.82,.033,.014),(.93,.026,.012)]:
        center=wrist.lerp(knuckle,u)+radial*(.007*sin(pi*u))
        shield.append([center+breadth*(v*w)+dome*(h*(1-.48*abs(v))) for v in [-1,-.6,0,.6,1]])
    closed_sheet("Glove | "+word+" stitched back",shield,dome*.003,"leather",.00085)
    for u in [-1,1]:
        cord("Glove | "+word+" dorsal seam",[row[0 if u<0 else -1]+dome*.0004 for row in shield[1:-1]],
             .00064,"thread",5)

    nail=tint("Fieldworn nails","bf9482",0,.56)
    def nail_plate(name,tip,out,along,radius,width,length):
        along=normal(out,along)
        across=out.cross(along)
        rows=[]
        for factor,d in [(.96,radius-.0007),(1,radius),(.72,radius+.0005)]:
            rows.append([tip+out*d+along*(length*factor*cos(k*TAU/12))
                         +across*(width*factor*sin(k*TAU/12)) for k in range(12)])
        ring_mesh(name,rows,nail)
    lengths=[1,.99,.92,.84]
    offsets=[-.030,-.010,.009,.027]
    for i,(offset,size) in enumerate(zip(offsets,lengths)):
        # Four independent knuckles lead into three slightly flattened phalanges.
        def finger(theta,r):
            a=radians(theta)
            ax=t+offset+.003*sin(a)-.004*max(0,(theta-100)/65)
            return centerline(ax)+(radial*cos(a)+tangent*sin(a))*r
        angles=[-8,9,31,56,78,97,116,135,151,160]
        if i==3: angles=[v*.91 for v in angles]
        radii=[.031,.033,.034,.032,.0295,.0272,.0262,.0255,.0243,.0236]
        outline=[(.008,.008),(.0093,.0090),(.0098,.0090),(.009,.0081),(.0087,.0083),
                 (.008,.0076),(.0081,.0076),(.0078,.0072),(.0065,.0066),(.0032,.003)]
        path=[finger(a,r) for a,r in zip(angles,radii)]
        radii=[(x*size,y*size) for x,y in outline]
        skin_tube(f"Hand | {word} finger {i+1}",path,radii,AXIS,"skin",14)
        sleeve_path=path[:5]+[path[4].lerp(path[5],.22)]
        sleeve_size=[(x*1.14,y*1.16) for x,y in radii[:5]]+[tuple(v*1.14 for v in radii[4])]
        skin_tube(f"Glove | {word} finger {i+1}",sleeve_path,sleeve_size,AXIS,"leather_dark",14)
        a=radians(angles[7])
        out=(radial*cos(a)+tangent*sin(a)).normalized()
        nail_plate(f"Hand | {word} nail {i+1}",path[7],out,path[8]-path[6],
                   .0073*size,.0044*size,.0056*size)
    # The opposing thumb travels from the wrist-side saddle over the index finger.
    thumb=[]
    for angle,ax,r in [(-18,-.025,.034),(-35,-.035,.037),(-61,-.045,.035),
                       (-86,-.047,.031),(-114,-.044,.030),(-136,-.037,.028),
                       (-152,-.030,.025)]:
        a=radians(angle)
        thumb.append(centerline(t+ax)+(radial*cos(a)+tangent*sin(a))*r)
    dims=[(.014,.013),(.014,.014),(.012,.011),(.010,.010),(.0100,.009),(.009,.008),(.005,.0045)]
    skin_tube("Hand | "+word+" thumb",thumb,dims,AXIS,"skin",16)
    skin_tube("Glove | "+word+" thumb saddle",thumb[:4],[(x*1.12,y*1.12) for x,y in dims[:4]],
              AXIS,"leather_dark",16)
    a=radians(-136)
    nail_plate("Hand | "+word+" thumb nail",thumb[-2],radial*cos(a)+tangent*sin(a),
               thumb[-1]-thumb[-3],.0083,.0055,.0064)
    return wrist


def sleeve(side,elbow):
    word="right" if side<0 else "left"
    shoulder=V((side*.179,.002,1.389))
    direction=(elbow-shoulder).normalized()
    x=normal(direction,V((side,0,0)))
    y=direction.cross(x)
    def row(t,width,depth,fold,hem=0):
        result=[]
        for j in range(40):
            a=j*TAU/40
            pleats=.50*cos(6*a+1.3*t)+.31*sin(9*a-.7*t)+.19*sin(13*a+t)
            folds=0
            if t<.737:
                # Compression above the rolled elbow gathers in broken diagonal
                # ridges, with the sleeve still falling freely at the shoulder.
                for height,slant,phase,strength in [(.43,.10,.4,.0038),(.56,.10,2.0,.0045),
                                                   (.69,.071,-.75,.0050)]:
                    center=height+slant*cos(a+phase)
                    weight=.50+.50*cos(a-phase*.83)**2
                    folds+=weight*strength*(exp(-((t-center+.029)/.036)**2)
                                           -.91*exp(-((t-center)/.025)**2))
            distance=t+hem*(.53*sin(a+.4)+.32*sin(3*a+.7)+.15*sin(5*a-.2))
            p=shoulder.lerp(elbow,distance)
            result.append(p+x*((width+fold*pleats+folds)*cos(a))+y*((depth+fold*pleats+folds)*sin(a)))
        return result
    envelope=[(.005,.020,.024,.001),(.063,.040,.042,.0015),(.150,.049,.051,.002),
              (.25,.053,.056,.0030),(.39,.055,.057,.0044),(.51,.053,.055,.0048),
              (.64,.051,.053,.0050),(.71,.052,.055,.0035),(.78,.049,.052,.0035),
              (.82,.045,.048,.002)]
    rows=[]
    for step in range(35):
        u=.005+step*(.82-.005)/34
        for a,b in zip(envelope,envelope[1:]):
            if u<=b[0]+1.e-9:
                f=(u-a[0])/(b[0]-a[0])
                rows.append(row(u,*[a[j]*(1-f)+b[j]*f for j in (1,2,3)]))
                break
    ring_mesh("Sleeve | "+word+" gathered linen",rows,"linen")
    rows=[row(*q) for q in [
        (.734,.048,.051,.002,.017),(.744,.053,.056,.003,.022),
        (.759,.055,.057,.003,.024),(.794,.055,.057,.0031,.026),
        (.808,.053,.055,.0026,.030),(.845,.052,.054,.003,.033),
        (.875,.049,.051,.002,.021),(.885,.045,.048,.002,.020)]]
    ring_mesh("Sleeve | "+word+" double turnback",rows,"linen")
    ring_mesh("Sleeve | "+word+" folded hem",[
        row(.841,.052,.054,.0029,.032),row(.853,.052,.054,.003,.032),
        row(.864,.051,.053,.002,.026)],"linen_shadow")
    return shoulder


def forearm(side,wrist):
    word="right" if side<0 else "left"
    elbow=V((side*(.245 if side<0 else .254),-.034,1.118))
    shoulder=sleeve(side,elbow)
    axis=(wrist-elbow).normalized()
    n=normal(axis,V((side*.60,-.79,.41)))
    b=axis.cross(n)
    shape=[(-.19,.038,.041),(-.12,.041,.043),(0,.041,.042),(.13,.043,.044),
           (.29,.043,.043),(.46,.038,.037),(.70,.0315,.032),(.85,.027,.028),
           (1,.024,.024),(1.055,.022,.020)]
    def armrow(t,rx,ry,nseg=28):
        center=elbow.lerp(wrist,t)
        if t<0:
            center=elbow.lerp(shoulder,-t*.82)
        return [center+n*(rx*cos(j*TAU/nseg))+b*(ry*sin(j*TAU/nseg)) for j in range(nseg)]
    ring_mesh("Arm | "+word+" exposed forearm",[armrow(*q) for q in shape],"skin")
    def profile(t):
        return .0397-(t-.34)*.022
    rows=[armrow(t,profile(t)+r,profile(t)+r+.001) for t,r in [
        (.344,-.001),(.354,.0028),(.38,.0032),(.56,.0029),(.79,.0027),
        (.91,.0025),(.925,.0008)]]
    ring_mesh("Bracer | "+word+" leather backing",rows,"leather_dark")
    for j,t in enumerate([.38,.82]):
        ring_mesh(f"Bracer | {word} strap {j+1}",[armrow(tt,profile(tt)+r,profile(tt)+r+.001)
             for tt,r in [(t,.003),(t+.009,.005),(t+.053,.005),(t+.062,.003)]],"leather")
    panels=[]
    for t,spread,edge in [(.316,34,.005),(.347,64,.008),(.39,81,.010),
                          (.52,82,.010),(.68,77,.010),(.84,74,.008),(.90,47,.006)]:
        c=elbow.lerp(wrist,t)
        pts=[]
        for u in [-1,-.72,-.36,0,.36,.72,1]:
            a=radians(u*spread)
            r=profile(t)+edge+.0018*(1-abs(u))
            pts.append(c+n*(r*cos(a))+b*(r*sin(a))+axis*(.006*abs(u) if t<.40 else -.004*abs(u)))
        panels.append(pts)
    closed_sheet("Bracer | "+word+" curved steel splint",panels,n*.0045,"iron",.0011)
    for idx in (0,-1):
        cord("Bracer | "+word+" rolled rim", [row[idx]+n*.0004 for row in panels],.0012,"steel",7)
    # Chased sprig in the steel, corresponding to the leaf on the field pouch.
    def chasing(t,angle):
        a=radians(angle)
        r=profile(t)+.0126
        return elbow.lerp(wrist,t)+(n*cos(a)+b*sin(a))*r
    cord("Bracer | "+word+" chased stem",[chasing(t,a) for t,a in
         [(.49,-3),(.54,0),(.61,2),(.68,2),(.73,3)]],.00085,"steel",6)
    for j,(t,a) in enumerate([(.53,-17),(.60,16)]):
        cord(f"Bracer | {word} chased leaf {j+1}",[chasing(t,1),chasing(t+.009,a*.62),
             chasing(t+.037,a),chasing(t+.063,a*.85),chasing(t+.041,a*.41),
             chasing(t+.009,2)],.00068,"steel",6)
    for j,k in [(1,1),(1,-2),(-2,1),(-2,-2)]:
        p=panels[j][k]
        h=(p-elbow-axis*(p-elbow).dot(axis)).normalized()
        v=normal(h,axis); w=h.cross(v)
        ring_mesh("Bracer | "+word+" gilt pin",[
            [p+h*d+(v*cos(i*TAU/12)+w*sin(i*TAU/12))*r for i in range(12)]
            for d,r in [(0,.0028),(.0015,.0028),(.0027,.0016)]],"gold")


def build():
    prior=set(bpy.context.scene.objects)
    axe()
    tool=set(bpy.context.scene.objects)-prior
    for obj in tool:
        obj["part"]="WoodcuttingAxe"
    for side,t in [(-1,.235),(1,.648)]:
        wrist=hands(side,t)
        forearm(side,wrist)
    arms=set(bpy.context.scene.objects)-prior-tool
    for obj in arms:
        obj["part"]="Arms"
    return sorted(arms|tool,key=lambda o:o.name)
