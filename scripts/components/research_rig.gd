extends "res://scripts/components/production_rig.gd"
## Plays a research building's authored clips: the Foundry (docs/FOUNDRY_MODEL.md) and the Forge
## (docs/FORGE_MODEL.md). Idle while nothing is researched, the research clip looping while an upgrade is under
## way, Build scrubbed by construction progress and Die when the building is destroyed (production_rig.gd).
## temple_of_science.gd calls show_research every frame.
@export var research_clip := &"Research"
## Seconds to blend between Idle and Research, so a started or finished upgrade does not snap.
@export_range(0.0,2.0,0.05) var blend_seconds := 0.4
func show_research(active: bool) -> void:
	if _dying: return
	var clip := research_clip if active and player.has_animation(research_clip) else idle_clip
	if player.is_playing() and player.assigned_animation == clip: return
	player.play(clip,blend_seconds)
func researching() -> bool:
	return not _dying and player.is_playing() and player.assigned_animation == research_clip
