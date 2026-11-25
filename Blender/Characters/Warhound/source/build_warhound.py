"""Build, rig, animate, export, and render the Arthurian Warhound in Blender 4.5.

Usage (background Blender):
    blender -b --python source/build_warhound.py
    blender -b --python source/build_warhound.py -- --no-render
    blender -b --python source/build_warhound.py -- --no-export

Outputs:
    source/warhound.blend
    export/warhound.glb
    preview/warhound_hero.png
    preview/warhound_turnaround.png
    preview/warhound_lineup.png
"""
from __future__ import annotations

import argparse
from math import cos, pi, radians, sin
from pathlib import Path
import sys

import bmesh
import bpy
from mathutils import Euler, Matrix, Vector


PACKAGE = Path(__file__).resolve().parents[1]
SOURCE_BLEND = PACKAGE / "source" / "warhound.blend"
EXPORT_GLB = PACKAGE / "export" / "warhound.glb"
PREVIEW_DIR = PACKAGE / "preview"
ROUND_TABLE_GLB = PACKAGE / "export" / "round_table_marine.glb"

ARMATURE_NAME = "warhound_rig"
ASSET_COLLECTION = "WARHOUND_ASSET"
PRESENTATION_COLLECTION = "PRESENTATION_NOT_EXPORTED"
ROOT_NAME = "Warhound"
RUN_SUBSAMPLES = 4


# ---------------------------------------------------------------------------
# Math & Interpolation Helpers
# ---------------------------------------------------------------------------

def smooth01(t: float) -> float:
    t = max(0.0, min(1.0, t))
    return t * t * (3.0 - 2.0 * t)


def smooth_range(val: float, lo: float, hi: float) -> float:
    if abs(hi - lo) < 1e-8:
        return 1.0 if val >= hi else 0.0
    return smooth01((val - lo) / (hi - lo))


def lerp(a: float, b: float, t: float) -> float:
    return a + (b - a) * t


def sample_curve(knots: list[tuple[float, float]], x: float) -> float:
    if x <= knots[0][0]:
        return knots[0][1]
    if x >= knots[-1][0]:
        return knots[-1][1]
    for (x0, y0), (x1, y1) in zip(knots, knots[1:]):
        if x <= x1:
            t = (x - x0) / max(1e-8, x1 - x0)
            return lerp(y0, y1, smooth01(t))
    return knots[-1][1]


# ---------------------------------------------------------------------------
# Materials (exact Principled BSDF values matched to round_table_marine.blend)
# ---------------------------------------------------------------------------

MATERIAL_SPECS = {
    "Ivory_Armor":         ((0.79, 0.77, 0.68), 0.30, 0.43, None, 0.0),
    "Satin_Silver":        ((0.69, 0.72, 0.73), 0.55, 0.40, None, 0.0),
    "Recessed_Steel":      ((0.25, 0.29, 0.32), 0.65, 0.43, None, 0.0),
    "Heraldic_Brass":      ((0.71, 0.44, 0.12), 0.65, 0.37, None, 0.0),
    "team_color":          ((0.032, 0.081, 0.35), 0.10, 0.55, None, 0.0),
    "team_color_shadow":   ((0.013, 0.033, 0.18), 0.04, 0.70, None, 0.0),
    "Flexible_Undersuit":  ((0.028, 0.035, 0.044), 0.05, 0.65, None, 0.0),
    "Harness_Leather":     ((0.044, 0.034, 0.027), 0.00, 0.64, None, 0.0),
    "Rifle_Parkerized":    ((0.058, 0.073, 0.083), 0.65, 0.38, None, 0.0),
    "Visor_Amber":         ((0.98, 0.55, 0.14), 0.14, 0.22, (1.0, 0.40, 0.085), 1.45),
    "Hound_Coat_Dark":     ((0.041, 0.050, 0.064), 0.00, 0.80, None, 0.0),
    "Hound_Muzzle_Brown":  ((0.090, 0.048, 0.038), 0.00, 0.75, None, 0.0),
    "Hound_Inner_Ear":     ((0.090, 0.048, 0.040), 0.00, 0.85, None, 0.0),
    "Hound_Nose_Claws":    ((0.013, 0.012, 0.014), 0.01, 0.57, None, 0.0),
}


def build_materials() -> dict[str, bpy.types.Material]:
    mats = {}
    for name, (color, metal, rough, em_color, em_str) in MATERIAL_SPECS.items():
        mat = bpy.data.materials.new(name)
        mat.diffuse_color = (*color, 1.0)
        mat.use_nodes = True
        bsdf = mat.node_tree.nodes["Principled BSDF"]
        bsdf.inputs["Base Color"].default_value = (*color, 1.0)
        bsdf.inputs["Metallic"].default_value = metal
        bsdf.inputs["Roughness"].default_value = rough
        if em_color is not None and em_str > 0.0:
            bsdf.inputs["Emission Color"].default_value = (*em_color, 1.0)
            bsdf.inputs["Emission Strength"].default_value = em_str
        mats[name] = mat
    return mats


# ---------------------------------------------------------------------------
# Mesh Construction Primitives (Watertight, Flat-Shaded, Consistent Normals)
# ---------------------------------------------------------------------------

def finalize_mesh_object(
    collection: bpy.types.Collection,
    parent: bpy.types.Object,
    name: str,
    verts: list[tuple[float, float, float] | Vector],
    faces: list[tuple[int, ...]],
    face_mats: list[str],
    mats: dict[str, bpy.types.Material],
    source_component: str = "body",
    rig_hint: str | None = None,
    recalc_normals: bool = True,
) -> bpy.types.Object:
    mesh = bpy.data.meshes.new(name)
    pt_list = [(float(v[0]), float(v[1]), float(v[2])) for v in verts]
    mesh.from_pydata(pt_list, [], faces)
    unique_mats = list(dict.fromkeys(face_mats))
    for m_name in unique_mats:
        mesh.materials.append(mats[m_name])
    mat_idx = {m_name: idx for idx, m_name in enumerate(unique_mats)}
    for poly, m_name in zip(mesh.polygons, face_mats):
        poly.material_index = mat_idx[m_name]
        poly.use_smooth = False
    if recalc_normals:
        bm = bmesh.new()
        bm.from_mesh(mesh)
        bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
        bm.to_mesh(mesh)
        bm.free()
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    collection.objects.link(obj)
    obj.parent = parent
    obj["source_component"] = source_component
    if rig_hint:
        obj["rig_hint"] = rig_hint
    return obj


class MeshBuilder:
    """Accumulates multiple sub-solids into one clean flat-shaded mesh object."""

    def __init__(self, name: str, source_component: str = "body", rig_hint: str | None = None):
        self.name = name
        self.source_component = source_component
        self.rig_hint = rig_hint
        self.verts: list[Vector] = []
        self.faces: list[tuple[int, ...]] = []
        self.face_mats: list[str] = []

    def add_loft(
        self,
        rings: list[list[Vector]],
        ring_mats: list[str] | str,
        cap_start: bool | str = True,
        cap_end: bool | str = True,
        per_quad_mat_fn=None,
    ) -> None:
        base = len(self.verts)
        n = len(rings[0])
        for ring in rings:
            assert len(ring) == n
            for p in ring:
                self.verts.append(Vector(p))

        for i in range(len(rings) - 1):
            default_mat = ring_mats if isinstance(ring_mats, str) else ring_mats[i]
            for j in range(n):
                k = (j + 1) % n
                a = base + i * n + j
                b = base + i * n + k
                c = base + (i + 1) * n + k
                d = base + (i + 1) * n + j
                self.faces.append((a, b, c, d))
                m = per_quad_mat_fn(i, j, n) if per_quad_mat_fn else default_mat
                self.face_mats.append(m)

        if cap_start:
            m_start = cap_start if isinstance(cap_start, str) else (
                ring_mats if isinstance(ring_mats, str) else ring_mats[0]
            )
            center = sum((self.verts[base + j] for j in range(n)), Vector()) / n
            c_idx = len(self.verts)
            self.verts.append(center)
            for j in range(n):
                k = (j + 1) % n
                self.faces.append((base + k, base + j, c_idx))
                self.face_mats.append(m_start)

        if cap_end:
            last = base + (len(rings) - 1) * n
            m_end = cap_end if isinstance(cap_end, str) else (
                ring_mats if isinstance(ring_mats, str) else ring_mats[-1]
            )
            center = sum((self.verts[last + j] for j in range(n)), Vector()) / n
            c_idx = len(self.verts)
            self.verts.append(center)
            for j in range(n):
                k = (j + 1) % n
                self.faces.append((last + j, last + k, c_idx))
                self.face_mats.append(m_end)

    def add_thick_patch(
        self,
        grid: list[list[Vector]],
        thickness: float,
        normal_fn,
        front_mat: str,
        back_mat: str | None = None,
        rim_mat: str | None = None,
        front_cell_mat_fn=None,
    ) -> None:
        rows = len(grid)
        cols = len(grid[0])
        if back_mat is None:
            back_mat = front_mat
        if rim_mat is None:
            rim_mat = back_mat

        base = len(self.verts)
        count = rows * cols
        for r in range(rows):
            for c in range(cols):
                self.verts.append(Vector(grid[r][c]))
        for r in range(rows):
            for c in range(cols):
                p = Vector(grid[r][c])
                n = Vector(normal_fn(r, c, p)).normalized()
                self.verts.append(p - n * thickness)

        def fidx(r: int, c: int) -> int:
            return base + r * cols + c

        def bidx(r: int, c: int) -> int:
            return base + count + r * cols + c

        for r in range(rows - 1):
            for c in range(cols - 1):
                q_front = (fidx(r, c), fidx(r, c + 1), fidx(r + 1, c + 1), fidx(r + 1, c))
                q_back = (bidx(r, c), bidx(r + 1, c), bidx(r + 1, c + 1), bidx(r, c + 1))
                self.faces.append(q_front)
                fm = front_cell_mat_fn(r, c) if front_cell_mat_fn else front_mat
                self.face_mats.append(fm)
                self.faces.append(q_back)
                self.face_mats.append(back_mat)

        border: list[tuple[int, int]] = []
        for c in range(cols):
            border.append((0, c))
        for r in range(1, rows):
            border.append((r, cols - 1))
        for c in range(cols - 2, -1, -1):
            border.append((rows - 1, c))
        for r in range(rows - 2, 0, -1):
            border.append((r, 0))

        for i in range(len(border)):
            r0, c0 = border[i]
            r1, c1 = border[(i + 1) % len(border)]
            self.faces.append((fidx(r1, c1), fidx(r0, c0), bidx(r0, c0), bidx(r1, c1)))
            self.face_mats.append(rim_mat)

    def add_prism(self, polygon_2d: list[tuple[float, float]], y_back: float, y_front: float, xf: Matrix, mat: str) -> None:
        base = len(self.verts)
        n = len(polygon_2d)
        for x, z in polygon_2d:
            self.verts.append(xf @ Vector((x, y_front, z)))
        for x, z in polygon_2d:
            self.verts.append(xf @ Vector((x, y_back, z)))
        c_front = sum((self.verts[base + i] for i in range(n)), Vector()) / n
        c_back = sum((self.verts[base + n + i] for i in range(n)), Vector()) / n
        if_c = len(self.verts)
        self.verts.append(c_front)
        ib_c = len(self.verts)
        self.verts.append(c_back)
        for i in range(n):
            j = (i + 1) % n
            self.faces.append((base + i, base + j, if_c))
            self.face_mats.append(mat)
            self.faces.append((base + n + j, base + n + i, ib_c))
            self.face_mats.append(mat)
            self.faces.append((base + j, base + i, base + n + i, base + n + j))
            self.face_mats.append(mat)

    def add_box(self, center: Vector, half_extents: Vector, mat: str, rot: Matrix | None = None, bevel_ratio: float = 0.0) -> None:
        bm = bmesh.new()
        bmesh.ops.create_cube(bm, size=1.0)
        for v in bm.verts:
            v.co.x *= half_extents.x * 2.0
            v.co.y *= half_extents.y * 2.0
            v.co.z *= half_extents.z * 2.0
        if bevel_ratio > 0.0:
            amt = min(half_extents.x, half_extents.y, half_extents.z) * bevel_ratio
            bmesh.ops.bevel(bm, geom=list(bm.edges), offset=amt, segments=1, affect="EDGES")
        xf = Matrix.Translation(center) @ (rot.to_4x4() if rot is not None else Matrix.Identity(4))
        bm.verts.ensure_lookup_table()
        base = len(self.verts)
        for v in bm.verts:
            self.verts.append(xf @ v.co)
        for f in bm.faces:
            self.faces.append(tuple(base + v.index for v in f.verts))
            self.face_mats.append(mat)
        bm.free()

    def build(self, collection, parent, mats) -> bpy.types.Object:
        return finalize_mesh_object(
            collection, parent, self.name,
            self.verts, self.faces, self.face_mats, mats,
            source_component=self.source_component,
            rig_hint=self.rig_hint,
        )


