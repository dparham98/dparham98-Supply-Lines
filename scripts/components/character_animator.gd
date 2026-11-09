extends Node3D
## Plays a rigged model's clips from what its owner reports each frame: running, working or idle,
## plus one-shot actions such as a shot. Sits on a model scene root (scenes/models/infantry_model.tscn);
## the owner calls set_motion() every frame and play_action() when something happens. Clips are the
## glTF animation names; a missing clip is skipped so a model without one still works.
@export var player_path: NodePath
@export var idle_clip: StringName = &"Rest"
@export var run_clip: StringName = &"Run"
@export var work_clip: StringName = &"Work"
@export var shoot_clip: StringName = &"Shoot"
## Ground speed (m/s) at which the run clip plays at normal rate; faster units stride faster.
@export_range(0.1,20,0.1) var run_reference_speed := 2.0
@export_range(0,0.5,0.01) var blend_time := 0.12
## Bone the shot leaves from; falls back to this node when missing.
@export var muzzle_bone: StringName = &"pistol"
## A mesh carrying assets/shaders/chainsaw_teeth.gdshader: its `speed` instance uniform runs while working.
@export var teeth_path: NodePath
@export_range(0,30,0.5) var teeth_speed := 10.0
var _motion: StringName = &"idle"
var _speed := 0.0
var _motion_frame := -2
var _action_left := 0.0
var _teeth_running := false
@onready var player: AnimationPlayer = get_node_or_null(player_path)
@onready var teeth: GeometryInstance3D = get_node_or_null(teeth_path)
@onready var skeleton: Skeleton3D = _find_skeleton()
func _find_skeleton() -> Skeleton3D:
	var found := find_children("*","Skeleton3D",true,false)
	return found[0] if not found.is_empty() else null
## Report this frame's motion: &"run" with the ground speed, &"work", or &"idle". Lapses after a frame.
func set_motion(kind: StringName, speed := 0.0) -> void:
	_motion = kind
	_speed = speed
	_motion_frame = Engine.get_process_frames()
## Play a one-shot clip now (&"shoot"); motion resumes when it ends.
func play_action(kind: StringName) -> void:
	var clip := shoot_clip if kind == &"shoot" else StringName(kind)
	if player == null or not player.has_animation(clip): return
	player.speed_scale = 1.0
	player.play(clip,blend_time)
	player.seek(0.0,true)
	_action_left = player.get_animation(clip).length
func motion() -> StringName:
	return _motion if Engine.get_process_frames()-_motion_frame <= 1 else &"idle"
func current_clip() -> StringName:
	return StringName(player.current_animation) if player else &""
func acting() -> bool:
	return _action_left > 0.0
func muzzle_position() -> Vector3:
	if skeleton:
		var bone := skeleton.find_bone(muzzle_bone)
		if bone >= 0: return skeleton.global_transform*skeleton.get_bone_global_pose(bone).origin
	return global_position
func _clip_for(kind: StringName) -> StringName:
	match kind:
		&"run": return run_clip
		&"work": return work_clip
	return idle_clip
func _process(delta: float) -> void:
	if player == null: return
	var kind := motion()
	if _action_left > 0.0:
		_action_left -= delta
		_run_teeth(false)
		return
	var clip := _clip_for(kind)
	if not player.has_animation(clip): clip = idle_clip
	if player.has_animation(clip) and (player.current_animation != String(clip) or not player.is_playing()):
		player.play(clip,blend_time)
	player.speed_scale = clampf(_speed/run_reference_speed,0.5,2.0) if kind == &"run" and _speed > 0.0 else 1.0
	_run_teeth(kind == &"work")
func _run_teeth(running: bool) -> void:
	if teeth == null or running == _teeth_running: return
	_teeth_running = running
	teeth.set_instance_shader_parameter(&"speed",teeth_speed if running else 0.0)
