"""Builds Blender/Buildings/Keep/Keep.blend procedurally: the static Arthurian Keep.

Run in headless Blender 4.5:
  blender --background --python build_keep.py

Rebuilds the entire keep collection from scratch so edits never compound.
- Forward / Sally-port Gatehouse: -Y in Blender (+Z in Godot after glTF export)
- Base at Z = 0, Z up, world metres
- Footprint 10 x 10 m: outer geometry kept strictly inside 9.8 x 9.8 m ([-4.88, +4.88])
- Max height strictly < 9.5 m (clear of 12 m Drones)
- Packed oak grain and blue enameled iron; `team_color` matches scripts/components/team_paint.gd
"""

from __future__ import annotations

import math
import os
from math import cos, pi, radians, sin
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector as V

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from keep_finishes import assign_timber_uv, timber_finish
from keep_hall import beam, dock, hall_walls, porch
from keep_roof import add_bay_canopy, build_roof_shell
from keep_towers import build_tower_shell

OUT = os.path.normpath(os.path.join(HERE, "..", "Keep.blend"))

X = V((1.0, 0.0, 0.0))
Y = V((0.0, 1.0, 0.0))
Z = V((0.0, 0.0, 1.0))

# Exact linear Principled BSDF materials aligned with ArthurianMarines/source/build_warhound.py
MATERIAL_SPECS = {
    "Ivory_Armor":        ((0.76, 0.674, 0.525), 0.32, 0.35, None, 0.0),
    "Satin_Silver":       ((0.69, 0.72, 0.73), 0.55, 0.40, None, 0.0),
    "Recessed_Steel":     ((0.065, 0.081, 0.096), 0.60, 0.34, None, 0.0),
    "Heraldic_Brass":     ((0.66, 0.348, 0.086), 0.65, 0.31, None, 0.0),
    "team_color":         ((0.025, 0.075, 0.38), 0.08, 0.64, None, 0.0),
    "team_color_shadow":  ((0.013, 0.033, 0.18), 0.04, 0.70, None, 0.0),
    "Harness_Leather":    ((0.044, 0.034, 0.027), 0.00, 0.64, None, 0.0),
    "Sack_Cloth":         ((0.34, 0.28, 0.20), 0.00, 0.85, None, 0.0),
    "Visor_Amber":        ((1.00, 0.69, 0.29), 0.14, 0.20, (1.0, 0.65, 0.22), 2.2),
    "Clerestory_Glass":    ((0.19, 0.086, 0.025), 0.30, 0.19, (0.70, 0.276, 0.067), 0.30),
    "Amber_Glass":        ((0.72, 0.34, 0.095), 0.12, 0.19, (0.95, 0.42, 0.10), 0.58),
    "Harvest_Grapes":     ((0.136, 0.035, 0.081), 0.02, 0.53, None, 0.0),
    "Royal_Enamel":       ((0.023, 0.062, 0.202), 0.41, 0.42, None, 0.0),
    "Midnight_Enamel":    ((0.031, 0.061, 0.135), 0.54, 0.32, None, 0.0),
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
    for name,srgb,seed in (("Heart_Oak",(176,111,58),18),("Honey_Oak",(209,153,90),36),("Smoked_Oak",(123,75,44),52)):
        mats[name] = timber_finish(name,srgb,seed)
    return mats


# ---------------------------------------------------------------------------
# Modular BMesh Part Assembler (Flat-shaded, Consistent Outward Normals)
# ---------------------------------------------------------------------------


class PartBuilder:
    """Accumulates typed sub-meshes with per-face material tags under one pivot."""

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
        vert_map = {}
        for v in sub_bm.verts:
            vert_map[v] = self.bm.verts.new(self._to_local(v.co))
        for f in sub_bm.faces:
            try:
                nf = self.bm.faces.new([vert_map[v] for v in f.verts])
                nf.smooth = False
                self.face_mats.append(mat_name)
            except ValueError:
                pass
        sub_bm.free()

    def add_box(
        self,
        center: tuple[float, float, float] | V,
        size: tuple[float, float, float] | V,
        mat: str,
        rot: Matrix | None = None,
        bevel: float = 0.0,
    ) -> None:
        sub = bmesh.new()
        xf = Matrix.Translation(V(center)) @ (rot if rot else Matrix.Identity(4)) @ Matrix.Diagonal((*V(size), 1.0))
        bmesh.ops.create_cube(sub, size=1.0, matrix=xf)
        if bevel > 0.0:
            bmesh.ops.bevel(sub, geom=sub.edges[:], offset=bevel, segments=1, profile=0.5, affect="EDGES")
        self._append_bm(sub, mat)

    def add_span(
        self,
        x0: float,
        x1: float,
        y0: float,
        y1: float,
        z0: float,
        z1: float,
        mat: str,
        bevel: float = 0.0,
    ) -> None:
        self.add_box(
            ((x0 + x1) * 0.5, (y0 + y1) * 0.5, (z0 + z1) * 0.5),
            (abs(x1 - x0), abs(y1 - y0), abs(z1 - z0)),
            mat,
            bevel=bevel,
        )

    def add_cyl(
        self,
        p0: tuple[float, float, float] | V,
        p1: tuple[float, float, float] | V,
        r0: float,
        r1: float | None = None,
        seg: int = 8,
        mat: str = "Recessed_Steel",
        cap: bool = True,
        twist_rad: float = 0.0,
    ) -> None:
        p0, p1 = V(p0), V(p1)
        r1 = r0 if r1 is None else r1
        d = p1 - p0
        if d.length < 1e-6:
            return
        sub = bmesh.new()
        track = d.to_track_quat("Z", "Y").to_matrix().to_4x4()
        xf = Matrix.Translation((p0 + p1) * 0.5) @ track @ Matrix.Rotation(twist_rad, 4, "Z")
        bmesh.ops.create_cone(
            sub,
            cap_ends=cap,
            cap_tris=False,
            segments=seg,
            radius1=max(r0, 1e-4),
            radius2=max(r1, 1e-4),
            depth=d.length,
            matrix=xf,
        )
        self._append_bm(sub, mat)

    def add_sphere(
        self,
        center: tuple[float, float, float] | V,
        r: float,
        mat: str,
        scale: tuple[float, float, float] = (1.0, 1.0, 1.0),
        sub: int = 2,
    ) -> None:
        bm = bmesh.new()
        xf = Matrix.Translation(V(center)) @ Matrix.Diagonal((*scale, 1.0))
        bmesh.ops.create_icosphere(bm, subdivisions=sub, radius=r, matrix=xf)
        self._append_bm(bm, mat)

    def add_prism(self, poly_xy: list[tuple[float, float]], z0: float, z1: float, mat: str) -> None:
        """Extrudes a CCW 2D polygon in world XY cleanly between z0 and z1."""
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

    def add_extruded_poly_frame(
        self,
        poly_uv: list[tuple[float, float]],
        origin: V,
        right: V,
        up: V,
        outward: V,
        d0: float,
        d1: float,
        mat: str,
    ) -> None:
        """Extrudes a convex/concave 2D shape in an oriented frame (for banners & heraldry)."""
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

    def add_frustum_shell(
        self,
        bot_pts: list[tuple[float, float, float] | V],
        top_pts: list[tuple[float, float, float] | V],
        mat: str,
    ) -> None:
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

    def add_thick_quad_frame(
        self,
        p00: V,
        p10: V,
        p11: V,
        p01: V,
        out_dir: V,
        thickness: float,
        front_mat: str,
        back_mat: str | None = None,
    ) -> None:
        """Adds a thin solid oriented plate/panel extruded along out_dir."""
        back_mat = back_mat or front_mat
        sub = bmesh.new()
        nrm = out_dir.normalized() * thickness
        b = [sub.verts.new(p) for p in (p00, p10, p11, p01)]
        f = [sub.verts.new(p + nrm) for p in (p00, p10, p11, p01)]
        sub.faces.new(list(reversed(b)))
        sub.faces.new(f)
        for i in range(4):
            j = (i + 1) % 4
            sub.faces.new((b[i], b[j], f[j], f[i]))
        bmesh.ops.recalc_face_normals(sub, faces=sub.faces[:])
        vert_map = {v: self.bm.verts.new(self._to_local(v.co)) for v in sub.verts}
        for idx, fc in enumerate(sub.faces):
            try:
                nf = self.bm.faces.new([vert_map[v] for v in fc.verts])
                nf.smooth = False
                self.face_mats.append(front_mat if fc.normal.dot(out_dir) > 0.25 else back_mat)
            except ValueError:
                pass
        sub.free()

    def build(
        self,
        collection: bpy.types.Collection,
        parent: bpy.types.Object,
        mats: dict[str, bpy.types.Material],
    ) -> bpy.types.Object:
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
        assign_timber_uv(me)

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
    sword_mat: str = "Heraldic_Brass",
) -> None:
    """Original Arthurian heraldry: 8-point starburst behind an upright vertical sword."""
    out = outward.normalized()
    right = up_hint.cross(out)
    if right.length < 1e-4:
        right = X.cross(out)
    right.normalize()
    up = out.cross(right).normalized()

    # 8-point bevelled starburst (16-vertex star profile)
    star_pts = []
    for k in range(16):
        ang = k * (pi / 8.0)
        if k % 2 == 0:
            r = (0.145 if (k % 4 == 0) else 0.112) * scale
        else:
            r = 0.036 * scale
        star_pts.append((sin(ang) * r, cos(ang) * r))
    pb.add_extruded_poly_frame(star_pts, center, right, up, out, 0.0, 0.018 * scale, star_mat)

    # Vertical upright sword seated cleanly in front of starburst center
    blade_pts = [
        (-0.015 * scale, -0.055 * scale),
        ( 0.015 * scale, -0.055 * scale),
        ( 0.011 * scale,  0.140 * scale),
        ( 0.000 * scale,  0.175 * scale),
        (-0.011 * scale,  0.140 * scale),
    ]
    pb.add_extruded_poly_frame(blade_pts, center, right, up, out, 0.014 * scale, 0.032 * scale, sword_mat)
    # Crossguard + grip + pommel
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
    return [(cx + r * cos(radians(rot_deg + 45.0 * i)), cy + r * sin(radians(rot_deg + 45.0 * i))) for i in range(8)]


