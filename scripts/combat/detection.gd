class_name Detection
extends RefCounted
## Detection (item 9 of the balance handoff, docs/MINES.md). A hidden thing is drawn for the other side and can be
## targeted by it only while it lies within the detect range of one of that side's detectors. Hidden things
## (`is_camouflaged`):
## - an armed land mine;
## - a unit camouflaged now: a Warhound in forest once its side has Forest Camouflage
##   (docs/ROUND3_SPELLS_AND_RESEARCH.md).
## Detectors:
## - a Depot or Keep, at its own range (SupplySource.radius, 26.25 m);
## - a unit whose UnitStats.detect_range is set: the Drone (20 m) and the Warhound (15 m).
## Nothing else detects.

## Whether `node` is hidden from the other side now, unless a detector covers it.
static func is_camouflaged(node: Node) -> bool:
	if not is_instance_valid(node): return false
	if node.is_in_group("land_mines"): return node.get("armed") == true
	return node.has_method("camouflaged") and node.camouflaged()
## Whether `side` can't see `node` now for its camouflage: another side's hidden thing that no detector of `side`
## covers.
static func hidden_from(node: Node, side: String) -> bool:
	if not is_instance_valid(node) or node.get("team") == side or not is_camouflaged(node): return false
	return not detects(node,side,node.global_position)

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
