"""Builds Blender/Buildings/Chapterhouse/Chapterhouse.blend procedurally.

Run in headless Blender 4.5:
  blender --background --python build_chapterhouse.py

Conventions:
- Forward / Cathedral Portal: -Y in Blender (+Z in Godot after glTF export)
- Base grounded at Z = 0, Z up, world metres
- Footprint 6 x 6 m: outer geometry strictly inside X, Y in [-2.88, +2.88]
- Max height strictly < 6.75 m (distinctly lower than Keep's 7.53 m, well below 12 m Drones)
- Flat PBR materials only; `team_color` & `team_color_shadow` match scripts/components/team_paint.gd
"""

from __future__ import annotations

import os
from math import cos, pi, radians, sin

import bmesh
import bpy
from mathutils import Matrix, Vector as V

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.normpath(os.path.join(HERE, "..", "Chapterhouse.blend"))

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
    "Visor_Amber":        ((1.00, 0.69, 0.29), 0.14, 0.20, (1.0, 0.65, 0.22), 2.2),
    "Keep_Interior_Dark": ((0.022, 0.025, 0.030), 0.10, 0.85, None, 0.0),
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
    """Accumulates flat-shaded sub-meshes with per-face materials under one pivot."""

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

    def add_sphere(self, center, r: float, mat: str, scale=(1.0, 1.0, 1.0), sub: int = 2) -> None:
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

    def add_frustum_shell(self, bot_pts, top_pts, mat: str) -> None:
        sub = bmesh.new()
        bv = [sub.verts.new(V(p)) for p in bot_pts]
        tv = [sub.verts.new(V(p)) for p in top_pts]
        n = len(bv)
        sub.faces.new(list(reversed(bv)))
        sub.faces.new(tv)
        for i in range(n):
            j = (i + 1) % n
            sub.faces.new((bv[i], bv[j], tv[j], tv[i]))
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
# 1. Foundation Plinth (6x6 footprint strictly inside [-2.86, +2.86])
# ---------------------------------------------------------------------------


def build_plinth(col, root, mats) -> bpy.types.Object:
    pb = PartBuilder("plinth", (0.0, 0.0, 0.0))

    # Main chamfered plinth tiers
    pb.add_span(-2.85, 2.85, -2.84, 2.85, 0.00, 0.16, "Recessed_Steel", bevel=0.04)
    pb.add_span(-2.66, 2.66, -2.68, 2.66, 0.14, 0.28, "Ivory_Armor", bevel=0.03)

    # Corner steel anchor piers
    for sx in (-1.0, 1.0):
        for sy in (-1.0, 1.0):
            pb.add_box((sx * 2.52, sy * 2.48, 0.19), (0.64, 0.64, 0.34), "Recessed_Steel", bevel=0.025)
            pb.add_box((sx * 2.52, sy * 2.48, 0.37), (0.48, 0.48, 0.08), "Satin_Silver", bevel=0.015)

    # Front sally-port threshold ramp & heraldic carpet trim (-Y)
    pb.add_frustum_shell(
        [(-1.26, -2.86, 0.00), (1.26, -2.86, 0.00), (1.16, -2.26, 0.00), (-1.16, -2.26, 0.00)],
        [(-1.12, -2.72, 0.27), (1.12, -2.72, 0.27), (1.12, -2.26, 0.27), (-1.12, -2.26, 0.27)],
        "Recessed_Steel",
    )
    pb.add_span(-0.88, 0.88, -2.78, -2.20, 0.24, 0.285, "Satin_Silver")
    pb.add_span(-0.56, 0.56, -2.76, -2.20, 0.27, 0.295, "Heraldic_Brass")

    return pb.build(col, root, mats)


# ---------------------------------------------------------------------------
# 2. Fortified Chapel-Nave Walls, Buttresses & Stained Lancet Windows
# ---------------------------------------------------------------------------


