class_name RailRules
extends SupplyRules
## Approved prototype rail costs. Inherited cargo fields configure the Train.
@export_range(0,10000) var rail_energy_cost := 0
@export_range(0,10000) var rail_iron_cost := 2
## Energy a train draws from a connected Depot per metre travelled.
@export_range(0,10,0.01) var train_energy_per_metre := 0.15
