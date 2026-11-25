"""Builds Blender/Buildings/Farm/Farm.blend procedurally.

Run in headless Blender 4.5:
  blender --background --python build_farm.py

Conventions:
- Front Loading Porch / Barn Gable / Windmill: -Y in Blender (+Z in Godot)
- Base grounded at Z = 0, Z up, world metres
- Footprint 4 x 4 m: outer geometry strictly inside X, Y in [-1.92, +1.92]
- Max height strictly < 4.65 m (compact pastoral building below Chapterhouse & Keep)
- Flat PBR materials only; `team_color` & `team_color_shadow` match scripts/components/team_paint.gd
"""

from __future__ import annotations

import os
import random
from math import cos, pi, radians, sin

import bmesh
import bpy
from mathutils import Matrix, Vector as V

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.normpath(os.path.join(HERE, "..", "Farm.blend"))

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
    # Farm agricultural flat-PBR materials
    "Timber_Oak":         ((0.26, 0.16, 0.085), 0.00, 0.78, None, 0.0),
    "Soil_Loam":          ((0.085, 0.055, 0.032), 0.00, 0.94, None, 0.0),
    "Wheat_Gold":         ((0.78, 0.56, 0.14), 0.00, 0.70, None, 0.0),
    "Wheat_Stalk":        ((0.46, 0.44, 0.14), 0.00, 0.78, None, 0.0),
    "Sprout_Green":       ((0.18, 0.34, 0.10), 0.00, 0.72, None, 0.0),
    "Heartwood":          ((0.115, 0.061, 0.032), 0.0, 0.81, None, 0.0),
    "Hewn_Limestone":     ((0.45, 0.41, 0.32), 0.03, 0.84, None, 0.0),
    "Fieldstone":         ((0.28, 0.26, 0.21), 0.02, 0.88, None, 0.0),
    "Sailcloth":          ((0.82, 0.72, 0.52), 0.0, 0.88, None, 0.0),
    "Barley_Chaff":       ((0.62, 0.32, 0.066), 0.0, 0.78, None, 0.0),
    "Flag_Leaf":          ((0.27, 0.36, 0.085), 0.0, 0.78, None, 0.0),
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

    def add_cyl(self, p0, p1, r0: float, r1: float | None = None, seg: int = 8, mat: str = "Timber_Oak", cap: bool = True, twist_rad: float = 0.0) -> None:
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

    def add_faces(self, coords, faces, mat: str) -> None:
        vertices = [self.bm.verts.new(self._to_local(p)) for p in coords]
        for face in faces:
            self.bm.faces.new([vertices[i] for i in face])
            self.face_mats.append(mat)

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


# ---------------------------------------------------------------------------
# 1. Curb Base, Raised Tilled Soil Beds & Perimeter Timber Fence
# ---------------------------------------------------------------------------


def build_curb_base(col, root, mats) -> bpy.types.Object:
    cb = PartBuilder("curb_base", (0.0, 0.0, 0.0))

    # Dry-laid perimeter and a cobbled unloading apron. The east and south
    # cultivation bays have a low sill that the Maiden can reach across.
    cb.add_span(-1.88, 1.88, -1.88, 1.88, 0.0, .095, "Fieldstone", bevel=.04)
    cb.add_span(-1.86, 1.84, -1.85, 1.85, .075, .125, "Soil_Loam", bevel=.04)
    rng = random.Random(350)
    for row in range(7):
        lo = -1.81
        y = -1.80 + .29 * row
        while lo < -.354:
            hi = min(-.353, lo + rng.uniform(.26, .57))
            if hi-lo > .050:
                cb.add_span(lo+.008, hi-.007, y, y+.274, .11, .161+rng.uniform(-.005,.006),
                            rng.choice(("Hewn_Limestone","Fieldstone","Hewn_Limestone")), bevel=.018)
            lo = hi
    for fx in (-.12,.15,.47,.80,1.14,1.48):
        y_top = -.12 if fx < .23 else 1.67
        cb.add_cyl((fx,-1.70,.148),(fx,y_top,.148),.082,.075,seg=7,mat="Soil_Loam")
    for bx in (-.33, .27, 1.78):
        cb.add_cyl((bx,-1.77,.146),(bx,-.01 if bx<0 else 1.77,.146),
                   .045,.044,seg=6,mat="Heartwood")
    posts=[(1.80,-1.78),(1.80,-1.32),(1.80,.70),(1.80,1.78),
           (.95,1.78),(.30,1.78),(-.30,-1.78),(.58,-1.78)]
    for px,py in posts:
        cb.add_box((px,py,.34),(.083,.083,.49),"Timber_Oak",bevel=.006)
        cb.add_cyl((px,py,.585),(px,py,.654),.061,.015,seg=4,mat="Heartwood",twist_rad=pi/4)
    for rz in (.30,.49):
        for start,end in [(-1.78,-1.32),(.70,1.78)]:
            cb.add_span(1.77,1.813,start,end,rz-.023,rz+.023,"Timber_Oak")
        cb.add_span(.58,1.80,-1.80,-1.76,rz-.023,rz+.023,"Timber_Oak")
        cb.add_span(.30,.70,1.76,1.80,rz-.023,rz+.023,"Timber_Oak")
        cb.add_span(1.52,1.80,1.76,1.80,rz-.023,rz+.023,"Timber_Oak")

    cb.add_span(-1.843,-1.65,-1.71,.015,.112,.169,"Soil_Loam",bevel=.013)

    return cb.build(col, root, mats)