def add_starburst_and_sword(
    mb: MeshBuilder,
    center: Vector,
    outward: Vector,
    up_hint: Vector,
    scale: float,
    star_mat: str = "Heraldic_Brass",
    sword_mat: str = "Ivory_Armor",
) -> None:
    normal = outward.normalized()
    up = (up_hint - normal * up_hint.dot(normal)).normalized()
    right = up.cross(normal).normalized()

    # The raised centre gives each gold ray a separate polished facet.
    def relief(outline, apex, material):
        base = len(mb.verts)
        for depth in (-0.004, 0.000):
            mb.verts.extend(center + scale * (right*x + up*z + normal*depth) for x, z in outline)
        count = len(outline)
        mb.verts.append(center + scale * (right*apex[0] + up*apex[1] + normal*0.0055))
        peak = base + 2 * count
        # Fan the back from a point inside this concave star so triangulation is deterministic.
        mb.verts.append(center + scale * (right*apex[0] + up*apex[1] - normal*0.004))
        for i in range(count):
            j = (i + 1) % count
            mb.faces.extend(((base+i, base+j, base+count+j, base+count+i),
                             (base+count+i, base+count+j, peak), (base+j, base+i, peak+1)))
            mb.face_mats.extend((material, material, material))

    star = []
    for i in range(16):
        angle = 2 * pi * i / 16
        radius = 0.024 if i % 4 == 0 else (0.018 if i % 2 == 0 else 0.0052)
        star.append((sin(angle)*radius, 0.023 + cos(angle)*radius))
    relief(star, (0, 0.023), star_mat)
    blade = [(-0.003, 0.006), (0.003, 0.006), (0.007, 0.002), (0.0044, -0.001),
             (0.0033, -0.038), (0, -0.058), (-0.0033, -0.038), (-0.0044, -0.001), (-0.007, 0.002)]
    relief(blade, (0.0, -0.003), sword_mat)


# ---------------------------------------------------------------------------
# Anatomical Cross-Section Helpers
# ---------------------------------------------------------------------------

def canine_section(
    center: Vector,
    rx: float,
    rz_top: float,
    rz_bot: float,
    pitch_deg: float = 0.0,
    yaw_deg: float = 0.0,
    n: int = 12,
    keel_sharpness: float = 0.25,
    back_flatness: float = 0.12,
) -> list[Vector]:
    """Generate a vertical X/Z cross-section ring (tilt via pitch_deg only where spline turns up)."""
    rot = Euler((radians(pitch_deg), 0.0, radians(yaw_deg)), "XYZ").to_matrix()
    pts = []
    for j in range(n):
        a = 2.0 * pi * j / n
        sa, ca = sin(a), cos(a)
        width_mod = 1.0 - keel_sharpness * max(0.0, -ca) + back_flatness * max(0.0, ca) * 0.25
        lx = rx * sa * width_mod
        if ca >= 0.0:
            lz = rz_top * (ca ** (1.0 - back_flatness * 0.4))
        else:
            lz = -rz_bot * ((-ca) ** (1.0 + keel_sharpness * 0.35))
        pts.append(center + rot @ Vector((lx, 0.0, lz)))
    return pts


def elliptical_ring(
    center: Vector,
    tangent_dir: Vector,
    up_hint: Vector,
    rx: float,
    rz: float,
    n: int = 10,
    squash_top: float = 1.0,
    squash_bot: float = 1.0,
) -> list[Vector]:
    fwd = tangent_dir.normalized()
    side = fwd.cross(up_hint)
    if side.length_squared < 1e-6:
        side = Vector((1.0, 0.0, 0.0))
    else:
        side.normalize()
    up = side.cross(fwd).normalized()
    pts = []
    for j in range(n):
        a = 2.0 * pi * j / n
        sa, ca = sin(a), cos(a)
        mod = squash_top if ca >= 0 else squash_bot
        pts.append(center + side * (rx * sa) + up * (rz * ca * mod))
    return pts


# ---------------------------------------------------------------------------
# 1. Warhound Organic Body, Neck & Tail
# ---------------------------------------------------------------------------

def build_body_mesh(collection, parent, mats) -> bpy.types.Object:
    mb = MeshBuilder("Warhound_Body", source_component="body")

    # Sculpted canine torso: tucked inside cuirass/breastplate at front (-0.49..-0.28) so zero coat clips through plates
    torso_specs = [
        ((0.0,  0.565, 0.725), 0.068, 0.068, 0.068,  26.0, 0.08),  # 0 rump tip
        ((0.0,  0.505, 0.719), 0.117, 0.096, 0.129,  21.0, 0.12),  # croup below the tail
        ((0.0,  0.390, 0.727), 0.142, 0.111, 0.156,   9.0, 0.14),  # gluteal swell
        ((0.0,  0.240, 0.734), 0.129, 0.108, 0.134,   0.0, 0.22),  # upward abdominal tuck
        ((0.0,  0.085, 0.728), 0.122, 0.118, 0.138,  -4.0, 0.26),  # 4 tucked waist
        ((0.0, -0.105, 0.715), 0.142, 0.145, 0.195,  -8.0, 0.30),  # 5 mid-ribcage
        ((0.0, -0.285, 0.695), 0.150, 0.172, 0.205, -14.0, 0.35),  # 6 deep ribcage (inside saddle!)
        ((0.0, -0.435, 0.715), 0.132, 0.162, 0.165, -24.0, 0.30),  # 7 upper chest sternum (cleanly inside breastplate)
        ((0.0, -0.505, 0.790), 0.102, 0.115, 0.115, -46.0, 0.15),  # 8 lower neck base (cleanly inside gorget)
        ((0.0, -0.547, 0.895), 0.099, 0.111, 0.095, -61.0, 0.10),
        ((0.0, -0.565, 0.956), 0.106, 0.107, 0.101, -62.0, 0.08),
        ((0.0, -0.580, 1.015), 0.095, 0.102, 0.084, -67.0, 0.06),
        ((0.0, -0.600, 1.072), 0.076, 0.084, 0.073, -78.0, 0.05),
    ]
    rings = [
        canine_section(Vector(c), rx, rzt, rzb, pitch, 0.0, n=12, keel_sharpness=ks)
        for c, rx, rzt, rzb, pitch, ks in torso_specs
    ]
    mb.add_loft(rings, "Hound_Coat_Dark", cap_start="Hound_Coat_Dark", cap_end="Hound_Coat_Dark")

    # Sabre tail
    tail_knots = [
        (Vector((0.0, 0.499, 0.747)), 0.049, 0.051),
        (Vector((0.0, 0.561, 0.686)), 0.043, 0.046),
        (Vector((0.0, 0.634, 0.597)), 0.035, 0.041),
        (Vector((0.0, 0.716, 0.456)), 0.030, 0.034),
        (Vector((0.0, 0.789, 0.391)), 0.025, 0.027),
        (Vector((0.0, 0.864, 0.390)), 0.018, 0.019),
        (Vector((0.0, 0.940, 0.415)), 0.005, 0.006),
    ]
    tail_rings = []
    for idx, (pt, rx, rz) in enumerate(tail_knots):
        fwd = (tail_knots[idx + 1][0] - pt) if idx < len(tail_knots) - 1 else (pt - tail_knots[idx - 1][0])
        tail_rings.append(elliptical_ring(pt, fwd, Vector((0, 0, 1)), rx, rz, n=8))
    mb.add_loft(tail_rings, "Hound_Coat_Dark", cap_start="Hound_Coat_Dark", cap_end="Hound_Coat_Dark")

    body = mb.build(collection, parent, mats)
    body["torso_ring_count"] = len(torso_specs)
    body["torso_ring_size"] = len(rings[0])
    return body


# ---------------------------------------------------------------------------
# 2. Head, Solid 3D Cranium & Muzzle, Jaw & Alert Ears
# ---------------------------------------------------------------------------

def build_head_mesh(collection, parent, mats) -> bpy.types.Object:
    mb = MeshBuilder("Warhound_Head", source_component="head", rig_hint="head")

    # Nasal bridge, zygomatic arch, upper flews. The lip rises at the mouth corner.
    stations = [
        # depth, height, half-width, crown and lower-lip depth
        (-0.512, 1.061, 0.068, 0.083, 0.069),
        (-0.565, 1.073, 0.096, 0.092, 0.083),
        (-0.625, 1.076, 0.104, 0.088, 0.091),
        (-0.678, 1.063, 0.098, 0.078, 0.082),
        (-0.709, 1.051, 0.089, 0.063, 0.063),
        (-0.735, 1.042, 0.082, 0.052, 0.046),
        (-0.757, 1.039, 0.074, 0.045, 0.038),
        (-0.782, 1.031, 0.065, 0.040, 0.040),
        (-0.817, 1.029, 0.058, 0.034, 0.044),
        (-0.845, 1.028, 0.050, 0.029, 0.041),
        (-0.868, 1.031, 0.040, 0.023, 0.031),
        (-0.881, 1.033, 0.030, 0.018, 0.022),
    ]
    half_contour = [(0, 1), (0.57, 0.91), (0.90, 0.52), (1, 0.02),
                    (0.96, -0.39), (0.87, -0.69), (0.77, -0.82), (0.48, -0.98), (0, -1)]
    contour = half_contour + [(-x, z) for x, z in reversed(half_contour[1:-1])]
    rings = [[Vector((x * w, y, h + z * (top if z >= 0 else drop))) for x, z in contour]
             for y, h, w, top, drop in stations]

    def muzzle_material(i, j, n):
        if i < 3 or (i == 3 and j in (0, 1, 14, 15)):
            return "Hound_Coat_Dark"
        if i in (4, 5, 6) and j in (5, 10):
            return "Hound_Coat_Dark"
        return "Hound_Muzzle_Brown"

    mb.add_loft(rings, "Hound_Muzzle_Brown", cap_start="Hound_Coat_Dark",
                cap_end="Hound_Muzzle_Brown", per_quad_mat_fn=muzzle_material)

    # A distinct, bevelled nasal pad. Broad upper lobes narrow into the philtrum.
    nose_contour = [(0, 0.70), (0.58, 1), (0.92, 0.67), (1, 0.20), (0.86, -0.22),
                    (0.44, -0.69), (0, -1), (-0.44, -0.69), (-0.86, -0.22),
                    (-1, 0.20), (-0.92, 0.67), (-0.58, 1)]
    nose = []
    for y, h, w, z_radius in [(-0.853, 1.040, 0.033, 0.019),
                               (-0.872, 1.040, 0.041, 0.022),
                               (-0.889, 1.038, 0.036, 0.020),
                               (-0.896, 1.037, 0.029, 0.015)]:
        nose.append([Vector((x * w, y + abs(x) * 0.003, h + z * z_radius)) for x, z in nose_contour])
    mb.add_loft(nose, "Hound_Nose_Claws", cap_start="Hound_Nose_Claws", cap_end="Hound_Nose_Claws")

    jaw_first = len(mb.verts)
    jaw_stations = [
        (-0.645, 1.004, 0.068, 0.035, 0.035),
        (-0.695, 0.993, 0.074, 0.028, 0.035),
        (-0.738, 0.987, 0.063, 0.022, 0.028),
        (-0.765, 0.985, 0.057, 0.021, 0.026),
        (-0.809, 0.981, 0.047, 0.019, 0.022),
        (-0.842, 0.983, 0.038, 0.017, 0.017),
        (-0.866, 0.996, 0.024, 0.011, 0.014),
        (-0.878, 1.006, 0.014, 0.010, 0.008),
    ]
    jaw = [canine_section(Vector((0, y, h)), w, top, drop, n=12, keel_sharpness=0.18)
           for y, h, w, top, drop in jaw_stations]
    mb.add_loft(jaw, "Hound_Muzzle_Brown", cap_start="Hound_Coat_Dark", cap_end="Hound_Muzzle_Brown",
                per_quad_mat_fn=lambda i, j, n: "Hound_Coat_Dark" if i == 0 or j in (0, 11) else "Hound_Muzzle_Brown")

    # Forward/outward facing ear cups. The dark rolled margin surrounds a recessed pinna.
    ear_starts = []
    for side in (-1, 1):
        ear_starts.append(len(mb.verts))
        yaw = radians(16)
        across = Vector((side * cos(yaw), sin(yaw), 0))
        forward = Vector((side * sin(yaw), -cos(yaw), 0))
        ear = []
        for x, y, z, w, depth in [
            (0.068, -0.576, 1.133, 0.043, 0.019),
            (0.077, -0.577, 1.174, 0.052, 0.025),
            (0.081, -0.580, 1.211, 0.046, 0.025),
            (0.087, -0.584, 1.249, 0.033, 0.021),
            (0.091, -0.590, 1.292, 0.015, 0.012),
            (0.093, -0.596, 1.320, 0.002, 0.003),
        ]:
            center = Vector((side * x, y, z))
            edge = [(-1, 0.24), (-0.77, 0.80), (-0.59, 0.53), (-0.12, 0.02),
                    (0.49, 0.36), (0.75, 0.72), (1, 0.20), (0.75, -0.66),
                    (0.15, -1), (-0.55, -0.82)]
            ear.append([center + across * (a * w) + forward * (b * depth) for a, b in edge])
        mb.add_loft(ear, "Hound_Coat_Dark", cap_start="Hound_Coat_Dark", cap_end="Hound_Coat_Dark",
                    per_quad_mat_fn=lambda i, j, n: "Hound_Inner_Ear" if j in (2, 3, 4) and i < 4 else "Hound_Coat_Dark")

    obj = mb.build(collection, parent, mats)
    obj["deform_part_starts"] = [jaw_first, *ear_starts]
    return obj

# ---------------------------------------------------------------------------
# 3. Seamless Quadruped Legs & Grounded 3D Paws (Z = 0.0)
# ---------------------------------------------------------------------------

