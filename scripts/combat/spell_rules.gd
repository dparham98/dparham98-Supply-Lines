class_name SpellRules
extends Resource
## The Grail Sentinel's Mist, Slow and Stimulus (item 14 of the balance handoff, docs/MIST_AND_SLOW.md; Stimulus from
## Round 3, docs/ROUND3_SPELLS_AND_RESEARCH.md). Each is cast at a point and paid from the Sentinel's healing reserve
## (`med_reserve`), so casting means less healing. Mist and Slow are cast within `cast_range`, Stimulus within
## `stimulus_cast_range`.
@export_range(1,100,0.5) var cast_range := 24.0
@export_group("Mist")
## For `mist_seconds`, units inside a `mist_radius` circle can be seen only from within `mist_reveal` of them.
@export_range(0,1000) var mist_cost := 40
@export_range(0.5,60,0.5) var mist_seconds := 8.0
@export_range(0.5,50,0.5) var mist_radius := 8.0
@export_range(0,50,0.5) var mist_reveal := 8.0
@export_group("Slow")
## Researched at the Forge (`Research.SLOW`). Enemy units in a `slow_radius` circle, vehicles too but not trains, move
## at `slow_factor` of their speed for `slow_seconds`.
@export_range(0,1000) var slow_cost := 25
@export_range(0.5,60,0.5) var slow_seconds := 5.0
@export_range(0.5,50,0.5) var slow_radius := 5.0
@export_range(0.05,1,0.05) var slow_factor := 0.6
@export_group("Stimulus")
## Friendly units that are not vehicles (the Azure Dragon included) in a `stimulus_radius` circle move and attack
## `stimulus_boost` faster for `stimulus_seconds`. A second Stimulus restarts the time; it does not add up.
@export_range(0,1000) var stimulus_cost := 35
@export_range(1,100,0.5) var stimulus_cast_range := 14.0
@export_range(0.5,60,0.5) var stimulus_seconds := 7.0
@export_range(0.5,50,0.5) var stimulus_radius := 5.0
@export_range(0,2,0.05) var stimulus_boost := 0.25