def build_plinth(col, root, mats) -> bpy.types.Object:
    pb = PartBuilder("plinth", (0.0, 0.0, 0.0))

    # Main stepped base slab inside 10x10 m (stay within [-4.72, +4.72])
    # The front vestibule is a real cutout. Only the timber deck crosses the doorway.
    for side,lo,hi,mat in ((4.20,0,.24,"Recessed_Steel"),(4.02,.24,.405,"Smoked_Oak"),(3.98,.405,.435,"Recessed_Steel")):
        pb.add_span(-side,side,-1.67,side,lo,hi,mat,.015)
        for low,high in ((-side,-1.25),(1.25,side)):
            pb.add_span(low,high,-side,-1.67,lo,hi,mat,.014)

    # Four octagonal corner plinth pads at (+-3.65, +-3.65) -> outer vertex ~ 4.72 <= 4.88
    for sx in (-1.0, 1.0):
        for sy in (-1.0, 1.0):
            cx, cy = sx * 3.65, sy * 3.65
            pb.add_prism(oct_pts(cx, cy, 1.07), 0.00, 0.26, "Recessed_Steel")
            pb.add_prism(oct_pts(cx, cy, 0.99), 0.26, 0.48, "Recessed_Steel")

    # Sloped front sally-port threshold ramp (-Y, within Y >= -4.78)
    pb.add_span(-1.82, 1.82, -4.54, -3.60, 0.00, 0.22, "Recessed_Steel", bevel=0.02)
    pb.add_span(-1.38, 1.38, -4.50, -2.05, 0.14, 0.26, "Recessed_Steel", bevel=0.015)
    # Tapered outer step ramp from -4.80 (-Y) up to threshold -4.46
    ramp_bot = [
        V((-1.42, -4.80, 0.00)),
        V(( 1.42, -4.80, 0.00)),
        V(( 1.42, -4.46, 0.00)),
        V((-1.42, -4.46, 0.00)),
    ]
    ramp_top = [
        V((-1.42, -4.80, 0.05)),
        V(( 1.42, -4.80, 0.05)),
        V(( 1.42, -4.46, 0.24)),
        V((-1.42, -4.46, 0.24)),
    ]
    pb.add_frustum_shell(ramp_bot, ramp_top, "Recessed_Steel")

    for i in range(12):
        y = -4.48+i*.225
        pb.add_span(-1.13,1.13,y,y+.215,.254,.285,"Smoked_Oak" if i%3 else "Heart_Oak",.005)
    for x in (-.96,.96):
        pb.add_span(x-.017,x+.017,-4.48,-1.81,.280,.298,"Recessed_Steel")
    for i in range(6):
        y=-4.77+i*.05
        z=.049+(y+4.80)*.550
        pb.add_box((0,y,z),(2.08,.020,.013),"Recessed_Steel")

    # Covered receiving bay floor pad (-X side, X >= -4.82)
    pb.add_span(-4.82, -3.60, -2.26, 2.26, 0.00, 0.20, "Recessed_Steel", bevel=0.025)
    pb.add_span(-4.74, -3.60, -2.18, 2.18, 0.18, 0.28, "Ivory_Armor", bevel=0.02)

    return pb.build(col, root, mats)


