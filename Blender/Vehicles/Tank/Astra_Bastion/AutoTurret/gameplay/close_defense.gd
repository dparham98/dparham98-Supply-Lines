extends Node
## Independent short-range weapon on the Bastion actor. Distances are in game metres.
signal fired(target: Node3D, origin: Vector3, end: Vector3)

const Combat = preload("res://scripts/combat/combat_resolver.gd")
const BULLET := preload("res://bastion/aux_bullet.tscn")
const SCAN_INTERVAL := 0.12

@export_range(0.1, 50.0, 0.1) var attack_range := 10.0
@export_range(1, 100, 1) var damage := 3
@export_range(0.05, 5.0, 0.01) var shot_interval := 0.35
@export_range(1.0, 1080.0, 1.0) var turn_speed_degrees := 360.0
@export_range(0.1, 15.0, 0.1) var alignment_degrees := 3.0

@onready var _actor: Node3D = get_parent()
var _pivot: Node3D
var _muzzle: Node3D
var _target: Node3D
var _scan_left := 0.0
var _reload_left := 0.0


func _ready() -> void:
	# The chassis and primary turret may both change bearing in the same frame.
	process_priority = 1
	var model := _actor.get_node("Visuals/Model")
	_pivot = model.find_child("Aux_Turret", true, false) as Node3D
	if _pivot != null:
		_muzzle = _pivot.find_child("Aux_Muzzle", true, false) as Node3D
	if _muzzle == null:
		push_error("The Bastion close-defense component needs Aux_Turret and its Aux_Muzzle marker.")
		set_process(false)


func _eligible(unit: Node3D) -> bool:
	return (not unit.is_queued_for_deletion() and unit.is_in_group("units")
		and Combat.can_hit(_actor, unit) and unit.team != "neutral" and unit.team != _actor.team
		and _actor.global_position.distance_squared_to(unit.global_position) <= attack_range * attack_range)


func _nearest() -> Node3D:
	var best: Node3D
	var best_distance := INF
	for node in get_tree().get_nodes_in_group("units"):
		var unit := node as Node3D
		if unit == null or not _eligible(unit):
			continue
		var distance := _actor.global_position.distance_squared_to(unit.global_position)
		if distance < best_distance:
			best = unit
			best_distance = distance
	return best


func _process(delta: float) -> void:
	if (_actor.is_queued_for_deletion() or not _actor.is_in_group("units")
		or _actor.health <= 0 or _actor.team == "neutral"):
		_target = null
		_scan_left = 0.0
		return
	_reload_left = maxf(0.0, _reload_left - delta)
	_scan_left -= delta
	if _scan_left <= 0.0 or (is_instance_valid(_target) and not _eligible(_target)):
		_target = _nearest()
		_scan_left = SCAN_INTERVAL
	if not is_instance_valid(_target):
		return

	var visuals := _target.get_node_or_null("Visuals") as Node3D
	var end: Vector3 = (visuals.global_position if visuals else _target.global_position) + Vector3.UP * 1.3
	# Use the rotating mount's frame and the offset pivot, not the chassis origin.
	var mount := _pivot.get_parent_node_3d()
	var direction := mount.global_basis.inverse() * (end - _pivot.global_position)
	if Vector2(direction.x, direction.z).length_squared() < 0.000001:
		return
	var bearing := atan2(direction.x, direction.z)
	_pivot.rotation.y = rotate_toward(_pivot.rotation.y, bearing, deg_to_rad(turn_speed_degrees) * delta)
	if _reload_left > 0.0 or absf(angle_difference(_pivot.rotation.y, bearing)) > deg_to_rad(alignment_degrees):
		return

	_reload_left = shot_interval
	var victim := _target
	var origin := _muzzle.global_position
	var bullet: Node3D = _actor.game.show_shot(origin, end, _actor.team, BULLET)
	bullet.arm(_actor, victim, damage)
	fired.emit(victim, origin, end)
