"""Build, rig, animate, and export the Arthurian Azure Dragon with barding armor and war-saddle.

Run headless:
  "C:/Program Files/Blender Foundation/Blender 4.5/blender.exe" -b --factory-startup --python-exit-code 1 -P Blender/Characters/AzureDragon/source/build_azure_dragon.py
"""

from math import atan2, cos, pi, radians, sin, tau
from pathlib import Path
import sys

import bpy
import bmesh
from mathutils import Vector


HERE = Path(__file__).resolve().parent
if str(HERE) not in sys.path:
    sys.path.insert(0, str(HERE))

PACKAGE = HERE.parent
BLEND_PATH = HERE / "Azure_Dragon.blend"
EXPORT_PATH = PACKAGE / "export" / "azure_dragon.glb"

MUZZLE_POS = Vector((0.0, -1.48, 2.09))
BREATH_LENGTH = 7.50


def clamp(v, lo=0.0, hi=1.0):
    return max(lo, min(hi, v))


def lerp(a, b, t):
    return a + (b - a) * t


def smoothstep(lo, hi, x):
    t = clamp((x - lo) / (hi - lo) if hi != lo else 0.0)
    return t * t * (3.0 - 2.0 * t)


def catmull_rom(pts, t):
    """Evaluate a Catmull-Rom spline through a sequence of Vector points for t in [0, 1]."""
    n = len(pts) - 1
    if n < 1:
        return Vector(pts[0]), Vector((0, 1, 0))
    scaled = clamp(t, 0.0, 1.0) * n
    i = min(int(scaled), n - 1)
    u = scaled - i
    p0 = Vector(pts[max(0, i - 1)])
    p1 = Vector(pts[i])
    p2 = Vector(pts[i + 1])
    p3 = Vector(pts[min(n, i + 2)])

    u2 = u * u
    u3 = u2 * u
    pos = 0.5 * (
        (2.0 * p1)
        + (-p0 + p2) * u
        + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * u2
        + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * u3
    )
    tan = 0.5 * (
        (-p0 + p2)
        + (4.0 * p0 - 10.0 * p1 + 8.0 * p2 - 2.0 * p3) * u
        + (-3.0 * p0 + 9.0 * p1 - 9.0 * p2 + 3.0 * p3) * u2
    )
    if tan.length < 1e-6:
        tan = (p2 - p1) if (p2 - p1).length > 1e-6 else Vector((0, 1, 0))
    return pos, tan.normalized()


def frame_from_tangent(tan, up_hint=Vector((0, 0, 1))):
    """Return right (+X-like), normal (up-like), tangent unit vectors."""
    t = tan.normalized()
    right = t.cross(up_hint)
    if right.length < 1e-5:
        right = t.cross(Vector((1, 0, 0)))
    right.normalize()
    up = right.cross(t).normalized()
    return right, up, t


