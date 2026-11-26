"""Optional farm hat, powered hand cultivator, bundle of billets and building mallet."""
from math import cos, exp, pi, sin

import bpy
import numpy as np
from mathutils import Vector

from art import cord, loops, mat, mesh
from arms_axe import AXIS, FRONT, WING, centerline, haft_ring, ring_mesh, tint


TAU = 2*pi
V = Vector


def bitmap(name, rgb, data=False):
    h,w,_=rgb.shape
    image=bpy.data.images.new(name,w,h,alpha=False)
    if data:
        image.colorspace_settings.name="Non-Color"
    rgba=np.ones((h,w,4),np.float32)
    rgba[:,:,:3]=np.clip(rgb,0,1)
    image.pixels.foreach_set(rgba.ravel())
    image.pack()
    return image


def textured(name, swatch, roughness, rgb, relief=None, strength=.38):
    material=tint(name,swatch,0,roughness)
    nodes=material.node_tree.nodes
    bsdf=nodes["Principled BSDF"]
    sampler=nodes.new("ShaderNodeTexImage")
    sampler.image=bitmap(name+" colour",rgb)
    material.node_tree.links.new(sampler.outputs["Color"],bsdf.inputs["Base Color"])
    if relief is not None:
        dx=(np.roll(relief,-1,1)-np.roll(relief,1,1))*8
        dy=(np.roll(relief,-1,0)-np.roll(relief,1,0))*8
        vectors=np.stack((-dx,-dy,np.ones_like(dx)),axis=-1)
        vectors/=np.linalg.norm(vectors,axis=-1,keepdims=True)
        bump=nodes.new("ShaderNodeTexImage")
        bump.image=bitmap(name+" relief",.5+.5*vectors,True)
        normals=nodes.new("ShaderNodeNormalMap")
        normals.inputs["Strength"].default_value=strength
        material.node_tree.links.new(bump.outputs["Color"],normals.inputs["Color"])
        material.node_tree.links.new(normals.outputs["Normal"],bsdf.inputs["Normal"])
    return material


def surface_uv(obj,coords):
    data=obj.data
    uv=data.uv_layers.new(name="UVMap")
    for poly in data.polygons:
        values=coords(poly,list(poly.vertices))
        for idx,value in zip(poly.loop_indices,values):
            uv.data[idx].uv=value


