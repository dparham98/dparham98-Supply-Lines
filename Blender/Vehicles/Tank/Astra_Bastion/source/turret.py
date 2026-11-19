"""The Bastion's armoured visor, single optic, service block and stepped barrel."""
from forms import Forms, front_section, plan, round_section
from hull import louvres


def turret_shell():
    shell = Forms()
    shell.tier([(-1.43,1.43,-1.69,1.59,.012,.45,.44),
                (-1.65,1.65,-1.86,1.83,.15,.48,.48),
                (-1.74,1.74,-1.91,1.86,.88,.48,.50),
                (-1.60,1.60,-1.79,1.74,1.07,.46,.48)], 'armor')
    return shell


def helmet():
    form = Forms()
    form.loft([plan(*data) for data in [
        (-1.76,1.76,-1.87,1.84,.91,.52,.54),
        (-1.95,1.95,-2.01,2.03,1.015,.58,.58),
        (-1.96,1.96,-2.02,2.025,1.11,.58,.58),
        (-1.81,1.81,-1.89,1.89,1.24,.52,.55)]],
        lambda row,edge: ('shade','edge','armor')[row], 'shade','armor')
    # Faceted lower dome. Its rear cutout leaves room for the armoured cooling box.
    form.tier([(-1.60,1.60,-1.39,1.58,1.20,.46,.48),
               (-1.45,1.45,-1.32,1.40,1.38,.40,.43),
               (-1.11,1.11,-1.08,1.14,1.51,.29,.38)], 'armor')
    return form


def striped_hatch():
    form = Forms()
    rings = []
    stripe = .25
    for width, rear, front, z, cx, cf in [(1.13,-1.11,1.17,1.472,.30,.38),
                                        (1.03,-.95,1.06,1.61,.29,.37),
                                        (.82,-.73,.75,1.88,.22,.29),
                                        (.73,-.64,.65,1.93,.19,.23)]:
        rings.append([(-width+cx,rear,z),(-stripe,rear,z),(stripe,rear,z),(width-cx,rear,z),
                      (width,rear+cf,z),(width,front-cf,z),(width-cx,front,z),(stripe,front,z),
                      (-stripe,front,z),(-width+cx,front,z),(-width,front-cf,z),(-width,rear+cf,z)])
    end = form.loft(rings,lambda row,edge: 'team' if edge==7 else 'armor','shade')
    for polygon, mat in (([0,1,8,9,10,11],'armor'),([1,2,7,8],'team'),([2,3,4,5,6,7],'armor')):
        form.face([end+i for i in polygon],mat)
    return form


def ears():
    form = Forms()
    for side in (-1,1):
        def outline(low,high,rear,front,z):
            x0,x1 = sorted((side*low,side*high))
            return plan(x0,x1,rear,front,z,.045,.105)
        form.loft([outline(1.18,1.73,-.39,.71,1.193),
                   outline(1.26,1.69,-.34,.68,1.28),
                   outline(1.32,1.61,-.26,.65,1.41),
                   outline(1.33,1.60,-.245,.64,1.428)],
                  lambda row,edge: 'team' if row==2 else 'armor','armor','team')
    return form


def optical_case():
    form = Forms()
    x,z = 1.00,.535
    sequence=[(1.60,.418,.405,.079),(1.94,.432,.397,.070),
              (2.005,.385,.347,.050),(2.005,.291,.275,.019),
              (1.925,.284,.268,.020)]
    form.loft([front_section(x,f,z,w,h,cut,cut*.82) for f,w,h,cut in sequence],
              lambda row,edge: ('armor','edge','armor','shade')[row], 'shade','bore')
    form.loft([round_section('f',f,(x,z),r,20) for f,r in [(1.926,.227),(1.965,.234),(1.986,.213)]],
              'shade','shade','rubber')
    return form


def optic():
    form = Forms()
    form.loft([round_section('f',f,(1,.535),r,24) for f,r in
               [(1.969,.185),(1.999,.189),(2.018,.168)]],
              lambda row,edge: 'optic' if row else 'shade','shade','optic')
    return form


