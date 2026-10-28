extends Node3D
@export var resource_name := "Iron"
@export var resource_kind: StringName = &"iron"
@export var amount := 500
var remaining := 500
func _ready() -> void:
	remaining = amount
	add_to_group("iron_deposits" if resource_kind == &"iron" and not is_in_group("mines") else "resources")
	update_label()
func can_extract(_team: String) -> bool:
	return resource_kind != &"iron" or is_in_group("mines")
func extract(requested: int, _team := "") -> int:
	if not can_extract(_team): return 0
	var taken := mini(maxi(0,requested),remaining)
	remaining -= taken
	update_label()
	return taken
func update_label() -> void:
	$Label.text = "%s · %d" % [resource_name,remaining] if remaining > 0 else resource_name+" depleted"
	$Visuals.visible = remaining > 0

func _process(_delta: float) -> void:
	if resource_kind != &"iron" or is_in_group("mines"): return
	var ground = get_tree().get_first_node_in_group("terrain_grid")
	var cell = ground.get_tile_at_position(global_position)
	var mine = ground.iron_mines.get(cell)
	$Label.visible = not is_instance_valid(mine)
	$Visuals.visible = not is_instance_valid(mine)
	$Label.text = "Iron deposit · mine required"
