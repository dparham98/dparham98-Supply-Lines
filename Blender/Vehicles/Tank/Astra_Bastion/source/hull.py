"""Bastion lower casting, overlapping track aprons and replaceable shoulder panels."""
from forms import Forms, front_section, plan, round_section


def louvres(form, x, rear, front, z, width, count):
    """Raised frame and individual leaning blades over the dark grille opening."""
    outline = [(0,z-.102),(.005,z+.036),(.045,z+.065),
               (.122,z+.065),(.148,z+.032),(.148,z-.055)]
    rings = [plan(x-width+i,x+width-i,rear+i,front-i,h,.085,.065) for i,h in outline]
    form.loft(rings,lambda row,edge: ('armor','edge','armor','shade','bore')[row], 'armor','bore')
    span = front - rear - .296
    pitch = span/count
    for i in range(count):
        f = rear + .148 + (i+.5)*pitch
        section = [(f-.22*pitch,z-.051),(f+.21*pitch,z-.051),
                   (f+.21*pitch,z+.069),(f+.03*pitch,z+.078),(f-.22*pitch,z+.044)]
        form.loft([[(xx,y,h) for y,h in section] for xx in (x-width+.15,x+width-.15)],
                  'edge', 'armor', 'armor')


def lower_casting():
    body = Forms()
    body.tier([(-1.32,1.32,-3.69,3.79,.53,.20,.26),
               (-1.59,1.59,-4.03,4.16,.91,.22,.32),
               (-1.60,1.60,-4.10,4.24,1.32,.22,.25),
               (-1.60,1.60,-3.91,3.96,1.44,.17,.34),
               (-1.60,1.60,-3.40,2.31,1.99,.23,.42)], 'armor')
    # The rear deck drops away to expose the grille and terminates in a recessed sill.
    body.tier([(-1.53,1.53,-4.15,-2.64,1.04,.18,.11),
               (-1.53,1.53,-4.12,-2.64,1.37,.17,.10),
               (-1.44,1.44,-3.83,-2.70,1.50,.14,.10)], 'skirt')
    return body


def apron(form, sign, rear, front, front_panel, rear_panel):
    """Each apron sits behind its upper plate, leaving a stepped reveal at the joint."""
    a = rear + .03
    b = front - .03
    def row(f, bottom, top):
        pairs = [(2.506,bottom+.10),(2.53,bottom),(2.67,bottom+.08),
                 (2.62,top-.07),(2.55,top),(2.506,top)]
        return [(sign*x,f,z) for x,z in pairs]
    courses = [row(a,.96 if rear_panel else .82,1.48 if rear_panel else 1.58),
               row(a+.24,.84,1.57),row(b-.25,.82,1.31 if front_panel else 1.55),
               row(b,.95 if front_panel else .86,1.25 if front_panel else 1.47)]
    form.loft(courses, 'skirt', 'skirt', 'shade')


def shoulder(sign, index):
    form = Forms()
    sections = [
        [(-4.07,1.12,1.73,2.73),(-3.72,1.02,1.91,2.74),
         (-3.46,1.00,2.08,2.76),(-1.91,1.00,2.10,2.79),(-1.53,1.01,2.08,2.78)],
        [(-1.52,1.08,2.04,2.73),(-1.25,1.01,2.10,2.77),
         (.89,1.00,2.10,2.79),(1.14,1.06,2.07,2.78)],
        [(1.13,1.08,2.06,2.74),(1.29,.99,2.10,2.79),
         (2.85,1.0,2.10,2.79),(3.13,1.02,2.05,2.77),
         (3.82,1.20,1.77,2.74),(4.02,1.20,1.72,2.72)],
    ][index]
    lower = Forms()
    apron(lower, sign, sections[0][0], sections[-1][0], index == 2, index == 0)
    rings = []
    for f, low, top, outer in sections:
        low += min(.245, (top-low)*.30)
        height = top - low
        # Turn the sheet back up behind the outer wall to leave the entire shoe loop open.
        soffit = min(1.66,top-.107)
        # A seam in the upper bevel lets the end caps close the roof and the
        # hanging flange separately, keeping triangulation out of the tread well.
        bevel_outer = outer-.205
        bevel_inner = outer-.42
        split = (bevel_outer-2.49)/(bevel_outer-bevel_inner)
        seam_height = (top-.19*height)*(1-split)+(top-.033)*split
        contour = [(1.42,soffit),(2.49,soffit),(2.514,low),
                   (outer,low+.20*height),(outer-.018,low+.33*height),
                   (bevel_outer,top-.19*height),(2.49,seam_height),(bevel_inner,top-.033),
                   (1.52,top),(1.42,top-.11*height)]
        rings.append([(sign*x,f,z) for x,z in contour])
    def finish(row, edge):
        painted = (index == 0 and row in (1,2)) or (index == 2 and row in (1,2))
        if painted and edge in (5,6,7):
            return 'team'
        if edge in (0,1,2):
            return 'shade'
        if edge == 3:
            return 'edge'
        return 'armor'
    end = form.loft(rings, finish)
    for offset, mat in ((0,'skirt'),(end,'armor')):
        for polygon in ((0,1,6,7,8,9),(1,2,3,4,5,6)):
            form.face([offset+i for i in polygon],mat)
    return form, lower