def service_case():
    form = Forms()
    def casing(xa,xb,rear,front,low,high,cut,material):
        rings = []
        for x,inset in ((xa,.035),(xa+.043,0),(xb-.045,0),(xb,.036)):
            a,b=rear+inset,front-inset
            c,d=low+inset,high-inset
            outline=[(a+cut,c),(b-cut,c),(b,c+cut),(b,d-cut),
                     (b-cut,d),(a+cut,d),(a,d-cut),(a,c+cut)]
            rings.append([(x,y,z) for y,z in outline])
        form.loft(rings,material,material,material)
    casing(1.57,1.775,-.68,.84,.13,.94,.09,'shade')
    casing(1.69,1.91,-.54,.73,.20,.92,.09,'steel')
    casing(1.75,1.98,.51,.92,.24,.54,.042,'steel')
    form.loft([round_section('x',x,(-.09,.546),r,16) for x,r in
               [(1.88,.214),(1.939,.236),(1.994,.211),(2.003,.187)]],
              lambda row,edge: 'steel' if row==1 else 'gun','shade','gun')
    return form


def barrel(mount, group, palette):
    form = Forms()
    rings = [front_section(0,f,0,w,h,cx,cz) for f,w,h,cx,cz in [
        (-.27,.399,.33,.105,.074),(.13,.485,.381,.115,.082),
        (.94,.475,.363,.112,.083),(1.10,.416,.318,.090,.071),
        (1.135,.377,.29,.082,.063),(1.64,.367,.284,.077,.061),
        (1.71,.298,.247,.068,.058),(4.90,.266,.220,.058,.049)]]
    form.loft(rings,lambda row,edge: 'edge' if row in (2,5) else 'gun','shade','gun')
    tube = form.finish('Tank_Barrel',mount,group,palette)
    muzzle = Forms()
    stations = [(-.46,.287,.243,.055),(-.375,.349,.304,.055),(.377,.349,.304,.055),
                (.45,.326,.286,.045),(.45,.227,.182,.026),(.38,.216,.173,.027),
                (.05,.199,.154,.025)]
    muzzle.loft([front_section(0,f,0,w,h,k,k*.78) for f,w,h,k in stations],
                lambda row,edge: ('gun','gun','edge','gun','shade','bore')[row],
                'gun','bore')
    muzzle.finish('Barrel_Muzzle_Brake',tube,group,palette,position=(0,5.20,0))


def build(hull, collections, palette):
    group = collections['Turret']
    turret = turret_shell().finish('Tank_Turret',hull,group,palette,(0,-.5,2.16))
    helmet().finish('Armored_visor',turret,group,palette)
    striped_hatch().finish('Turret_Hatch',turret,group,palette)
    ears().finish('Turret_shoulder_plates',turret,group,palette)
    cooling = Forms()
    cooling.tier([(-1.14,1.14,-2.10,-1.03,.88,.13,.10),
                  (-1.14,1.14,-2.12,-1.03,1.13,.13,.10),
                  (-1.07,1.07,-2.06,-1.03,1.29,.12,.09)],'armor')
    louvres(cooling,0,-2.065,-1.12,1.369,1.055,3)
    cooling.finish('Turret_rear_vents',turret,group,palette)
    optical_case().finish('Optical_recess',turret,collections['Optics and service'],palette)
    optic().finish('Neon_Sensor_Lens',turret,collections['Optics and service'],palette)
    service_case().finish('Service_housing',turret,collections['Optics and service'],palette)
    bearing = Forms()
    bearing.loft([front_section(0,f,0,w,h,.14,.107) for f,w,h in [
        (-.44,.635,.43),(-.19,.637,.431),(.27,.590,.407),(.385,.531,.380)]],
        lambda row,edge: 'edge' if row==2 else 'armor','armor','shade')
    mount = bearing.finish('Barrel_Mount',turret,collections['Cannon'],palette,(0,1.95,.46))
    barrel(mount,collections['Cannon'],palette)