def build_nave_walls(col, root, mats) -> bpy.types.Object:
    nw = PartBuilder("nave_walls", (0.0, 0.10, 0.0))

    # Main armored hall body (leaves recessed portal pocket at front -Y)
    # Dark interior box + stepped Ivory_Armor side walls and rear wall
    nw.add_span(-2.14, 2.14, -2.08, 2.34, 0.28, 3.08, "Ivory_Armor", bevel=0.03)
    # Lower steel wainscot skirt
    nw.add_span(-2.22, 2.22, -2.14, 2.40, 0.26, 0.72, "Recessed_Steel", bevel=0.02)
    # Upper brass cornice frieze band under roof eaves
    nw.add_span(-2.26, 2.26, -2.18, 2.44, 2.88, 3.04, "Heraldic_Brass", bevel=0.01)
    nw.add_span(-2.32, 2.32, -2.22, 2.48, 3.02, 3.16, "Satin_Silver", bevel=0.015)

    # 6 heavy gothic pilaster buttresses along East (+X) and West (-X) flanks + 2 rear corner buttresses
    for sx in (-1.0, 1.0):
        for by in (-1.68, 0.12, 1.98):
            bx = sx * 2.32
            nw.add_box((bx, by, 1.05), (0.46, 0.44, 1.56), "Ivory_Armor", bevel=0.02)
            nw.add_box((bx + sx * 0.06, by, 0.55), (0.52, 0.48, 0.56), "Recessed_Steel", bevel=0.02)
            nw.add_box((bx * 0.96, by, 2.38), (0.36, 0.36, 1.24), "Ivory_Armor", bevel=0.02)
            # Sloped cap + pinnacle cone
            nw.add_box((bx, by, 1.85), (0.44, 0.46, 0.10), "Satin_Silver", bevel=0.015)
            nw.add_cyl((bx * 0.96, by, 2.98), (bx * 0.96, by, 3.44), 0.18, 0.04, seg=4, mat="Heraldic_Brass", twist_rad=radians(45.0))
            nw.add_sphere((bx * 0.96, by, 3.48), 0.065, "Satin_Silver", sub=1)

        # 2 pointed gothic lancet stained windows per side (between buttresses at y = -0.78 and +1.05)
        for wy in (-0.78, 1.05):
            wx = sx * 2.15
            # Dark frame recess + gothic triangular arch hood
            nw.add_span(wx - 0.07, wx + 0.07, wy - 0.34, wy + 0.34, 1.06, 2.38, "Recessed_Steel", bevel=0.01)
            nw.add_cyl((wx, wy, 2.32), (wx, wy, 2.74), 0.34, 0.04, seg=4, mat="Recessed_Steel", twist_rad=radians(45.0))
            # Glowing Visor_Amber lancet glass & pointed arch top
            nw.add_span(wx - 0.085, wx + 0.085, wy - 0.24, wy + 0.24, 1.14, 2.30, "Visor_Amber")
            nw.add_cyl((wx + sx * 0.03, wy, 2.30), (wx + sx * 0.03, wy, 2.60), 0.22, 0.02, seg=4, mat="Visor_Amber", twist_rad=radians(45.0))
            # Outer brass Gothic hood trim & vertical mullion cross
            nw.add_span(wx - 0.10, wx + 0.10, wy - 0.03, wy + 0.03, 1.12, 2.52, "Heraldic_Brass")
            nw.add_span(wx - 0.10, wx + 0.10, wy - 0.26, wy + 0.26, 1.78, 1.84, "Heraldic_Brass")

    # Rear facade (+Y): buttresses + central stained rose-lancet panel & heraldic plaque
    for rx in (-1.20, 1.20):
        nw.add_box((rx, 2.44, 1.65), (0.42, 0.36, 2.74), "Ivory_Armor", bevel=0.02)
        nw.add_cyl((rx, 2.44, 3.02), (rx, 2.44, 3.46), 0.16, 0.04, seg=4, mat="Heraldic_Brass", twist_rad=radians(45.0))
    # Rear stained window
    nw.add_span(-0.56, 0.56, 2.28, 2.44, 1.16, 2.66, "Recessed_Steel", bevel=0.015)
    nw.add_span(-0.44, 0.44, 2.32, 2.46, 1.24, 2.58, "Visor_Amber")
    nw.add_span(-0.04, 0.04, 2.32, 2.48, 1.24, 2.58, "Heraldic_Brass")
    nw.add_span(-0.46, 0.46, 2.32, 2.48, 1.88, 1.94, "Heraldic_Brass")

    # Asymmetric Forge Hearth Chimney on +X rear-flank (distinct RTS silhouette from Keep)
    nw.add_span(2.12, 2.66, 0.78, 1.38, 0.28, 3.55, "Recessed_Steel", bevel=0.02)
    nw.add_span(2.18, 2.62, 0.84, 1.32, 1.80, 4.18, "Ivory_Armor", bevel=0.02)
    nw.add_span(2.14, 2.68, 0.80, 1.36, 4.14, 4.30, "Heraldic_Brass", bevel=0.015)
    nw.add_span(2.24, 2.58, 0.90, 1.26, 4.26, 4.46, "Keep_Interior_Dark")
    # Small warm forge vent slit near base of chimney
    nw.add_span(2.58, 2.69, 0.92, 1.24, 0.82, 1.28, "Visor_Amber")

    return nw.build(col, root, mats)


