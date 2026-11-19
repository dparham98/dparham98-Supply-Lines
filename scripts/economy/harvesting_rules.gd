class_name HarvestingRules
extends Resource
@export_range(1,10000) var forest_wood_per_tile := 20
## How far, in cells, a worker looks for the next Forest cell when the one it is cutting runs out
## (docs/FOREST_HAND_ON.md). 0 stops it when the cell runs out, as before.
@export_range(0,64) var forest_search_cells := 10
## Fell (docs/FELL.md): after the lane to the clicked spot, Infantry also clear the Forest cells within this
## many cells of it. 0 fells only the lane.
@export_range(0,32) var fell_radius_cells := 1
## Autocast Fell (docs/FELL.md): an idle Infantry with autocast on fells the Forest within this many cells of
## where it was left.
@export_range(0,32) var autocast_fell_radius_cells := 4
@export_range(1,10000) var iron_per_tile := 250
## Iron under each cell of a mine site (docs/MINE_SITES.md). A site is 4 x 3 cells, so it holds twelve times this:
## 7,500, as much as one of the balanced map's ore fields.
@export_range(1,100000) var iron_per_site_tile := 625
## Coal in each Coal cell. Fields are drawn 20 cells large, so a field holds 1,000; contested fields are 40 cells.
@export_range(1,10000) var coal_per_tile := 50
## Coal is taken through a mine built on its seam (docs/COAL_MINES.md), as iron is. Off, Infantry dig it straight
## out of the ground as they did before, and each emptied cell becomes open ground.
@export var coal_needs_mine := true
