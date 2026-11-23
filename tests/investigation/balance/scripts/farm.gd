extends Node3D
## BALANCE PROTOTYPE: a Farm. A worker tills it like a mine, but it gives `per_beat` Food a work beat (1.2 s), so a
## load of 10 takes 12 s; the worker then carries it to the Keep. It never runs out.
static var per_beat := 1
@export var team := "player"
var assigned_depot: Node3D
var health := 200
var max_health := 200
var resource_kind: StringName = &"food"
var resource_name := "Farm"
var remaining := 1000000
var amount := 1000000
var size := Vector2i(4,4)
var cells: Array[Vector2i] = []
@onready var ground = get_tree().get_first_node_in_group("terrain_grid")
func _ready() -> void:
	var centre = ground.get_tile_at_position(global_position)
	var start: Vector2i = centre-size/2
	global_position = ground.tile_to_world(start)+Vector3(size.x*0.5-0.5,0,size.y*0.5-0.5)
	for z in range(start.y,start.y+size.y):
		for x in range(start.x,start.x+size.x):
			var cell := Vector2i(x,z)
			cells.append(cell)
			ground.set_tile_feature(cell,"occupied_by",_key())
	add_to_group("farms")
	add_to_group("selectable_buildings")
func _key() -> String: return "farm_%s" % get_instance_id()
func can_extract(asking: String) -> bool: return asking == team and health > 0 and not is_queued_for_deletion()
func extract(requested: int, asking := "") -> int:
	if not can_extract(asking): return 0
	return mini(maxi(0,requested),per_beat)
func take_damage(hit: int) -> void:
	health = maxi(0,health-maxi(0,hit))
	if health <= 0:
		for group in get_groups(): remove_from_group(group)
		queue_free()
func _exit_tree() -> void:
	if not is_instance_valid(ground): return
	for cell in cells:
		if ground.tiles[cell.y*500+cell.x].occupied_by == _key(): ground.set_tile_feature(cell,"occupied_by",null)
