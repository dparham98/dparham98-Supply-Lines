"""The oak arcades, iron wall cassettes, great-hall porch and receiving dock."""

from math import cos, pi, sin

from mathutils import Matrix, Vector


X = Vector((1, 0, 0))
Y = Vector((0, 1, 0))
Z = Vector((0, 0, 1))
OAK = "Heart_Oak"
HONEY = "Honey_Oak"
CEDAR = "Smoked_Oak"
IRON = "Recessed_Steel"
IVORY = "Ivory_Armor"
BRASS = "Heraldic_Brass"
SILVER = "Satin_Silver"
GLASS = "Clerestory_Glass"


def beam(part, a, b, width, depth, material, across=Y):
    """An oriented rectangular timber or rolled section with its grain along a to b."""
    a, b = Vector(a), Vector(b)
    axis = (b-a).normalized()
    along = Vector(across) - axis * axis.dot(across)
    if along.length < 0.01:
        along = X - axis * axis.x
    along.normalize()
    width_axis = along.cross(axis).normalized()
    rot = Matrix((width_axis, along, axis)).transposed().to_4x4()
    part.add_box((a+b)/2, (width, depth, (a-b).length), material, rot=rot,
                 bevel=min(width, depth)*0.055)


def plate(part, origin, normal, points, depth, thickness, mat):
    right = Z.cross(normal)
    part.add_extruded_poly_frame(points, origin, right, Z, normal, depth, depth+thickness, mat)


def shield_plate(part, origin, normal, width, lo, hi, depth, mat):
    x, height = width/2, hi-lo
    polygon = [(-x+.11,lo), (x-.11,lo), (x,lo+.15*height),
               (x,hi-.12), (x-.13,hi), (-x+.13,hi), (-x,hi-.12), (-x,lo+.15*height)]
    plate(part,origin,normal,polygon,depth,.075,mat)


def bolt(part, point, normal, radius=.043):
    part.add_cyl(point,point+normal*.037,radius,radius*.89,8,SILVER)


def wall_rails(part, normal, start, end):
    """Timber studwork and individually seated iron plates with an inset glazed band."""
    right = Z.cross(normal)
    origin = normal*3.33
    def pos(u, d, z): return origin+right*u+normal*d+Z*z
    def box(a,b,di,do,lo,hi,mat):
        part.add_extruded_poly_frame([(a,lo),(b,lo),(b,hi),(a,hi)],origin,right,Z,normal,di,do,mat)
    box(start,end,-.17,-.03,.32,4.47,CEDAR)
    # Each panel is a fitted infill in a structural timber frame.
    count=max(1, round((end-start)/1.28))
    step=(end-start)/count
    for i in range(count):
        a=start+i*step
        b=a+step
        mid=(a+b)/2
        for j in range(4):
            left=a+.08+j*(step-.16)/4
            box(left,left+(step-.16)/4-.012,-.02,.011,.55,2.58, OAK if j%3 else HONEY)
        shield_plate(part, pos(mid,.055,0),normal,step-.22,.47,1.25,.015,IVORY)
        for x in (mid-step*.28,mid+step*.28):
            bolt(part,pos(x,.148,1.10),normal)
        box(a+.1,b-.1,-.015,.014,2.79,4.17,GLASS)
        height = 3.91
        for u in (mid-step*.26, mid, mid+step*.26):
            beam(part,pos(u,.039,2.79),pos(u,.039,height+.24),.036,.055,IRON,normal)
        box(a+.08,b-.08,.025,.064,3.18,3.23,SILVER)
        # Angled knee braces meet an iron saddle at the head of every post.
        for side in (-1,1):
            u=mid+side*(step*.48-.06)
            beam(part,pos(u,.12,2.20),pos(mid+side*step*.19,.12,2.72),.13,.19,HONEY,normal)
    for i in range(count+1):
        u=start+i*step
        box(u-.085,u+.085,.055,.26,.40,4.46,OAK)
        box(u-.12,u+.12,.035,.285,.33,.74,IRON)
        box(u-.12,u+.12,.04,.28,2.54,2.75,IRON)
        bolt(part,pos(u,.286,.63),normal)
    for lo,hi,d,mat in ((.30,.46,.21,IRON),(1.34,1.44,.08,IRON),(2.60,2.79,.25,HONEY),
                          (4.15,4.37,.27,OAK),(4.36,4.47,.34,IRON)):
        box(start,end,.0,d,lo,hi,mat)


