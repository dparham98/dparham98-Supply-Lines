"""Builds Blender/Vehicles/AirBalloon/AirBalloon.blend procedurally.

Run in headless Blender 4.5:
  blender --background --python build_balloon.py

Conventions:
- Forward Prow: -Y in Blender (-Z in Godot via 180-deg Y Rig rotation in air_balloon_model.tscn)
- Gondola skids grounded at Z = 0, Z up, world metres
- Docking Ring & Skids strictly inside Keep balloon_pad clamp circle (R <= 1.25 m vs Keep clamps at R=1.34 m)
- 4 individual `crate_slot_1..4` children under `gondola_hull` for future visual cargo loading
- Flat PBR materials only; `team_color` & `team_color_shadow` match scripts/components/team_paint.gd
"""

from __future__ import annotations

import os
from math import cos, pi, radians, sin

import bmesh
import bpy
from mathutils import Matrix, Vector as V

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.normpath(os.path.join(HERE, "..", "AirBalloon.blend"))

X = V((1.0, 0.0, 0.0))
Y = V((0.0, 1.0, 0.0))
Z = V((0.0, 0.0, 1.0))

MATERIAL_SPECS = {
    "Ivory_Armor":        ((0.83, 0.82, 0.73), 0.35, 0.43, None, 0.0),
    "Satin_Silver":       ((0.69, 0.72, 0.73), 0.55, 0.40, None, 0.0),
    "Recessed_Steel":     ((0.25, 0.29, 0.32), 0.65, 0.43, None, 0.0),
    "Heraldic_Brass":     ((0.71, 0.44, 0.12), 0.65, 0.37, None, 0.0),
    "team_color":         ((0.025, 0.075, 0.38), 0.08, 0.64, None, 0.0),
    "team_color_shadow":  ((0.013, 0.033, 0.18), 0.04, 0.70, None, 0.0),
    "Harness_Leather":    ((0.044, 0.034, 0.027), 0.00, 0.64, None, 0.0),
    "Sack_Cloth":         ((0.34, 0.28, 0.20), 0.00, 0.85, None, 0.0),
    "Visor_Amber":        ((1.00, 0.69, 0.29), 0.14, 0.20, (1.0, 0.65, 0.22), 2.5),
    "Keep_Interior_Dark": ((0.022, 0.025, 0.030), 0.10, 0.85, None, 0.0),
    "Timber_Oak":         ((0.26, 0.16, 0.085), 0.00, 0.78, None, 0.0),
}