# ---------------------------------------------------------------------------
# 3. Side Armory Weapon & Shield Rack (-X side, strictly within -2.84 m)
# ---------------------------------------------------------------------------


def build_armory_rack(col, root, mats) -> bpy.types.Object:
    ar = PartBuilder("armory_rack", (-2.48, -0.78, 0.0))

    # Ground timber sill & canopy frame tucked between front & mid -X buttresses (Y = -1.35..-0.22)
    ar.add_span(-2.78, -2.26, -1.36, -0.20, 0.26, 0.36, "Harness_Leather", bevel=0.01)
    for py in (-1.28, -0.28):
        ar.add_box((-2.72, py, 0.98), (0.09, 0.09, 1.36), "Harness_Leather", bevel=0.01)
    ar.add_span(-2.78, -2.26, -1.36, -0.20, 1.62, 1.72, "Harness_Leather")
    # Slanted team_color awning hood with brass fascia
    ar.add_frustum_shell(
        [(-2.24, -1.38, 1.98), (-2.82, -1.38, 1.56), (-2.82, -0.18, 1.56), (-2.24, -0.18, 1.98)],
        [(-2.24, -1.38, 2.06), (-2.82, -1.38, 1.64), (-2.82, -0.18, 1.64), (-2.24, -0.18, 2.06)],
        "team_color",
    )
    ar.add_cyl((-2.83, -1.38, 1.60), (-2.83, -0.18, 1.60), 0.032, 0.032, seg=6, mat="Heraldic_Brass")

    # Halberd / lance rack (4 vertical lances with Satin_Silver spearheads)
    for idx, ly in enumerate((-1.10, -0.92, -0.74, -0.56)):
        ar.add_cyl((-2.56, ly, 0.34), (-2.56, ly, 1.38), 0.024, 0.022, seg=6, mat="Harness_Leather")
        ar.add_cyl((-2.56, ly, 1.38), (-2.56, ly, 1.62), 0.036, 0.005, seg=4, mat="Satin_Silver")

    # 2 leaned heraldic round buckler shields on front-right rack slot
    for sy_pos in (-0.42, -0.96):
        sh_rot = Matrix.Rotation(radians(-16.0), 4, "Y")
        ar.add_box((-2.62, sy_pos, 0.74), (0.06, 0.34, 0.44), "team_color", rot=sh_rot, bevel=0.015)
        ar.add_box((-2.65, sy_pos, 0.74), (0.05, 0.14, 0.14), "Heraldic_Brass", rot=sh_rot)

    return ar.build(col, root, mats)


