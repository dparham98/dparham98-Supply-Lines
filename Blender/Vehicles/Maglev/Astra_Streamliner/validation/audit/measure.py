"""Measure exported GLB vertices in glTF coordinates. Run with Blender's bundled Python.

blender -b --factory-startup --python-exit-code 1 --python <this-file>
"""
from collections import Counter
from hashlib import sha256
import json
from math import asin, cos, radians, sin
from pathlib import Path
import struct

import bpy
from mathutils import Matrix, Quaternion, Vector
from mathutils.bvhtree import BVHTree
import numpy as np


AUDIT = Path(__file__).resolve().parent
PACKAGE = AUDIT.parent.parent
PROJECT = next(p for p in PACKAGE.parents if (p / "project.godot").is_file())
CARGO = PROJECT / "assets/models/units/maglev_train_cargo.glb"
TRUCK = PROJECT / "assets/models/units/cargo_truck.glb"
TRACK = PROJECT / "assets/models/rails/maglev_track_curve.glb"
EXPORT = PACKAGE / "export/maglev_train_cargo.glb"
SCALE = 0.6


def rnd(array):
    return np.round(np.asarray(array, dtype=float), 5).tolist()


def write_json(filename, data):
    (AUDIT / filename).write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")


def bounds(vertices):
    low = vertices.min(axis=0)
    high = vertices.max(axis=0)
    return {"min": rnd(low), "max": rnd(high), "size": rnd(high - low)}


def unpack_glb(path):
    """Read uncompressed exported coordinates and indices with their accessor strides."""
    data = path.read_bytes()
    length, = struct.unpack_from("<I", data, 12)
    doc = json.loads(data[20:20 + length])
    binary = memoryview(data)[28 + length:]

    def read(index):
        a = doc["accessors"][index]
        view = doc["bufferViews"][a["bufferView"]]
        dtype = np.dtype({5121: "<u1", 5123: "<u2", 5125: "<u4", 5126: "<f4"}[a["componentType"]])
        width = {"SCALAR": 1, "VEC3": 3}[a["type"]]
        offset = view.get("byteOffset", 0) + a.get("byteOffset", 0)
        stride = view.get("byteStride", dtype.itemsize * width)
        return np.ndarray((a["count"], width), dtype, binary, offset, (stride, dtype.itemsize))

    nodes = {}
    surfaces = []

    def visit(i, ancestors, parent_matrix):
        n = doc["nodes"][i]
        name = n["name"]
        if "matrix" in n:
            local = np.array(n["matrix"]).reshape(4, 4).T
        else:
            q = n.get("rotation", (0, 0, 0, 1))
            rot = Quaternion((q[3], q[0], q[1], q[2]))
            local = np.array(Matrix.LocRotScale(n.get("translation", (0, 0, 0)), rot, n.get("scale", (1, 1, 1))))
        world = parent_matrix @ local
        node = {"parent": ancestors[-1] if ancestors else None,
                "local_matrix_rows": rnd(local), "pivot_asset_xyz": rnd(world[:3, 3])}
        nodes[name] = node
        branch = ancestors + [name]
        sofar = []
        if "mesh" in n:
            for p in doc["meshes"][n["mesh"]]["primitives"]:
                assert p.get("mode", 4) == 4
                v = read(p["attributes"]["POSITION"]) @ world[:3, :3].T + world[:3, 3]
                indices = (read(p["indices"]).ravel() if "indices" in p else np.arange(len(v))).reshape(-1, 3)
                mat = doc["materials"][p["material"]]["name"]
                surfaces.append((branch, mat, v, indices))
                sofar.append(v)
            node["surface_bounds_asset_xyz"] = bounds(np.concatenate(sofar))
        for child in n.get("children", []):
            visit(child, branch, world)

    for i in doc["scenes"][doc.get("scene", 0)]["nodes"]:
        visit(i, [], np.eye(4))
    verts = np.concatenate([v for _, _, v, _ in surfaces])
    stats = {
        "file": path.relative_to(PROJECT).as_posix(),
        "sha256": sha256(data).hexdigest(), "bytes": len(data),
        "asset_bounds_xyz": bounds(verts), "world_bounds_xyz_at_0_6": bounds(SCALE * verts),
        "node_count": len(nodes), "mesh_nodes": sum("mesh" in n for n in doc["nodes"]),
        "unique_meshes": len(doc["meshes"]),
        "unique_surfaces": sum(len(m["primitives"]) for m in doc["meshes"]),
        "unique_triangles": sum(doc["accessors"][p.get("indices",p["attributes"]["POSITION"])]["count"]//3
                                for m in doc["meshes"] for p in m["primitives"]),
        "surface_instances": len(surfaces),
        "instanced_triangles": sum(len(f) for _, _, _, f in surfaces),
        "exported_position_entries_including_surface_splits": sum(len(v) for _, _, v, _ in surfaces),
        "materials": [m["name"] for m in doc["materials"]], "images": len(doc.get("images", [])),
        "textures": len(doc.get("textures", [])), "skins": len(doc.get("skins", [])),
        "animations": len(doc.get("animations", [])), "cameras": len(doc.get("cameras", [])),
        "punctual_lights": len(doc.get("extensions", {}).get("KHR_lights_punctual", {}).get("lights", [])),
    }
    return stats, nodes, surfaces


