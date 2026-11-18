"""Measure the shipped Streamliner against the guideway meshes and live power plates.

Run with Blender in background mode: blender -b --factory-startup --python-exit-code 1 -P clearance.py
"""
from collections import Counter
from math import atan2, cos, pi, sin
from pathlib import Path
import json
import re
import runpy

import numpy as np
from mathutils.bvhtree import BVHTree

HERE = Path(__file__).resolve().parent
ROOT = next(p for p in HERE.parents if (p / "project.godot").is_file())
kit = runpy.run_path(str(HERE.parents[1] / "Astra_Streamliner/validation/audit/measure.py"))
unpack, bvh = kit["unpack_glb"], kit["make_bvh"]
SCALE, RADIUS, SPAN = .6, 20., 6.


def vec_property(section, key, default=None):
    match = re.search(r"^" + key + r" = Vector3\(([^)]+)\)$", section, re.MULTILINE)
    if match:
        return np.array([float(x) for x in match[1].split(",")])
    if default is not None:
        return np.array(default)
    raise ValueError("Missing vector property " + key)


def yaw(angle):
    c, s = cos(angle), sin(angle)
    return np.array([[c,0,s], [0,1,0], [-s,0,c]])


def power_plate(kind):
    text = (ROOT / f"scenes/gameplay/track_{kind}.tscn").read_text()
    owner = text.split('[node name="Owner"', 1)[1].split('[node ', 1)[0]
    box = text.split('type="BoxMesh" id="owner_mesh"]', 1)[1].split('[', 1)[0]
    centre = vec_property(owner, "position") / SCALE
    half = vec_property(box, "size") / (2*SCALE)
    rotation = yaw(vec_property(owner, "rotation", (0,0,0))[1])
    sides = [(x,y,z) for y in (-1,1) for x,z in [(-1,-1),(-1,1),(1,1),(1,-1)]]
    points = (np.array(sides)*half) @ rotation.T + centre
    faces = [(0,1,2,3),(4,7,6,5),(0,4,5,1),(3,2,6,7),(1,5,6,2),(0,3,7,4)]
    samples = np.array([(x,1,z) for x in (-.8,0,.8) for z in (-.8,0,.8)])
    return BVHTree.FromPolygons(points.tolist(), faces), (samples*half) @ rotation.T + centre


def path_sample(s, curved, side):
    if not curved or s < 0:
        return np.array((0.,0.,s)), 0.
    a = min(s/RADIUS, pi/2)
    return np.array((side*(RADIUS*(1-cos(a))+max(0.,s-RADIUS*pi/2)),0.,RADIUS*sin(a))), side*a


def assemble_car(surfaces):
    blocks = {}
    all_faces = []
    n = 0
    for names, _, v, f in surfaces:
        sled = next((s for s in ("sled_cargo_front","sled_cargo_rear") if s in names), "body")
        blocks.setdefault(sled, []).append((slice(n,n+len(v)), v))
        all_faces.append(f+n)
        n += len(v)
    return np.empty((n,3)), np.concatenate(all_faces).tolist(), blocks


def car_at(front_s, direction, curved, side, car):
    vertices, indices, blocks = car
    front, a = path_sample(front_s,curved,side)
    lo, hi = SPAN, SPAN*1.25
    for _ in range(24):
        span = (lo+hi)/2
        rear, b = path_sample(front_s-direction*span,curved,side)
        if np.linalg.norm(front-rear)>SPAN: hi=span
        else: lo=span
    reverse = pi if direction < 0 else 0.
    delta = front-rear
    chord = atan2(delta[0], delta[2])
    axes = {"body": ((front+rear)*.5, chord,0),
            "sled_cargo_front": (front,a+reverse,SPAN*.5),
            "sled_cargo_rear": (rear,b+reverse,-SPAN*.5)}
    for bone, batch in blocks.items():
        origin, angle, z = axes[bone]
        rotation = yaw(angle)
        for rows, v in batch:
            vertices[rows] = (v-[0,0,z]) @ rotation.T + origin
    return BVHTree.FromPolygons(vertices.tolist(), indices, all_triangles=True), (front+rear)*.5, chord