def build_corner_tower(col, root, mats, name: str, sx: float, sy: float) -> bpy.types.Object:
    cx, cy = sx * 3.65, sy * 3.65
    pb = PartBuilder(name, (cx, cy, 0.0))

    build_tower_shell(pb,cx,cy)
    return pb.build(col,root,mats)


def build_bastion_walls(col, root, mats):
    wall = PartBuilder("bastion_walls")
    hall_walls(wall)
    return wall.build(col, root, mats)


def build_gatehouse(col, root, mats):
    gf = PartBuilder("gatehouse_frame", (0.0, -4.05, 0.0))
    porch(gf,add_starburst_and_sword)
    gf_obj = gf.build(col,root,mats)

    # Sliding dark-steel lattice portcullis (child of gatehouse_frame; pivot at top bar Z = 2.86)
    pc = PartBuilder("portcullis", (0.0, -4.16, 2.86))
    # Top frame beam & horizontal lattice bars
    for zz in (2.82, 2.25, 1.68, 1.11, 0.56):
        pc.add_span(-1.18, 1.18, -4.22, -4.10, zz - 0.045, zz + 0.045, "Recessed_Steel", bevel=0.008)
    # 7 vertical iron bars with lower pikes + brass rivets at intersections
    for bx in (-1.02, -0.68, -0.34, 0.0, 0.34, 0.68, 1.02):
        # Trim outer bars slightly to follow upper arch contour smoothly
        top_bar_z = 2.84 if abs(bx) < 0.72 else 2.66
        pc.add_span(bx - 0.04, bx + 0.04, -4.21, -4.11, 0.28, top_bar_z, "Recessed_Steel", bevel=0.008)
        pc.add_cyl((bx, -4.16, 0.28), (bx, -4.16, 0.16), 0.045, 0.006, seg=6, mat="Satin_Silver")
        for zz in (2.25, 1.68, 1.11, 0.56):
            pc.add_box((bx, -4.22, zz), (0.048, 0.03, 0.048), "Heraldic_Brass")
    pc_obj = pc.build(col, gf_obj, mats)

    # Interior warm hearth glow panel + vestibule floor ember slab (child of gatehouse_frame)
    hg = PartBuilder("gate_hearth_glow", (0.0, -2.55, 1.10))
    # Sheltered, lit timber corridor visible through the gate.
    hg.add_span(-1.18,1.18,-1.95,-1.87,0.28,2.94,"Smoked_Oak")
    for x in (-.96,-.65,-.34,.34,.65,.96):
        hg.add_box((x,-1.98,1.61),(.23,.07,1.65),"Clerestory_Glass",bevel=.018)
        hg.add_box((x,-2.025,1.76),(.15,.025,.41),"Visor_Amber",bevel=.009)
    for x in (-1.02,1.02):
        hg.add_box((x,-2.93,.30),(.045,1.45,.035),"Visor_Amber")
    hg.add_box((0,-2.62,.26),(2.44,2.52,.08),"Heart_Oak",bevel=.009)
    hg_obj = hg.build(col, gf_obj, mats)

    return gf_obj, pc_obj, hg_obj


