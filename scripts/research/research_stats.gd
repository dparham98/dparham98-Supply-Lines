class_name ResearchStats
extends Resource
## One research a research building can carry out (docs/TEMPLE_OF_SCIENCE.md). It is paid when queued, takes
## `seconds` at the building, and once done holds for the whole side.
@export var research_id: StringName
@export var display_name := "Research"
@export var energy_cost := 0
@export var iron_cost := 0
@export_range(1.0,600.0,0.5) var seconds := 60.0
## One line on what it unlocks, for the card's tooltip.
@export_multiline var summary := ""