def sample_lane(surfaces, plate, lens, kind, lane, car):
    fork = kind.startswith("fork")
    curved = kind=="curve" or (fork and lane==1)
    length = RADIUS*pi/2 if curved else 24. if fork else 8.
    side = -1. if kind=="fork_right" else 1.
    def shift(name):
        if not (fork and lane): return 0.
        if name.endswith("_blade_branch"): return .46
        if name.endswith("_blade_straight"): return -.46
        return 0.
    moved = [(n,m,v+[0,shift(n[-1]),0],f) for n,m,v,f in surfaces]
    rail, _, _ = bvh(moved)
    hits=Counter()
    smallest=float("inf")
    poses=0
    for d in (1,-1):
        # Start outside the tile and follow tangent extensions at joins.
        for s in np.arange(-6.5,length+6.51,.5):
            train,mid,angle = car_at(s,d,curved,side,car)
            poses+=1
            if train.overlap(rail): hits["train_vs_rail"]+=1
            if train.overlap(plate): hits["train_vs_power_plate"]+=1
            if poses%13: continue
            # Vertical clearance for sampled rays only. Surface intersection is
            # checked separately for every triangle at every tested pose.
            rotation=yaw(angle)
            for dx in np.arange(-1.8,1.81,.15):
                for dz in np.arange(-5.4,5.41,.15):
                    x,_,z = mid + rotation @ [dx,0,dz]
                    under = train.ray_cast((x,-1,z),(0,1,0),8)[0]
                    top = rail.ray_cast((x,8,z),(0,-1,0),10)[0]
                    if under is not None and top is not None:
                        smallest=min(smallest,SCALE*(under.y-top.y))
    if hits or not np.isfinite(smallest) or smallest <= 0:
        raise AssertionError((kind,lane,hits,smallest))
    for x,y,z in lens:
        top = rail.ray_cast((x,8,z),(0,-1,0),10)[0]
        if top is not None and top.y>y+.0001: raise AssertionError(("buried power plate",kind,x,z))
    return {"poses":poses,"train_vs_rail_contacts":0,"train_vs_power_plate_contacts":0,
            "sampled_vertical_gap_world_m":round(smallest,4),"visible_power_plate_samples":len(lens)}


def main():
    cargo,_,train = unpack(ROOT/"assets/models/units/maglev_train_cargo.glb")
    car=assemble_car(train)
    report={"train_sha256":cargo["sha256"],"pose_step_world_m":.3,"directions":["nose first","nose last"],"pieces":{}}
    for kind in ("straight","curve","fork_left","fork_right"):
        name="track_"+kind
        stats,nodes,surfaces=unpack(ROOT/f"assets/models/rails/maglev_{name}.glb")
        side=-1 if kind=="fork_right" else 1
        ends={"A":[0,0,0],"B":([20,0,20] if kind=="curve" else [0,0,8 if kind=="straight" else 24])}
        if kind.startswith("fork"): ends["C"]=[side*20,0,20]
        for suffix, point in ends.items():
            mat=np.array(nodes[name+"_"+suffix]["local_matrix_rows"])
            exit_angle=side*pi/2 if suffix=="C" or (suffix=="B" and kind=="curve") else 0.
            if not np.allclose(mat[:3,3],point,atol=1e-4) or not np.allclose(mat[:3,:3],yaw(exit_angle),atol=1e-4):
                raise AssertionError(("end marker transform",kind,suffix,mat))
        if kind.startswith("fork"):
            for suffix,expected in [("straight",0.),("branch",-.46)]:
                if abs(nodes[name+"_blade_"+suffix]["pivot_asset_xyz"][1]-expected)>.0001:
                    raise AssertionError(("blade rest pivot",kind,suffix))
        plate,samples=power_plate(kind)
        result={"glb_sha256":stats["sha256"],"triangles":stats["instanced_triangles"],"end_markers":len(ends)}
        for lane in range(2 if kind.startswith("fork") else 1):
            result["lane_"+str(lane)]=sample_lane(surfaces,plate,samples,kind,lane,car)
        report["pieces"][kind]=result
        print(kind, result,flush=True)
    (HERE/"clearance.json").write_text(json.dumps(report,indent=2)+"\n",encoding="utf-8")


if __name__=="__main__": main()
