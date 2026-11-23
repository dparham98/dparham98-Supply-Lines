extends Node
## Balance investigation only: a second weapon that picks its own target, for trying two-weapon units (the proposed
## Ubermech). Damage lands when it fires. `light_only` limits it to units that are not Tanks or Ubermechs.
const Combat = preload("res://scripts/combat/combat_resolver.gd")
var attack_range := 16.0
var min_range := 0.0
var damage := 40
var heavy_damage := -1
var shot_interval := 2.0
var light_only := false
var heavy_only := false
var splash := 0.0
var needs_sight := true
var _reload := 0.0
var _scan := 0.0
var _target = null
@onready var actor: Node3D = get_parent()
static func is_heavy(unit: Node3D) -> bool:
	return unit.is_in_group("selectable_buildings") or (unit.get("unit_stats") != null and unit.unit_stats.unit_id in [&"tank",&"ubermech",&"azure_dragon"])
func _ok(unit) -> bool:
	if unit == null or not is_instance_valid(unit) or unit.is_queued_for_deletion() or not Combat.can_hit(actor,unit): return false
	var d := actor.global_position.distance_to(unit.global_position)
	if d > attack_range or d < min_range: return false
	if light_only and is_heavy(unit): return false
	if heavy_only and not is_heavy(unit): return false
	return not needs_sight or actor._team_sees(unit)
func _process(delta: float) -> void:
	if actor.health <= 0 or actor.is_queued_for_deletion(): return
	_reload = maxf(0.0,_reload-delta)
	_scan -= delta
	if _scan <= 0.0 or not _ok(_target):
		_scan = 0.2
		_target = null
		var best := INF
		for unit in actor.game.units_near(actor.global_position,attack_range):
			if not _ok(unit): continue
			var d := actor.global_position.distance_squared_to(unit.global_position)
			if d < best: best = d; _target = unit
	if _target == null or _reload > 0.0: return
	_reload = shot_interval
	var victims: Array = [_target]
	if splash > 0.0:
		for unit in actor.game.units_near(_target.global_position,splash):
			if unit != _target and is_instance_valid(unit) and Combat.can_hit(actor,unit) and unit.global_position.distance_to(_target.global_position) <= splash: victims.append(unit)
	for victim in victims:
		victim.take_damage(heavy_damage if heavy_damage >= 0 and is_heavy(victim) else damage)
