"""Coat sleeves, artificial arm and hand props in the original infantry bind pose."""
from math import cos, pi, radians, sin

import bpy
from mathutils import Matrix, Vector


class Assembly:
    def __init__(self, k, name, bone):
        self.k, self.name, self.bone = k, name, bone
        self.verts, self.faces, self.slots, self.face_slots = [], [], [], []

    def solid(self, rings, side_material, cap_material=None, face_materials=None):
        """Loft closed cross sections and orient the exposed faces outwards."""
        count = len(rings[0])
        vertices = [Vector(p) for ring in rings for p in ring]
        centre = sum(vertices, Vector()) / len(vertices)
        offset = len(self.verts)
        self.verts += vertices

        def face(indices, mat):
            points = [vertices[i] for i in indices]
            normal = (points[1]-points[0]).cross(points[2]-points[0])
            if normal.dot(sum(points, Vector())/len(points)-centre) < 0:
                indices = list(reversed(indices))
            self.faces.append(tuple(offset + i for i in indices))
            if mat not in self.slots:
                self.slots.append(mat)
            self.face_slots.append(self.slots.index(mat))

        face(list(range(count)), cap_material or side_material)
        for j in range(len(rings)-1):
            for i in range(count):
                t = (i+1) % count
                mat = face_materials(j, i) if face_materials else side_material
                face([j*count+i, j*count+t, (j+1)*count+t, (j+1)*count+i], mat)
        face(list(range(len(vertices)-count,len(vertices))), cap_material or side_material)

    def finish(self):
        weights = [self.bone(v) for v in self.verts] if callable(self.bone) else self.bone
        return self.k.mesh(self.name,self.verts,self.faces,self.slots,weights,self.face_slots)


def frame(origin, axis, broad_face):
    """Width, thickness and length axes for a fitted section."""
    z = Vector(axis).normalized()
    y = Vector(broad_face)
    y = (y-z*y.dot(z)).normalized()
    x = y.cross(z).normalized()
    return (Vector(origin),x,y,z)


def pt(f, x,y,z):
    return f[0] + f[1]*x + f[2]*y + f[3]*z


def section(hw, hd, cut=.28):
    return [(-hw+hw*cut,-hd),(hw-hw*cut,-hd),(hw,-hd+hd*cut),
            (hw,hd-hd*cut),(hw-hw*cut,hd),(-hw+hw*cut,hd),
            (-hw,hd-hd*cut),(-hw,-hd+hd*cut)]


def shell(assembly, f, samples, mat, cap=None, faces=None):
    rings = [[pt(f,x+dx,y+dy,t) for x,y in section(w,h,c)] for t,w,h,c,dx,dy in samples]
    assembly.solid(rings,mat,cap,faces)


def pad(assembly,f,outline,back,front,mat,rim):
    """An extruded plate on the width/length plane."""
    assembly.solid([[pt(f,x,depth,t) for x,t in outline] for depth in (back,front)],rim,mat)


def disk(assembly, f, cx, t, rings, mat, cap=None, sides=10):
    outlines = [[pt(f,cx+r*cos(i*2*pi/sides),depth,t+r*sin(i*2*pi/sides))
                 for i in range(sides)] for depth,r in rings]
    assembly.solid(outlines,mat,cap)


def upper_sleeve(k, side, shoulder, elbow):
    sign=1 if side=='L' else -1
    bone='upper_arm.'+side
    def shoulder_weights(v):
        if v.z<1.275:
            return bone
        # The neck end stays sewn to the bodice while the outer sleeve rolls with the arm.
        t=max(0.,min(1.,(abs(v.x)-.145)/.173))
        return {'chest':.68*(1-t),bone:.32+.68*t}
    sleeve=Assembly(k,'Overcoat upper sleeve.'+side,shoulder_weights)
    # The top is inset under the yoke. Below the upper seam the octagonal section
    # turns into the hanging sleeve and narrows towards the elbow opening.
    stations=[
        (Vector((sign*.216,.071,1.326)),.073,.096),
        (Vector((sign*.264,.073,1.302)),.078,.104),
        (Vector((sign*.291,.082,1.251)),.080,.104),
        (shoulder.lerp(elbow,.56)+Vector((0,-.009,.014)),.083,.093),
        (shoulder.lerp(elbow,.89),.077,.084),
        (elbow+Vector((0,0,.012)),.071,.077),
    ]
    rings=[]
    for centre,w,d in stations:
        rings.append([centre+Vector((x,y,-sign*x*.30)) for x,y in section(w,d,.47)])
    sleeve.solid(rings,k.wool)
    sleeve.finish()

    epaulette=Assembly(k,'Team shoulder tab.'+side,shoulder_weights)
    # Each section crosses the shoulder from front to back. The coloured cloth
    # rolls down over the seam, keeping a definite coloured plane in front view.
    rings=[]
    for x,top,y_front,y_back,front_drop in [
            (.148,1.375,-.047,.146,.033),(.180,1.365,-.073,.164,.038),
            (.250,1.344,-.078,.166,.038),(.291,1.331,-.071,.165,.040),
            (.326,1.316,-.052,.154,.045),(.338,1.295,-.032,.135,.033)]:
        yz=[(y_front,top-front_drop),(y_front+.009,top-front_drop+.013),
            (y_front+.051,top-.005),(y_front+.084,top),(y_back-.048,top-.003),
            (y_back-.009,top-.020),(y_back,top-.034)]
        rr=[Vector((sign*x,y,z)) for y,z in yz]
        rings.append(rr+[p-Vector((0,0,.007)) for p in reversed(rr)])
    epaulette.solid(rings,k.team,k.leather,lambda j,i: k.team if i<6 else k.leather)
    epaulette.finish()


