"""Keep the editable kit and its rigid, animated glTF attachments in the same outfit."""
import json
import struct
import bpy
from mathutils import Matrix

BONES = {
    "Kerchief": "head", "Sunhat": "head", "WoodcuttingAxe": "tool",
    "FarmingTool": "tool", "BuildingHammer": "hammer", "MaterialLoad": "load", "FoodBasket": "load",
}
HELD = {"Walk": 0, "Chop": 0, "Gather": 1, "Carry": 1, "Build": 2, "Till": 0, "CarryFood": 3}
CLOSED = .00001


def tag_kerchief(objects):
    for obj in objects:
        if obj.name.startswith(("Kerchief |", "Side | turned kerchief hem",
                                "Brow | folded linen edge", "Rear | folded linen edge")):
            obj["part"] = "Kerchief"


def shown(part, clip):
    farm = clip in {"Till","CarryFood"}
    held = HELD.get(clip, 0)
    return {
        "Kerchief": not farm, "Sunhat": farm,
        "WoodcuttingAxe": not farm and held == 0, "FarmingTool": farm and held == 0,
        "BuildingHammer": held == 2, "MaterialLoad": held == 1, "FoodBasket": held == 3,
    }[part]


def source_controls(rig, objects):
    # Selecting an NLA strip previews its equipment. The Farm assignment switch
    # also dresses her for the farm while walking, carrying or standing still.
    for name in ("farm_assignment", "tilling", "held_kit", "inspect_all_gear"):
        rig[name] = 0.0
        rig.id_properties_ui(name).update(min=0, max=3 if name == "held_kit" else 1)
    for track in rig.animation_data.nla_tracks:
        for strip in track.strips:
            action = strip.action
            if action.name not in HELD:
                continue
            bag = action.layers[0].strips[0].channelbag(strip.action_slot, ensure=True)
            for prop, value in [("tilling", int(action.name in {"Till","CarryFood"})), ("held_kit", HELD[action.name])]:
                curve = bag.fcurves.new(data_path=f'["{prop}"]', index=0)
                curve.keyframe_points.insert(action.frame_range[0], value).interpolation = "CONSTANT"
    expressions = {
        "Kerchief": "farm or till", "Sunhat": "not (farm or till)",
        "WoodcuttingAxe": "farm or till or held > 0.5",
        "FarmingTool": "not (farm or till) or held > 0.5",
        "MaterialLoad": "abs(held - 1) > 0.5", "BuildingHammer": "abs(held - 2) > 0.5",
        "FoodBasket": "held < 2.5",
    }
    for obj in objects:
        part = obj.get("part")
        if part not in BONES:
            continue
        for path in ("hide_render", "hide_viewport"):
            driver = obj.driver_add(path).driver
            for name, prop in [("farm","farm_assignment"), ("till","tilling"),
                               ("held","held_kit"), ("inspect","inspect_all_gear")]:
                var = driver.variables.new()
                var.name = name
                var.type = "SINGLE_PROP"
                var.targets[0].id = rig
                var.targets[0].data_path = f'["{prop}"]'
            driver.expression = "not inspect and (" + expressions[part] + ")"
    for track in rig.animation_data.nla_tracks:
        track.mute = track.name != "Walk"
    bpy.context.scene.frame_end = int(rig.animation_data.nla_tracks["Walk"].strips[0].frame_end)-1
    bpy.context.scene.frame_set(0)


def attach_for_export(obj, part, rig):
    # Bake the editable rigid pieces into joint-local coordinates. Standard glTF
    # clients can then switch tools through ordinary scale tracks on mesh nodes.
    bone = rig.data.bones[BONES[part]]
    obj.data.transform((rig.matrix_world @ bone.matrix_local).inverted())
    obj.parent = rig
    obj.parent_type = "BONE"
    obj.parent_bone = bone.name
    obj.matrix_parent_inverse = Matrix.Identity(4)
    obj.matrix_basis = Matrix.Translation((0, -bone.length, 0))


def publish_kit_tracks(path):
    # Blender elides constant object tracks on bone-parented equipment when
    # baking NLA strips. Each clip explicitly selects its kit at t=0 using a
    # core glTF STEP scale channel. A tiny positive value keeps transforms
    # invertible. The actor disables inactive meshes altogether in Godot.
    raw = path.read_bytes()
    json_length = struct.unpack_from("<I",raw,12)[0]
    asset = json.loads(raw[20:20+json_length])
    binary = bytearray(raw[28+json_length:])

    def accessor(values, kind):
        offset = len(binary)
        binary.extend(struct.pack("<"+"f"*len(values), *values))
        view = len(asset["bufferViews"])
        asset["bufferViews"].append({"buffer":0,"byteOffset":offset,"byteLength":4*len(values)})
        index = len(asset["accessors"])
        asset["accessors"].append({"bufferView":view,"componentType":5126,"count":1,
                                   "type":kind,"min":values,"max":values})
        return index

    time = accessor([0.0],"SCALAR")
    states = {active:accessor([1.0 if active else CLOSED]*3,"VEC3") for active in (False,True)}
    nodes = {node["name"]:i for i,node in enumerate(asset["nodes"])
             if "mesh" in node and node["name"] in BONES}
    for part, i in nodes.items():
        asset["nodes"][i]["scale"] = [1.0 if shown(part,None) else CLOSED]*3
    for action in asset["animations"]:
        for part, i in nodes.items():
            index = len(action["samplers"])
            action["samplers"].append({"input":time,"output":states[shown(part,action["name"])],
                                       "interpolation":"STEP"})
            action["channels"].append({"sampler":index,"target":{"node":i,"path":"scale"}})
    asset["buffers"][0]["byteLength"] = len(binary)
    metadata = json.dumps(asset,separators=(",",":")).encode()
    metadata += b" "*(-len(metadata)%4)
    header = struct.pack("<4sII",b"glTF",2,28+len(metadata)+len(binary))
    path.write_bytes(header+struct.pack("<I4s",len(metadata),b"JSON")+metadata+
                     struct.pack("<I4s",len(binary),b"BIN\0")+binary)
