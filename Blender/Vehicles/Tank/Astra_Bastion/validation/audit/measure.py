"""Check exported tank geometry, runtime pivots, track contracts, and turret clearance in Blender."""
from hashlib import sha256
import json
from math import cos, radians, sin
from pathlib import Path
import re
import runpy
import struct

import bpy
from mathutils.bvhtree import BVHTree
import numpy as np

HERE = Path(__file__).resolve().parent
ROOT = next(p for p in HERE.parents if (p/"project.godot").is_file())
OLD = ROOT / "assets/models/units/tank.glb"
NEW = HERE.parent.parent / "export/Bastion.glb"
helpers = runpy.run_path(str(ROOT / "Blender/Vehicles/Maglev/Astra_Streamliner/validation/audit/measure.py"))
unpack = helpers["unpack_glb"]
SCALE = .6
CONTRACT = ("Tank_Root","Tank_Hull","Tank_Turret","Barrel_Mount","Tank_Barrel","Barrel_Muzzle_Brake")
GEAR = tuple(prefix + side for prefix in ("Track_Links_", "Road_Wheels_", "Return_Rollers_",
                                            "Drive_Sprocket_", "Idler_Wheel_") for side in ("L","R"))


def summary(path):
    info, nodes, surfaces = unpack(path)
    body = np.concatenate([v for branch,_,v,_ in surfaces if "Tank_Turret" not in branch])
    pts = np.concatenate([v for _,_,v,_ in surfaces]) * np.array([-SCALE,SCALE,-SCALE])
    details = {}
    for key in ("bytes","node_count","mesh_nodes","unique_meshes","unique_surfaces","unique_triangles",
                "images","textures","animations","skins","materials","sha256"):
        details[key] = info[key]
    details["camera_light_count"] = info["cameras"] + info["punctual_lights"]
    details["bounds_gltf_xyz"] = info["asset_bounds_xyz"]
    details["bounds_world_after_wrapper_xyz"] = helpers["bounds"](pts)
    details["lower_vehicle_bounds_gltf_xyz"] = helpers["bounds"](body)
    details["central_hull_lower_face_world_m"] = round(nodes["Tank_Hull"]["surface_bounds_asset_xyz"]["min"][1] * SCALE,5)
    details["pivot_locations_gltf_xyz"] = {name:nodes[name]["pivot_asset_xyz"] for name in CONTRACT}
    blob = path.read_bytes()
    length = struct.unpack_from("<I",blob,12)[0]
    doc = json.loads(blob[20:20+length])
    details["embedded_images"] = []
    for image in doc.get("images",[]):
        record = {"name":image.get("name"),"mime":image.get("mimeType")}
        if "bufferView" in image:
            view = doc["bufferViews"][image["bufferView"]]
            offset = 28+length+view.get("byteOffset",0)
            record["encoded_bytes"] = view["byteLength"]
            record["sha256"] = sha256(blob[offset:offset+view["byteLength"]]).hexdigest()
            if image.get("mimeType") == "image/png":
                record["pixels"] = struct.unpack_from(">II",blob,offset+16)
        details["embedded_images"].append(record)
    return details,nodes,surfaces


def grouped(surfaces):
    pts,indices,names,offset = [],[],[],0
    for branch,_,v,f in surfaces:
        pts.append(v)
        indices.append(f+offset)
        names.extend([branch[-1]]*len(f))
        offset += len(v)
    return np.concatenate(pts),np.concatenate(indices).tolist(),names


def bvh(points,indices):
    return BVHTree.FromPolygons(points.tolist(),indices,all_triangles=True)


