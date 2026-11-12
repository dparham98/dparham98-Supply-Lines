extends Node3D
## Logic-only handle for one Coal cell (docs/BALANCED_MAP.md). All scenery remains in saved batches.
var ground: Node3D
var cell: Vector2i
var resource_kind: StringName = &"coal"
var amount: int:
	get: return ground.harvesting_rules.coal_per_tile
var remaining: int:
	get: return ground.coal_amount(cell)
func _ready() -> void:
	add_to_group("coal_cells")
func can_extract(_team: String) -> bool: return remaining > 0
func extract(requested: int, _team: String = "") -> int: return ground.harvest_coal(cell,requested)
## What is left in the whole field this cell belongs to.
func field_remaining() -> int: return ground.coal_field_remaining(ground.coal_field_at(cell))
## The handle a worker moves on to when this cell is dug out: the nearest cell of the same field with coal left.
func next_source(near: Vector3) -> Node3D:
	var next: Vector2i = ground.next_coal_cell(cell,near)
	return ground.coal_source(next) if next.x >= 0 else null
