class_name HydroDamStats
extends Resource
## A Cyborg Hydro Dam (Round 3, docs/ROUND3_CYBORG_ECONOMY.md). It stands across a dam channel on the map
## (TerrainGrid.dam_channels), burns nothing, and banks energy into the friendly Depot whose range covers it.
@export var display_name := "Hydro Dam"
@export var energy_cost := 0
@export var iron_cost := 90
## Cells across the channel (x) and along it (z). Two Lakes' channels are 8 cells wide.
@export var footprint := Vector2i(8,3)
@export var max_health := 600
## Energy banked every `beat_seconds` while the Depot has room: 12 every 3 s is 4 a second.
@export_range(0,1000) var energy_per_beat := 12
@export_range(0.1,60,0.1) var beat_seconds := 3.0
