class_name FuelRules
extends Resource
## Editable prototype fuel values from docs/ECONOMY_PLAN.md; not recovered original balance.
## Fuel only applies in scenes whose skirmish root enables vehicle_fuel_required (see docs/FUEL_BATCH.md).
@export_range(0,1000,1) var reserve_capacity: float = 30.0
## Off leaves this vehicle type free to operate (Drone until landing rules are approved).
@export var consumes_fuel := true
@export_range(0,10,0.01) var coal_per_movement_unit := 0.10
## Coal burned every second while the vehicle is in the air, moving or not (the Drone, item 10 of the balance
## handoff). Out of coal, a flyer lands where it is and waits to be refuelled. 0 for ground vehicles.
@export_range(0,10,0.01) var coal_per_second_airborne := 0.0
@export_range(0,100,0.5) var refuel_coal_per_second := 5.0
## Energy a vehicle takes from a friendly Depot per metre moved inside its range, instead of fuel
## (docs/FUEL_BATCH.md). 0 leaves it on its tank everywhere.
@export_range(0,10,0.01) var depot_energy_per_metre := 0.2
@export_range(0,1,0.01) var low_fuel_fraction := 0.25
## Fallback for a vehicle made with no skirmish root (a scene run on its own): start with a full tank.
static var testing_full_tanks := true
## Whether a vehicle made now starts with a full tank. The map's skirmish decides (`testing_full_tanks`, on
## except on the balanced map, economy report step 5 in PR #66); the fallback applies only without one.
static func full_tanks_for(game: Node) -> bool:
	if is_instance_valid(game) and game.get("testing_full_tanks") is bool: return game.testing_full_tanks
	return testing_full_tanks