def add_warhound_paw(mb, x, heel_y, size):
    """Flat bearing surface, broad metacarpus, four rounded and slightly splayed digits."""
    coat, claw = "Hound_Coat_Dark", "Hound_Nose_Claws"

    def section(dx, dy, width, top, base, count):
        # Make the bottom facet a plane so the toe pads bear weight at Z=0.
        points = []
        for j in range(count):
            a = 2 * pi * (j + 0.5) / count
            h = max(0.0, (cos(a) + 0.78) / 1.78)
            points.append(Vector((x + size * (dx + width * sin(a)),
                                  heel_y + size * dy, size * lerp(base, top, h))))
        return points

    pad = [
        section(0, 0.018, 0.030, 0.052, 0.010, 10),
        section(0, -0.005, 0.042, 0.068, 0.002, 10),
        section(0, -0.043, 0.049, 0.064, 0.000, 10),
        section(0, -0.071, 0.047, 0.040, 0.002, 10),
    ]
    mb.add_loft(pad, coat)
    for dx in (-0.036, -0.012, 0.012, 0.036):
        central = abs(dx) < 0.020
        tip = -0.131 if central else -0.119
        width = 0.0144 if central else 0.0138
        splay = 0.003 if dx > 0 else -0.003
        toe = [
            section(dx * 0.90, -0.052, width, 0.045, 0.003, 6),
            section(dx, -0.078, width * 1.1, 0.051 if central else 0.047, 0.000, 6),
            section(dx + splay, tip + 0.010, width * 0.84, 0.031, 0.000, 6),
            section(dx + splay, tip, width * 0.45, 0.015, 0.002, 6),
        ]
        mb.add_loft(toe, [coat, coat, claw], cap_start=coat, cap_end=claw)


def build_legs_mesh(collection, parent, mats) -> bpy.types.Object:
    mb = MeshBuilder("Warhound_Legs", source_component="body")
    # Transverse sections run down the limbs without rolling across the elbow or hock.
    # Each row is lateral offset, depth, height, half width, forward reach, rear reach.
    foreleg = [
        (0.118, -0.377, 0.750, 0.074, 0.092, 0.088),
        (0.128, -0.367, 0.654, 0.081, 0.098, 0.106),
        (0.133, -0.329, 0.553, 0.075, 0.090, 0.088),
        (0.132, -0.297, 0.482, 0.057, 0.064, 0.078),
        (0.130, -0.280, 0.431, 0.046, 0.056, 0.052),
        (0.129, -0.288, 0.365, 0.041, 0.046, 0.044),
        (0.128, -0.300, 0.245, 0.036, 0.039, 0.039),
        (0.128, -0.313, 0.142, 0.034, 0.038, 0.039),
        (0.128, -0.319, 0.110, 0.035, 0.039, 0.036),
        (0.128, -0.340, 0.048, 0.035, 0.037, 0.031),
        (0.128, -0.351, 0.026, 0.035, 0.032, 0.026),
    ]
    hindleg = [
        # Bury the closed top inside the croup. The muscle rolls out in profile
        # below the hip joint, with its greatest depth underneath the guard.
        (0.068, 0.410, 0.763, 0.044, 0.067, 0.069),
        (0.090, 0.413, 0.727, 0.060, 0.091, 0.093),
        (0.113, 0.407, 0.678, 0.075, 0.117, 0.116),
        (0.129, 0.377, 0.575, 0.071, 0.111, 0.122),
        (0.137, 0.323, 0.483, 0.064, 0.081, 0.109),
        (0.138, 0.312, 0.435, 0.055, 0.060, 0.086),
        (0.137, 0.369, 0.377, 0.047, 0.060, 0.085),
        (0.136, 0.435, 0.315, 0.040, 0.059, 0.071),
        (0.135, 0.499, 0.259, 0.034, 0.048, 0.046),
        (0.135, 0.519, 0.231, 0.034, 0.042, 0.037),
        (0.135, 0.512, 0.209, 0.031, 0.033, 0.034),
        (0.135, 0.503, 0.121, 0.030, 0.033, 0.032),
        (0.135, 0.494, 0.057, 0.033, 0.038, 0.036),
        (0.135, 0.478, 0.028, 0.035, 0.032, 0.027),
    ]
    for side in (-1.0, 1.0):
        for limb in (foreleg, hindleg):
            rings = []
            facets = 8 if limb is foreleg else 10
            for cx, cy, z, width, forward, rear in limb:
                ring = []
                for j in range(facets):
                    a = 2 * pi * j / facets
                    depth = forward if cos(a) >= 0 else rear
                    ring.append(Vector((side * cx + width * sin(a), cy - depth * cos(a), z)))
                rings.append(ring)
            mb.add_loft(rings, "Hound_Coat_Dark")
        add_warhound_paw(mb, side * 0.128, -0.336, 1.0)
        add_warhound_paw(mb, side * 0.135, 0.494, 0.91)

    return mb.build(collection, parent, mats)


# ---------------------------------------------------------------------------
# 4. Armor & Barding Pieces (Zero Clipping, Crisp Facets, Glowing Visor)
# ---------------------------------------------------------------------------

def build_helm_mesh(collection, parent, mats) -> bpy.types.Object:
    mb = MeshBuilder("Warhound_Helm", source_component="head", rig_hint="head")
    center_y, radius_x, radius_y = -0.626, 0.124, 0.146

    def brim_height(y):
        return 1.092 + 0.014 * (y - center_y + radius_y) / (2 * radius_y)

    # Sagittal bands travel from the front brim, over the crown, to the nape.
    # This gives the stripe continuous width and closes the exposed frontal arch.
    lateral = [-84, -70, -54, -38, -23, -10, 10, 23, 38, 54, 70, 84]
    shell = []
    for meridian in (0, 13, 28, 45, 63, 82, 100, 118, 137, 155, 171, 180):
        v = radians(meridian)
        row = []
        for degree in lateral:
            u = radians(degree)
            y = center_y - radius_y * cos(u) * cos(v)
            row.append(Vector((radius_x * sin(u), y, brim_height(y) + 0.118 * cos(u) * sin(v))))
        shell.append(row)
    mb.add_thick_patch(shell, thickness=0.009,
        normal_fn=lambda r, c, p: Vector((p.x / radius_x, (p.y - center_y) / radius_y,
                                          (p.z - brim_height(p.y)) / 0.118)),
        front_mat="Ivory_Armor", back_mat="Recessed_Steel", rim_mat="Satin_Silver",
        front_cell_mat_fn=lambda r, c: "team_color" if c == 5 else
        ("Satin_Silver" if c in (0, 10) else "Ivory_Armor"))

    # Layered cheek skirt beneath the lens. The upper wing clears the muzzle;
    # an angled lower cheek guard protects the hinge without covering the neck.
    for side in (-1, 1):
        upper = [(0.035, -0.765, 1.087), (0.073, -0.744, 1.088),
                 (0.105, -0.703, 1.090), (0.122, -0.647, 1.092),
                 (0.122, -0.605, 1.094), (0.106, -0.560, 1.095)]
        lower = [(0.048, -0.760, 1.077), (0.085, -0.742, 1.044),
                 (0.112, -0.686, 1.052), (0.119, -0.649, 1.052),
                 (0.123, -0.613, 1.011), (0.107, -0.548, 1.032)]
        rows = []
        for t in (0, 0.13, 0.60, 1):
            row = []
            for a, b in zip(lower, upper):
                x, y, z = (lerp(start, end, t) for start, end in zip(a, b))
                row.append(Vector((side * (x + (0.002 if t == 0.13 else 0)), y, z)))
            rows.append(row)
        mb.add_thick_patch(rows, thickness=0.007,
            normal_fn=lambda r, c, p: Vector((p.x / radius_x, (p.y - center_y) / radius_y, 0.12)),
            front_mat="Satin_Silver", back_mat="Recessed_Steel", rim_mat="Satin_Silver",
            front_cell_mat_fn=lambda r, c: "Recessed_Steel" if r == 0 else
            ("Ivory_Armor" if c in (0, 1, 2, 3) else "Satin_Silver"))

    def visor_band(pad, lo, hi, material, thickness):
        strip = []
        for level in (lo, hi):
            row = []
            for i in range(23):
                angle = radians(-100 + 200 * i / 22)
                y = center_y - (radius_y + pad) * cos(angle)
                row.append(Vector(((radius_x + pad) * sin(angle), y, brim_height(y) + level)))
            strip.append(row)
        mb.add_thick_patch(strip, thickness=thickness,
            normal_fn=lambda r, c, p: Vector((p.x / radius_x, (p.y - center_y) / radius_y, 0)),
            front_mat=material, back_mat="Recessed_Steel", rim_mat=material)

    visor_band(0.002, -0.0090, 0.0080, "Recessed_Steel", 0.005)
    visor_band(0.004, -0.0050, 0.0045, "Heraldic_Brass", 0.004)
    visor_band(0.006, -0.0024, 0.0024, "Visor_Amber", 0.003)

    # Flanged discs meet the visor at each temple, with a bevel around the pale inset.
    for side in (-1, 1):
        rings = []
        for radius, x in [(0.030, 0.117), (0.032, 0.128), (0.029, 0.135),
                          (0.022, 0.136), (0.019, 0.139)]:
            ring = [Vector((side * x, -0.603 + radius * cos(2 * pi * i / 12),
                            1.092 + radius * sin(2 * pi * i / 12))) for i in range(12)]
            rings.append(ring)
        mb.add_loft(rings, ["Recessed_Steel", "Recessed_Steel", "Satin_Silver", "Ivory_Armor"],
                    cap_start="Recessed_Steel", cap_end="Satin_Silver")
    return mb.build(collection, parent, mats)

def build_gorget_and_comms_meshes(collection, parent, mats) -> tuple[bpy.types.Object, bpy.types.Object]:
    mg = MeshBuilder("Warhound_Gorget", source_component="body", rig_hint="neck")

    # Dark ribbed neck seal rings (tightly fitted between neck and gorget)
    for cy, cz, rx, rzt in [
        (-0.556, 0.960, 0.107, 0.108),
        (-0.547, 0.942, 0.110, 0.109),
        (-0.538, 0.924, 0.112, 0.111),
        (-0.529, 0.906, 0.114, 0.113),
    ]:
        r0 = canine_section(Vector((0, cy, cz - 0.010)), rx * 0.99, rzt * 0.99, rzt * 0.99, pitch_deg=-63.0, n=14, keel_sharpness=0.05)
        r1 = canine_section(Vector((0, cy - 0.003, cz)), rx * 1.025, rzt * 1.025, rzt * 1.025, pitch_deg=-63.0, n=14, keel_sharpness=0.05)
        r2 = canine_section(Vector((0, cy - 0.005, cz + 0.010)), rx * 0.99, rzt * 0.99, rzt * 0.99, pitch_deg=-63.0, n=14, keel_sharpness=0.05)
        mg.add_loft([r0, r1, r2], "Flexible_Undersuit", cap_start="Flexible_Undersuit", cap_end="Flexible_Undersuit")

    # Snug Flared Ivory Gorget seating cleanly onto the upper cuirass with a thin satin brass edge trim
    g_specs = [
        (Vector((0, -0.490, 0.829)), 0.145, 0.149, 0.149, -43.0),
        (Vector((0, -0.519, 0.892)), 0.134, 0.138, 0.138, -44.0),
        (Vector((0, -0.523, 0.899)), 0.131, 0.134, 0.134, -44.0),
        (Vector((0, -0.524, 0.900)), 0.117, 0.121, 0.121, -44.0),
        (Vector((0, -0.504, 0.860)), 0.104, 0.110, 0.110, -42.0),
    ]
    g_rings = [canine_section(c, rx, rzt, rzb, pitch, n=16, keel_sharpness=0.08, back_flatness=0.1) for c, rx, rzt, rzb, pitch in g_specs]
    mg.add_loft(g_rings, ["Ivory_Armor", "Heraldic_Brass", "Satin_Silver", "Recessed_Steel"],
                cap_start="Recessed_Steel", cap_end="Recessed_Steel")
    gorget_obj = mg.build(collection, parent, mats)

    # Recon Comms Pack & Swept Antenna on Upper Withers
    mc = MeshBuilder("Warhound_Comms", source_component="equipment", rig_hint="chest")
    rot_pack = Euler((radians(-14.0), 0.0, 0.0), "XYZ").to_matrix()
    mc.add_box(Vector((0.0, -0.375, 0.910)), Vector((0.044, 0.068, 0.032)), "Rifle_Parkerized", rot=rot_pack, bevel_ratio=0.22)
    mc.add_box(Vector((0.0, -0.380, 0.940)), Vector((0.028, 0.040, 0.012)), "Recessed_Steel", rot=rot_pack, bevel_ratio=0.20)
    ant_knots = [
        (Vector((0.0, -0.370, 0.935)), 0.012, 0.012),
        (Vector((0.0, -0.374, 0.978)), 0.0085, 0.0085),
        (Vector((0.0, -0.395, 1.052)), 0.005, 0.005),
        (Vector((0.0, -0.417, 1.120)), 0.0038, 0.0038),
    ]
    ant_rings = [
        elliptical_ring(pt, (ant_knots[min(i + 1, 3)][0] - ant_knots[max(i - 1, 0)][0]), Vector((0, -1, 0)), r, r, n=8)
        for i, (pt, r, _) in enumerate(ant_knots)
    ]
    mc.add_loft(ant_rings, ["Recessed_Steel", "Rifle_Parkerized", "Rifle_Parkerized"],
                cap_start="Rifle_Parkerized", cap_end="Satin_Silver")
    comms_obj = mc.build(collection, parent, mats)

    return gorget_obj, comms_obj