# ---------------------------------------------------------------------------
# 2. Granary Barn, Silo Hopper, Windmill Rotor & Pennant (back-left quadrant)
# ---------------------------------------------------------------------------


def build_barn_and_windmill(col, root, mats) -> tuple[bpy.types.Object, bpy.types.Object, bpy.types.Object]:
    gb = PartBuilder("granary_barn", (-0.82, 0.96, 0.0))

    # Barn body: X in [-1.68, +0.16], Y in [+0.06, +1.76], Z in [0.14, 2.02]
    x0, x1 = -1.68, 0.16
    y0, y1 = 0.06, 1.76
    cx = (x0 + x1) * 0.5  # -0.76
    cy = (y0 + y1) * 0.5  # +0.91

    # Stone foundation skirt & Ivory_Armor half-timbered plaster hull
    gb.add_span(x0 - 0.04, x1 + 0.04, y0 - 0.04, y1 + 0.04, 0.14, 0.44, "Recessed_Steel", bevel=0.015)
    gb.add_span(x0, x1, y0, y1, 0.42, 2.04, "Ivory_Armor", bevel=0.02)

    # Half-timbered Oak vertical corner posts & cross beams
    for tx in (x0, cx, x1):
        for ty in (y0, y1):
            gb.add_box((tx, ty, 1.22), (0.11, 0.11, 1.62), "Timber_Oak", bevel=0.01)
    for tz in (0.46, 1.24, 1.98):
        gb.add_span(x0 - 0.03, x1 + 0.03, y0 - 0.03, y1 + 0.03, tz - 0.045, tz + 0.045, "Timber_Oak")

    # Pitched royal-blue barn roof along Y (X in [-1.80, +0.26], eave Z=1.98 -> ridge Z=3.18 at cx=-0.76)
    eave_z, ridge_z = 1.98, 3.18
    sub = bmesh.new()
    v_fl = sub.verts.new(V((-1.78, y0 - 0.08, eave_z)))
    v_fr = sub.verts.new(V(( 0.24, y0 - 0.08, eave_z)))
    v_ft = sub.verts.new(V(( cx,   y0 - 0.08, ridge_z)))
    v_bl = sub.verts.new(V((-1.78, y1 + 0.08, eave_z)))
    v_br = sub.verts.new(V(( 0.24, y1 + 0.08, eave_z)))
    v_bt = sub.verts.new(V(( cx,   y1 + 0.08, ridge_z)))
    sub.faces.new((v_fl, v_fr, v_ft))
    sub.faces.new((v_br, v_bl, v_bt))
    sub.faces.new((v_fl, v_ft, v_bt, v_bl))
    sub.faces.new((v_fr, v_br, v_bt, v_ft))
    sub.faces.new((v_fl, v_bl, v_br, v_fr))
    bmesh.ops.recalc_face_normals(sub, faces=sub.faces[:])
    vmap = {v: gb.bm.verts.new(gb._to_local(v.co)) for v in sub.verts}
    for fc in sub.faces:
        nf = gb.bm.faces.new([vmap[v] for v in fc.verts])
        nf.smooth = False
        mat_pick = "Ivory_Armor" if abs(fc.normal.y) > 0.7 else ("Timber_Oak" if fc.normal.z < -0.5 else "team_color")
        gb.face_mats.append(mat_pick)
    sub.free()

    # Brass ridge spine & verge fascia
    gb.add_cyl((cx, y0 - 0.10, ridge_z), (cx, y1 + 0.10, ridge_z), 0.065, 0.065, seg=6, mat="Heraldic_Brass")
    gb.add_cyl((-1.78, y0 - 0.08, eave_z), (cx, y0 - 0.08, ridge_z), 0.045, 0.045, seg=6, mat="Timber_Oak")
    gb.add_cyl(( 0.24, y0 - 0.08, eave_z), (cx, y0 - 0.08, ridge_z), 0.045, 0.045, seg=6, mat="Timber_Oak")

    # Hand-laid slate courses. The bottom edges form the scalloped silhouette
    # of clay tiles; two overlapping facets on each tile catch the raking light.
    for side in (-1, 1):
        eave = cx + side*1.01
        slope = V((-side*1.01,0,ridge_z-eave_z)).normalized()
        out = V((side*slope.z,0,abs(slope.x)))
        roof_length = (V((cx,0,ridge_z))-V((eave,0,eave_z))).length
        course = roof_length/6
        for row in range(6):
            first_y = -.014
            for tile_index in range(8):
                start = first_y + (tile_index-(row%2)*.5)*.295
                end = min(start+.294,y1+.068)
                start = max(start,y0-.074)
                width=end-start
                if width < .04: continue
                origin = V((eave,(start+end)/2,eave_z))+slope*(row*course)+out*.012
                tile=[(-width*.5,.014),(-width*.39,-.018),(width*.36,-.018),
                      (width*.5,.012),(width*.5,course+.013),(-width*.5,course+.013)]
                gb.add_extruded_poly_frame(tile,origin,Y,slope,out,.003,.019,
                                      "team_color_shadow" if (row+2*tile_index)%7==0 else "team_color")
    for fy in (y0-.087,y1+.087):
        gb.add_cyl((cx,fy,eave_z+.03),(cx,fy,ridge_z-.105),.041,.041,seg=4,mat="Heartwood",twist_rad=pi/4)
        for sign in (-1,1):
            gb.add_cyl((cx+sign*.58,fy,eave_z+.07),(cx,fy,ridge_z-.22),
                       .036,.036,seg=4,mat="Timber_Oak",twist_rad=pi/4)
    # Front oak doors tall enough for the farm worker. Dark reveals separate
    # the planks, and diagonal cross braces carry each leaf into its hinges.
    gb.add_span(cx-.49,cx+.49,y0-.05,y0+.02,.17,1.84,"Heartwood",bevel=.022)
    for i in range(8):
        x=cx-.419+i*.12
        gb.add_box((x,y0-.064,1.002),(.113,.042,1.59),"Timber_Oak",bevel=.007)
    for s in (-1,1):
        gb.add_cyl((cx+s*.43,y0-.101,.36),(cx+s*.07,y0-.101,1.62),.039,.039,seg=4,mat="Heartwood",twist_rad=pi/4)
        for z in (.42,1.53):
            gb.add_box((cx+s*.33,y0-.103,z),(.229,.018,.047),"Recessed_Steel",bevel=.005)
            gb.add_sphere((cx+s*.25,y0-.116,z),.018,"Heraldic_Brass")
    gb.add_box((cx,y0-.08,1.87),(1.04,.13,.11),"Heartwood",bevel=.016)
    for side in (-1,1):
        sx = x0-.063 if side<0 else x1+.063
        for wy in (.32,.80,1.28,1.65):
            gb.add_box((sx-.03*side,wy,.306),(.055,.32,.185),
                       "Fieldstone" if wy>.8 else "Hewn_Limestone",bevel=.015)
        # Field-side leaded windows and a pair of timber braces in each bay.
        for wy in (.54,1.32):
            gb.add_box((sx,wy,1.42),(.057,.40,.43),"Heartwood",bevel=.025)
            gb.add_box((sx+side*.032,wy,1.43),(.023,.302,.316),"Keep_Interior_Dark")
            gb.add_box((sx+side*.05,wy,1.43),(.02,.037,.317),"Satin_Silver")
            gb.add_box((sx+side*.05,wy,1.43),(.02,.303,.033),"Satin_Silver")
            for n in (-1,1):
                gb.add_cyl((sx,wy+n*.075,1.955),(sx,wy+n*.32,1.68),
                           .042,.04,seg=4,mat="Timber_Oak",twist_rad=pi/4)
    # Suspended lantern in the loading porch.
    gb.add_cyl((cx-.62,y0-.07,1.89),(cx-.62,y0-.22,1.89),.028,.021,seg=6,mat="Heartwood")
    lamp=V((cx-.62,y0-.205,1.65))
    gb.add_cyl(lamp, lamp+Z*.167,.054,.087,seg=4,mat="Visor_Amber",twist_rad=pi/4)
    gb.add_cyl(lamp+Z*.153,lamp+Z*.217,.107,.038,seg=4,mat="Recessed_Steel",twist_rad=pi/4)
    gb.add_cyl(lamp-Z*.02,lamp+Z*.016,.039,.064,seg=4,mat="Recessed_Steel",twist_rad=pi/4)

    # Silo / Grain Hopper Tower at back-left corner (-1.50, +1.42, Z = 0.16..3.42)
    sx, sy = -1.50, 1.42
    gb.add_cyl((sx, sy, 0.16), (sx, sy, 2.86), 0.36, 0.34, seg=10, mat="Satin_Silver")
    for bz in (0.65, 1.40, 2.15, 2.80):
        gb.add_cyl((sx, sy, bz - 0.04), (sx, sy, bz + 0.04), 0.38, 0.38, seg=10, mat="Heraldic_Brass")
    gb.add_cyl((sx, sy, 2.86), (sx, sy, 3.44), 0.42, 0.04, seg=10, mat="team_color")
    gb.add_sphere((sx, sy, 3.47), 0.06, "Heraldic_Brass", sub=1)

    # Rotor axle collar mounted forward of front gable at cx=-0.76, Z=3.02
    gb.add_cyl((cx, y0 - 0.05, 3.02), (cx, y0 - 0.28, 3.02), 0.11, 0.10, seg=8, mat="Heraldic_Brass")

    gb_obj = gb.build(col, root, mats)

    # Windmill Rotor (`windmill_rotor`, child of `granary_barn`), pivoted cleanly at (-0.76, -0.22, 3.02)
    hub = (-0.76, -0.22, 3.02)
    wr = PartBuilder("windmill_rotor", hub)
    wr.add_cyl((hub[0], hub[1] + 0.06, hub[2]), (hub[0], hub[1] - 0.14, hub[2]), 0.13, 0.04, seg=8, mat="Heraldic_Brass")
    # Four handed shutter sails. Canvas bellies between the dark spar and
    # the leech. The open upper lattice keeps each sail legible in motion.
    for k in range(4):
        ang=radians(27+90*k)
        spar=V((cos(ang),0,sin(ang)))
        cross=V((-sin(ang),0,cos(ang)))
        center=V(hub)
        def sail_point(r,w):
            return center+spar*r+cross*w-Y*(.025+w*.16)
        wr.add_cyl(sail_point(.06,0),sail_point(1.068,0),.036,.021,seg=7,mat="Heartwood")
        wr.add_cyl(sail_point(.273,.13),sail_point(1.02,.318),.015,.012,seg=5,mat="Timber_Oak")
        wr.add_cyl(sail_point(.273,-.060),sail_point(1.044,-.068),.015,.012,seg=5,mat="Timber_Oak")
        for i in range(6):
            r=.282+i*.148
            width=.130+i*.0376
            wr.add_cyl(sail_point(r,-.070),sail_point(r,width+.012),.012,.010,seg=5,mat="Timber_Oak")
            if i==0 or i==5: continue
            cloth="team_color" if i==4 else "Sailcloth"
            a,b,c,d=(sail_point(r+.004,-.052),sail_point(r+.004,width),
                     sail_point(r+.145,width+.034),sail_point(r+.145,-.055))
            raised=(a+b+c+d)*.25-Y*.012
            # Back face shares the four seams, giving canvas a closed volume.
            wr.add_faces([a,b,c,d,raised,raised+Y*.032],
                         [(0,4,1),(1,4,2),(2,4,3),(3,4,0),
                          (0,1,5),(1,2,5),(2,3,5),(3,0,5)],cloth)
    for i in range(6):
        a=i*pi/3
        wr.add_sphere((hub[0]+.076*cos(a),hub[1]-.12,hub[2]+.076*sin(a)),
                      .018,"Satin_Silver")
    wr_obj = wr.build(col, gb_obj, mats)

    # Small pennant atop the grain silo
    pn_pos = V((sx, sy, 3.48))
    pn = PartBuilder("farm_pennant", tuple(pn_pos))
    pn.add_cyl(pn_pos, pn_pos + Z * 0.42, 0.018, 0.016, seg=6, mat="Heraldic_Brass")
    pn.add_extruded_poly_frame(
        [(0.0, 0.0), (0.36, -0.05), (0.26, -0.11), (0.36, -0.17), (0.0, -0.22)],
        pn_pos + Z * 0.39,
        X,
        Z,
        -Y,
        -0.012,
        0.012,
        "team_color",
    )
    pn_obj = pn.build(col, gb_obj, mats)

    return gb_obj, wr_obj, pn_obj


