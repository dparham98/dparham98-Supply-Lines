"""The two turnout castings. A single throat feeds the straight and curved exits."""
from math import acos, asin, cos, pi, sin

RADIUS = 20.0
THROAT_END = 16.0


def arc_sample(radius, first, last, count):
    return [(RADIUS - radius*cos(first+(last-first)*i/count),
             -radius*sin(first+(last-first)*i/count)) for i in range(count+1)]


def throat_course(width, start, end):
    """Boundary of a cross-cut slab in the common, unsplit part of a left turnout."""
    inner = RADIUS - width
    curve = arc_sample(inner,asin(end/inner),asin(start/inner),5)
    return [(-width,-start),(-width,-end),*curve]


def branch_course(width,start,stop):
    """Trace the union boundary. The cusp is the true circle/straight intersection."""
    outer,inner=RADIUS+width,RADIUS-width
    split=acos(inner/outer)
    end=stop/RADIUS
    return [(-width,-start),(-width,-stop),(width,-stop),
            *arc_sample(outer,split,end,5),
            *arc_sample(inner,end,asin(start/inner),13)]


def casting(b,sign,boundary,levels,sides,top):
    rings=[]
    for width,z in levels:
        ring=[(sign*x,y,z) for x,y in boundary(width)]
        if sign<0: ring.reverse()
        rings.append(ring)
    n=len(rings[0])
    faces=[tuple(reversed(range(n))),tuple(range((len(rings)-1)*n,len(rings)*n))]
    mats=['edge',top]
    for j in range(len(rings)-1):
        for i in range(n):
            t=(i+1)%n
            faces.append((j*n+i,j*n+t,(j+1)*n+t,(j+1)*n+i))
            mats.append(sides[j])
    b.add([v for ring in rings for v in ring],faces,mats)


def turnout_deck(k,b,sign,stem,branch):
    casting(b,sign,lambda w:branch_course(w,0,THROAT_END),
            [(2.12,.01),(2.20,.08),(2.20,.17),(2.12,.215)],['edge']*3,'edge')
    slab=[(2.20,.125),(2.32,.20),(2.32,.262),(2.22,.325)]
    mats=['edge','bed','bed']
    for a,z in [(0,4),(4,8)]:
        casting(b,sign,lambda w:throat_course(w,a+.027,z-.027),slab,mats,'bed')
    casting(b,sign,lambda w:branch_course(w,8.027,THROAT_END-.027),slab,mats,'bed')
    for path in (stem,branch): k.deck(b,path,THROAT_END,path.length)


def tongue(k,obj,path,end):
    """The moving power strip disappears below the slab in the unselected lane."""
    blade=k.Builder()
    blade.sweep(path,1.51,end,[(-.38,.461),(.38,.461),(.418,.485),
                               (.359,.523),(-.359,.523),(-.418,.485)],
                ['iron','iron','pad','pad','pad','iron'],cap='iron')
    # Narrow raised pickup faces follow the switch route even from a steep camera.
    count=6
    pitch=(end-1.51)/count
    for i in range(count):
        mid=1.51+(i+.5)*pitch
        for side in (-1,1):
            blade.block(path,mid-.39*pitch,mid+.39*pitch,
                        side*.191,side*.292,.521,.539,'alloy',cut=.028,bevel=0)
    k.install(obj,blade,(obj.location.x,obj.location.y,0))


def bearing(b,path,s,half_width=.175):
    """Fixed lift saddle: the top meets the raised tongue and is exposed when it drops."""
    b.block(path,s-.23,s+.23,-half_width,half_width,.305,.462,
            'iron',cut=.045,bevel=.016)


def lead_in(b,path,start,end,side):
    """Taper the exposed ends of the inner bearing rails at the frog."""
    rings=[]
    for s,w,top in [(start,.062,.482),(start+.55,.146,.656),(end,.211,.926)]:
        rail=1.591
        shape=[(rail-w,.329),(rail+w,.329),(rail+w,top-.055),(rail+.76*w,top),
               (rail-.76*w,top),(rail-w,top-.055)]
        if side<0: shape=[(-u,z) for u,z in reversed(shape)]
        rings.append([path.at(s,u,z) for u,z in shape])
    n=len(rings[0])
    faces=[tuple(reversed(range(n))),tuple(range(2*n,3*n))]
    mats=['iron','iron']
    for j in range(2):
        for i in range(n):
            t=(i+1)%n
            faces.append((j*n+i,j*n+t,(j+1)*n+t,(j+1)*n+i))
            top_side=3 if side>0 else 1
            mats.append('steel' if i==top_side else 'iron')
    b.add([v for ring in rings for v in ring],faces,mats)


def build_fork(k,sign,root):
    stem=k.Path(0,24)
    branch=k.Path(sign,RADIUS*pi/2)
    b=k.Builder()
    turnout_deck(k,b,sign,stem,branch)
    # At the inlet the shared pair of outer guides is identical to the next track.
    # The two inside guides only rise once they clear the other lane's sled path.
    for path,side in [(stem,-sign),(branch,sign)]:
        k.guide(b,path,0,path.length,side)
        lead_in(b,path,13.55,15.03,-side)
        k.guide(b,path,15.03,path.length,-side)
        for i in range(round(path.length/4)):
            s=(i+.5)*path.length/round(path.length/4)
            k.outrigger(b,path,s,side)
            if s>15.7: k.outrigger(b,path,s,-side)

    k.pad(b,stem,.115,1.39)
    # Both tongues start on the common entry saddle before their centre lines diverge.
    bearing(b,stem,1.72,.225)
    for path,key,stop in [(stem,'straight',12.00),(branch,'branch',13.0)]:
        blade=next(ob for ob in root.children if ob.name.endswith('_blade_'+key))
        tongue(k,blade,path,stop)
        for mount in (5.20,8.80,stop-.22):
            bearing(b,path,mount)
        count=round((path.length-stop)/2)
        pitch=(path.length-stop)/count
        for i in range(count):
            s=stop+(i+.5)*pitch
            k.pad(b,path,s-pitch*.413,s+pitch*.413)
    k.status(b,stem,5,-sign)
    k.install(root,b)