def hall_walls(part):
    wall_rails(part, X,-3.41,3.41)
    wall_rails(part, Y,-3.42,3.42)
    for lo,hi in ((-3.45,-1.39),(1.39,3.45)):
        wall_rails(part,-Y,lo,hi)
    # The loading side opens below its clerestory; the recess has a stained oak lining.
    for lo,hi in ((-3.49,-2.04),(2.04,3.49)):
        wall_rails(part,-X,lo,hi)
    part.add_span(-3.44,-3.16,-2.1,2.1,3.22,4.49,IRON,.022)
    for i in range(4):
        y=-2.08+i*1.04
        for j in range(4):
            py=y+j*.256
            part.add_span(-3.46,-3.44,py,py+.246,3.31,4.19,HONEY if j%3 else OAK)
        # Continuous A-braced timber band over the receiving porch.
        for dy in (-.46,.46):
            beam(part,(-3.48,y+.52+dy,3.38),(-3.48,y+.52,4.18),.085,.074,IRON,X)
        part.add_span(-3.55,-3.44,y-.044,y+.044,3.27,4.34,OAK)
    part.add_span(-3.58,-3.42,-2.22,2.22,3.24,3.41,OAK,.01)
    part.add_span(-3.58,-3.26,-2.25,2.25,4.17,4.42,OAK,.014)
    for i in range(15):
        y=-2.36+i*.32
        part.add_span(-2.51,-2.39,y,y+.30,.28,3.31,CEDAR if i%4 else OAK)
    part.add_span(-3.30,-2.42,-2.20,-2.08,.24,3.28,OAK)
    part.add_span(-3.30,-2.42,2.07,2.19,.24,3.28,OAK)
    # Right flank carries exterior iron tension members rising into the wooden eaves.
    for y in (-2.08,0,2.08):
        beam(part,(3.61,y,.63),(3.95,y,1.03),.27,.35,IRON)
        beam(part,(3.95,y,1.03),(3.61,y,3.94),.23,.32,OAK)
        beam(part,(3.92,y,1.13),(3.61,y,3.85),.07,.36,IRON)
    # Rear maintenance hatch and louvres for the gate's electric hoist.
    part.add_span(-.86,.86,3.63,3.77,.44,2.63,IRON,.065)
    for i in range(8):
        z=.58+i*.24
        part.add_box((0,3.80,z),(1.46,.11,.16), IVORY if i%4==0 else SILVER,
                     rot=Matrix.Rotation(.17,4,"X"),bevel=.022)
    part.add_span(-.73,.73,3.74,3.80,2.39,2.45,"Visor_Amber")