# ---------------------------------------------------------------------------
# 3. Cut Stubble (Persistent Base) + 3 Sculpted Golden Wheat Rows
# ---------------------------------------------------------------------------


def build_crops(col, root, mats) -> tuple[bpy.types.Object, list[bpy.types.Object]]:
    rng = random.Random(316)
    # Each crown has a hollow-stem silhouette, folded flag leaves, paired
    # spikelets and fine awns. Groups share mesh surfaces across the field.
    def leaf(builder,base,tip,width,mat):
        along=tip-base
        cross=V((-along.y,along.x,0))
        if cross.length < 1e-5: cross=X.copy()
        cross.normalize()
        middle=base+along*.44+Z*width*.68
        left=middle+cross*width
        right=middle-cross*width
        rib=middle+Z*width*.48
        builder.add_faces([base,left,rib,right,tip,rib-Z*width*.62],
                          [(0,2,1),(0,3,2),(1,2,4),(2,3,4),
                           (0,1,5),(0,5,3),(1,4,5),(5,4,3)],mat)

    def spike(builder,base,height,angle,tone):
        az=V((cos(angle),sin(angle),0))
        span=V((-az.y,az.x,0))
        drift=az*height*.33
        top=base+drift+Z*height
        builder.add_cyl(base,top,.013,.005,seg=4,mat=tone)
        for level in range(5):
            u=level*.172
            core=base+(top-base)*u
            width=(1-level*.06)*height*.126
            for sign in (-1,1):
                direction=(span*sign+az*.13).normalized()
                centre=core+direction*.032+Z*.033
                tip=core+direction*width*1.30+Z*height*.255
                builder.add_faces([core-.006*Z,centre+az*width*.68,
                                   centre+direction*width*.48,centre-az*width*.68,tip],
                                  [(0,1,2),(0,2,3),(1,4,2),(2,4,3),(0,4,1),(0,3,4)],tone)
                if level in (1,3,4):
                    builder.add_cyl(tip,tip+direction*height*.21+Z*height*.26,.005,.001,
                                    seg=3,mat=tone)

    st=PartBuilder("crop_stubble",(.85,0,.16))
    specs=[("crop_row_1",V((0,-.98,.16)),[-.13,.12],[-1.51,-1.17,-.81,-.45]),
           ("crop_row_2",V((.63,0,.16)),[.47,.79],[-1.53,-1.12,-.70,-.28,.12,.52,.92,1.34,1.54]),
           ("crop_row_3",V((1.28,0,.16)),[1.13,1.47],[-1.53,-1.12,-.70,-.28,.12,.52,.92,1.34,1.54])]
    rows=[]
    for name,origin,columns,stations in specs:
        rb=PartBuilder(name,tuple(origin))
        for fx in columns:
            for fy in stations:
                cut_back = fx > 1.40 and -1.32 < fy < .70
                for _ in range(3):
                    angle=rng.uniform(0,2*pi)
                    h=rng.uniform(.43,.61)
                    stem=V((fx+rng.uniform(-.058,.058),fy+rng.uniform(-.075,.075),.177))
                    az=V((cos(angle),sin(angle),0))
                    stub=stem+az*.014+Z*.11
                    st.add_cyl(stem,stub,.010,.008,seg=4,mat="Wheat_Stalk")
                    if cut_back:
                        for d in (-1,1):
                            leaf(st,stem,stem+az*(.064*d)+Z*rng.uniform(.075,.15),.023,"Sprout_Green")
                        continue
                    top=stem+az*rng.uniform(.025,.078)+Z*h
                    rb.add_cyl(stem,top,.012,.008,seg=5,mat="Wheat_Stalk")
                    for j in range(2):
                        start=stem+(top-stem)*(.20+j*.24)
                        vec=az*(-1 if j==0 else 1)
                        leaf(rb,start,start+vec*rng.uniform(.09,.15)+Z*rng.uniform(.11,.21),.024,
                             "Flag_Leaf" if j==0 else "Wheat_Stalk")
                    spike(rb,top,rng.uniform(.214,.265),angle,
                          "Barley_Chaff" if rng.random()<.26 else "Wheat_Gold")
        rows.append(rb.build(col,root,mats))
    # The west nursery stays accessible from the barn's loading apron.
    for pos_y in [-1.53,-1.29,-1.05,-.81,-.57,-.33,-.09]:
        p=V((-1.748,pos_y,.16))
        for s in (-1,1):
            leaf(st,p,p+V((s*.054,.047,.103)),.020,"Sprout_Green")
    st_obj=st.build(col,root,mats)

    return st_obj, rows


