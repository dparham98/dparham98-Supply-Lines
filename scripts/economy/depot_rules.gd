class_name DepotRules
extends Resource
## Provisional Milestone 2 settings; see docs/MILESTONE_2.md.
@export_range(8,100) var construction_radius := 35.0
@export_range(8,30) var capture_radius := 12.0
@export_range(1,60) var capture_seconds := 8.0
@export_range(1,100000) var storage_capacity := 2000
@export var initial_energy := 500
## Testing grant applied once at spawn to every Depot. -1 restores normal inventories.
@export var testing_starting_iron := -1
@export var initial_iron := 0
@export var depot_energy_cost := 20
@export var depot_iron_cost := 20
@export var truck_energy_cost := 150
@export var truck_iron_cost := 30
@export var deployed_energy := 100
@export var deployed_iron := 0
## A new Depot (built, planned or deployed from a truck) must stand at least this far, centre to centre, from
## every other friendly Depot and Depot plan, so service ranges never overlap and free Infantry cannot be
## farmed from Depots packed together (docs/ECONOMY_REPORT.md step 6). Authored Depots are not checked. 0 is off.
@export_range(0,500) var min_depot_spacing := 70.0