# ---------------------------------------------------------------------------
# 3. Covered Resource Receiving Bay & Lantern (-X side)
# ---------------------------------------------------------------------------


def build_receiving_bay(col, root, mats) -> tuple[bpy.types.Object, bpy.types.Object]:
    rb = PartBuilder("receiving_bay", (-4.20, 0.0, 0.0))

    dock(rb)
    add_bay_canopy(rb)

    # Stacked low-poly wooden supply crates (south half Y = -1.75..-0.52)
    def add_crate(cx: float, cy: float, cz: float, sz: float, yaw_deg: float = 0.0) -> None:
        r = Matrix.Rotation(radians(yaw_deg), 4, "Z")
        rb.add_box((cx, cy, cz + sz * 0.5), (sz, sz, sz), "Honey_Oak", rot=r, bevel=0.01)
        rb.add_box((cx, cy, cz + sz * 0.5), (sz + 0.02, sz * 0.22, sz * 0.94), "Recessed_Steel", rot=r)
        rb.add_box((cx, cy, cz + sz * 0.5), (sz * 0.22, sz + 0.02, sz * 0.94), "Recessed_Steel", rot=r)

    add_crate(-4.18, -1.42, 0.28, 0.58, 4.0)
    add_crate(-4.20, -0.78, 0.28, 0.54, -6.0)
    add_crate(-4.18, -1.16, 0.86, 0.46, 12.0)
    # Small banded wooden supply barrel
    rb.add_cyl((-4.42, -0.45, 0.28), (-4.42, -0.45, 0.84), 0.20, 0.18, seg=10, mat="Honey_Oak")
    rb.add_cyl((-4.42, -0.45, 0.40), (-4.42, -0.45, 0.45), 0.21, 0.21, seg=10, mat="Recessed_Steel")
    rb.add_cyl((-4.42, -0.45, 0.68), (-4.42, -0.45, 0.73), 0.205, 0.205, seg=10, mat="Recessed_Steel")

    # Stacked low-poly tied grain sacks (north half Y = +0.55..+1.70)
    for sx_pos, sy_pos, sz_pos, sc in [
        (-4.12, 1.68, 0.40, (0.30, 0.42, 0.16)),
        (-4.15, 1.96, 0.40, (0.28, 0.38, 0.15)),
        (-4.46, 1.83, 0.38, (0.26, 0.36, 0.14)),
        (-4.18, 1.78, 0.66, (0.26, 0.36, 0.14)),
    ]:
        rb.add_sphere((sx_pos, sy_pos, sz_pos), 1.0, "Sack_Cloth", scale=sc, sub=1)

    rb_obj = rb.build(col, root, mats)

    # Hanging lantern under center awning edge (child of receiving_bay)
    bl = PartBuilder("bay_lantern", (-4.45, 0.0, 2.52))
    bl.add_cyl((-4.45, 0.0, 2.52), (-4.45, 0.0, 2.34), 0.018, 0.018, seg=6, mat="Recessed_Steel")
    bl.add_cyl((-4.45, 0.0, 2.34), (-4.45, 0.0, 2.26), 0.11, 0.05, seg=6, mat="Heraldic_Brass")
    bl.add_cyl((-4.45, 0.0, 2.26), (-4.45, 0.0, 2.04), 0.085, 0.075, seg=6, mat="Visor_Amber")
    bl.add_cyl((-4.45, 0.0, 2.04), (-4.45, 0.0, 1.98), 0.10, 0.08, seg=6, mat="Heraldic_Brass")
    bl_obj = bl.build(col, rb_obj, mats)

    return rb_obj, bl_obj


