"""Cast shoulder shields, articulated arms and asymmetric Ubermech attachments."""
from math import cos, pi, sin

from mathutils import Vector

import mech


TAU = 2 * pi
X = Vector((1, 0, 0))


def center(points):
    return sum(points, Vector((0, 0, 0))) / len(points)


def loft(name, rings, mat, group, bevel=0.009):
    """Close matching rings, including asymmetric and mirrored castings."""
    rings = [[Vector(p) for p in ring] for ring in rings]
    direction = center(rings[-1]) - center(rings[0])
    normal = sum((a.cross(b) for a, b in zip(rings[0], rings[0][1:] + rings[0][:1])),
                 Vector((0, 0, 0)))
    if normal.dot(direction) < 0:
        rings = [ring[::-1] for ring in rings]
    n = len(rings[0])
    faces = [tuple(reversed(range(n)))]
    for j in range(len(rings)-1):
        for i in range(n):
            k = (i+1) % n
            faces.append((j*n+i, j*n+k, (j+1)*n+k, (j+1)*n+i))
    faces.append(tuple(range((len(rings)-1)*n, len(rings)*n)))
    return mech.mesh(name, [p for ring in rings for p in ring], faces, mat, group, bevel)


def plate(name, perimeter, normal, thickness, mat, group, bevel=.005):
    n = Vector(normal).normalized()
    face = [Vector(p) for p in perimeter]
    return loft(name, [[p-n*thickness for p in face], face], mat, group, bevel)


class Axis:
    """Local cross sections perpendicular to an attachment or limb."""

    def __init__(self, start, end):
        self.start = Vector(start)
        vector = Vector(end) - self.start
        self.length = vector.length
        self.n = vector.normalized()
        self.u = (X - self.n*self.n.x).normalized()
        self.v = self.n.cross(self.u)

    def at(self, s, x=0, y=0):
        return self.start + self.n*s + self.u*x + self.v*y

    def flat_cast(self, name, sections, mat, group, bevel=.014):
        rings = []
        for depth, w, h, corner in sections:
            pts = [(-w+corner,-h),(w-corner,-h),(w,-h+corner),(w,h-corner),
                   (w-corner,h),(-w+corner,h),(-w,h-corner),(-w,-h+corner)]
            rings.append([self.at(depth,x,y) for x,y in pts])
        return loft(name,rings,mat,group,bevel)

    def turned(self, name, profile, mat, group, sides=16, bevel=.006, x=0, y=0):
        rings = [[self.at(depth,x+r*cos(TAU*i/sides),y+r*sin(TAU*i/sides))
                  for i in range(sides)] for depth,r in profile]
        return loft(name,rings,mat,group,bevel)

    def side_plaque(self, name, coords, angle, radius, thickness, mat, group, bevel=.004):
        outward=self.u*cos(angle)+self.v*sin(angle)
        tangent=self.v*cos(angle)-self.u*sin(angle)
        return plate(name,[self.at(d)+outward*radius+tangent*w for d,w in coords],
                     outward,thickness,mat,group,bevel)


def fastener(name, face, normal, radius, group):
    pos,n=Vector(face),Vector(normal).normalized()
    mech.rod(name+' | socket',pos-n*.009,pos+n*.002,radius,'black',group,12,.002)
    mech.rod(name+' | head',pos+n*.001,pos+n*.008,radius*.72,'steel',group,6,.002)