def circular_uv(obj,count,v_positions,repeats=1):
    def mapped(poly,indices):
        ang=[i%count for i in indices]
        cross=max(ang)-min(ang)>count//2
        return [((k+(count if cross and k<count//2 else 0))/count*repeats,
                 v_positions[v//count]) for v,k in zip(indices,ang)]
    surface_uv(obj,mapped)


def straw_hat():
    n=192
    yy,xx=np.mgrid[0:n,0:n].astype(np.float32)/n
    side=np.cos(TAU*yy)
    drift=.32*np.sin(TAU*yy)
    slant=xx+drift
    reeds=np.cos(TAU*slant)
    split=np.cos(TAU*(slant*5+.12*np.sin(xx*TAU)))**4
    seam=np.exp(-((1+side)/.18)**2)
    row=.48*reeds+.12*split+.23*side-.36*seam
    grain=np.random.default_rng(293).uniform(-.1,.1,(n,n))
    tone=.98+.20*row+.05*grain
    straw=textured("Sunhat | plaited rye straw","d4a866",.78,
                  np.array((.80,.637,.391))*tone[:,:,None],row,.36)
    reed=tint("Sunhat | toasted binding","9e723f",.015,.60)
    light=tint("Sunhat | pale reeds","d6b27c",0,.76)
    count=80
    def rim(t,u):
        # The front dips away from the face; the sides turn up independently.
        a=TAU*t
        ripple=.0026*sin(3*a+.6)+.0014*cos(5*a)
        rx=.0855+(.199+ripple-.0855)*u
        ry=.104+(.189+ripple-.104)*u
        x=rx*sin(a)-.003*u*u
        y=.008-ry*cos(a)
        h=1.667+.006*sin(a)-.002*cos(a)
        fall=-.023*u+.013*u*u +u*u*(.014*sin(a)**2+.006*sin(3*a+.44)-.003*cos(a))
        return V((x,y,h+fall))
    # Brim is a thin closed annulus; the crown and liner have a genuine head opening.
    path=[(i/32,-.0029) for i in range(33)]+[(1,.0001)]+[(i/32,0) for i in range(31,-1,-1)]
    rows=[[rim(j/count,u)+V((0,0,d+.00045*cos(u*TAU*16))) for j in range(count)] for u,d in path]
    nrows=len(rows)
    faces=[(i*count+j,i*count+(j+1)%count,((i+1)%nrows)*count+(j+1)%count,
            ((i+1)%nrows)*count+j) for i in range(nrows) for j in range(count)]
    brim=mesh("Sunhat | sweeping field brim",[p for row in rows for p in row],faces,straw,True)
    circular_uv(brim,count,[u*24 for u,d in path],77)
    # Bound rolled hem; very fine individual reed lashes catch the sun at its edge.
    hem=[rim(j/120,1)+V((0,0,-.0010)) for j in range(121)]
    cord("Sunhat | bound brim edge",hem,.00225,reed,8)
    for dx,height in [(.010,.0008),(.022,.0007)]:
        cord("Sunhat | brim braid",[rim(j/144,1-dx)+V((0,0,.00065)) for j in range(145)],
             height,light,6)
    def crown_point(a,z,rx,ry,t):
        dent=(exp(-((a%(2*pi)-.63)/.36)**2)+exp(-((a%(2*pi)-5.61)/.36)**2))
        pinch=.006*exp(-((t-.71)/.25)**2)*dent
        top=.004*t*t*sin(a-.4)-.006*t**3*cos(a)**2
        return V(((rx-pinch)*sin(a)-.004*t,.008-(ry-pinch)*cos(a),
                  z+.005*sin(a)*(1-t)+top))
    profile=[(1.663,.084,.101),(1.669,.085,.103),(1.676,.084,.102),
             (1.689,.083,.100),(1.712,.078,.094),(1.730,.073,.087),
             (1.742,.063,.078),(1.750,.048,.061),(1.754,.027,.040),(1.752,.006,.010)]
    crown=[]; vrow=[]
    for i,(a,b) in enumerate(zip(profile,profile[1:])):
        for j in range(4):
            f=j/4
            z,rx,ry=(a[k]*(1-f)+b[k]*f for k in range(3))
            t=(i+f)/(len(profile)-1)
            rip=.00048*cos(2*pi*4*t*5)
            crown.append([crown_point(TAU*k/count,z,rx+rip,ry+rip,t) for k in range(count)])
            vrow.append((z-1.663)*205)
    z,rx,ry=profile[-1]
    crown.append([crown_point(TAU*k/count,z,rx,ry,1) for k in range(count)])
    vrow.append(vrow[-1]+.45)
    # Only the top of the crown is capped, leaving a real head opening.
    faces=[(i*count+j,i*count+(j+1)%count,(i+1)*count+(j+1)%count,
            (i+1)*count+j) for i in range(len(crown)-1) for j in range(count)]
    faces.append(tuple(range((len(crown)-1)*count,len(crown)*count)))
    shell=mesh("Sunhat | pinched straw crown",[p for row in crown for p in row],faces,straw,True)
    circular_uv(shell,count,vrow,45)

    def hatband(z,rx,ry):
        return [V((rx*sin(j*TAU/count),.008-ry*cos(j*TAU/count),
                   z+.005*sin(j*TAU/count))) for j in range(count)]
    band_rows=[hatband(z,rx,ry) for z,rx,ry in [
        (1.668,.0868,.1046),(1.670,.0876,.1055),(1.674,.0871,.1052),
        (1.685,.0859,.1042),(1.689,.0850,.1031),(1.690,.0841,.1022)]]
    loops("Sunhat | dark leather hatband",band_rows,"leather_dark",cap=False)
    for level,rx,ry in [(1.671,.088,.1059),(1.687,.086,.1041)]:
        points=hatband(level,rx,ry)
        cord("Sunhat | welted band border",points+[points[0]],.00075,"leather",6)
    # The woven bronze keeper and buckle sit near her anatomical left temple.
    a=.92
    center=V((.0875*sin(a),.008-.105*cos(a),1.681+.005*sin(a)))
    lateral=V((cos(a),sin(a),.03)).normalized()
    up=V((0,0,1))
    face=V((sin(a),-cos(a),0))
    coords=[(-.012,-.0085),(.011,-.0085),(.014,-.005),(.014,.006),(.011,.008),(-.011,.008),(-.014,.005),(-.014,-.005),(-.012,-.0085)]
    cord("Sunhat | brass slide buckle",[center+lateral*x+up*z+face*.002 for x,z in coords],.00145,"gold",8)
    cord("Sunhat | buckle tongue",[center+up*.006+face*.003,center-up*.003+face*.004,
                                   center-lateral*.007-up*.004+face*.003],.00085,"gold",6)
    liner=[hatband(z,rx,ry) for z,rx,ry in [(1.663,.083,.100),(1.668,.083,.098),
                                            (1.680,.082,.098),(1.682,.081,.097)]]
    loops("Sunhat | inner sweatband",liner,"leather_dark",cap=False)


def workpoint(t,w=0,f=0):
    return centerline(t)+WING*w+FRONT*f


def pin(name,p,axis,radius,height,finish):
    v=axis.cross(V((1,0,0)))
    if v.length<.1: v=axis.cross(V((0,0,1)))
    v.normalize()
    w=axis.cross(v).normalized()
    return ring_mesh(name,[[p+axis*z+(v*cos(TAU*k/12)+w*sin(TAU*k/12))*r for k in range(12)]
                           for z,r in [(0,radius),(.65*height,radius),(height,radius*.68)]],finish)


def shaft(labels,profile,finish):
    return ring_mesh(labels,[haft_ring(t,r,n=24) for t,r in profile],finish)


def collar(name,start,end,radius,finish):
    shaft(name,[(start,radius-.0013),(start+.0013,radius),(end-.0014,radius),(end,radius-.0012)],finish)


def farmer_grip(name,start,end,radius=.0228):
    shaft(name,[(start,radius*.89),(start+.006,radius),(end-.007,radius),(end,radius*.89)],"leather_dark")
    for i in range(7):
        t=start+.008+i*(end-start-.022)/6
        rows=[]
        for off,r in [(0,radius-.0003),(.0012,radius+.0007),(.0036,radius+.0007),(.0048,radius-.0003)]:
            rows.append([workpoint(t+off+.0025*sin(a*TAU/24),r*cos(a*TAU/24),r*.86*sin(a*TAU/24))
                         for a in range(24)])
        ring_mesh(name+" | seam",rows,"leather")


def farmtool():
    silver=tint("Cultivator | planished faces","9aa7af",.78,.31)
    cyan=tint("Cultivator | blue crystal","1cbbfc",.30,.26,1.45)
    dark=tint("Cultivator | blue steel","566575",.72,.37)
    wood=tint("Work gear | oiled hickory","87613f",0,.50)
    shaft("Cultivator | long hickory haft",[(-.02,.022),(.09,.024),(.20,.020),
          (.31,.0205),(.54,.021),(.70,.020),(.85,.022),(.90,.024)],wood)
    farmer_grip("Cultivator | upper grip",.187,.300)
    farmer_grip("Cultivator | lower grip",.572,.713)
    for a,b,r,finish in [(.051,.103,.026,"gold"),(.110,.125,.024,"iron"),
                         (.305,.320,.023,"brass_dark"),(.534,.552,.023,"gold"),
                         (.722,.730,.022,"brass_dark"),(.862,.90,.026,"gold")]:
        collar("Cultivator | socket band",a,b,r,finish)
    # The grip-to-grip steel channel contains a protected blue insert on both flanks.
    shaft("Cultivator | protected power spine",[(.319,.021),(.328,.0224),(.526,.0226),(.538,.021)],dark)
    for side in [-1,1]:
        for name,rad,w0,finish in [("steel bezel",.0204,.0075,"steel"),("crystal window",.0212,.0042,cyan)]:
            shape=[(.337,-w0*.4),(.346,-w0),(.513,-w0),(.521,-w0*.45),
                   (.519,w0*.55),(.512,w0),(.344,w0),(.336,w0*.42)]
            ring_mesh("Cultivator | "+name,[[workpoint(t,w,side*z) for t,w in shape]
                    for z in (rad-.0015,rad)],finish,False,.00025)
    # A diagonal cross-head lets all three curved tines read in the neutral carry.
    cross=[(-.076,-.027),(-.062,-.044),(.046,-.035),(.077,-.015),
           (.072,.024),(.047,.042),(-.055,.027),(-.076,.009)]
    for name,scale,half,fin in [("iron socket",1,.037,dark),("gilt cheek",.84,.0392,"gold")]:
        if name=="iron socket":
            depths=[-half,half]
            ring_mesh("Cultivator | "+name,[[workpoint(t*scale,w*scale,z) for t,w in cross] for z in depths],fin,False,.0025)
        else:
            for sign in [-1,1]:
                ring_mesh("Cultivator | "+name,[[workpoint(t*scale,w*scale,sign*z) for t,w in cross]
                       for z in (.0369,half)],fin,False,.00065)
                for t in [-.042,.032]:
                    pin("Cultivator | cheek peg",workpoint(t,-.003,sign*half),FRONT*sign,.004,.0024,"steel")
    for tine in (-1,0,1):
        # A forged rectangular root transitions to a curved, diamond-section point.
        path=[]
        for dt,dw,wide,deep in [(-.012,.007,.014,.012),(-.047,.024,.016,.013),
            (-.079,.042,.016,.012),(-.110,.070,.014,.010),(-.134,.103,.0117,.0083),
            (-.158,.135,.0083,.006),(-.180,.160,.0042,.0031),(-.190,.170,.00085,.0013)]:
            fraction=max(0.,(dw-.007)/.163)
            t=dt+tine*(.029+.016*fraction)
            w=dw+tine*(.007+.006*fraction)
            path.append((workpoint(t,w,tine*(.026+.017*fraction)),wide,deep))
        rings=[]
        for i,(p,width,depth) in enumerate(path):
            tangent=(path[min(i+1,len(path)-1)][0]-path[max(0,i-1)][0]).normalized()
            lateral=FRONT.cross(tangent).normalized()
            face=tangent.cross(lateral).normalized()
            section=[(-1,0),(-.70,-.70),(0,-1),(.71,-.67),(1,0),(.68,.65),(0,1),(-.71,.70)]
            rings.append([p+lateral*x*width+face*f*depth for x,f in section])
        obj=ring_mesh("Cultivator | forged tine "+str(tine+2),rings,silver,False,.0005)
        obj.data.materials.append(mat("steel"));obj.data.materials.append(dark)
        for poly in obj.data.polygons:
            if len(poly.vertices)==4:
                j=poly.vertices[0]%8
                poly.material_index=1 if j in (0,3,4,7) else 0
        for sign in [-1,1]:
            pts=[]
            for i in range(1,5):
                p,width,depth=path[i]
                pts.append(p+FRONT*depth*sign)
            cord("Cultivator | blue tine inlay",pts,.00135,cyan,6)


def mallet():
    wood=tint("Work gear | oiled hickory","87613f",0,.50)
    end=tint("Mallet | hornbeam end grain","b88d5d",0,.62)
    shaft("Mallet | oval handle",[(-.025,.018),(.052,.021),(.115,.018),
                                 (.212,.019),(.278,.0195),(.341,.021),(.359,.023)],wood)
    farmer_grip("Mallet | finger grip",.190,.289,.0223)
    collar("Mallet | handle heel",.338,.357,.0235,"brass_dark")
    collar("Mallet | ferrule",.057,.075,.0227,"gold")
    def section(w,rx,ry,cut):
        points=[(-rx+cut,-ry),(rx-cut,-ry),(rx,-ry+cut),(rx,ry-cut),(rx-cut,ry),
                (-rx+cut,ry),(-rx,ry-cut),(-rx,-ry+cut)]
        return [workpoint(.014+x,w,y) for x,y in points]
    stations=[(-.091,.035,.031),(-.086,.043,.036),(-.073,.043,.037),(-.032,.039,.034),
              (.030,.040,.034),(.072,.043,.037),(.089,.043,.037),(.096,.037,.0315)]
    obj=ring_mesh("Mallet | joiner's hornbeam head",[section(w,rx,ry,.007) for w,rx,ry in stations],
                  wood,False,.0009)
    obj.data.materials.append(end)
    for poly in obj.data.polygons:
        if len(poly.vertices)>4:poly.material_index=1
    for w in (-.069,.070):
        ring_mesh("Mallet | peened retaining hoop",
                  [section(w+d,rx,ry,.0078) for d,rx,ry in [(-.0061,.042,.036),
                   (-.005,.0442,.0385),(.005,.0442,.0385),(.0061,.042,.036)]],
                  "iron",False,.0006)
        for side in (-1,1):
            pin("Mallet | band rivet",workpoint(.014,w,side*.0384),FRONT*side,.0033,.0018,"brass_dark")
    for side in (-1,1):
        pin("Mallet | haft pin",workpoint(.014,-.006,side*.0347),FRONT*side,.0044,.0022,"gold")
    # Endgrain shows growth arcs on the flat, replaceable wooden blow faces.
    for sense,w in [(-1,-.0911),(1,.0961)]:
        for i,rad in enumerate([.012,.021,.030]):
            path=[workpoint(.012+rad*cos(a*TAU/52),w+sense*.00012,
                            .002+rad*.72*sin(a*TAU/52)) for a in range(53)]
            cord("Mallet | growth line",path,.00038,"leather",5)


def bark_finishes():
    n=256
    v,u=np.mgrid[0:n,0:n].astype(np.float32)/n
    x,y=TAU*u,TAU*v
    ridges=18*x+1.4*np.sin(3*x+2*y)+.8*np.sin(5*x-3*y)
    clefts=np.exp(-((1-np.cos(ridges))/.19)**2)
    small=.5+.5*np.cos(41*x+.95*np.sin(4*y+2*x))
    pores=np.random.default_rng(632).uniform(0,1,(n,n))
    flake=.5+.5*np.sin(12*x+3*y)*np.sin(11*y-3*x)
    height=.37*small-.70*clefts+.18*flake+.18*pores
    bark=textured("Timber | split oak bark","725440",.83,
        np.array((.372,.292,.208))*(1+.40*height[:,:,None]),height,.48)
    x,y=(u-.53)*2,(v-.47)*2
    r=np.sqrt(x*x+(y*1.04)**2)
    a=np.arctan2(y,x)
    deformed=r+.014*np.sin(3*a)*r+.01*np.cos(7*a)*r+.02*np.sin(3*r)
    growth=np.exp(-((np.cos(TAU*deformed*12)-.85)/.22)**2)
    split=np.zeros((n,n))
    for angle in [-1.45,.16,2.68]:
        distance=np.arctan2(np.sin(a-angle-.055*np.sin(6*r)),np.cos(a-angle-.055*np.sin(6*r)))
        split+=np.exp(-(distance/.012)**2)*np.clip((r-.62)*7,0,1)
    tone=1.06-.19*growth-.37*split+.05*pores-.085*(1-r)
    cut=textured("Timber | sawn oak rings","c69866",.73,np.array((.79,.608,.415))*tone[:,:,None])
    return bark,cut


def timber():
    bark,cut=bark_finishes()
    count=24
    # The thin lower billet is the true two-hand contact for carrying this load.
    specs=[(-.295,.293,-.307,1.114,.045),(-.258,.273,-.236,1.103,.041),
           (-.281,.303,-.264,1.169,.0385),(-.268,.248,-.319,1.159,.0245),
           (-.285,.285,-.327,1.065,.0185),(-.25,.235,-.251,1.062,.021)]
    for i,(x0,x1,y,z,rad) in enumerate(specs):
        rings=[]
        levels=[0,.008,.072,.22,.40,.59,.76,.934,.991,1]
        for f in levels:
            x=x0+(x1-x0)*f
            bend=sin(pi*f)
            cy=y+(.0027*sin(i*2.1+.6)*bend if i!=4 else 0)
            cz=z+(.0039*cos(i+.3)*bend if i!=4 else 0)
            row=[]
            for k in range(count):
                a=TAU*k/count
                variation=1+.040*sin(5*a+i)+.028*cos(7*a+.7*i)+.026*sin(3*a+i+f)
                r=rad*variation*(1-.055*f)
                edge=(-.0017 if f in (0,1) else 0)
                row.append(V((x if f not in (0,1) else x+.0015*sin(a*4+i),
                              cy+(r+edge)*cos(a),cz+(r+edge)*sin(a))))
            rings.append(row)
        log=ring_mesh("Timber | billet "+str(i+1),rings,bark,False,.0008)
        log.data.materials.append(cut)
        for poly in log.data.polygons:
            if len(poly.vertices)>4:poly.material_index=1
            else:poly.use_smooth=True
        def coords(poly,indices):
            if poly.material_index:
                return [(.5+(log.data.vertices[k].co.y-y)/rad*.47,
                         .5+(log.data.vertices[k].co.z-z)/rad*.47) for k in indices]
            angular=[j%count for j in indices]
            seam=max(angular)-min(angular)>count//2
            return [((j+(count if seam and j<count//2 else 0))/count,(.23*i+levels[k//count]*1.9))
                    for k,j in zip(indices,angular)]
        surface_uv(log,coords)
    # Taut lashings span the convex hull of the different round sections.
    rope=tint("Timber | weathered hemp","ae9165",0,.85)
    for center in [-.224,.220]:
        for winding in range(3):
            loop=[]
            for j in range(97):
                a=TAU*j/96
                ny,nz=cos(a),sin(a)
                winner=max(specs,key=lambda q:q[2]*ny+q[3]*nz+q[4])
                y,z,rad=winner[2:]
                rad=rad*1.025+.003
                x=center+(winding-1)*.0065+.001*sin(a+.5*winding)
                loop.append(V((x,y+ny*rad,z+nz*rad)))
            cord("Timber | hemp lashing",loop,.0038,rope,9)
        base=V((center,-.353,1.12))
        for s in (-1,1):
            path=[base+V((s*x,y,z)) for x,y,z in [(-.012,-.002,-.012),(-.005,-.004,-.008),
                  (.006,-.007,-.001),(.008,-.005,.004),(.003,-.004,.006),(-.004,-.006,.002),
                  (-.006,-.009,-.005),(-.014,-.013,-.018),(-.023,-.011,-.031)]]
            cord("Timber | square hitch",path,.00355,rope,8)


def build():
    from harvest_trug import build as harvest_trug
    result=[]
    for group,builder in [("Sunhat",straw_hat),("FarmingTool",farmtool),
                          ("MaterialLoad",timber),("BuildingHammer",mallet),
                          ("FoodBasket",harvest_trug)]:
        before=set(bpy.context.scene.objects)
        builder()
        created=set(bpy.context.scene.objects)-before
        for obj in created:
            obj["part"]="HarvestGrapes" if group=="FoodBasket" and obj.name.startswith("Harvest |") else group
        result.extend(sorted(created,key=lambda o:o.name))
    return result