# ---------------------------------------------------------------------------
# 4. Harvest Loading Bin & Grain Sacks (-Y, -X Pickup Porch)
# ---------------------------------------------------------------------------


def build_harvest_bin(col, root, mats) -> tuple[bpy.types.Object, bpy.types.Object]:
    hb = PartBuilder("harvest_bin", (-1.04, -0.92, 0.18))

    # Open low timber grain-loading wain crib (X in [-1.62, -0.52], Y in [-1.52, -0.44])
    hb.add_span(-1.60, -0.54, -1.50, -0.46, 0.16, 0.28, "Timber_Oak", bevel=0.01)
    # 4 corner posts + side slats
    for px in (-1.54, -0.60):
        for py in (-1.44, -0.52):
            hb.add_box((px, py, 0.42), (0.09, 0.09, 0.48), "Timber_Oak", bevel=0.008)
    for sz in (0.36, 0.54):
        hb.add_span(-1.58, -0.56, -1.50, -1.42, sz - 0.04, sz + 0.04, "Timber_Oak")
        hb.add_span(-1.58, -0.56, -0.54, -0.46, sz - 0.04, sz + 0.04, "Timber_Oak")
        hb.add_span(-1.58, -1.50, -1.48, -0.48, sz - 0.04, sz + 0.04, "Timber_Oak")
    # The owner's badge carries the same eight-rayed star and sword as the
    # Round Table infantry. The blue escutcheon hangs from the crib rail.
    hb.add_span(-1.58,-.56,-1.509,-1.428,.614,.656,"Recessed_Steel")
    origin=V((-1.079,-1.505,.443))
    shield=[(-.15,.153),(.15,.153),(.128,-.035),(0,-.14),(-.128,-.035)]
    hb.add_extruded_poly_frame(shield,origin,X,Z,-Y,.006,.021,"Heraldic_Brass")
    hb.add_extruded_poly_frame([(x*.85,y*.85) for x,y in shield],origin,X,Z,-Y,.020,.026,"team_color")
    star=[((.061 if i%2==0 else .017)*cos(i*pi/8),.057+(.067 if i%2==0 else .017)*sin(i*pi/8))
          for i in range(16)]
    hb.add_extruded_poly_frame(star,origin,X,Z,-Y,.026,.029,"Heraldic_Brass")
    hb.add_extruded_poly_frame([(-.013,.022),(.013,.022),(.01,-.056),(0,-.092),(-.01,-.056)],
                               origin,X,Z,-Y,.026,.03,"Heraldic_Brass")
    hb_obj=hb.build(col,root,mats)

    hs=PartBuilder("harvest_sacks",(-1.04,-.98,.28))
    for x,y,z,rad,height,angle in [
        (-1.32,-1.18,.27,.194,.46,-.14),(-.92,-1.17,.27,.205,.49,.12),
        (-1.25,-.79,.27,.192,.53,.10),(-.86,-.78,.27,.185,.52,-.18)]:
        rings=[(0,.70),(.12,1.00),(.40,1.05),(.64,1.02),(.79,.72),(.91,.23),(.94,.21),(1,.35)]
        verts=[]
        faces=[]
        for j,(h,w) in enumerate(rings):
            for k in range(10):
                theta=k*2*pi/10+.17+.067*sin(h*pi)
                fold=1+(.135 if h>.76 else .023)*cos(k*2.5*h+1.2)
                rim=(.025*cos(k*2.0+.7) if j==len(rings)-1 else .012*sin(k*2+h) if j in (2,3,4) else 0)
                verts.append((x+rad*(1.05*w*fold*cos(theta)+angle*h),y+rad*w*fold*.89*sin(theta),z+height*h+rim))
                if j:
                    a=(j-1)*10+k
                    b=(j-1)*10+(k+1)%10
                    faces.append((a,b,b+10,a+10))
        faces+=[tuple(reversed(range(10))),tuple(range(len(verts)-10,len(verts)))]
        hs.add_faces(verts,faces,"Sack_Cloth")
        tie=V((x+rad*angle*.935,y,z+height*.935))
        hs.add_cyl(tie-Z*.009,tie+Z*.009,.048,.048,seg=10,mat="Wheat_Stalk")
        hs.add_cyl(tie+Y*.03,tie+Y*.071-Z*.065,.009,.006,seg=4,mat="Wheat_Stalk")
    hs_obj=hs.build(col,hb_obj,mats)

    # A hanging grain riddle feeds the sacks below. The link swings from the
    # barn hatch while the timber crib and the filled grain sacks stay grounded.
    pivot=V((-1.435,.033,1.136))
    sieve=PartBuilder("grain_riddle",tuple(pivot))
    end=pivot+V((.057,-.750,-.405))
    right=(end-pivot).normalized().cross(Z).normalized()
    for side in (-1,1):
        a=pivot+right*side*.125
        b=end+right*side*.125
        sieve.add_cyl(a,b,.033,.029,seg=4,mat="Heartwood",twist_rad=pi/4)
    for i in range(10):
        c=pivot.lerp(end,i/9)
        sieve.add_cyl(c-right*.129,c+right*.129,.017,.017,seg=4,mat="Timber_Oak",twist_rad=pi/4)
    for side in (-1,1):
        c=end+right*side*.125
        sieve.add_cyl(c,c+V((0,.19,.41)),.012,.012,seg=5,mat="Recessed_Steel")
    sieve.build(col,root,mats)
    return hb_obj, hs_obj