def skirt_sweep(nodes,surfaces):
    """Run the installed shader's rigid shoe interpolation against the two armour skirts."""
    shader = (ROOT/"assets/shaders/tank_running_gear.gdshader").read_text()
    table = shader.partition("const vec3 LINKS[37]")[2].partition("};")[0]
    rest = np.array([tuple(map(float,match)) for match in re.findall(
        r"vec3\(([-.\d]+),\s*([-.\d]+),\s*([-.\d]+)\)",table)])
    assert rest.shape==(37,3)
    ahead = np.roll(rest,1,axis=0)
    delta = (ahead[:,2]-rest[:,2]+np.pi)%(2*np.pi)-np.pi
    results = {}
    for side in ("L","R"):
        name = "Track_Links_"+side
        track = next(s for s in surfaces if s[0][-1]==name)
        local = np.array(nodes[name]["local_matrix_rows"])
        verts = (track[2]-local[:3,3]) @ np.linalg.inv(local[:3,:3]).T
        verts = verts.reshape(37,24,3)
        origin = verts[:,:,[0,2]]-rest[:,None,:2]
        skirt = [s for s in surfaces if s[0][-1].startswith(("Skirt_"+side,"Apron_"+side))]
        casing = [s for s in surfaces if s[0][-1]=="Headlamp_housing_"+side]
        front = [s for s in skirt if s[0][-1]=="Skirt_"+side+"_Front"]
        lamp_v,lamp_i,_ = grouped(casing)
        front_v,front_i,_ = grouped(front)
        assert bvh(lamp_v,lamp_i).overlap(bvh(front_v,front_i)), "Unseated headlight housing on "+side
        skirt += casing + [s for s in surfaces if s[0][-1]=="Tank_Hull"]
        sv,si,sn = grouped(skirt)
        shell = bvh(sv,si)
        for t in np.linspace(0,1,17):
            moved = verts.copy()
            c,s = np.cos(delta*t)[:,None],np.sin(delta*t)[:,None]
            centre = (1-t)*rest[:,:2]+t*ahead[:,:2]
            moved[:,:,0] = c*origin[:,:,0]-s*origin[:,:,1]+centre[:,None,0]
            moved[:,:,2] = s*origin[:,:,0]+c*origin[:,:,1]+centre[:,None,1]
            posed = moved.reshape(-1,3) @ local[:3,:3].T + local[:3,3]
            contacts = shell.overlap(bvh(posed,track[3].tolist()))
            if contacts:
                i,_ = contacts[0]
                triangle = sv[si[i]].round(4).tolist()
                raise AssertionError(f"Track {side}, phase {t}: intersects {sn[i]} at triangle {triangle}")
        results[side] = 0
    return {"phases_per_side":17,"tested_fixed_parts":["upper and lower skirts","lamp housing and saddle","hull casting"],
            "both_lamp_housings_seated_in_front_shoulders":True,"tread_intersections_by_side":results}


def sweep(nodes, surfaces):
    turret_pos = np.array(nodes["Tank_Turret"]["pivot_asset_xyz"])
    low_parts = [s for s in surfaces if "Tank_Turret" not in s[0]]
    high_parts = [s for s in surfaces if "Tank_Turret" in s[0]]
    low_verts,low_indices,low_names = grouped(low_parts)
    low_tree = bvh(low_verts,low_indices)
    lower_top = max(v[:,1].max() for path,_,v,_ in low_parts if path[-1]!="Turret_Ring")
    barrel_floor = min(v[:,1].min() for path,_,v,_ in high_parts if "Tank_Barrel" in path)
    gaps = {}
    overlaps = set()
    for recoil in (0., .55):
        components = [(branch,mat,verts-np.array([0,0,recoil]) if "Tank_Barrel" in branch else verts,idx)
                      for branch,mat,verts,idx in high_parts]
        verts,indices,names = grouped(components)
        clearance = float(verts[:,1].min()-low_verts[:,1].max()) * SCALE
        # This bound applies to the entire continuous slew if positive, including unsampled angles.
        gaps[str(recoil)] = round(clearance,6)
        for degrees in range(360):
            angle = radians(degrees)
            rot = np.array([[cos(angle),0,sin(angle)],[0,1,0],[-sin(angle),0,cos(angle)]])
            moving = bvh((verts-turret_pos) @ rot.T + turret_pos,indices)
            for a,b in moving.overlap(low_tree):
                overlaps.add((names[a],low_names[b]))
    if overlaps:
        raise AssertionError(f"Turret to lower vehicle contact: {sorted(overlaps)}")
    guard_parts = [s for s in high_parts if "Barrel_Mount" not in s[0] and s[0][-1]!="Tank_Turret"]
    gv,gi,gn = grouped(guard_parts)
    guards = bvh(gv,gi)
    gun_verts,gun_indices,gun_names = grouped([s for s in high_parts if "Tank_Barrel" in s[0]])
    for recoil in np.linspace(0.,.55,23):
        moving = bvh(gun_verts-np.array([0.,0.,recoil]),gun_indices)
        for a,b in moving.overlap(guards):
            overlaps.add((gun_names[a],gn[b]))
    if overlaps:
        raise AssertionError(f"External recoil clearance: {sorted(overlaps)}")
    return {"turret_positions":720,"yaw_step_degrees":1,"recoil_endpoints_authored_m":[0,.55],
            "rotating_vs_lower_mesh_intersections":0,"continuous_vertical_separation_lower_bound_world_m":gaps,
            "barrel_above_hull_and_skirts_world_m":round((barrel_floor-lower_top)*SCALE,5),
            "gun_to_turret_accessory_recoil_samples":23,"gun_to_turret_accessory_intersections":0,
            "gun_contact_exclusions":["Barrel_Mount socket","Tank_Turret core"]}


