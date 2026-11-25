"""Field boots, pleated trousers and leather forestry kit for the resting carry."""
from math import cos, exp, pi, sin
from mathutils import Vector

from art import bevel, cord, loops, mat, mesh, volume

TAU=2*pi

def leg_center(side,z):
    # The left foot carries a little more weight. The right toe leads.
    low=min(1,max(0,(.83-z)/.73))
    x=side*(.083+.041*low)+.009*(1-low)
    y=.002+(.040 if side==1 else -.028)*low
    y-=.029*exp(-((z-.47)/.14)**2)
    return x,y

def pants(side):
    label="L" if side==1 else "R"
    shape=[(.312,.044,.045),(.346,.050,.048),(.367,.056,.056),
           (.385,.060,.059),(.400,.058,.054),(.419,.061,.063),
           (.438,.067,.066),(.455,.066,.058),(.473,.065,.067),
           (.492,.069,.070),(.511,.067,.064),(.539,.073,.079),
           (.580,.076,.083),(.648,.080,.086),(.72,.083,.089),(.81,.084,.085)]
    n=32
    rings=[]
    for k,(z,rx,ry) in enumerate(shape):
        x,y=leg_center(side,z)
        ring=[]
        for j in range(n):
            a=TAU*j/n
            amp=(.002+.0022*exp(-((z-.44)/.095)**2))
            rumple=amp*(sin(5*a+side*8*z)+.6*sin(8*a-13*z+.2))
            fold=exp(-((z-.45)/.105)**2)
            h=z+fold*(.012*sin(2*a+k*.39+side*.4)+.008*sin(a-side*.7))
            ring.append((x+(rx+rumple)*sin(a),y-(ry+rumple)*cos(a),h))
        rings.append(ring)
    loops("Gathered field trousers "+label,rings,"trousers")
    # A double-stitched outside seam disappears under the skirt.
    points=[]
    for z,rx,ry in shape[4:]:
        x,y=leg_center(side,z)
        points.append((x+side*(rx-.001),y+.015,z))
    cord("Trouser seam "+label,points,.0019,"leather_dark",5)

