class_name RailRules
extends SupplyRules
## Approved prototype rail costs. Inherited cargo fields configure the Train.
@export_range(0,10000) var rail_energy_cost := 0
@export_range(0,10000) var rail_iron_cost := 2
## Energy a train draws from a connected Depot per metre travelled.
@export_range(0,10,0.01) var train_energy_per_metre := 0.15
## Planned track (docs/RAIL_PLANNING.md) connects to a target when its centre line passes within this far of
## the target's footprint edge. Targets are friendly Depots, mines and unfinished build sites.
@export_range(0,50,0.1) var connect_reach := 4.0
## Upkeep every line with a Depot pays from its Depots: this many energy a second per 100 m of track, while
## the line is idle (docs/RAIL_PLANNING.md).
@export_range(0,100,0.01) var upkeep_per_100m := 0.1
## Each train running on the line adds this many times the idle upkeep.
@export_range(0,100,0.01) var upkeep_per_running_train := 1.0