def shoulder(sign, side):
    group = 'Shoulder.'+side
    # Front face tilts upwards and slightly out. All inlaid details follow that face.
    norm = Vector((sign*.105,-1,.24)).normalized()
    def front(x,z):
        return Vector((sign*x,-.467+.105*(x-1.4)+.24*(z-4.21),z))
    def applique(name,coords,offset,thickness,mat,bevel=.005):
        return plate(name,[front(x,z)+norm*offset for x,z in coords],
                     norm,thickness,mat,group,bevel)

    # The forging is a pitched trapezoid. Its one long top edge and straight lower
    # break run diagonally over the arm; the outer return wall is a separate plane.
    def panel(s,t):
        x=(.82+.735*s)*(1-t)+(1.085+.817*s)*t
        z=(4.516+.209*s)*(1-t)+(3.708+.326*s)*t
        return x,z
    def backpoint(s,t):
        x,z=panel(s,t)
        p=front(x,z)
        return p + Vector((sign*(.171*s-.023),.865,.095-.029*s))
    rim=[(.005,.028),(.025,.005),(.978,0),(1,.018),(1,.963),(.985,.99),
         (.024,1),(0,.972)]
    outline=[panel(s,t) for s,t in rim]
    fore=[front(*p) for p in outline]
    back=[backpoint(s,t) for s,t in rim]
    loft('Shoulder | slab pauldron '+side,[fore,back],'graphite',group,.013)
    def roof(depth,s):
        return front(*panel(s,0)).lerp(backpoint(s,0),depth)
    roof_norm=(roof(.8,.5)-roof(.1,.5)).cross(roof(.2,.9)-roof(.2,.1)).normalized()
    if roof_norm.z<0:
        roof_norm.negate()
    cover=[roof(d,s)+roof_norm*.011 for d,s in [
        (.035,.033),(.08,.021),(.938,.023),(.964,.072),
        (.958,.957),(.90,.982),(.033,.972)]]
    plate('Shoulder | nonreflective crown '+side,cover,roof_norm,.016,'black',group,.005)
    for i in range(2):
        k=.54+i*.105
        vent=[roof(d,s)+roof_norm*.017 for d,s in [
            (.39,k),(.70,k+.002),(.734,k+.020),(.41,k+.023)]]
        plate('Shoulder | crown fluting '+str(i),vent,roof_norm,.011,'joint',group,.002)
    raised=[panel(.010+.980*s,.013+.974*t) for s,t in rim]
    applique('Shoulder | cast lip '+side,raised,.012,.019,'edge',.004)
    inner=[panel(.016+.968*s,.020+.960*t) for s,t in rim]
    applique('Shoulder | front casting '+side,inner,.017,.011,'graphite',.004)
    stripe=[panel(s,t) for s,t in [(.982,.422),(.754,.711),(.414,.776),
                                     (.414,.901),(.857,.961),(.983,.86)]]
    applique('Shoulder | faction flash '+side,stripe,.022,.009,'team_color',.002)
    for i,(s,t) in enumerate([(.068,.12),(.081,.798),(.92,.14),(.665,.875)]):
        x,z=panel(s,t)
        fastener('Shoulder | face bolt %s %d'%(side,i+1),front(x,z)+norm*.020,norm,.024,group)

    # Paint wraps from the front across the broad outside ramp. Two black drains
    # make the depth of that upper surface visible from a three-quarter camera.
    def outside(depth,t):
        return front(*panel(1,t)).lerp(backpoint(1,t),depth)
    outer_norm=(outside(.0,.9)-outside(.0,.1)).cross(outside(.9,.1)-outside(.0,.1)).normalized()
    if outer_norm.x*sign<0:
        outer_norm.negate()
    for label,uv,mat,offset in [
        ('Outer wing',[ (.025,.050),(.922,.066),(.951,.110),(.944,.929),(.030,.954) ],'plate',.010),
        ('Return flash',[ (.018,.418),(.941,.442),(.937,.704),(.432,.758),(.018,.854) ],'team_color',.015),
        ('Return stencil',[ (.50,.424),(.656,.430),(.674,.555),(.592,.551) ],'graphite',.018),
        ('Upper drain',[ (.29,.103),(.71,.106),(.737,.127),(.284,.144) ],'black',.015)]:
        pts=[outside(d,t)+outer_norm*offset for d,t in uv]
        plate('Shoulder | '+label+' '+side,pts,outer_norm,.014,mat,group,.002)

    # Heavy lower flange, caught by a small identification lamp.
    lip=[panel(s,t) for s,t in [(.54,.985),(.94,.976),(.986,1.001),(.944,1.08),(.58,1.08)]]
    applique('Shoulder | underside visor '+side,lip,-.012,.095,'joint',.007)
    lamp=[panel(s,t) for s,t in [(.698,1.025),(.871,1.024),(.848,1.048),(.71,1.056)]]
    applique('Shoulder | ID lamp '+side,lamp,-.009,.009,'glow_red',.001)

    # Backplate follows the taper. Exposed upper flanks retain a cast-steel finish.
    backnormal=-norm
    plate('Shoulder | rear inspection cover '+side,
          [p+backnormal*.019 for p in back],backnormal,.029,'plate',group,.015)
    for j in range(3):
        t=.38+j*.085
        vents=[backpoint(s,tt)+backnormal*.026 for s,tt in [(.23,t),(.72,t),
                                                             (.70,t+.034),(.22,t+.034)]]
        plate('Shoulder | rear louvre '+str(j),vents,backnormal,.014,'black',group,.005)
    for j,(s,t) in enumerate([(.12,.12),(.90,.89),(.87,.13)]):
        fastener('Shoulder | rear screw '+str(j),backpoint(s,t)+backnormal*.023,backnormal,.019,group)

    if sign<0:
        hub=front(*panel(.475,.43))+norm*.029
        vertical=Vector((0,0,1))
        horizontal=vertical.cross(norm).normalized()
        vertical=norm.cross(horizontal).normalized()
        # Separate outer and inner loops make the dark annulus a true opening.
        tooth_angles=[]
        for j in range(10):
            for t,r in ((-.5,.153),(-.25,.153),(-.19,.194),(.19,.194),(.25,.153)):
                tooth_angles.append(((j+t)*TAU/10,r))
        outer=[hub+(horizontal*cos(a)+vertical*sin(a))*r for a,r in tooth_angles]
        inner=[hub+(horizontal*cos(a)+vertical*sin(a))*.083 for a,_ in tooth_angles]
        outer_back=[p-norm*.009 for p in outer]
        inner_back=[p-norm*.009 for p in inner]
        vertices=outer+inner+outer_back+inner_back
        n=len(outer)
        faces=[]
        for i in range(n):
            k=(i+1)%n
            faces.extend([(i,k,n+k,n+i),(2*n+k,2*n+i,3*n+i,3*n+k),
                          (i,2*n+i,2*n+k,k),(n+k,3*n+k,3*n+i,n+i)])
        mech.mesh('Shoulder | ivory cog badge',vertices,faces,'white',group,.0018)
        mech.rod('Shoulder | crimson faction seal',hub-norm*.008,hub+norm*.001,.065,
                 'enamel',group,32,.002)
    else:
        for j in range(2):
            x,z=panel(.257,.26+j*.098)
            applique('Shoulder | slanted witness slot '+str(j),
                     [(x-.032,z+.037),(x+.004,z+.048),(x+.045,z-.04),(x+.008,z-.052)],
                     .023,.009,'joint')
        led=front(*panel(.20,.19))+norm*.029
        mech.rod('Shoulder | inspection telltale',led,led+norm*.009,.02,'glow_red',group,10,.003)