# ---------------------------------------------------------------------------
# 4. Gothic Portal Pavilion, Armored Chapter Doors & Vestibule Hearth (-Y)
# ---------------------------------------------------------------------------


def build_portal(col, root, mats) -> tuple[bpy.types.Object, bpy.types.Object, bpy.types.Object, bpy.types.Object]:
    pf = PartBuilder("portal_frame", (0.0, -2.42, 0.0))

    # Flanking Ivory_Armor chamfered gatehouse piers (Y = -2.76..-1.96, X = +-0.94..+-1.52)
    for sx in (-1.0, 1.0):
        px = sx * 1.24
        pf.add_box((px, -2.38, 1.56), (0.56, 0.76, 2.56), "Ivory_Armor", bevel=0.025)
        pf.add_box((px, -2.38, 0.50), (0.60, 0.80, 0.44), "Recessed_Steel", bevel=0.02)
        pf.add_box((px, -2.38, 2.86), (0.62, 0.82, 0.14), "Heraldic_Brass", bevel=0.015)
        # Small pier shoulder pinnacle
        pf.add_cyl((px, -2.48, 2.93), (px, -2.48, 3.34), 0.16, 0.03, seg=4, mat="team_color", twist_rad=radians(45.0))

    # Upper arched pediment & recessed doorway lintel
    pf.add_span(-1.12, 1.12, -2.76, -1.96, 2.50, 3.06, "Ivory_Armor", bevel=0.02)
    # Gable pediment over portal (team_color roof face + brass trim)
    pf.add_frustum_shell(
        [(-1.26, -2.78, 3.02), (1.26, -2.78, 3.02), (1.26, -1.92, 3.02), (-1.26, -1.92, 3.02)],
        [(-0.08, -2.72, 4.02), (0.08, -2.72, 4.02), (0.08, -1.92, 4.02), (-0.08, -1.92, 4.02)],
        "team_color",
    )
    pf.add_cyl((-1.28, -2.78, 3.04), (0.0, -2.72, 4.04), 0.055, 0.055, seg=6, mat="Heraldic_Brass")
    pf.add_cyl(( 1.28, -2.78, 3.04), (0.0, -2.72, 4.04), 0.055, 0.055, seg=6, mat="Heraldic_Brass")
    pf.add_cyl((0.0, -2.72, 4.04), (0.0, -1.92, 4.04), 0.06, 0.06, seg=6, mat="Heraldic_Brass")

    # Gothic doorway arch trim & starburst crest above doors
    pf.add_span(-0.98, 0.98, -2.78, -2.62, 2.42, 2.60, "Heraldic_Brass", bevel=0.012)
    add_starburst_and_sword(pf, V((0.0, -2.74, 3.36)), -Y, Z, scale=1.65, star_mat="Heraldic_Brass", sword_mat="Satin_Silver")

    # Deep dark chapter hall vestibule behind the doors (behind front doorway pocket Y=-2.28..-1.88)
    pf.add_span(-0.94, 0.94, -2.26, -1.88, 0.28, 2.46, "Keep_Interior_Dark")

    pf_obj = pf.build(col, root, mats)

    # Armored Double Doors (`portal_door_L`, `portal_door_R`), pivoted cleanly on outer hinge line
    doors = []
    for side, sname in ((-1.0, "portal_door_L"), (1.0, "portal_door_R")):
        hx = side * 0.92
        hy = -2.66
        d_pb = PartBuilder(sname, (hx, hy, 1.38))
        x_in = 0.00 if side > 0 else hx
        x_out = hx if side > 0 else 0.00
        # Slight 1 cm center seam gap so closed leaves read cleanly without z-fighting
        xmin = x_in + (0.012 if side > 0 else 0.015)
        xmax = x_out - (0.015 if side > 0 else 0.012)
        cx = (xmin + xmax) * 0.5
        w = xmax - xmin
        # Steel armored leaf
        d_pb.add_box((cx, hy, 1.38), (w, 0.11, 2.18), "Recessed_Steel", bevel=0.012)
        # Outer hinge cylinder pin
        d_pb.add_cyl((hx, hy, 0.32), (hx, hy, 2.44), 0.048, 0.048, seg=8, mat="Heraldic_Brass")
        # Horizontal brass reinforcing straps + central heraldic diamond inlay
        for bz in (0.62, 1.38, 2.12):
            d_pb.add_box((cx, hy - 0.052, bz), (w * 0.94, 0.025, 0.075), "Heraldic_Brass")
        d_pb.add_box((cx, hy - 0.056, 1.38), (w * 0.52, 0.028, 0.68), "team_color_shadow", bevel=0.008)
        d_pb.add_box((cx, hy - 0.068, 1.38), (w * 0.22, 0.024, 0.34), "Ivory_Armor")
        doors.append(d_pb.build(col, pf_obj, mats))

    # Warm vestibule hearth glow panel revealed cleanly when doors swing wide open
    hg = PartBuilder("portal_hearth_glow", (0.0, -2.30, 1.25))
    hg.add_span(-0.72, 0.72, -2.28, -2.18, 0.36, 2.12, "Visor_Amber", bevel=0.02)
    hg.add_span(-0.82, 0.82, -2.56, -2.24, 0.27, 0.32, "Visor_Amber")
    hg_obj = hg.build(col, pf_obj, mats)

    return pf_obj, doors[0], doors[1], hg_obj