# ---------------------------------------------------------------------------
# Assemble Scene & Save Farm.blend
# ---------------------------------------------------------------------------


def build_farm() -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.unit_settings.system = "METRIC"
    scene.unit_settings.scale_length = 1.0

    col = bpy.data.collections.new("farm")
    scene.collection.children.link(col)

    root = bpy.data.objects.new("farm_root", None)
    root.empty_display_type = "PLAIN_AXES"
    root.empty_display_size = 1.0
    col.objects.link(root)

    mats = build_materials()

    curb = build_curb_base(col, root, mats)
    barn, rotor, pennant = build_barn_and_windmill(col, root, mats)
    stubble, crop_rows = build_crops(col, root, mats)
    hbin, hsacks = build_harvest_bin(col, root, mats)

    all_meshes = [ob for ob in col.objects if ob.type == "MESH"]

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

    assert mn.x >= -1.96 and mx.x <= 1.96, f"X footprint exceeded 4x4 m: [{mn.x:.3f}, {mx.x:.3f}]"
    assert mn.y >= -1.96 and mx.y <= 1.96, f"Y footprint exceeded 4x4 m: [{mn.y:.3f}, {mx.y:.3f}]"
    assert mn.z >= -0.02 and mx.z <= 4.70, f"Z bounds unexpected: [{mn.z:.3f}, {mx.z:.3f}]"

    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    bpy.context.preferences.filepaths.save_version = 0
    bpy.ops.wm.save_as_mainfile(filepath=OUT)
    print(f"BUILT {OUT} | parts={len(all_meshes)} tris={tri_count} | bounds=({mn.x:.2f}..{mx.x:.2f}, {mn.y:.2f}..{mx.y:.2f}, {mn.z:.2f}..{mx.z:.2f})")


if __name__ == "__main__":
    build_farm()