def build_cuirass_mesh(collection, parent, mats) -> bpy.types.Object:
    mb = MeshBuilder("Warhound_Cuirass", source_component="body", rig_hint="chest")

    # 1) Dorsal & Upper Flank Saddle Cuirass (Y = -0.49 .. +0.23) cleanly outside torso
    nu, nv = 13, 8
    grid = []
    y_stops = [-0.490, -0.420, -0.335, -0.225, -0.105, 0.015, 0.130, 0.225]
    for yv in y_stops:
        rx = sample_curve([(-0.50, 0.145), (-0.42, 0.172), (-0.28, 0.180), (-0.10, 0.168), (0.10, 0.148), (0.24, 0.145)], yv)
        z_top = sample_curve([(-0.50, 0.918), (-0.42, 0.908), (-0.28, 0.902), (-0.10, 0.892), (0.10, 0.878), (0.24, 0.868)], yv)
        z_cen = sample_curve([(-0.50, 0.770), (-0.42, 0.735), (-0.28, 0.720), (-0.10, 0.725), (0.10, 0.735), (0.24, 0.740)], yv)
        wrap_deg = sample_curve([(-0.50, 128.0), (-0.34, 118.0), (-0.18, 86.0), (0.0, 68.0), (0.24, 62.0)], yv)
        row = []
        for iu in range(nu):
            tu = -1.0 + 2.0 * iu / (nu - 1)
            ang = tu * radians(wrap_deg)
            sx, cz = sin(ang), cos(ang)
            x = sx * rx
            z = z_cen + cz * (z_top - z_cen)
            if yv > 0.18:
                z += 0.010 * cz
            row.append(Vector((x, yv, z)))
        grid.append(row)

    mb.add_thick_patch(
        grid, thickness=0.016,
        normal_fn=lambda r, c, p: Vector((p.x, (p.y + 0.15) * 0.25, max(0.05, p.z - 0.71))),
        front_mat="Ivory_Armor", back_mat="Recessed_Steel", rim_mat="Satin_Silver",
        front_cell_mat_fn=lambda r, c: "Satin_Silver" if (r in (0, nv - 2) or c in (0, nu - 2)) else "Ivory_Armor",
    )

    # 2) Front Keel Breastplate covering the upper/lower chest cleanly outside sternum (no coat clipping!)
    nu_f, nv_f = 9, 7
    f_grid = []
    for iv in range(nv_f):
        tv = iv / (nv_f - 1)  # 0=bottom sternum keel, 1=top gorget base
        zz = lerp(0.517, 0.865, tv)
        yc = lerp(-0.497, -0.557, tv ** 0.72) - 0.016 * sin(pi * tv)
        w = lerp(0.081, 0.173, sin(pi * 0.70 * tv + 0.20))
        row = []
        for iu in range(nu_f):
            tu = -1.0 + 2.0 * iu / (nu_f - 1)
            ang = tu * radians(84.0)
            # The outer corners sweep up around the forelegs, freeing the elbows.
            hem = 0.114 * (abs(tu) ** 1.4) * ((1.0 - tv) ** 1.6)
            row.append(Vector((sin(ang) * w, yc + (1.0 - cos(ang)) * 0.066, zz + hem)))
        f_grid.append(row)

    mb.add_thick_patch(
        f_grid, thickness=0.016,
        normal_fn=lambda r, c, p: Vector((p.x * 0.7, -0.95, (p.z - 0.70) * 0.35)),
        front_mat="Ivory_Armor", back_mat="Recessed_Steel", rim_mat="Satin_Silver",
        front_cell_mat_fn=lambda r, c: "Satin_Silver" if (r == 0 or c in (0, nu_f - 2)) else "Ivory_Armor",
    )

    return mb.build(collection, parent, mats)


def build_tabard_mesh(collection, parent, mats) -> bpy.types.Object:
    mb = MeshBuilder("Warhound_Tabard", source_component="cloth", rig_hint="chest")
    # Rigid-faced heraldic pendant on the breastplate, hung from both sides of
    # the gorget. Its straight sides, tapered lower point and gold face bevel
    # remain legible in the three-quarter view.
    outline = [
        (-0.83, 0.94), (-0.56, 1.00), (0.0, 0.96), (0.56, 1.00),
        (0.83, 0.94), (1.0, 0.70), (0.92, -0.53), (0.0, -1.00),
        (-0.92, -0.53), (-1.0, 0.70),
    ]
    def breast_point(u, v, depth):
        t = (v + 1.0) * 0.5
        z = 0.442 + 0.408 * t
        y = -0.521 - 0.062 * t - 0.027 * sin(pi * t) + 0.019 * u * u
        return Vector((0.092 * u, y - depth, z))

    rings = [
        [breast_point(u * size, v * size, depth) for u, v in outline]
        for size, depth in [(0.97, -0.008), (1.0, 0.001), (0.935, 0.008),
                            (0.90, 0.0085), (0.54, 0.014)]
    ]
    mb.add_loft(rings, ["Recessed_Steel", "Heraldic_Brass", "team_color_shadow", "team_color"],
                cap_start="Harness_Leather", cap_end="team_color")

    add_starburst_and_sword(mb, center=breast_point(0.0, 0.15, 0.0175),
                            outward=Vector((0.0, -1.0, -0.10)),
                            up_hint=Vector((0, 0, 1)), scale=1.55,
                            star_mat="Heraldic_Brass", sword_mat="Heraldic_Brass")

    # Convex, turned brass studs with recessed collars seat against the ivory.
    for side in (-1.0, 1.0):
        c_pos = Vector((side * 0.141, -0.535, 0.807))
        out = Vector((side * 0.55, -0.82, 0.15)).normalized()
        right = out.cross(Vector((0, 0, 1))).normalized()
        up = right.cross(out).normalized()
        n = 16
        rings = [
            [c_pos + out * depth + (right * cos(2 * pi * i / n) + up * sin(2 * pi * i / n)) * radius for i in range(n)]
            for depth, radius in [(-0.005, 0.028), (0.001, 0.032), (0.007, 0.031),
                                  (0.013, 0.027), (0.022, 0.020), (0.027, 0.011)]
        ]
        mb.add_loft(rings, ["Recessed_Steel", "Heraldic_Brass", "Recessed_Steel",
                            "Heraldic_Brass", "Heraldic_Brass"],
                    cap_start="Recessed_Steel", cap_end="Heraldic_Brass")
    return mb.build(collection, parent, mats)


def build_pauldron_mesh(collection, parent, mats, side: float) -> bpy.types.Object:
    suffix = "L" if side > 0 else "R"
    mb = MeshBuilder(f"Warhound_Pauldron_{suffix}", source_component="body", rig_hint=f"shoulder.{suffix}")

    # Low, rounded heater shield. The forward corner meets the breast clasp,
    # while the shorter lower edge leaves the upper foreleg visible.
    outline = [
        (-1.00, 0.13), (-0.71, 0.62), (-0.31, 1.00), (0.19, 0.88),
        (0.72, 0.66), (1.00, 0.26), (0.87, -0.60), (0.48, -0.94),
        (-0.12, -0.90), (-0.81, -0.47),
    ]
    def shell_point(u, v, depth):
        y = -0.350 + 0.190 * u
        z = 0.783 + 0.143 * v
        x = 0.199 - 0.27 * (z - 0.775) - 0.038 * u * u + depth
        return Vector((side * x, y, z))

    rings = [
        [shell_point(u * size, v * size, depth) for u, v in outline]
        for size, depth in [(0.94, -0.016), (1.0, -0.004), (0.99, 0.007),
                            (0.929, 0.013), (0.91, 0.0138), (0.59, 0.024)]
    ]
    # Exposed rear lip, outward-facing gold bevel, narrow shadow line and blue crown.
    def shoulder_finish(layer, edge, _count):
        if layer == 0:
            return "Recessed_Steel"
        if layer in (1, 2) and edge in (5, 6, 7, 8, 9):
            return "Heraldic_Brass"
        return "team_color_shadow" if layer == 1 else "team_color"
    mb.add_loft(rings, "team_color", cap_start="Flexible_Undersuit", cap_end="team_color",
                per_quad_mat_fn=shoulder_finish)

    add_starburst_and_sword(mb, center=shell_point(-0.03, 0.14, 0.029),
                            outward=Vector((side, 0, 0.27)), up_hint=Vector((0, 0, 1)),
                          scale=1.47, star_mat="Heraldic_Brass", sword_mat="Heraldic_Brass")
    return mb.build(collection, parent, mats)


def build_harness_mesh(collection, parent, mats) -> bpy.types.Object:
    mb = MeshBuilder("Warhound_Harness", source_component="equipment")

    for y_c in (-0.205, -0.158, -0.111, -0.064, -0.017):
        rx = sample_curve([(-0.28, 0.155), (-0.10, 0.145), (0.08, 0.125), (0.20, 0.122)], y_c) + 0.005
        rzt = sample_curve([(-0.28, 0.175), (-0.10, 0.148), (0.08, 0.120), (0.20, 0.110)], y_c) + 0.003
        rzb = sample_curve([(-0.28, 0.212), (-0.10, 0.198), (0.08, 0.140), (0.20, 0.132)], y_c) + 0.005
        zc = sample_curve([(-0.28, 0.695), (-0.10, 0.715), (0.08, 0.728), (0.20, 0.732)], y_c)
        r0 = canine_section(Vector((0, y_c - 0.017, zc)), rx * 0.985, rzt * 0.985, rzb * 0.985, pitch_deg=-5.0, n=14, keel_sharpness=0.25)
        r1 = canine_section(Vector((0, y_c, zc)), rx * 1.03, rzt * 1.02, rzb * 1.03, pitch_deg=-5.0, n=14, keel_sharpness=0.25)
        r2 = canine_section(Vector((0, y_c + 0.017, zc)), rx * 0.985, rzt * 0.985, rzb * 0.985, pitch_deg=-5.0, n=14, keel_sharpness=0.25)
        mb.add_loft([r0, r1, r2], "Flexible_Undersuit", cap_start="Flexible_Undersuit", cap_end="Flexible_Undersuit")

    # Leather girth belt & flank brass buckles
    y_belt = 0.052
    rx_b, rzt_b, rzb_b, zc_b = 0.153, 0.153, 0.161, 0.729
    b_rings = [
        canine_section(Vector((0, y_belt - 0.028, zc_b)), rx_b * 1.00, rzt_b * 1.00, rzb_b * 1.00, pitch_deg=-5.0, n=16, keel_sharpness=0.24),
        canine_section(Vector((0, y_belt - 0.025, zc_b)), rx_b * 1.05, rzt_b * 1.05, rzb_b * 1.05, pitch_deg=-5.0, n=16, keel_sharpness=0.24),
        canine_section(Vector((0, y_belt + 0.025, zc_b)), rx_b * 1.05, rzt_b * 1.05, rzb_b * 1.05, pitch_deg=-5.0, n=16, keel_sharpness=0.24),
        canine_section(Vector((0, y_belt + 0.028, zc_b)), rx_b * 1.00, rzt_b * 1.00, rzb_b * 1.00, pitch_deg=-5.0, n=16, keel_sharpness=0.24),
    ]
    mb.add_loft(b_rings, "Harness_Leather", cap_start="Harness_Leather", cap_end="Harness_Leather")

    for side in (-1.0, 1.0):
        bx = side * 0.157
        bz = 0.680
        mb.add_box(Vector((bx, y_belt - 0.032, bz)), Vector((0.008, 0.006, 0.036)), "Heraldic_Brass")
        mb.add_box(Vector((bx, y_belt + 0.032, bz)), Vector((0.008, 0.006, 0.036)), "Heraldic_Brass")
        mb.add_box(Vector((bx, y_belt, bz + 0.031)), Vector((0.008, 0.036, 0.006)), "Heraldic_Brass")
        mb.add_box(Vector((bx, y_belt, bz - 0.031)), Vector((0.008, 0.036, 0.006)), "Heraldic_Brass")
        mb.add_box(Vector((bx + side * 0.003, y_belt - 0.008, bz)), Vector((0.005, 0.024, 0.005)), "Heraldic_Brass")

    return mb.build(collection, parent, mats)


