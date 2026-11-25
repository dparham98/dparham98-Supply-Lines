"""Reimport both exports and check material, clearance and animation contracts."""
from pathlib import Path
import json
import struct

import bpy
from mathutils import Vector


export=Path(__file__).resolve().parents[1]/"export"
def document(path):
    data=path.read_bytes()
    assert data[:4]==b"glTF"
    size=struct.unpack_from("<I",data,12)[0]
    return json.loads(data[20:20+size])


def imported(path):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.render.fps=24
    bpy.ops.import_scene.gltf(filepath=str(path))
    return bpy.context.scene


def evaluate(clip,frame):
    for obj in bpy.data.objects:
        ad=obj.animation_data
        if ad:
            ad.action=None
            for track in ad.nla_tracks:
                track.mute=track.name!=clip
    bpy.context.scene.frame_set(frame)
    bpy.context.view_layer.update()


def bounds():
    points=[obj.matrix_world@v.co for obj in bpy.data.objects if obj.type=="MESH" for v in obj.data.vertices]
    return tuple(min(p[i] for p in points) for i in range(3)),tuple(max(p[i] for p in points) for i in range(3))


file=export/"keep.glb"
doc=document(file)
assert {a["name"] for a in doc["animations"]}=={"Idle","Build","Train","LaunchBalloon","Die"}
assert not doc.get("cameras") and not doc.get("extensions",{}).get("KHR_lights_punctual")
assert {"Royal_Enamel","team_color","Honey_Oak","Heart_Oak","Smoked_Oak","Ivory_Armor"}<={m["name"] for m in doc["materials"]}
assert len(doc["images"])==3 and all("bufferView" in image for image in doc["images"])
scene=imported(file)
evaluate("Idle",0)
low,high=bounds()
assert min(low[:2])>=-4.901 and max(high[:2])<=4.901 and -.006<=low[2]<.016 and high[2]<9.50,(low,high)
gate=bpy.data.objects["portcullis"]
closed=gate.matrix_world.translation.copy()
assert closed.y< -4 and closed.z>2.5
evaluate("Train",68)
assert gate.matrix_world.translation.z>closed.z+.9
clamps=[bpy.data.objects[f"mooring_clamp_{i:02d}"] for i in range(1,5)]
evaluate("LaunchBalloon",0)
latched=[c.matrix_world.to_quaternion() for c in clamps]
evaluate("LaunchBalloon",45)
assert all(q.rotation_difference(c.matrix_world.to_quaternion()).angle>.42 for c,q in zip(clamps,latched))
evaluate("Build",0)
assert max(max(ob.dimensions) for ob in bpy.data.objects if ob.type=="MESH")<.03
evaluate("Build",239)
assert bounds()[1][2]>7
evaluate("Die",132)
assert bounds()[1][2]<.01
fx=export/"keep_death_fx.glb"
assert [a["name"] for a in document(fx)["animations"]]==["Death"]
imported(fx)
assert bpy.data.objects.get("Flash") or any("Flash" in ob.name for ob in bpy.data.objects)
print(f"KEEP_EXPORT_PASSED world bounds {low}..{high}; gate, four clamps, build and collapse; wood images packed")
