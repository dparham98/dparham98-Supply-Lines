extends "res://scripts/gameplay/resource_node.gd"
@export var footprint := Vector2i(3,3)
var cells: Array[Vector2i] = []
@onready var ground = get_tree().get_first_node_in_group("terrain_grid")
func _ready() -> void:
	resource_kind = &"wood"
	resource_name = "Wood stand"
	var center = ground.get_tile_at_position(global_position)
	var start: Vector2i = center-footprint/2 if center != null else Vector2i(-1,-1)
	if not ground.is_footprint_valid(start,footprint): push_error("Wood stand needs an exact open footprint"); queue_free(); return
	global_position = ground.tile_to_world(start)+Vector3(footprint.x*0.5-0.5,0,footprint.y*0.5-0.5)
	for z in range(start.y,start.y+footprint.y):
		for x in range(start.x,start.x+footprint.x):
			var cell := Vector2i(x,z)
			cells.append(cell)
			ground.set_tile_feature(cell,"occupied_by",_key())
	super._ready()
	if remaining <= 0: release_cells()
func extract(requested: int, team := "") -> int:
	var taken := super.extract(requested,team)
	if remaining <= 0: release_cells()
	return taken
func _key() -> String:
	return "wood_%s" % get_instance_id()
func release_cells() -> void:
	if not is_instance_valid(ground): return
	for cell in cells:
		if ground.tiles[cell.y*500+cell.x].occupied_by == _key(): ground.set_tile_feature(cell,"occupied_by",null)
	cells.clear()
func _exit_tree() -> void:
	release_cells()
