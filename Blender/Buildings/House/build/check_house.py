"""Verify the shipped GLB geometry, roof clearance, faction paint and authored clips."""
from pathlib import Path
import json
import struct

import bpy
from mathutils import Vector


path=Path(__file__).resolve().parents[1]/"export"/"house.glb"
data=path.read_bytes()
chunk_size=struct.unpack_from("<I",data,12)[0]
doc=json.loads(data[20:20+chunk_size])
assert {anim["name"] for anim in doc["animations"]}=={"Build","Idle","Die"}
assert all("bufferView" in img for img in doc["images"])
assert {"team_color","team_color_shadow"} <= {mat["name"] for mat in doc["materials"]}
assert not any("solar" in ob["name"].lower() or "upgrade" in ob["name"].lower() for ob in doc["nodes"])

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=str(path))
scene=bpy.context.scene

def pose(clip,frame):
    for ob in scene.objects:
        if ob.animation_data:
            ob.animation_data.action=None
            for track in ob.animation_data.nla_tracks:
                track.mute=track.name!=clip
    # Blender's glTF reader puts clip time zero on frame 1.
    scene.frame_set(frame+1)
    bpy.context.view_layer.update()

def bounds():
    coords=[ob.matrix_world@v.co for ob in scene.objects if ob.type=="MESH" for v in ob.data.vertices]
    return [min(v[i] for v in coords) for i in range(3)],[max(v[i] for v in coords) for i in range(3)]

pose("Idle",0)
lo,hi=bounds()
assert min(lo[:2])>=-2.0001 and max(hi[:2])<=2.0001,(lo,hi)
assert -.002<=lo[2]<=.002 and 3.7<hi[2]<4.2,(lo,hi)
static_height=hi[2]
deps=bpy.context.evaluated_depsgraph_get()
# A vertical ray on the full shingle fields may hit only the named roof slope.
# The front ridge, cap, façade and eaves are deliberately outside these samples.
for y in [-1.7,-1.35,-.85,-.74,-.25,.25,.74,.85,1.35,1.7]:
    for x in [.2,.40,.56,.74,.79,.94,1.24,1.50,1.70]:
        for sign in (-1,1):
            hit,pt,normal,face,ob,matrix=scene.ray_cast(deps,Vector((sign*x,y,4.8)),Vector((0,0,-1)))
            assert hit and ob.name.startswith("Shingle_roof_"),(x,y,ob,pt)
pose("Build",0)
assert bounds()[1][2]<.01,bounds()
pose("Build",48)
assert min(bpy.data.objects["Shingle_roof_west"].scale)<.02
assert min(bpy.data.objects["Timber_portals"].scale)>.97
pose("Build",96)
assert abs(bounds()[1][2]-static_height)<.015,(bounds(),static_height,[(o.name,tuple(o.scale)) for o in scene.objects])
pose("Die",54)
assert bounds()[1][2]<0
triangles=sum(doc["accessors"][p["indices"]]["count"]//3 for m in doc["meshes"] for p in m["primitives"])
print("HOUSE_OK", "bounds",lo,hi,"triangles",triangles,"bytes",len(data),"clean roof samples",180)