def porch(part, add_heraldry):
    """A deep pointed timber portal enclosing the working steel portcullis."""
    outward=-Y
    # Two coupled glulam ribs, faceted from continuous laminated arch outlines.
    for y in (-4.44,-3.46):
        for sign in (-1,1):
            xs=(2.12,2.09,2.025,1.90,1.65,1.31,.90,.45,.0)
            zs=(.29,1.60,2.54,3.14,3.70,4.16,4.49,4.76,5.02)
            for layer,(offset,mat) in enumerate(((.00,OAK),(.105,HONEY),(.19,OAK))):
                coords=[(sign*x*(1+offset/2.3),z+offset*(1-x/2.2)) for x,z in zip(xs,zs)]
                width=.145 if layer==1 else .180
                # A contiguous curved polygon for each lamination, no gaps at scarf joints.
                outer=[(x*(1+width*.40), z+width*(1-abs(x)/2.4)) for x,z in coords]
                poly=coords+list(reversed(outer))
                part.add_extruded_poly_frame(poly,Vector((0,y,0)),X,Z,outward,-.075,.155,mat)
            part.add_box((sign*2.20,y+.01,.53),(.43,.51,.57),IRON,bevel=.052)
            part.add_box((sign*2.20,y-.12,.71),(.42,.35,.12),SILVER,bevel=.023)
            for z in (.43,.64):
                bolt(part,Vector((sign*2.20,y-.26,z)),outward,.056)
    # Slim storm doors sit inside the arch, the travelling grille has clear space behind it.
    for sign in (-1,1):
        # The smaller rib bears on iron gate guides, inside the glulam arch above.
        edges=[(1.40,.27),(1.40,1.52),(1.36,2.13),(1.20,2.57),(.90,2.95),(.50,3.28),(0,3.62)]
        inner=[(sign*x,z) for x,z in edges]
        outer=[(sign*(x+.19),z+.16*(1-x/1.50)) for x,z in edges]
        part.add_extruded_poly_frame(inner+list(reversed(outer)),Vector((0,-4.41,0)),X,Z,outward,-.07,.14,HONEY)
        for j in range(4):
            x=sign*(1.21+j*.23)
            part.add_box((x,-4.08,1.62),(.214,.28,2.67),OAK if j in (0,2) else HONEY,
                         bevel=.015)
        part.add_box((sign*1.20,-4.18,1.65),(.115,.32,2.82),IRON,bevel=.017)
        part.add_box((sign*1.23,-4.37,1.50),(.07,.05,.65),"Visor_Amber",bevel=.012)
        # Sill, hoist bearings and sheltered personnel entry around the gate.
        beam(part,(sign*1.44,-4.19,2.62),(sign*1.20,-4.19,3.35),.22,.21,IRON)
        part.add_cyl((sign*1.47,-4.31,2.61),(sign*1.47,-4.48,2.61),.12,.09,12,SILVER)
    # Enclosed upper gate mechanism. The clerestory windows follow the rising gable,
    # with a central sill and mullions that keep the glass out of the sliding gate.
    facade=[(-2.40,3.27),(-2.10,3.86),(0,6.21),(2.10,3.86),(2.40,3.27)]
    part.add_extruded_poly_frame(facade,Vector((0,-4.17,0)),X,Z,outward,-.44,.09,IRON)
    # Infill follows the intrados of the smaller arch, so the grille opens
    # onto a clear vestibule. Narrow board joints remain visible between ribs.
    for i in range(18):
        x=-2.13+i*.24
        a,b=x,x+.228
        def opening(u):
            u=min(1.4,abs(u))
            return 2.0+1.59*(1-(u/1.4)**1.6)**.57
        def top(u): return 6.11-1.045*abs(u)
        if min(top(a)-opening(a),top(b)-opening(b)) < .02:
            continue
        panel=[(a,opening(a)),(b,opening(b)),(b,top(b)),(a,top(a))]
        part.add_extruded_poly_frame(panel,Vector((0,-4.28,0)),X,Z,outward,
                                    -.04,.028,OAK if i%3 else CEDAR)
    for sign in (-1,1):
        for i in range(5):
            inner=.12+i*.35
            outer=inner+.306
            ceiling=lambda x:6.06-.90*x
            floor=lambda x:4.52-.40*x
            poly=[(sign*inner,floor(inner)),(sign*outer,floor(outer)),
                  (sign*outer,ceiling(outer)),(sign*inner,ceiling(inner))]
            part.add_extruded_poly_frame(poly,Vector((0,-4.31,0)),X,Z,outward,-.005,.025,GLASS)
            # A fine amber strip within the window reflects the lit interior.
            strip=[(sign*(inner+.017),floor(inner)+.025),(sign*(inner+.049),floor(inner)+.025),
                   (sign*(inner+.049),ceiling(inner)-.065),(sign*(inner+.017),ceiling(inner)-.04)]
            part.add_extruded_poly_frame(strip,Vector((0,-4.34,0)),X,Z,outward,0,.006,"Amber_Glass")
        # Leaded transom between the inner and outer arch. Each pointed pane
        # steps down from the escutcheon towards the jamb with a dark glazing bead.
        for i in range(4):
            mid=.37+i*.326
            bottom=3.77-.70*mid
            crown=4.92-.77*mid
            for half,offset,d,mat in ((.153,0,.0,IRON),(.120,.050,.026,"Amber_Glass")):
                profile=[(-half,bottom+offset),(half,bottom+offset),(half,crown-.21-offset),
                         (0,crown-offset),(-half,crown-.21-offset)]
                points=[(sign*(mid+xx),zz) for xx,zz in profile]
                part.add_extruded_poly_frame(points,Vector((0,-4.394,0)),X,Z,outward,d,d+.021,mat)
            beam(part,(sign*mid,-4.445,bottom+.08),(sign*mid,-4.445,crown-.12),
                 .022,.025,SILVER,Y)
        beam(part,(sign*2.39,-4.42,3.46),(0,-4.42,6.31),.22,.24,HONEY)
        beam(part,(sign*2.49,-4.38,3.40),(0,-4.38,6.42),.063,.32,IRON)
        # Standing seam roof of the projecting hall gable intersects the main roof.
        a,b=Vector((sign*2.55,-4.59,3.48)),Vector((0,-4.59,6.45))
        # Clip the dormer pan at the hip and fold a continuous valley flashing
        # over the joint. Each standing seam stops short of this watercourse.
        hip_eave_y=-3.62
        hip_rise=1.825/1.90
        slope=(b.z-a.z)/abs(a.x)
        joint_x=(b.z+.075-5.055)/slope
        upper=Vector((0,hip_eave_y+(b.z+.075-5.055)/hip_rise,b.z))
        valley=Vector((sign*joint_x,hip_eave_y,5.055-.075))
        lower=Vector((a.x,hip_eave_y,a.z))
        pan=[a,b,upper,valley,lower]
        part.add_frustum_shell(pan,[p+Z*.075 for p in pan],"Royal_Enamel")
        beam(part,valley+Z*.096,upper+Z*.096,.105,.055,IRON,X)
        for i in range(6):
            y=a.y+i*.46
            x=abs(a.x) if y < hip_eave_y else joint_x-(y-hip_eave_y)*hip_rise/slope-.08
            if x<.12: continue
            start=Vector((sign*x,y,b.z-slope*x+.082))
            beam(part,start,Vector((0,y,b.z+.082)),.046,.055,SILVER if i==0 else "Midnight_Enamel")
        beam(part,a+Z*.06,lower+Z*.06,.12,.15,IRON, X)
    beam(part,(0,-4.61,6.535),(0,upper.y+.03,6.535),.115,.064,"Midnight_Enamel",X)
    # Main shield is genuinely raised over the glazing with an enamel field and gilded trim.
    centre=Vector((0,-4.60,4.40))
    def badge(scale,d,mat):
        shape=[(-.58,.59),(.58,.59),(.56,-.15),(.38,-.45),(0,-.73),(-.38,-.45),(-.56,-.15)]
        plate(part,centre,outward,[(x*scale,z*scale) for x,z in shape],d,.035,mat)
    badge(1.06,.00,IRON)
    badge(1,.044,BRASS)
    badge(.91,.079,"team_color")
    add_heraldry(part,centre+outward*.115+Z*.02,outward,Z,2.95, BRASS,SILVER)
    # Steel threshold rails carry the grille between the massive oak jambs.
    for sign in (-1,1):
        part.add_box((sign*1.36,-3.18,.50),(.34,2.12,.45),IRON,bevel=.035)
        part.add_box((sign*1.36,-3.18,1.69),(.25,2.00,2.30),CEDAR,bevel=.027)
    part.add_box((0,-2.54,3.06),(2.94,.32,.34),OAK,bevel=.028)


