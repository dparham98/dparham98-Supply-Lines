extends "res://scripts/components/character_animator.gd"
## A character animator for a spellcaster (the Grail Sentinel, docs/MIST_AND_SLOW.md). The owner calls play_cast()
## when a spell goes off: the cast clip plays as a one-shot and the cast burst appears where the hand is at the top
## of the gesture. The clip comes from a saved library (scripts/tools/build_sentinel_cast.gd) because the rig's
## glTF has none; it is added to the rig's player under `cast_library_name`.
@export var cast_library: AnimationLibrary
@export var cast_library_name := &"spells"
@export var cast_clip := &"Cast"
## Bone that holds the light, and how far into the clip the arm is at the top.
@export var cast_bone := &"hand.R"
@export_range(0,2,0.01) var cast_peak_time := 0.22
## Burst scenes by spell kind; `default` covers kinds without their own.
@export var cast_fx: Dictionary[StringName,PackedScene] = {}
var _cast_hand := Vector3(0,2.6,0)
var _fx: Node3D
func _ready() -> void:
	if player != null and cast_library != null and not player.has_animation_library(cast_library_name):
		player.add_animation_library(cast_library_name,cast_library)
	super._ready()
	_measure_cast()
func _cast_name() -> StringName:
	return StringName("%s/%s" % [cast_library_name,cast_clip])
func has_cast() -> bool:
	return player != null and player.has_animation(_cast_name())
## Where the hand is, in this node's frame, at the top of the cast.
func _measure_cast() -> void:
	if not has_cast() or skeleton == null: return
	var bone := skeleton.find_bone(cast_bone)
	if bone < 0: return
	player.play(_cast_name()); player.seek(cast_peak_time,true); skeleton.force_update_all_bone_transforms()
	_cast_hand = to_local(skeleton.global_transform*skeleton.get_bone_global_pose(bone).origin)
	player.stop()
	skeleton.reset_bone_poses()
func cast_hand() -> Vector3:
	return _cast_hand
## A spell of `kind` (&"mist", &"slow") goes off now.
func play_cast(kind: StringName) -> void:
	if _dying: return
	play_action(_cast_name())
	var scene: PackedScene = cast_fx.get(kind,cast_fx.get(&"default"))
	if scene == null: return
	var fx: Node3D = scene.instantiate()
	add_child(fx)
	fx.position = _cast_hand
	_fx = fx
## The burst rides on the hand while it lasts.
func _process(delta: float) -> void:
	super._process(delta)
	if not is_instance_valid(_fx) or skeleton == null: return
	var bone := skeleton.find_bone(cast_bone)
	if bone >= 0: _fx.position = to_local(skeleton.global_transform*skeleton.get_bone_global_pose(bone).origin)