def build_haunch_mesh(collection, parent, mats, side: float) -> bpy.types.Object:
    suffix = "L" if side > 0 else "R"
    mb = MeshBuilder(f"Warhound_Haunch_{suffix}", source_component="body", rig_hint=f"thigh.{suffix}R")

    # The plate follows the thigh's rake: clipped front shoulder, faceted cap,
    # long slanted back edge, and a near-horizontal skirt above the hock.
    outline = [
        (-1.00, 0.50), (-0.67, 0.91), (-0.17, 1.00), (0.44, 0.87),
        (0.85, 0.50), (1.00, 0.06), (0.91, -0.62), (0.60, -1.00),
        (-0.59, -0.85), (-0.86, -0.25),
    ]
    def flank_point(u, v, depth):
        z = 0.641 + 0.153 * v
        y = 0.399 + 0.127 * u - 0.047 * v
        # Turn the upper lip in over the hip. Below it the plate swells over
        # the muscle and follows it back in towards the skirt at the knee.
        lip = 0.030 * smooth_range(v, 0.40, 0.98)
        skirt = 0.012 * smooth_range(-v, 0.45, 1.00)
        x = 0.209 - 0.11 * (z - 0.64) - 0.018 * u * u - lip - skirt + depth
        return Vector((side * x, y, z))

    # The guard beds into the side of the croup on a tapered pad. Its upper
    # anchor meets the body below the trim, while the lower skirt stays free.
    anchor = [(-0.60, 0.42), (-0.43, 0.74), (0.30, 0.71), (0.51, 0.47),
              (0.46, 0.08), (0.17, -0.16), (-0.40, -0.07)]
    mount = [[flank_point(u * scale, v * scale, d) for u, v in anchor]
             for scale, d in [(0.75, -0.084), (0.96, -0.044), (1.00, -0.012)]]
    mb.add_loft(mount, "Flexible_Undersuit",
                cap_start="Flexible_Undersuit", cap_end="Flexible_Undersuit")

    rings = [[flank_point(u * size, v * size, d) for u, v in outline]
             for size, d in [(0.96, -0.014), (1.0, -0.003), (0.93, 0.007), (0.62, 0.019)]]
    def finish(i, j, n):
        if i == 0:
            return "Recessed_Steel"
        if i == 1:
            return "Heraldic_Brass" if j in (0, 1, 2, 3) else "team_color_shadow"
        return "team_color"
    mb.add_loft(rings, "team_color", cap_start="Recessed_Steel", cap_end="team_color", per_quad_mat_fn=finish)
    return mb.build(collection, parent, mats)


def build_greaves_mesh(collection, parent, mats, side: float) -> bpy.types.Object:
    suffix = "L" if side > 0 else "R"
    mb = MeshBuilder(f"Warhound_Greave_F{suffix}", source_component="body", rig_hint=f"lower_leg.F{suffix}")
    cx = side * 0.128

    # The shin has a broad lateral top, modest central ridge, and a narrower ankle.
    # Angle-dependent edge heights leave the elbow and carpus free to flex.
    shin_levels = [
        (0.151, -0.313, 0.040, 0.046),
        (0.161, -0.311, 0.044, 0.049),
        (0.257, -0.300, 0.047, 0.052),
        (0.356, -0.288, 0.053, 0.058),
        (0.412, -0.279, 0.055, 0.061),
        (0.423, -0.278, 0.052, 0.059),
    ]
    panel = []
    for i, (z, cy, width, depth) in enumerate(shin_levels):
        row = []
        for degrees in (-97, -62, -32, -10, 10, 32, 62, 97):
            a = radians(degrees)
            front = max(0.0, cos(a))
            peak = (0.014 * front + 0.013 * side * sin(a)) if i >= 4 else 0.0
            lower_edge = 0.012 * (1 - front) if i < 2 else 0.0
            ridge = 0.004 * front ** 5
            row.append(Vector((cx + width * sin(a), cy - depth * cos(a) - ridge, z + peak + lower_edge)))
        panel.append(row)
    mb.add_thick_patch(panel, 0.007,
                       normal_fn=lambda r, c, p: Vector((p.x - cx, p.y - shin_levels[r][1], 0)),
                       front_mat="Satin_Silver", back_mat="Recessed_Steel", rim_mat="Recessed_Steel")

    # Two rubber straps wrap the open rear half of the greave, visible in profile.
    for z, cy, width, depth in [(0.200, -0.305, 0.040, 0.045), (0.347, -0.290, 0.046, 0.051)]:
        band = []
        for height in (z - 0.008, z + 0.008):
            row = []
            for degrees in (84, 130, 180, 230, 276):
                a = radians(degrees)
                row.append(Vector((cx + width * sin(a), cy - depth * cos(a), height)))
            band.append(row)
        mb.add_thick_patch(band, 0.003,
                           normal_fn=lambda r, c, p: Vector((p.x - cx, p.y - cy, 0)),
                           front_mat="Flexible_Undersuit")

    # A separate ivory plate rakes forward over the pastern. The exposed band
    # above its upper rim separates it from the long silver shin.
    cuff_levels = [(0.061, -0.341, 0.039, 0.043), (0.077, -0.336, 0.041, 0.045),
                   (0.116, -0.322, 0.042, 0.045), (0.132, -0.318, 0.040, 0.043)]
    cuff = []
    for i, (z, cy, width, depth) in enumerate(cuff_levels):
        row = []
        for degrees in (-88, -53, -19, 19, 53, 88):
            a = radians(degrees)
            rim_rise = 0.009 * abs(sin(a)) if i == 0 else 0.0
            row.append(Vector((cx + width * sin(a), cy - depth * cos(a), z + rim_rise)))
        cuff.append(row)
    mb.add_thick_patch(cuff, 0.006,
                       normal_fn=lambda r, c, p: Vector((p.x - cx, p.y - cuff_levels[r][1], 0)),
                       front_mat="Ivory_Armor", back_mat="Recessed_Steel", rim_mat="Recessed_Steel")
    return mb.build(collection, parent, mats)


# ---------------------------------------------------------------------------
# 5. Quadruped Armature & Analytical Skinning
# ---------------------------------------------------------------------------

def create_rig(collection, parent) -> bpy.types.Object:
    arm_data = bpy.data.armatures.new("Warhound skeleton")
    arm_data.display_type = "STICK"
    rig = bpy.data.objects.new(ARMATURE_NAME, arm_data)
    collection.objects.link(rig)
    rig.parent = parent
    rig.show_in_front = True

    bpy.context.view_layer.objects.active = rig
    rig.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    bones = arm_data.edit_bones

    def add_bone(name: str, head, tail, parent_name: str | None = None, up=(0, 0, 1), deform: bool = True):
        b = bones.new(name)
        b.head = Vector(head)
        b.tail = Vector(tail)
        b.use_deform = deform
        if parent_name:
            b.parent = bones[parent_name]
        aim = (b.tail - b.head).normalized()
        ref = Vector(up)
        if abs(aim.dot(ref)) > 0.96:
            ref = Vector((0, -1, 0))
        b.align_roll(ref)
        return b

    add_bone("root", (0, 0, 0), (0, -0.25, 0), None, up=(0, 0, 1))
    add_bone("pelvis", (0, 0.44, 0.72), (0, 0.24, 0.73), "root")
    add_bone("spine.01", (0, 0.24, 0.73), (0, 0.00, 0.72), "pelvis")
    add_bone("spine.02", (0, 0.00, 0.72), (0, -0.20, 0.70), "spine.01")
    add_bone("chest", (0, -0.20, 0.70), (0, -0.49, 0.75), "spine.02")
    add_bone("neck", (0, -0.49, 0.75), (0, -0.59, 1.06), "chest")
    add_bone("head", (0, -0.59, 1.06), (0, -0.89, 1.03), "neck")
    add_bone("jaw", (0, -0.66, 1.00), (0, -0.87, 1.00), "head")

    for side, sfx in ((-1.0, "R"), (1.0, "L")):
        add_bone(f"ear.{sfx}", (side * 0.070, -0.576, 1.140), (side * 0.093, -0.596, 1.320), "head", up=(0, -1, 0))

    add_bone("tail.01", (0, 0.499, 0.747), (0, 0.634, 0.597), "pelvis")
    add_bone("tail.02", (0, 0.634, 0.597), (0, 0.789, 0.391), "tail.01")
    add_bone("tail.03", (0, 0.789, 0.391), (0, 0.940, 0.415), "tail.02")

    for side, sfx in ((-1.0, "R"), (1.0, "L")):
        add_bone(f"shoulder.{sfx}", (side * 0.14, -0.37, 0.73), (side * 0.16, -0.35, 0.58), "chest", up=(0, -1, 0))
        add_bone(f"upper_leg.F{sfx}", (side * 0.130, -0.365, 0.710), (side * 0.130, -0.275, 0.430), f"shoulder.{sfx}", up=(0, -1, 0))
        add_bone(f"lower_leg.F{sfx}", (side * 0.130, -0.275, 0.430), (side * 0.128, -0.312, 0.135), f"upper_leg.F{sfx}", up=(0, -1, 0))
        add_bone(f"paw.F{sfx}", (side * 0.128, -0.312, 0.135), (side * 0.128, -0.415, 0.015), f"lower_leg.F{sfx}", up=(0, 0, 1))

        add_bone(f"thigh.{sfx}R", (side * 0.128, 0.420, 0.710), (side * 0.138, 0.295, 0.440), "pelvis", up=(0, -1, 0))
        add_bone(f"shin.{sfx}R", (side * 0.138, 0.295, 0.440), (side * 0.135, 0.515, 0.235), f"thigh.{sfx}R", up=(0, -1, 0))
        add_bone(f"hock.{sfx}R", (side * 0.135, 0.515, 0.235), (side * 0.135, 0.492, 0.042), f"shin.{sfx}R", up=(0, -1, 0))
        add_bone(f"paw.{sfx}R", (side * 0.135, 0.492, 0.042), (side * 0.135, 0.415, 0.012), f"hock.{sfx}R", up=(0, 0, 1))

    bpy.ops.object.mode_set(mode="OBJECT")
    return rig


def _set_weights(obj: bpy.types.Object, rig: bpy.types.Object, weight_fn) -> None:
    groups = {}
    for v in obj.data.vertices:
        wmap = weight_fn(v.index, v.co)
        total = sum(w for w in wmap.values() if w > 0.0)
        if total <= 1e-6:
            raise ValueError(f"Zero weight on {obj.name} vert {v.index} at {tuple(v.co)}")
        for bname, w in wmap.items():
            if w <= 1e-5:
                continue
            if bname not in rig.data.bones:
                raise ValueError(f"Unknown bone {bname} referenced by {obj.name}")
            grp = groups.get(bname)
            if grp is None:
                grp = obj.vertex_groups.new(name=bname)
                groups[bname] = grp
            grp.add([v.index], w / total, "REPLACE")
    mod = obj.modifiers.new("Warhound skeleton", "ARMATURE")
    mod.object = rig
    mod.use_vertex_groups = True
    mod.use_bone_envelopes = False


