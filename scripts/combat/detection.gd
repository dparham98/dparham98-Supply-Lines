class_name Detection
extends RefCounted
## Detection (item 9 of the balance handoff, docs/MINES.md). A hidden thing, for now only an armed land mine, is
## drawn for a side and can be targeted by it only while it lies within the detect range of one of that side's
## detectors:
## - a Depot or Keep, at its own range (SupplySource.radius, 26.25 m);
## - a unit whose UnitStats.detect_range is set: the Drone (20 m) and the Warhound (10 m).
## Nothing else detects.

## Whether `team` has a detector covering `point`. `from` is any node in the map.
static func detects(from: Node, team: String, point: Vector3) -> bool:
	if from == null or not from.is_inside_tree(): return false
	var tree := from.get_tree()
	for depot in tree.get_nodes_in_group("depots"):
		if depot.get("team") != team or depot.is_queued_for_deletion(): continue
		if depot.get("health") != null and depot.health <= 0: continue
		if _flat(depot.global_position,point) <= SupplySource.radius(depot): return true
	for unit in tree.get_nodes_in_group("units"):
		if unit.team != team or unit.health <= 0 or unit.get("unit_stats") == null: continue
		var reach: float = unit.unit_stats.detect_range
		if reach > 0.0 and _flat(unit.global_position,point) <= reach: return true
	return false
static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x-b.x,a.z-b.z).length()
