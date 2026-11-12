class_name HarvestingRules
extends Resource
@export_range(1,10000) var forest_wood_per_tile := 20
@export_range(1,10000) var iron_per_tile := 250
## Coal in each Coal cell. Fields are drawn 20 cells large, so a field holds 1,000; contested fields are 40 cells.
@export_range(1,10000) var coal_per_tile := 50