def bind_warhound_meshes(rig: bpy.types.Object, objects: list[bpy.types.Object]) -> None:
    def seg(val: float, knots: list[tuple[float, str]]) -> dict[str, float]:
        if val <= knots[0][0]:
            return {knots[0][1]: 1.0}
        for (a, ba), (b, bb) in zip(knots, knots[1:]):
            if val <= b:
                if ba == bb:
                    return {ba: 1.0}
                t = smooth_range(val, a, b)
                return {ba: 1.0 - t, bb: t}
        return {knots[-1][1]: 1.0}

    for obj in objects:
        name = obj.name
        hint = obj.get("rig_hint")
        if hint:
            if name == "Warhound_Head":
                jaw_first, ear_r_first, ear_l_first = obj["deform_part_starts"]
                def head_w(idx, co: Vector):
                    if idx >= ear_r_first:
                        ear_w = smooth_range(co.z, 1.138, 1.206)
                        ear = "ear.L" if idx >= ear_l_first else "ear.R"
                        return {ear: ear_w, "head": 1.0 - ear_w}
                    if idx >= jaw_first:
                        jaw_w = smooth_range(-co.y, 0.645, 0.700)
                        return {"jaw": jaw_w, "head": 1.0 - jaw_w}
                    return {"head": 1.0}
                _set_weights(obj, rig, head_w)
            elif name == "Warhound_Cuirass":
                # The breastplate and forward saddle bear on the ribcage. The
                # back of the shell sits over the lumbar spine. Interpolate
                # only along the body's length, keeping each cross-section
                # rigid and the lower pectoral face entirely on the chest.
                saddle_bind = [(-0.33, "chest"), (-0.21, "chest"),
                               (-0.04, "spine.02"), (0.12, "spine.01"),
                               (0.28, "pelvis")]
                _set_weights(obj, rig, lambda _i, co: seg(co.y, saddle_bind))
            else:
                _set_weights(obj, rig, lambda _i, _c, h=hint: {h: 1.0})
        elif name == "Warhound_Body":
            ring_size = obj["torso_ring_size"]
            cap_start = obj["torso_ring_count"] * ring_size
            def body_w(idx, co: Vector):
                if idx >= cap_start + 2:
                    return seg(co.y, [(0.535, "pelvis"), (0.60, "tail.01"), (0.715, "tail.02"), (0.855, "tail.03")])
                # Rings wrap completely around the pitched neck. Cutting its
                # rear surface by a Y coordinate leaves isolated chest-bound
                # points in the upper neck that spike when the head reaches.
                ring = 0 if idx == cap_start else min(idx // ring_size, obj["torso_ring_count"] - 1)
                if ring >= 7:
                    return seg(ring, [(7, "chest"), (9, "neck"), (10, "neck"), (12, "head")])
                if ring < 2:
                    return {"pelvis": 1.0}
                return seg(-co.y, [(-0.46, "pelvis"), (-0.28, "pelvis"), (-0.12, "spine.01"), (0.04, "spine.02"), (0.22, "chest"), (0.50, "chest")])
            _set_weights(obj, rig, body_w)
        elif name == "Warhound_Harness":
            def harness_w(_idx, co: Vector):
                return seg(-co.y, [(-0.18, "pelvis"), (-0.06, "spine.01"), (0.08, "spine.02"), (0.20, "chest")])
            _set_weights(obj, rig, harness_w)
        elif name == "Warhound_Legs":
            def legs_w(_idx, co: Vector):
                s = "L" if co.x >= 0 else "R"
                if co.y < 0.0:
                    return seg(co.z, [(0.048, f"paw.F{s}"), (0.140, f"lower_leg.F{s}"), (0.380, f"lower_leg.F{s}"), (0.480, f"upper_leg.F{s}"), (0.660, f"upper_leg.F{s}"), (0.740, "chest")])
                return seg(co.z, [(0.045, f"paw.{s}R"), (0.120, f"hock.{s}R"), (0.220, f"hock.{s}R"), (0.270, f"shin.{s}R"), (0.410, f"shin.{s}R"), (0.475, f"thigh.{s}R"), (0.660, f"thigh.{s}R"), (0.740, "pelvis")])
            _set_weights(obj, rig, legs_w)
        else:
            raise ValueError(f"Unhandled mesh weight assignment: {name}")


# ---------------------------------------------------------------------------
# 6. NLA Animations (Rest, Run, Attack, Die)
# ---------------------------------------------------------------------------

def build_animations(rig: bpy.types.Object) -> None:
    scene = bpy.context.scene
    scene.render.fps = 24
    scene.render.fps_base = 1

    def stash(action: bpy.types.Action) -> None:
        data = rig.animation_data_create()
        data.action = None
        for t in list(data.nla_tracks):
            if t.name == action.name:
                data.nla_tracks.remove(t)
        track = data.nla_tracks.new()
        track.name = action.name
        strip = track.strips.new(action.name, int(action.frame_range[0]), action)
        strip.extrapolation = "NOTHING"
        strip.influence = 1.0
        track.mute = True
        action.use_fake_user = True

    def key_pose(pb_name: str, frame: int, rot_xyz=(0.0, 0.0, 0.0), loc=(0.0, 0.0, 0.0)) -> None:
        pb = rig.pose.bones[pb_name]
        pb.rotation_mode = "XYZ"
        pb.rotation_euler = Euler((radians(rot_xyz[0]), radians(rot_xyz[1]), radians(rot_xyz[2])), "XYZ")
        pb.location = Vector(loc)
        pb.keyframe_insert(data_path="rotation_euler", frame=frame)
        pb.keyframe_insert(data_path="location", frame=frame)

    def clear_pose() -> None:
        for pb in rig.pose.bones:
            pb.rotation_mode = "XYZ"
            pb.rotation_euler = Euler((0, 0, 0), "XYZ")
            pb.location = Vector((0, 0, 0))
            pb.scale = Vector((1, 1, 1))

    def new_action(name: str) -> bpy.types.Action:
        act = bpy.data.actions.new(name)
        rig.animation_data_create().action = act
        # Establish the whole rig's neutral pose, including otherwise-unused
        # channels. Sampling a different action must never inherit its last pose.
        clear_pose()
        for bone in rig.pose.bones:
            bone.keyframe_insert(data_path="location", frame=1)
            bone.keyframe_insert(data_path="rotation_euler", frame=1)
        return act

    act_rest = new_action("Rest")
    for f in range(1, 26, 4):
        ph = 2.0 * pi * (f - 1) / 24.0
        br = sin(ph)
        # Keep the supporting shoulder chain fixed while attention moves
        # through the neck, head, ears and tail.
        key_pose("neck", f, rot_xyz=(-1.0 * br, 0, 2.0 * sin(ph * 0.5)))
        key_pose("head", f, rot_xyz=(1.5 * br, 0, -2.5 * sin(ph * 0.5)))
        key_pose("ear.L", f, rot_xyz=(3.0 * max(0.0, sin(ph)), 0, 0))
        key_pose("ear.R", f, rot_xyz=(3.0 * max(0.0, -sin(ph)), 0, 0))
        key_pose("tail.01", f, rot_xyz=(2.0 * br, 0, 8.0 * sin(ph)))
        key_pose("tail.02", f, rot_xyz=(1.5 * br, 0, 12.0 * sin(ph - 0.5)))
    stash(act_rest)

    # Bake sagittal IK into ordinary bone channels. The ankle follows a fixed
    # world-plane target during stance; no IK controls are needed in the GLB.
    import math
    bones = rig.pose.bones
    arm_x = Vector((1.0, 0.0, 0.0))

    def translate_in_armature_space(bone, motion):
        return bone.bone.matrix_local.to_quaternion().inverted() @ Vector(motion)

    def absolute_x_rotation(bone, angle, frame):
        rest = bone.bone.matrix_local.to_quaternion()
        desired = Matrix.Rotation(angle, 3, arm_x).to_quaternion() @ rest
        # Convert the desired armature-space orientation into local pose space.
        parent_rest = bone.parent.bone.matrix_local.to_quaternion()
        rest_local = parent_rest.inverted() @ rest
        local = rest_local.inverted() @ bone.parent.matrix.to_quaternion().inverted() @ desired
        bone.rotation_mode = "XYZ"
        bone.rotation_euler = local.to_euler("XYZ", bone.rotation_euler)
        bone.keyframe_insert(data_path="rotation_euler", frame=frame)
        bpy.context.view_layer.update()

    def sagittal_angle(rest, desired):
        return math.atan2(rest.y * desired.z - rest.z * desired.y,
                          rest.y * desired.y + rest.z * desired.z)

    def solve_leg(front, side, ankle_y, ankle_z, foot_pitch, hock_pitch, frame):
        if front:
            first, second = bones["upper_leg.F" + side], bones["lower_leg.F" + side]
            foot, pole = bones["paw.F" + side], 1.0
        else:
            first, second = bones["thigh." + side + "R"], bones["shin." + side + "R"]
            foot, pole = bones["paw." + side + "R"], -1.0
        a = first.bone.tail_local - first.bone.head_local
        b = second.bone.tail_local - second.bone.head_local
        desired_end = Vector((first.head.x, ankle_y, ankle_z))
        if not front:
            hock = bones["hock." + side + "R"]
            hock_vector = hock.bone.tail_local - hock.bone.head_local
            desired_end -= Matrix.Rotation(hock_pitch, 3, arm_x) @ hock_vector
        direction = desired_end - first.head
        dy, dz = direction.y, direction.z
        target_dist = max(1.e-6, math.hypot(dy, dz))
        length_a, length_b = math.hypot(a.y, a.z), math.hypot(b.y, b.z)
        dist = min(target_dist, length_a + length_b - 1.e-6)
        uy, uz = dy / target_dist, dz / target_dist
        along = (length_a**2 - length_b**2 + dist**2) / (2.0 * dist)
        across = math.sqrt(max(0.0, length_a**2 - along**2))
        upper = Vector((a.x, uy * along - pole * uz * across, uz * along + pole * uy * across))
        lower = Vector((b.x, uy * dist - upper.y, uz * dist - upper.z))
        absolute_x_rotation(first, sagittal_angle(a, upper), frame)
        absolute_x_rotation(second, sagittal_angle(b, lower), frame)
        if not front:
            absolute_x_rotation(hock, hock_pitch, frame)
        absolute_x_rotation(foot, foot_pitch, frame)

    def paw_rest(front, side):
        name = ("paw.F" + side) if front else ("paw." + side + "R")
        return bones[name].bone.head_local

    def smooth_keys(keys, f):
        # Interpolate each authored pose without overshoot.
        for (start, *a), (end, *b) in zip(keys, keys[1:]):
            if f <= end:
                t = smooth01((f - start) / (end - start))
                return [lerp(x, y, t) for x, y in zip(a, b)]
        return keys[-1][1:]

    def ground_action(action, first, last):
        # Sample before keying corrections so adjacent keys cannot influence the
        # measurements. This grounds the *deformed mesh*, including all armor.
        meshes = [obj for obj in bpy.data.collections[ASSET_COLLECTION].all_objects
                  if obj.type == "MESH" and any(m.type == "ARMATURE" and m.object == rig for m in obj.modifiers)]
        if not meshes:
            raise ValueError("No bound meshes available for animation contact check")
        pelvis = bones["pelvis"]
        samples = []
        for frame in range(first, last + 1):
            scene.frame_set(frame)
            deps = bpy.context.evaluated_depsgraph_get()
            lowest = float("inf")
            for obj in meshes:
                evaluated = obj.evaluated_get(deps)
                world_z = evaluated.matrix_world[2]
                lowest = min(lowest, min(world_z.x * v.co.x + world_z.y * v.co.y
                                        + world_z.z * v.co.z + world_z.w for v in evaluated.data.vertices))
            samples.append((frame, lowest, pelvis.location.copy()))
        for frame, low, authored in samples:
            pelvis.location = authored + translate_in_armature_space(pelvis, (0, 0, -low))
            pelvis.keyframe_insert(data_path="location", frame=frame)
        print(f"{action.name}: baked {len(samples)} mesh contacts; original min/max height "
              f"{min(x[1] for x in samples):.4f} to {max(x[1] for x in samples):.4f} m")

    act_run = new_action("Run")
    # A rotary gallop in place, authored at four metres/second. Ground speed
    # belongs to the actor. The two hind contacts drive the extended suspension;
    # the two fore contacts brake, then vault the body into the gathered flight.
    period = 16
    stride = 4.0 * period / scene.render.fps
    stance = 4.0 / period
    touchdown = {(False, "R"): 0, (False, "L"): 1.5,
                 (True, "L"): 8, (True, "R"): 9.5}

    def swing_path(keys, u):
        # Cubic Hermite interpolation with explicit end velocities. A paw is
        # still traveling backward in body space when it leaves or meets turf.
        for (t0, y0, v0), (t1, y1, v1) in zip(keys, keys[1:]):
            if u <= t1:
                dt = t1 - t0
                q = (u - t0) / dt
                h = smooth01(q)
                return ((1 - h) * y0 + h * y1
                        + dt * (v0 * q * (1 - q)**2 - v1 * q*q * (1 - q)))
        return keys[-1][1]

    half_sweep = stride * stance / 2
    ground_velocity = stride * (1 - stance)
    fore_stride = [(0, half_sweep, ground_velocity), (.13, .405, 0),
                   (.46, .020, -1.83), (.79, -.475, 0), (1, -half_sweep, ground_velocity)]
    hind_stride = [(0, half_sweep, ground_velocity), (.19, .475, 0),
                   (.50, .103, -1.70), (.85, -.341, 0), (1, -half_sweep, ground_velocity)]
    fore_height = [(0, 0, 0), (.20, .165, 1.05), (.38, .29, 0),
                   (.66, .17, -.60), (.84, .074, -.55), (1, 0, 0)]
    hind_height = [(0, 0, 0), (.18, .12, 1.10), (.44, .305, 0),
                   (.69, .20, -.72), (.87, .063, -.65), (1, 0, 0)]

    # Use the actual resting toe geometry to roll a paw off the ground. The
    # ankle rises about the front toe instead of driving the digits below it.
    foot_points = {}
    leg_mesh = bpy.data.objects["Warhound_Legs"].data
    for front in (True, False):
        rest = paw_rest(front, "L")
        foot_points[front] = [(v.co.y - rest.y, v.co.z - rest.z)
                              for v in leg_mesh.vertices
                              if v.co.x > 0 and (v.co.y < 0) == front and v.co.z < .048]

    for tick in range(period * RUN_SUBSAMPLES + 1):
        f = 1 + tick / RUN_SUBSAMPLES
        scene.frame_set(math.floor(f), subframe=f % 1)
        t = ((f - 1) % period) / period
        theta = 2 * pi * (t - .405)
        stretch = cos(theta)
        # Pelvis drops as each support pair accepts weight and rises toward
        # each suspension. A rounded lumbar spine uncurls with the hind push.
        height = -.084 + .054 * cos(2 * theta)
        pelvis = bones["pelvis"]
        pelvis.location = translate_in_armature_space(pelvis, (0, 0, height))
        pelvis.keyframe_insert(data_path="location", frame=f)
        axial = [("pelvis", 13 * stretch), ("spine.01", 8 * cos(theta-.16)),
                 ("spine.02", -5 * cos(theta-.20)), ("chest", -12 * cos(theta-.22)),
                 ("neck", 24 + 10 * cos(theta-.35)), ("head", 5 - 5 * cos(theta-.42)),
                 ("tail.01", 21 + 9 * cos(theta+.2)), ("tail.02", 29 + 12 * cos(theta-.23)),
                 ("tail.03", 8 + 13 * cos(theta-.51))]
        for name, degrees in axial:
            absolute_x_rotation(bones[name], radians(degrees), f)
        key_pose("ear.L", f, rot_xyz=(-7 + 4 * sin(theta-.38), 0, 0))
        key_pose("ear.R", f, rot_xyz=(-7 + 4 * sin(theta-.50), 0, 0))

        for (front, side), landing in touchdown.items():
            p = (t - landing / period) % 1.0
            if p <= stance:
                load = p / stance
                offset = stride * (p - stance * .5)
                lift = 0.0
                pitch_deg = (29 if front else 34) * smooth01((load - .47) / .53)
            else:
                u = (p - stance) / (1 - stance)
                offset = swing_path(fore_stride if front else hind_stride, u)
                lift = swing_path(fore_height if front else hind_height, u)
                toeoff = 29 if front else 34
                fold = 64 if front else 40
                pitch_deg = swing_path([(0, toeoff, 0), (.24, fold, 0), (.66, -8, 0),
                                        (.85, -4, 25), (1, 0, 0)], u)
            pitch = radians(pitch_deg)
            if front:
                # A dog's mobile scapula moves the humerus origin with the
                # reaching foreleg. The shoulder plate follows the same bone.
                shoulder = bones["shoulder." + side]
                # The plate rides outside the retracted upper arm; the arm's
                # centerline slips medially as its elbow folds underneath.
                sign = 1 if side == "L" else -1
                shell_lift = .012 + .022 * (0.5 - 0.5*cos(2*pi*p))
                motion = (sign * shell_lift, .036 * offset / .475, -.010 * cos(2*pi*p))
                shoulder.location = translate_in_armature_space(shoulder, motion)
                shoulder.keyframe_insert(data_path="location", frame=f)
                upper = bones["upper_leg.F" + side]
                fold = max(0.0, sin(pi * (p - stance) / (1 - stance))) if p > stance else 0
                upper.location = translate_in_armature_space(upper, (-sign * (shell_lift + .025*fold), 0, 0))
                upper.keyframe_insert(data_path="location", frame=f)
                bpy.context.view_layer.update()
            else:
                # The hind legs pass just outside the folding forearms during
                # collection. Use a small, transient outward swing only.
                sign = 1 if side == "L" else -1
                passing = max(0.0, sin(pi*(p-.52)/.48)) if p > .52 else 0
                thigh = bones["thigh." + side + "R"]
                thigh.location = translate_in_armature_space(thigh, (sign * .038 * passing, 0, 0))
                thigh.keyframe_insert(data_path="location", frame=f)
                bpy.context.view_layer.update()
            sole = foot_points[front]
            toe_y, toe_z = min(sole, key=lambda yz: yz[0])
            ankle_y = (-.407 if front else .437) + offset
            ankle_y += toe_y - (cos(pitch)*toe_y - sin(pitch)*toe_z)
            ankle_z = lift - min(sin(pitch)*y + cos(pitch)*z for y, z in sole)
            hock_angle = radians(42 * offset / .475 - 7)
            solve_leg(front, side, ankle_y, ankle_z, pitch, hock_angle, f)
    stash(act_run)

    act_atk = new_action("Attack")
    # Brace on both hind paws, gather, lunge through the neck and recover. The
    # chest supplies reach; the pelvis and all paws return to their starting sites.
    attack_keys = [
        # frame, pelvis Y/Z, pelvis/chest/neck/head angle, jaw, forepaw reach/lift
        (1,   0.0,    0.0,   0,  0,   0,   0,   0,   0.0,   0.0),
        (4,   0.050, -0.066,  4,  6,  -8,  -8, -22,   0.010, 0.038),
        (8,  -0.080, -0.050, -4, -7,  18,   8,  -5,  -0.080, 0.012),
        (12, -0.045, -0.080, -1, -2,  11,   4, -14,  -0.078, 0.0),
        (15, -0.010, -0.043,  1,  2,  -3,  -2,  -6,  -0.034, 0.032),
        (19,  0.0,    0.0,   0,  0,   0,   0,   0,   0.0,   0.0),
    ]
    for f in range(1, 20):
        scene.frame_set(f)
        y, z, pelvis, chest, neck, head, jaw, reach, lift = smooth_keys(attack_keys, f)
        key_pose("pelvis", f, rot_xyz=(pelvis, 0, 0),
                 loc=translate_in_armature_space(bones["pelvis"], (0, y, z)))
        key_pose("chest", f, rot_xyz=(chest, 0, 0))
        key_pose("neck", f, rot_xyz=(neck, 0, 0))
        key_pose("head", f, rot_xyz=(head, 0, 0))
        key_pose("jaw", f, rot_xyz=(jaw, 0, 0))
        key_pose("tail.01", f, rot_xyz=(-chest, 0, 0))
        bpy.context.view_layer.update()
        for front in (True, False):
            for side in ("L", "R"):
                rest = paw_rest(front, side)
                solve_leg(front, side, rest.y + (reach if front else 0),
                          rest.z + (lift if front else 0), 0.0, 0.0, f)
    ground_action(act_atk, 1, 19)
    stash(act_atk)

    act_die = new_action("Die")
    # Roll about the pelvis, whose pivot is inside the torso. The ground-level
    # root stays fixed; rolling around it would send the torso sideways.
    death_keys = [
        # frame, roll, chest, head pitch/yaw, jaw, forelimb flex, hindlimb flex
        (1,   0,  0,   0,  0,   0,   0,  0),
        (5,   6,  3,   5,  4, -10,  18, 12),
        (10, 35,  7,  13, 11, -18,  28, 24),
        (15, 76,  9,  16, 16, -13,  36, 29),
        (18, 91, 10,  15, 18, -11,  37, 30),
        (21, 85,  8,  13, 17,  -8,  33, 27),
        (25, 87,  8,  13, 17,  -8,  33, 27),
    ]
    for f in range(1, 26):
        scene.frame_set(f)
        # The paw hands support to the rim of the hip plate halfway between
        # the original keys. Put that pose on frame 17 so GLB interpolation
        # no longer bridges two different contact surfaces above the ground.
        contact_offset = 0.5 * max(0.0, 1.0 - abs(f - 17.0) / 3.0)
        roll, chest, head, yaw, jaw, fore, rear = smooth_keys(death_keys, f - contact_offset)
        key_pose("pelvis", f, rot_xyz=(0, roll, 0))
        key_pose("chest", f, rot_xyz=(chest, 0, 0))
        key_pose("head", f, rot_xyz=(head, 0, yaw))
        key_pose("jaw", f, rot_xyz=(jaw, 0, 0))
        for side, bias in (("L", 1.0), ("R", 0.65)):
            key_pose("upper_leg.F" + side, f, rot_xyz=(-fore * bias, 0, 0))
            key_pose("lower_leg.F" + side, f, rot_xyz=(fore * 1.45 * bias, 0, 0))
            key_pose("thigh." + side + "R", f, rot_xyz=(rear * bias, 0, 0))
            key_pose("shin." + side + "R", f, rot_xyz=(-rear * 1.5 * bias, 0, 0))
        key_pose("tail.01", f, rot_xyz=(-0.22 * roll, 0, 0.08 * roll))
    ground_action(act_die, 1, 25)
    stash(act_die)

    clear_pose()
    rig.data.pose_position = "POSE"
    scene.frame_set(0)


# ---------------------------------------------------------------------------
# 7. Export Verification & Cycles Studio Rendering
# ---------------------------------------------------------------------------

def restore_gallop_timing(path: Path, expected_seconds: float) -> None:
    """Restore real time for the one oversampled NLA strip in Blender's GLB."""
    import json
    import struct

    raw = path.read_bytes()
    json_size, kind = struct.unpack_from("<I4s", raw, 12)
    assert raw[:4] == b"glTF" and kind == b"JSON"
    doc = json.loads(raw[20:20+json_size])
    bin_header = 20 + json_size
    _, kind = struct.unpack_from("<I4s", raw, bin_header)
    assert kind == b"BIN\0" and len(doc["buffers"]) == 1
    data = bytearray(raw[bin_header+8:bin_header+8+doc["buffers"][0]["byteLength"]])
    run, = (a for a in doc["animations"] if a.get("name") == "Run")
    # Blender may deduplicate accessors across clips. Always duplicate Run's
    # input times before editing, preserving the other samplers byte for byte.
    replacements = {}
    longest = 0.0
    for sampler in run["samplers"]:
        original = sampler["input"]
        if original not in replacements:
            accessor = doc["accessors"][original]
            view = doc["bufferViews"][accessor["bufferView"]]
            assert accessor["componentType"] == 5126 and accessor["type"] == "SCALAR"
            assert view["buffer"] == 0 and view.get("byteStride", 4) == 4
            offset = view.get("byteOffset", 0) + accessor.get("byteOffset", 0)
            values = struct.unpack_from(f"<{accessor['count']}f", data, offset)
            times = [v / RUN_SUBSAMPLES for v in values]
            longest = max(longest, times[-1])
            data.extend(b"\0" * (-len(data) % 4))
            times_offset = len(data)
            packed = struct.pack(f"<{len(times)}f", *times)
            data.extend(packed)
            times_view = len(doc["bufferViews"])
            doc["bufferViews"].append({"buffer":0, "byteOffset":times_offset, "byteLength":len(packed)})
            replacements[original] = len(doc["accessors"])
            doc["accessors"].append({"bufferView":times_view, "componentType":5126,
                                     "count":len(times), "type":"SCALAR", "min":[times[0]], "max":[times[-1]]})
        sampler["input"] = replacements[original]
    if abs(longest - expected_seconds) > 1e-5:
        raise RuntimeError(f"Wrong gallop duration after sampling: {longest} seconds")
    doc["buffers"][0]["byteLength"] = len(data)
    data.extend(b"\0" * (-len(data) % 4))
    encoded = json.dumps(doc, separators=(",",":"), ensure_ascii=False).encode()
    encoded += b" " * (-len(encoded) % 4)
    glb = (struct.pack("<4sII", b"glTF", 2, 28+len(encoded)+len(data))
           + struct.pack("<I4s", len(encoded), b"JSON") + encoded
           + struct.pack("<I4s", len(data), b"BIN\0") + data)
    temporary = path.with_suffix(".retimed.glb")
    temporary.write_bytes(glb)
    temporary.replace(path)


def export_warhound_glb(rig: bpy.types.Object, meshes: list[bpy.types.Object], output: Path) -> None:
    asset = bpy.data.collections[ASSET_COLLECTION]
    for obj in meshes:
        if obj.type != "MESH":
            continue
        for v in obj.data.vertices:
            total = sum(g.weight for g in v.groups if obj.vertex_groups[g.group].name in rig.data.bones)
            if total < 0.99:
                raise ValueError(f"{obj.name} vertex {v.index} under-weighted ({total})")

    pres = bpy.data.collections.get(PRESENTATION_COLLECTION)
    if pres:
        pres.hide_viewport = True
        pres.hide_render = True

    rig.data.pose_position = "POSE"
    anim = rig.animation_data
    anim.action = None
    anim.use_nla = True
    for track in anim.nla_tracks:
        track.is_solo = False
        track.mute = False
    bpy.context.scene.frame_set(0)

    bpy.ops.object.select_all(action="DESELECT")
    for obj in asset.all_objects:
        if obj.type in {"MESH", "ARMATURE"}:
            obj.select_set(True)
    bpy.context.view_layer.objects.active = rig

    output.parent.mkdir(parents=True, exist_ok=True)
    run_strip = anim.nla_tracks["Run"].strips[0]
    duration = (run_strip.frame_end - run_strip.frame_start) / bpy.context.scene.render.fps
    native_scale = run_strip.scale
    try:
        run_strip.scale = native_scale * RUN_SUBSAMPLES
        bpy.ops.export_scene.gltf(
            filepath=str(output),
            export_format="GLB",
            use_selection=True,
            export_yup=True,
            export_animations=True,
            export_cameras=False,
            export_animation_mode="NLA_TRACKS",
            export_frame_range=False,
            export_anim_slide_to_zero=True,
            export_rest_position_armature=True,
            export_skins=True,
            export_def_bones=False,
            export_lights=False,
            export_normals=True,
            export_all_vertex_colors=False,
        )
    finally:
        run_strip.scale = native_scale
    restore_gallop_timing(output, duration)
    print(f"Exported {output} ({len(meshes)} meshes)")


def _look_at(obj: bpy.types.Object, target: tuple[float, float, float]) -> None:
    obj.rotation_euler = (Vector(target) - obj.location).to_track_quat("-Z", "Y").to_euler()


def _setup_studio_scene() -> bpy.types.Scene:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 36
    scene.cycles.use_denoising = True
    scene.cycles.seed = 12
    scene.view_settings.view_transform = "AgX"
    scene.view_settings.look = "AgX - Medium High Contrast"

    scene.world = bpy.data.worlds.new("Studio ambient")
    scene.world.use_nodes = True
    bg = scene.world.node_tree.nodes["Background"]
    bg.inputs[0].default_value = (0.56, 0.65, 0.82, 1.0)
    bg.inputs[1].default_value = 0.145

    def add_area(name, pos, target, power, w, h, color):
        data = bpy.data.lights.new(name, "AREA")
        data.shape = "RECTANGLE"
        data.size, data.size_y = w, h
        data.energy = power
        data.color = color
        obj = bpy.data.objects.new(name, data)
        scene.collection.objects.link(obj)
        obj.location = pos
        _look_at(obj, target)

    add_area("Warm key",   (-2.6, -2.9, 4.2), (0, -0.1, 0.65), 255, 2.2, 2.2, (1.0, 0.87, 0.72))
    add_area("Window",     ( 2.6, -1.9, 2.4), (0, -0.1, 0.65),  96, 1.2, 2.6, (0.69, 0.82, 1.0))
    add_area("Crown edge", ( 0.8,  1.9, 3.4), (0, -0.1, 0.65), 230, 1.2, 2.4, (1.0, 0.85, 0.56))
    add_area("Muzzle fill", (-0.6, -2.6, 1.1), (0, -0.65, 1.00), 22, 0.9, 0.7, (1.0, 0.92, 0.85))

    # Studio seamless curved backdrop sitting behind Y=+1.6 (cameras always look from -Y toward +Y!)
    section = [(-6.0, -0.001), (1.4, -0.001)]
    for i in range(1, 25):
        t = pi * 0.5 * i / 24
        section.append((1.4 + 2.8 * sin(t), -0.001 + 2.8 * (1.0 - cos(t))))
    section.append((4.2, 12.0))
    pts = [(x, y, z) for y, z in section for x in (-16.0, 16.0)]
    faces = [(2 * i, 2 * i + 1, 2 * i + 3, 2 * i + 2) for i in range(len(section) - 1)]
    mesh = bpy.data.meshes.new("Seamless floor")
    mesh.from_pydata(pts, [], faces)
    for p in mesh.polygons:
        p.use_smooth = True
    mat = bpy.data.materials.new("Backdrop")
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (0.044, 0.052, 0.068, 1.0)
    bsdf.inputs["Roughness"].default_value = 0.85
    mesh.materials.append(mat)
    scene.collection.objects.link(bpy.data.objects.new("Sweep", mesh))

    cam_data = bpy.data.cameras.new("StudioCam")
    cam = bpy.data.objects.new("StudioCam", cam_data)
    scene.collection.objects.link(cam)
    scene.camera = cam
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGB"
    return scene


def _import_glb_at(path: Path, x: float = 0.0, yaw_deg: float = 0.0) -> bpy.types.Object:
    existing = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=str(path))
    imported = set(bpy.data.objects) - existing
    for obj in imported:
        if obj.type == "ARMATURE":
            obj.data.pose_position = "REST"
    roots = [o for o in imported if o.parent is None]
    pivot = bpy.data.objects.new(path.stem + "_pose", None)
    bpy.context.scene.collection.objects.link(pivot)
    for o in roots:
        o.parent = pivot
    pivot.location.x = x
    pivot.rotation_euler.z = radians(yaw_deg)
    return pivot