def boot(side):
    label="L" if side==1 else "R"
    x,y=leg_center(side,.09)
    yaw=-side*.095
    def space(xx,yy,zz):
        return (x+xx*cos(yaw)-yy*sin(yaw),y+xx*sin(yaw)+yy*cos(yaw),zz)
    n=36
    def foot_ring(front,back,width,height):
        ring=[]
        for j in range(n):
            a=TAU*j/n
            co,si=cos(a),sin(a)
            # Rounded toe box, narrower heel, and a softened instep on the inside.
            sx=(1 if si>=0 else -1)*abs(si)**.73
            sy=(1 if co>=0 else -1)*abs(co)**.78
            breadth=width*(1+.10*co-.10*max(-co,0))
            xx=sx*breadth+side*(.009*max(co,0)-.003)
            yy=-sy*(front if co>0 else back)
            z=height(co,si) if callable(height) else height
            ring.append(space(xx,yy,z))
        return ring
    sole_rings=[foot_ring(fr,ba,wd,h) for fr,ba,wd,h in [
        (.157,.074,.052,.000),(.160,.076,.056,.007),
        (.160,.076,.057,.022),(.156,.075,.055,.029)]]
    loops("Layered boot sole "+label,sole_rings,"sole")
    loops("Welt "+label,[foot_ring(.158,.075,.056,.025),foot_ring(.157,.074,.055,.032)],"welt")
    rings=[foot_ring(.155,.073,.054,.030),
           foot_ring(.151,.071,.054,lambda c,s:.043+.005*(1-c)),
           foot_ring(.143,.069,.053,lambda c,s:.053+.015*(1-max(c,0))),
           foot_ring(.119,.067,.051,lambda c,s:.067+.025*(1-max(c,0))),
           foot_ring(.094,.061,.046,lambda c,s:.083+.028*(1-max(c,0))),
           foot_ring(.067,.058,.042,.128),foot_ring(.057,.055,.043,.153)]
    loops("Shaped vamp and vamp quarters "+label,rings,"boot")
    zrows=[(.104,.044,.060),(.130,.043,.057),(.144,.046,.055),
           (.153,.047,.055),(.162,.044,.050),(.180,.045,.049),
           (.192,.050,.055),(.204,.051,.055),(.216,.049,.049),
           (.240,.053,.052),(.283,.057,.055),(.332,.059,.055),
           (.355,.064,.058),(.368,.065,.060),(.377,.064,.058)]
    def shin_point(z,rx,ry,a):
        lx,ly=leg_center(side,z)
        return (lx+rx*sin(a),ly-ry*cos(a),z+.004*sin(2*a+.5)*exp(-((z-.19)/.075)**2))
    shaft_rings=[[shin_point(z,rx,ry,TAU*i/n) for i in range(n)] for z,rx,ry in zrows]
    loops("Creased boot shaft "+label,shaft_rings,"boot")
    def band(name,z,rx,ry,h,finish,tilt=0):
        rings=[]
        for dz,expand in ((-h/2,0),(-h/2+.0018,.0012),(h/2-.0018,.0012),(h/2,0)):
            row=[]
            for j in range(n):
                a=TAU*j/n
                lz=z+dz+tilt*sin(a)
                row.append(shin_point(lz,rx+expand,ry+expand,a))
            rings.append(row)
        loops(name+" "+label,rings,finish)
    band("Turned cuff",.360,.066,.061,.032,"leather_dark",side*.013)
    band("Cuff rim",.377,.0665,.062,.006,"welt",side*.013)
    band("Boot top strap",.321,.0625,.058,.016,"leather_dark",side*.012)
    band("Ankle strap",.174,.049,.055,.016,"leather_dark",-side*.012)
    # Boot tongue and side quarters frame the crossed laces.
    def tongue(z,u):
        if z<.12:
            ly=-.100+(.12-z)*-.74
            return space(u*.020,ly,z)
        lx,ly=leg_center(side,z)
        t=(z-.12)/.18
        return (lx+u*(.021+.002*t),ly-(.054+.002*t)+.003*u*u,z)
    tongue_rows=[.128,.146,.170,.195,.22,.25,.28,.316]
    uv=[tongue(z,t) for z in tongue_rows for t in (-1,0,1)]
    faces=[(i*3+k,i*3+k+1,i*3+k+4,i*3+k+3) for i in range(7) for k in (0,1)]
    ob=mesh("Boot tongue "+label,uv,faces,"leather_dark")
    for k in (-1,1):
        cord("Tongue piping "+label,[tongue(z,k) for z in tongue_rows],.00135,"welt")
    levels=[.144,.166,.188,.211,.235,.262,.288,.310]
    for i in range(len(levels)-1):
        for k in (-1,1):
            a=Vector(tongue(levels[i],k))
            b=Vector(tongue(levels[i+1],-k))
            a.y-=.002
            b.y-=.002
            mid=(a+b)*.5
            mid.y-=.0018 if k==1 else .0004
            cord("Cross lace "+label,[a,mid,b],.0016,"welt",5)
    # Discrete heel counter seam and toe cap stitching.
    arc=[space(.050*sin(a),-.101-.015*cos(a),.069-.017*abs(sin(a))) for a in [(-1+i/12)*1.39 for i in range(25)]]
    cord("Toe cap seam "+label,arc,.0013,"welt")
    lx,ly=leg_center(side,.321)
    buckle=volume("Boot strap clasp "+label,(lx+side*.061,ly-.007,.333),(.003,.012,.011),"gold",radius=.0024)
    volume("Boot strap clasp center "+label,(lx+side*.0638,ly-.007,.333),(.0009,.007,.006),"leather_dark",radius=.0007)

def waist_point(a,z,dx=0):
    return ((.141+dx)*sin(a),.003-(.105+dx)*cos(a),z-.007*cos(a)+.003*sin(a))
def waist_band(name,low,high,dx,finish):
    rings=[[waist_point(TAU*j/64,z,dx+inc) for j in range(64)] for z,inc in [
        (low,-.001),(low+.0018,.001),(high-.0018,.001),(high,-.001)]]
    loops(name,rings,finish)

def belt():
    waist_band("Broad waist belt",1.001,1.054,.0005,"leather")
    for z in (1.004,1.050):
        waist_band("Dark burnished belt edge",z-.0014,z+.0014,.0021,"leather_dark")
    # The brass frame is hollow, with a tongue placed over its leather strap.
    cx,cy,cz=.023,-.108,1.021
    volume("Buckle understrap",(cx,cy+.005,cz),(.036,.005,.016),"leather_dark",radius=.003)
    corners=[(-.026,-.017),(-.023,-.020),(.022,-.020),(.025,-.017),
             (.025,.016),(.022,.019),(-.023,.019),(-.026,.016)]
    points=[(cx+u,cy,cz+z) for u,z in corners]
    cord("Cast buckle",points+[points[0]],.0032,"gold",8)
    cord("Buckle tongue",[(cx-.022,cy-.001,cz),(cx+.007,cy-.0035,cz),(cx+.025,cy-.001,cz)],.0019,"gold")
    for a in (-.48,.68,2.3,-2.25):
        for dz in (1.004,1.048):
            p=Vector(waist_point(a,dz,.005))
            volume("Keeper rivet",p,(.0026,.0019,.0026),"gold",(0,0,a),.0015)
        ob=volume("Leather belt keeper",waist_point(a,1.026,.004),(.007,.003,.0255),"leather_dark",(0,0,a),.002)
    for i in range(4):
        a=.315+.057*i
        ob=volume("Belt eyelet",waist_point(a,1.025,.0031),(.0018,.0018,.0018),"brass_dark",(0,0,a),.0012)