def main():
    a,an,asurf = summary(OLD)
    b,bn,bsurf = summary(NEW)
    for name in (*CONTRACT,*GEAR):
        if an[name]["parent"] != bn[name]["parent"] or not np.allclose(an[name]["local_matrix_rows"],
                bn[name]["local_matrix_rows"],atol=1e-5,rtol=0):
            raise AssertionError(f"Handoff transform changed: {name}")
    original = {s[0][-1]:s for s in asurf if s[0][-1] in GEAR}
    indexed = []
    for branch,_,v,f in bsurf:
        if branch[-1] not in GEAR: continue
        ov,of = original.pop(branch[-1])[2:]
        if np.array_equal(v,ov) and np.array_equal(f,of):
            indexed.append(branch[-1])
        elif branch[-1].startswith(("Track_Links","Road_Wheels","Return_Rollers")):
            raise AssertionError(f"Shader-indexed geometry changed: {branch[-1]}")
        else:
            # The idlers and sprockets rotate as nodes. Their shape can survive reindexing.
            def triangle_keys(verts,faces):
                return sorted(tuple(sorted(tuple(np.round(p,4)) for p in tri)) for tri in verts[faces])
            assert triangle_keys(v,f)==triangle_keys(ov,of), branch[-1]
    assert not original
    surface_mats = {branch[-1]:set(mat for br,mat,_,_ in bsurf if br[-1] == branch[-1]) for branch,_,_,_ in bsurf}
    for fixed in ("Neon_Sensor_Lens","Neon_Headlamp_L","Neon_Headlamp_R","Service_housing"):
        assert "team_color" not in surface_mats[fixed], fixed
    team_nodes = [name for name,mats in surface_mats.items() if "team_color" in mats]
    muzzle = np.array(bn["Barrel_Mount"]["pivot_asset_xyz"]) + np.array([0,0,5.65])
    tip = bn["Barrel_Muzzle_Brake"]["surface_bounds_asset_xyz"]["max"][2]
    assert abs(muzzle[2]-tip) < .003, (muzzle,tip)
    data = {"Blender":bpy.app.version_string, "accepted":a, "bastion":b, "team_paint_meshes":team_nodes,
            "checks":{"matching_named_transforms":len(CONTRACT)+len(GEAR),
                      "unchanged_gear_geometry":len(GEAR),"identical_gear_positions_and_index_order":sorted(indexed),
                      "rest_muzzle_gltf_xyz":list(muzzle),"rest_muzzle_delta_world_m":round(abs(muzzle[2]-tip)*SCALE,6),
                      "clearance":sweep(bn,bsurf),"skirts":skirt_sweep(bn,bsurf)}}
    (HERE/"geometry.json").write_text(json.dumps(data,indent=2)+"\n",encoding="utf-8")
    print("BASTION_EXPORTED_GEOMETRY_PASSED",data["checks"])


if __name__=="__main__":
    main()
