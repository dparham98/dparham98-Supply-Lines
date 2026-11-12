extends Node3D
signal ownership_changed
@export var infantry_scene: PackedScene
@export var infantry_cost := 20 # Legacy test/readout alias for iron; payment uses UnitStats.
@export var rules: DepotRules
@export var team := "player"
@export var max_health := 1000 # Provisional building durability; no new enemy targeting.
var health := 1000
@export var initial_energy := -1
@export var initial_iron := -1
var stockpile := ResourceStockpile.new()
@export var storage_capacity_override := -1
var storage_capacity: int:
	get: return stockpile.capacity
	set(value): stockpile.resize(value)
var energy: int:
	get: return stockpile.amount(&"energy")
	set(value): stockpile.set_amount(&"energy",value)
@export var initial_wood := 0
@export var initial_coal := 0
var wood: int:
	get: return stockpile.amount(&"wood")
	set(value): stockpile.set_amount(&"wood",value)
var iron: int:
	get: return stockpile.amount(&"iron")
	set(value): stockpile.set_amount(&"iron",value)
var coal: int:
	get: return stockpile.amount(&"coal")
	set(value): stockpile.set_amount(&"coal",value)
var capture_team := ""
var capture_progress := 0.0
var pending: Array[String] = []
## Enabled for newly constructed/deployed Depots, not prebuilt map fixtures.
@export var grant_construction_infantry := false
var construction_infantry_pending := false
var construction_infantry_spawned := false
func infantry_stats() -> UnitStats:
	var preview = infantry_scene.instantiate()
	var stats: UnitStats = preview.unit_stats
	preview.free()
	return stats

@export var print_seconds := 3.0
@export var dropoff_range := 8.5
@export var footprint := Vector2i(10,10)
@export var queue_limit := 3
## How much faster a cancelled truck's animation runs backwards.
@export_range(0.5,8,0.5) var cancel_speed := 2.0
var queue := 0
var cancelling := false
## Tiles reserved beside the Depot while a truck is being built there.
var truck_cells: Array[Vector2i] = []
var progress := 0.0
var cells: Array[Vector2i] = []
@onready var game = get_tree().get_first_node_in_group("skirmish")
@onready var ground = get_tree().get_first_node_in_group("terrain_grid")
func _ready() -> void:
	construction_infantry_pending = grant_construction_infantry and team == "player"
	if construction_infantry_pending: call_deferred("try_construction_infantry")
	stockpile = ResourceStockpile.new(storage_capacity_override if storage_capacity_override > 0 else rules.storage_capacity)
	health = max_health
	add_to_group("selectable_buildings")
	# Startup priority reserves the enabled testing iron grant before other authored stock.
	iron = rules.testing_starting_iron if rules.testing_starting_iron >= 0 else (rules.initial_iron if initial_iron < 0 else initial_iron)
	wood = initial_wood
	coal = initial_coal
	energy = rules.initial_energy if initial_energy < 0 else initial_energy
	$Territory.scale = Vector3.ONE * rules.construction_radius
	add_to_group("depots")
	add_to_group("capturable_buildings")
	add_to_group("headquarters")
	var center = ground.get_tile_at_position(global_position)
	var start: Vector2i = ground.find_buildable_footprint(center-footprint/2,footprint)
	if start.x < 0:
		push_error("No valid footprint for authored Depot")
		queue_free()
		return
	global_position = ground.tile_to_world(start)+Vector3(footprint.x*0.5-0.5,0,footprint.y*0.5-0.5)
	for z in range(start.y,start.y+footprint.y):
		for x in range(start.x,start.x+footprint.x):
			var cell := Vector2i(x,z)
			cells.append(cell)
			ground.set_tile_feature(cell,"occupied_by","depot_%s" % get_instance_id())
func request_infantry() -> bool:
	# Compatibility rejection: repeatable infantry production belongs to Barracks.
	game.notify("Depots grant one Infantry on establishment. Produce additional Infantry at Barracks.")
	return false
