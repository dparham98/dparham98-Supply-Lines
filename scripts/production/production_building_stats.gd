class_name ProductionBuildingStats
extends Resource
@export var building_id: StringName
@export var display_name := "Production building"
@export var energy_cost := 0
@export var iron_cost := 0
## Provisional dimensions, HP, queue cap and print duration, not historical balance.
@export var footprint := Vector2i(6,6)
@export var max_health := 1000
@export var queue_limit := 3
@export var print_seconds := 3.0
@export var unit_scenes: Array[PackedScene] = []
