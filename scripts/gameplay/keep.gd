extends "res://scripts/gameplay/depot.gd"
## Arthurian Keep: local Food/Wood/Iron storage hub and frontline outpost that trains
## Forester Maidens and Warhounds from the Keep gatehouse (Train animation).

@export var forester_scene: PackedScene = preload("res://scenes/gameplay/forester_maiden.tscn")
@export var warhound_scene: PackedScene = preload("res://scenes/gameplay/warhound.tscn")
@export var balloon_scene: PackedScene = preload("res://scenes/gameplay/air_balloon.tscn")
## Found Keep (docs/ROUND3_SKY_PAVILION.md): the chartered Sky-Pavilion, and where each one queued here is bound.
@export var pavilion_scene: PackedScene = preload("res://scenes/gameplay/sky_pavilion.tscn")
var pavilion_sites: Array[Vector3] = []
## The Knights' coal train (docs/KNIGHTS_RAIL.md): ordered at a Dragon Yard, built here and leaving on this Keep's track.
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
	if kind == "sky_pavilion": return pavilion_scene
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
	if not KnightRail.has_dragon_yard(self,team): return "Build a Dragon Yard first: it builds trains and lets your Keeps lay track."
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

## Launch balloon (docs/AIR_BALLOON.md): an Air Balloon takes up to `balloon_crates` crates to `point`, land the
## side has explored with open land near it for the crates. It carries the balloon's manifest, crates of 25 taken
## from this Keep's stock (docs/ROUND3_SKY_PAVILION.md), or, with no manifest set, the full crates packed beside it.
var balloon_manifest := {}
const BALLOON_KINDS: Array[StringName] = [&"food",&"wood",&"iron",&"coal"]
func balloon_manifest_total() -> int:
	var total := 0
	for kind in balloon_manifest: total += balloon_manifest[kind]
	return total
## Adds a crate of `kind` to the manifest; false when it is full or `kind` doesn't fly.
func balloon_manifest_add(kind: StringName) -> bool:
	if kind not in BALLOON_KINDS or balloon_manifest_total() >= KnightHousing.rules().balloon_crates: return false
	balloon_manifest[kind] = balloon_manifest.get(kind,0)+1
	return true
func balloon_manifest_fill(kind: StringName) -> bool:
	var added := false
	while balloon_manifest_add(kind): added = true
	return added
func balloon_manifest_remove(kind: StringName, every := false) -> bool:
	if balloon_manifest.get(kind,0) <= 0: return false
	balloon_manifest[kind] = 0 if every else balloon_manifest[kind]-1
	if balloon_manifest[kind] <= 0: balloon_manifest.erase(kind)
	return true
## What a launch takes from the Keep's stock: the manifest's crates, if set, and the balloon's Wood.
func balloon_stock_cost() -> Dictionary:
	var costs := {}
	for kind in balloon_manifest: costs[kind] = balloon_manifest[kind]*ResourceStockpile.CRATE
	costs[&"wood"] = costs.get(&"wood",0)+KnightHousing.rules().balloon_wood_cost
	return costs
func balloon_crates() -> Array[Node3D]:
	var result: Array[Node3D] = []
	for crate in CrateYard.beside(self):
		if crate.amount > 0 and result.size() < KnightHousing.rules().balloon_crates: result.append(crate)
	return result
## Why this Keep can't send up balloons at all, or "" (the Launch balloon tile, which opens the manifest).
func balloon_keep_refusal() -> String:
	if health <= 0 or not SupplySource.plays(team): return "This Keep can't launch a balloon."
	return ""