def cuff_and_glove(k, elbow, wrist, gun_hand):
    f = frame(elbow,wrist-elbow,(.56,-.80,.1))
    length=(wrist-elbow).length
    p=Assembly(k,'Overcoat lower sleeve.L','forearm.L')
    shell(p,f,[(-.037,.075,.071,.42,0,0),(.019,.086,.078,.40,0,0),
               (length*.72,.071,.064,.38,0,0),(length+.012,.064,.060,.32,0,0)],k.wool)
    shell(p,f,[(length-.033,.073,.067,.35,0,0),(length-.022,.076,.070,.35,0,0),
               (length+.013,.069,.064,.35,0,0)],k.wool_light,k.leather)
    p.finish()

    g=Assembly(k,'Articulated glove.L','hand.L')
    glove_frame=frame(wrist,gun_hand-wrist,(.85,-.35,.17))
    size=(gun_hand-wrist).length
    shell(g,glove_frame,[(-.023,.046,.044,.41,0,0),(.012,.058,.052,.36,0,0),
                         (size*.75,.061,.054,.38,0,0),(size+.018,.054,.042,.40,0,0)],
          k.leather)
    # Curl four separate knuckle blocks along the palm. Their shared bevel
    # catches the studio light without requiring skin or normal textures.
    for n in range(4):
        x=(n-1.5)*.027
        t=size*.55+.007*(1.5-abs(n-1.5))
        shell(g,glove_frame,[(t,.014,.026,.5,x,.032),
                             (t+.019,.014,.031,.40,x,.031),
                             (t+.056-abs(n-1.4)*.008,.011,.023,.40,x,.020)],k.leather)
    shell(g,glove_frame,[(.024,.021,.030,.42,.047,-.020),(.061,.024,.026,.48,.063,-.017),
                         (.090,.016,.024,.49,.059,-.006)],k.leather)
    g.finish()


def artificial_forearm(k, elbow, wrist):
    f=frame(elbow,wrist-elbow,(-.68,-.74,.08))
    p=Assembly(k,'Cyborg elbow and wrist.R','forearm.R')
    dark, steel, block=k.blacksteel,k.steel,k.gunmetal
    shell(p,f,[(-.027,.062,.064,.38,0,0),(.041,.076,.072,.38,0,0),
               (.273,.047,.051,.38,0,0),(.361,.055,.058,.38,0,0)],dark)
    shell(p,f,[(.000,.078,.067,.40,0,0),(.031,.097,.079,.36,0,0),
               (.124,.094,.079,.33,0,0),(.172,.079,.073,.29,0,0),
               (.205,.078,.071,.28,0,0)],block)
    # Outer elbow boss and inner bearing share the same pivot line.
    disk(p,f,0,.063,[(.075,.037),(.083,.042),(.087,.033)],dark,block)
    disk(p,f,0,.063,[(.088,.027),(.091,.025)],steel,block)
    disk(p,f,0,.063,[(-.080,.026),(-.073,.038)],dark)
    pad(p,f,[(-.084,.100),(-.070,.087),(-.057,.095),(-.058,.147),(-.068,.174),(-.078,.176)],
        .060,.077,dark,dark)
    shell(p,f,[(.183,.081,.073,.3,0,0),(.196,.084,.077,.3,0,0),
               (.207,.080,.069,.3,0,0)],dark)
    shell(p,f,[(.220,.072,.065,.30,0,0),(.235,.082,.075,.29,0,0),
               (.302,.088,.076,.28,0,0),(.348,.071,.070,.27,0,0),
               (.368,.060,.061,.30,0,0)],block)
    pad(p,f,[(-.050,.240),(.051,.240),(.063,.252),(.059,.303),
             (.041,.321),(-.046,.321),(-.060,.301)],.065,.082,block,steel)
    pad(p,f,[(-.014,.260),(.020,.260),(.020,.283),(-.014,.283)],.082,.084,dark,dark)
    p.finish()


