extends Node3D
## The mark a Grail Sentinel's Slow leaves (docs/MIST_AND_SLOW.md). The slowing itself is put on each unit when cast
## (`unit_agent.apply_slow`); this only shows the circle until it ends.
var seconds := 5.0
func _process(delta: float) -> void:
	seconds -= delta
	if seconds <= 0.0: queue_free()