# ---------------------------------------------------------------------------
# 5. Steep Gothic Roof, Open Belfry Lantern & Heraldic Banners
# ---------------------------------------------------------------------------


def build_roof_and_banners(col, root, mats) -> tuple[bpy.types.Object, bpy.types.Object, list[bpy.types.Object]]:
    rf = PartBuilder("roof", (0.0, 0.10, 3.12))

    # Main steep gothic gable roof (eaves Z=3.08 +-2.48 X -> ridge Z=4.90 along Y)
    eave_z, ridge_z = 3.08, 4.90
    y0, y1 = -2.22, 2.48
    # Build solid triangular prism for pitched roof with brass verge borders
    sub = bmesh.new()
    v_fl = sub.verts.new(V((-2.48, y0, eave_z)))
    v_fr = sub.verts.new(V(( 2.48, y0, eave_z)))
    v_ft = sub.verts.new(V(( 0.00, y0, ridge_z)))
    v_bl = sub.verts.new(V((-2.48, y1, eave_z)))
    v_br = sub.verts.new(V(( 2.48, y1, eave_z)))
    v_bt = sub.verts.new(V(( 0.00, y1, ridge_z)))
    sub.faces.new((v_fl, v_fr, v_ft))
    sub.faces.new((v_br, v_bl, v_bt))
    sub.faces.new((v_fl, v_ft, v_bt, v_bl))
    sub.faces.new((v_fr, v_br, v_bt, v_ft))
    sub.faces.new((v_fl, v_bl, v_br, v_fr))
    bmesh.ops.recalc_face_normals(sub, faces=sub.faces[:])
    # Tag gable triangle ends Ivory_Armor and steep sloped faces team_color
    vmap = {v: rf.bm.verts.new(rf._to_local(v.co)) for v in sub.verts}
    for fc in sub.faces:
        nf = rf.bm.faces.new([vmap[v] for v in fc.verts])
        nf.smooth = False
        mat_pick = "Ivory_Armor" if abs(fc.normal.y) > 0.7 else ("Recessed_Steel" if fc.normal.z < -0.5 else "team_color")
        rf.face_mats.append(mat_pick)
    sub.free()

    # Brass roof ridge beam, eave gutters & 2 side dormer armor accents
    rf.add_cyl((0.0, y0 - 0.04, ridge_z), (0.0, y1 + 0.04, ridge_z), 0.09, 0.09, seg=6, mat="Heraldic_Brass")
    for gy in (y0, y1):
        rf.add_cyl((-2.48, gy, eave_z), (0.0, gy, ridge_z + 0.03), 0.06, 0.06, seg=6, mat="Heraldic_Brass")
        rf.add_cyl(( 2.48, gy, eave_z), (0.0, gy, ridge_z + 0.03), 0.06, 0.06, seg=6, mat="Heraldic_Brass")
    for sx in (-1.0, 1.0):
        rf.add_span(sx * 2.42, sx * 2.52, y0 - 0.04, y1 + 0.04, eave_z - 0.05, eave_z + 0.06, "Satin_Silver")

    # Heraldic flush starburst badges seated cleanly on the roof slopes (matching Keep roof emblems)
    for sx in (-1.0, 1.0):
        nrm = V((sx * (ridge_z - eave_z), 0.0, 2.48)).normalized()
        up_s = V((-sx * 2.48, 0.0, ridge_z - eave_z)).normalized()
        for dy in (-0.82, 0.96):
            mid = V((sx * 1.24, dy, (eave_z + ridge_z) * 0.5)) + nrm * 0.014
            add_starburst_and_sword(rf, mid, nrm, up_s, scale=1.55, star_mat="Heraldic_Brass", sword_mat="Satin_Silver")

    # Central Octagonal Belfry Lantern Tower + Spire Finial (total Z <= 6.60 m)
    bx, by = 0.0, 0.14
    rf.add_prism(oct_pts(bx, by, 0.96, 22.5), 4.35, 4.78, "Ivory_Armor")
    rf.add_prism(oct_pts(bx, by, 1.02, 22.5), 4.74, 4.86, "Satin_Silver")
    # 8 open belfry corner brass/ivory columns (Z = 4.84..5.52)
    for k in range(8):
        ang = radians(22.5 + 45.0 * k)
        px = bx + cos(ang) * 0.78
        py = by + sin(ang) * 0.78
        rf.add_cyl((px, py, 4.84), (px, py, 5.54), 0.075, 0.065, seg=6, mat="Heraldic_Brass")
    # Belfry cornice + steep octagonal royal-blue spire
    rf.add_prism(oct_pts(bx, by, 0.94, 22.5), 5.50, 5.64, "Ivory_Armor")
    rf.add_cyl((bx, by, 5.64), (bx, by, 6.26), 0.86, 0.07, seg=8, mat="team_color", twist_rad=radians(22.5))
    rf.add_sphere((bx, by, 6.32), 0.11, "Heraldic_Brass", sub=1)
    # Upright chapter starburst + sword finial crowning spire apex (top ~6.60 m)
    add_starburst_and_sword(rf, V((bx, by - 0.02, 6.46)), -Y, Z, scale=1.15, star_mat="Heraldic_Brass", sword_mat="Satin_Silver")

    roof_obj = rf.build(col, root, mats)

    # Suspended brass bell & glowing amber reliquary beacon inside the belfry arches
    bc = PartBuilder("belfry_beacon", (0.0, 0.14, 5.44))
    bc.add_cyl((bx, by, 5.48), (bx, by, 5.34), 0.04, 0.04, seg=6, mat="Recessed_Steel")
    bc.add_cyl((bx, by, 5.34), (bx, by, 5.06), 0.12, 0.24, seg=10, mat="Heraldic_Brass")
    bc.add_sphere((bx, by, 5.04), 0.14, "Visor_Amber", sub=2)
    bc_obj = bc.build(col, roof_obj, mats)

    # 2 Flanking Swallowtail Chapterhouse Banners on front wall (-Y)
    banners: list[bpy.types.Object] = []
    for side, bname in ((-1.0, "banner_front_L"), (1.0, "banner_front_R")):
        pos = V((side * 1.84, -2.06, 2.74))
        bp = PartBuilder(bname, tuple(pos))
        bp.add_cyl(pos - X * 0.28, pos + X * 0.28, 0.024, 0.024, seg=6, mat="Satin_Silver")
        for s in (-1.0, 1.0):
            bp.add_sphere(pos + X * (s * 0.30), 0.036, "Heraldic_Brass", sub=1)
        cloth_uv = [(-0.24, 0.0), (0.24, 0.0), (0.24, -1.06), (0.0, -1.36), (-0.24, -1.06)]
        bp.add_extruded_poly_frame(cloth_uv, pos, X, Z, -Y, 0.00, 0.035, "team_color")
        bp.add_extruded_poly_frame(
            [(-0.26, 0.01), (0.26, 0.01), (0.26, -1.08), (0.0, -1.40), (-0.26, -1.08)],
            pos, X, Z, -Y, -0.014, 0.004, "Heraldic_Brass",
        )
        add_starburst_and_sword(bp, pos - Z * 0.56 - Y * 0.036, -Y, Z, scale=0.95, star_mat="Heraldic_Brass", sword_mat="Ivory_Armor")
        banners.append(bp.build(col, root, mats))

    return roof_obj, bc_obj, banners