func _process(delta: float) -> void:
	update_capture(delta)
	try_construction_infantry()
	if queue <= 0: progress = 0; $Progress.text = "%s DEPOT · E %d / I %d · capture %d%%" % [team,energy,iron,roundi(capture_progress/rules.capture_seconds*100)]; return
	if team != "player": return
	if cancelling: _step_cancel(delta); return
	var truck: bool = pending[0] == "truck"
	var seconds := current_seconds()
	if truck and truck_cells.is_empty():
		if $Visuals/Model.deploying(): $Progress.text = "Depot unfolding · truck waiting"; return
		if not _begin_truck(): $Progress.text = "Exit blocked · waiting"; return
	progress = minf(seconds,progress+delta)
	if truck: $Visuals/Model.show_truck(progress)
	$Progress.text = "Printing %s · %d%%" % [pending[0],roundi(progress/seconds*100)]
	if progress >= seconds:
		if truck: _complete_truck(); return
		var center = ground.get_tile_at_position(global_position)
		var spawn := Vector2i(-1,-1)
		for radius in range(6,16):
			for offset in [Vector2i(0,radius),Vector2i(radius,0),Vector2i(-radius,0),Vector2i(0,-radius)]:
				if ground.is_tile_valid(center+offset): spawn = center+offset; break
			if spawn.x >= 0: break
		if pending[0] != "train" and spawn.x < 0: $Progress.text = "Exit blocked · waiting"; return
		var train_stop := {}
		if pending[0] == "train":
			train_stop = game.get_node("RailNetwork").spawn_stop(self)
			if train_stop.is_empty(): $Progress.text = "Train needs friendly track in the Depot loading area"; return
		var kind: String = pending.pop_front()
		var scene: PackedScene = infantry_scene
		if kind == "cargo": scene = game.get_node("DepotNetwork").cargo_scene
		elif kind == "train": scene = game.get_node("RailNetwork").train_scene
		var unit = scene.instantiate()
		if "start_fuelled" in unit: unit.start_fuelled = FuelRules.testing_full_tanks
		unit.position = train_stop.position if not train_stop.is_empty() else ground.tile_to_world(spawn)
		game.get_node("Entities/Units").add_child(unit,true)
		queue -= 1
		progress = 0
		if kind == "infantry": game.units_printed += 1
		game.notify("%s ready at %s." % [kind,name])

## Seconds the job at the head of the queue takes.
func current_seconds() -> float:
	return $Visuals/Model.truck_seconds() if not pending.is_empty() and pending[0] == "truck" else print_seconds
## The tiles a new truck stands on beside this Depot, or none if that ground is off the map.
func truck_side_cells() -> Array[Vector2i]:
	var side: AABB = $Visuals/Model.truck_side
	var result: Array[Vector2i] = []
	var a = ground.get_tile_at_position($Visuals/Model.to_global(side.position))
	var b = ground.get_tile_at_position($Visuals/Model.to_global(side.end))
	if a == null or b == null: return result
	for z in range(mini(a.y,b.y),maxi(a.y,b.y)+1):
		for x in range(mini(a.x,b.x),maxi(a.x,b.x)+1): result.append(Vector2i(x,z))
	return result
func _begin_truck() -> bool:
	var side := truck_side_cells()
	if side.is_empty(): return false
	for cell in side:
		if not ground.is_tile_valid(cell): return false
	for cell in side: ground.set_tile_feature(cell,"occupied_by","depot_%s" % get_instance_id())
	truck_cells = side
	return true
func _release_truck_side() -> void:
	for cell in truck_cells:
		if ground.tiles[cell.y*ground.grid_size.x+cell.x].occupied_by == "depot_%s" % get_instance_id(): ground.set_tile_feature(cell,"occupied_by",null)
	truck_cells.clear()
## The chassis and trailer on the side become the real truck, on the same spot.
func _complete_truck() -> void:
	var where: Vector3 = $Visuals/Model.assembly.global_position
	pending.pop_front()
	queue -= 1
	progress = 0
	_release_truck_side()
	$Visuals/Model.finish_truck()
	var unit = game.get_node("DepotNetwork").truck_scene.instantiate()
	unit.start_fuelled = FuelRules.testing_full_tanks
	unit.position = where
	game.get_node("Entities/Units").add_child(unit,true)
	unit.global_position = where
	unit.get_node("Visuals").rotation.y = $Visuals.rotation.y
	game.notify("truck ready at %s." % name)
func can_cancel() -> bool:
	return team == "player" and queue > 0 and not pending.is_empty() and not cancelling
## Cancels the job in progress for a full refund. A truck first backs its animation out.
func cancel_current() -> bool:
	if not can_cancel(): return false
	if truck_cells.is_empty(): _drop_current()
	else: cancelling = true
	return true
func _step_cancel(delta: float) -> void:
	progress = maxf(0.0,progress-delta*cancel_speed)
	$Visuals/Model.show_truck(progress)
	$Progress.text = "Cancelling truck · %d%%" % roundi(progress/current_seconds()*100)
	if progress <= 0.0:
		_release_truck_side()
		_drop_current()
