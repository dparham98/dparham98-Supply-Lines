class_name HarvestingRules
extends Resource
@export_range(1,10000) var forest_wood_per_tile := 20
@export_range(1,10000) var iron_per_tile := 250
## Iron under each cell of a mine site (docs/MINE_SITES.md). A site is 4 x 3 cells, so it holds twelve times this:
## 7,500, as much as one of the balanced map's ore fields.
@export_range(1,100000) var iron_per_site_tile := 625
## Coal in each Coal cell. Fields are drawn 20 cells large, so a field holds 1,000; contested fields are 40 cells.
@export_range(1,10000) var coal_per_tile := 50
