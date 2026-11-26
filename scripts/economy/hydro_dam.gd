extends Node3D
## A Cyborg Hydro Dam (Round 3, docs/ROUND3_CYBORG_ECONOMY.md). It stands across one of the map's dam channels
## (TerrainGrid.dam_channels) and burns nothing: every `stats.beat_seconds` it banks `stats.energy_per_beat`
## energy into the friendly Depot whose range covers it, while that Depot has the room. Nothing is pooled: the
## energy goes into that one Depot. A beat that finds the Depot full waits at its end, so blocked time banks
## nothing.
@export var stats: HydroDamStats
@export var team := "player"
var health := 600
var max_health: int:
	get: return stats.max_health
var assigned_depot: Node3D
var cells: Array[Vector2i] = []
var state := "Waiting for a Depot"
## Seconds into the current beat.
var beat_elapsed := 0.0
var _search_left := 0.0
@onready var ground = get_tree().get_first_node_in_group("terrain_grid")
func _ready() -> void:
	health = stats.max_health
	add_to_group("selectable_buildings")
	add_to_group("hydro_dams")
	var start: Vector2i = ground.get_tile_at_position(global_position)-stats.footprint/2
	if not ground.dam_site_valid(start,stats.footprint):
		push_error("A Hydro Dam must stand across a dam channel")
		queue_free()
		return
	global_position = ground.tile_to_world(start)+Vector3(stats.footprint.x*0.5-0.5,0,stats.footprint.y*0.5-0.5)
	for z in range(start.y,start.y+stats.footprint.y):
		for x in range(start.x,start.x+stats.footprint.x):
			var cell := Vector2i(x,z)
			cells.append(cell)
			ground.set_tile_feature(cell,"occupied_by",_key())
	# Its team_color surfaces take its side's paint (docs/TEAM_MARKERS.md).
	preload("res://scripts/components/team_paint.gd").apply(get_node_or_null("Visuals/Model"),team)
	if not source_valid(): find_source()
	_update_display()
## Takes the nearest friendly Depot whose range covers it, as a Generator does (docs/DEPOT_RANGE.md).
func find_source() -> bool:
	var best: Node3D = null
	for depot in get_tree().get_nodes_in_group("depots"):
		if depot.is_queued_for_deletion() or depot.health <= 0 or not SupplySource.covers(depot,global_position,team): continue
		if best == null or depot.global_position.distance_to(global_position) < best.global_position.distance_to(global_position): best = depot
	assigned_depot = best
	return best != null
func source_valid() -> bool:
	return is_instance_valid(assigned_depot) and not assigned_depot.is_queued_for_deletion() and assigned_depot.team == team and assigned_depot.health > 0 and SupplySource.covers(assigned_depot,global_position,team)
func active() -> bool:
	return health > 0 and source_valid() and assigned_depot.stockpile.space() >= stats.energy_per_beat
## Energy a second while it banks, for the HUD.
func output_rate() -> float:
	return float(stats.energy_per_beat)/stats.beat_seconds if active() else 0.0
func _process(delta: float) -> void:
	if health <= 0: return
	if not source_valid():
		# Its Depot was lost or captured: look for another covering one about twice a second.
		_search_left -= delta
		if _search_left <= 0.0:
			_search_left = 0.5
			find_source()
		if not source_valid():
			beat_elapsed = 0.0
			_update_display()
			return
	beat_elapsed = minf(stats.beat_seconds,beat_elapsed+maxf(0.0,delta))
	if beat_elapsed >= stats.beat_seconds and assigned_depot.stockpile.space() >= stats.energy_per_beat:
		assigned_depot.stockpile.deposit(&"energy",stats.energy_per_beat)
		beat_elapsed = 0.0
	_update_display()
func describe_state() -> String:
	if health <= 0: return "Destroyed"
	if not source_valid(): return "Paused · no friendly Depot covers it"
	if assigned_depot.stockpile.space() < stats.energy_per_beat: return "Paused · %s has no room" % assigned_depot.name
	return "Banking %d E every %s s into %s" % [stats.energy_per_beat,str(stats.beat_seconds),assigned_depot.name]
func _update_display() -> void:
	state = describe_state()
	$Status.text = "HYDRO DAM · %s" % state
	var model := get_node_or_null("Visuals/Model")
	if model != null and model.has_method("show_running"): model.show_running(active())
func _key() -> String:
	return "hydro_dam_%s" % get_instance_id()
func _exit_tree() -> void:
	if not is_instance_valid(ground): return
	for cell in cells:
		if ground.tiles[cell.y*ground.grid_size.x+cell.x].occupied_by == _key(): ground.set_tile_feature(cell,"occupied_by",null)
func take_damage(amount: int) -> void:
	health = maxi(0,health-maxi(0,amount))
	if health <= 0:
		set_process(false)
		for group in get_groups(): remove_from_group(group)
		queue_free()