def _render_view(scene, target, direction, ortho_scale: float, size: tuple[int, int], out_path: Path) -> None:
    cam = scene.camera
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = ortho_scale
    cam.location = Vector(target) + Vector(direction).normalized() * 6.5
    _look_at(cam, target)
    scene.render.resolution_x, scene.render.resolution_y = size
    scene.render.resolution_percentage = 100
    scene.render.filepath = str(out_path)
    bpy.ops.render.render(write_still=True)


def _stitch_2x2(paths: list[Path], out_path: Path) -> None:
    imgs = [bpy.data.images.load(str(p)) for p in paths]
    w, h = imgs[0].size
    c = 4
    grid = bpy.data.images.new("TurnaroundGrid", width=w * 2, height=h * 2, alpha=False)
    dst = [0.0] * (w * 2 * h * 2 * c)
    offsets = [(0, h), (w, h), (0, 0), (w, 0)]
    for img, (ox, oy) in zip(imgs, offsets):
        src = list(img.pixels)
        for row in range(h):
            s0 = row * w * c
            d0 = ((oy + row) * (w * 2) + ox) * c
            dst[d0:d0 + w * c] = src[s0:s0 + w * c]
        bpy.data.images.remove(img)
    grid.pixels.foreach_set(dst)
    grid.filepath_raw = str(out_path)
    grid.file_format = "PNG"
    grid.save()
    bpy.data.images.remove(grid)


