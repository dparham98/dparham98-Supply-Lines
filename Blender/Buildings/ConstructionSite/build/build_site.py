"""Builds ConstructionSite.blend from nothing: the fenced site a building goes up inside.

Run in background Blender:
  blender --background --python build_site.py

Everything is rebuilt each run, so edits here never compound. One shared kit (posts, rope spans,
bunting, lamps, gate boom, site board, props) is laid out five times, once per footprint the game
plans: 2 x 2 (Iron Mine), 3 x 3 (Generator), 6 x 6 (Barracks), 8 x 8 (Tank Factory) and 10 x 10
(Depot), each in its own collection (site_2 .. site_10) that export_site.py writes to its own .glb. The front faces -Y,
Z up, base on Z = 0, centred on the footprint. The fence stands on the footprint's edge, one span per
cell, with the gate in the middle of the front.

Names the game reads (scripts/components/site_rig.gd):
  lamp_glass*  the lamp globes, recoloured by the site's state (waiting, ready, building)
  prop*        the clutter inside the fence on the larger sites, cleared away near the end of a build
The bunting sways in the one clip, Idle (3 s loop), as an NLA track per strand.
"""
import bpy, bmesh, math, os
from math import sin, cos, radians, pi
from mathutils import Vector as V, Matrix

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.normpath(os.path.join(HERE, "..", "ConstructionSite.blend"))
SIZES = (2, 3, 6, 8, 10)
FPS = 24
IDLE_FRAMES = 72                      # 3 s

bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
scene.render.fps = FPS

# ---------------------------------------------------------------- materials (flat PBR, linear colour)
MATS = {}


