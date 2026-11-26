extends Node3D
@export var stats: ProductionBuildingStats
@export var team := "player"
@export var assigned_depot_path: NodePath
var assigned_depot: Node3D
var health := 1000
var max_health: int:
	get: return stats.max_health
const Rally = preload("res://scripts/production/rally.gd")
var pending: Array[PackedScene] = []
## Where new units go (docs/RALLY_POINTS.md): right-click with this building selected; Shift adds stops.
var rally_points: Array[Dictionary] = []
var queue: int:
	get: return pending.size()
## Seconds of base-rate work done on the head unit, from 0 to its build_seconds.
var progress := 0.0
## Production power, 1 to stats.max_power (docs/PRODUCTION_POWER.md).
var power := 1.0
## Extra energy owed for power above 1, drawn from the Depot in whole units.
var _energy_owed := 0.0
## True while the Depot cannot pay for the extra power, so the unit prints at 1x.
var power_starved := false
## True while a finished unit waits for a free exit cell (shown on the map).
var exit_blocked := false
## Stoke Brazier (docs/ROUND3_KNIGHTS_COAL.md): set by the player on a building whose stats allow it.
var brazier_on := false
## Whether the brazier burns now: on, working, with its coal paid.
var brazier_lit := false
## On and working, but no Coal to burn: it works at 1x.
var brazier_starved := false
## Seconds of stoked work its last Coal still pays for.
var _brazier_paid := 0.0
var cells: Array[Vector2i] = []
@onready var ground = get_tree().get_first_node_in_group("terrain_grid")
@onready var game = get_tree().get_first_node_in_group("skirmish")
func _ready() -> void:
	health = stats.max_health
	if assigned_depot == null and not assigned_depot_path.is_empty(): assigned_depot = get_node_or_null(assigned_depot_path)
	var center = ground.get_tile_at_position(global_position)
	var start: Vector2i = center-stats.footprint/2 if center != null else Vector2i(-1,-1)
	if not ground.is_footprint_valid(start,stats.footprint):
		push_error("Production building requires an exact empty footprint")
		queue_free()
		return
	global_position = ground.tile_to_world(start)+Vector3(stats.footprint.x*0.5-0.5,0,stats.footprint.y*0.5-0.5)
	for z in range(start.y,start.y+stats.footprint.y):
		for x in range(start.x,start.x+stats.footprint.x):
			var cell := Vector2i(x,z)
			cells.append(cell)
			ground.set_tile_feature(cell,"occupied_by",_key())
	add_to_group("production_buildings")
	add_to_group("selectable_buildings")
	if is_instance_valid(assigned_depot) and not assigned_depot.ownership_changed.is_connected(_source_changed): assigned_depot.ownership_changed.connect(_source_changed)
	preload("res://scripts/components/team_paint.gd").apply(get_node_or_null("Visuals/Model"),team)
## Production picks its paying Depot itself (docs/HUD_POLISH.md, Production picks its Depot): it keeps the one it
## has while that stays friendly; otherwise it takes the nearest friendly Depot whose range covers the building.
func source_friendly() -> bool:
	if not SupplySource.plays(team): return false
	if not _depot_ok(assigned_depot):
		var options := covering_depots()
		_set_source(options[0] if not options.is_empty() else null)
	return assigned_depot != null
func _depot_ok(depot) -> bool:
	return is_instance_valid(depot) and depot.is_inside_tree() and depot.health > 0 and depot.team == team
## Friendly Depots whose range covers the building, nearest first.
func covering_depots() -> Array[Node3D]:
	var found: Array[Node3D] = []
	for depot in get_tree().get_nodes_in_group("depots"):
		if _depot_ok(depot) and SupplySource.covers(depot,global_position,team): found.append(depot)
	found.sort_custom(func(a,b): return a.global_position.distance_squared_to(global_position) < b.global_position.distance_squared_to(global_position))
	return found
