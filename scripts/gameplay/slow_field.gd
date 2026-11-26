extends Node3D
## The mark a Grail Sentinel's Slow leaves (docs/MIST_AND_SLOW.md), and in green and gold its Stimulus
## (scenes/gameplay/stimulus_field.tscn, docs/ROUND3_SPELLS_AND_RESEARCH.md). The effect itself is put on each unit
## when cast (`unit_agent.apply_slow`, `apply_stimulus`); this only shows the sigil until it ends. Its Visuals
## (spell_look.gd) read `seconds` and `radius`.
var seconds := 5.0
var radius := 5.0
func _process(delta: float) -> void:
	seconds -= delta
	if seconds <= 0.0: queue_free()
