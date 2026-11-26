class_name ForgeResearchRules
extends Resource
## The Forge's Sundering Lances and Forest Camouflage (Round 3, docs/ROUND3_SPELLS_AND_RESEARCH.md). Both are
## researched at the Forge and hold for the whole side.
@export_group("Sundering Lances")
## A hit from a unit with the `sundering_lances` ability (the Questing Marine) on an armoured or giant unit marks it
## sundered for `sunder_seconds`. Every hit on a sundered unit, from anyone, deals `sunder_bonus` more after armour.
@export_range(0.5,30,0.5) var sunder_seconds := 4.0
@export_range(0,50) var sunder_bonus := 3
@export_group("Forest Camouflage")
## A unit with the `forest_camouflage` ability (the Warhound) is hidden in forest from the other side, unless one of
## its detectors covers it. It stays hidden `camo_leave_grace` s after it leaves the forest, and attacking breaks the
## camouflage for `camo_attack_break` s.
@export_range(0,10,0.1) var camo_leave_grace := 1.5
@export_range(0,10,0.1) var camo_attack_break := 2.0