# ---------------------------------------------------------------------------
# 4. Sloped Armor Roof, Banners & Heraldic Emblems
# ---------------------------------------------------------------------------


def build_roof_and_banners(col, root, mats) -> tuple[bpy.types.Object, list[bpy.types.Object]]:
    rf = PartBuilder("roof", (0.0, 0.0, 4.35))

    build_roof_shell(rf)
    roof_obj = rf.build(col, root, mats)

    # 4 individually pivoted vertical swallowtail heraldry banners (front gatehouse & +X flank)
    banners: list[bpy.types.Object] = []
    banner_specs = [
        ("banner_front_L", V((-2.61, -4.19, 3.80)), -Y),
        ("banner_front_R", V(( 2.61, -4.19, 3.80)), -Y),
        ("banner_side_L",  V(( 3.76, -1.63, 3.98)),  X),
        ("banner_side_R",  V(( 3.76,  1.63, 3.98)),  X),
    ]
    for bname, pos, out in banner_specs:
        bp = PartBuilder(bname, tuple(pos))
        right = Z.cross(out).normalized()
        # Wall bracket rod + finials
        bp.add_cyl(pos - right * 0.34, pos + right * 0.34, 0.026, 0.026, seg=6, mat="Satin_Silver")
        for s in (-1.0, 1.0):
            bp.add_sphere(pos + right * (s * 0.36), 0.042, "Heraldic_Brass", sub=1)
        # Swallowtail banner cloth (origin on top bar Z = 3.60 down to tip Z = 1.92)
        cloth_uv = [
            (-0.29,  0.00),
            ( 0.29,  0.00),
            ( 0.29, -1.28),
            ( 0.00, -1.64),
            (-0.29, -1.28),
        ]
        bp.add_extruded_poly_frame(cloth_uv, pos, right, Z, out, 0.00, 0.04, "team_color")
        # Thin brass border backing strip slightly proud
        bp.add_extruded_poly_frame(
            [(-0.31, 0.01), (0.31, 0.01), (0.31, -1.30), (0.0, -1.68), (-0.31, -1.30)],
            pos, right, Z, out, -0.015, 0.005, "Heraldic_Brass",
        )
        # Miniature gold starburst & sword on banner center
        add_starburst_and_sword(bp, pos - Z * 0.68 + out * 0.036, out, Z, scale=1.22, star_mat="Heraldic_Brass", sword_mat="Ivory_Armor")
        banners.append(bp.build(col, root, mats))

    return roof_obj, banners


