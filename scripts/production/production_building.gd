extends Node3D
@export var stats: ProductionBuildingStats
@export var team := "player"
@export var assigned_depot_path: NodePath
var assigned_depot: Node3D
var health := 1000
var max_health: int:
	get: return stats.max_health
var pending: Array[PackedScene] = []
var queue: int:
	get: return pending.size()
var progress := 0.0
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
	if is_instance_valid(assigned_depot): assigned_depot.ownership_changed.connect(_source_changed)
func source_friendly() -> bool:
	return team == "player" and is_instance_valid(assigned_depot) and assigned_depot.health > 0 and assigned_depot.team == team
func _source_changed() -> void:
	# Preserve the existing Depot policy: paid queue cancellation without refund on source capture.
	pending.clear()
	progress = 0
func unit_stats_for(scene: PackedScene) -> UnitStats:
	var unit = scene.instantiate()
	var resource: UnitStats = unit.unit_stats
	unit.free()
	return resource
func request_unit(id: StringName) -> bool:
	if not source_friendly(): game.notify("Assigned Depot is unavailable or no longer friendly."); return false
	if queue >= stats.queue_limit: game.notify("Production queue is full."); return false
	for scene in stats.unit_scenes:
		var resource := unit_stats_for(scene)
		if resource.unit_id != id: continue
		if not assigned_depot.spend_local(resource.energy_cost,resource.iron_cost): game.notify("Assigned Depot lacks local production resources."); return false
		pending.append(scene)
		game.notify("%s queued at %s; paid by %s." % [resource.display_name,name,assigned_depot.name])
		return true
	game.notify("That unit is not produced by this building.")
	return false
func _process(delta: float) -> void:
	if not source_friendly():
		pending.clear()
		progress = 0
		$Status.text = stats.display_name+" · assigned Depot unavailable"
		return
	if pending.is_empty():
		progress = 0
		$Status.text = "%s → %s" % [stats.display_name,assigned_depot.name]
		return
	progress = minf(stats.print_seconds,progress+delta)
	if progress >= stats.print_seconds:
		var queued_stats := unit_stats_for(pending[0])
		var layer: int = queued_stats.mobility.layer if queued_stats.mobility != null else MobilityRules.Layer.GROUND
		var cell := ProductionExit.find_cell(ground,global_position,stats.footprint,layer)
		if cell.x < 0: $Status.text = stats.display_name+" · exit blocked, waiting"; return
		var scene = pending.pop_front()
		var unit = scene.instantiate()
		unit.team = team
		if "start_fuelled" in unit: unit.start_fuelled = false # New vehicles start empty.
		unit.position = ground.tile_to_world(cell)
		game.get_node("Entities/Units").add_child(unit,true)
		if unit.unit_stats.unit_id == &"infantry": game.units_printed += 1
		progress = 0
		game.notify("%s ready at %s." % [unit.unit_stats.display_name,name])
	$Status.text = "%s · %d queued · %d%%" % [stats.display_name,queue,roundi(progress/stats.print_seconds*100)]
func _key() -> String:
	return "production_%s" % get_instance_id()
func take_damage(amount: int) -> void:
	health = maxi(0,health-maxi(0,amount))
	if health <= 0:
		set_process(false)
		for group in get_groups(): remove_from_group(group)
		queue_free()
func _exit_tree() -> void:
	if is_instance_valid(assigned_depot) and assigned_depot.ownership_changed.is_connected(_source_changed): assigned_depot.ownership_changed.disconnect(_source_changed)
	if not is_instance_valid(ground): return
	for cell in cells:
		if ground.tiles[cell.y*500+cell.x].occupied_by == _key(): ground.set_tile_feature(cell,"occupied_by",null)

func assign_source(depot: Node3D) -> bool:
	if not is_instance_valid(depot) or not depot.is_in_group("depots") or not SupplySource.covers(depot,global_position,team): return false
	if not pending.is_empty(): return false
	if is_instance_valid(assigned_depot) and assigned_depot.ownership_changed.is_connected(_source_changed): assigned_depot.ownership_changed.disconnect(_source_changed)
	assigned_depot = depot
	assigned_depot.ownership_changed.connect(_source_changed)
	return true
