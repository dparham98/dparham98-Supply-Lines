class_name RailRules
extends SupplyRules
## Approved prototype rail costs. Inherited cargo fields configure the Train.
@export_range(0,10000) var rail_energy_cost := 0
@export_range(0,10000) var rail_iron_cost := 2
## Energy a train draws from a connected Depot per metre travelled.
@export_range(0,10,0.01) var train_energy_per_metre := 0.15
## Planned track (docs/RAIL_PLANNING.md) connects to a mine or build site when its edge comes within this far
## of the target's footprint edge. A Depot instead uses its loading area, where trains are built and load.
@export_range(0,50,0.1) var connect_reach := 4.0
## A Depot's rail ring, as a fraction of its range: where track connects to it and trains are built, load and
## unload. 0.5 matches a deployed Cargo truck's range, 13.125 m at the 26.25 m Depot range.
@export_range(0.05,1,0.01) var depot_reach_fraction := 0.5
## Upkeep every line with a Depot pays from its Depots: this many energy a second per 100 m of track, while
## the line is idle (docs/RAIL_PLANNING.md).
@export_range(0,100,0.01) var upkeep_per_100m := 0.1
## Each train running on the line adds this many times the idle upkeep.
@export_range(0,100,0.01) var upkeep_per_running_train := 1.0
