class_name MobileSupplyRules
extends Resource
## User-approved half-Depot ranges and two-second deployment/packing.
@export var depot_rules: DepotRules
@export_range(0.01,1) var depot_range_fraction := 0.5
@export_range(0.1,30) var depot_dropoff_range := 7.0
@export_range(0,30) var deploy_seconds := 2.0
@export_range(0,30) var pack_seconds := 2.0
func supply_radius() -> float: return depot_rules.construction_radius*depot_range_fraction
func dropoff_radius() -> float: return depot_dropoff_range*depot_range_fraction
