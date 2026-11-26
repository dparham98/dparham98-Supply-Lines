extends Node3D
## A Forward Railhead (docs/ROUND3_TROOP_TRAINS.md), for either side: a 4 x 4 platform beside friendly track, built
## from `RailRules.railhead_iron_cost` iron. It has no supply range and stores nothing. Trains stop at it as at a
## Depot (RailNetwork.depot_reach): riders board and get off there, and a train unloading there sets its crates down
## round the platform, where a train loading there picks them up.
const RULES := preload("res://assets/economy/rail_rules.tres")
@export var team := "player"
var health := 300
var max_health: int:
	get: return RULES.railhead_health
var assigned_depot: Node3D
var cells: Array[Vector2i] = []
## Its footprint, as Depots have, for the crate apron round it (CrateYard).
var footprint: Vector2i:
	get: return RULES.railhead_footprint
@onready var ground = get_tree().get_first_node_in_group("terrain_grid")
func _ready() -> void:
	health = max_health
	var size: Vector2i = footprint
	var centre = ground.get_tile_at_position(global_position)
	var start: Vector2i = centre-size/2 if centre != null else Vector2i.ZERO
	global_position = ground.tile_to_world(start)+Vector3(size.x*0.5-0.5,0,size.y*0.5-0.5)
	for z in range(start.y,start.y+size.y):
		for x in range(start.x,start.x+size.x):
			var cell := Vector2i(x,z)
			cells.append(cell)
			ground.set_tile_feature(cell,"occupied_by",_key())
	add_to_group("railheads"); add_to_group("selectable_buildings")
	preload("res://scripts/components/team_paint.gd").apply(get_node_or_null("Visuals/Model"),team)
func _key() -> String: return "railhead_%s" % get_instance_id()
## Trains of its side stopped at it now.
func trains_here() -> Array[Node3D]:
	var result: Array[Node3D] = []
	for train in get_tree().get_nodes_in_group("rail_trains"):
		if train.team == team and train.has_method("station") and train.station() == self: result.append(train)
	return result
func _process(_delta: float) -> void:
	if has_node("Label"): $Label.text = "RAILHEAD · %d train%s here · %d/%d HP" % [trains_here().size(),"" if trains_here().size() == 1 else "s",health,max_health]
func take_damage(hit: int) -> void:
	health = maxi(0,health-maxi(0,hit))
	if health <= 0:
		set_process(false)
		for group in get_groups(): remove_from_group(group)
		queue_free()
func _exit_tree() -> void:
	if not is_instance_valid(ground): return
	for cell in cells:
		if ground.tiles[cell.y*ground.grid_size.x+cell.x].occupied_by == _key(): ground.set_tile_feature(cell,"occupied_by",null)
