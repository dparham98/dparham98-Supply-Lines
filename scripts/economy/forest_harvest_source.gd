extends Node3D
## Logic-only handle for an existing forest cell. All scenery remains in saved batches.
var ground: Node3D
var cell: Vector2i
var resource_kind: StringName = &"wood"
var amount: int:
	get: return ground.harvesting_rules.forest_wood_per_tile
var remaining: int:
	get: return ground.forest_amount(cell)
func can_extract(_team: String) -> bool: return remaining > 0
func extract(requested: int, _team: String = "") -> int: return ground.harvest_forest(cell,requested)
