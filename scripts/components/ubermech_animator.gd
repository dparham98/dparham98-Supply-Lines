extends "res://scripts/components/character_animator.gd"
## Each confirmed attack advances this walker's firing sequence. The six pod
## rounds are a visual salvo belonging to a single combat resolution.

const LASER := &"Shoot"
const VOLLEY := &"PodVolley"
const BEAM_EFFECT := preload("res://scenes/gameplay/ubermech_laser.tscn")
const ROUND_EFFECT := preload("res://scenes/gameplay/ubermech_pod_round.tscn")
const PORT_ORDER := [&"Pod01", &"Pod04", &"Pod05", &"Pod02", &"Pod03", &"Pod06"]
const PORT_FRAMES := [12, 17, 22, 27, 32, 37]
const FPS := 30.0

var _next_clip: StringName = LASER
var _winding_up := false
var _aim_lines := {}
var _salvo_map: Node3D
var _salvo_end: Vector3
var _salvo_team: String
var _next_port: int


func _ready() -> void:
	# The positive local Y axis of each authored socket points out of its lens.
	# Cache both sampled gun lines once. Turning the unit then uses the same
	# aim_yaw geometry as every other character, with the active arm's offset.
	for clip: StringName in [LASER, VOLLEY]:
		shoot_clip = clip
		muzzle_bone = &"Muzzle" if clip == LASER else PORT_ORDER[0]
		var socket := skeleton.find_bone(muzzle_bone)
		assert(socket >= 0, "Missing Ubermech socket %s" % muzzle_bone)
		gun_rest_axis = skeleton.get_bone_global_rest(socket).basis.y.normalized()
		_measure_gun()
		_aim_lines[clip] = [_gun_axis, _gun_origin, _gun_dir]
	_select_weapon(LASER)


## The unit names the weapon of its next shot (unit_agent.weapon_for): 0 the laser, 1 the pod volley. Without
## it, the walker alternates the two as before.
func use_weapon(weapon: int) -> void:
	if weapon >= 0: _next_clip = LASER if weapon == 0 else VOLLEY


func _select_weapon(clip: StringName) -> void:
	shoot_clip = clip
	muzzle_bone = &"Muzzle" if clip == LASER else PORT_ORDER[0]
	var line: Array = _aim_lines[clip]
	_gun_axis = line[0]
	_gun_origin = line[1]
	_gun_dir = line[2]


func play_action(kind: StringName, from := 0.0) -> void:
	if kind == &"shoot" or kind == LASER or kind == VOLLEY:
		_salvo_map = null
		_winding_up = kind == &"shoot" and from < shot_lead_time
		_select_weapon(_next_clip if kind == &"shoot" else kind)
		super.play_action(&"shoot", from)
	else:
		super.play_action(kind, from)


func set_motion(kind: StringName, value := 0.0) -> void:
	super.set_motion(kind, value)
	if _winding_up and kind != &"aim":
		# An interrupted wind-up does not spend a shot or advance the sequence.
		_winding_up = false
		_action_left = 0.0


func show_weapon_shot(game: Node3D, end: Vector3, team: String) -> Node3D:
	_winding_up = false
	# A long gameplay tick can step past the release pose. Align the actual
	# shot, animated socket and remaining follow-through to the same instant.
	player.seek(shot_lead_time, true)
	skeleton.force_update_all_bone_transforms()
	_action_left = player.get_animation(shoot_clip).length - shot_lead_time
	var start := muzzle_position()
	if shoot_clip == LASER:
		_next_clip = VOLLEY
		return game.show_shot(start, end, team, BEAM_EFFECT)
	_next_clip = LASER
	_salvo_map = game
	_salvo_end = end
	_salvo_team = team
	_next_port = 1
	return game.show_shot(start, end, team, ROUND_EFFECT)


func _process(delta: float) -> void:
	if is_instance_valid(_salvo_map):
		if player.assigned_animation != VOLLEY:
			_salvo_map = null
		else:
			var elapsed := player.current_animation_position if player.is_playing() else player.get_animation(VOLLEY).length
			while _next_port < PORT_ORDER.size() and elapsed + 0.00001 >= PORT_FRAMES[_next_port] / FPS:
				var joint := skeleton.find_bone(PORT_ORDER[_next_port])
				var origin := skeleton.to_global(skeleton.get_bone_global_pose(joint).origin)
				_salvo_map.show_shot(origin, _salvo_end, _salvo_team, ROUND_EFFECT)
				_next_port += 1
			if _next_port == PORT_ORDER.size():
				_salvo_map = null
	super._process(delta)