def headlamp(x):
    form = Forms()
    centre = 1.755
    sections = [(3.73,1.86,.33,.214),(4.16,1.77,.33,.215),(4.23,centre,.306,.195),
                (4.23,centre,.227,.105),(4.197,centre,.217,.093)]
    rings = [front_section(x,f,z,w,h,.037 if i<3 else .012,.016)
             for i,(f,z,w,h) in enumerate(sections)]
    finish = ['armor','edge','gun','shade']
    form.loft(rings, lambda row, edge: finish[row], 'armor', 'rubber')
    # The projecting lamp is cradled where the glacis meets the track cover.
    saddle = [(3.82,1.64,1.80,.39),(4.015,1.61,1.74,.378),(4.18,1.55,1.64,.311)]
    form.loft([front_section(x,f,(bottom+top)/2,w,(top-bottom)/2,.045,.021)
               for f,bottom,top,w in saddle], 'skirt','skirt','gun')
    glass = Forms()
    glass.loft([front_section(x,f,centre,w,h,.012,.012) for f,w,h in
                [(4.199,.210,.086),(4.206,.206,.082)]], 'lamp', 'shade', 'lamp')
    return form, glass


def build(root, collections, palette):
    group = collections['Hull']
    hull = lower_casting().finish('Tank_Hull', root, group, palette)
    for sign, side in ((1,'L'),(-1,'R')):
        for index, station in enumerate(('Rear','Middle','Front')):
            plate, lower = shoulder(sign,index)
            plate.finish('Skirt_'+side+'_'+station,hull,collections['Skirts'],palette)
            lower.finish('Apron_'+side+'_'+station,hull,collections['Skirts'],palette)
        housing, glass = headlamp(sign*1.89)
        housing.finish('Headlamp_housing_'+side,hull,group,palette)
        glass.finish('Neon_Headlamp_'+side,hull,group,palette)
    # The road wheels revolve around these stationary, concentric axle covers.
    for sign,side in ((1,'L'),(-1,'R')):
        hubs = Forms()
        for station in (-2.75,-1.65,-.55,.55,1.65,2.75):
            rings = [round_section('x',sign*x,(station,.60),r,16)
                     for x,r in [(2.29,.285),(2.314,.265),(2.325,.245),
                                  (2.325,.160),(2.311,.151)]]
            hubs.loft(rings,lambda row,edge: ('shade','gun','skirt','shade')[row],'shade','rubber')
        hubs.finish('Axle_caps_'+side,hull,group,palette)
    ring = Forms()
    ring.loft([round_section('z',z,(0,-.5),radius,20) for z,radius in
               [(1.96,1.37),(2.00,1.54),(2.11,1.52),(2.17,1.40)]],
              'rubber','rubber','shade')
    ring.finish('Turret_Ring',hull,group,palette)
    deck = Forms()
    # Large vent on the rear slope. Its pedestal follows the fall of the cast deck.
    deck.tier([(-1.12,1.12,-4.04,-2.67,1.38,.12,.09),
               (-1.12,1.12,-3.89,-2.67,1.70,.12,.09),
               (-1.08,1.08,-3.75,-2.69,1.91,.11,.08)], 'armor')
    louvres(deck,0,-3.75,-2.68,1.991,1.10,4)
    deck.finish('Rear_deck_cooling',hull,group,palette)
    hatch = Forms()
    # A flush hatch immediately ahead of the turret follows the inclined glacis.
    footprint = plan(-.60,.60,1.88,2.84,0,.12,.14)
    layers=[]
    for offset,shrink in ((.008,1),(.046,.98)):
        layer=[]
        for x,y,_ in footprint:
            yy=2.35+(y-2.35)*shrink
            layer.append((x*shrink,yy,1.99-max(0,yy-2.31)*.335+offset))
        layers.append(layer)
    hatch.loft(layers,'shade','armor','armor')
    hatch.finish('Hull_Driver_Hatch',hull,group,palette)
    return hull
