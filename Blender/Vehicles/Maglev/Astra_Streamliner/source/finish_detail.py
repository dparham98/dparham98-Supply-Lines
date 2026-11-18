"""The fitted armour, optical equipment, cargo access and insignia of the streamliner."""
from mathutils import Vector
import bpy


def clipped_plate(part, center, u, v, width, height, cut, depth, face, rim):
    """An eight-corner plate extruded outward along its surface normal."""
    u,v = Vector(u).normalized(),Vector(v).normalized()
    n = u.cross(v).normalized()
    center = Vector(center)
    w,h = width*.5,height*.5
    cut = min(cut,w*.8,h*.8)
    corners = [(-w+cut,-h),(w-cut,-h),(w,-h+cut),(w,h-cut),(w-cut,h),
               (-w+cut,h),(-w,h-cut),(-w,-h+cut)]
    outer = [center+u*x+v*y for x,y in corners]
    inner = [pt-n*depth for pt in outer]
    faces = [tuple(range(8)),tuple(reversed(range(8,16)))]
    faces.extend((i,i+8,(i+1)%8+8,(i+1)%8) for i in range(8))
    part.geo(outer+inner,faces,[face]+[rim]*9)


def sideplate(part, side, x, y, z, width, height, cut, depth, face, rim):
    clipped_plate(part,(side*x,y,z),(0,side,0),(0,0,1),width,height,cut,depth,face,rim)


def roofplate(part, x,y,z, width,length, cut,depth,face,rim):
    clipped_plate(part,(x,y,z),(1,0,0),(0,1,0),width,length,cut,depth,face,rim)


def joints(k):
    p = k.Part("bulkhead_reveals",k.shells)
    for y,half in [(-2.371,.055),(-.65,.05),(1.094,.095),(4.327,.057)]:
        rings=[]
        for yy in (y-half,y+half):
            ring=[k.skin(yy,v,1) for v in range(7)]+[k.skin(yy,v,-1) for v in reversed(range(7))]
            rings.append([(x*.979,py,z-.042) for x,py,z in ring])
        k.bridge(p,rings,[k.frame]*14)
    p.finish()


def optical_deck(k):
    p=k.Part("visor_and_navigation_lights",k.systems)
    for s in (-1,1):
        # Two shallow side apertures and a transverse sensor brow leave the
        # centre of the nose armoured. The brow and the hull share one rake.
        k.patch(p,s,[(4.44,-3.40,-2.32),(4.65,-3.55,-2.18),(5.0,-3.57,-2.16),
                     (5.66,-3.42,-2.28)],k.frame,.050)
        k.patch(p,s,[(4.63,-3.40,-2.35),(4.82,-3.48,-2.25),(5.0,-3.49,-2.24),
                     (5.46,-3.39,-2.32)],k.glass,.084)
        k.patch(p,s,[(5.70,-2.43,-2.22),(6,-2.46,-2.21),(7,-2.49,-2.22)],k.frame,.065)
        k.patch(p,s,[(5.84,-2.40,-2.30),(6,-2.41,-2.29),(7,-2.44,-2.30)],k.glass,.086)
        # Stainless sill tracing the lower visor edge.
        k.patch(p,s,[(4.39,-3.37,-2.36),(4.45,-3.37,-2.36)],k.steel,.068)
        # Pale three-part transverse headlamp recessed in the shallow prow.
        k.patch(p,s,[(4.28,-4.78,-4.53),(5,-4.80,-4.54),(6,-4.79,-4.52),
                     (7,-4.79,-4.52)],k.frame,.048)
        k.patch(p,s,[(4.52,-4.738,-4.57),(5,-4.744,-4.575),(5.79,-4.73,-4.56)],
                k.white,.069)
        k.patch(p,s,[(6.05,-4.73,-4.56),(7,-4.73,-4.56)],k.white,.069)
        # Amber piloting lamps and a dark isolating shoulder strip.
        k.rect_patch(p,s,3.53,4.20,-3.89,-3.56,k.frame,.044,.05)
        k.rect_patch(p,s,3.70,4.07,-3.85,-3.60,k.amber,.065,.05)
        k.rect_patch(p,s,4.62,4.92,-1.90,-1.51,k.frame,.034)
        k.rect_patch(p,s,4.70,4.84,-1.85,-1.55,k.amber,.053)
    p.finish()
    p=k.Part("nose_service_armour",k.systems)
    for s in (-1,1):
        # Hood sits between the prow lights and the visor.
        k.patch(p,s,[(5.70,-4.49,-2.51),(6,-4.50,-2.48),(7,-4.50,-2.52)],k.shell,.046)
        # Nose service grille below the fang, with a narrow flush sill on either side.
        k.patch(p,s,[(6.12,-4.38,-3.98),(7,-4.38,-4.00)],k.frame,.080)
        for y in (-4.30,-4.20,-4.10):
            k.rect_patch(p,s,6.21,7,y,y+.022,k.gun,.125)
        k.rect_patch(p,s,4.01,4.18,-4.49,-3.87,k.steel,.035,.018)
        k.rect_patch(p,s,2.05,2.22,-4.44,-3.31,k.frame,.034,.17)
    p.finish()


