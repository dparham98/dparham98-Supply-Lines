extends "res://scripts/gameplay/depot.gd"
## Arthurian Keep: local Food/Wood/Iron storage hub and frontline outpost that trains
## Forester Maidens and Warhounds from the Keep gatehouse (Train animation).

@export var forester_scene: PackedScene = preload("res://scenes/gameplay/forester_maiden.tscn")
@export var warhound_scene: PackedScene = preload("res://scenes/gameplay/warhound.tscn")
@export var balloon_scene: PackedScene = preload("res://scenes/gameplay/air_balloon.tscn")
## The Knights' coal train (docs/KNIGHTS_RAIL.md), built here once the side has a Wainwright.
@export var knights_train_scene: PackedScene = preload("res://scenes/gameplay/knights_train.tscn")

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
	if not SupplySource.plays(team) or queue >= queue_limit: return false
	var stats := unit_stats_for_kind(kind)
	if not KnightHousing.room(get_tree(), team, stats.unit_id):
		game.notify("No housing for a %s (%s used): build a House inside a Keep's range." % [stats.display_name, KnightHousing.text(get_tree(), team)], team)
		return false
	var costs := {}
	if stats.food_cost > 0: costs[&"food"] = stats.food_cost
	if stats.iron_cost > 0: costs[&"iron"] = stats.iron_cost
	if stats.wood_cost > 0: costs[&"wood"] = stats.wood_cost
	if stats.energy_cost > 0: costs[&"energy"] = stats.energy_cost
	if not spend_resources(costs): return false
	pending.append(kind)
	queue += 1
	game.notify("%s queued at %s." % [stats.display_name, name], team)
	return true

## Knights rail (docs/KNIGHTS_RAIL.md): why this Keep can't build a train now, or "".
func train_refusal() -> String:
	if health <= 0 or not SupplySource.plays(team): return "This Keep can't build a train."
	if not KnightRail.has_wainwright(self,team): return "Build a Wainwright first: it lets your Keeps lay track and build trains."
	if game.get_node("RailNetwork").loading_pieces(self,team).is_empty(): return "Lay friendly track into this Keep's loading area first."
	return ""
## `line`: a piece of the line the train starts on, when the Keep has more than one.
func request_train(line: Node3D = null) -> bool:
	var refusal := train_refusal()
	if not refusal.is_empty(): game.notify(refusal,team); return false
	if queue >= queue_limit: return false
	var r := KnightHousing.rules()
	if not spend_resources({&"food":r.train_food_cost,&"wood":r.train_wood_cost,&"iron":r.train_iron_cost}): return false
	pending.append("train"); queue += 1
	train_lines.append(line)
	game.notify("Train queued at %s." % name,team)
	return true
func request_truck() -> bool:
	game.notify("Keeps train Forester Maidens and Warhounds, not Cyborg Depot trucks.")
	return false

func request_cargo() -> bool:
	game.notify("Keeps use Wood/Food logistics instead of Cyborg Cargo vehicles.")
	return false

## Launch balloon (docs/AIR_BALLOON.md): the full crates packed beside this Keep, up to `balloon_crates`, go up in
## an Air Balloon to `point`. The player must see `point`, and there must be open land near it for the crates.
func balloon_crates() -> Array[Node3D]:
	var result: Array[Node3D] = []
	for crate in CrateYard.beside(self):
		if crate.amount > 0 and result.size() < KnightHousing.rules().balloon_crates: result.append(crate)
	return result
## Why a balloon can't be launched to `point` now, or "" when it can. `point` null checks only the Keep.
func balloon_refusal(point = null) -> String:
	var rules := KnightHousing.rules()
	if health <= 0 or not SupplySource.plays(team): return "This Keep can't launch a balloon."
	if balloon_crates().is_empty(): return "Pack crates beside the Keep first: Make crates, then Launch balloon."
	if stockpile.amount(&"wood") < rules.balloon_wood_cost: return "A balloon costs %d Wood from the Keep." % rules.balloon_wood_cost
	if point == null: return ""
	var fog = game.fog_of_war() if game.has_method("fog_of_war") else null
	if fog != null and not fog.visible_to(team,point): return "Send the balloon to a point you can see."
	if ground.get_tile_at_position(point) == null or CrateYard.free_cell(get_tree(),point,0,8) == null: return "The balloon needs open land to set its crates on."
	return ""
## Launches the balloon to `point`; false, with the reason told to the player, if it can't go.
func launch_balloon(point: Vector3) -> bool:
	var refusal := balloon_refusal(point)
	if not refusal.is_empty():
		game.notify(refusal,team)
		return false
	if not stockpile.spend({&"wood": KnightHousing.rules().balloon_wood_cost}): return false
	var cargo: Array[Dictionary] = []
	for crate in balloon_crates():
		cargo.append({kind = crate.resource_kind, amount = crate.amount})
		crate.extract(crate.amount)
	var balloon: Node3D = balloon_scene.instantiate()
	balloon.team = team
	balloon.position = global_position
	game.get_node("Entities/Units").add_child(balloon,true)
	balloon.launch(point,cargo,KnightHousing.rules().balloon_dock_height)
	launch_balloon_fx()
	game.notify("Air Balloon launched from %s with %s." % [name,balloon.cargo_text()],team)
	return true

func launch_balloon_fx() -> void:
	var model := get_node_or_null("Visuals/Model")
	if model != null and model.has_method("play_launch_balloon"):
		model.play_launch_balloon()

func current_seconds() -> float:
	if pending.is_empty(): return print_seconds
	if pending[0] == "train": return KnightHousing.rules().train_build_seconds
	return unit_stats_for_kind(pending[0]).build_seconds

func _drop_current() -> void:
	if pending.is_empty(): return
	var kind: String = pending.pop_front()
	queue -= 1
	progress = 0.0
	cancelling = false
	if kind == "train":
		if not train_lines.is_empty(): train_lines.pop_front()
		var r := KnightHousing.rules()
		stockpile.deposit(&"food",r.train_food_cost)
		stockpile.deposit(&"wood",r.train_wood_cost)
		stockpile.deposit(&"iron",r.train_iron_cost)
		return
	var stats := unit_stats_for_kind(kind)
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
	if not SupplySource.plays(team): return
	var kind: String = pending[0]
	if kind == "train":
		_train_tick(delta,model)
		return
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
		game.notify("%s ready at %s." % [stats.display_name, name], team)
## Builds the queued train on friendly track in the loading area, as a Depot does.
func _train_tick(delta: float, model: Node) -> void:
	var seconds := maxf(0.1,KnightHousing.rules().train_build_seconds)
	progress = minf(seconds,progress+delta)
	if model != null and model.has_method("show_print"): model.show_print(progress/seconds)
	$Progress.text = "Building train · %d%%" % roundi(progress/seconds*100)
	if progress < seconds: return
	var stop: Dictionary = game.get_node("RailNetwork").spawn_stop(self,train_lines.front() if not train_lines.is_empty() else null)
	if stop.is_empty():
		$Progress.text = "Train needs friendly track in the Keep's loading area"
		return
	pending.pop_front()
	if not train_lines.is_empty(): train_lines.pop_front()
	var unit = knights_train_scene.instantiate()
	if "start_fuelled" in unit: unit.start_fuelled = FuelRules.full_tanks_for(game)
	unit.position = stop.position
	unit.team = team
	game.get_node("Entities/Units").add_child(unit,true)
	Rally.send(self,unit)
	queue -= 1
	progress = 0.0
	if model != null and model.has_method("unit_left"): model.unit_left()
	game.notify("Train ready at %s." % name,team)
