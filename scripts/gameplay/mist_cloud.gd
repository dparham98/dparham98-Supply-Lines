class_name MistCloud
extends Node3D
## A Grail Sentinel's Mist (docs/MIST_AND_SLOW.md): for `seconds`, any unit inside `radius` can be seen, and targeted,
## only from within `reveal` of it, by either side. It works through sight (`hides`, used by `unit_agent.team_sees`
## and the fog of war), not through pathing: units move through it freely.
var team := "player"
var radius := 8.0
var reveal := 8.0
var seconds := 8.0
func _ready() -> void:
	add_to_group("mists")
func _process(delta: float) -> void:
	seconds -= delta
	if seconds <= 0.0: queue_free()
func covers(point: Vector3) -> bool:
	return Vector2(point.x-global_position.x,point.z-global_position.z).length() <= radius
## Whether a Mist hides `target` from `viewer`: the target stands in a Mist and none of the viewer's units or
## buildings is within that Mist's reveal distance of it.
static func hides(target: Node3D, viewer: String) -> bool:
	if not is_instance_valid(target) or not target.is_inside_tree() or not target.is_in_group("units"): return false
	var mists := target.get_tree().get_nodes_in_group("mists")
	if mists.is_empty(): return false
	for mist in mists:
		if mist.is_queued_for_deletion() or not mist.covers(target.global_position): continue
		if not _watched(target,viewer,mist.reveal): return true
	return false
static func _watched(target: Node3D, viewer: String, within: float) -> bool:
	for group in ["units","selectable_buildings"]:
		for node in target.get_tree().get_nodes_in_group(group):
			if node == target or node.get("team") != viewer: continue
			if node.get("health") != null and node.health <= 0: continue
			if node.global_position.distance_to(target.global_position) <= within: return true
	return false