def machine_room(k):
    vent=k.Part("protected_radiator_banks",k.systems)
    for side in (-1,1):
        # A coaming, recessed cavity, four projecting longitudinal blades and a central stay.
        sideplate(vent,side,.879,-.12,3.622,1.91,.430,.092,.053,k.gun,k.frame)
        sideplate(vent,side,.894,-.12,3.625,1.77,.348,.065,.038,k.frame,k.frame)
        for i in range(4):
            sideplate(vent,side,.932,-.12,3.495+i*.083,1.64,.037,.014,.051,k.gun,k.steel)
        for y in (-.94,-.16,.70):
            sideplate(vent,side,.939,y,3.627,.052,.329,.010,.052,k.steel,k.gun)
        # Narrow cooling intake on each side of the loading section.
        k.rect_patch(vent,side,4.09,4.73,1.91,3.78,k.frame,.048,.05)
        for y in (2.02,2.24,2.46,2.68,2.90,3.12,3.34,3.56):
            k.patch(vent,side,[(4.15,y,y+.057),(4.62,y+.075,y+.132)],k.gun,.078)
        # Lower power-module access plate and quarter-turn latches clear the livery.
        k.rect_patch(vent,side,2.10,2.59,-1.40,.61,k.frame,.026,.016)
        k.rect_patch(vent,side,2.15,2.53,-1.32,.53,k.gun,.052,.015)
        for y in (-1.20,.34):
            k.rect_patch(vent,side,2.25,2.44,y,y+.09,k.steel,.078)
        k.rect_patch(vent,side,2.18,2.38,-.43,-.05,k.frame,.078)
    vent.finish()
    p=k.Part("spine_covers_and_exchanger",k.systems)
    # Flush graphite inspection lids and narrow service line on the upper spine.
    roofplate(p,0,-.59,3.968,1.22,.53,.078,.028,k.shell,k.frame)
    roofplate(p,0,.09,3.965,1.23,.73,.082,.025,k.frame,k.frame)
    for x in (-.44,-.22,0,.22,.44):
        roofplate(p,x,.085,3.97,.094,.56,.028,.026,k.gun,k.gun)
    roofplate(p,0,.582,3.969,1.22,.185,.04,.018,k.gun,k.frame)
    # Forward-facing inlet follows the ramp of the machinery spine.
    incline=Vector((0,.80,.60)).normalized()
    surface=Vector((0,-1.505,3.648))
    clipped_plate(p,surface,(1,0,0),incline,1.04,.52,.061,.04,k.frame,k.frame)
    for along in (-.12,0,.12):
        clipped_plate(p,surface+incline*along+Vector((0,-.01,.015)),(1,0,0),incline,
                      .89,.044,.014,.019,k.gun,k.steel)
    roofplate(p,0,2.28,3.606,1.12,1.36,.10,.035,k.frame,k.frame)
    for y in (1.88,2.18,2.48,2.78):
        roofplate(p,0,y,3.626,.99,.226,.041,.035,k.gun,k.frame)
    p.finish()