def make_bvh(surfaces):
    vertices, faces, labels = [], [], []
    offset = 0
    for branch, material, v, f in surfaces:
        vertices.append(v)
        faces.append(f + offset)
        labels.extend([(branch[-1], material)] * len(f))
        offset += len(v)
    v = np.concatenate(vertices)
    return BVHTree.FromPolygons(v.tolist(), np.concatenate(faces).tolist(), all_triangles=True), labels, v


def visible_surfaces(surfaces):
    """Count first visible samples for ownership and the load indicator, independent of lights."""
    tree, labels, vertices = make_bvh(surfaces)
    paint_by_yaw = {}
    indicator_by_yaw = {}
    for heading in (0, 45, 90, 135, 180, 225, 270, 315):
        a, p = radians(heading), radians(50)
        toward_camera = np.array([sin(a)*cos(p), sin(p), cos(a)*cos(p)])
        horizontal = np.array([cos(a), 0, -sin(a)])
        vertical = np.cross(toward_camera, horizontal)
        u, v = vertices @ horizontal, vertices @ vertical
        du = max(np.ptp(u), np.ptp(v)) / 200
        visible, paint, indicator = 0, 0, 0
        direction = Vector(-toward_camera)
        for x in np.arange(u.min()+du/2, u.max(), du):
            start = toward_camera * 30 + horizontal * x
            for y in np.arange(v.min()+du/2, v.max(), du):
                hit = tree.ray_cast(Vector(start + y * vertical), direction, 60)[2]
                if hit is not None:
                    visible += 1
                    paint += int(labels[hit][1] == "team_color")
                    indicator += int(labels[hit][0] == "cargo_car_indicator")
        paint_by_yaw[str(heading)] = round(100 * paint / visible, 2)
        indicator_by_yaw[str(heading)] = round(100 * indicator / visible, 3)
    return paint_by_yaw, indicator_by_yaw


def measure_pose_visibility(stats, surfaces):
    loaded = [(branch, m, v + [0, 0.32, 0] if "cargo_car_indicator" in branch else v, f)
              for branch, m, v, f in surfaces]
    stats["visible_team_percent_at_50deg_pitch_by_yaw"], rest = visible_surfaces(surfaces)
    _, raised = visible_surfaces(loaded)
    stats["visible_indicator_percent_at_50deg_pitch_by_yaw"] = {"empty": rest, "loaded": raised}
    stats["loaded_world_bounds_xyz_at_0_6"] = bounds(SCALE * np.concatenate([v for _, _, v, _ in loaded]))


def exposed_body_paint(surfaces):
    """Estimate physical paint area on cargo_body surfaces visible from at/above the horizon."""
    tree, _, _ = make_bvh(surfaces)
    body = [(v[f], np.full(len(f), material == "team_color"))
            for branch, material, v, f in surfaces if branch[-1] == "cargo_body"]
    triangles = np.concatenate([tri for tri,_ in body])
    is_team = np.concatenate([mask for _,mask in body])
    normals = np.cross(triangles[:,1]-triangles[:,0], triangles[:,2]-triangles[:,0])
    areas = np.linalg.norm(normals, axis=1)/2
    normals /= np.maximum(areas*2, 1e-14)[:,None]
    rng = np.random.default_rng(20261117)
    samples = 50000
    ids = rng.choice(len(triangles), samples, p=areas/areas.sum())
    u,v = rng.random((2,samples))
    flip = u+v > 1
    u[flip], v[flip] = 1-u[flip], 1-v[flip]
    faces = triangles[ids]
    origins = faces[:,0]+u[:,None]*(faces[:,1]-faces[:,0])+v[:,None]*(faces[:,2]-faces[:,0])+normals[ids]*0.0001
    visible = np.zeros(samples, dtype=bool)
    # 17 directions. Exclude grazing rays and the lower hemisphere. Recesses which none of
    # these directions can see are excluded from both numerator and denominator.
    for x in (-1,0,1):
        for y in (0,1):
            for z in (-1,0,1):
                if not any((x,y,z)):
                    continue
                d = Vector((x,y,z)).normalized()
                trial = np.flatnonzero((~visible) & ((normals[ids] @ np.array(d)) > .12))
                visible[trial] = [tree.ray_cast(Vector(origins[i]), d, 30)[2] is None for i in trial]
    return {"percent": round(float(100*is_team[ids][visible].mean()), 2), "samples": samples,
            "visible_samples": int(visible.sum()), "directions": 17,
            "scope": "Area-weighted samples on the fixed cargo_body mesh, front-facing and unobstructed in at least one upper-hemisphere or horizontal direction. Excludes underside, moving parts and occluded underlying paint panels."}