func _drop_current() -> void:
	var cost := _job_cost(pending.pop_front())
	queue -= 1
	progress = 0
	cancelling = false
	stockpile.deposit(&"energy",cost.x)
	stockpile.deposit(&"iron",cost.y)
func _job_cost(kind: String) -> Vector2i:
	match kind:
		"truck": return Vector2i(rules.truck_energy_cost,rules.truck_iron_cost)
		"cargo":
			var config = game.get_node("DepotNetwork").supply_rules
			return Vector2i(config.cargo_energy_cost,config.cargo_iron_cost)
		"train":
			var config = game.get_node("RailNetwork").rules
			return Vector2i(config.cargo_energy_cost,config.cargo_iron_cost)
	return Vector2i.ZERO
func spend_local(energy_cost: int, iron_cost: int) -> bool:
	return stockpile.spend({&"energy":energy_cost,&"iron":iron_cost})
func request_truck() -> bool:
	if team != "player" or queue >= queue_limit: return false
	if not spend_local(rules.truck_energy_cost,rules.truck_iron_cost): return false
	pending.append("truck")
	queue += 1
	return true
func request_cargo() -> bool:
	var config = game.get_node("DepotNetwork").supply_rules
	if team != "player" or queue >= queue_limit: return false
	if not spend_local(config.cargo_energy_cost,config.cargo_iron_cost): return false
	pending.append("cargo")
	queue += 1
	return true
func generation_rate() -> float:
	var total := 0.0
	for generator in get_tree().get_nodes_in_group("energy_generators"):
		if generator.assigned_depot == self: total += generator.output_rate()
	return total
func update_capture(delta: float) -> void:
	var teams: Array[String] = []
	for unit in get_tree().get_nodes_in_group("units"):
		if unit.health <= 0 or unit.is_depot_truck or unit.is_cargo_vehicle or not unit.can_capture_depots: continue
		if unit.global_position.distance_to(global_position) <= rules.capture_radius and not teams.has(unit.team): teams.append(unit.team)
	if teams.size() != 1 or teams[0] == team:
		capture_progress = 0
		capture_team = ""
		return
	if capture_team != teams[0]: capture_team = teams[0]; capture_progress = 0
	capture_progress += delta
	if capture_progress >= rules.capture_seconds:
		construction_infantry_pending = false
		team = capture_team
		ownership_changed.emit()
		capture_progress = 0
		capture_team = ""
		# Inventory changes hands intact; paid production is cancelled without refund.
		if not truck_cells.is_empty():
			_release_truck_side()
			$Visuals/Model.show_truck(0.0)
		cancelling = false
		pending.clear()
		queue = 0
		progress = 0
		game.get_node("DepotNetwork").select_depot(game.get_node("DepotNetwork").selected)
		game.notify("Depot captured by %s; local inventory retained, queue cancelled." % team)
func _exit_tree() -> void:
	if not is_instance_valid(ground): return
	_release_truck_side()
	for cell in cells:
		if ground.tiles[cell.y*500+cell.x].occupied_by == "depot_%s" % get_instance_id(): ground.set_tile_feature(cell,"occupied_by",null)

func take_damage(amount: int) -> void:
	health = maxi(0,health-maxi(0,amount))
	if health <= 0:
		set_process(false)
		for group in get_groups(): remove_from_group(group)
		_leave_wreck()
		queue_free()
## The model stays behind to play its collapse, as units leave their corpses. The Depot itself is gone at
## once, so the wreck cannot be selected or targeted.
func _leave_wreck() -> void:
	var model := get_node_or_null("Visuals/Model")
	if model == null or not model.has_method("has_death_clip") or not model.has_death_clip(): return
	model.reparent(game if is_instance_valid(game) else get_parent())
	model.play_death()

func try_construction_infantry() -> bool:
	if not construction_infantry_pending or construction_infantry_spawned or team != "player" or health <= 0: return false
	var spawn := ProductionExit.find_cell(ground,global_position,footprint)
	if spawn.x < 0: return false
	var unit = infantry_scene.instantiate()
	unit.team = team
	unit.position = ground.tile_to_world(spawn)
	game.get_node("Entities/Units").add_child(unit,true)
	construction_infantry_pending = false
	construction_infantry_spawned = true
	game.notify("Construction infantry ready at %s." % name)
	return true

func request_train() -> bool:
	var config = game.get_node("RailNetwork").rules
	if team != "player" or health <= 0 or queue >= queue_limit: return false
	if not spend_local(config.cargo_energy_cost,config.cargo_iron_cost): return false
	pending.append("train"); queue += 1
	game.notify("Train queued; needs friendly track in this Depot loading area.")
	return true