def cargo_bay(k):
    door=k.Part("cargo_service_doors",k.systems)
    fittings=k.Part("bay_frames_and_latches",k.systems)
    for s in (-1,1):
        # Door hardware is kept within the service envelope. The panels sit flush.
        sideplate(door,s,1.788,2.80,2.165,2.58,.92,.105,.080,k.frame,k.frame)
        sideplate(door,s,1.807,2.80,2.165,2.48,.826,.085,.049,k.shell,k.gun)
        for y in (2.215,3.385):
            sideplate(door,s,1.815,y,2.17,1.10,.67,.073,.035,k.gun,k.frame)
        for y in (1.69,3.91):
            sideplate(fittings,s,1.824,y,2.18,.090,.56,.021,.043,k.steel,k.frame)
        for y in (2.13,3.42):
            sideplate(fittings,s,1.820,y,2.35,.22,.070,.019,.019,k.frame,k.frame)
        # Stamped diagonal stiffeners, separated by the resilient centre seal.
        for y,direction in [(2.20,1),(3.38,-1)]:
            points=[(s*1.817,y-.43*direction,2.45),(s*1.817,y-.32*direction,2.45),
                    (s*1.817,y+.34*direction,1.96),(s*1.817,y+.26*direction,1.96)]
            fittings.face(points,k.shell,(s,0,0))
        sideplate(fittings,s,1.825,2.78,1.893,.42,.048,.012,.012,k.amber,k.frame)
        # Upper and lower steel rub strips are interrupted at the shell breaks.
        for a,b in [(-3.48,-2.51),(-2.24,-.75),(-.57,.92),(1.37,4.17)]:
            k.rect_patch(fittings,s,1.52,1.69,a,b,k.steel,.032)
        # Wheel-free mass under the tapered nose: flush, layered side cheek.
        k.patch(door,s,[(2.02,-4.41,-2.61),(2.13,-4.53,-2.63),(2.44,-4.23,-2.72)],
                k.shell,.023)
        # Keep the rear bulkhead dark and provide a small amber end marker.
        k.rect_patch(fittings,s,3.23,3.71,4.50,4.73,k.frame,.029)
        k.rect_patch(fittings,s,3.36,3.57,4.54,4.69,k.amber,.052)
    door.finish()
    fittings.finish()
    p=k.Part("cargo_indicator_pocket",k.systems)
    roofplate(p,0,3.55,3.515,1.64,.52,.085,.15,k.frame,k.shell)
    for x in (-.70,.70):
        roofplate(p,x,3.55,3.596,.12,.49,.035,.095,k.gun,k.frame)
    p.finish()
    # As the runtime raises this entire cassette, an amber load flag emerges.
    p=k.Part("cargo_car_indicator",k.livery,origin=(0,3.55,3.60))
    k.vault(p,[(3.42,.47,3.305,3.60,.035),(3.46,.59,3.305,3.626,.035),
               (3.64,.59,3.305,3.626,.035),(3.68,.47,3.305,3.60,.035)],
            [k.frame,k.signal,k.gun,k.gun,k.gun,k.signal,k.frame,k.frame],k.signal)
    roofplate(p,0,3.55,3.637,.80,.14,.035,.015,k.signal,k.frame)
    moving=p.finish()
    for vertex in moving.data.vertices:
        vertex.co.z-=.15


