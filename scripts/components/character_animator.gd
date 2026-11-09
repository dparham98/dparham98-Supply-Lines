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
## Swings the work clip contains, and swings to fit into one reported work cycle.
@export_range(1,8,1) var work_swings_in_clip := 1
@export_range(1,8,1) var work_swings_per_cycle := 2
@export_range(0,0.5,0.01) var blend_time := 0.12
## Bone the shot leaves from; falls back to this node when missing.
@export var muzzle_bone: StringName = &"pistol"
## Bone whose axis is the barrel, when it is not the muzzle bone.
@export var gun_bone: StringName = &""
## The barrel's direction in skeleton space while the rig rests (the pistol mesh's long axis).
@export var gun_rest_axis := Vector3(0,0,1)
## Time into the shoot clip at which the arm is extended; the gun line is measured there.
@export_range(0,2,0.01) var gun_sample_time := 0.1
## Seconds into the shoot clip at which the shot goes off. The owner starts the clip this early, so
## the wind-up plays before the shot and the flash lands on it.
@export_range(0,2,0.001) var shot_lead_time := 0.0
## A light that follows a bone's scale, as a Blender light driven by a flash bone does. The bone
## shrinks to almost nothing between shots, which leaves the light off.
@export var flash_bone: StringName = &""
@export var flash_light_path: NodePath
@export_range(0,100,0.1) var flash_light_energy := 1.0
## A mesh carrying assets/shaders/chainsaw_teeth.gdshader: its `speed` instance uniform runs while working.
@export var teeth_path: NodePath
@export_range(0,30,0.5) var teeth_speed := 10.0
var _motion: StringName = &"idle"
var _value := 0.0
var _motion_frame := -2
var _action_left := 0.0
var _teeth_running := false
var _gun_axis := Vector3.ZERO
var _gun_origin := Vector3.ZERO
var _gun_dir := Vector3.ZERO
@onready var player: AnimationPlayer = get_node_or_null(player_path)
@onready var teeth: GeometryInstance3D = get_node_or_null(teeth_path)
@onready var flash_light: Light3D = get_node_or_null(flash_light_path)
@onready var skeleton: Skeleton3D = _find_skeleton()
func _find_skeleton() -> Skeleton3D:
	var found := find_children("*","Skeleton3D",true,false)
	return found[0] if not found.is_empty() else null
func _ready() -> void:
	_measure_gun()
## Where the gun sits and points in this node's frame while shooting, read once from the clips.
func _measure_gun() -> void:
	if player == null or skeleton == null or not player.has_animation(shoot_clip): return
	var bone := skeleton.find_bone(_barrel_bone())
	if bone < 0: return
	if player.has_animation(idle_clip):
		player.play(idle_clip); player.seek(0.0,true); skeleton.force_update_all_bone_transforms()
	_gun_axis = (skeleton.get_bone_global_pose(bone).basis.inverse()*gun_rest_axis).normalized()
	player.play(shoot_clip); player.seek(gun_sample_time,true); skeleton.force_update_all_bone_transforms()
	var pose := skeleton.get_bone_global_pose(bone)
	var world := skeleton.global_transform*pose
	_gun_origin = to_local(world.origin)
	_gun_dir = (global_transform.basis.inverse()*(world.basis*_gun_axis)).normalized()
	if player.has_animation(idle_clip): player.play(idle_clip); player.seek(0.0,true)
func _barrel_bone() -> StringName:
	return gun_bone if gun_bone != &"" else muzzle_bone
func shot_lead() -> float:
	return shot_lead_time
func has_gun_line() -> bool:
	return _gun_dir != Vector3.ZERO
## The barrel's direction in world space right now.
func gun_direction() -> Vector3:
	if skeleton == null or _gun_axis == Vector3.ZERO: return -global_transform.basis.z
	var bone := skeleton.find_bone(_barrel_bone())
	return (skeleton.global_transform.basis*(skeleton.get_bone_global_pose(bone).basis*_gun_axis)).normalized()
## Yaw for this node's parent so the gun line, not the face, runs through `target` (given in that parent's frame).
func aim_yaw(target: Vector3) -> float:
	var flat := Vector3(target.x,0,target.z)
	var yaw := atan2(-flat.x,-flat.z)
	if not has_gun_line() or flat.length_squared() < 0.01: return yaw
	for i in range(3):
		var turned := Basis(Vector3.UP,yaw)
		var dir := turned*_gun_dir; dir.y = 0
		var want := flat-turned*_gun_origin; want.y = 0
		if dir.length_squared() < 0.0001 or want.length_squared() < 0.0001: break
		yaw += dir.signed_angle_to(want,Vector3.UP)
	return yaw
## Report this frame's motion: &"run" with the ground speed, &"work" with the work cycle period in
## seconds, &"aim" (hold the gun on a target), or &"idle". Lapses after a frame without a call.
func set_motion(kind: StringName, value := 0.0) -> void:
	_motion = kind
	_value = value
	_motion_frame = Engine.get_process_frames()
## Restart the work clip so its swings line up with a work cycle that starts now.
func sync_work() -> void:
	if player and player.current_animation == String(work_clip): player.seek(0.0,true)
## Play a one-shot clip now (&"shoot"), `from` seconds in; motion resumes when it ends.
func play_action(kind: StringName, from := 0.0) -> void:
	var clip := shoot_clip if kind == &"shoot" else StringName(kind)
	if player == null or not player.has_animation(clip): return
	player.speed_scale = 1.0
	# Joining a clip partway has no wind-up to blend through, and a blend would swallow a short flash.
	player.play(clip,blend_time if from < 0.05 else 0.0)
	player.seek(from,true)
	_action_left = player.get_animation(clip).length-from
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
	_update_flash_light()
	var kind := motion()
	if _action_left > 0.0:
		_action_left -= delta
		_run_teeth(false)
		return
	if kind == &"aim" and player.has_animation(shoot_clip):
		_hold_aim()
		_run_teeth(false)
		return
	var clip := _clip_for(kind)
	if not player.has_animation(clip): clip = idle_clip
	if player.has_animation(clip) and (player.current_animation != String(clip) or not player.is_playing()):
		player.play(clip,blend_time)
	player.speed_scale = _pace(kind,clip)
	_run_teeth(kind == &"work")
## Run strides with ground speed; work fits `work_swings_per_cycle` swings into the reported cycle.
func _pace(kind: StringName, clip: StringName) -> float:
	if _value <= 0.0: return 1.0
	if kind == &"run": return clampf(_value/run_reference_speed,0.5,2.0)
	if kind == &"work": return player.get_animation(clip).length*work_swings_per_cycle/(work_swings_in_clip*_value)
	return 1.0
## Keep the gun up between shots: the shoot clip ends in the aimed pose, so a finished one-shot holds it.
func _hold_aim() -> void:
	player.speed_scale = 1.0
	if player.assigned_animation == String(shoot_clip): return
	player.play(shoot_clip,blend_time)
	player.seek(player.get_animation(shoot_clip).length,true)
func _update_flash_light() -> void:
	if flash_light == null or skeleton == null: return
	var bone := skeleton.find_bone(flash_bone)
	if bone < 0: return
	var energy := flash_light_energy*maxf(0.0,skeleton.get_bone_pose_scale(bone).x-0.001)
	flash_light.light_energy = energy
	flash_light.visible = energy > 0.0
func _run_teeth(running: bool) -> void:
	if teeth == null or running == _teeth_running: return
	_teeth_running = running
	teeth.set_instance_shader_parameter(&"speed",teeth_speed if running else 0.0)
