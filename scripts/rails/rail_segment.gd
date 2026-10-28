extends Node3D
@export var assigned_depot_path: NodePath
var assigned_depot: Node3D
var cell := Vector2i(-1,-1)
@onready var network = get_tree().get_first_node_in_group("rail_network")
func _ready() -> void:
	if assigned_depot == null and not assigned_depot_path.is_empty(): assigned_depot = get_node_or_null(assigned_depot_path)
	var authored_cell = network.ground.get_tile_at_position(global_position)
	if authored_cell == null: queue_free(); return
	cell = authored_cell
	if not network.register(self): queue_free(); return
	global_position = network.ground.tile_to_world(cell)
	add_to_group("rails")
	update_color()
func update_color() -> void:
	for item in $Visuals.get_children():
		if not item is MeshInstance3D: continue
		if item.material_override == null: item.material_override = item.mesh.material.duplicate()
		item.material_override.albedo_color = Color(0.55,0.65,0.7) if network.friendly(cell,"player") else Color(0.65,0.25,0.2)
func _exit_tree() -> void:
	if is_instance_valid(network): network.unregister(self)
