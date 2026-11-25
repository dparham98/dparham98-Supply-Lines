extends Node3D
## A Knights House (docs/KNIGHTS_ECONOMY.md). It adds `house_room` housing for its side while it stands inside the
## range of one of the side's Keeps (KnightHousing).
const RULES := preload("res://assets/economy/knights_rules.tres")
@export var team := "player"
var health := 300
var max_health: int:
	get: return RULES.house_health
var assigned_depot: Node3D
var cells: Array[Vector2i] = []
@onready var model: Node3D = $Visuals/Model
@onready var ground = get_tree().get_first_node_in_group("terrain_grid")
func _ready() -> void:
	health = max_health
	var size: Vector2i = RULES.house_footprint
	var centre = ground.get_tile_at_position(global_position)
	var start: Vector2i = centre-size/2 if centre != null else Vector2i.ZERO
	global_position = ground.tile_to_world(start)+Vector3(size.x*0.5-0.5,0,size.y*0.5-0.5)
	for z in range(start.y,start.y+size.y):
		for x in range(start.x,start.x+size.x):
			var cell := Vector2i(x,z)
			cells.append(cell)
			ground.set_tile_feature(cell,"occupied_by",_key())
	add_to_group("houses"); add_to_group("selectable_buildings")
	preload("res://scripts/components/team_paint.gd").apply(get_node_or_null("Visuals/Model"),team)
func _key() -> String: return "house_%s" % get_instance_id()
## Whether it stands inside the range of one of its side's Keeps, so its housing counts.
func housed() -> bool:
	for keep in get_tree().get_nodes_in_group("keeps"):
		if SupplySource.covers(keep,global_position,team): return true
	return false
func _process(_delta: float) -> void:
	if has_node("Label"): $Label.text = "HOUSE · %s · %d/%d HP" % ["+%d housing" % RULES.house_room if housed() else "outside Keep range: no housing",health,max_health]
func take_damage(hit: int) -> void:
	health = maxi(0,health-maxi(0,hit))
	if health <= 0 and not is_queued_for_deletion():
		set_process(false)
		for group in get_groups(): remove_from_group(group)
		model.reparent(get_parent())
		model.play_death()
		queue_free()
func _exit_tree() -> void:
	if not is_instance_valid(ground): return
	for cell in cells:
		if ground.tiles[cell.y*ground.grid_size.x+cell.x].occupied_by == _key(): ground.set_tile_feature(cell,"occupied_by",null)
