"""Portrait surfaces on the Derailer's existing head pivot, in Blender metres."""
from math import cos, pi, sin
import bmesh
import bpy
import numpy as np
from mathutils import Vector


def finishes(material):
    # Tile a hand-scaled rolled finish across the metal. Packing the maps carries
    # the same patina through the GLB exporter and into the selection portrait.
    rng = np.random.default_rng(173)
    size = 256
    grain = rng.normal(0, 0.014, (size, size)) + rng.normal(0, 0.005, (size, 1))
    yy, xx = np.indices((size, size))
    grain += 0.009 * np.sin(2*pi*(xx/size + 3*yy/size))
    for length_scale in (1,2,3,5,8):
        angle = rng.uniform(-pi,pi)
        grain += .005*np.sin(2*pi*(length_scale*xx/size + (length_scale+1)*yy/size)+angle)
    for _ in range(64):
        x, y = rng.integers(size, size=2)
        length = rng.integers(3, 32)
        t = np.arange(length)
        grain[(y + (t//8)) % size, (x+t) % size] += 0.045*np.sin(pi*t/length)
    for name, color, metal, roughness in (
        ("Derailer blued iron", (.33,.32,.31), .65, .45),
        ("Derailer brushed mask", (.49,.48,.45), .62, .42),
        ("Derailer oxblood enamel", (.38,.135,.10), .42, .36),
    ):
        mat = material(name, color, metal, roughness)
        image = bpy.data.images.new(name + " finish", width=size, height=size, alpha=False)
        image.colorspace_settings.name = "sRGB"
        pixels = np.ones((size,size,4), dtype=np.float32)
        pixels[:,:,:3] = np.clip(np.asarray(color) + grain[:,:,None], .02, .94)
        image.pixels.foreach_set(pixels.ravel())
        image.pack()
        node = mat.node_tree.nodes.new("ShaderNodeTexImage")
        node.image = image
        shader = next(n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
        mat.node_tree.links.new(node.outputs["Color"], shader.inputs["Base Color"])
    material("Derailer optic glass", (.36,.076,.009), .35, .17, (.95,.16,.006), .85)
    material("Derailer optic filament", (1,.56,.13), .12, .18, (1,.54,.085), 3.8)


def project_grain(mesh):
    uv = mesh.uv_layers.new(name="Metal grain")
    for face in mesh.polygons:
        axis = max(range(3), key=lambda k: abs(face.normal[k]))
        for loop in face.loop_indices:
            x, y, z = mesh.vertices[mesh.loops[loop].vertex_index].co
            pair = ((y,z), (x,z), (x,y))[axis]
            uv.data[loop].uv = (pair[0]*5.1, pair[1]*5.1)
    mesh.uv_layers.active = uv
    uv.active_render = True


def build_head(part, center, loft):
    iron, mask, enamel = "Derailer blued iron", "Derailer brushed mask", "Derailer oxblood enamel"
    seal, bronze = "moto_joint", "moto_brass"

    def at(x,y,z):
        return center + Vector((x,y,z))

    def plate(finish, points, depth, bevel=.0015):
        # Points describe the outward-facing outline, including its curvature.
        bm = loft([points, [p + Vector(depth) for p in points]])
        if bevel:
            bmesh.ops.bevel(bm, geom=bm.edges[:], offset=bevel, segments=2, affect="EDGES")
        part.add(bm, finish)

    def dome(angle, t, growth=1):
        # The back cups the occiput; the peak projects over the optics.
        a = angle
        front = max(0,cos(a))
        bottom = -.075 + .086*front**1.5
        radial = cos(t*pi/2)
        y = -.147*cos(a)*radial*(1+.09*front**5*(1-t)**4)
        z = .142*sin(t*pi/2) + bottom*(1-t)**2
        return at(.128*sin(a)*radial*growth, y*growth, z)

    def around(height, growth):
        return [dome(2*pi*i/64,height,growth) for i in range(64)]

    part.add(loft([around(0,.986), around(.008,1.008), around(.025,1.012)] +
                  [around(t/24,1) for t in range(1,24)] + [around(.998,1)]), iron)
    part.tube("moto_gunmetal", [*around(.03,1.014),dome(0,.03,1.014)], .0023, seg=8)

    # The rolled peak is one continuous piece from ear to ear. Its centre dips
    # toward the nose while its sides lift to clear the lenses.
    brow = []
    brow_trim = []
    for i in range(49):
        a = -1.69 + 3.38*i/48
        x,y = sin(a),-cos(a)
        z = .004 + .024*sin(min(abs(a)*1.7,pi/2)) - .033*max(0,abs(a)-.93)
        rim = at(.141*x,.177*y,z)
        brow.append([rim, rim+Vector((0,0,.005)), at(.137*x,.168*y,z+.014),
                     at(.121*x,.141*y,z+.029),at(.116*x,.132*y,z+.025),
                     at(.125*x,.151*y,z+.003)])
        brow_trim.append(at(.140*x,.176*y,z+.002))
    part.add(loft(brow), iron)
    part.tube("moto_steel",brow_trim,.0016,seg=8)

    # A narrow cast spine follows the helmet from the nape to the peaked brow.
    sections = []
    for i in range(49):
        a = pi*i/48
        n = Vector((0,cos(a),sin(a)))
        t = min(i,48-i)/24
        base = dome(pi if i <= 24 else 0,t)
        sections.append([base+Vector((x,0,0))+n*h for x,h in
                         ((-.015,-.005),(-.015,.002),(-.011,.005),(.011,.005),(.015,.002),(.015,-.005))])
    part.add(loft(sections), enamel)

    # A gasket shows between fitted mask plates. The centre fold runs from nose to chin.
    def mask_ring(z, width, projection, rear):
        return [at(width*x, rear+(projection-rear)*f,z+lift) for x,f,lift in
                ((0,1,-.002),(.52,.92,0),(.86,.72,.006),(1,.32,.009),
                 (.98,0,.005),(-.98,0,.005),(-1,.32,.009),(-.86,.72,.006),(-.52,.92,0))]

    part.add(loft([mask_ring(*row) for row in (
        (-.136,.049,-.099,-.026),(-.123,.068,-.12,-.014),(-.082,.101,-.137,.008),
        (-.034,.111,-.15,.030),(.003,.108,-.145,.035),(.028,.102,-.13,.035))]), seal)

    for side in (-1,1):
        def p(x,y,z):
            return at(side*x,y,z)

        def front_plate(finish, verts, thickness=.004):
            plate(finish,[p(*v) for v in verts],(0,thickness,0))

        def lens(finish, outline):
            # A continuous curved band with flatter front, turning into the temple.
            front_plate(finish,[(x, -.160 + 3.1*x*x - offset,z) for x,z,offset in outline])

        lens("moto_charcoal",[(.002,.015,.002),(.055,.028,.002),(.098,.029,.001),
                              (.112,.017,0),(.097,-.012,0),(.051,-.027,.001),(.011,-.017,.002)])
        lens("Derailer optic glass",[(.016,-.003,.008),(.063,.009,.008),(.097,.013,.008),
                                     (.090,-.001,.008),(.053,-.013,.008),(.023,-.014,.008)])
        lens("Derailer optic filament",[(.031,-.009,.010),(.065,.001,.010),(.084,.005,.010),
                                        (.065,-.004,.010),(.036,-.012,.010)])
        # Black rubber recesses sit between separately stamped cheek and jaw plates.
        front_plate(mask,[(.004,-.161,-.021),(.051,-.153,-.030),(.097,-.136,-.014),
                          (.110,-.110,-.036),(.084,-.121,-.073),(.040,-.149,-.084),(.006,-.16,-.059)], .009)
        front_plate(iron,[(.103,-.111,-.037),(.113,-.078,-.027),(.108,-.040,-.052),
                          (.091,-.053,-.091),(.059,-.105,-.122),(.049,-.128,-.100)])
        front_plate(mask,[(.002,-.157,-.060),(.038,-.145,-.083),(.070,-.130,-.073),
                          (.059,-.131,-.109),(.027,-.123,-.137),(.001,-.131,-.135)], .009)
        front_plate(iron,[(.106,-.111,-.037),(.100,-.132,-.014),(.108,-.115,.009),
                          (.127,-.063,.009),(.123,-.040,-.029),(.108,-.071,-.061)], .008)
        for x,y,z in ((.086,-.128,.045),(.119,-.074,.036),(.126,-.014,.040)):
            n=Vector((side*x,y,.03)).normalized()
            pos=p(x,y,z)
            part.cyl("moto_gunmetal",pos-n*.002,pos+n*.002,.0048,seg=14)
            part.cyl(bronze,pos+n*.0018,pos+n*.003,.0028,seg=10)
        for i in range(3):
            front_plate(seal,[(.020+i*.002,-.146+i*.002,-.085-i*.006),
                              (.043+i*.001,-.142+i*.002,-.079-i*.006),
                              (.041+i*.001,-.142+i*.002,-.082-i*.006),
                              (.020+i*.002,-.146+i*.002,-.088-i*.006)], .001)

        # Ear receiver, concentric cast rings, exposed fasteners and a short coiled lead.
        for x0,x1,r,mat in ((.101,.131,.055,seal),(.126,.143,.050,iron),(.142,.147,.040,bronze),
                             (.146,.151,.034,iron),(.150,.153,.024,"moto_charcoal"),(.152,.155,.015,mask)):
            part.cyl(mat,p(x0,.002,-.024),p(x1,.002,-.024),r,seg=36)
        for i in range(6):
            a=2*pi*i/6
            part.cyl(bronze,p(.143,.002+.044*cos(a),-.024+.044*sin(a)),
                     p(.146,.002+.044*cos(a),-.024+.044*sin(a)),.0033,seg=8)
            # Recessed ports break up the concentric rings of the receiver.
            for x,radius in ((.151,.028),(.155,.010)):
                y=.002+radius*cos(a)
                z=-.024+radius*sin(a)
                part.cyl(seal,p(x,y,z),p(x+.0009,y,z),.0028,seg=10)

        hose = [p(.132,.038,-.034),p(.146,.070,-.041),p(.145,.093,-.066),
                p(.134,.108,-.102),p(.099,.103,-.129),p(.074,.078,-.144)]
        part.tube(seal,hose,.012,seg=14,fillet=.007)
        for a,b in zip(hose,hose[1:]):
            d=(b-a).normalized()
            ribs=max(1,round((b-a).length/.009))
            for i in range(ribs):
                pos=a.lerp(b,(i+.5)/ribs)
                part.cyl("moto_gunmetal",pos-d*.0018,pos+d*.0018,.0130,seg=12)
        for x,y,z in ((.091,-.13,-.034),(.057,-.13,-.090)):
            part.cyl(bronze,p(x,y,z),p(x,y-.0026,z),.0036,seg=12)

    plate(mask,[at(0,-.169,.005),at(.016,-.161,-.010),at(.012,-.164,-.043),
                at(0,-.17,-.061),at(-.012,-.164,-.043),at(-.016,-.161,-.010)],(0,.009,0))
    for i in range(4):
        z=-.133-i*.009
        part.cyl(seal,at(0,.020,z-.003),at(0,.020,z+.003),.072-i*.001,seg=28)


def shoulder(part, center, tilt, loft):
    """A rolled pauldron leaves the lower team-painted lames visible."""
    rows = []
    def point(i, angle, inset=1):
        a = i*2*pi/40
        x = cos(a)*cos(angle)
        y = sin(a)*cos(angle)
        return center + tilt @ Vector((.134*x*inset,.151*y*inset,.091*sin(angle)))
    for angle, inset in ((-.14,.94),(-.14,1),(-.08,1.01),(.02,1.0),
                         (.18,1),(.37,1),(.56,1),(.75,1),(.94,1),(1.13,1),(1.32,1),(1.50,1),(1.565,1)):
        rows.append([point(i,angle,inset) for i in range(40)])
    part.add(loft(rows), "Derailer blued iron")
    part.tube("moto_steel",[point(i,-.08,1.01) for i in range(41)],.003,seg=8)
    # Countersunk pins on the flange of the upper plate.
    for i in (3,13,22,32):
        pos=point(i,.19)
        n=tilt @ Vector((cos(i*pi/20), sin(i*pi/20), .30)).normalized()
        part.cyl("moto_charcoal",pos-n*.001,pos+n*.0015,.007,seg=16)
        part.cyl("moto_brass",pos+n*.001,pos+n*.0025,.004,seg=12)