## Why a balloon can't be launched to `point` now, or "" when it can. `point` null checks only the Keep.
func balloon_refusal(point = null) -> String:
	var rules := KnightHousing.rules()
	var refusal := balloon_keep_refusal()
	if not refusal.is_empty(): return refusal
	if balloon_manifest.is_empty() and balloon_crates().is_empty(): return "Set the balloon's manifest from the Keep's stock, or pack crates beside the Keep."
	if balloon_manifest.is_empty():
		if stockpile.amount(&"wood") < rules.balloon_wood_cost: return "A balloon costs %d Wood from the Keep." % rules.balloon_wood_cost
	else:
		var costs := balloon_stock_cost()
		for kind in costs:
			if stockpile.amount(kind) < costs[kind]: return "The Keep lacks %d %s for the manifest%s." % [costs[kind]-stockpile.amount(kind),str(kind).capitalize()," and the balloon's %d Wood" % rules.balloon_wood_cost if kind == &"wood" else ""]
	if point == null: return ""
	var fog = game.fog_of_war() if game.has_method("fog_of_war") else null
	if fog != null and not fog.explored_by(team,point): return "Send the balloon to land you have explored."
	if ground.get_tile_at_position(point) == null or CrateYard.free_cell(get_tree(),point,0,8) == null: return "The balloon needs open land to set its crates on."
	return ""
## Launches the balloon to `point`; false, with the reason told to the player, if it can't go.
func launch_balloon(point: Vector3) -> bool:
	var refusal := balloon_refusal(point)
	if not refusal.is_empty():
		game.notify(refusal,team)
		return false
	var cargo: Array[Dictionary] = []
	if not balloon_manifest.is_empty():
		if not stockpile.spend(balloon_stock_cost()): return false
		for kind in BALLOON_KINDS:
			for i in range(balloon_manifest.get(kind,0)): cargo.append({kind = kind, amount = ResourceStockpile.CRATE})
	else:
		if not stockpile.spend({&"wood": KnightHousing.rules().balloon_wood_cost}): return false
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

## Why this Keep can't send a Sky-Pavilion to `point` now, or "". `point` null checks only the Keep. The site must be
## land the side has explored (not necessarily in sight) where a Keep could stand.
func pavilion_refusal(point = null) -> String:
	if health <= 0 or not SupplySource.plays(team): return "This Keep can't charter a Sky-Pavilion."
	if point == null: return ""
	var fog = game.fog_of_war() if game.has_method("fog_of_war") else null
	if fog != null:
		var spec: Dictionary = game.get_node("DepotNetwork").plan_spec(&"keep")
		var start: Vector2i = game.get_node("DepotNetwork").footprint_start(point,spec.size)
		for z in [start.y,start.y+spec.size.y-1]:
			for x in [start.x,start.x+spec.size.x-1]:
				if not fog.explored_by(team,ground.tile_to_world(Vector2i(x,z))): return "Send the Sky-Pavilion to land you have explored."
	return game.get_node("DepotNetwork").keep_site_refusal(point,team)
## Found Keep: pays 50 W / 50 I / 45 F and a housing for a Sky-Pavilion bound for `point`, which lifts off after
## its 15 s prep. False, with the reason told, when it can't.
func request_pavilion(point: Vector3) -> bool:
	var refusal := pavilion_refusal(point)
	if not refusal.is_empty():
		game.notify(refusal,team)
		return false
	if not _request_keep_unit("sky_pavilion"):
		# No housing is told already; otherwise it is the price or the queue.
		if KnightHousing.room(get_tree(),team,&"sky_pavilion"): game.notify("%s lacks the Sky-Pavilion's price or queue space." % name,team)
		return false
	pavilion_sites.append(point)
	return true
func _launch_pavilion() -> void:
	var site: Vector3 = pavilion_sites.pop_front() if not pavilion_sites.is_empty() else global_position
	var pavilion: Node3D = pavilion_scene.instantiate()
	pavilion.team = team
	pavilion.position = global_position
	game.get_node("Entities/Units").add_child(pavilion,true)
	pavilion.launch(site,[] as Array[Dictionary],KnightHousing.rules().balloon_dock_height)
	launch_balloon_fx()
	game.notify("Sky-Pavilion lifted off %s." % name,team)
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
	if kind == "sky_pavilion" and not pavilion_sites.is_empty(): pavilion_sites.pop_front()
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
	if progress >= seconds and kind == "sky_pavilion":
		pending.pop_front()
		queue -= 1
		progress = 0.0
		if model != null and model.has_method("unit_left"): model.unit_left()
		_launch_pavilion()
		return
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
## A Keep's ceiling counts Iron and Wood only, leaving room for Food and Coal (docs/ROUND3_CYBORG_ECONOMY.md).
func raw_material_total() -> int:
	return iron+wood
