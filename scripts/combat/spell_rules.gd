class_name SpellRules
extends Resource
## The Grail Sentinel's Mist and Slow (item 14 of the balance handoff, docs/MIST_AND_SLOW.md). Both are cast at a point
## within `cast_range` and paid from the Sentinel's healing reserve (`med_reserve`), so casting means less healing.
@export_range(1,100,0.5) var cast_range := 20.0
@export_group("Mist")
## For `mist_seconds`, units inside a `mist_radius` circle can be seen only from within `mist_reveal` of them.
@export_range(0,1000) var mist_cost := 40
@export_range(0.5,60,0.5) var mist_seconds := 8.0
@export_range(0.5,50,0.5) var mist_radius := 8.0
@export_range(0,50,0.5) var mist_reveal := 8.0
@export_group("Slow")
## Researched at the Forge (`Research.SLOW`). Enemy units in a `slow_radius` circle move at `slow_factor` of their
## speed for `slow_seconds`.
@export_range(0,1000) var slow_cost := 25
@export_range(0.5,60,0.5) var slow_seconds := 5.0
@export_range(0.5,50,0.5) var slow_radius := 5.0
@export_range(0.05,1,0.05) var slow_factor := 0.6
