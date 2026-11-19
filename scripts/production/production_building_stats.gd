class_name ProductionBuildingStats
extends Resource
@export var building_id: StringName
@export var display_name := "Production building"
@export var energy_cost := 0
@export var iron_cost := 0
## Provisional dimensions, HP and queue cap, not historical balance.
@export var footprint := Vector2i(6,6)
@export var max_health := 1000
@export var queue_limit := 5
## Production power (docs/PRODUCTION_POWER.md): the player sets each building between 1x and max_power. At
## power p a unit prints in its build_seconds / p and costs p times its energy: the base at queueing, the
## rest drawn from the assigned Depot while it prints.
@export_range(1.0, 10.0, 0.5) var max_power := 4.0
@export_range(0.1, 2.0, 0.1) var power_step := 0.5
@export var unit_scenes: Array[PackedScene] = []