def render_previews(glb_path: Path) -> None:
    PREVIEW_DIR.mkdir(parents=True, exist_ok=True)

    # 1. Hero 3/4 view + 4-angle turnaround (rotate the model so camera stays on -Y facing backdrop!)
    sc = _setup_studio_scene()
    pivot = _import_glb_at(glb_path, x=0.0, yaw_deg=-52.0)

    # Hero 3/4 view with generous paw/ear margin
    _render_view(sc, (0.02, -0.02, 0.62), (0.0, -1.0, 0.18), 2.15, (1400, 960), PREVIEW_DIR / "warhound_hero.png")

    tmp_views = []
    # (tag, model_yaw_deg, cam_target, cam_dir, ortho_scale)
    specs = [
        ("front", 0.0,    (0.0, -0.10, 0.67), (0.0, -1.0, 0.10), 1.95),
        ("side",  90.0,   (0.0,  0.00, 0.64), (0.0, -1.0, 0.06), 2.15),
        ("rear",  138.0,  (0.0,  0.00, 0.64), (0.0, -1.0, 0.22), 2.05),
        ("rts",   -35.0,  (0.0,  0.00, 0.54), (0.0, -0.64, 0.77), 1.95),  # ~50-deg RTS pitch view!
    ]
    for tag, myaw, tgt, vdir, scale in specs:
        pivot.rotation_euler.z = radians(myaw)
        bpy.context.view_layer.update()
        p = PREVIEW_DIR / f"_tmp_wh_{tag}.png"
        _render_view(sc, tgt, vdir, scale, (760, 560), p)
        tmp_views.append(p)

    _stitch_2x2(tmp_views, PREVIEW_DIR / "warhound_turnaround.png")
    for p in tmp_views:
        p.unlink(missing_ok=True)

    # 2. Scale & aesthetic lineup alongside Round Table Marine
    if ROUND_TABLE_GLB.exists():
        sc = _setup_studio_scene()
        _import_glb_at(ROUND_TABLE_GLB, x=-0.75, yaw_deg=14.0)
        _import_glb_at(glb_path, x=0.70, yaw_deg=-48.0)
        _render_view(sc, (0.0, 0.0, 0.92), (0.0, -1.0, 0.14), 3.10, (1600, 1000), PREVIEW_DIR / "warhound_lineup.png")


# ---------------------------------------------------------------------------
# Main Build Entry Point
# ---------------------------------------------------------------------------

def prepare_artist_scene(scene, collection, rig, meshes):
    # The NLA editor retains each named clip. Play just the idle loop on opening.
    animation = rig.animation_data
    animation.action = None
    animation.use_nla = True
    rest_track = animation.nla_tracks["Rest"]
    for track in animation.nla_tracks:
        track.is_solo = False
        track.mute = track != rest_track
    strip = rest_track.strips[0]
    scene.frame_start = int(strip.frame_start)
    scene.frame_end = max(scene.frame_start, int(strip.frame_end) - 1)
    scene.frame_set(scene.frame_start)

    # Keep the asset transform and the editable rig in their original coordinates.
    # Rotate the entire studio around the hound to reproduce the reference view.
    orbit = Matrix.Rotation(radians(42), 3, "Z")
    elevation = radians(7)
    sightline = orbit @ Vector((0, -cos(elevation), sin(elevation)))
    rotation = (-sightline).to_track_quat("-Z", "Y")
    axes = [rotation @ Vector(a) for a in ((1, 0, 0), (0, 1, 0), (0, 0, 1))]
    points = [obj.matrix_world @ vert.co for obj in meshes for vert in obj.data.vertices]
    limits = [(min(p.dot(a) for p in points), max(p.dot(a) for p in points)) for a in axes]
    focus = sum((axis * ((low + high) / 2) for axis, (low, high) in zip(axes, limits)), Vector())
    ratio = 1280 / 714
    width = max(limits[0][1] - limits[0][0], (limits[1][1] - limits[1][0]) * ratio) / 0.895
    target = focus - axes[0] * (0.035 * width) + axes[1] * (0.01 * width / ratio)
    camera = bpy.data.cameras.new("Hero â€¢ orthographic")
    camera.type, camera.ortho_scale = "ORTHO", width
    cam = bpy.data.objects.new("Camera â€¢ Warhound hero", camera)
    collection.objects.link(cam)
    cam.location = target + sightline * 5
    cam.rotation_euler = rotation.to_euler()
    scene.camera = cam

    scene.render.engine = "CYCLES"
    scene.render.resolution_x, scene.render.resolution_y = 1280, 714
    scene.render.resolution_percentage = 100
    scene.cycles.samples, scene.cycles.max_bounces = 32, 5
    scene.cycles.use_denoising = True
    scene.view_settings.view_transform = "AgX"
    scene.view_settings.look = "AgX - Medium High Contrast"
    scene.world = bpy.data.worlds.new("Studio â€¢ ambient")
    scene.world.use_nodes = True
    ambient = scene.world.node_tree.nodes["Background"]
    ambient.inputs[0].default_value = (0.73, 0.76, 0.82, 1)
    ambient.inputs[1].default_value = 0.145
    for name, location, power, width, height, color in [
        ("Key â€¢ warm softbox", (-2.6, -2.9, 4.2), 255, 2.2, 2.2, (1.0, 0.93, 0.85)),
        ("Fill â€¢ cool window", (2.6, -1.9, 2.4), 96, 1.2, 2.6, (0.69, 0.82, 1.0)),
        ("Rim â€¢ armor edge", (0.8, 1.9, 3.4), 165, 1.2, 2.4, (1.0, 0.85, 0.56)),
    ]:
        data = bpy.data.lights.new(name, "AREA")
        data.energy, data.shape, data.color = power, "RECTANGLE", color
        data.size, data.size_y = width, height
        light = bpy.data.objects.new(name, data)
        collection.objects.link(light)
        light.location = orbit @ Vector(location)
        _look_at(light, focus)

    # A curved sweep creates a seamless studio horizon for the native F12 render.
    section = [(-8.0, -0.004), (1.4, -0.004)]
    for step in range(1, 17):
        angle = pi * 0.5 * step / 16
        section.append((1.4 + 2.8 * sin(angle), -0.004 + 2.8 * (1 - cos(angle))))
    section.append((4.2, 7.0))
    floor_mesh = bpy.data.meshes.new("Studio sweep")
    floor_mesh.from_pydata([orbit @ Vector((x, y, z)) for y, z in section for x in (-9, 9)], [],
                           [(2*i, 2*i+1, 2*i+3, 2*i+2) for i in range(len(section)-1)])
    for face in floor_mesh.polygons:
        face.use_smooth = True
    material = bpy.data.materials.new("Studio â€¢ neutral gray")
    material.use_nodes = True
    surface = material.node_tree.nodes["Principled BSDF"]
    surface.inputs["Base Color"].default_value = (0.045, 0.053, 0.072, 1)
    surface.inputs["Roughness"].default_value = 0.92
    floor_mesh.materials.append(material)
    floor = bpy.data.objects.new("Backdrop â€¢ seamless studio", floor_mesh)
    collection.objects.link(floor)
    floor.hide_set(True)  # Keep orbiting/editing clear. Final renders still include it.

    bpy.ops.object.select_all(action="DESELECT")
    rig.select_set(True)
    bpy.context.view_layer.objects.active = rig
    for area in bpy.data.screens["Layout"].areas:
        if area.type != "VIEW_3D":
            continue
        space = area.spaces.active
        space.shading.type, space.shading.color_type = "SOLID", "MATERIAL"
        space.shading.light, space.shading.show_shadows = "STUDIO", True
        space.shading.background_type = "VIEWPORT"
        space.shading.background_color = (0.055, 0.060, 0.070)
        space.overlay.show_bones = space.overlay.show_extras = False
        space.overlay.show_outline_selected = space.overlay.show_relationship_lines = False
        space.overlay.show_floor = space.overlay.show_axis_x = space.overlay.show_axis_y = False
        space.overlay.show_cursor = False
        region = space.region_3d
        region.view_perspective, region.view_rotation = "ORTHO", rotation
        region.view_distance, region.view_location = 2.55, focus


def build_scene() -> tuple[bpy.types.Object, list[bpy.types.Object]]:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene

    asset_col = bpy.data.collections.new(ASSET_COLLECTION)
    pres_col = bpy.data.collections.new(PRESENTATION_COLLECTION)
    scene.collection.children.link(asset_col)
    scene.collection.children.link(pres_col)

    root = bpy.data.objects.new(ROOT_NAME, None)
    asset_col.objects.link(root)

    mats = build_materials()

    body = build_body_mesh(asset_col, root, mats)
    head = build_head_mesh(asset_col, root, mats)
    legs = build_legs_mesh(asset_col, root, mats)
    helm = build_helm_mesh(asset_col, root, mats)
    gorget, comms = build_gorget_and_comms_meshes(asset_col, root, mats)
    cuirass = build_cuirass_mesh(asset_col, root, mats)
    tabard = build_tabard_mesh(asset_col, root, mats)
    pauldron_l = build_pauldron_mesh(asset_col, root, mats, 1.0)
    pauldron_r = build_pauldron_mesh(asset_col, root, mats, -1.0)
    harness = build_harness_mesh(asset_col, root, mats)
    haunch_l = build_haunch_mesh(asset_col, root, mats, 1.0)
    haunch_r = build_haunch_mesh(asset_col, root, mats, -1.0)
    greave_l = build_greaves_mesh(asset_col, root, mats, 1.0)
    greave_r = build_greaves_mesh(asset_col, root, mats, -1.0)

    meshes = [
        body, head, legs, helm, gorget, comms, cuirass,
        tabard, pauldron_l, pauldron_r, harness, haunch_l, haunch_r, greave_l, greave_r,
    ]

    rig = create_rig(asset_col, root)
    bind_warhound_meshes(rig, meshes)
    build_animations(rig)

    prepare_artist_scene(scene, pres_col, rig, meshes)

    root["asset_status"] = "Arthurian Warhound rigged unit"
    bpy.context.preferences.filepaths.save_version = 0
    SOURCE_BLEND.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE_BLEND), compress=True)
    print(f"Saved {SOURCE_BLEND}")
    return rig, meshes


def main() -> None:
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--no-export", action="store_true")
    parser.add_argument("--no-render", action="store_true")
    args = parser.parse_args(argv)

    rig, meshes = build_scene()
    if not args.no_export:
        export_warhound_glb(rig, meshes, EXPORT_GLB)
    if not args.no_render and EXPORT_GLB.exists():
        render_previews(EXPORT_GLB)


if __name__ == "__main__":
    main()