def owner_marker(world_position):
    centre = np.array(world_position) / SCALE
    half = np.array([0.3, 0.04, 0.3]) / SCALE
    corners = [centre + np.array([x, y, z])*half for x, y, z in
               ((-1,-1,-1),(-1,-1,1),(1,-1,1),(1,-1,-1),(-1,1,-1),(-1,1,1),(1,1,1),(1,1,-1))]
    return BVHTree.FromPolygons(corners, [(0,1,2,3),(4,7,6,5),(0,4,5,1),
                                         (3,2,6,7),(1,5,6,2),(0,3,7,4)])


def straight_clearance(surfaces, track_surfaces):
    rail, _, _ = make_bvh(track_surfaces)
    status = owner_marker((0, .7, 2.4))
    hits, owner_hits = Counter(), Counter()
    for z in np.linspace(-5.5,13.5,77):
        mapped = [(branch, m, v + (0, 0, z), f) for branch, m, v, f in surfaces]
        car, labels, _ = make_bvh(mapped)
        hits.update({labels[i][0] for i,_ in car.overlap(rail)})
        owner_hits.update({labels[i][0] for i,_ in car.overlap(status)})
    return {"poses": 77, "step_world_m": .15,
            "train_nodes_meeting_exported_rail_triangles_by_number_of_poses": dict(hits),
            "train_nodes_meeting_owner_marker_triangles_by_number_of_poses": dict(owner_hits)}


def curve_clearance(surfaces, track_surfaces, kind="curve"):
    """Sweep the exported train against the accepted curved bed, using analytic chord poses."""
    side = -1 if kind == "fork_right" else 1
    rail_part = track_surfaces
    if kind.startswith("fork"):
        # The archived meshes are authored in straight-lane state. set_route(1) drops
        # the straight blade and raises the branch, each by 0.46 unscaled metres.
        rail_part = []
        for branch, material, v, f in track_surfaces:
            dy = 0.46 if branch[-1].endswith("_blade_branch") else -0.46 if branch[-1].endswith("_blade_straight") else 0
            rail_part.append((branch, material, v+[0,dy,0], f))
    rail, _, _ = make_bvh(rail_part)
    r = 20.0
    half_angle = asin(3.0/r)
    hits = Counter()
    outside_margin = float("inf")
    vertical_gap = float("inf")
    owner_hits = Counter()
    # The static status plate is authored in track_curve.tscn, separate from the rail GLB.
    status = owner_marker((3.515, 0.7, 8.485) if kind == "curve" else (0, 0.7, 3))
    def point(theta):
        return np.array([side*r*(1-cos(theta)), 0, r*sin(theta)])

    # Chassis centre is the midpoint between sleds. Sleds turn independently to their tangents.
    for degree in range(18, 73):
        angle = radians(degree)
        front, rear = angle+half_angle, angle-half_angle
        centre = (point(front) + point(rear))/2
        mapped = []
        for branch, material, v, f in surfaces:
            pose_angle, origin, local_z = angle, centre, 0
            if "sled_cargo_front" in branch:
                pose_angle, origin, local_z = front, point(front), 3
            if "sled_cargo_rear" in branch:
                pose_angle, origin, local_z = rear, point(rear), -3
            co, si = cos(pose_angle), side*sin(pose_angle)
            m = np.array([(co, 0, si), (0, 1, 0), (-si, 0, co)])
            placed = (v - [0, 0, local_z]) @ m.T + origin
            radial = np.hypot(placed[:, 0]-side*r, placed[:, 2])
            outside_margin = min(outside_margin, float((2.5 - np.abs(radial-r)).min())*SCALE)
            mapped.append((branch, material, placed, f))
        car, labels, _ = make_bvh(mapped)
        touched = {labels[car_face][0] for car_face, rail_face in car.overlap(rail)}
        hits.update(touched)
        owner_hits.update({labels[car_face][0] for car_face, _ in car.overlap(status)})
        # Sample both silhouettes at the same ground points along the car's footprint.
        # The exact surface-intersection check above runs at every pose.
        if degree in (25, 45, 65):
            for longitudinal in np.arange(-5.5, 5.51, 0.075):
                for lateral in np.arange(-1.85, 1.86, 0.075):
                    x = centre[0] + lateral*cos(angle) + side*longitudinal*sin(angle)
                    z = centre[2] - side*lateral*sin(angle) + longitudinal*cos(angle)
                    lower = car.ray_cast((x, -1, z), (0, 1, 0), 10)[0]
                    upper = rail.ray_cast((x, 8, z), (0, -1, 0), 10)[0]
                    if lower is not None and upper is not None:
                        vertical_gap = min(vertical_gap, SCALE*(lower.y-upper.y))
    return {"poses": 55, "angular_step_deg": 1, "chassis_centre_heading_range_deg": [18, 72],
            "rail_half_width_world_m": 1.5, "minimum_lateral_vertex_margin_to_ideal_edge_world_m": round(outside_margin, 5),
            "train_nodes_meeting_exported_rail_triangles_by_number_of_poses": dict(hits),
            "minimum_sampled_vertical_gap_over_rail_mesh_world_m": round(vertical_gap, 5),
            "vertical_sample": "4.5 cm grid in car frame at 25, 45, 65 degrees, uppermost rail to lowest train surface.",
            "train_nodes_meeting_owner_marker_triangles_by_number_of_poses": dict(owner_hits),
            "scope": f"{kind} GLB and separate owner indicator, tangent-following sleds. Forks use settled branch-lane switch positions. Runtime movement is tested separately."}


