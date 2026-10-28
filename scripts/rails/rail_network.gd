extends Node
signal changed
@export var rules: RailRules
@export var segment_scene: PackedScene
@export var train_scene: PackedScene
var revision := 0
var segments: Dictionary = {}
var subscribed: Dictionary = {}
const NEIGHBORS = [Vector2i(1,0),Vector2i(-1,0),Vector2i(0,1),Vector2i(0,-1)]
@onready var ground = get_tree().get_first_node_in_group("terrain_grid")
@onready var game = get_parent()
func _ready() -> void: add_to_group("rail_network")
func friendly(cell: Vector2i, team: String) -> bool:
	var rail = segments.get(cell)
	return is_instance_valid(rail) and is_instance_valid(rail.assigned_depot) and rail.assigned_depot.health > 0 and rail.assigned_depot.team == team
func register(rail: Node3D) -> bool:
	if not ground.is_tile_in_bounds(rail.cell) or segments.has(rail.cell) or ground.get_terrain(rail.cell) not in [0,2] or not is_instance_valid(rail.assigned_depot): return false
	var tile: Dictionary = ground.tiles[rail.cell.y*500+rail.cell.x]
	if not tile.buildable or (tile.occupied_by != null and not str(tile.occupied_by).begins_with("agent_")): return false
	segments[rail.cell] = rail
	ground.tiles[rail.cell.y*500+rail.cell.x]["rail"] = rail
	var id: int = rail.assigned_depot.get_instance_id()
	if not subscribed.has(id):
		subscribed[id] = true
		rail.assigned_depot.ownership_changed.connect(_owner_changed)
		rail.assigned_depot.tree_exiting.connect(_owner_changed)
	_announce()
	return true
func unregister(rail: Node3D) -> void:
	if segments.get(rail.cell) != rail: return
	segments.erase(rail.cell)
	if is_instance_valid(ground) and ground.is_tile_in_bounds(rail.cell): ground.tiles[rail.cell.y*500+rail.cell.x].erase("rail")
	_announce()
func _owner_changed() -> void:
	for rail in segments.values():
		if is_instance_valid(rail): rail.update_color()
	_announce()
func can_build(cell: Vector2i, payer: Node3D) -> bool:
	if not is_instance_valid(payer) or not payer.is_in_group("depots") or payer.team != "player" or payer.health <= 0 or not ground.is_tile_valid(cell) or segments.has(cell): return false
	# All four tile corners must remain within the explicitly selected payer territory.
	var center: Vector3 = ground.tile_to_world(cell)
	for x in [-0.5,0.5]:
		for z in [-0.5,0.5]:
			if (center+Vector3(x,0,z)).distance_to(payer.global_position) > payer.rules.construction_radius: return false
	return true
func build(point: Vector3) -> bool:
	var cell = ground.get_tile_at_position(point)
	var depots = game.get_node("DepotNetwork")
	if cell == null or not depots.builder_valid() or not can_build(cell,depots.selected): game.notify("Rail needs empty open land inside the paying Depot territory."); return false
	var payer = depots.selected
	if not payer.spend_local(rules.rail_energy_cost,rules.rail_iron_cost): game.notify("Paying Depot lacks local rail resources."); return false
	var rail = segment_scene.instantiate()
	rail.assigned_depot = payer
	rail.position = ground.tile_to_world(cell)
	game.add_child(rail,true)
	game.notify("Rail built from %s local stock. Click the next tile; Esc finishes." % payer.name)
	return true
func traversable(cell: Vector2i, team: String, owner: String = "", traffic := true) -> bool:
	return friendly(cell,team) and (not traffic or ground.can_traverse(cell,0,owner))
func path(start: Vector2i, goal: Vector2i, team: String, owner: String = "", traffic := true) -> Array[Vector2i]:
	if not traversable(start,team,owner,traffic) or not traversable(goal,team,owner,traffic): return []
	var frontier: Array[Vector2i] = [start]
	var parents: Dictionary = {start:start}
	var head := 0
	while head < frontier.size():
		var cell := frontier[head]; head += 1
		if cell == goal:
			var result: Array[Vector2i] = [goal]
			while result[0] != start: result.push_front(parents[result[0]])
			return result
		for offset in NEIGHBORS:
			var next: Vector2i = cell+offset
			if not parents.has(next) and traversable(next,team,owner,traffic): parents[next] = cell; frontier.append(next)
	return []
func path_to_depot(start: Vector2i, depot: Node3D, team: String, owner: String, traffic := true) -> Array[Vector2i]:
	var best: Array[Vector2i] = []
	if not is_instance_valid(depot) or depot.health <= 0 or depot.team != team: return best
	for cell in segments:
		if ground.tile_to_world(cell).distance_to(depot.global_position) > depot.dropoff_range: continue
		var route := path(start,cell,team,owner,traffic)
		if not route.is_empty() and (best.is_empty() or route.size() < best.size()): best = route
	return best
func spawn_cell(depot: Node3D) -> Vector2i:
	for cell in segments:
		if traversable(cell,depot.team) and ground.tile_to_world(cell).distance_to(depot.global_position) <= depot.dropoff_range: return cell
	return Vector2i(-1,-1)

func _announce() -> void:
	revision += 1
	changed.emit()
