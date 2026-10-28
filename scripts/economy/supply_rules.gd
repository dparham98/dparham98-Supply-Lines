class_name SupplyRules
extends Resource
## All values provisional; runtime inventory is never stored here.
@export_range(0,10000) var generator_energy_cost := 100
@export_range(0,10000) var generator_iron_cost := 20
## Legacy Inspector compatibility only; GeneratorRules now defines fuel conversion.
@export_range(0,100) var energy_per_second := 5.0
@export var generator_footprint := Vector2i(3,3)
@export_range(0,10000) var cargo_energy_cost := 100
@export_range(0,10000) var cargo_iron_cost := 20
@export_range(1,1000) var cargo_capacity := 100
@export_range(0.1,30) var cargo_speed := 4.0
@export_range(1,1000) var cargo_health := 80
@export_range(0.1,30) var transfer_seconds := 2.0
