extends "res://scripts/gameplay/depot.gd"
## Arthurian Keep: local Food/Wood/Iron storage hub and frontline outpost that trains
## Forester Maidens and Warhounds from the Keep gatehouse (Train animation).

@export var forester_scene: PackedScene = preload("res://scenes/gameplay/forester_maiden.tscn")
@export var warhound_scene: PackedScene = preload("res://scenes/gameplay/warhound.tscn")

var _unit_stats_cache := {}

func testing_iron_granted() -> bool:
	return false

func _reserve_apron() -> void:
	pass

func _ready() -> void:
	if initial_energy < 0: initial_energy = 0
	super._ready()
	add_to_group("keeps")
	_paint_team()
	if not ownership_changed.is_connected(_paint_team):
		ownership_changed.connect(_paint_team)

func _paint_team() -> void:
	preload("res://scripts/components/team_paint.gd").apply(get_node_or_null("Visuals/Model"), team)

func _scene_for(kind: String) -> PackedScene:
	return warhound_scene if kind == "warhound" else forester_scene

func unit_stats_for_kind(kind: String) -> UnitStats:
	if not _unit_stats_cache.has(kind):
		var unit := _scene_for(kind).instantiate()
		_unit_stats_cache[kind] = unit.unit_stats
		unit.free()
	return _unit_stats_cache[kind]

func request_forester() -> bool:
	return _request_keep_unit("forester_maiden")

func request_warhound() -> bool:
	return _request_keep_unit("warhound")

func _request_keep_unit(kind: String) -> bool:
	if team != "player" or queue >= queue_limit: return false
	var stats := unit_stats_for_kind(kind)
	var costs := {}
	if stats.food_cost > 0: costs[&"food"] = stats.food_cost
	if stats.iron_cost > 0: costs[&"iron"] = stats.iron_cost
	if stats.wood_cost > 0: costs[&"wood"] = stats.wood_cost
	if stats.energy_cost > 0: costs[&"energy"] = stats.energy_cost
	if not spend_resources(costs): return false
	pending.append(kind)
	queue += 1
	game.notify("%s queued at %s." % [stats.display_name, name])
	return true

func request_truck() -> bool:
	game.notify("Keeps train Forester Maidens and Warhounds, not Cyborg Depot trucks.")
	return false

func request_cargo() -> bool:
	game.notify("Keeps use Wood/Food logistics instead of Cyborg Cargo vehicles.")
	return false

func launch_balloon_fx() -> void:
	var model := get_node_or_null("Visuals/Model")
	if model != null and model.has_method("play_launch_balloon"):
		model.play_launch_balloon()

func current_seconds() -> float:
	if pending.is_empty(): return print_seconds
	return unit_stats_for_kind(pending[0]).build_seconds

func _drop_current() -> void:
	if pending.is_empty(): return
	var kind: String = pending.pop_front()
	var stats := unit_stats_for_kind(kind)
	queue -= 1
	progress = 0.0
	cancelling = false
	if stats.food_cost > 0: stockpile.deposit(&"food", stats.food_cost)
	if stats.iron_cost > 0: stockpile.deposit(&"iron", stats.iron_cost)
	if stats.wood_cost > 0: stockpile.deposit(&"wood", stats.wood_cost)
	if stats.energy_cost > 0: stockpile.deposit(&"energy", stats.energy_cost)
	var model := get_node_or_null("Visuals/Model")
	if model != null and model.has_method("show_idle"): model.show_idle()

func _process(delta: float) -> void:
	update_capture(delta)
	var model := get_node_or_null("Visuals/Model")
	if queue <= 0 or pending.is_empty():
		progress = 0.0
		if model != null and model.has_method("show_idle"): model.show_idle()
		$Progress.text = "%s KEEP · F %d / W %d / I %d · capture %d%%" % [team, food, wood, iron, roundi(capture_progress / rules.capture_seconds * 100)]
		return
	if team != "player": return
	var kind: String = pending[0]
	var stats := unit_stats_for_kind(kind)
	var seconds := maxf(0.1, stats.build_seconds)
	progress = minf(seconds, progress + delta)
	if model != null and model.has_method("show_print"):
		model.show_print(progress / seconds)
	$Progress.text = "Training %s · %d%%" % [stats.display_name, roundi(progress / seconds * 100)]
	if progress >= seconds:
		var layer: int = stats.mobility.layer if stats.mobility != null else MobilityRules.Layer.GROUND
		var spawn := ProductionExit.find_cell(ground, global_position, footprint, layer)
		if spawn.x < 0:
			$Progress.text = "Keep gate blocked · waiting"
			return
		pending.pop_front()
		var unit := _scene_for(kind).instantiate()
		unit.team = team
		unit.position = ground.tile_to_world(spawn)
		game.get_node("Entities/Units").add_child(unit, true)
		Rally.send(self, unit)
		queue -= 1
		progress = 0.0
		if model != null and model.has_method("unit_left"): model.unit_left()
		if kind == "forester_maiden": game.units_printed += 1
		game.notify("%s ready at %s." % [stats.display_name, name])