# ---------------------------------------------------------------------------
# 5. Rooftop Air Balloon Mooring Pad, Radial Clamps & Cardinal Beacons
# ---------------------------------------------------------------------------


def build_balloon_pad(col, root, mats) -> tuple[bpy.types.Object, list[bpy.types.Object], list[bpy.types.Object]]:
    pad = PartBuilder("balloon_pad", (0.0, 0.0, 7.00))

    def octagon(size, corner):
        return [(-size+corner,-size),(size-corner,-size),(size,-size+corner),(size,size-corner),
                (size-corner,size),(-size+corner,size),(-size,size-corner),(-size,-size+corner)]
    pad.add_prism(octagon(1.74,.15),6.945,7.09,"Recessed_Steel")
    pad.add_prism(octagon(1.61,.11),7.086,7.125,"Smoked_Oak")
    for i in range(11):
        x = -1.42+i*.262
        pad.add_box((x,0,7.140),(.250,2.94,.033),"Heart_Oak" if i%4==0 else "Smoked_Oak",bevel=.006)
    pad.add_cyl((0,0,7.145),(0,0,7.173),.43,.43,24,"Recessed_Steel")
    pad.add_cyl((0,0,7.17),(0,0,7.180),.32,.32,24,"Heraldic_Brass")
    pad.add_cyl((0,0,7.177),(0,0,7.20),.24,.22,16,"Recessed_Steel")
    for side in (-1,1):
        for i in range(5):
            along=-1.32+i*.66
            pad.add_cyl((along,side*1.67,7.082),(along,side*1.67,7.105),.036,.030,8,"Satin_Silver")
            pad.add_cyl((side*1.67,along,7.082),(side*1.67,along,7.105),.036,.030,8,"Satin_Silver")

    for side in (-1,1):
        for i in range(4):
            along=-1.17+i*.63
            pad.add_box((along,side*1.64,7.086),(.42,.051,.02),"Visor_Amber",bevel=.005)
            pad.add_box((side*1.64,along,7.086),(.051,.42,.02),"Visor_Amber",bevel=.005)

    pad_obj = pad.build(col, root, mats)

    # 4 Diagonal Articulated Mooring Clamps at 45, 135, 225, 315 deg (matches BALLOON MOORING PAD detail)
    clamps: list[bpy.types.Object] = []
    for idx, deg in enumerate((45.0, 135.0, 225.0, 315.0), start=1):
        a = radians(deg)
        rad_out = V((cos(a), sin(a), 0.0))
        tan = V((-sin(a), cos(a), 0.0))
        hinge = rad_out * 1.34 + Z * 7.20
        cb = PartBuilder(f"mooring_clamp_{idx:02d}", tuple(hinge))
        # Outer hinge knuckles
        cb.add_cyl(hinge - tan * 0.15, hinge + tan * 0.15, 0.10, 0.10, seg=8, mat="Heraldic_Brass")
        # Arm arching radially inward over the landing deck
        elbow = rad_out * 1.04 + Z * 7.60
        tip = rad_out * 0.66 + Z * 7.36
        rot = Matrix(((rad_out.x, tan.x, 0, 0), (rad_out.y, tan.y, 0, 0), (0, 0, 1, 0), (0, 0, 0, 1)))
        # Twin side cheeks straddle the second bearing; a hooked black shoe folds over the deck.
        for side in (-1,1):
            offset=tan*side*.102
            beam(cb,hinge+offset,elbow+offset,.128,.070,"Heraldic_Brass",tan)
        cb.add_cyl(elbow-tan*.158,elbow+tan*.158,.109,.109,12,"Recessed_Steel")
        cb.add_cyl(elbow-tan*.165,elbow+tan*.165,.059,.059,10,"Satin_Silver")
        beam(cb,elbow,tip+Z*.08,.155,.145,"Recessed_Steel",tan)
        beam(cb,tip+Z*.13,tip-Z*.025,.105,.17,"Heraldic_Brass",tan)
        clamps.append(cb.build(col, pad_obj, mats))

    # 4 Cardinal Glowing Amber Guidance Beacons at 0, 90, 180, 270 deg
    beacons: list[bpy.types.Object] = []
    for idx, deg in enumerate((270.0, 0.0, 90.0, 180.0), start=1):
        a = radians(deg)
        bc_pos = V((cos(a) * 1.56, sin(a) * 1.56, 7.12))
        bb = PartBuilder(f"pad_beacon_{idx:02d}", tuple(bc_pos))
        bb.add_cyl(bc_pos - Z * 0.10, bc_pos + Z * 0.06, 0.17, 0.14, seg=8, mat="Heraldic_Brass")
        bb.add_sphere(bc_pos + Z * 0.11, 0.12, "Visor_Amber", scale=(1.0, 1.0, 1.25), sub=2)
        bb.add_cyl(bc_pos + Z * 0.04, bc_pos + Z * 0.14, 0.14, 0.11, seg=8, mat="Recessed_Steel", cap=False)
        beacons.append(bb.build(col, pad_obj, mats))

    return pad_obj, clamps, beacons