def saw(k):
    teeth=bpy.data.objects['chainsaw_teeth_rig']
    # Keep the shader's original tooth dimensions and longitudinal axis.
    # Rolling the whole outer assembly reveals its wide face from a front view.
    pos=k.rig.data.pose_position
    k.rig.data.pose_position='REST'
    bpy.context.view_layer.update()
    teeth.matrix_basis=teeth.matrix_basis @ Matrix.Rotation(radians(-50),4,'Z')
    bpy.context.view_layer.update()
    m=teeth.matrix_world.copy()
    k.rig.data.pose_position=pos
    bpy.context.view_layer.update()
    teeth.data.materials.clear()
    teeth.data.materials.append(k.steel)
    f=(m.translation,*[m.col[i].to_3d().normalized() for i in range(3)])
    p=Assembly(k,'chainsaw_rig','chainsaw')
    outline=[(-.038,-.030),(.042,-.030),(.063,.005),(.063,.499),
             (.056,.529),(.039,.553),(.018,.565),(-.016,.565),
             (-.041,.553),(-.057,.530),(-.063,.503),(-.063,.015)]
    pad(p,f,outline,-.030,.030,k.gunmetal,k.steel)
    plate=[(-.028,.030),(.033,.030),(.048,.056),(.048,.495),
           (.039,.518),(.019,.532),(-.008,.537),(-.030,.525),
           (-.044,.508),(-.048,.489),(-.047,.055)]
    for s in (-1,1):
        pad(p,f,plate,s*.030,s*.033,k.blacksteel,k.steel)
        disk(p,f,0,.472,[(s*.034,.028),(s*.037,.025)],k.blacksteel,k.gunmetal)
        disk(p,f,0,.472,[(s*.038,.014),(s*.040,.013)],k.gunmetal,k.blacksteel)
    p.finish()


def sidearm(k):
    """A single solid prop. Its front cap meets the accepted flash socket."""
    tip=k.rig.data.bones['flash'].head_local
    axis=Vector((.175,-.942,-.287)).normalized()
    f=frame(tip,axis,(0,0,1))
    p=Assembly(k,'pistol_rig','pistol')
    shell(p,f,[(-.483,.046,.068,.3,0,.003),(-.461,.056,.079,.3,0,.005),
               (-.183,.056,.076,.32,0,.004),(-.117,.050,.062,.31,0,0),
               (-.092,.044,.051,.33,0,0)],k.blacksteel)
    shell(p,f,[(-.445,.058,.019,.28,0,.053),(-.426,.060,.024,.32,0,.054),
               (-.162,.057,.020,.30,0,.054),(-.143,.049,.016,.30,0,.047)],k.gunmetal)
    circle=lambda r,t:[pt(f,r*cos(i*2*pi/10),r*sin(i*2*pi/10),t) for i in range(10)]
    p.solid([circle(.042,-.122),circle(.044,-.101),circle(.039,-.089),
             circle(.039,-.008),circle(.035,0)],k.gunmetal,k.blacksteel)
    p.solid([circle(.025,-.001),circle(.024,.0006)],k.blacksteel,k.leather)
    # Graphic grip block sits inside the gloved hand.
    hand=k.rig.data.bones['hand.L'].tail_local
    butt=hand+Vector((-.007,.028,-.080))
    grip_top=pt(f,-.007,-.023,-.405)
    grip=frame(grip_top,butt-grip_top,(.85,.30,.08))
    length=(butt-grip_top).length
    shell(p,grip,[(0,.053,.042,.38,0,0),(.035,.052,.042,.35,0,0),
                  (length-.016,.043,.037,.30,0,0),(length,.042,.035,.32,0,0)],
          k.leather,k.blacksteel)
    p.finish()


def build(k):
    bones=k.rig.data.bones
    for side in ('L','R'):
        arm=bones['upper_arm.'+side]
        lower=bones['forearm.'+side]
        upper_sleeve(k,side,arm.head_local.copy(),arm.tail_local.copy())
        if side=='L':
            cuff_and_glove(k,lower.head_local,lower.tail_local,bones['hand.L'].tail_local)
        else:
            artificial_forearm(k,lower.head_local,lower.tail_local)
    saw(k)
    sidearm(k)