def pouch():
    # The broad pouch curves around the right hip. Its outside face is slightly
    # forward so the leaf clasp can also be read in the character's front view.
    tangent=Vector((.76,-.65,0))
    normal=Vector((-.65,-.76,0))
    up=Vector((0,0,1))
    center=Vector((-.147,-.064,.928))
    def loc(u,d,h):
        return center+tangent*u+normal*d+up*(h-.10*u)
    for u in (-.039,.038):
        p=loc(u,-.014,.045)
        direction=Vector((p.x,p.y-.003,0))
        factor=((direction.x/.143)**2+(direction.y/.108)**2)**-.5
        outer=Vector((0,.003,0))+direction*factor
        inward=-direction.normalized()
        path=[p, .52*p+.48*(outer+up*1.016), outer+up*1.023,
              outer+up*1.051, outer+inward*.006+up*1.053,
              outer+inward*.010+up*1.041, p+inward*.009]
        strip=[point+tangent*d for point in path for d in (-.006,.006)]
        faces=[(2*i,2*i+1,2*i+3,2*i+2) for i in range(len(path)-1)]
        keeper=mesh("Satchel belt suspension",strip,faces,"leather_dark")
        keeper.modifiers.new("Leather thickness","SOLIDIFY").thickness=.0025
    rings=[]
    for z,rx,ry in [(-.064,.051,.020),(-.058,.063,.027),(-.044,.068,.030),(.022,.070,.031),(.048,.067,.028)]:
        ring=[]
        for j in range(36):
            a=TAU*j/36
            s,c=sin(a),cos(a)
            ring.append(loc(rx*(1 if s>=0 else -1)*abs(s)**.54,
                            ry*(1 if c>=0 else -1)*abs(c)**.44,z))
        rings.append(ring)
    loops("Leather field satchel",rings,"leather")
    sections=[(-.023,.044),(-.016,.051),(.0,.054),(.023,.050),(.032,.042),
              (.034,.026),(.035,.008),(.035,-.003)]
    us=[-1+i/8 for i in range(17)]
    verts=[]
    for depth,z in sections:
        for u in us:
            last=(.014*u*u if z<.015 else .003*u*u)
            verts.append(loc(.067*u, depth-.005*abs(u)**4,z+last))
    faces=[(i*17+j,i*17+j+1,(i+1)*17+j+1,(i+1)*17+j) for i in range(len(sections)-1) for j in range(16)]
    flap=mesh("Shaped satchel flap",verts,faces,"leather_dark")
    thick=flap.modifiers.new("Folded leather edge","SOLIDIFY")
    thick.thickness=.0028
    edge_pts=[loc(.067*u,.0355-.005*abs(u)**4,-.003+.014*u*u) for u in us]
    cord("Piped flap edge",edge_pts,.0016,"welt")
    for j in range(14):
        a=-.89+j*.13
        cord("Flap saddle stitch",[loc(.067*u,.036-.004*abs(u)**4,.002+.014*u*u) for u in (a,a+.069)],.00065,"thread",4)
    for s in (-1,1):
        leaf=[(0,.011),(.006*s,.021),(.015*s,.030),(.013*s,.020),(.008*s,.014)]
        mesh("Forestry leaf clasp",[loc(.002+u,.0365,h) for u,h in leaf],[(0,1,2,3,4)],"gold",False)
    strap=mesh("Satchel clasp tongue",[loc(u,.0377,h) for u,h in [(-.006,.009),(.007,.009),(.008,-.025),(.0,-.031),(-.006,-.026)]],[(0,1,2,3,4)],"leather")
    strap.modifiers.new("Tongue thickness","SOLIDIFY").thickness=.002
    buckle=[loc(u,.040,h) for u,h in [(-.009,-.004),(.010,-.004),(.010,-.015),(-.009,-.015),(-.009,-.004)]]
    cord("Satchel brass clasp",buckle,.0018,"gold")
    # A short cased honing stone hangs from the opposite rear hip.
    ob=volume("Stone sheath",(.149,.058,.920),(.018,.028,.070),"leather_dark",(0,.14,-.29),.009)
    volume("Sheath flap",(.169,.054,.950),(.005,.025,.027),"leather",(0,.14,-.29),.004)
    volume("Sheath fastener",(.173,.052,.933),(.0019,.004,.004),"brass_dark",(0,.14,-.29),.0016)

def build():
    for side in (-1,1):
        pants(side)
        boot(side)
    belt()
    pouch()