# ---------------------------------------------------------------------------
# Assemble Scene & Save Keep.blend
# ---------------------------------------------------------------------------


def build_keep() -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.render.fps = 24
    scene.unit_settings.system = "METRIC"
    scene.unit_settings.scale_length = 1.0

    keep_col = bpy.data.collections.new("keep")
    scene.collection.children.link(keep_col)

    root = bpy.data.objects.new("keep_root", None)
    root.empty_display_type = "PLAIN_AXES"
    root.empty_display_size = 1.0
    keep_col.objects.link(root)

    mats = build_materials()

    plinth = build_plinth(keep_col, root, mats)
    towers = [
        build_corner_tower(keep_col, root, mats, "corner_tower_FL", -1.0, -1.0),
        build_corner_tower(keep_col, root, mats, "corner_tower_FR",  1.0, -1.0),
        build_corner_tower(keep_col, root, mats, "corner_tower_BL", -1.0,  1.0),
        build_corner_tower(keep_col, root, mats, "corner_tower_BR",  1.0,  1.0),
    ]
    walls = build_bastion_walls(keep_col, root, mats)
    gatehouse, portcullis, hearth = build_gatehouse(keep_col, root, mats)
    bay, lantern = build_receiving_bay(keep_col, root, mats)
    roof, banners = build_roof_and_banners(keep_col, root, mats)
    pad, clamps, beacons = build_balloon_pad(keep_col, root, mats)

    all_meshes = [plinth, *towers, walls, gatehouse, portcullis, hearth, bay, lantern, roof, *banners, pad, *clamps, *beacons]

    bpy.context.view_layer.update()
    mn = V((1e9, 1e9, 1e9))
    mx = V((-1e9, -1e9, -1e9))
    total_verts = 0
    total_tris = 0
    for ob in all_meshes:
        me = ob.data
        total_verts += len(me.vertices)
        total_tris += sum(max(0, len(p.vertices) - 2) for p in me.polygons)
        xf = ob.matrix_world
        for v in me.vertices:
            w = xf @ v.co
            mn.x = min(mn.x, w.x); mn.y = min(mn.y, w.y); mn.z = min(mn.z, w.z)
            mx.x = max(mx.x, w.x); mx.y = max(mx.y, w.y); mx.z = max(mx.z, w.z)

    print(
        f"BUILT keep: {len(all_meshes)} meshes, {total_verts} verts, {total_tris} tris | "
        f"bounds min=({mn.x:.3f}, {mn.y:.3f}, {mn.z:.3f}) max=({mx.x:.3f}, {mx.y:.3f}, {mx.z:.3f}) "
        f"size=({mx.x - mn.x:.3f} x {mx.y - mn.y:.3f} x {mx.z - mn.z:.3f})"
    )
    assert mn.x >= -4.90 and mx.x <= 4.90 and mn.y >= -4.90 and mx.y <= 4.90, f"Keep exceeded 9.8x9.8 footprint: {mn}..{mx}"
    assert mn.z >= -0.005 and mx.z < 9.5, f"Keep Z bounds out of spec: {mn.z}..{mx.z}"

    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    bpy.context.preferences.filepaths.save_version = 0
    for screen in bpy.data.screens:
        for area in screen.areas:
            if area.type == "VIEW_3D":
                view = area.spaces.active
                view.shading.type = "MATERIAL"
                view.overlay.show_overlays = False
                view.region_3d.view_distance = 19.5
                view.region_3d.view_location = (0,0,3.2)
                view.region_3d.view_perspective = "ORTHO"
                view.region_3d.view_rotation = V((-12,-17,10)).to_track_quat("Z","Y")
    bpy.ops.wm.save_as_mainfile(filepath=OUT, compress=True)
    print("SAVED", OUT)


if __name__ == "__main__":
    build_keep()