def upper_arm(sign,side):
    group='UpperArm.'+side
    pivot=Vector((sign*1.205,.005,4.015))
    mech.ellipsoid('Upper arm | floating shoulder joint '+side,pivot,(.29,.32,.30),
                   'joint',group,24,12)
    mech.rod('Upper arm | shoulder axle '+side,pivot+X*sign*(-.265),pivot+X*sign*.265,.209,
             'steel',group,20,.016)
    a=Axis((sign*1.28,.01,3.975),(sign*1.605,-.055,3.205))
    l=a.length
    a.turned('Upper arm | composite joint liner '+side,[(0,.206),(.07,.246),(l-.03,.227),
             (l,.195)],'joint',group,14,.012)
    a.flat_cast('Upper arm | vambrace casting '+side,
                [(l*.15,.248,.255,.083),(l*.26,.281,.273,.086),(l*.73,.238,.238,.07),
                 (l*.77,.217,.219,.066)],'plate',group,.018)
    a.flat_cast('Upper arm | piston clamp '+side,
                [(l*.77,.198,.213,.07),(l*.8,.233,.249,.09),(l*.91,.222,.238,.08)],
                'graphite',group,.009)
    # Raised external torque link and polished piston remain readable from the back.
    for j,off in enumerate((-.114,.117)):
        p=a.at(.14,off,-.19)
        q=a.at(l-.035,off,-.205)
        mech.rod('Upper arm | rear strut '+str(j),p,p.lerp(q,.56),.042,'joint',group,12,.007)
        mech.rod('Upper arm | bright plunger '+str(j),p.lerp(q,.50),q,.026,'steel',group,12,.004)
    elbow=Vector((sign*1.608,-.055,3.20))
    mech.rod('Upper arm | elbow hinge '+side,elbow-X*.269,elbow+X*.269,.218,
             'joint',group,24,.016)
    n=X*sign
    for j,(length,r,mat) in enumerate([(.284,.193,'edge'),(.295,.154,'graphite'),(.302,.09,'steel')]):
        mech.rod('Upper arm | elbow ring '+str(j),elbow+n*(length-.027),elbow+n*length,r,
                 mat,group,20,.007)


