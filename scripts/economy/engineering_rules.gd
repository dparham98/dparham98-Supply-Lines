class_name EngineeringRules
extends Resource
## Prototype rates/costs, not values recovered from the original design.
@export_range(1,1000) var repair_hp := 10
@export_range(0,1000) var repair_energy := 2
@export_range(0,1000) var repair_iron := 1
## What a repair costs the Knights instead of energy, which a Keep doesn't hold (docs/VEHICLE_REPAIR.md): Wood and
## Iron from a Keep or a pitched Hearth-Wain.
@export_range(0,1000) var repair_wood := 1
@export_range(0.1,30) var repair_interval := 1.0
@export_range(5,20) var repair_range := 7.0
@export_range(0,10000) var mine_energy_cost := 0
@export_range(0,10000) var mine_iron_cost := 25
@export var mine_footprint := Vector2i(2,2)
@export_range(1,100000) var mine_health := 1000
