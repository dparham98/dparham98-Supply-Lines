extends Node3D
## BALANCE PROTOTYPE: a House. It adds housing while it stands inside a friendly Keep's range (knight_supply.gd).
@export var team := "player"
var assigned_depot: Node3D
var health := 250
var max_health := 250
var size := Vector2i(3,3)
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
	add_to_group("houses")
	add_to_group("selectable_buildings")
func _key() -> String: return "house_%s" % get_instance_id()
func take_damage(hit: int) -> void:
	health = maxi(0,health-maxi(0,hit))
	if health <= 0:
		for group in get_groups(): remove_from_group(group)
		queue_free()
func _exit_tree() -> void:
	if not is_instance_valid(ground): return
	for cell in cells:
		if ground.tiles[cell.y*500+cell.x].occupied_by == _key(): ground.set_tile_feature(cell,"occupied_by",null)