def material(name, col, met, rough, emis=None, strength=0.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = next(n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    b.inputs["Base Color"].default_value = (*col, 1)
    b.inputs["Metallic"].default_value = met
    b.inputs["Roughness"].default_value = rough
    if emis:
        b.inputs["Emission Color"].default_value = (*emis, 1)
        b.inputs["Emission Strength"].default_value = strength
    m.diffuse_color = (*col, 1)
    MATS[name] = m
    return m


material("site_timber", (0.20, 0.13, 0.07), 0.0, 0.85)
material("site_timber2", (0.13, 0.085, 0.045), 0.0, 0.9)
material("site_plank", (0.30, 0.21, 0.12), 0.0, 0.8)
material("site_hazard", (0.62, 0.42, 0.035), 0.05, 0.6)
material("site_black", (0.025, 0.025, 0.027), 0.1, 0.7)
material("site_rope", (0.36, 0.29, 0.18), 0.0, 0.95)
material("site_red", (0.42, 0.04, 0.025), 0.0, 0.7)
material("site_white", (0.62, 0.60, 0.55), 0.0, 0.75)
material("site_steel", (0.16, 0.155, 0.15), 0.6, 0.5)
material("site_board", (0.07, 0.11, 0.09), 0.0, 0.8)
material("site_sand", (0.38, 0.30, 0.19), 0.0, 0.95)
material("site_toolbox", (0.35, 0.05, 0.03), 0.3, 0.5)
# The game replaces the globe's colour with the site's state; amber here, as a site waiting.
material("site_lamp", (0.9, 0.62, 0.18), 0.0, 0.3, (1.0, 0.65, 0.15), 4.0)


# ---------------------------------------------------------------- geometry helpers
def mk_box(c, size, rot=None):
    bm = bmesh.new()
    M = Matrix.Translation(V(c)) @ (rot if rot else Matrix.Identity(4)) @ Matrix.Diagonal((*size, 1))
    bmesh.ops.create_cube(bm, size=1.0, matrix=M)
    return bm


def mk_cyl(p0, p1, r0, r1=None, seg=8):
    p0, p1 = V(p0), V(p1)
    r1 = r0 if r1 is None else r1
    d = p1 - p0
    bm = bmesh.new()
    M = Matrix.Translation((p0 + p1) / 2) @ d.to_track_quat('Z', 'Y').to_matrix().to_4x4()
    bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=seg, radius1=max(r0, 1e-4),
                          radius2=max(r1, 1e-4), depth=d.length, matrix=M)
    return bm


def mk_sphere(c, r, scale=(1, 1, 1), u=10, v=6):
    bm = bmesh.new()
    M = Matrix.Translation(V(c)) @ Matrix.Diagonal((*scale, 1))
    bmesh.ops.create_uvsphere(bm, u_segments=u, v_segments=v, radius=r, matrix=M)
    return bm


def mk_tri(a, b, c, thick=0.004):
    """A thin two-sided pennant: the triangle and its offset copy, closed round the edge."""
    a, b, c = V(a), V(b), V(c)
    n = (b - a).cross(c - a).normalized() * thick
    bm = bmesh.new()
    f = [bm.verts.new(p) for p in (a, b, c)]
    k = [bm.verts.new(p + n) for p in (a, b, c)]
    bm.faces.new(f)
    bm.faces.new(list(reversed(k)))
    for i in range(3):
        j = (i + 1) % 3
        bm.faces.new((f[j], f[i], k[i], k[j]))
    return bm


def mesh_from(name, parts):
    """parts: (bmesh, material name). One mesh datablock, so the kit is shared between sites."""
    me = bpy.data.meshes.new(name)
    out = bmesh.new()
    names = []
    for bm, mat in parts:
        if mat not in names:
            names.append(mat)
        idx = names.index(mat)
        tmp = bpy.data.meshes.new("_tmp")
        bm.to_mesh(tmp)
        bm.free()
        for p in tmp.polygons:
            p.material_index = idx
        out.from_mesh(tmp)
        bpy.data.meshes.remove(tmp)
    out.to_mesh(me)
    out.free()
    for mat in names:
        me.materials.append(MATS[mat])
    for p in me.polygons:
        p.use_smooth = False
    return me


# ---------------------------------------------------------------- the kit (meshes only)
POST_H = 0.62
ROPE_LO, ROPE_HI = 0.30, 0.54


def striped_cap(x, y, half, z0, bands, mat_a="site_hazard", mat_b="site_black", band=0.05):
    parts = []
    for i in range(bands):
        parts.append((mk_box((x, y, z0 + band * (i + 0.5)), (half * 2 + 0.012, half * 2 + 0.012, band)),
                      mat_a if i % 2 == 0 else mat_b))
    return parts


def kit_post():
    parts = [(mk_box((0, 0, POST_H / 2), (0.06, 0.06, POST_H)), "site_timber")]
    parts += striped_cap(0, 0, 0.03, POST_H - 0.10, 2)
    parts.append((mk_box((0, 0, POST_H + 0.012), (0.074, 0.074, 0.024)), "site_timber2"))
    return mesh_from("kit_post", parts)


LAMP_Z = 0.955


def kit_lamp_post():
    """A heavier post with a bracket and a caged lamp housing; the globe is a separate object."""
    h = 0.86
    parts = [(mk_box((0, 0, h / 2), (0.085, 0.085, h)), "site_timber")]
    parts += striped_cap(0, 0, 0.0425, h - 0.25, 4)
    parts.append((mk_box((0, 0, h + 0.015), (0.10, 0.10, 0.03)), "site_timber2"))
    # Housing: a dark base ring and four cage bars around the globe, a hood above.
    parts.append((mk_cyl((0, 0, h + 0.03), (0, 0, h + 0.05), 0.066, 0.066, seg=8), "site_steel"))
    for k in range(4):
        a = pi / 4 + k * pi / 2
        p = V((cos(a) * 0.062, sin(a) * 0.062, 0))
        parts.append((mk_cyl(p + V((0, 0, h + 0.05)), p + V((0, 0, h + 0.155)), 0.007, seg=4), "site_steel"))
    parts.append((mk_cyl((0, 0, h + 0.155), (0, 0, h + 0.19), 0.078, 0.035, seg=8), "site_black"))
    return mesh_from("kit_lamp_post", parts)


def kit_lamp_glass():
    return mesh_from("kit_lamp_glass", [(mk_sphere((0, 0, 0), 0.05, (1, 1, 1.2)), "site_lamp")])


def kit_rope():
    """Two rope lines along +X from 0 to 1 m, with a slight sag."""
    parts = []
    for z in (ROPE_LO, ROPE_HI):
        prev = None
        for i in range(5):
            t = i / 4
            p = V((t, 0, z - 0.03 * sin(pi * t)))
            if prev is not None:
                parts.append((mk_cyl(prev, p, 0.007, seg=5), "site_rope"))
            prev = p
    return mesh_from("kit_rope", parts)


def kit_bunting():
    """Pennants hung from the top rope, origin on the rope at mid-span so it can sway about X."""
    parts = []
    cols = ("site_red", "site_hazard", "site_white")
    n = 5
    for i in range(n):
        t = (i + 0.5) / n
        x = t - 0.5
        z = -0.03 * sin(pi * t) + 0.03 * sin(pi * 0.5)       # follow the sag, relative to the middle
        w = 0.06
        parts.append((mk_tri((x - w, 0, z), (x + w, 0, z), (x, 0, z - 0.12)), cols[i % 3]))
    return mesh_from("kit_bunting", parts)


def kit_boom(length):
    """The gate's barrier pole, hinged at its origin, striped red and white along +X."""
    parts = []
    segs = 6 * length
    for i in range(segs):
        a, b = i / segs * length, (i + 1) / segs * length
        parts.append((mk_cyl((a * 0.95, 0, 0), (b * 0.95, 0, 0), 0.016, seg=6),
                      "site_red" if i % 2 == 0 else "site_white"))
    parts.append((mk_box((-0.06, 0, 0), (0.10, 0.05, 0.05)), "site_black"))      # counterweight
    return mesh_from("kit_boom_%d" % length, parts)


def kit_board():
    """The site board, hung on the rope, facing -Y: a dark panel in a hazard frame, a white
    building outline and a crane hook so it reads as 'construction' from the game camera."""
    parts = []
    cx, cz, w, h = 0.0, 0.42, 0.56, 0.34
    parts.append((mk_box((cx, 0.0, cz), (w, 0.02, h)), "site_board"))
    fr = 0.03
    for i, (px, pz, sx, sz) in enumerate(((cx, cz + h / 2, w + fr, fr), (cx, cz - h / 2, w + fr, fr),
                                          (cx - w / 2, cz, fr, h + fr), (cx + w / 2, cz, fr, h + fr))):
        parts.append((mk_box((px, -0.004, pz), (sx, 0.026, sz)), "site_hazard"))
    # Diagonal hazard ticks along the bottom bar.
    for k in range(6):
        x = cx - w / 2 + 0.05 + k * (w - 0.1) / 5
        parts.append((mk_box((x, -0.018, cz - h / 2), (0.012, 0.004, fr * 0.9), Matrix.Rotation(radians(40), 4, 'Y')),
                      "site_black"))
    # A gabled building outline and a crane hook beside it.
    o = -0.0115
    def bar(p, q, t=0.012):
        p, q = V(p), V(q)
        d = q - p
        c = (p + q) / 2
        R = Matrix.Rotation(math.atan2(d.z, d.x), 4, 'Y').inverted()
        return (mk_box(c, (d.length + t, 0.003, t), R), "site_white")
    bx, bz = cx - 0.08, cz - 0.11
    for p, q in (((bx - 0.1, bz), (bx + 0.1, bz)), ((bx - 0.1, bz), (bx - 0.1, bz + 0.12)),
                 ((bx + 0.1, bz), (bx + 0.1, bz + 0.12)), ((bx - 0.12, bz + 0.11), (bx, bz + 0.19)),
                 ((bx, bz + 0.19), (bx + 0.12, bz + 0.11))):
        parts.append(bar((p[0], o, p[1]), (q[0], o, q[1])))
    hx = cx + 0.16
    hook = ((hx, cz + 0.13), (hx, cz - 0.03), (hx - 0.015, cz - 0.065), (hx - 0.045, cz - 0.075),
            (hx - 0.07, cz - 0.055), (hx - 0.072, cz - 0.03))
    for p, q in zip(hook, hook[1:]):
        parts.append(bar((p[0], o, p[1]), (q[0], o, q[1])))
    # Two short legs down to the ground behind the panel, so it stands as well as hangs.
    for sx in (-1, 1):
        parts.append((mk_box((cx + sx * (w / 2 - 0.04), 0.03, (cz - h / 2) / 2), (0.035, 0.035, cz - h / 2)), "site_timber"))
    return mesh_from("kit_board", parts)


def kit_sawhorse():
    parts = []
    L, H = 0.5, 0.26
    parts.append((mk_box((0, 0, H), (L, 0.05, 0.04)), "site_timber"))
    for sx in (-1, 1):
        for sy in (-1, 1):
            p = V((sx * (L / 2 - 0.05), 0, H))
            q = V((sx * (L / 2 - 0.02), sy * 0.11, 0))
            parts.append((mk_cyl(p, q, 0.014, seg=4), "site_timber2"))
    # Two planks laid across it, one resting on the ground at its other end.
    parts.append((mk_box((0.05, 0.0, H + 0.035), (0.9, 0.12, 0.024), Matrix.Rotation(radians(-3), 4, 'Y')), "site_plank"))
    parts.append((mk_box((-0.05, 0.13, H * 0.55), (0.85, 0.11, 0.022), Matrix.Rotation(radians(17), 4, 'Y')), "site_plank"))
    return mesh_from("kit_sawhorse", parts)


def kit_planks():
    parts = []
    for i in range(4):
        z = 0.012 + i * 0.026
        r = Matrix.Rotation(radians((-1) ** i * 4), 4, 'Z')
        parts.append((mk_box((0.01 * i, 0, z), (0.9, 0.11, 0.024), r), "site_plank" if i % 2 else "site_timber"))
    for x in (-0.3, 0.3):
        parts.append((mk_box((x, 0, 0.006), (0.05, 0.16, 0.012)), "site_timber2"))
    return mesh_from("kit_planks", parts)


def kit_sand():
    """A sand heap with a shovel stuck in it."""
    bm = mk_sphere((0, 0, 0), 0.22, (1.2, 1.0, 0.55), u=12, v=6)
    bmesh.ops.bisect_plane(bm, geom=bm.verts[:] + bm.edges[:] + bm.faces[:], plane_co=(0, 0, 0),
                           plane_no=(0, 0, -1), clear_outer=True)
    parts = [(bm, "site_sand")]
    s0, s1 = V((0.04, 0.0, 0.05)), V((0.14, -0.03, 0.42))
    parts.append((mk_cyl(s0, s1, 0.011, seg=5), "site_timber"))
    parts.append((mk_box(s0 + (s0 - s1).normalized() * 0.05, (0.08, 0.012, 0.10),
                         (s1 - s0).to_track_quat('Z', 'Y').to_matrix().to_4x4()), "site_steel"))
    parts.append((mk_box(s1, (0.07, 0.015, 0.015)), "site_black"))
    return mesh_from("kit_sand", parts)


def kit_toolbox():
    parts = [(mk_box((0, 0, 0.055), (0.26, 0.12, 0.11)), "site_toolbox"),
             (mk_box((0, 0, 0.115), (0.27, 0.125, 0.012)), "site_steel")]
    for sx in (-1, 1):
        parts.append((mk_cyl((sx * 0.06, 0, 0.12), (sx * 0.06, 0, 0.16), 0.006, seg=4), "site_steel"))
    parts.append((mk_cyl((-0.065, 0, 0.16), (0.065, 0, 0.16), 0.008, seg=5), "site_black"))
    return mesh_from("kit_toolbox", parts)


KIT = {
    "post": kit_post(), "lamp_post": kit_lamp_post(), "lamp_glass": kit_lamp_glass(), "rope": kit_rope(),
    "bunting": kit_bunting(), "boom1": kit_boom(1), "boom2": kit_boom(2), "board": kit_board(), "sawhorse": kit_sawhorse(),
    "planks": kit_planks(), "sand": kit_sand(), "toolbox": kit_toolbox(),
}


# ---------------------------------------------------------------- laying out one site
def obj(coll, name, mesh, loc, rot_z=0.0, parent=None):
    o = bpy.data.objects.new(name, mesh)
    o.location = loc
    o.rotation_euler = (0, 0, rot_z)
    if parent is not None:
        o.parent = parent
    coll.objects.link(o)
    return o


def gate_spans(size):
    """Indices of the front spans left open as the gate."""
    if size <= 2:
        return {size - 1}
    if size % 2 == 1:
        return {size // 2}
    return {size // 2 - 1, size // 2}


def push_idle(ob, fn):
    """Bake one Idle clip onto ob as an NLA track named Idle; fn(t) -> rotation about local X."""
    ad = ob.animation_data_create()
    act = bpy.data.actions.new("%s_Idle" % ob.name)
    ad.action = act
    for f in range(IDLE_FRAMES + 1):
        ob.rotation_euler = (fn(f / IDLE_FRAMES), 0, ob.rotation_euler.z)
        ob.keyframe_insert("rotation_euler", frame=f)
    ad.action = None
    track = ad.nla_tracks.new()
    track.name = "Idle"
    track.strips.new("Idle", 0, act)
    ob.rotation_euler = (0, 0, ob.rotation_euler.z)


def build_site(size):
    coll = bpy.data.collections.new("site_%d" % size)
    scene.collection.children.link(coll)
    tag = "s%d_" % size
    root = bpy.data.objects.new(tag + "root", None)
    coll.objects.link(root)
    h = size / 2
    gate = gate_spans(size)
    # Sides walked anticlockwise from the front-left corner: front (-Y), right (+X), back (+Y), left (-X).
    sides = [((-h, -h), (1, 0)), ((h, -h), (0, 1)), ((h, h), (-1, 0)), ((-h, h), (0, -1))]
    lamps = 0
    strand = 0
    for s, ((sx, sy), (dx, dy)) in enumerate(sides):
        yaw = math.atan2(dy, dx)
        for i in range(size):
            a = V((sx + dx * i, sy + dy * i, 0))
            front = s == 0
            open_span = front and i in gate
            gate_post = front and ((i in gate and i - 1 not in gate) or (i - 1 in gate and i not in gate))
            if front and i in gate and i - 1 in gate:
                pass                          # no post standing in the middle of a wide gate
            elif i == 0:
                o = obj(coll, tag + "corner_%d" % s, KIT["lamp_post"], a, yaw, root)
                obj(coll, tag + "lamp_glass_%d" % lamps, KIT["lamp_glass"], a + V((0, 0, LAMP_Z)), 0, root)
                lamps += 1
            elif gate_post:
                obj(coll, tag + "gate_post_%d" % i, KIT["lamp_post"], a, yaw, root)
                obj(coll, tag + "lamp_glass_%d" % lamps, KIT["lamp_glass"], a + V((0, 0, LAMP_Z)), 0, root)
                lamps += 1
            else:
                obj(coll, tag + "post_%d_%d" % (s, i), KIT["post"], a, yaw, root)
            if open_span:
                continue
            obj(coll, tag + "rope_%d_%d" % (s, i), KIT["rope"], a, yaw, root)
            mid = a + V((dx, dy, 0)) * 0.5 + V((0, 0, ROPE_HI))
            b = obj(coll, tag + "bunting_%d" % strand, KIT["bunting"], mid, yaw, root)
            phase = strand * 0.37
            amp = radians(9 + 4 * ((strand * 7) % 3) / 2)
            push_idle(b, lambda t, ph=phase, am=amp: am * sin(2 * pi * t + ph) + am * 0.35 * sin(4 * pi * t + 2 * ph))
            strand += 1
    # The gate's boom, raised, hinged on the left gate post; the board on the span left of the gate.
    g0 = min(gate)
    hinge = V((-h + g0, -h, 0.70))
    boom = obj(coll, tag + "gate_boom", KIT["boom%d" % len(gate)], hinge + V((0.0, -0.06, 0)), 0, root)
    boom.rotation_euler = (0, radians(-62 if len(gate) == 1 else -48), 0)
    board_span = g0 - 1 if g0 >= 1 else None
    if board_span is not None:
        obj(coll, tag + "board", KIT["board"], V((-h + board_span + 0.5, -h - 0.03, 0)), 0, root)
    else:
        obj(coll, tag + "board", KIT["board"], V((-h + 0.5, -h - 0.03, 0)), 0, root)
    # Clutter inside the front corners on the sites big enough to keep it clear of the building.
    if size >= 6:
        m = 0.42
        obj(coll, tag + "prop_sawhorse", KIT["sawhorse"], V((-h + 0.75, -h + m, 0)), radians(4), root)
        obj(coll, tag + "prop_toolbox", KIT["toolbox"], V((-h + 1.45, -h + 0.28, 0)), radians(-12), root)
        obj(coll, tag + "prop_sand", KIT["sand"], V((h - 0.55, -h + 0.5, 0)), radians(30), root)
        obj(coll, tag + "prop_planks", KIT["planks"], V((h - 0.35, -h + 1.45, 0)), radians(88), root)
        if size >= 8:
            obj(coll, tag + "prop_planks_back", KIT["planks"], V((-h + 0.35, h - 1.6, 0)), radians(92), root)
            obj(coll, tag + "prop_sand_back", KIT["sand"], V((h - 0.6, h - 0.55, 0)), radians(-20), root)
        if size >= 10:
            obj(coll, tag + "prop_sawhorse_back", KIT["sawhorse"], V((h - 1.3, h - 0.42, 0)), radians(178), root)
            obj(coll, tag + "prop_toolbox_back", KIT["toolbox"], V((-h + 1.2, h - 0.3, 0)), radians(160), root)
    return coll, lamps


report = []
for size in SIZES:
    coll, lamps = build_site(size)
    tris = sum(sum(len(p.vertices) - 2 for p in o.data.polygons) for o in coll.objects if o.type == 'MESH')
    report.append((size, len(coll.objects), lamps, tris))

# Lay the five out side by side in the file so they can all be seen at once; the export resets each.
x = 0.0
for size in SIZES:
    root = bpy.data.objects["s%d_root" % size]
    root.location = (x + size / 2, 0, 0)
    x += size + 2
scene.frame_start, scene.frame_end = 0, IDLE_FRAMES
bpy.ops.wm.save_as_mainfile(filepath=OUT)
for size, count, lamps, tris in report:
    print("SITE %dx%d: %d objects, %d lamps, %d triangles" % (size, size, count, lamps, tris))
print("SAVED", OUT)