def gauntlet(sign,side):
    group='Forearm.'+side
    a=Axis((sign*1.61,-.059,3.20),(sign*1.798,-.325,2.55))
    l=a.length
    # The emitter side has a flared receiver and a deep offset side shield.
    extra=.063 if sign<0 else 0
    a.flat_cast('Forearm | articulated gauntlet '+side,
                [(.02,.203,.195,.06),(.10,.258+extra,.249,.08),(.20,.285+extra,.281,.07),
                 (l*.79,.269+extra,.254,.075),(l,.237,.221,.064)],'graphite',group,.016)
    a.flat_cast('Forearm | armored cuff '+side,
                [(l*.61,.278+extra,.267,.07),(l*.68,.305+extra,.284,.093),
                 (l*.98,.265+extra,.261,.076),(l*1.04,.227,.228,.073)],'plate',group,.015)
    for normal_angle in (pi/2,0 if sign>0 else pi):
        width=.124 if normal_angle==pi/2 else .104
        shape=[(.11,-width*.6),(.18,-width),(.405,-width*.72),(.469,-width*.3),
               (.435,width),(.20,width),(.12,width*.65)]
        radius=.282 if normal_angle==pi/2 else .282+extra
        a.side_plaque('Forearm | segmented cheek '+side,shape,normal_angle,radius,.078,
                      'plate',group,.012)
    if sign<0:
        # Large stepped front guard and collar locks like the pauldron's cast flanges.
        guard=[(.045,-.163),(.091,-.21),(.367,-.211),(.478,-.143),
               (.421,.132),(.315,.177),(.114,.157)]
        a.side_plaque('Forearm | front shield bevel',guard,pi/2,.325,.109,'edge',group,.017)
        center_s=.255
        inside=[(center_s+(d-center_s)*.946,t*.925) for d,t in guard]
        a.side_plaque('Forearm | front shield enamel',inside,pi/2,.335,.042,'graphite',group,.014)
        for i,(d,t) in enumerate(((.135,.102),(.385,-.145))):
            fastener('Forearm | shield lock '+str(i),a.at(d,-t,.338),a.v,.022,group)
        a.side_plaque('Forearm | raised emitter coupling',
                      [(.532,-.175),(.57,-.208),(.676,-.188),(.704,-.102),
                       (.691,.163),(.574,.194),(.523,.116)],pi/2,.31,.08,'graphite',group,.014)
    a.side_plaque('Forearm | faction cuff stripe '+side,
                  [(.160,-.046),(.195,-.066),(.405,-.049),(.422,.054),(.185,.064)],
                  pi/2,.342 if sign<0 else .289,.015,'team_color',group)
    outer=0 if sign>0 else pi
    for j in range(3):
        z=.216+j*.05
        a.side_plaque('Forearm | power gauge '+str(j),
                      [(z,-.046),(z+.021,-.046),(z+.021,.046),(z,.046)],
                      outer,.290+extra,.012,'glow_red',group,.002)
    return group


def emitter(group):
    a=Axis((-1.78,-.27,2.665),(-2.350,-1.04,1.35))
    l=a.length
    breech_end=l-.29
    a.turned('Emitter | inner field tube',[(0,.157),(.11,.23),(breech_end-.09,.182),(breech_end,.176)],
             'joint',group,12,.012)
    # Each lane sits in a milled raceway and is capped at both ends.
    for i in range(6):
        angle=i*TAU/6+pi/6
        a.side_plaque('Emitter | channel cradle '+str(i),
                      [(.14,-.048),(.20,-.079),(breech_end-.05,-.068),(breech_end,-.043),
                       (breech_end,.043),(breech_end-.05,.068),(.20,.079),(.14,.048)],
                      angle,.211,.054,'graphite',group,.012)
        a.side_plaque('Emitter | ruby field window '+str(i),
                      [(.225,-.044),(.258,-.054),(breech_end-.084,-.047),(breech_end-.034,-.032),
                       (breech_end-.034,.032),(breech_end-.084,.047),(.258,.054),(.225,.044)],
                      angle,.224,.021,'glow_red',group,.006)
        a.side_plaque('Emitter | light filament '+str(i),
                      [(.28,-.011),(breech_end-.08,-.011),(breech_end-.08,.011),(.28,.011)],
                      angle,.228,.007,'glow_core',group,.002)
    a.turned('Emitter | breech gasket',[(.035,.237),(.077,.27),(.235,.27),(.264,.224)],
             'joint',group,12,.009)
    a.turned('Emitter | cast breech crown',[(.052,.248),(.105,.288),(.191,.285),(.225,.246)],
             'plate',group,10,.013)
    a.turned('Emitter | steel bridge band',[(l*.49,.224),(l*.51,.258),(l*.59,.257),
             (l*.61,.224)],'edge',group,10,.011)
    bell=Axis(a.at(l-.355),a.at(l)+Vector((-.012,-.160,.081)))
    d=bell.length
    bell.turned('Emitter | muzzle bell',[(0,.212),(.077,.289),(d-.108,.305),
             (d-.025,.270)],'plate',group,10,.014)
    bell.turned('Emitter | dark muzzle liner',[(d-.10,.245),(d-.05,.260),(d-.007,.237)],
             'joint',group,20,.006)
    bell.turned('Emitter | luminous corona',[(d-.03,.203),(d+.001,.203),(d+.015,.154)],
             'glow_red',group,24,.005)
    bell.turned('Emitter | optic retaining ring',[(d+.006,.158),(d+.017,.151),(d+.021,.133)],
             'enamel',group,24,.003)
    bell.turned('Emitter | radiant core',[(d+.014,.130),(d+.029,.115),(d+.032,.086)],
             'glow_core',group,32,.003)


