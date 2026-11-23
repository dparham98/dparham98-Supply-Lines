extends Node3D
## Logic-only handle for an existing forest cell. All scenery remains in saved batches.
var ground: Node3D
var cell: Vector2i
var resource_kind: StringName = &"wood"
var amount: int:
	get: return ground.harvesting_rules.forest_wood_per_tile
var remaining: int:
	get: return ground.forest_amount(cell)
func _ready() -> void:
	add_to_group("forest_cells")
func can_extract(_team: String) -> bool: return remaining > 0
func extract(requested: int, _team: String = "") -> int: return ground.harvest_forest(cell,requested)
## The handle a worker moves on to when this cell is cut out: the nearest Forest cell near it with wood left.
func next_source(near: Vector3) -> Node3D:
	var next: Vector2i = ground.next_forest_cell(cell,near)
	return ground.forest_source(next) if next.x >= 0 else null