def dock(part):
    """Raised receiving apron with an open centre, crates and a small stock of dressed iron."""
    for j in range(17):
        y=-2.34+j*.285
        part.add_span(-4.76,-2.54,y,y+.272,.227,.30,OAK if j%4 else HONEY,.008)
    for y in (-2.09,2.09):
        part.add_box((-4.62,y,1.43),(.20,.23,2.30),OAK,bevel=.015)
        part.add_box((-4.62,y,.53),(.27,.30,.45),IRON,bevel=.028)
        part.add_box((-4.62,y,2.40),(.24,.26,.22),IRON,bevel=.018)
    for y in (-1.82,-.70,.70,1.82):
        part.add_span(-3.82,-2.75,y-.055,y+.055,.31,.40,CEDAR,.008)
    # Metal bars rest in a low slotted cradle at the far end, clear of the delivery aisle.
    for z in range(2):
        for j in range(4-z):
            y=.81+j*.17+z*.085
            part.add_box((-3.42,y,.43+z*.14),(1.20,.14,.13),SILVER,bevel=.025)
    for x in (-3.94,-3.02):
        part.add_box((x,1.02,.46),(.082,.90,.30),IRON,bevel=.015)
    # The hand reader and warm task strip belong to the receiving counter.
    part.add_box((-3.79,-.18,1.04),(.30,.43,.16),IRON,rot=Matrix.Rotation(-.22,4,"Y"),bevel=.023)
    part.add_box((-3.80,-.18,1.12),(.23,.30,.025),GLASS,rot=Matrix.Rotation(-.22,4,"Y"))
    part.add_box((-3.92,-.22,1.09),(.022,.16,.023),"Visor_Amber")
    part.add_box((-3.74,-.18,.65),(.105,.12,.77),IRON,bevel=.012)
    # Small open harvest baskets at the receiving counter, on the opposite
    # side of the aisle from the iron cradle. Individual grape clusters show the scale.
    for n,(x,y) in enumerate(((-4.43,.15),(-4.17,.40))):
        low, high=.30,.67
        part.add_cyl((x,y,low),(x,y,high-.055),.126,.215,14,OAK)
        for j in range(5):
            t=(j+1)/6
            radius=.134+t*.080
            z=low+(high-low)*t
            part.add_cyl((x,y,z),(x,y,z+.023),radius+.009,radius+.011,14,HONEY)
        for i in range(9):
            angle=i*2*pi/9+n
            part.add_sphere((x+.145*cos(angle),y+.145*sin(angle),high-.010+(i%3)*.027),
                            .070,"Harvest_Grapes",scale=(1,.86,.92),sub=1)
        part.add_sphere((x,y,high+.018),.087,"Harvest_Grapes",sub=1)
