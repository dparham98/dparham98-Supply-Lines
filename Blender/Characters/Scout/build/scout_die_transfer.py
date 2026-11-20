# Transfers the old Scout's `die` clip (Scout.blend, rig "Skater rig") onto ScoutCyborg_Rig as a new `die` action and
# NLA track. Each bone takes the old bone's motion away from its rest pose in armature space, applied to its own rest
# pose, so differences in rest orientation (the gun bones, the shoulders) do not carry over.
#   blender -b ScoutCyborg.blend -P scout_die_transfer.py -- <save_as.blend or "inplace">
import bpy, sys
from mathutils import Matrix

out = sys.argv[sys.argv.index("--")+1] if "--" in sys.argv else ""
new = bpy.data.objects["ScoutCyborg_Rig"]
with bpy.data.libraries.load(bpy.path.abspath("//Scout.blend"), link=False) as (src, dst):
    dst.objects = ["Skater rig"]
    dst.actions = ["die"]
old_die = dst.actions[0]
old_die.name = "old_scout_die"
old = bpy.data.objects["Skater rig"]
bpy.context.scene.collection.objects.link(old)
old.animation_data_create()
old.animation_data.action = old_die
for track in old.animation_data.nla_tracks: track.mute = True
print("OLD DIE", old_die.name, tuple(old_die.frame_range))

names = {"shoulder.L": "clavicle.L", "shoulder.R": "clavicle.R"}
for i in range(1, 5):
    for side in "LR": names["wheel%d.%s" % (i, side)] = "wheel.%s%d" % (side, i)

# Parents before children.
order = []
def visit(bone):
    order.append(bone.name)
    for child in bone.children: visit(child)
for bone in new.data.bones:
    if bone.parent is None: visit(bone)
mapped = [n for n in order if old.data.bones.get(names.get(n, n)) is not None]
print("MAPPED", len(mapped), "of", len(order), "missing", [n for n in order if n not in mapped])

# Bake onto a fresh action with the NLA muted.
new.animation_data_create()
saved_action = new.animation_data.action
for track in new.animation_data.nla_tracks: print("TRACK", track.name, "mute", track.mute, "solo", track.is_solo)
mutes = {track.name: track.mute for track in new.animation_data.nla_tracks}
for track in new.animation_data.nla_tracks: track.mute = True
if "die" in bpy.data.actions and bpy.data.actions["die"].users == 0: bpy.data.actions.remove(bpy.data.actions["die"])
die = bpy.data.actions.new("die")
die.use_fake_user = True
new.animation_data.action = die
start, end = int(old_die.frame_range[0]), int(old_die.frame_range[1])
scene = bpy.context.scene
for frame in range(start, end+1):
    scene.frame_set(frame)
    deltas = {}
    for name in mapped:
        ob = old.pose.bones[names.get(name, name)]
        deltas[name] = ob.matrix @ ob.bone.matrix_local.inverted()
    for name in mapped:
        pb = new.pose.bones[name]
        pb.matrix = deltas[name] @ pb.bone.matrix_local
        bpy.context.view_layer.update()
    for name in mapped:
        pb = new.pose.bones[name]
        pb.keyframe_insert("location", frame=frame, group=name)
        pb.keyframe_insert("rotation_quaternion" if pb.rotation_mode == "QUATERNION" else "rotation_euler", frame=frame, group=name)
        pb.keyframe_insert("scale", frame=frame, group=name)
# Unmapped bones (neutral_bone) stay at rest.
new.animation_data.action = saved_action
track = new.animation_data.nla_tracks.get("die") or new.animation_data.nla_tracks.new()
track.name = "die"
for strip in list(track.strips): track.strips.remove(strip)
track.strips.new("die", start, die)
track.mute = True
for t in new.animation_data.nla_tracks:
    if t.name in mutes: t.mute = mutes[t.name]
old_data = old.data
imported = {old_die}|{s.action for t in old.animation_data.nla_tracks for s in t.strips if s.action}
bpy.data.objects.remove(old)
bpy.data.armatures.remove(old_data)
for a in imported:
    if a and a.users == 0: bpy.data.actions.remove(a)
print("DIE KEYS", len(die.fcurves), tuple(die.frame_range))
# A dark-metal piece at the base of the head had no weights, so it stayed behind when the head moved (and made the
# glTF exporter add a neutral_bone). Bind it to the head, like the rest of its mesh.
jaw = bpy.data.objects["Head_CyberJaw"]
loose = [v.index for v in jaw.data.vertices if not v.groups]
if loose: jaw.vertex_groups["head"].add(loose, 1.0, "REPLACE")
print("BOUND", len(loose), "loose vertices of Head_CyberJaw to head")
if out == "inplace": bpy.ops.wm.save_mainfile()
elif out: bpy.ops.wm.save_as_mainfile(filepath=out, copy=True)
print("SCOUT_DIE_DONE")
