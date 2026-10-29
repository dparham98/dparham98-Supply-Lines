class_name FuelRules
extends Resource
## Editable prototype fuel values from docs/ECONOMY_PLAN.md; not recovered original balance.
## Fuel only applies in scenes whose skirmish root enables vehicle_fuel_required (see docs/FUEL_BATCH.md).
@export_range(0,1000,1) var reserve_capacity: float = 30.0
## Off leaves this vehicle type free to operate (Drone until landing rules are approved).
@export var consumes_fuel := true
@export_range(0,10,0.01) var coal_per_movement_unit := 0.10
@export_range(0,100,0.5) var refuel_coal_per_second := 5.0
@export_range(0,1,0.01) var low_fuel_fraction := 0.25