def insignia(k):
    # Reproject the accepted Drone's exact faction_fang polygons to the forward deck.
    drone=k.BASE.parents[1]/"Drone"/"Drone.blend"
    with bpy.data.libraries.load(str(drone)) as (_,dst):
        dst.objects=["faction_fang"]
    ref=dst.objects[0]
    mesh=ref.data
    normal=sum((p.normal*p.area for p in mesh.polygons),Vector()).normalized()
    coords=[v.co.copy() for v in mesh.vertices]
    center=sum(coords,Vector())/len(coords)
    tip=min(coords,key=lambda v:v.y)-center
    tip=(tip-normal*tip.dot(normal)).normalized()
    lateral=normal.cross(tip)
    uv=[((v-center).dot(lateral),(v-center).dot(tip)) for v in coords]
    hu=(max(a for a,b in uv)+min(a for a,b in uv))*.5
    hv=(max(b for a,b in uv)+min(b for a,b in uv))*.5
    span=max(b for a,b in uv)-min(b for a,b in uv)
    p=k.Part("faction_fang_badges",k.livery)
    # The large insignia anchors the nose ahead of the spine, as on the profile sheet.
    y0=-3.24
    for poly in mesh.polygons:
        pts=[]
        for i in poly.vertices:
            a,b=uv[i]
            x=(a-hu)*1.09/span
            y=y0-(b-hv)*1.09/span
            z=k.skin(y,7)[2]+.030+(.004 if poly.material_index else 0)
            pts.append((x,y,z))
        p.face(pts,k.ink if poly.material_index==0 else k.frame,(0,0,1))
    p.finish()
    bpy.data.objects.remove(ref,do_unlink=True)
    if not mesh.users:
        bpy.data.meshes.remove(mesh)


def service_marks(k):
    """Low-relief serial stencil, exposed latch heads and selective edge wear."""
    p=k.Part("service_stencils_and_fasteners",k.livery)
    wear=k.Part("edge_wear",k.livery)
    # Stencil contours use deck coordinates. The broken corners keep the 0 open.
    strokes=[
        ((.03,.87),(.12,1),(.44,1),(.49,.87)),
        ((.00,.19),(.00,.78),(.13,.94),(.13,.21)),
        ((.36,.09),(.36,.80),(.49,.91),(.49,.20)),
        ((.02,.12),(.12,.00),(.36,.00),(.47,.12)),
        ((.61,1),(.99,1),(.97,.85),(.61,.85)),
        ((.85,.83),(.98,.83),(.76,.00),(.62,.00)),
    ]
    for s in (-1,1):
        for polygon in strokes:
            pts=[k.skin(-1.18+s*(x-.5)*.61,4.67+v*.73,s,.082) for x,v in polygon]
            p.face(pts,k.ink,(s,0,1))
        # A small block stencil and seam witness mark on each cargo shoulder.
        for j in range(3):
            k.rect_patch(p,s,4.76,4.87,2.03+j*.13,2.10+j*.13,k.ink,.076,.038)
        for y in (1.68,3.91):
            for z in (1.965,2.389):
                sideplate(p,s,1.829,y,z,.040,.044,.012,.005,k.frame,k.frame)
        # Towing checks expose steel around the door clasps and lift points.
        for y,v,length in [(-4.14,3.10,.19),(-3.88,4.08,.21),(-1.66,4.44,.22),
                           (-.52,2.78,.29),(.77,4.96,.12),(1.51,4.21,.17),
                           (2.23,3.31,.21),(3.97,3.94,.13),(4.46,4.05,.14)]:
            pts=[k.skin(y,v,s,.104),k.skin(y+length,v+.018,s,.104),
                 k.skin(y+length*.71,v+.045,s,.104),k.skin(y+.03,v+.037,s,.104)]
            wear.face(pts,k.wear,(s,0,.5))
        # Under-nose intake, backed and split into three pitched teeth.
        k.patch(p,s,[(2.07,-3.69,-2.74),(2.20,-3.59,-2.69),(2.36,-3.45,-2.74)],k.frame,.075)
        for y in (-3.40,-3.18,-2.96):
            k.patch(p,s,[(2.10,y,y+.045),(2.30,y+.08,y+.125)],k.gun,.105)
    wear.finish()
    p.finish()


def build(k):
    joints(k)
    optical_deck(k)
    machine_room(k)
    cargo_bay(k)
    insignia(k)
    service_marks(k)