def make_material(name, rgb, roughness=0.45, metallic=0.0, emission=None, emission_strength=0.0,
                  sheen=0.0, alpha=1.0, vertex_color_layer=None, emission_from_vcol=False):
    mat = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    mat.use_nodes = True
    mat.diffuse_color = (*rgb, alpha)
    bsdf = next(n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    bsdf.inputs["Base Color"].default_value = (*rgb, 1.0)
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = metallic
    if sheen > 0 and "Sheen Weight" in bsdf.inputs:
        bsdf.inputs["Sheen Weight"].default_value = sheen
    if emission is not None and "Emission Color" in bsdf.inputs:
        bsdf.inputs["Emission Color"].default_value = (*emission, 1.0)
        bsdf.inputs["Emission Strength"].default_value = emission_strength
    if alpha < 1.0 and "Alpha" in bsdf.inputs:
        bsdf.inputs["Alpha"].default_value = alpha
        if hasattr(mat, "blend_method"):
            mat.blend_method = "BLEND"
        if hasattr(mat, "surface_render_method"):
            mat.surface_render_method = "BLENDED"
    if vertex_color_layer:
        vcol = mat.node_tree.nodes.new("ShaderNodeVertexColor")
        vcol.layer_name = vertex_color_layer
        mat.node_tree.links.new(vcol.outputs["Color"], bsdf.inputs["Base Color"])
        if emission_from_vcol and "Emission Color" in bsdf.inputs:
            mat.node_tree.links.new(vcol.outputs["Color"], bsdf.inputs["Emission Color"])
    return mat


def create_palette():
    mats = {}
    # Rich Cobalt/Cerulean Azure Dragon organic palette
    mats["Dragon_Azure_Scales"] = make_material("Dragon_Azure_Scales", (0.016, 0.125, 0.65), roughness=0.40, metallic=0.06)
    mats["Dragon_Bright_Azure"] = make_material("Dragon_Bright_Azure", (0.026, 0.180, 0.75), roughness=0.38, metallic=0.05)
    mats["Dragon_Deep_Azure"] = make_material("Dragon_Deep_Azure", (0.007, 0.052, 0.36), roughness=0.46, metallic=0.06)

    mats["Dragon_Wing_Membrane"] = make_material(
        "Dragon_Wing_Membrane", (0.045, 0.30, 0.84), roughness=0.38, metallic=0.02,
        vertex_color_layer="WingGradient"
    )

    mats["Dragon_Cream_Belly"] = make_material("Dragon_Cream_Belly", (0.76, 0.70, 0.57), roughness=0.46, metallic=0.04)
    mats["Dragon_Cream_Recess"] = make_material("Dragon_Cream_Recess", (0.48, 0.41, 0.31), roughness=0.55, metallic=0.04)
    mats["Dragon_Horn_Ivory"] = make_material("Dragon_Horn_Ivory", (0.82, 0.72, 0.52), roughness=0.34, metallic=0.10)
    mats["Dragon_Horn_Gold"] = make_material("Dragon_Horn_Gold", (0.74, 0.49, 0.16), roughness=0.32, metallic=0.45)
    mats["Dragon_Eye_Gold"] = make_material(
        "Dragon_Eye_Gold", (1.0, 0.64, 0.06), roughness=0.15, metallic=0.0,
        emission=(1.0, 0.58, 0.04), emission_strength=2.2
    )
    mats["Dragon_Pupil"] = make_material("Dragon_Pupil", (0.010, 0.010, 0.015), roughness=0.15, metallic=0.0)

    # Open-Jaw & Fire-Breath FX materials
    mats["Dragon_Mouth_Inner"] = make_material(
        "Dragon_Mouth_Inner", (0.18, 0.025, 0.03), roughness=0.55, metallic=0.0,
        emission=(0.85, 0.22, 0.03), emission_strength=0.38
    )
    mats["Dragon_Tongue"] = make_material("Dragon_Tongue", (0.34, 0.065, 0.065), roughness=0.48, metallic=0.0)
    mats["Dragon_Fire_Core"] = make_material(
        "Dragon_Fire_Core", (1.0, 0.94, 0.62), roughness=0.20, metallic=0.0,
        emission=(1.0, 0.85, 0.35), emission_strength=4.8
    )
    mats["Dragon_Fire_Mid"] = make_material(
        "Dragon_Fire_Mid", (1.0, 0.36, 0.02), roughness=0.25, metallic=0.0,
        emission=(1.0, 0.38, 0.025), emission_strength=3.0, alpha=0.56
    )
    mats["Dragon_Fire_Outer"] = make_material(
        "Dragon_Fire_Outer", (0.95, 0.18, 0.01), roughness=0.30, metallic=0.0,
        emission=(0.95, 0.18, 0.01), emission_strength=2.1, alpha=0.44,
        vertex_color_layer="FireGradient", emission_from_vcol=True
    )
    mats["Dragon_Fire_Plume"] = make_material(
        "Dragon_Fire_Plume", (1.0, 0.44, 0.03), roughness=0.25, metallic=0.0,
        emission=(1.0, 0.44, 0.03), emission_strength=3.4, alpha=0.62
    )

    # Arthurian Marine Barding & Tack materials
    mats["Ivory_Armor"] = make_material("Ivory_Armor", (0.83, 0.81, 0.72), roughness=0.40, metallic=0.32)
    mats["Satin_Silver"] = make_material("Satin_Silver", (0.69, 0.72, 0.73), roughness=0.38, metallic=0.55)
    mats["Recessed_Steel"] = make_material("Recessed_Steel", (0.24, 0.27, 0.30), roughness=0.44, metallic=0.62)
    mats["Heraldic_Brass"] = make_material("Heraldic_Brass", (0.78, 0.51, 0.14), roughness=0.32, metallic=0.68)
    mats["team_color"] = make_material("team_color", (0.022, 0.068, 0.36), roughness=0.58, metallic=0.08)
    mats["team_color_shadow"] = make_material("team_color_shadow", (0.011, 0.028, 0.16), roughness=0.68, metallic=0.04)
    mats["Harness_Leather"] = make_material("Harness_Leather", (0.14, 0.070, 0.030), roughness=0.54, metallic=0.0)
    mats["Saddle_Leather_Dark"] = make_material("Saddle_Leather_Dark", (0.075, 0.036, 0.016), roughness=0.60, metallic=0.0)
    return mats


def create_mesh_obj(name, collection, parent, verts, faces, face_mats=None, default_mat="Dragon_Azure_Scales",
                    smooth=False, auto_recalc_normals=True):
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata([tuple(v) for v in verts], [], faces)
    mesh.update()

    if face_mats is None:
        face_mats = [default_mat] * len(faces)
    unique_mats = list(dict.fromkeys(face_mats))
    for m_name in unique_mats:
        mesh.materials.append(bpy.data.materials[m_name])

    for poly, m_name in zip(mesh.polygons, face_mats):
        poly.material_index = unique_mats.index(m_name)
        poly.use_smooth = smooth

    if auto_recalc_normals:
        bm = bmesh.new()
        bm.from_mesh(mesh)
        bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
        bm.to_mesh(mesh)
        bm.free()

    obj = bpy.data.objects.new(name, mesh)
    collection.objects.link(obj)
    if parent is not None:
        obj.parent = parent
    return obj


def loft_rings(name, collection, parent, rings, ring_mats=None, default_mat="Dragon_Azure_Scales",
               cap_start=True, cap_end=True, smooth=False, face_mat_fn=None):
    """Loft a sequence of equal-length vertex rings into a clean mesh."""
    n = len(rings[0])
    verts = [v for r in rings for v in r]
    faces = []
    face_mats = []
    for i in range(len(rings) - 1):
        m_ring = ring_mats[i] if ring_mats and i < len(ring_mats) else default_mat
        for j in range(n):
            nj = (j + 1) % n
            faces.append((i * n + j, i * n + nj, (i + 1) * n + nj, (i + 1) * n + j))
            if face_mat_fn is not None:
                face_mats.append(face_mat_fn(i, j, n, len(rings)))
            else:
                face_mats.append(m_ring)
    if cap_start and n >= 3:
        faces.append(tuple(reversed(range(n))))
        face_mats.append(face_mats[0] if face_mats else default_mat)
    if cap_end and n >= 3:
        last = (len(rings) - 1) * n
        faces.append(tuple(range(last, last + n)))
        face_mats.append(face_mats[-1] if face_mats else default_mat)
    return create_mesh_obj(name, collection, parent, verts, faces, face_mats, default_mat, smooth=smooth)


# ---------------------------------------------------------------------------
# 1. DRAGON SPINE, NECK, TORSO, BELLY SCUTES & TAIL
# ---------------------------------------------------------------------------

SPINE_CONTROLS = [
    (0.00, -1.05, 2.20, 0.145, 0.155, 0.145),  # 0: skull base / atlas
    (0.00, -1.01, 1.98, 0.165, 0.175, 0.165),  # 1: upper neck
    (0.00, -0.96, 1.72, 0.210, 0.215, 0.195),  # 2: mid neck
    (0.00, -0.87, 1.48, 0.285, 0.280, 0.260),  # 3: lower neck
    (0.00, -0.68, 1.30, 0.420, 0.370, 0.380),  # 4: chest entry
    (0.00, -0.40, 1.36, 0.470, 0.410, 0.430),  # 5: broad thorax / shoulders
    (0.00, -0.06, 1.42, 0.420, 0.350, 0.380),  # 6: mid-back (under saddle)
    (0.00, +0.28, 1.41, 0.390, 0.330, 0.340),  # 7: lumbar / loins
    (0.00, +0.60, 1.35, 0.360, 0.300, 0.300),  # 8: pelvis / croup
    (0.000, 0.93, 1.22, 0.270, 0.240, 0.230),  # first caudal vertebrae
    (0.014, 1.26, 1.04, 0.215, 0.195, 0.190),
    (0.047, 1.58, 0.86, 0.170, 0.155, 0.155),
    (0.077, 1.91, 0.70, 0.130, 0.125, 0.120),
    (0.089, 2.24, 0.59, 0.097, 0.095, 0.092),
    (0.079, 2.57, 0.52, 0.068, 0.068, 0.065),
    (0.043, 2.88, 0.48, 0.040, 0.043, 0.040),
    (-0.009, 3.16, 0.46, 0.009, 0.011, 0.010),  # relaxed tapered tip
]


def eval_spine(t):
    pts = [Vector(c[:3]) for c in SPINE_CONTROLS]
    dims = [Vector(c[3:]) for c in SPINE_CONTROLS]
    pos, tan = catmull_rom(pts, t)
    dim, _ = catmull_rom(dims, t)
    return pos, tan, dim.x, dim.y, dim.z


def build_body_and_tail(collection, root):
    n_steps = 92
    n_sides = 28
    rings = []
    ring_frames = []

    for i in range(n_steps):
        t = i / (n_steps - 1)
        pos, tan, rx, rz_top, rz_bot = eval_spine(t)
        right, up, forward = frame_from_tangent(tan)
        ring_frames.append((t, pos, right, up, forward, rx, rz_top, rz_bot))

        ring = []
        for j in range(n_sides):
            ang = tau * j / n_sides
            sa = sin(ang)
            ca = cos(ang)
            rz = rz_top if ca >= 0 else rz_bot

            crest = 1.0 + 0.10 * max(0.0, ca) ** 3
            belly_flat = 1.0 - 0.10 * max(0.0, -ca) ** 2
            side_flare = 1.0 + 0.08 * (sa ** 2) * smoothstep(0.18, 0.45, t) * (1.0 - smoothstep(0.55, 0.80, t))

            lx = rx * sa * side_flare
            lz = rz * ca * crest * belly_flat
            pt = pos + right * lx + up * lz
            ring.append(pt)
        rings.append(ring)

    def body_face_mat(i, j, n, total_rings):
        ang = tau * (j + 0.5) / n
        ca = cos(ang)
        t = i / max(1, total_rings - 1)
        if ca < -0.58 and (t < 0.23 or t > 0.52):
            return "Dragon_Cream_Belly" if (i % 2 == 0) else "Dragon_Cream_Recess"
        if ca > 0.78:
            return "Dragon_Deep_Azure"
        return "Dragon_Azure_Scales"

    body_obj = loft_rings(
        "Dragon_Body", collection, root, rings,
        default_mat="Dragon_Azure_Scales", smooth=False, face_mat_fn=body_face_mat
    )

    build_throat_and_tail_scutes(collection, root, ring_frames)
    build_layered_body_scales(collection, root, ring_frames)
    build_dorsal_spines(collection, root, ring_frames)
    return body_obj, ring_frames


def build_throat_and_tail_scutes(collection, root, ring_frames):
    """Build articulated overlapping horizontal cream-ivory plates down the throat and under the tail."""
    verts = []
    faces = []
    mats = []

    def add_scute_band(f_curr, f_next, half_ang=0.58, thickness=0.022):
        _, pos0, right0, up0, _, rx0, _, rzb0 = f_curr
        _, pos1, right1, up1, _, rx1, _, rzb1 = f_next
        steps = 8
        base = len(verts)
        for k in range(steps + 1):
            u = -1.0 + 2.0 * k / steps
            ang = pi + u * half_ang
            sa, ca = sin(ang), cos(ang)
            p0_in = pos0 + right0 * (rx0 * sa * 0.98) + up0 * (rzb0 * ca * 0.90)
            p0_out = pos0 + right0 * ((rx0 + thickness * 0.45) * sa) + up0 * ((rzb0 + thickness) * ca * 0.90)
            p1_out = pos1 + right1 * ((rx1 + thickness) * sa) + up1 * ((rzb1 + thickness * 1.15) * ca * 0.90)
            p1_in = pos1 + right1 * (rx1 * sa * 0.97) + up1 * (rzb1 * ca * 0.90)
            verts.extend([p0_in, p0_out, p1_out, p1_in])

        for k in range(steps):
            b = base + k * 4
            faces.append((b + 0, b + 4, b + 5, b + 1))
            mats.append("Dragon_Cream_Recess")
            faces.append((b + 1, b + 5, b + 6, b + 2))
            mats.append("Dragon_Cream_Belly")
            faces.append((b + 2, b + 6, b + 7, b + 3))
            mats.append("Dragon_Cream_Recess")

    for idx in range(1, 19, 2):
        add_scute_band(ring_frames[idx], ring_frames[idx + 2], half_ang=0.58, thickness=0.022)

    for idx in range(50, 86, 2):
        add_scute_band(ring_frames[idx], ring_frames[idx + 2], half_ang=0.50, thickness=0.015)

    create_mesh_obj("Dragon_Belly_Scutes", collection, root, verts, faces, mats, smooth=False)


def add_diamond_scale(verts, faces, mats, center, tangent_down, tangent_side, normal,
                      length=0.095, width=0.072, thickness=0.012, mat_top="Dragon_Azure_Scales"):
    """Add a sleek, low-profile overlapping diamond dragon scale hugging the surface."""
    base = len(verts)
    p_top = center - tangent_down * (length * 0.46) - normal * (thickness * 0.15)
    p_left = center + tangent_side * (width * 0.50) + normal * (thickness * 0.35)
    p_right = center - tangent_side * (width * 0.50) + normal * (thickness * 0.35)
    p_tip = center + tangent_down * (length * 0.58) + normal * (thickness * 0.85)
    p_crest = center + tangent_down * (length * 0.08) + normal * (thickness * 0.78)
    p_bot = center + tangent_down * (length * 0.52)

    verts.extend([p_top, p_left, p_right, p_tip, p_crest, p_bot])
    faces.extend([
        (base + 0, base + 1, base + 4),
        (base + 0, base + 4, base + 2),
        (base + 1, base + 3, base + 4),
        (base + 4, base + 3, base + 2),
        (base + 1, base + 5, base + 3),
        (base + 3, base + 5, base + 2),
    ])
    mats.extend([
        mat_top, mat_top, "Dragon_Bright_Azure", mat_top,
        "Dragon_Deep_Azure", "Dragon_Deep_Azure"
    ])


def build_layered_body_scales(collection, root, ring_frames):
    """Populate sleek overlapping rows of faceted scales along the neck, flanks, and tail."""
    verts, faces, mats = [], [], []
    for idx in range(2, len(ring_frames) - 3):
        t, pos, right, up, forward, rx, rz_top, rz_bot = ring_frames[idx]
        if 0.21 < t < 0.33 or 0.38 < t < 0.49:
            continue
        n_row = 11 if t < 0.65 else 8
        for k in range(n_row):
            frac = (k + 0.5 * (idx % 2)) / n_row
            ang = lerp(0.30, 2.25, frac)
            for side in (-1.0, 1.0):
                sa = side * sin(ang)
                ca = cos(ang)
                rz = rz_top if ca >= 0 else rz_bot
                surf_pt = pos + right * (rx * sa) + up * (rz * ca)
                if 0.44 < t < 0.58 and surf_pt.z > 1.02 and abs(surf_pt.x) > 0.26:
                    continue
                nrm = (right * (sa / max(0.05, rx)) + up * (ca / max(0.05, rz))).normalized()
                tan_side = forward.cross(nrm).normalized()
                scale_len = lerp(0.088, 0.042, smoothstep(0.55, 0.98, t))
                scale_wid = scale_len * 0.78
                add_diamond_scale(
                    verts, faces, mats,
                    surf_pt - nrm * 0.002,
                    forward, tan_side, nrm,
                    length=scale_len, width=scale_wid, thickness=scale_len * 0.13
                )
    create_mesh_obj("Dragon_Body_Scales", collection, root, verts, faces, mats, smooth=False)


def build_dorsal_spines(collection, root, ring_frames):
    """Build swept-back ivory & gold dorsal spines along the neck and tail."""
    verts, faces, mats = [], [], []

    def add_spine(pos, right, up, forward, height, base_len, base_w):
        b = len(verts)
        p_front = pos - forward * (base_len * 0.55) - up * 0.015
        p_back = pos + forward * (base_len * 0.55) - up * 0.015
        p_left = pos + right * base_w - up * 0.01
        p_right = pos - right * base_w - up * 0.01
        p_mid_f = pos - forward * (base_len * 0.10) + up * (height * 0.50)
        p_mid_b = pos + forward * (base_len * 0.70) + up * (height * 0.40)
        p_mid_l = pos + forward * (base_len * 0.28) + right * (base_w * 0.52) + up * (height * 0.46)
        p_mid_r = pos + forward * (base_len * 0.28) - right * (base_w * 0.52) + up * (height * 0.46)
        p_tip = pos + forward * (base_len * 1.15) + up * height

        verts.extend([p_front, p_left, p_back, p_right, p_mid_f, p_mid_l, p_mid_b, p_mid_r, p_tip])
        faces.extend([
            (b + 0, b + 1, b + 5, b + 4),
            (b + 1, b + 2, b + 6, b + 5),
            (b + 2, b + 3, b + 7, b + 6),
            (b + 3, b + 0, b + 4, b + 7),
        ])
        mats.extend(["Dragon_Horn_Gold"] * 4)
        faces.extend([
            (b + 4, b + 5, b + 8),
            (b + 5, b + 6, b + 8),
            (b + 6, b + 7, b + 8),
            (b + 7, b + 4, b + 8),
        ])
        mats.extend(["Dragon_Horn_Ivory"] * 4)

    for idx in range(1, 18, 2):
        t, pos, right, up, forward, rx, rz_top, _ = ring_frames[idx]
        top_pt = pos + up * (rz_top * 1.01)
        h = lerp(0.180, 0.115, (idx - 1) / 16.0)
        add_spine(top_pt, right, up, forward, height=h, base_len=h * 0.90, base_w=0.028)

    for idx in range(54, 89, 2):
        t, pos, right, up, forward, rx, rz_top, _ = ring_frames[idx]
        top_pt = pos + up * (rz_top * 1.00)
        u = (idx - 54) / 34.0
        h = lerp(0.145, 0.050, u)
        add_spine(top_pt, right, up, forward, height=h, base_len=h * 0.95, base_w=lerp(0.026, 0.010, u))

    create_mesh_obj("Dragon_Dorsal_Spines", collection, root, verts, faces, mats, smooth=False)


# ---------------------------------------------------------------------------
# 2. FIERCE DRAGON HEAD, JAW, FANGS, INNER MOUTH, EYES & HORNS
# ---------------------------------------------------------------------------

def _add_tooth(verts, faces, mats, base_pos, tip_pos, radius=0.011, mat="Dragon_Horn_Ivory"):
    """Build a crisp 4-sided faceted fang/tooth from base_pos to tip_pos."""
    b = len(verts)
    axis = (tip_pos - base_pos).normalized()
    side = axis.cross(Vector((0, 1, 0)))
    if side.length < 1e-4:
        side = Vector((1, 0, 0))
    side.normalize()
    fwd = side.cross(axis).normalized()
    verts.extend([
        base_pos + side * radius,
        base_pos + fwd * radius,
        base_pos - side * radius,
        base_pos - fwd * radius,
        tip_pos,
    ])
    faces.extend([
        (b + 0, b + 1, b + 4),
        (b + 1, b + 2, b + 4),
        (b + 2, b + 3, b + 4),
        (b + 3, b + 0, b + 4),
        (b + 3, b + 2, b + 1, b + 0),
    ])
    mats.extend([mat] * 5)


def build_dragon_head(collection, root):
    """Build the faceted azure dragon head, mandible, glowing golden eyes, teeth, palate, tongue, and horns."""
    head_base = Vector((0.0, -1.04, 2.22))

    skull_sections = [
        (+0.06, -0.02, 0.155, 0.175, +0.14, -0.09),  # occiput / back of cranium
        (-0.05, +0.01, 0.180, 0.200, +0.16, -0.10),  # rear skull / temple
        (-0.18, +0.02, 0.148, 0.158, +0.15, -0.09),  # eye orbit region
        (-0.30, +0.00, 0.115, 0.130, +0.105, -0.075),# pre-orbital step / mid snout
        (-0.44, -0.01, 0.092, 0.105, +0.092, -0.068),# nasal bridge
        (-0.56, -0.01, 0.078, 0.088, +0.088, -0.062),# nostril boss swell
        (-0.66, -0.04, 0.046, 0.054, +0.042, -0.058),# hooked predatory snout tip
    ]

    rings = []
    for dy, dz, wt, wj, zt, zb in skull_sections:
        y = head_base.y + dy
        z0 = head_base.z + dz
        zm = z0 + 0.5 * (zt + zb)
        rings.append([
            Vector((0.0, y, z0 + zt * 1.06)),
            Vector((wt * 0.62, y, z0 + zt * 0.96)),
            Vector((wt * 1.12, y, z0 + zt * 0.62)),
            Vector((wj * 0.98, y, zm + 0.005)),
            Vector((wj * 0.92, y, z0 + zb)),
            Vector((0.0, y, z0 + zb - 0.012)),
            Vector((-wj * 0.92, y, z0 + zb)),
            Vector((-wj * 0.98, y, zm + 0.005)),
            Vector((-wt * 1.12, y, z0 + zt * 0.62)),
            Vector((-wt * 0.62, y, z0 + zt * 0.96)),
        ])

    def skull_mat(i, j, n, total):
        if j in (4, 5):
            return "Dragon_Deep_Azure"
        if j in (0, 9):
            return "Dragon_Bright_Azure"
        return "Dragon_Azure_Scales"

    loft_rings("Dragon_Skull", collection, root, rings, smooth=False, face_mat_fn=skull_mat)

    jaw_sections = [
        (+0.02, -0.08, 0.155, +0.01, -0.088),
        (-0.10, -0.09, 0.168, +0.01, -0.098),
        (-0.25, -0.09, 0.125, +0.01, -0.082),
        (-0.42, -0.08, 0.088, +0.01, -0.068),
        (-0.55, -0.07, 0.064, +0.005, -0.055),
        (-0.63, -0.06, 0.036, +0.00, -0.036),
    ]
    jaw_rings = []
    for dy, dz, w, zt, zb in jaw_sections:
        y = head_base.y + dy
        z0 = head_base.z + dz
        jaw_rings.append([
            Vector((0.0, y, z0 + zt)),
            Vector((w * 0.88, y, z0 + zt)),
            Vector((w, y, z0 + 0.45 * zb)),
            Vector((w * 0.72, y, z0 + zb)),
            Vector((0.0, y, z0 + zb * 1.08)),
            Vector((-w * 0.72, y, z0 + zb)),
            Vector((-w, y, z0 + 0.45 * zb)),
            Vector((-w * 0.88, y, z0 + zt)),
        ])
    loft_rings("Dragon_Mandible", collection, root, jaw_rings, default_mat="Dragon_Azure_Scales", smooth=False)

    # Inner glowing throat & palate ceiling inside the upper skull (visible when jaw opens)
    palate_rings = []
    for dy, w, z_roof, z_lip in [
        (-0.02, 0.11, 2.185, 2.095),
        (-0.16, 0.105, 2.185, 2.135),
        (-0.34, 0.082, 2.178, 2.142),
        (-0.54, 0.052, 2.172, 2.148),
    ]:
        y = head_base.y + dy
        palate_rings.append([
            Vector((0.0, y, z_roof)),
            Vector((w * 0.72, y, lerp(z_roof, z_lip, 0.35))),
            Vector((w, y, z_lip)),
            Vector((0.0, y, z_lip + 0.012)),
            Vector((-w, y, z_lip)),
            Vector((-w * 0.72, y, lerp(z_roof, z_lip, 0.35))),
        ])
    loft_rings("Dragon_Mouth_Upper", collection, root, palate_rings, default_mat="Dragon_Mouth_Inner", smooth=False)

    # Sculpted Dragon Tongue resting on the mandible floor
    tongue_rings = []
    for dy, w, z_top, z_bot in [
        (-0.06, 0.058, 2.142, 2.118),
        (-0.22, 0.052, 2.144, 2.122),
        (-0.38, 0.040, 2.148, 2.128),
        (-0.52, 0.022, 2.150, 2.136),
        (-0.58, 0.006, 2.148, 2.142),
    ]:
        y = head_base.y + dy
        tongue_rings.append([
            Vector((0.0, y, z_top)),
            Vector((w, y, 0.5 * (z_top + z_bot))),
            Vector((0.0, y, z_bot)),
            Vector((-w, y, 0.5 * (z_top + z_bot))),
        ])
    loft_rings("Dragon_Tongue", collection, root, tongue_rings, default_mat="Dragon_Tongue", smooth=False)

    # Upper & Lower Ivory Fangs (tucked neatly inside closed mouth at Rest/Walk, gleaming when roaring)
    ut_v, ut_f, ut_m = [], [], []
    lt_v, lt_f, lt_m = [], [], []
    for side in (-1.0, 1.0):
        # Prominent upper front canine fang + 3 smaller maxillary teeth
        _add_tooth(
            ut_v, ut_f, ut_m,
            Vector((side * 0.044, head_base.y - 0.54, 2.155)),
            Vector((side * 0.040, head_base.y - 0.53, 2.104)),
            radius=0.011
        )
        for dy_t, x_t, h_t in [(-0.45, 0.064, 0.032), (-0.36, 0.076, 0.030), (-0.27, 0.094, 0.028)]:
            _add_tooth(
                ut_v, ut_f, ut_m,
                Vector((side * x_t, head_base.y + dy_t, 2.150)),
                Vector((side * x_t * 0.95, head_base.y + dy_t + 0.008, 2.150 - h_t)),
                radius=0.0075
            )
        # Prominent lower front tusk + 3 smaller mandibular teeth
        _add_tooth(
            lt_v, lt_f, lt_m,
            Vector((side * 0.030, head_base.y - 0.56, 2.145)),
            Vector((side * 0.028, head_base.y - 0.555, 2.186)),
            radius=0.0095
        )
        for dy_t, x_t, h_t in [(-0.47, 0.048, 0.028), (-0.38, 0.062, 0.026), (-0.29, 0.078, 0.025)]:
            _add_tooth(
                lt_v, lt_f, lt_m,
                Vector((side * x_t, head_base.y + dy_t, 2.138)),
                Vector((side * x_t * 0.96, head_base.y + dy_t + 0.006, 2.138 + h_t)),
                radius=0.007
            )
    create_mesh_obj("Dragon_Upper_Teeth", collection, root, ut_v, ut_f, ut_m, smooth=False)
    create_mesh_obj("Dragon_Lower_Teeth", collection, root, lt_v, lt_f, lt_m, smooth=False)

    verts, faces, mats = [], [], []
    for dy_c, h_c, l_c in [(-0.52, 0.060, 0.075), (-0.36, 0.044, 0.065), (-0.21, 0.032, 0.060)]:
        b = len(verts)
        yc = head_base.y + dy_c
        zc = head_base.z + 0.082
        verts.extend([
            Vector((0.0, yc - l_c * 0.5, zc - 0.01)),
            Vector((0.018, yc, zc - 0.01)),
            Vector((0.0, yc + l_c * 0.5, zc - 0.005)),
            Vector((-0.018, yc, zc - 0.01)),
            Vector((0.0, yc + l_c * 0.35, zc + h_c)),
        ])
        faces.extend([
            (b + 0, b + 1, b + 4),
            (b + 1, b + 2, b + 4),
            (b + 2, b + 3, b + 4),
            (b + 3, b + 0, b + 4),
        ])
        mats.extend(["Dragon_Bright_Azure"] * 4)

    for side in (-1.0, 1.0):
        eb = len(verts)
        ex, ey, ez = side * 0.160, head_base.y - 0.19, head_base.z + 0.048
        verts.extend([
            Vector((ex - side * 0.005, ey - 0.045, ez - 0.008)),
            Vector((ex + side * 0.010, ey - 0.008, ez + 0.024)),
            Vector((ex + side * 0.005, ey + 0.045, ez + 0.012)),
            Vector((ex + side * 0.008, ey - 0.005, ez - 0.024)),
            Vector((ex + side * 0.024, ey - 0.005, ez + 0.002)),
        ])
        faces.extend([
            (eb + 0, eb + 1, eb + 4),
            (eb + 1, eb + 2, eb + 4),
            (eb + 2, eb + 3, eb + 4),
            (eb + 3, eb + 0, eb + 4),
        ] if side > 0 else [
            (eb + 1, eb + 0, eb + 4),
            (eb + 2, eb + 1, eb + 4),
            (eb + 3, eb + 2, eb + 4),
            (eb + 0, eb + 3, eb + 4),
        ])
        mats.extend(["Dragon_Eye_Gold"] * 4)

        pb = len(verts)
        px = ex + side * 0.025
        verts.extend([
            Vector((px, ey - 0.010, ez + 0.001)),
            Vector((px, ey - 0.005, ez + 0.016)),
            Vector((px, ey + 0.001, ez + 0.002)),
            Vector((px, ey - 0.005, ez - 0.014)),
        ])
        faces.append((pb + 0, pb + 1, pb + 2, pb + 3) if side > 0 else (pb + 3, pb + 2, pb + 1, pb + 0))
        mats.append("Dragon_Pupil")

        nb = len(verts)
        nx, ny, nz = side * 0.078, head_base.y - 0.54, head_base.z + 0.022
        verts.extend([
            Vector((nx, ny - 0.022, nz - 0.006)),
            Vector((nx + side * 0.004, ny, nz + 0.014)),
            Vector((nx + side * 0.006, ny + 0.024, nz + 0.008)),
            Vector((nx + side * 0.004, ny, nz - 0.012)),
        ])
        faces.append((nb + 0, nb + 1, nb + 2, nb + 3) if side > 0 else (nb + 3, nb + 2, nb + 1, nb + 0))
        mats.append("Dragon_Deep_Azure")

        bb = len(verts)
        verts.extend([
            Vector((side * 0.105, head_base.y - 0.29, head_base.z + 0.080)),
            Vector((side * 0.178, head_base.y - 0.27, head_base.z + 0.060)),
            Vector((side * 0.215, head_base.y - 0.07, head_base.z + 0.135)),
            Vector((side * 0.135, head_base.y - 0.06, head_base.z + 0.158)),
            Vector((side * 0.185, head_base.y - 0.17, head_base.z + 0.125)),
        ])
        if side > 0:
            faces.extend([
                (bb + 0, bb + 1, bb + 4),
                (bb + 1, bb + 2, bb + 4),
                (bb + 2, bb + 3, bb + 4),
                (bb + 3, bb + 0, bb + 4),
            ])
        else:
            faces.extend([
                (bb + 1, bb + 0, bb + 4),
                (bb + 2, bb + 1, bb + 4),
                (bb + 3, bb + 2, bb + 4),
                (bb + 0, bb + 3, bb + 4),
            ])
        mats.extend(["Dragon_Bright_Azure"] * 4)

    create_mesh_obj("Dragon_Head_Details", collection, root, verts, faces, mats, smooth=False)
    build_head_horns(collection, root, head_base)


def build_curved_horn(collection, root, name, ctrl_pts, radii, ring_sides=8, gold_split=0.28):
    """Build a faceted swept horn along ctrl_pts with golden base and ivory shaft."""
    n_steps = 18
    rings = []
    for i in range(n_steps):
        t = i / (n_steps - 1)
        pos, tan = catmull_rom(ctrl_pts, t)
        right, up, _ = frame_from_tangent(tan)
        r = lerp(radii[0], radii[1], t ** 0.78) * (1.0 - 0.85 * (t ** 3.2))
        ring = []
        for j in range(ring_sides):
            ang = tau * j / ring_sides
            flute = 1.0 + 0.08 * cos(ring_sides * 0.5 * ang)
            pt = pos + (right * cos(ang) + up * sin(ang)) * (r * flute)
            ring.append(pt)
        rings.append(ring)

    def horn_mat(i, j, n, total):
        t = i / max(1, total - 1)
        return "Dragon_Horn_Gold" if t < gold_split else "Dragon_Horn_Ivory"

    return loft_rings(name, collection, root, rings, smooth=False, face_mat_fn=horn_mat)


def build_head_horns(collection, root, head_base):
    for side in (-1.0, 1.0):
        tag = "L" if side > 0 else "R"
        main_pts = [
            head_base + Vector((side * 0.13, -0.09, 0.12)),
            head_base + Vector((side * 0.19, +0.08, 0.21)),
            head_base + Vector((side * 0.24, +0.28, 0.24)),
            head_base + Vector((side * 0.27, +0.48, 0.29)),
            head_base + Vector((side * 0.27, +0.64, 0.39)),
        ]
        build_curved_horn(collection, root, f"Dragon_Crown_Horn_{tag}", main_pts, (0.068, 0.010), ring_sides=8, gold_split=0.28)

        brow_pts = [
            head_base + Vector((side * 0.15, -0.12, 0.11)),
            head_base + Vector((side * 0.20, -0.02, 0.18)),
            head_base + Vector((side * 0.23, +0.09, 0.24)),
        ]
        build_curved_horn(collection, root, f"Dragon_Brow_Spike_{tag}", brow_pts, (0.036, 0.005), ring_sides=6, gold_split=0.35)

        sec_pts = [
            head_base + Vector((side * 0.17, -0.02, 0.05)),
            head_base + Vector((side * 0.25, +0.16, 0.10)),
            head_base + Vector((side * 0.31, +0.36, 0.15)),
        ]
        build_curved_horn(collection, root, f"Dragon_Temple_Horn_{tag}", sec_pts, (0.048, 0.008), ring_sides=6, gold_split=0.35)

        for idx, (y_off, z_off, x_out, y_back, z_up, r0) in enumerate([
            (-0.04, -0.02, 0.31, +0.22, +0.02, 0.046),
            (-0.08, -0.07, 0.29, +0.15, -0.05, 0.042),
            (-0.14, -0.11, 0.24, +0.06, -0.10, 0.034),
        ]):
            sp_pts = [
                head_base + Vector((side * 0.15, y_off, z_off)),
                head_base + Vector((side * (0.15 + 0.55 * (x_out - 0.15)), y_off + 0.55 * (y_back - y_off), z_off + 0.55 * (z_up - z_off))),
                head_base + Vector((side * x_out, y_back, z_up)),
            ]
            build_curved_horn(collection, root, f"Dragon_Cheek_Spike_{tag}_{idx}", sp_pts, (r0, 0.006), ring_sides=6, gold_split=0.45)


# ---------------------------------------------------------------------------
# 3. MUSCULAR QUADRUPEDAL LIMBS, SCALES & CLAWED FEET (Z = 0 GROUNDED)
# ---------------------------------------------------------------------------

def build_limb_tube(name, collection, parent, joints, n_sides=14):
    """Build a muscular limb from a list of (Vector_pos, rx, ry) joints."""
    n_steps = 22
    pts = [j[0] for j in joints]
    rxs = [Vector((j[1], j[2], 0.0)) for j in joints]
    rings = []
    frames = []
    for i in range(n_steps):
        t = i / (n_steps - 1)
        pos, tan = catmull_rom(pts, t)
        rad, _ = catmull_rom(rxs, t)
        up_limb = -tan
        right = Vector((1.0, 0.0, 0.0))
        fwd = right.cross(up_limb).normalized()
        right = up_limb.cross(fwd).normalized()
        frames.append((t, pos, right, fwd, up_limb, rad.x, rad.y))

        ring = []
        for j in range(n_sides):
            ang = tau * j / n_sides
            ca, sa = cos(ang), sin(ang)
            muscle = 1.0 + 0.05 * cos(3 * ang)
            pt = pos + (right * (rad.x * ca) + fwd * (rad.y * sa)) * muscle
            ring.append(pt)
        rings.append(ring)

    obj = loft_rings(name, collection, parent, rings, default_mat="Dragon_Azure_Scales", smooth=False)
    return obj, frames


def build_foot_and_talons(name, collection, parent, ankle_pos, side, is_front=True):
    """Build a heavy draconic foot planted at Z = 0 with arched toes and large curved ivory talons."""
    paw_ground = Vector((ankle_pos.x, ankle_pos.y - (0.07 if is_front else 0.09), 0.075))
    paw_rings = [
        [
            ankle_pos + Vector((cos(tau * k / 10) * 0.11, sin(tau * k / 10) * 0.125, 0.02))
            for k in range(10)
        ],
        [
            paw_ground + Vector((cos(tau * k / 10) * 0.15, sin(tau * k / 10) * 0.16, 0.0))
            for k in range(10)
        ],
        [
            Vector((paw_ground.x + cos(tau * k / 10) * 0.155, paw_ground.y + sin(tau * k / 10) * 0.165, 0.002))
            for k in range(10)
        ],
    ]
    loft_rings(f"{name}_Paw", collection, parent, paw_rings, default_mat="Dragon_Azure_Scales", smooth=False)

    if is_front:
        toe_specs = [
            (-side * 32.0, 0.20, 0.050, 0.175, 0.044),
            (-side * 10.0, 0.23, 0.054, 0.195, 0.048),
            (+side * 12.0, 0.22, 0.052, 0.190, 0.046),
            (+side * 34.0, 0.18, 0.046, 0.165, 0.040),
        ]
    else:
        toe_specs = [
            (-side * 25.0, 0.20, 0.050, 0.175, 0.044),
            (0.0,          0.23, 0.055, 0.195, 0.048),
            (+side * 25.0, 0.19, 0.048, 0.170, 0.042),
        ]

    for t_idx, (yaw_deg, t_len, t_rad, c_len, c_rad) in enumerate(toe_specs):
        yaw = radians(yaw_deg)
        dir_xy = Vector((sin(yaw), -cos(yaw), 0.0)).normalized()
        perp_xy = Vector((cos(yaw), sin(yaw), 0.0)).normalized()

        t_start = Vector((paw_ground.x, paw_ground.y, 0.08)) + dir_xy * 0.06
        t_mid = Vector((t_start.x, t_start.y, 0.105)) + dir_xy * (t_len * 0.50)
        t_end = Vector((t_start.x, t_start.y, 0.068)) + dir_xy * t_len

        toe_rings = []
        for p, rx, rz_t, rz_b in [
            (t_start, t_rad * 1.05, t_rad * 1.08, t_rad * 0.90),
            (t_mid,   t_rad * 0.98, t_rad * 1.18, t_rad * 0.95),
            (t_end,   t_rad * 0.88, t_rad * 0.95, t_rad * 0.85),
        ]:
            ring = []
            for k in range(8):
                a = tau * k / 8
                ca, sa = cos(a), sin(a)
                rz = rz_t if sa >= 0 else rz_b
                pt = p + perp_xy * (rx * ca) + Vector((0, 0, max(0.002, p.z + rz * sa) - p.z))
                ring.append(pt)
            toe_rings.append(ring)
        loft_rings(f"{name}_Toe_{t_idx}", collection, parent, toe_rings, default_mat="Dragon_Azure_Scales", smooth=False)

        claw_base = t_end - dir_xy * 0.02
        claw_arch = claw_base + dir_xy * (c_len * 0.38) + Vector((0, 0, 0.028))
        claw_lower = claw_base + dir_xy * (c_len * 0.74) + Vector((0, 0, -0.015))
        claw_tip = Vector((claw_base.x + dir_xy.x * c_len, claw_base.y + dir_xy.y * c_len, 0.002))
        claw_rings = []
        for cp, crx, crz in [
            (claw_base,  c_rad * 1.00, c_rad * 1.15),
            (claw_arch,  c_rad * 0.82, c_rad * 0.98),
            (claw_lower, c_rad * 0.46, c_rad * 0.56),
            (claw_tip,   0.005, 0.005),
        ]:
            c_ring = [
                cp + perp_xy * (crx * cos(tau * k / 6)) + Vector((0, 0, max(0.002 - cp.z, crz * sin(tau * k / 6))))
                for k in range(6)
            ]
            claw_rings.append(c_ring)
        loft_rings(
            f"{name}_Talon_{t_idx}", collection, parent, claw_rings,
            ring_mats=["Dragon_Horn_Gold", "Dragon_Horn_Ivory", "Dragon_Horn_Ivory"],
            default_mat="Dragon_Horn_Ivory", smooth=False
        )

    if not is_front:
        dew_base = ankle_pos + Vector((0.0, 0.09, 0.02))
        build_curved_horn(
            collection, parent, f"{name}_Dewclaw",
            [dew_base, dew_base + Vector((0, 0.07, -0.02)), dew_base + Vector((0, 0.12, -0.08))],
            (0.032, 0.004), ring_sides=6, gold_split=0.35
        )


def build_limbs(collection, root):
    for side in (-1.0, 1.0):
        tag = "L" if side > 0 else "R"

        fore_y_shift = -0.06 if side < 0 else +0.05
        hind_y_shift = -0.05 if side < 0 else +0.07

        fore_joints = [
            (Vector((side * 0.22, -0.54 + fore_y_shift * 0.3, 1.32)), 0.17, 0.19),
            (Vector((side * 0.42, -0.45 + fore_y_shift * 0.6, 1.06)), 0.18, 0.20),
            (Vector((side * 0.45, -0.40 + fore_y_shift * 0.8, 0.82)), 0.14, 0.155),
            (Vector((side * 0.45, -0.53 + fore_y_shift,       0.50)), 0.112, 0.125),
            (Vector((side * 0.45, -0.63 + fore_y_shift,       0.19)), 0.098, 0.110),
        ]
        _, fore_frames = build_limb_tube(f"Dragon_Foreleg_{tag}", collection, root, fore_joints)
        build_foot_and_talons(
            f"Dragon_Forefoot_{tag}", collection, root,
            Vector((side * 0.45, -0.63 + fore_y_shift, 0.18)), side, is_front=True
        )

        s_verts, s_faces, s_mats = [], [], []
        for f_idx in range(3, 11):
            t, pos, right, fwd, up_limb, rx, ry = fore_frames[f_idx]
            for k in range(6):
                ang = lerp(-0.95, 0.95, (k + 0.5 * (f_idx % 2)) / 5.5)
                nrm = (right * (side * cos(ang)) + fwd * sin(ang)).normalized()
                pt = pos + right * (side * rx * cos(ang)) + fwd * (ry * sin(ang))
                if pt.z > 1.20:
                    continue
                add_diamond_scale(
                    s_verts, s_faces, s_mats,
                    pt - nrm * 0.002, -up_limb, nrm.cross(-up_limb).normalized(), nrm,
                    length=0.088, width=0.072, thickness=0.011
                )
        create_mesh_obj(f"Dragon_Foreleg_Scales_{tag}", collection, root, s_verts, s_faces, s_mats, smooth=False)

        hind_joints = [
            (Vector((side * 0.20, +0.52 + hind_y_shift * 0.3, 1.28)), 0.18, 0.20),
            (Vector((side * 0.43, +0.36 + hind_y_shift * 0.6, 0.98)), 0.20, 0.23),
            (Vector((side * 0.47, +0.28 + hind_y_shift * 0.8, 0.76)), 0.15, 0.17),
            (Vector((side * 0.47, +0.76 + hind_y_shift,       0.48)), 0.115, 0.13),
            (Vector((side * 0.46, +0.62 + hind_y_shift,       0.18)), 0.098, 0.112),
        ]
        _, hind_frames = build_limb_tube(f"Dragon_Hindleg_{tag}", collection, root, hind_joints)
        build_foot_and_talons(
            f"Dragon_Hindfoot_{tag}", collection, root,
            Vector((side * 0.46, +0.62 + hind_y_shift, 0.18)), side, is_front=False
        )

        h_verts, h_faces, h_mats = [], [], []
        for f_idx in range(3, 11):
            t, pos, right, fwd, up_limb, rx, ry = hind_frames[f_idx]
            for k in range(6):
                ang = lerp(-0.90, 0.95, (k + 0.5 * (f_idx % 2)) / 5.5)
                nrm = (right * (side * cos(ang)) + fwd * sin(ang)).normalized()
                pt = pos + right * (side * rx * cos(ang)) + fwd * (ry * sin(ang))
                if pt.z > 0.97 and pt.y < 0.48:
                    continue
                add_diamond_scale(
                    h_verts, h_faces, h_mats,
                    pt - nrm * 0.002, -up_limb, nrm.cross(-up_limb).normalized(), nrm,
                    length=0.092, width=0.075, thickness=0.011
                )
        create_mesh_obj(f"Dragon_Hindleg_Scales_{tag}", collection, root, h_verts, h_faces, h_mats, smooth=False)

        hock_pos = Vector((side * 0.47, +0.78 + hind_y_shift, 0.48))
        build_curved_horn(
            collection, root, f"Dragon_Hock_Spur_{tag}",
            [hock_pos, hock_pos + Vector((0, 0.08, 0.05)), hock_pos + Vector((0, 0.15, 0.12))],
            (0.032, 0.005), ring_sides=6, gold_split=0.65
        )


# ---------------------------------------------------------------------------
# 4. FOLDED GROUND WINGS (SHARED LANDMARKS FOR FINGER BONES)
# ---------------------------------------------------------------------------

def wing_landmarks(side):
    """Fold the elbow back, bring the wrist forward, and stack the digits along the ribs."""
    def point(x, y, z):
        return Vector((side * x, y, z))

    shoulder = point(0.145, -0.025, 1.725)
    elbow = point(0.81, 0.065, 1.83)
    wrist = point(0.80, -0.49, 2.12)
    # The longer upper fingers ride over the shorter inner ones. Their decreasing
    # heights leave the saddle, the rider's boot and the hock visible from the side.
    fingers = [
        [wrist, point(0.99, 0.23, 1.69), point(0.91, 1.08, 1.56), point(0.41, 1.87, 1.37)],
        [wrist, point(1.045, 0.13, 1.59), point(1.13, 0.94, 1.41), point(0.88, 1.65, 1.20)],
        [wrist, point(1.05, 0.01, 1.54), point(1.15, 0.73, 1.30), point(1.04, 1.39, 1.08)],
        [wrist, point(1.025, -0.08, 1.47), point(1.15, 0.55, 1.21), point(1.15, 1.13, 1.02)],
    ]
    body_anchor = [
        shoulder, point(0.20, -0.010, 1.735), point(0.275, 0.025, 1.70), point(0.33, 0.06, 1.66)
    ]
    return shoulder, elbow, wrist, fingers, body_anchor


def build_wings(collection, root):
    for side in (-1.0, 1.0):
        tag = "L" if side > 0 else "R"
        shoulder, elbow, wrist, fingers, anchor = wing_landmarks(side)

        def spar(name, points, radius, material):
            rings = []
            for i in range(21):
                t = i / 20.0
                pos, tangent = catmull_rom(points, t)
                right, up, _ = frame_from_tangent(tangent)
                rings.append([pos + radius(t) * (right * cos(tau * k / 8) + up * sin(tau * k / 8))
                              for k in range(8)])
            loft_rings(name, collection, root, rings, face_mat_fn=material)

        spar(f"Dragon_Wing_Arm_{tag}", [shoulder, elbow, wrist],
             lambda t: lerp(0.088, 0.052, t) + 0.012 * sin(pi * t) ** 10,
             lambda *args: "Dragon_Azure_Scales")

        for index, points in enumerate(fingers, start=1):
            def finger_material(i, j, count, rings):
                if index == 1 and j in (0, 1, 6, 7):
                    return "Dragon_Bright_Azure" if i / (rings - 1) < 0.81 else "Dragon_Horn_Gold"
                return "Dragon_Azure_Scales"

            spar(f"Dragon_Wing_Finger_{tag}_{index}", points,
                 lambda t: lerp(0.038 if index == 1 else 0.027, 0.011, t), finger_material)
            tip = points[-1]
            tangent = (tip - points[-2]).normalized()
            hook = Vector((-side * 0.04, 0.01, -0.04))
            build_curved_horn(collection, root, f"Dragon_Wing_Tip_Claw_{tag}_{index}",
                              [tip - 0.035 * tangent, tip + 0.065 * tangent, tip + 0.13 * tangent + hook],
                              (0.021 if index == 1 else 0.016, 0.002), ring_sides=6, gold_split=0.45)

        # A wrist thumb curves forward and down. Its barb and the leading knuckle
        # stay in silhouette at game scale without spreading sideways like antlers.
        build_curved_horn(collection, root, f"Dragon_Wing_Thumb_Claw_{tag}",
                          [wrist + Vector((-side * 0.025, 0.03, -0.04)),
                           wrist + Vector((side * 0.02, -0.035, 0.075)),
                           wrist + Vector((side * 0.035, -0.12, 0.085)),
                           wrist + Vector((side * 0.028, -0.165, 0.025))],
                          (0.045, 0.003), ring_sides=8, gold_split=0.39)
        knuckle, _ = catmull_rom(fingers[0], 0.36)
        build_curved_horn(collection, root, f"Dragon_Wing_Edge_Spur_{tag}",
                          [knuckle, knuckle + Vector((side * 0.017, 0.045, 0.022)),
                           knuckle + Vector((side * 0.022, 0.095, 0.020))],
                          (0.022, 0.002), ring_sides=6, gold_split=0.5)

        vertices, faces, colors = [], [], []
        rows, cols = 16, 8  # Shared with the skin-binding code.
        stride = cols + 1
        for panel, (outer, inner) in enumerate(zip(fingers, fingers[1:] + [anchor])):
            outer_surface, inner_surface, shading = [], [], []
            for row in range(rows + 1):
                u = row / rows
                a, _ = catmull_rom(outer, u)
                b, _ = catmull_rom(inner, u)
                for column in range(cols + 1):
                    v = column / cols
                    valley = sin(pi * v)
                    pt = a.lerp(b, v)
                    if panel == 3:
                        # The leading edge follows the folded wristâ€“elbowâ€“shoulder
                        # bend rather than bridging it with a triangle of loose skin.
                        support, _ = catmull_rom([wrist, elbow, shoulder], v)
                        pt += (support - wrist.lerp(shoulder, v)) * (1.0 - smoothstep(0, 0.55, u))
                        pt.x += side * 0.275 * valley * smoothstep(0.12, 0.82, u)
                        pt.y -= 0.24 * valley * smoothstep(0.12, 0.82, u)
                    # Collapsed membrane folds follow the parallel fingers, with
                    # shallow scallops drawn forward between their tapered claws.
                    pt.x -= side * (0.048 if panel < 3 else 0.030) * valley * sin(pi * u)
                    pt.y -= (0.17 if panel < 3 else 0.105) * valley * u ** 2
                    pt.z += 0.040 * valley * u ** 2
                    thickness = Vector((side * 0.0035, 0.0, 0.0))
                    outer_surface.append(pt + thickness)
                    inner_surface.append(pt - thickness)
                    light = (0.48 + 0.52 * u) * (1.0 - 0.43 * valley)
                    shading.append((lerp(0.012, 0.057, light), lerp(0.084, 0.326, light),
                                    lerp(0.35, 0.755, light), 1.0))
            front = len(vertices)
            vertices.extend(outer_surface)
            back = len(vertices)
            vertices.extend(inner_surface)
            colors.extend(shading + shading)
            for row in range(rows):
                for column in range(cols):
                    i = row * stride + column
                    quad = [i, i + 1, i + stride + 1, i + stride]
                    if row == 0 and panel < 3:
                        quad = [i, i + stride + 1, i + stride]
                    faces.append(tuple(front + k for k in quad))
                    faces.append(tuple(back + k for k in reversed(quad)))
            for column in range(cols):
                i = rows * stride + column
                faces.append((front + i, back + i, back + i + 1, front + i + 1))

        web = create_mesh_obj(f"Dragon_Wing_Membrane_{tag}", collection, root, vertices, faces,
                              default_mat="Dragon_Wing_Membrane")
        gradient = web.data.color_attributes.new(name="WingGradient", type="FLOAT_COLOR", domain="POINT")
        for vertex, color in zip(gradient.data, colors):
            vertex.color = color
        web.data.color_attributes.active_color_index = 0


# ---------------------------------------------------------------------------
# 5. ARTHURIAN BARDING ARMOR, HERALDIC SHIELDS, WAR-SADDLE & GREAVES
# ---------------------------------------------------------------------------

def add_thick_plate(verts, faces, mats, grid_pts, thickness=0.024,
                    mat_face="Ivory_Armor", mat_rim="Heraldic_Brass", mat_back="Recessed_Steel",
                    outward_ref=Vector((0.0, 0.0, 1.25)), border_rows=(0, -1), border_cols=(0, -1)):
    """Extrude a 2D grid of 3D surface points outward away from outward_ref, with guaranteed outward face normals."""
    rows = len(grid_pts)
    cols = len(grid_pts[0])
    normals = [[Vector((0, -1, 0)) for _ in range(cols)] for _ in range(rows)]

    mid_r, mid_c = rows // 2, cols // 2
    p_mid = grid_pts[mid_r][mid_c]
    pr_mid = grid_pts[min(rows - 1, mid_r + 1)][mid_c] - grid_pts[max(0, mid_r - 1)][mid_c]
    pc_mid = grid_pts[mid_r][min(cols - 1, mid_c + 1)] - grid_pts[mid_r][max(0, mid_c - 1)]
    n_test = pc_mid.cross(pr_mid)
    out_dir = p_mid - outward_ref
    if n_test.dot(out_dir) < 0:
        grid_pts = [list(reversed(row)) for row in grid_pts]

    for r in range(rows):
        for c in range(cols):
            p = grid_pts[r][c]
            pr = grid_pts[min(rows - 1, r + 1)][c] - grid_pts[max(0, r - 1)][c]
            pc = grid_pts[r][min(cols - 1, c + 1)] - grid_pts[r][max(0, c - 1)]
            n = pc.cross(pr)
            if n.length < 1e-6:
                n = (p - outward_ref)
            if n.dot(p - outward_ref) < 0:
                n = -n
            normals[r][c] = n.normalized()

    base_in = len(verts)
    for r in range(rows):
        for c in range(cols):
            verts.append(grid_pts[r][c])
    base_out = len(verts)
    for r in range(rows):
        for c in range(cols):
            verts.append(grid_pts[r][c] + normals[r][c] * thickness)

    def idx_in(r, c):
        return base_in + r * cols + c

    def idx_out(r, c):
        return base_out + r * cols + c

    b_rows = {(rows - 2 + br + 1) if br < 0 else br for br in border_rows}
    b_cols = {(cols - 2 + bc + 1) if bc < 0 else bc for bc in border_cols}

    for r in range(rows - 1):
        for c in range(cols - 1):
            is_border = (r in b_rows) or (c in b_cols)
            m = mat_rim if is_border else mat_face
            faces.append((idx_out(r, c), idx_out(r, c + 1), idx_out(r + 1, c + 1), idx_out(r + 1, c)))
            mats.append(m)
            faces.append((idx_in(r + 1, c), idx_in(r + 1, c + 1), idx_in(r, c + 1), idx_in(r, c)))
            mats.append(mat_back)

    for c in range(cols - 1):
        faces.append((idx_in(0, c), idx_in(0, c + 1), idx_out(0, c + 1), idx_out(0, c)))
        mats.append(mat_rim)
        faces.append((idx_out(rows - 1, c), idx_out(rows - 1, c + 1), idx_in(rows - 1, c + 1), idx_in(rows - 1, c)))
        mats.append(mat_rim)
    for r in range(rows - 1):
        faces.append((idx_out(r, 0), idx_out(r + 1, 0), idx_in(r + 1, 0), idx_in(r, 0)))
        mats.append(mat_rim)
        faces.append((idx_in(r, cols - 1), idx_in(r + 1, cols - 1), idx_out(r + 1, cols - 1), idx_out(r, cols - 1)))
        mats.append(mat_rim)


def add_arthurian_emblem(verts, faces, mats, center, right_vec, up_vec, out_vec, scale=1.0):
    """Build the 3D relief Arthurian 8-pointed compass star and vertical downward sword."""
    star_center = center + up_vec * (0.068 * scale)
    n_pts = 16
    outline = []
    for i in range(n_pts):
        ang = tau * i / n_pts
        if i % 4 == 0:
            r = 0.064 * scale
        elif i % 2 == 0:
            r = 0.043 * scale
        else:
            r = 0.016 * scale
        outline.append(star_center + right_vec * (sin(ang) * r) + up_vec * (cos(ang) * r))

    b = len(verts)
    for pt in outline:
        verts.append(pt)
    for pt in outline:
        verts.append(pt + out_vec * (0.011 * scale))
    verts.append(star_center + out_vec * (0.016 * scale))
    apex_idx = b + 2 * n_pts
    for i in range(n_pts):
        ni = (i + 1) % n_pts
        faces.append((b + i, b + ni, b + n_pts + ni, b + n_pts + i))
        mats.append("Heraldic_Brass")
        faces.append((b + n_pts + i, b + n_pts + ni, apex_idx))
        mats.append("Heraldic_Brass")

    sword_poly = [
        (0.0, +0.022),
        (+0.008, +0.014),
        (+0.032, +0.012),
        (+0.030, +0.001),
        (+0.011, +0.001),
        (+0.008, -0.105),
        (0.0, -0.142),
        (-0.008, -0.105),
        (-0.011, +0.001),
        (-0.030, +0.001),
        (-0.032, +0.012),
        (-0.008, +0.014),
    ]
    sb = len(verts)
    sn = len(sword_poly)
    for sx, sz in sword_poly:
        verts.append(center + right_vec * (sx * scale) + up_vec * (sz * scale))
    for sx, sz in sword_poly:
        verts.append(center + right_vec * (sx * scale) + up_vec * (sz * scale) + out_vec * (0.010 * scale))
    faces.append(tuple(range(sb + sn, sb + 2 * sn)))
    mats.append("Heraldic_Brass")
    for i in range(sn):
        ni = (i + 1) % sn
        faces.append((sb + i, sb + ni, sb + sn + ni, sb + sn + i))
        mats.append("Heraldic_Brass")


def build_chest_barding_and_shield(collection, root):
    """Build the peytral chest barding, separate L/R shoulder pauldrons, and front heraldic shield."""
    verts, faces, mats = [], [], []
    chest_core = Vector((0.0, -0.50, 1.26))

    for tier, (z_top, z_bot, y_front, r_width, y_wrap, drop) in enumerate([
        (1.58, 1.28, -1.03, 0.47, 0.44, 0.20),
        (1.30, 1.05, -0.97, 0.47, 0.46, 0.16),
        (1.07, 0.87, -0.86, 0.43, 0.44, 0.13),
    ]):
        rows_pts = []
        n_rows, n_cols = 7, 17
        for r in range(n_rows):
            v = r / (n_rows - 1)
            row = []
            for c in range(n_cols):
                u = -1.0 + 2.0 * c / (n_cols - 1)
                x = u * r_width * lerp(0.96, 1.04, v)
                y = y_front + (u * u) * y_wrap + v * 0.08 + tier * 0.018
                z = lerp(z_top, z_bot, v) - drop * (1.0 - abs(u)) ** 1.4
                row.append(Vector((x, y, z)))
            rows_pts.append(row)
        b_rows = (0,) if tier == 0 else ()
        add_thick_plate(
            verts, faces, mats, rows_pts, thickness=0.028,
            mat_face="Ivory_Armor", mat_rim="Heraldic_Brass" if tier == 0 else "Ivory_Armor",
            outward_ref=chest_core, border_rows=b_rows, border_cols=(0, -1)
        )

    create_mesh_obj("Dragon_Chest_Barding", collection, root, verts, faces, mats, smooth=False)

    # Separate L and R shoulder pauldron armor wings for clean pauldron.{L/R} bone weighting
    for side in (-1.0, 1.0):
        tag = "L" if side > 0 else "R"
        pv, pf, pm = [], [], []
        p_grid = []
        n_r, n_c = 7, 11
        for r in range(n_r):
            v = r / (n_r - 1)
            row = []
            for c in range(n_c):
                u = c / (n_c - 1)
                ang = lerp(0.24, 1.32, v)
                x = side * (0.22 + 0.34 * sin(ang) + 0.03 * sin(pi * u))
                y = lerp(-0.68, -0.22, u) - 0.04 * (1.0 - v)
                z = lerp(1.56, 1.23, v) - 0.03 * (u - 0.35) ** 2
                row.append(Vector((x, y, z)))
            p_grid.append(row)
        add_thick_plate(
            pv, pf, pm, p_grid, thickness=0.026,
            mat_face="Ivory_Armor", mat_rim="Heraldic_Brass",
            outward_ref=Vector((0.0, -0.46, 1.28))
        )
        create_mesh_obj(f"Dragon_Shoulder_Barding_{tag}", collection, root, pv, pf, pm, smooth=False)

    # Front Heraldic Escutcheon (Heater Shield)
    s_verts, s_faces, s_mats = [], [], []
    sh_center = Vector((0.0, -1.07, 1.25))
    sh_right = Vector((1.0, 0.0, 0.0))
    sh_up = Vector((0.0, -0.20, 0.98)).normalized()
    sh_out = sh_right.cross(sh_up).normalized()

    shield_outline = [
        (0.0, +0.21),
        (+0.11, +0.17),
        (+0.20, +0.20),
        (+0.19, +0.02),
        (+0.15, -0.12),
        (+0.08, -0.21),
        (0.0, -0.28),
        (-0.08, -0.21),
        (-0.15, -0.12),
        (-0.19, +0.02),
        (-0.20, +0.20),
        (-0.11, +0.17),
    ]
    n_sh = len(shield_outline)

    def sh_pt(lx, lz, scale_xy=1.0, depth_out=0.0):
        crease = -0.025 * abs(lx)
        return sh_center + sh_right * (lx * scale_xy) + sh_up * (lz * scale_xy) + sh_out * (depth_out + crease)

    ring_back = [sh_pt(x, z, 1.00, 0.000) for x, z in shield_outline]
    ring_rim_out = [sh_pt(x, z, 1.00, 0.032) for x, z in shield_outline]
    ring_rim_in = [sh_pt(x, z, 0.83, 0.034) for x, z in shield_outline]
    ring_field = [sh_pt(x, z, 0.81, 0.024) for x, z in shield_outline]
    center_field = sh_pt(0.0, -0.02, 1.0, 0.030)

    s_verts.extend(ring_back + ring_rim_out + ring_rim_in + ring_field + [center_field])
    c_idx = 4 * n_sh
    for i in range(n_sh):
        ni = (i + 1) % n_sh
        s_faces.append((i, ni, n_sh + ni, n_sh + i))
        s_mats.append("Heraldic_Brass")
        s_faces.append((n_sh + i, n_sh + ni, 2 * n_sh + ni, 2 * n_sh + i))
        s_mats.append("Heraldic_Brass")
        s_faces.append((2 * n_sh + i, 2 * n_sh + ni, 3 * n_sh + ni, 3 * n_sh + i))
        s_mats.append("Heraldic_Brass")
        s_faces.append((3 * n_sh + i, 3 * n_sh + ni, c_idx))
        s_mats.append("team_color")

    add_arthurian_emblem(
        s_verts, s_faces, s_mats,
        sh_center + sh_out * 0.027,
        sh_right, sh_up, sh_out, scale=1.12
    )
    create_mesh_obj("Dragon_Chest_Shield", collection, root, s_verts, s_faces, s_mats, smooth=False)


def build_war_saddle_and_flank_tassets(collection, root):
    """Build contoured war-saddle, saddle skirt, crupper plates (separate tiers), L/R flank shields, and tack."""
    sk_v, sk_f, sk_m = [], [], []
    for side in (-1.0, 1.0):
        g = []
        for r in range(7):
            v = r / 6.0
            row = []
            for c in range(9):
                u = c / 8.0
                ang = lerp(0.18, 1.22, v)
                x = side * 0.44 * sin(ang)
                y = lerp(-0.22, +0.34, u)
                z = 1.43 + 0.34 * cos(ang) - 0.03 * sin(pi * u)
                row.append(Vector((x, y, z)))
            g.append(row)
        add_thick_plate(
            sk_v, sk_f, sk_m, g, thickness=0.024,
            mat_face="Ivory_Armor", mat_rim="Heraldic_Brass",
            outward_ref=Vector((0.0, 0.06, 1.32))
        )
    create_mesh_obj("Dragon_Saddle_Skirt", collection, root, sk_v, sk_f, sk_m, smooth=False)

    seat_rings = []
    for y, w, z_base, arch_h in [
        (-0.22, 0.16, 1.74, 0.15),
        (-0.14, 0.21, 1.73, 0.11),
        (-0.02, 0.24, 1.71, 0.04),
        (+0.12, 0.25, 1.72, 0.06),
        (+0.24, 0.24, 1.75, 0.17),
        (+0.31, 0.20, 1.75, 0.18),
    ]:
        ring = []
        for k in range(12):
            a = tau * k / 12
            ca, sa = cos(a), sin(a)
            bolster = 0.035 * (ca ** 2) if sa > 0 else 0.0
            pt = Vector((w * ca, y, z_base + (arch_h if sa > 0 else 0.04) * sa + bolster))
            ring.append(pt)
        seat_rings.append(ring)
    loft_rings(
        "Dragon_War_Saddle_Seat", collection, root, seat_rings,
        ring_mats=["Harness_Leather", "Saddle_Leather_Dark", "Saddle_Leather_Dark", "Harness_Leather", "Harness_Leather"],
        default_mat="Harness_Leather", smooth=False
    )

    # Crupper Tail-Base Armor separated per tier for clean spine/tail articulation
    for tier, (t_start, t_end, w_scale) in enumerate([
        (0.45, 0.51, 1.04),
        (0.50, 0.56, 1.02),
        (0.55, 0.61, 1.00),
    ]):
        cv, cf, cm = [], [], []
        c_grid = []
        for r in range(5):
            v = r / 4.0
            t_sp = lerp(t_start, t_end, v)
            pos, tan, rx, rz_top, _ = eval_spine(t_sp)
            right, up, _ = frame_from_tangent(tan)
            row = []
            for c in range(9):
                u = -1.0 + 2.0 * c / 8.0
                ang = u * 0.92
                pt = (
                    pos
                    + right * ((rx + 0.022 + tier * 0.004) * w_scale * sin(ang))
                    + up * ((rz_top + 0.024 + tier * 0.004) * cos(ang))
                )
                row.append(pt)
            c_grid.append(row)
        add_thick_plate(cv, cf, cm, c_grid, thickness=0.020, outward_ref=Vector((0.0, 0.65, 1.10)))
        create_mesh_obj(f"Dragon_Crupper_Plate_{tier}", collection, root, cv, cf, cm, smooth=False)

    # Separate L and R Heraldic Flank Tassets
    for side in (-1.0, 1.0):
        tag = "L" if side > 0 else "R"
        t_verts, t_faces, t_mats = [], [], []
        tc = Vector((side * 0.51, +0.26, 1.28))
        t_up = Vector((-side * 0.28, +0.16, 0.94)).normalized()
        t_out = Vector((side * 0.94, -0.10, 0.30)).normalized()
        t_right = t_up.cross(t_out).normalized()

        tasset_outline = [
            (0.0, +0.24),
            (+0.18, +0.21),
            (+0.22, +0.03),
            (+0.16, -0.16),
            (0.0, -0.32),
            (-0.16, -0.16),
            (-0.22, +0.03),
            (-0.18, +0.21),
        ]
        nt = len(tasset_outline)

        def t_pt(lx, lz, sc=1.0, dout=0.0):
            curve = -0.02 * (lx * lx / 0.05)
            return tc + t_right * (lx * sc) + t_up * (lz * sc) + t_out * (dout + curve)

        r_back = [t_pt(x, z, 1.08, 0.000) for x, z in tasset_outline]
        r_ivory = [t_pt(x, z, 1.08, 0.020) for x, z in tasset_outline]
        r_brass_out = [t_pt(x, z, 0.94, 0.026) for x, z in tasset_outline]
        r_brass_in = [t_pt(x, z, 0.81, 0.028) for x, z in tasset_outline]
        r_blue = [t_pt(x, z, 0.79, 0.022) for x, z in tasset_outline]
        c_blue = t_pt(0.0, -0.02, 1.0, 0.026)

        t_verts.extend(r_back + r_ivory + r_brass_out + r_brass_in + r_blue + [c_blue])
        ci = 5 * nt
        for i in range(nt):
            ni = (i + 1) % nt
            t_faces.append((i, ni, nt + ni, nt + i))
            t_mats.append("Ivory_Armor")
            t_faces.append((nt + i, nt + ni, 2 * nt + ni, 2 * nt + i))
            t_mats.append("Ivory_Armor")
            t_faces.append((2 * nt + i, 2 * nt + ni, 3 * nt + ni, 3 * nt + i))
            t_mats.append("Heraldic_Brass")
            t_faces.append((3 * nt + i, 3 * nt + ni, 4 * nt + ni, 4 * nt + i))
            t_mats.append("Heraldic_Brass")
            t_faces.append((4 * nt + i, 4 * nt + ni, ci))
            t_mats.append("team_color")

        add_arthurian_emblem(
            t_verts, t_faces, t_mats,
            tc + t_out * 0.025,
            t_right, t_up, t_out, scale=1.05
        )
        create_mesh_obj(f"Dragon_Flank_Tasset_{tag}", collection, root, t_verts, t_faces, t_mats, smooth=False)

    build_leather_tack_and_buckles(collection, root)


def add_strap_strip(verts, faces, mats, path_pts, width=0.055, thickness=0.014, mat="Harness_Leather"):
    """Build a 3D leather strap along path_pts."""
    n_steps = 18
    grid = []
    for i in range(n_steps):
        t = i / (n_steps - 1)
        pos, tan = catmull_rom(path_pts, t)
        nrm = (pos - Vector((0.0, pos.y, 1.32)))
        if nrm.length < 1e-4:
            nrm = Vector((0, 0, 1))
        nrm.normalize()
        side_v = tan.cross(nrm).normalized()
        grid.append([pos - side_v * (width * 0.5), pos + side_v * (width * 0.5)])
    add_thick_plate(
        verts, faces, mats, grid, thickness=thickness,
        mat_face=mat, mat_rim=mat, mat_back=mat,
        outward_ref=Vector((0.0, 0.0, 1.30))
    )


def add_brass_buckle(verts, faces, mats, center, normal, strap_dir, width=0.078, length=0.092, thickness=0.018):
    """Build a 3D rectangular brass buckle frame."""
    nrm = normal.normalized()
    t_dir = (strap_dir - nrm * strap_dir.dot(nrm)).normalized()
    s_dir = t_dir.cross(nrm).normalized()

    outer = [(-width * 0.5, -length * 0.5), (width * 0.5, -length * 0.5), (width * 0.5, length * 0.5), (-width * 0.5, length * 0.5)]
    inner = [(-width * 0.28, -length * 0.28), (width * 0.28, -length * 0.28), (width * 0.28, length * 0.28), (-width * 0.28, length * 0.28)]
    b = len(verts)
    for z_off in (0.0, thickness):
        for x, y in outer:
            verts.append(center + s_dir * x + t_dir * y + nrm * z_off)
        for x, y in inner:
            verts.append(center + s_dir * x + t_dir * y + nrm * z_off)
    for i in range(4):
        ni = (i + 1) % 4
        faces.append((b + 8 + i, b + 8 + ni, b + 12 + ni, b + 12 + i))
        mats.append("Heraldic_Brass")
        faces.append((b + i, b + ni, b + 8 + ni, b + 8 + i))
        mats.append("Heraldic_Brass")
        faces.append((b + 12 + i, b + 12 + ni, b + 4 + ni, b + 4 + i))
        mats.append("Heraldic_Brass")


def build_leather_tack_and_buckles(collection, root):
    gv, gf, gm = [], [], []
    rv, rf, rm = [], [], []

    for side in (-1.0, 1.0):
        tag = "L" if side > 0 else "R"
        sv, sf, sm = [], [], []
        sh_strap = [
            Vector((side * 0.44, -0.78, 1.38)),
            Vector((side * 0.56, -0.58, 1.40)),
            Vector((side * 0.55, -0.38, 1.43)),
        ]
        add_strap_strip(sv, sf, sm, sh_strap, width=0.068, thickness=0.016)
        add_brass_buckle(
            sv, sf, sm,
            Vector((side * 0.56, -0.58, 1.40)),
            Vector((side * 0.92, -0.32, 0.22)),
            Vector((0.0, 0.98, 0.12)),
            width=0.088, length=0.105
        )
        create_mesh_obj(f"Dragon_Shoulder_Strap_{tag}", collection, root, sv, sf, sm, smooth=False)

        for y_off, z_buckle in [(-0.14, 1.20), (-0.02, 1.17)]:
            girth_strap = [
                Vector((side * 0.39, y_off, 1.36)),
                Vector((side * 0.42, y_off, 1.20)),
                Vector((side * 0.28, y_off, 1.09)),
                Vector((0.0,         y_off, 1.07)),
            ]
            add_strap_strip(gv, gf, gm, girth_strap, width=0.056, thickness=0.014)
            add_brass_buckle(
                gv, gf, gm,
                Vector((side * 0.43, y_off, z_buckle)),
                Vector((side * 0.95, 0.0, -0.15)),
                Vector((0.0, 0.0, -1.0)),
                width=0.076, length=0.088
            )

        rein_pts = [
            Vector((side * 0.16, -0.96, 2.02)),
            Vector((side * 0.28, -0.68, 1.72)),
            Vector((side * 0.30, -0.42, 1.66)),
            Vector((side * 0.16, -0.22, 1.78)),
        ]
        add_strap_strip(rv, rf, rm, rein_pts, width=0.040, thickness=0.012)

    create_mesh_obj("Dragon_Girth_Straps", collection, root, gv, gf, gm, smooth=False)
    create_mesh_obj("Dragon_Reins", collection, root, rv, rf, rm, smooth=False)


def build_leg_greaves(collection, root):
    """Build separate L/R foreleg and hindleg greaves for rigid lower-limb weighting."""
    for side in (-1.0, 1.0):
        tag = "L" if side > 0 else "R"
        fore_y_shift = -0.06 if side < 0 else +0.05
        hind_y_shift = -0.05 if side < 0 else +0.07

        fv, ff, fm = [], [], []
        f_top = Vector((side * 0.45, -0.42 + fore_y_shift * 0.85, 0.84))
        f_bot = Vector((side * 0.45, -0.63 + fore_y_shift,        0.20))
        f_grid = []
        n_r, n_c = 8, 9
        for r in range(n_r):
            v = r / (n_r - 1)
            p_axis = f_top.lerp(f_bot, v)
            rad = lerp(0.142, 0.105, v)
            row = []
            for c in range(n_c):
                u = -1.0 + 2.0 * c / (n_c - 1)
                ang = radians(-95.0 + side * (-20.0 + u * 105.0))
                ridge = 1.14 if abs(u) < 0.14 else 1.0
                wing_lift = 0.15 * (1.0 - v) ** 1.5 * max(0.0, 1.0 - abs(u - 0.35) * 1.6)
                wing_flare = 0.04 * (1.0 - v) ** 1.5 * max(0.0, u)
                ankle_dip = -0.03 * (v ** 2) * max(0.0, 1.0 - abs(u) * 1.5)
                x = p_axis.x + cos(ang) * (rad * ridge + wing_flare)
                y = p_axis.y + sin(ang) * (rad * ridge + wing_flare)
                z = p_axis.z + wing_lift + ankle_dip
                row.append(Vector((x, y, z)))
            f_grid.append(row)
        add_thick_plate(
            fv, ff, fm, f_grid, thickness=0.018,
            outward_ref=f_top.lerp(f_bot, 0.5),
            border_rows=(0, -1), border_cols=(0, -1)
        )
        for v_s in (0.30, 0.75):
            p_s = f_top.lerp(f_bot, v_s)
            r_s = lerp(0.14, 0.105, v_s)
            s_pts = [
                p_s + Vector((cos(radians(-95 + side * k)) * r_s, sin(radians(-95 + side * k)) * r_s, 0.0))
                for k in range(-95, 195, 45)
            ]
            add_strap_strip(fv, ff, fm, s_pts, width=0.038, thickness=0.010)
        create_mesh_obj(f"Dragon_Foreleg_Greave_{tag}", collection, root, fv, ff, fm, smooth=False)

        hv, hf, hm = [], [], []
        h_top = Vector((side * 0.47, +0.74 + hind_y_shift, 0.48))
        h_bot = Vector((side * 0.46, +0.62 + hind_y_shift, 0.19))
        h_grid = []
        for r in range(6):
            v = r / 5.0
            p_axis = h_top.lerp(h_bot, v)
            rad = lerp(0.122, 0.104, v)
            row = []
            for c in range(9):
                u = -1.0 + 2.0 * c / 8.0
                ang = radians(-90.0 + side * (-15.0 + u * 105.0))
                ridge = 1.12 if abs(u) < 0.15 else 1.0
                hock_flare = 0.08 * (1.0 - v) ** 1.5 * max(0.0, 1.0 - abs(u - 0.35) * 1.6)
                x = p_axis.x + cos(ang) * rad * ridge
                y = p_axis.y + sin(ang) * rad * ridge
                z = p_axis.z + hock_flare
                row.append(Vector((x, y, z)))
            h_grid.append(row)
        add_thick_plate(
            hv, hf, hm, h_grid, thickness=0.016,
            outward_ref=h_top.lerp(h_bot, 0.5),
            border_rows=(0, -1), border_cols=(0, -1)
        )
        create_mesh_obj(f"Dragon_Hindleg_Greave_{tag}", collection, root, hv, hf, hm, smooth=False)


# ---------------------------------------------------------------------------
# 6. LONG-CONE AOE FIRE BREATH GEOMETRY & DYNAMIC PLUMES
# ---------------------------------------------------------------------------

def map_breath_surface(mesh, length, plume=False):
    """Give the game material longitudinal and circumferential coordinates in bind pose."""
    uv = mesh.uv_layers.new(name="BreathFlow")
    ys = [v.co.y for v in mesh.vertices]
    near = max(ys) if plume else MUZZLE_POS.y
    span = max(ys) - min(ys) if plume else length
    for face in mesh.polygons:
        loops = tuple(face.loop_indices)
        points = [mesh.vertices[mesh.loops[i].vertex_index].co for i in loops]
        angles = [(atan2(p.z - MUZZLE_POS.z, p.x - MUZZLE_POS.x) / tau) % 1.0 for p in points]
        crosses_seam = max(angles) - min(angles) > 0.55
        for index, point, angle in zip(loops, points, angles):
            if crosses_seam and angle < 0.5:
                angle += 1.0
            uv.data[index].uv = (clamp((near - point.y) / span), angle)


def _build_flame_cone(name, collection, root, length, r_start, r_end, rz_ratio, n_rings, n_sides,
                      ridge_count, ridge_amp, twist_rate, mat_name, with_vcol=False):
    """Build a stylized faceted conical dragonfire blast extending along -Y from MUZZLE_POS."""
    rings = []
    vcols = []
    for i in range(n_rings):
        t = i / (n_rings - 1)
        y = MUZZLE_POS.y - t * length
        # Slightly curved expansion flare so the cone accelerates outward cleanly
        spread = lerp(r_start, r_end, t ** 0.88)
        # Taper tip slightly at the very last ring so jagged flame tongues look sculpted rather than blunt
        tip_taper = 1.0 - 0.18 * smoothstep(0.86, 1.0, t)
        rx = spread * tip_taper
        rz = rx * lerp(1.0, rz_ratio, smoothstep(0.15, 0.85, t))

        # Subtle undulating flame billow along length
        billow_z = 0.03 * sin(t * pi * 3.0) * (1.0 - 0.5 * t)
        ring = []
        for j in range(n_sides):
            ang = tau * j / n_sides
            tongue = 1.0 + ridge_amp * cos(ridge_count * ang + twist_rate * t) * smoothstep(0.05, 0.35, t)
            # Jagged forward flame spikes at the outer front rim
            y_spike = -0.28 * length * 0.14 * max(0.0, cos(ridge_count * ang + twist_rate)) * smoothstep(0.82, 1.0, t)
            pt = Vector((
                rx * tongue * cos(ang),
                y + y_spike,
                MUZZLE_POS.z + billow_z + rz * tongue * sin(ang),
            ))
            ring.append(pt)
            if with_vcol:
                if t < 0.28:
                    u = t / 0.28
                    col = (1.0, lerp(0.70, 0.34, u), lerp(0.18, 0.02, u), 1.0)
                elif t < 0.70:
                    u = (t - 0.28) / 0.42
                    col = (lerp(1.0, 0.92, u), lerp(0.34, 0.12, u), lerp(0.02, 0.008, u), 1.0)
                else:
                    u = (t - 0.70) / 0.30
                    col = (lerp(0.92, 0.52, u), lerp(0.12, 0.025, u), lerp(0.008, 0.002, u), 1.0)
                vcols.append(col)
        rings.append(ring)

    # Front nose vertex closing the cone with jagged flame apex
    verts = [v for r in rings for v in r]
    tip_pt = Vector((0.0, MUZZLE_POS.y - length * 1.03, MUZZLE_POS.z))
    verts.append(tip_pt)
    if with_vcol:
        vcols.append((0.52, 0.04, 0.005, 1.0))

    faces = []
    for i in range(n_rings - 1):
        for j in range(n_sides):
            nj = (j + 1) % n_sides
            faces.append((i * n_sides + j, i * n_sides + nj, (i + 1) * n_sides + nj, (i + 1) * n_sides + j))
    # Cap start inside throat and close jagged front tip
    faces.append(tuple(reversed(range(n_sides))))
    last = (n_rings - 1) * n_sides
    tip_idx = len(verts) - 1
    for j in range(n_sides):
        nj = (j + 1) % n_sides
        faces.append((last + j, last + nj, tip_idx))

    obj = create_mesh_obj(name, collection, root, verts, faces, [mat_name] * len(faces), default_mat=mat_name, smooth=False)
    map_breath_surface(obj.data, length)
    if with_vcol:
        attr = obj.data.color_attributes.new(name="FireGradient", type="FLOAT_COLOR", domain="POINT")
        for idx_v, rgba in enumerate(vcols):
            attr.data[idx_v].color = rgba
        obj.data.color_attributes.active_color_index = 0
    return obj


def build_fire_breath_fx(collection, rig):
    """Create the layered long-cone AOE fire geometry, streaming flame plumes, and mouth light."""
    _build_flame_cone(
        "Dragon_Fire_Cone_Core", collection, rig,
        length=5.20, r_start=0.075, r_end=0.52, rz_ratio=0.86,
        n_rings=18, n_sides=12, ridge_count=6, ridge_amp=0.16, twist_rate=4.2,
        mat_name="Dragon_Fire_Core", with_vcol=False
    )
    _build_flame_cone(
        "Dragon_Fire_Cone_Mid", collection, rig,
        length=6.80, r_start=0.115, r_end=1.10, rz_ratio=0.76,
        n_rings=22, n_sides=14, ridge_count=7, ridge_amp=0.18, twist_rate=-5.2,
        mat_name="Dragon_Fire_Mid", with_vcol=False
    )
    _build_flame_cone(
        "Dragon_Fire_Cone_Outer", collection, rig,
        length=BREATH_LENGTH, r_start=0.15, r_end=1.65, rz_ratio=0.66,
        n_rings=26, n_sides=16, ridge_count=8, ridge_amp=0.20, twist_rate=6.0,
        mat_name="Dragon_Fire_Outer", with_vcol=True
    )

    # 6 streaming flame plumes centered around breath_plume_k head so bone translation drives them cleanly
    for k in range(6):
        bm = bmesh.new()
        bmesh.ops.create_icosphere(bm, subdivisions=1, radius=0.28)
        rot_k = k * 0.95
        for v in bm.verts:
            # Stretch along -Y and add jagged flame-billow irregularity
            n_val = 1.0 + 0.28 * sin(v.co.x * 9.0 + rot_k) * cos(v.co.z * 9.0 - rot_k)
            v.co = Vector((
                MUZZLE_POS.x + v.co.x * 0.95 * n_val,
                MUZZLE_POS.y - 0.16 + v.co.y * 1.45 * n_val,
                MUZZLE_POS.z + v.co.z * 0.78 * n_val,
            ))
        for f in bm.faces:
            f.smooth = False
        mesh = bpy.data.meshes.new(f"Dragon_Fire_Plume_{k}")
        bm.to_mesh(mesh)
        bm.free()
        mesh.materials.append(bpy.data.materials["Dragon_Fire_Plume"])
        map_breath_surface(mesh, 1.0, plume=True)
        plume_obj = bpy.data.objects.new(f"Dragon_Fire_Plume_{k}", mesh)
        collection.objects.link(plume_obj)
        plume_obj.parent = rig

    # Dynamic firelight attached to breath_origin
    light_data = bpy.data.lights.new("Breath_Light", "POINT")
    light_data.color = (1.0, 0.50, 0.12)
    light_data.energy = 0.0
    light_data.shadow_soft_size = 0.35
    light_obj = bpy.data.objects.new("Breath_Light", light_data)
    collection.objects.link(light_obj)
    light_obj.parent = rig
    light_obj.parent_type = "BONE"
    light_obj.parent_bone = "breath_origin"
    bpy.context.view_layer.update()
    light_obj.matrix_world.translation = MUZZLE_POS + Vector((0.0, -0.55, 0.0))


# ---------------------------------------------------------------------------
# 7. ARMATURE RIG & RIDER MOUNT SOCKET
# ---------------------------------------------------------------------------

def build_armature(collection):
    """Create Azure_Dragon_Rig with full spine, limbs, articulated wings, jaw, Rider_Mount, and breath cone bones."""
    arm_data = bpy.data.armatures.new("Azure_Dragon_Rig")
    arm_obj = bpy.data.objects.new("Azure_Dragon_Rig", arm_data)
    collection.objects.link(arm_obj)
    bpy.context.view_layer.objects.active = arm_obj
    bpy.ops.object.mode_set(mode="EDIT")
    eb = arm_data.edit_bones

    def add_bone(name, head, tail, parent=None, connect=False, up_ref=(0, 0, 1)):
        b = eb.new(name)
        b.head = Vector(head)
        b.tail = Vector(tail)
        if parent is not None:
            b.parent = parent
            b.use_connect = connect
        aim = (b.tail - b.head).normalized()
        ref = Vector(up_ref)
        if abs(aim.dot(ref)) > 0.96:
            ref = Vector((0, -1, 0))
        b.align_roll(ref)
        return b

    b_root = add_bone("root", (0, 0, 0), (0, -0.35, 0), up_ref=(0, 0, 1))
    b_pelvis = add_bone("pelvis", (0, 0.48, 1.34), (0, 0.12, 1.40), b_root)
    b_spine1 = add_bone("spine.01", (0, 0.12, 1.40), (0, -0.26, 1.38), b_pelvis, True)
    b_chest = add_bone("chest", (0, -0.26, 1.38), (0, -0.72, 1.32), b_spine1, True)
    b_neck1 = add_bone("neck.01", (0, -0.72, 1.32), (0, -0.95, 1.66), b_chest, True, up_ref=(0, -1, 0))
    b_neck2 = add_bone("neck.02", (0, -0.95, 1.66), (0, -1.04, 2.20), b_neck1, True, up_ref=(0, -1, 0))
    b_head = add_bone("head", (0, -1.04, 2.20), (0, -1.65, 2.18), b_neck2, True)
    add_bone("jaw", (0, -1.03, 2.14), (0, -1.64, 2.11), b_head)

    add_bone("Rider_Mount", (0, -0.02, 1.71), (0, -0.02, 2.11), b_spine1, up_ref=(0, -1, 0))

    # Fire-breath cone bone hierarchy under head
    b_muzzle = add_bone("breath_muzzle", MUZZLE_POS, MUZZLE_POS + Vector((0, -0.30, 0)), b_head)
    b_origin = add_bone("breath_origin", MUZZLE_POS, MUZZLE_POS + Vector((0, -0.20, 0)), b_muzzle)
    seg_len = BREATH_LENGTH / 4.0
    b_seg_parent = b_origin
    for s_idx in range(4):
        p0 = MUZZLE_POS + Vector((0, -s_idx * seg_len, 0))
        p1 = MUZZLE_POS + Vector((0, -(s_idx + 1) * seg_len, 0))
        b_seg_parent = add_bone(f"breath_seg_{s_idx}", p0, p1, b_seg_parent, connect=(s_idx > 0))
    for k in range(6):
        add_bone(f"breath_plume_{k}", MUZZLE_POS, MUZZLE_POS + Vector((0, -0.40, 0)), b_origin)

    # Tail chain
    # Keep the skin, the caudal plates and the five caudal joints on one spine.
    t_pts = [SPINE_CONTROLS[i][:3] for i in (8, 10, 12, 13, 15, 16)]
    t_parent = b_pelvis
    for idx in range(len(t_pts) - 1):
        t_parent = add_bone(f"tail.0{idx + 1}", t_pts[idx], t_pts[idx + 1], t_parent, idx > 0)

    # Limbs, armor followers & articulated wing fingers
    for side in (-1.0, 1.0):
        tag = "L" if side > 0 else "R"
        fy = -0.06 if side < 0 else +0.05
        hy = -0.05 if side < 0 else +0.07

        sh_pos = (side * 0.34, -0.50 + fy * 0.3, 1.24)
        el_pos = (side * 0.45, -0.40 + fy * 0.8, 0.82)
        wr_pos = (side * 0.45, -0.63 + fy, 0.18)
        ft_pos = (side * 0.45, -0.85 + fy, 0.02)

        f_up = add_bone(f"fore_upper.{tag}", sh_pos, el_pos, b_chest, up_ref=(0, -1, 0))
        f_lo = add_bone(f"fore_lower.{tag}", el_pos, wr_pos, f_up, True, up_ref=(0, -1, 0))
        add_bone(f"fore_foot.{tag}", wr_pos, ft_pos, f_lo, True, up_ref=(0, 0, 1))
        add_bone(f"pauldron.{tag}", sh_pos, el_pos, b_chest, up_ref=(0, -1, 0))

        hp_pos = (side * 0.30, 0.52 + hy * 0.3, 1.24)
        kn_pos = (side * 0.47, 0.28 + hy * 0.8, 0.76)
        hk_pos = (side * 0.47, 0.76 + hy, 0.48)
        ak_pos = (side * 0.46, 0.62 + hy, 0.18)
        hf_pos = (side * 0.46, 0.40 + hy, 0.02)

        h_up = add_bone(f"hind_thigh.{tag}", hp_pos, kn_pos, b_pelvis, up_ref=(0, -1, 0))
        h_mid = add_bone(f"hind_shin.{tag}", kn_pos, hk_pos, h_up, True, up_ref=(0, -1, 0))
        h_lo = add_bone(f"hind_ankle.{tag}", hk_pos, ak_pos, h_mid, True, up_ref=(0, -1, 0))
        add_bone(f"hind_foot.{tag}", ak_pos, hf_pos, h_lo, True, up_ref=(0, 0, 1))
        add_bone(f"flank_tasset.{tag}", hp_pos, kn_pos, b_pelvis, up_ref=(0, -1, 0))

        w_root, w_elbow, w_wrist, fingers, _ = wing_landmarks(side)
        w_arm = add_bone(f"wing_arm.{tag}", w_root, w_elbow, b_chest)
        w_fore = add_bone(f"wing_forearm.{tag}", w_elbow, w_wrist, w_arm, True)
        for f_idx, f_pts in enumerate(fingers, start=1):
            add_bone(f"wing_finger_{f_idx}.{tag}", w_wrist, f_pts[-1], w_fore)

    bpy.ops.object.mode_set(mode="OBJECT")
    arm_obj.show_in_front = True
    arm_obj.data.display_type = "STICK"
    return arm_obj


def build_all():
    import rig_dragon
    import animate_dragon
    import export_dragon

    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.unit_settings.system = "METRIC"
    scene.unit_settings.scale_length = 1.0
    scene.render.fps = 24
    scene.render.fps_base = 1.0
    try:
        scene.view_settings.view_transform = "AgX"
        scene.view_settings.look = "AgX - Medium High Contrast"
    except Exception:
        pass

    create_palette()

    col = bpy.data.collections.new("azure_dragon")
    scene.collection.children.link(col)

    rig = build_armature(col)

    build_body_and_tail(col, rig)
    build_dragon_head(col, rig)
    build_limbs(col, rig)
    build_wings(col, rig)
    build_chest_barding_and_shield(col, rig)
    build_war_saddle_and_flank_tassets(col, rig)
    build_leg_greaves(col, rig)
    build_fire_breath_fx(col, rig)

    mount_empty = bpy.data.objects.new("Rider_Mount_Socket", None)
    mount_empty.empty_display_type = "ARROWS"
    mount_empty.empty_display_size = 0.25
    col.objects.link(mount_empty)
    mount_empty.parent = rig
    mount_empty.parent_type = "BONE"
    mount_empty.parent_bone = "Rider_Mount"
    bpy.context.view_layer.update()
    mount_empty.matrix_world.translation = Vector((0.0, -0.02, 1.71))

    rig_dragon.bind_all_meshes(col, rig)
    animate_dragon.build_all_animations(rig)
    import mounted_knight
    mounted_knight.install(col, rig, PACKAGE.parent / "ArthurianMarines" / "export" / "round_table_marine.glb")
    scene.frame_set(1)
    bpy.ops.object.select_all(action="DESELECT")
    rig.select_set(True)
    bpy.context.view_layer.objects.active = rig
    for screen in bpy.data.screens:
        for area in screen.areas:
            if area.type == "VIEW_3D":
                space = area.spaces.active
                space.shading.color_type = "MATERIAL"
                space.overlay.show_overlays = False
                space.region_3d.view_perspective = "ORTHO"
                space.region_3d.view_location = Vector((0.0, 0.60, 1.5))
                space.region_3d.view_distance = 7.5
                space.region_3d.view_rotation = Vector((-4.7, 5.1, -2.0)).to_track_quat("-Z", "Y")

    HERE.mkdir(parents=True, exist_ok=True)
    EXPORT_PATH.parent.mkdir(parents=True, exist_ok=True)
    bpy.context.preferences.filepaths.save_version = 0
    bpy.ops.wm.save_as_mainfile(filepath=str(BLEND_PATH), compress=True)

    export_dragon.export_glb(col, rig, EXPORT_PATH)
    print(f"Saved {BLEND_PATH} and exported {EXPORT_PATH}")


if __name__ == "__main__":
    build_all()