# ---------------------------------------------------------------------------
# Assemble Scene & Save Chapterhouse.blend
# ---------------------------------------------------------------------------


def build_chapterhouse() -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.unit_settings.system = "METRIC"
    scene.unit_settings.scale_length = 1.0

    col = bpy.data.collections.new("chapterhouse")
    scene.collection.children.link(col)

    root = bpy.data.objects.new("chapterhouse_root", None)
    root.empty_display_type = "PLAIN_AXES"
    root.empty_display_size = 1.0
    col.objects.link(root)

    mats = build_materials()

    plinth = build_plinth(col, root, mats)
    walls = build_nave_walls(col, root, mats)
    rack = build_armory_rack(col, root, mats)
    portal, door_l, door_r, hearth = build_portal(col, root, mats)
    roof, beacon, banners = build_roof_and_banners(col, root, mats)

    all_meshes = [plinth, walls, rack, portal, door_l, door_r, hearth, roof, beacon, *banners]

    bpy.context.view_layer.update()
    mn = V((1e9, 1e9, 1e9))
    mx = V((-1e9, -1e9, -1e9))
    tri_count = 0
    for ob in all_meshes:
        tri_count += sum(max(1, len(p.vertices) - 2) for p in ob.data.polygons)
        for corner in ob.bound_box:
            wc = ob.matrix_world @ V(corner)
            mn.x, mn.y, mn.z = min(mn.x, wc.x), min(mn.y, wc.y), min(mn.z, wc.z)
            mx.x, mx.y, mx.z = max(mx.x, wc.x), max(mx.y, wc.y), max(mx.z, wc.z)

    assert mn.x >= -2.92 and mx.x <= 2.92, f"X footprint exceeded 6x6 m: [{mn.x:.3f}, {mx.x:.3f}]"
    assert mn.y >= -2.92 and mx.y <= 2.92, f"Y footprint exceeded 6x6 m: [{mn.y:.3f}, {mx.y:.3f}]"
    assert mn.z >= -0.02 and mx.z <= 6.75, f"Z bounds unexpected: [{mn.z:.3f}, {mx.z:.3f}]"

    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    bpy.context.preferences.filepaths.save_version = 0
    bpy.ops.wm.save_as_mainfile(filepath=OUT)
    print(f"BUILT {OUT} | parts={len(all_meshes)} tris={tri_count} | bounds=({mn.x:.2f}..{mx.x:.2f}, {mn.y:.2f}..{mx.y:.2f}, {mn.z:.2f}..{mx.z:.2f})")


if __name__ == "__main__":
    build_chapterhouse()
