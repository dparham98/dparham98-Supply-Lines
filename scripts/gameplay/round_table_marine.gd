extends "res://scripts/gameplay/unit_agent.gd"
## The rifle's Shoot clip contains three one-second bursts. Its first round
## resolves the attack; the following two are visible rounds from that burst.

const FRAMES_PER_SECOND := 24.0
const CLIP_SECONDS := 3.0
const FIRST_ROUND := 5.0 / FRAMES_PER_SECOND # Blender frame 6, timeline begins at 1.
const ROUND_SPACING := 4.0 / FRAMES_PER_SECOND
const ROUNDS_PER_BURST := 3
const READY_WINDOW := 0.30

var _ready_delay := 0.0
var _step_seconds := 0.0
var _engaging_this_step := false
var _rifle_target: Node3D
var _clip_clock := 0.0
var _next_round := 0


func _ready() -> void:
	super._ready()
	# Unit creation order is reproducible and includes successive recruits
	# leaving the same building. The counter belongs to this match.
	var match_units := get_parent()
	var recruit := int(match_units.get_meta(&"round_table_recruits", 0))
	match_units.set_meta(&"round_table_recruits", recruit + 1)
	_ready_delay = fposmod(recruit * 0.61803398875, 1.0) * READY_WINDOW


func _order_process(delta: float) -> void:
	_step_seconds = delta
	_engaging_this_step = false
	super._order_process(delta)
	if not _engaging_this_step:
		_rifle_target = null


func _round_time(index: int) -> float:
	var burst := floori(float(index) / ROUNDS_PER_BURST)
	return burst + FIRST_ROUND + (index % ROUNDS_PER_BURST) * ROUND_SPACING


func _shoot(target: Node3D) -> void:
	if not _attack_enabled or not _may_hit(target) or not in_attack_range(target): return
	_engaging_this_step = true
	_aimed_frame = Engine.get_process_frames()
	var model := _animator()
	_aim_body(target, null, model)
	var interval := CombatResolver.interval_for(self, target)
	if not is_instance_valid(_rifle_target) or _rifle_target != target:
		_rifle_target = target
		_next_round = 0
		# Preserve an outstanding reload when changing target or resuming fire.
		_clip_clock = FIRST_ROUND - maxf(_cooldown, _ready_delay) / interval
	else:
		_clip_clock += _step_seconds / interval

	while _round_time(_next_round) <= _clip_clock + 0.000001:
		if not _may_hit(target): break
		if model: model.pose_shoot(fposmod(_round_time(_next_round), CLIP_SECONDS))
		_release_shot(target, null, _next_round % ROUNDS_PER_BURST == 0)
		_next_round += 1
	var next_attack := ceili(float(_next_round) / ROUNDS_PER_BURST) * ROUNDS_PER_BURST
	_cooldown = maxf(0.0, (_round_time(next_attack) - _clip_clock) * interval)
	if model: model.pose_shoot(fposmod(maxf(0.0, _clip_clock), CLIP_SECONDS))