def main():
    old, old_nodes, old_surfaces = unpack_glb(CARGO)
    track, _, rail_surfaces = unpack_glb(TRACK)
    straight = unpack_glb(TRACK.with_name("maglev_track_straight.glb"))[2]
    forks = {kind: unpack_glb(TRACK.with_name(f"maglev_track_{kind}.glb"))[2]
             for kind in ("fork_left", "fork_right")}
    truck, _, _ = unpack_glb(TRUCK)
    measure_pose_visibility(old, old_surfaces)
    old["estimated_exposed_body_paint_area"] = exposed_body_paint(old_surfaces)
    old["analytic_curve_mesh_clearance"] = curve_clearance(old_surfaces, rail_surfaces)
    old["straight_mesh_clearance"] = straight_clearance(old_surfaces, straight)
    old["analytic_fork_branch_mesh_clearance"] = {k: curve_clearance(old_surfaces, v, k) for k,v in forks.items()}
    before = json.loads((AUDIT/"reference_sha256_before.json").read_text(encoding="utf-8-sig"))
    results = {"blender": bpy.app.version_string, "baseline": old, "truck": truck, "curve": track}
    write_json("accepted_cargo_nodes.json", old_nodes)
    if EXPORT.is_file():
        new, new_nodes, new_surfaces = unpack_glb(EXPORT)
        measure_pose_visibility(new, new_surfaces)
        new["estimated_exposed_body_paint_area"] = exposed_body_paint(new_surfaces)
        new["analytic_curve_mesh_clearance"] = curve_clearance(new_surfaces, rail_surfaces)
        new["straight_mesh_clearance"] = straight_clearance(new_surfaces, straight)
        new["analytic_fork_branch_mesh_clearance"] = {k: curve_clearance(new_surfaces, v, k) for k,v in forks.items()}
        results["prototype"] = new
        fixed = {}
        for name in old_nodes:
            same = name in new_nodes and np.allclose(old_nodes[name]["pivot_asset_xyz"], new_nodes[name]["pivot_asset_xyz"], atol=1e-4)
            fixed[name] = {"present": name in new_nodes, "asset_pivot_matches": bool(same),
                           "parent_matches": name in new_nodes and old_nodes[name]["parent"] == new_nodes[name]["parent"],
                           "local_transform_matches": name in new_nodes and bool(np.allclose(old_nodes[name]["local_matrix_rows"], new_nodes[name]["local_matrix_rows"], atol=1e-4))}
        results["accepted_node_contracts"] = fixed
        write_json("prototype_nodes.json", new_nodes)
        after = {path: sha256((PROJECT/path).read_bytes()).hexdigest() for path in before}
        write_json("reference_sha256_after.json", after)
        results["reference_hashes_match_before_after"] = before == after
    write_json("mesh_metrics.json", results)
    print("Measured", ", ".join([old["file"]] + ([new["file"]] if EXPORT.is_file() else [])))


if __name__ == "__main__":
    main()