func _set_source(depot: Node3D) -> void:
	if depot == assigned_depot: return
	if is_instance_valid(assigned_depot) and assigned_depot.ownership_changed.is_connected(_source_changed): assigned_depot.ownership_changed.disconnect(_source_changed)
	assigned_depot = depot
	if is_instance_valid(assigned_depot) and not assigned_depot.ownership_changed.is_connected(_source_changed): assigned_depot.ownership_changed.connect(_source_changed)
## The Depot to pay `energy` and `iron` now: the current one if it can, else the nearest covering one that can.
func payer_for(energy: int, iron: int, food := 0, wood := 0, coal := 0) -> Node3D:
	if not source_friendly(): return null
	if _can_pay(assigned_depot,energy,iron,food,wood,coal): return assigned_depot
	for depot in covering_depots():
		if _can_pay(depot,energy,iron,food,wood,coal): return depot
	return null
## Whether a Depot (or Keep, which pays in Food) holds the whole cost.
func _can_pay(depot: Node3D, energy: int, iron: int, food: int, wood: int, coal := 0) -> bool:
	return depot.energy >= energy and depot.iron >= iron and depot.food >= food and depot.wood >= wood and depot.coal >= coal
func _source_changed() -> void:
	# Preserve the existing Depot policy: paid queue cancellation without refund on source capture.
	pending.clear()
	progress = 0
	_energy_owed = 0.0
## Lights or puts out the Stoke Brazier, where the building has one.
func set_brazier(on: bool) -> void:
	brazier_on = on and stats.can_stoke_brazier
	if not brazier_on: brazier_lit = false; brazier_starved = false
## How much faster the work goes this frame: `stoked_speed` while the brazier burns, else 1. Called only while it
## works. A Coal from the paying Keep pays for `brazier_coal_interval` s of burning, taken as the last one runs out;
## with none, it works at 1x and the queue goes on.
func brazier_scale(delta: float) -> float:
	brazier_lit = false
	brazier_starved = false
	if not brazier_on or not stats.can_stoke_brazier: return 1.0
	if _brazier_paid <= 0.0:
		if not is_instance_valid(assigned_depot) or assigned_depot.coal < 1 or not assigned_depot.spend_resources({&"coal": 1}):
			brazier_starved = true
			return 1.0
		_brazier_paid += stats.brazier_coal_interval
	_brazier_paid -= delta
	brazier_lit = true
	return stats.stoked_speed
## The brazier's word for status lines: "" when it is off or idle.
func brazier_note() -> String:
	if brazier_lit: return " · Brazier lit"
	if brazier_starved: return " · Brazier unlit · needs Coal"
	return ""
## Sets the production power, snapped to the step and kept between 1 and the most.
func set_power(value: float) -> void:
	power = clampf(snappedf(value,stats.power_step),1.0,stats.max_power)
## Seconds the head unit (or `scene`) takes at base power.
func base_seconds(scene: PackedScene = null) -> float:
	if scene == null: scene = pending[0] if not pending.is_empty() else null
	return unit_stats_for(scene).build_seconds if scene != null else 1.0
## Seconds a unit takes at the power set now.
func seconds_at_power(scene: PackedScene = null) -> float:
	return base_seconds(scene)/power
## How far the head unit is, 0 to 1.
func fraction() -> float:
	return clampf(progress/base_seconds(),0.0,1.0) if not pending.is_empty() else 0.0
## Energy a unit costs in all at the power set now: its base cost, and (power - 1) x the building's
## extra_power_energy_scale of it on top (docs/PRODUCTION_POWER.md).
func energy_at_power(scene: PackedScene) -> int:
	return roundi(unit_stats_for(scene).energy_cost*(1.0+(power-1.0)*stats.extra_power_energy_scale))
## Stats are read once per unit scene: instantiating a unit (and its model) every frame is costly.
static var _stats_cache := {}
func unit_stats_for(scene: PackedScene) -> UnitStats:
	var key := scene.resource_path
	if not _stats_cache.has(key):
		var unit = scene.instantiate()
		_stats_cache[key] = unit.unit_stats
		unit.free()
	return _stats_cache[key]
