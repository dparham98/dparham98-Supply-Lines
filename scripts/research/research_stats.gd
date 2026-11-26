class_name ResearchStats
extends Resource
## One research a research building can carry out (docs/TEMPLE_OF_SCIENCE.md). It is paid when queued, takes
## `seconds` at the building, and once done holds for the whole side.
@export var research_id: StringName
@export var display_name := "Research"
@export var energy_cost := 0
@export var iron_cost := 0
## Food, for research paid by a Keep (the Knights' Forge).
@export var food_cost := 0
## Coal, for the Forge's Sundering Lances and Forest Camouflage (docs/ROUND3_SPELLS_AND_RESEARCH.md).
@export var coal_cost := 0
## An upgrade level (docs/UPGRADES.md): the line it belongs to and its level, 1 to 3. Level n needs n-1 first.
@export var line: StringName
@export_range(0,3,1) var level := 0
@export_range(1.0,600.0,0.5) var seconds := 60.0
## One line on what it unlocks, for the card's tooltip.
@export_multiline var summary := ""