def build_materials() -> dict[str, bpy.types.Material]:
    mats: dict[str, bpy.types.Material] = {}
    for name, (col, met, rough, emis, strength) in MATERIAL_SPECS.items():
        mat = bpy.data.materials.new(name)
        mat.use_nodes = True
        bsdf = next(n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
        bsdf.inputs["Base Color"].default_value = (*col, 1.0)
        bsdf.inputs["Metallic"].default_value = met
        bsdf.inputs["Roughness"].default_value = rough
        if emis is not None and strength > 0.0:
            bsdf.inputs["Emission Color"].default_value = (*emis, 1.0)
            bsdf.inputs["Emission Strength"].default_value = strength
        mat.diffuse_color = (*col, 1.0)
        mats[name] = mat
    return mats


class PartBuilder:
    def __init__(self, name: str, origin: tuple[float, float, float] = (0.0, 0.0, 0.0)):
        self.name = name
        self.origin = V(origin)
        self.bm = bmesh.new()
        self.face_mats: list[str] = []

    def _to_local(self, p) -> V:
        return V(p) - self.origin

    def _append_bm(self, sub_bm: bmesh.types.BMesh, mat_name: str, recalc: bool = True) -> None:
        if recalc and len(sub_bm.faces) > 0:
            bmesh.ops.recalc_face_normals(sub_bm, faces=sub_bm.faces[:])
        vert_map = {v: self.bm.verts.new(self._to_local(v.co)) for v in sub_bm.verts}
        for f in sub_bm.faces:
            try:
                nf = self.bm.faces.new([vert_map[v] for v in f.verts])
                nf.smooth = False
                self.face_mats.append(mat_name)
            except ValueError:
                pass
        sub_bm.free()

    def add_box(self, center, size, mat: str, rot: Matrix | None = None, bevel: float = 0.0) -> None:
        sub = bmesh.new()
        xf = Matrix.Translation(V(center)) @ (rot if rot else Matrix.Identity(4)) @ Matrix.Diagonal((*V(size), 1.0))
        bmesh.ops.create_cube(sub, size=1.0, matrix=xf)
        if bevel > 0.0:
            bmesh.ops.bevel(sub, geom=sub.edges[:], offset=bevel, segments=1, profile=0.5, affect="EDGES")
        self._append_bm(sub, mat)

    def add_span(self, x0: float, x1: float, y0: float, y1: float, z0: float, z1: float, mat: str, bevel: float = 0.0) -> None:
        self.add_box(
            ((x0 + x1) * 0.5, (y0 + y1) * 0.5, (z0 + z1) * 0.5),
            (abs(x1 - x0), abs(y1 - y0), abs(z1 - z0)),
            mat,
            bevel=bevel,
        )

    def add_cyl(self, p0, p1, r0: float, r1: float | None = None, seg: int = 8, mat: str = "Recessed_Steel", cap: bool = True, twist_rad: float = 0.0) -> None:
        p0, p1 = V(p0), V(p1)
        r1 = r0 if r1 is None else r1
        d = p1 - p0
        if d.length < 1e-6:
            return
        sub = bmesh.new()
        track = d.to_track_quat("Z", "Y").to_matrix().to_4x4()
        xf = Matrix.Translation((p0 + p1) * 0.5) @ track @ Matrix.Rotation(twist_rad, 4, "Z")
        bmesh.ops.create_cone(sub, cap_ends=cap, cap_tris=False, segments=seg, radius1=max(r0, 1e-4), radius2=max(r1, 1e-4), depth=d.length, matrix=xf)
        self._append_bm(sub, mat)

    def add_sphere(self, center, r: float, mat: str, scale=(1.0, 1.0, 1.0), sub: int = 1) -> None:
        bm = bmesh.new()
        xf = Matrix.Translation(V(center)) @ Matrix.Diagonal((*scale, 1.0))
        bmesh.ops.create_icosphere(bm, subdivisions=sub, radius=r, matrix=xf)
        self._append_bm(bm, mat)

    def add_prism(self, poly_xy: list[tuple[float, float]], z0: float, z1: float, mat: str) -> None:
        sub = bmesh.new()
        n = len(poly_xy)
        bot = [sub.verts.new(V((x, y, z0))) for x, y in poly_xy]
        top = [sub.verts.new(V((x, y, z1))) for x, y in poly_xy]
        sub.faces.new(list(reversed(bot)))
        sub.faces.new(top)
        for i in range(n):
            j = (i + 1) % n
            sub.faces.new((bot[i], bot[j], top[j], top[i]))
        self._append_bm(sub, mat, recalc=True)

    def add_extruded_poly_frame(self, poly_uv, origin: V, right: V, up: V, outward: V, d0: float, d1: float, mat: str) -> None:
        sub = bmesh.new()
        n = len(poly_uv)
        r0 = [sub.verts.new(origin + right * u + up * v + outward * d0) for u, v in poly_uv]
        r1 = [sub.verts.new(origin + right * u + up * v + outward * d1) for u, v in poly_uv]
        sub.faces.new(list(reversed(r0)))
        sub.faces.new(r1)
        for i in range(n):
            j = (i + 1) % n
            sub.faces.new((r0[i], r0[j], r1[j], r1[i]))
        self._append_bm(sub, mat, recalc=True)

    def build(self, collection: bpy.types.Collection, parent: bpy.types.Object, mats: dict[str, bpy.types.Material]) -> bpy.types.Object:
        me = bpy.data.meshes.new(self.name)
        mat_order: list[str] = []
        mat_idx: dict[str, int] = {}
        for mname in self.face_mats:
            if mname not in mat_idx:
                mat_idx[mname] = len(mat_order)
                mat_order.append(mname)
                me.materials.append(mats[mname])

        self.bm.faces.ensure_lookup_table()
        for fc, mname in zip(self.bm.faces, self.face_mats):
            fc.material_index = mat_idx[mname]
            fc.smooth = False

        self.bm.to_mesh(me)
        self.bm.free()

        bpy.context.view_layer.update()
        parent_world = parent.matrix_world.translation.copy()
        obj = bpy.data.objects.new(self.name, me)
        collection.objects.link(obj)
        obj.parent = parent
        obj.location = self.origin - parent_world
        return obj


def add_starburst_and_sword(
    pb: PartBuilder,
    center: V,
    outward: V,
    up_hint: V,
    scale: float,
    star_mat: str = "Heraldic_Brass",
    sword_mat: str = "Satin_Silver",
) -> None:
    out = outward.normalized()
    right = up_hint.cross(out)
    if right.length < 1e-4:
        right = X.cross(out)
    right.normalize()
    up = out.cross(right).normalized()

    star_pts = []
    for k in range(16):
        ang = k * (pi / 8.0)
        r = (0.145 if (k % 4 == 0) else 0.112) * scale if k % 2 == 0 else 0.036 * scale
        star_pts.append((sin(ang) * r, cos(ang) * r))
    pb.add_extruded_poly_frame(star_pts, center, right, up, out, 0.0, 0.018 * scale, star_mat)

    blade_pts = [
        (-0.015 * scale, -0.055 * scale),
        ( 0.015 * scale, -0.055 * scale),
        ( 0.011 * scale,  0.140 * scale),
        ( 0.000 * scale,  0.175 * scale),
        (-0.011 * scale,  0.140 * scale),
    ]
    pb.add_extruded_poly_frame(blade_pts, center, right, up, out, 0.014 * scale, 0.032 * scale, sword_mat)
    guard_pts = [
        (-0.058 * scale, -0.068 * scale),
        ( 0.058 * scale, -0.068 * scale),
        ( 0.050 * scale, -0.044 * scale),
        (-0.050 * scale, -0.044 * scale),
    ]
    pb.add_extruded_poly_frame(guard_pts, center, right, up, out, 0.012 * scale, 0.036 * scale, sword_mat)
    grip_pts = [
        (-0.011 * scale, -0.145 * scale),
        ( 0.011 * scale, -0.145 * scale),
        ( 0.011 * scale, -0.066 * scale),
        (-0.011 * scale, -0.066 * scale),
    ]
    pb.add_extruded_poly_frame(grip_pts, center, right, up, out, 0.014 * scale, 0.030 * scale, sword_mat)
    pommel_pts = [
        (-0.022 * scale, -0.168 * scale),
        ( 0.000 * scale, -0.182 * scale),
        ( 0.022 * scale, -0.168 * scale),
        ( 0.016 * scale, -0.142 * scale),
        (-0.016 * scale, -0.142 * scale),
    ]
    pb.add_extruded_poly_frame(pommel_pts, center, right, up, out, 0.014 * scale, 0.034 * scale, sword_mat)


def oct_pts(cx: float, cy: float, r: float, rot_deg: float = 22.5) -> list[tuple[float, float]]:
    return [(cx + r * cos(radians(rot_deg + 45.0 * k)), cy + r * sin(radians(rot_deg + 45.0 * k))) for k in range(8)]


# ---------------------------------------------------------------------------
# 1. Ribbed Arthurian Dirigible Envelope & Steering Rudder
# ---------------------------------------------------------------------------


def build_envelope(col, airframe, mats) -> tuple[bpy.types.Object, bpy.types.Object]:
    eh = PartBuilder("envelope_hull", (0.0, 0.0, 3.70))

    # Build faceted 12-gore ribbed dirigible-teardrop hull (Z = 2.08..5.35, -Y slightly nose-heavy)
    n_gores = 12
    # Vertical rings: (z, rx, ry_front, ry_back, puff_amp)
    rings = [
        (2.08, 0.62, 0.64, 0.66, 0.02),
        (2.42, 0.94, 0.98, 1.04, 0.04),
        (2.88, 1.32, 1.38, 1.52, 0.055),
        (3.40, 1.54, 1.62, 1.82, 0.065),
        (3.92, 1.56, 1.64, 1.84, 0.065),
        (4.44, 1.38, 1.44, 1.60, 0.055),
        (4.88, 1.02, 1.06, 1.18, 0.04),
        (5.20, 0.56, 0.58, 0.64, 0.02),
        (5.36, 0.24, 0.24, 0.26, 0.00),
    ]

    # Build 24 circumferential segments (2 per gore: ridge + mid-puff) for crisp puffed gores
    n_seg = n_gores * 2
    sub = bmesh.new()
    ring_verts: list[list] = []
    for rz, rx, ryf, ryb, puff in rings:
        row = []
        for s in range(n_seg):
            ang = 2.0 * pi * s / n_seg
            is_ridge = (s % 2 == 0)
            p_mul = 1.0 if is_ridge else (1.0 + puff)
            ca, sa = cos(ang), sin(ang)
            ry = ryf if sa <= 0.0 else ryb
            x = ca * rx * p_mul
            y = sa * ry * p_mul + 0.06  # slight stern balance
            row.append(sub.verts.new(eh._to_local((x, y, rz))))
        ring_verts.append(row)

    # Side quads alternating per gore: Ivory_Armor vs team_color (with lower collar team_color_shadow)
    vert_map = {v: eh.bm.verts.new(v.co) for row in ring_verts for v in row}
    for r in range(len(rings) - 1):
        for s in range(n_seg):
            s2 = (s + 1) % n_seg
            v00 = vert_map[ring_verts[r][s]]
            v01 = vert_map[ring_verts[r][s2]]
            v11 = vert_map[ring_verts[r + 1][s2]]
            v10 = vert_map[ring_verts[r + 1][s]]
            try:
                nf = eh.bm.faces.new((v00, v01, v11, v10))
                nf.smooth = False
                gore_idx = s // 2
                if r == 0:
                    mat = "team_color_shadow"
                elif gore_idx % 2 == 0:
                    mat = "Ivory_Armor"
                else:
                    mat = "team_color"
                eh.face_mats.append(mat)
            except ValueError:
                pass

    # Underside dark burner cavity cap + top dome cap
    bot_center = eh.bm.verts.new(eh._to_local((0.0, 0.06, 2.22)))
    for s in range(n_seg):
        s2 = (s + 1) % n_seg
        v0 = vert_map[ring_verts[0][s]]
        v1 = vert_map[ring_verts[0][s2]]
        nf = eh.bm.faces.new((v1, v0, bot_center))
        nf.smooth = False
        eh.face_mats.append("Keep_Interior_Dark")
    top_center = eh.bm.verts.new(eh._to_local((0.0, 0.06, 5.38)))
    for s in range(n_seg):
        s2 = (s + 1) % n_seg
        v0 = vert_map[ring_verts[-1][s]]
        v1 = vert_map[ring_verts[-1][s2]]
        nf = eh.bm.faces.new((v0, v1, top_center))
        nf.smooth = False
        eh.face_mats.append("Satin_Silver")
    sub.free()

    # Equatorial brass belt wrapping seamlessly along the exact 24-point oval gore perimeter (Z = 3.58..3.76)
    belt_b, belt_t = [], []
    belt_z0, belt_z1 = 3.58, 3.76
    belt_rx, belt_ryf, belt_ryb = 1.56, 1.64, 1.84
    for s in range(n_seg):
        ang = 2.0 * pi * s / n_seg
        p_mul = 1.018 if (s % 2 == 0) else 1.084
        ca, sa = cos(ang), sin(ang)
        ry = belt_ryf if sa <= 0.0 else belt_ryb
        bx = ca * belt_rx * p_mul
        by = sa * ry * p_mul + 0.06
        belt_b.append(V((bx, by, belt_z0)))
        belt_t.append(V((bx, by, belt_z1)))
    # Connect oval belt quad strip with proud upper/lower brass bevel thickness
    belt_in_b = [V((p.x * 0.96, (p.y - 0.06) * 0.96 + 0.06, belt_z0)) for p in belt_b]
    belt_in_t = [V((p.x * 0.96, (p.y - 0.06) * 0.96 + 0.06, belt_z1)) for p in belt_t]
    sub_b = bmesh.new()
    vb_o = [sub_b.verts.new(p) for p in belt_b]
    vt_o = [sub_b.verts.new(p) for p in belt_t]
    vb_i = [sub_b.verts.new(p) for p in belt_in_b]
    vt_i = [sub_b.verts.new(p) for p in belt_in_t]
    for s in range(n_seg):
        s2 = (s + 1) % n_seg
        sub_b.faces.new((vb_o[s], vb_o[s2], vt_o[s2], vt_o[s]))
        sub_b.faces.new((vt_o[s], vt_o[s2], vt_i[s2], vt_i[s]))
        sub_b.faces.new((vb_i[s], vb_i[s2], vb_o[s2], vb_o[s]))
    eh._append_bm(sub_b, "Heraldic_Brass", recalc=True)

    # Lower burner throat brass collar ring
    eh.add_cyl((0.0, 0.06, 2.06), (0.0, 0.06, 2.16), 0.68, 0.70, seg=12, mat="Heraldic_Brass")

    # 6 brass meridian ribs arching cleanly from collar to crown
    for g in range(0, n_gores, 2):
        ang = 2.0 * pi * g / n_gores
        ca, sa = cos(ang), sin(ang)
        pts = []
        for rz, rx, ryf, ryb, _ in rings:
            ry = ryf if sa <= 0.0 else ryb
            pts.append(V((ca * (rx + 0.03), sa * (ry + 0.03) + 0.06, rz)))
        for k in range(len(pts) - 1):
            eh.add_cyl(pts[k], pts[k + 1], 0.028, 0.028, seg=6, mat="Heraldic_Brass")

    # Top relief valve turret + brass crown spirelet (apex Z ~ 5.56 m)
    eh.add_cyl((0.0, 0.06, 5.28), (0.0, 0.06, 5.44), 0.34, 0.28, seg=8, mat="Satin_Silver")
    eh.add_cyl((0.0, 0.06, 5.44), (0.0, 0.06, 5.58), 0.14, 0.02, seg=8, mat="Heraldic_Brass")

    # Forward Bow Prow Figurehead Fin (-Y nose) + Side Heraldic Starbursts mounted cleanly proud on equator
    eh.add_extruded_poly_frame(
        [(0.0, -0.35), (0.34, 0.0), (0.28, 0.34), (0.0, 0.18)],
        V((0.0, -1.62, 3.66)),
        -Y,
        Z,
        X,
        -0.04,
        0.04,
        "Heraldic_Brass",
    )
    add_starburst_and_sword(eh, V((-1.71, 0.06, 3.68)), -X, Z, scale=1.55, star_mat="Heraldic_Brass", sword_mat="Satin_Silver")
    add_starburst_and_sword(eh, V(( 1.71, 0.06, 3.68)),  X, Z, scale=1.55, star_mat="Heraldic_Brass", sword_mat="Satin_Silver")

    eh_obj = eh.build(col, airframe, mats)

    # Rear Tail Steering Rudder (`rudder_fin`, child of `envelope_hull`), pivoted at stern hinge (0, 1.88, 3.68)
    rd = PartBuilder("rudder_fin", (0.0, 1.88, 3.68))
    # Vertical rudder fin framed in brass with royal-blue cloth sail projecting to Y = +2.56
    rd.add_extruded_poly_frame(
        [(0.0, -0.44), (0.58, -0.22), (0.64, 0.42), (0.0, 0.62)],
        V((0.0, 1.86, 3.68)),
        Y,
        Z,
        X,
        -0.028,
        0.028,
        "team_color",
    )
    rd.add_cyl((0.0, 1.86, 3.24), (0.0, 2.44, 3.46), 0.04, 0.035, seg=6, mat="Heraldic_Brass")
    rd.add_cyl((0.0, 1.86, 4.30), (0.0, 2.50, 4.10), 0.04, 0.035, seg=6, mat="Heraldic_Brass")
    rd.add_cyl((0.0, 2.44, 3.46), (0.0, 2.50, 4.10), 0.038, 0.038, seg=6, mat="Heraldic_Brass")
    # Small horizontal tailplane stabilizers for clear top-down directional arrow!
    for sx in (-1.0, 1.0):
        rd.add_extruded_poly_frame(
            [(0.0, -0.22), (0.62 * sx, 0.08), (0.56 * sx, 0.34), (0.0, 0.24)],
            V((0.0, 1.88, 3.68)),
            X,
            Y,
            Z,
            -0.022,
            0.022,
            "team_color_shadow",
        )
    rd_obj = rd.build(col, eh_obj, mats)

    return eh_obj, rd_obj


# ---------------------------------------------------------------------------
# 2. Burner Basket & Rigging Lines
# ---------------------------------------------------------------------------


def build_burner(col, airframe, mats) -> tuple[bpy.types.Object, bpy.types.Object]:
    br = PartBuilder("burner_rig", (0.0, 0.0, 1.82))

    # Central brass burner ring & dual fuel tanks suspended cleanly at Z = 1.65..1.98
    br.add_cyl((0.0, 0.0, 1.72), (0.0, 0.0, 1.94), 0.28, 0.34, seg=8, mat="Heraldic_Brass")
    br.add_cyl((0.0, 0.0, 1.68), (0.0, 0.0, 1.78), 0.36, 0.36, seg=8, mat="Recessed_Steel")
    for sx in (-1.0, 1.0):
        br.add_cyl((sx * 0.28, 0.0, 1.48), (sx * 0.28, 0.0, 1.80), 0.09, 0.09, seg=8, mat="Satin_Silver")

    # 4 sturdy vertical struts from gondola corners up to burner platform + 8 shroud cables up to equator
    gond_corners = [(-0.76, -0.78), (0.76, -0.78), (0.76, 0.76), (-0.76, 0.76)]
    ring_corners = [(-0.40, -0.40), (0.40, -0.40), (0.40, 0.40), (-0.40, 0.40)]
    for (gx, gy), (rx, ry) in zip(gond_corners, ring_corners):
        br.add_cyl((gx, gy, 0.78), (rx, ry, 1.78), 0.032, 0.026, seg=6, mat="Recessed_Steel")

    for k in range(8):
        ang = radians(22.5 + 45.0 * k)
        ca, sa = cos(ang), sin(ang)
        ex = ca * 1.62
        ey = sa * (1.68 if sa < 0 else 1.84) + 0.06
        cx, cy = gond_corners[k // 2]
        br.add_cyl((cx, cy, 0.78), (ex, ey, 3.60), 0.016, 0.016, seg=5, mat="Harness_Leather")

    br_obj = br.build(col, airframe, mats)

    # Glowing burner flame cone (`burner_flame`, child of `burner_rig`)
    bf = PartBuilder("burner_flame", (0.0, 0.0, 1.92))
    bf.add_cyl((0.0, 0.0, 1.90), (0.0, 0.0, 2.38), 0.21, 0.04, seg=8, mat="Visor_Amber")
    bf.add_sphere((0.0, 0.0, 1.98), 0.17, "Visor_Amber", scale=(1.0, 1.0, 1.2), sub=1)
    bf_obj = bf.build(col, br_obj, mats)

    return br_obj, bf_obj


# ---------------------------------------------------------------------------
# 3. Armored Freight Gondola, Keep-Pad Docking Ring, 4 Crate Bays & Props
# ---------------------------------------------------------------------------


def build_gondola(col, airframe, mats) -> tuple[bpy.types.Object, list[bpy.types.Object], list[bpy.types.Object]]:
    gd = PartBuilder("gondola_hull", (0.0, 0.0, 0.56))

    # Docking Ring & Landing Skids strictly inside Keep balloon_pad clamps (hinged at R=1.34 m)
    # Two compact skids along X = +-0.62 (Y in [-0.80, +0.80], tips +-0.88 -> corner radius = 1.10 m < 1.34 m!)
    for sx in (-1.0, 1.0):
        gd.add_span(sx * 0.62 - 0.07, sx * 0.62 + 0.07, -0.80, 0.80, 0.00, 0.11, "Recessed_Steel", bevel=0.015)
        gd.add_cyl((sx * 0.62, -0.80, 0.06), (sx * 0.62, -0.88, 0.18), 0.055, 0.042, seg=6, mat="Heraldic_Brass")
        gd.add_cyl((sx * 0.62,  0.80, 0.06), (sx * 0.62,  0.88, 0.16), 0.055, 0.042, seg=6, mat="Heraldic_Brass")

    # Octagonal docking collar + 4 diagonal mooring lugs at 45/135/225/315 deg
    gd.add_prism(oct_pts(0.0, 0.0, 0.82, 22.5), 0.08, 0.25, "Recessed_Steel")
    for deg in (45.0, 135.0, 225.0, 315.0):
        a = radians(deg)
        lx, ly = cos(a) * 0.88, sin(a) * 0.88
        rot = Matrix.Rotation(a, 4, "Z")
        gd.add_box((lx, ly, 0.16), (0.22, 0.16, 0.11), "Heraldic_Brass", rot=rot, bevel=0.01)

    # Freight Deck (Timber_Oak planks framed in Ivory_Armor + Steel bulwarks, Z = 0.26..0.76 cleanly above clamps)
    gd.add_span(-0.78, 0.78, -0.86, 0.84, 0.24, 0.32, "Timber_Oak", bevel=0.01)
    # Armored outer bulwark waist rails (Z = 0.26..0.76)
    gd.add_span(-0.82, 0.82, -0.90, -0.80, 0.26, 0.76, "Ivory_Armor", bevel=0.02)
    gd.add_span(-0.82, 0.82,  0.76,  0.86, 0.26, 0.76, "Ivory_Armor", bevel=0.02)
    gd.add_span(-0.82, -0.70, -0.86, 0.82, 0.26, 0.76, "Ivory_Armor", bevel=0.02)
    gd.add_span( 0.70,  0.82, -0.86, 0.82, 0.26, 0.76, "Ivory_Armor", bevel=0.02)
    # Top gunwale brass & steel rail trim
    gd.add_span(-0.85, 0.85, -0.93, -0.79, 0.72, 0.80, "Heraldic_Brass")
    gd.add_span(-0.85, 0.85,  0.75,  0.89, 0.72, 0.80, "Heraldic_Brass")
    gd.add_span(-0.85, -0.69, -0.89, 0.85, 0.72, 0.80, "Heraldic_Brass")
    gd.add_span( 0.69,  0.85, -0.89, 0.85, 0.72, 0.80, "Heraldic_Brass")

    # Side Heraldic team_color shield plates on Port/Starboard flanks + Forward Brass Prow Ram (-Y)
    for sx in (-1.0, 1.0):
        gd.add_box((sx * 0.83, 0.0, 0.51), (0.05, 0.92, 0.34), "team_color", bevel=0.01)
        gd.add_box((sx * 0.86, 0.0, 0.51), (0.03, 0.26, 0.20), "Heraldic_Brass")
    # Forward pointed bow ram & amber navigation lamp at -Y
    gd.add_cyl((0.0, -0.88, 0.52), (0.0, -1.18, 0.60), 0.20, 0.04, seg=6, mat="Heraldic_Brass")
    gd.add_sphere((0.0, -0.98, 0.62), 0.10, "Visor_Amber", sub=1)

    # Twin rear propeller outrigger booms & brass shroud ducts (+Y, elevated Z=0.92 m cleanly above Keep clamps!)
    for sx in (-1.0, 1.0):
        px = sx * 0.98
        gd.add_box((sx * 0.84, 0.64, 0.86), (0.36, 0.14, 0.18), "Recessed_Steel", bevel=0.01)
        gd.add_cyl((px, 0.54, 0.92), (px, 0.86, 0.92), 0.14, 0.12, seg=8, mat="Satin_Silver")
        # Open protective brass shroud ring around propeller disc (Y = 0.88..0.96, bottom Z >= 0.56 m!)
        for k in range(8):
            a0 = 2.0 * pi * k / 8.0
            a1 = 2.0 * pi * (k + 1) / 8.0
            p0 = V((px + cos(a0) * 0.36, 0.92, 0.92 + sin(a0) * 0.36))
            p1 = V((px + cos(a1) * 0.36, 0.92, 0.92 + sin(a1) * 0.36))
            gd.add_cyl(p0, p1, 0.024, 0.024, seg=6, mat="Heraldic_Brass")

    gd_obj = gd.build(col, airframe, mats)

    # 4 Individual Supply Crate Slots (`crate_slot_1..4`), arranged 2x2 on deck (Z = 0.32..0.76)
    crate_coords = [
        ("crate_slot_1", (-0.34, -0.37, 0.32)),
        ("crate_slot_2", ( 0.34, -0.37, 0.32)),
        ("crate_slot_3", (-0.34,  0.35, 0.32)),
        ("crate_slot_4", ( 0.34,  0.35, 0.32)),
    ]
    crates: list[bpy.types.Object] = []
    for cname, (cx, cy, cz) in crate_coords:
        cb = PartBuilder(cname, (cx, cy, cz))
        sz = 0.44
        cb.add_box((cx, cy, cz + sz * 0.44), (sz, sz, sz * 0.88), "Timber_Oak", bevel=0.015)
        cb.add_box((cx, cy, cz + sz * 0.44), (sz + 0.02, sz * 0.22, sz * 0.84), "Recessed_Steel")
        cb.add_box((cx, cy, cz + sz * 0.44), (sz * 0.22, sz + 0.02, sz * 0.84), "Recessed_Steel")
        cb.add_box((cx, cy, cz + sz * 0.86), (sz * 0.56, sz * 0.56, 0.04), "Heraldic_Brass")
        cb.add_box((cx, cy, cz + sz * 0.89), (sz * 0.28, sz * 0.28, 0.03), "team_color")
        crates.append(cb.build(col, gd_obj, mats))

    # Twin Rear Pusher Propellers (`prop_L`, `prop_R`, children of `gondola_hull`)
    props: list[bpy.types.Object] = []
    for sx, pname in ((-1.0, "prop_L"), (1.0, "prop_R")):
        hub = (sx * 0.98, 0.91, 0.92)
        pb = PartBuilder(pname, hub)
        pb.add_cyl((hub[0], hub[1] - 0.04, hub[2]), (hub[0], hub[1] + 0.09, hub[2]), 0.085, 0.03, seg=8, mat="Heraldic_Brass")
        for b in range(4):
            ang = radians(45.0 + 90.0 * b)
            u = V((cos(ang), 0.0, sin(ang)))
            rot_bl = Matrix.Rotation(ang, 4, "Y") @ Matrix.Rotation(radians(20.0), 4, "X")
            pb.add_box(V(hub) + u * 0.18, (0.25, 0.018, 0.070), "Satin_Silver", rot=rot_bl, bevel=0.004)
            pb.add_box(V(hub) + u * 0.29, (0.075, 0.020, 0.074), "team_color", rot=rot_bl, bevel=0.004)
        props.append(pb.build(col, gd_obj, mats))

    return gd_obj, crates, props


# ---------------------------------------------------------------------------
# Assemble Scene & Save AirBalloon.blend
# ---------------------------------------------------------------------------


def build_balloon() -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.unit_settings.system = "METRIC"
    scene.unit_settings.scale_length = 1.0

    col = bpy.data.collections.new("air_balloon")
    scene.collection.children.link(col)

    root = bpy.data.objects.new("balloon_root", None)
    root.empty_display_type = "PLAIN_AXES"
    root.empty_display_size = 1.0
    col.objects.link(root)

    # Flight airframe pivot at center of buoyancy (0, 0, 2.75) for natural pitch/roll
    airframe = bpy.data.objects.new("airframe_root", None)
    airframe.empty_display_type = "PLAIN_AXES"
    airframe.empty_display_size = 0.8
    col.objects.link(airframe)
    airframe.parent = root
    airframe.location = (0.0, 0.0, 2.75)

    mats = build_materials()

    env, rudder = build_envelope(col, airframe, mats)
    burner, flame = build_burner(col, airframe, mats)
    gondola, crates, props = build_gondola(col, airframe, mats)

    all_meshes = [env, rudder, burner, flame, gondola, *crates, *props]

    bpy.context.view_layer.update()
    mn = V((1e9, 1e9, 1e9))
    mx = V((-1e9, -1e9, -1e9))
    max_dock_r = 0.0
    tri_count = 0
    for ob in all_meshes:
        tri_count += sum(max(1, len(p.vertices) - 2) for p in ob.data.polygons)
        for v in ob.data.vertices:
            wc = ob.matrix_world @ v.co
            mn.x, mn.y, mn.z = min(mn.x, wc.x), min(mn.y, wc.y), min(mn.z, wc.z)
            mx.x, mx.y, mx.z = max(mx.x, wc.x), max(mx.y, wc.y), max(mx.z, wc.z)
            if wc.z <= 0.45:
                max_dock_r = max(max_dock_r, (wc.x * wc.x + wc.y * wc.y) ** 0.5)

    assert mn.z >= -0.02 and mx.z <= 5.75, f"Z bounds unexpected: [{mn.z:.3f}, {mx.z:.3f}]"
    assert max_dock_r <= 1.26, f"Docking ring/skids radius {max_dock_r:.3f} m risks intersecting Keep 1.34 m clamps!"

    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    bpy.context.preferences.filepaths.save_version = 0
    bpy.ops.wm.save_as_mainfile(filepath=OUT)
    print(f"BUILT {OUT} | parts={len(all_meshes)} tris={tri_count} | dock_R={max_dock_r:.2f}m | bounds=({mn.x:.2f}..{mx.x:.2f}, {mn.y:.2f}..{mx.y:.2f}, {mn.z:.2f}..{mx.z:.2f})")


if __name__ == "__main__":
    build_balloon()