func request_unit(id: StringName) -> bool:
	if not source_friendly(): game.notify("No friendly Depot's range covers %s." % name,team); return false
	if queue >= stats.queue_limit: game.notify("Production queue is full.",team); return false
	for scene in stats.unit_scenes:
		var resource := unit_stats_for(scene)
		if resource.unit_id != id: continue
		if not KnightHousing.room(get_tree(),team,resource.unit_id):
			game.notify("No housing for a %s (%s used): build a House inside a Keep's range." % [resource.display_name,KnightHousing.text(get_tree(),team)],team)
			return false
		var payer := payer_for(resource.energy_cost,resource.iron_cost,resource.food_cost,resource.wood_cost,resource.coal_cost)
		if payer == null:
			if resource.coal_cost > 0: game.notify("No Keep in range has %d F, %d I and %d C for a %s." % [resource.food_cost,resource.iron_cost,resource.coal_cost,resource.display_name],team)
			elif resource.food_cost > 0 or resource.wood_cost > 0: game.notify("No Keep in range has %d F, %d W and %d I for a %s." % [resource.food_cost,resource.wood_cost,resource.iron_cost,resource.display_name],team)
			else: game.notify("No Depot in range has %d E and %d I for a %s." % [resource.energy_cost,resource.iron_cost,resource.display_name],team)
			return false
		_set_source(payer)
		var paid := false
		if resource.food_cost > 0 or resource.wood_cost > 0 or resource.coal_cost > 0:
			var costs := {}
			if resource.energy_cost > 0: costs[&"energy"] = resource.energy_cost
			if resource.iron_cost > 0: costs[&"iron"] = resource.iron_cost
			if resource.food_cost > 0: costs[&"food"] = resource.food_cost
			if resource.wood_cost > 0: costs[&"wood"] = resource.wood_cost
			if resource.coal_cost > 0: costs[&"coal"] = resource.coal_cost
			paid = assigned_depot.spend_resources(costs)
		else: paid = assigned_depot.spend_local(resource.energy_cost,resource.iron_cost)
		if not paid: game.notify("%s lacks local production resources." % assigned_depot.name,team); return false
		pending.append(scene)
		game.notify("%s queued at %s; paid by %s." % [resource.display_name,name,assigned_depot.name],team)
		return true
	game.notify("That unit is not produced by this building.",team)
	return false
func _process(delta: float) -> void:
	if not source_friendly():
		pending.clear()
		progress = 0
		_show_model(&"show_idle")
		$Status.text = stats.display_name+" · no Depot in range"
		return
	if pending.is_empty():
		progress = 0
		brazier_lit = false; brazier_starved = false
		_show_model(&"show_idle")
		$Status.text = "%s → %s" % [stats.display_name,assigned_depot.name]
		return
	var queued_stats := unit_stats_for(pending[0])
	var build: float = queued_stats.build_seconds
	# Power above 1 does that much more work a second and draws the extra energy as it goes: a whole unit
	# at power p costs (p-1) x extra_power_energy_scale of its base energy on top. With too little energy it
	# prints at 1x.
	# Only the work that is left is done and paid for, so a long frame does not overcharge the last one.
	# A lit Stoke Brazier speeds the work as power does, paid in Coal (docs/ROUND3_KNIGHTS_COAL.md).
	var stoke := brazier_scale(delta) if progress < build else 1.0
	var work := minf(delta*stoke,build-progress)
	power_starved = false
	if power > 1.0 and progress < build:
		var fast := minf(delta*power*stoke,build-progress)
		var owed := _energy_owed+fast*(power-1.0)*stats.extra_power_energy_scale*queued_stats.energy_cost/build
		var whole := floori(owed)
		if whole == 0 or assigned_depot.spend_local(whole,0):
			_energy_owed = owed-whole
			work = fast
		else: power_starved = true
	progress = minf(build,progress+maxf(work,0.0))
	var layer: int = queued_stats.mobility.layer if queued_stats.mobility != null else MobilityRules.Layer.GROUND
	var flight_to = null
	if layer == MobilityRules.Layer.AIR:
		# A flyer leaves through the roof: the factory flies its model to where the real one will hover.
		var air_cell := _exit_cell(layer)
		if air_cell.x < 0: air_cell = ground.get_tile_at_position(global_position)
		flight_to = Transform3D(Basis(),ground.tile_to_world(air_cell)+_visuals_property(pending[0],&"position",Vector3.ZERO))
	_show_model(&"show_unit",[unit_model_scene(pending[0]),flight_to])
	_show_model(&"show_print",[progress/build])
	if progress >= build:
		var cell := _exit_cell(layer)
		exit_blocked = cell.x < 0
		if exit_blocked: $Status.text = stats.display_name+" · exit blocked, waiting"; return
		var scene = pending.pop_front()
		var unit = scene.instantiate()
		unit.team = team
		if "start_fuelled" in unit: unit.start_fuelled = FuelRules.full_tanks_for(game)
		unit.position = ground.tile_to_world(cell)
		game.get_node("Entities/Units").add_child(unit,true)
		Rally.send(self,unit)
		if unit.unit_stats.unit_id in [&"infantry",&"forester_maiden",&"round_table_marine"] and team == "player": game.units_printed += 1
		progress = 0
		_show_model(&"unit_left")
		game.notify("%s ready at %s." % [unit.unit_stats.display_name,name],team)
	$Status.text = "%s · %d queued · %d%%%s" % [stats.display_name,queue,roundi(fraction()*100),brazier_note()]