def capsule_pod(group):
    a=Axis((1.675,.262,2.804),(1.852,-.981,2.647))
    l=a.length
    a.flat_cast('Pod | central magazine',[(0,.246,.342,.072),(.099,.303,.409,.076),
                (l-.062,.324,.447,.098),(l,.30,.405,.064)],'joint',group,.019)
    a.flat_cast('Pod | rear shell',[(.026,.252,.354,.09),(.097,.317,.425,.10),
                (.33,.347,.447,.085),(.37,.323,.423,.078)],'plate',group,.015)
    a.flat_cast('Pod | cassette case',[(.38,.318,.414,.078),(.431,.335,.437,.085),
                (l-.208,.339,.437,.087),(l-.135,.312,.413,.083)],'graphite',group,.016)
    # Raised structural surround with a true recessed six-port face.
    a.flat_cast('Pod | armored aperture frame',[(l-.24,.335,.439,.086),(l-.192,.371,.477,.102),
                (l-.066,.374,.479,.102),(l,.338,.443,.083)],'edge',group,.010)
    a.flat_cast('Pod | recessed face',[(l-.01,.32,.421,.079),(l+.009,.309,.411,.072)],
                'black',group,.009)
    for r in range(3):
        for c in range(2):
            x=(c-.5)*.29
            y=(1-r)*.268
            label=str(1+r*2+c)
            a.turned('Pod | seal bezel '+label,[(l+.003,.127),(l+.024,.128),
                     (l+.044,.114)],'graphite',group,20,.004,x,y)
            a.turned('Pod | indicator gasket '+label,[(l+.04,.099),(l+.048,.102)],
                     'glow_red',group,20,.0015,x,y)
            a.turned('Pod | crimson ogive '+label,[(l+.045,.097),(l+.070,.098),
                     (l+.102,.089),(l+.15,.058),(l+.186,.018),(l+.188,.011)],
                     'enamel',group,20,.003,x,y)
    # Staggered armor side doors leave continuous separation between the cassettes.
    for i in range(2):
        start=.43+i*.35
        a.side_plaque('Pod | side cassette '+str(i),[(start,-.27),(start+.05,-.35),
                       (start+.277,-.35),(start+.306,-.28),(start+.306,.25),
                       (start+.24,.33),(start+.035,.33),(start,.26)],0,.351,.025,'plate',group,.010)
        for j,(d,h) in enumerate([(start+.062,-.239),(start+.229,.238)]):
            fastener('Pod | side latch %d %d'%(i,j),a.at(d,.352,h),a.u,.021,group)
    a.side_plaque('Pod | service cover',[(.28,-.164),(.32,-.206),(.78,-.206),
                  (.85,-.14),(.85,.14),(.78,.206),(.32,.206),(.28,.164)],
                  pi/2,.478,.08,'plate',group,.018)
    for i in range(3):
        d=.43+i*.092
        a.side_plaque('Pod | upper slot '+str(i),[(d,-.125),(d+.045,-.125),
                      (d+.045,.125),(d,.125)],pi/2,.483,.012,'black',group,.004)
    for j,off in enumerate((-.14,0,.14)):
        c=a.at(-.004,off,0)
        mech.rod('Pod | rear auxiliary connector '+str(j),c,c-a.n*.025,.054,
                 'joint',group,12,.005)


def build():
    for sign,side in [(-1,'R'),(1,'L')]:
        shoulder(sign,side)
        upper_arm(sign,side)
        group=gauntlet(sign,side)
        if sign<0:
            emitter(group)
        else:
            capsule_pod(group)