## The model a unit scene wears (its Visuals slot's model_scene), read from the packed scene without building
## the unit, so a factory can show the unit being made.
static func unit_model_scene(scene: PackedScene) -> PackedScene:
	return _visuals_property(scene,&"model_scene",null)
static func _visuals_property(scene: PackedScene, property_name: StringName, fallback: Variant) -> Variant:
	if scene == null: return fallback
	var state := scene.get_state()
	for node in range(state.get_node_count()):
		if state.get_node_name(node) != &"Visuals": continue
		for property in range(state.get_node_property_count(node)):
			if state.get_node_property_name(node,property) == property_name: return state.get_node_property_value(node,property)
	return fallback
## Where a finished unit appears: a flyer over the middle of the roof if that air cell is free, otherwise (and
## for ground units) the first free cell around the building.
func _exit_cell(layer: int) -> Vector2i:
	if layer == MobilityRules.Layer.AIR:
		var center = ground.get_tile_at_position(global_position)
		if center != null and ground.can_traverse(center,layer): return center
	return ProductionExit.find_cell(ground,global_position,stats.footprint,layer)
func _key() -> String:
	return "production_%s" % get_instance_id()
func take_damage(amount: int) -> void:
	health = maxi(0,health-maxi(0,amount))
	if health <= 0:
		set_process(false)
		for group in get_groups(): remove_from_group(group)
		_leave_wreck()
		queue_free()
## A model with a death clip stays behind to play it out, as units leave their corpses. The building
## itself is gone at once, so the wreck cannot be selected or targeted.
func _leave_wreck() -> void:
	var model := get_node_or_null("Visuals/Model")
	if model == null or not model.has_method("has_death_clip") or not model.has_death_clip(): return
	model.reparent(game if is_instance_valid(game) else get_parent())
	model.play_death()
## Production models that animate (docs/BARRACKS_MODEL.md) follow the queue; placeholders are left alone.
func _show_model(method: StringName, args := []) -> void:
	var model := get_node_or_null("Visuals/Model")
	if model != null and model.has_method(method): model.callv(method,args)
func _exit_tree() -> void:
	if is_instance_valid(assigned_depot) and assigned_depot.ownership_changed.is_connected(_source_changed): assigned_depot.ownership_changed.disconnect(_source_changed)
	if not is_instance_valid(ground): return
	for cell in cells:
		if ground.tiles[cell.y*500+cell.x].occupied_by == _key(): ground.set_tile_feature(cell,"occupied_by",null)

func assign_source(depot: Node3D) -> bool:
	if not is_instance_valid(depot) or not depot.is_in_group("depots") or not SupplySource.covers(depot,global_position,team): return false
	if not pending.is_empty(): return false
	_set_source(depot)
	return true
