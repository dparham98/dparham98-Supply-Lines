class_name KnightRail
extends RefCounted
## Knights rail (item 13 of the balance handoff, docs/KNIGHTS_RAIL.md). The Knights lay the same maglev track as the
## Cyborgs, paid in iron by a Keep, once the side has a standing Wainwright. A Keep with friendly track in its
## loading area then builds a train that burns coal by the metre instead of drawing a Depot's energy.
static func has_wainwright(from: Node, team: String) -> bool:
	if from == null or not from.is_inside_tree(): return false
	for building in from.get_tree().get_nodes_in_group("production_buildings"):
		if building.team == team and building.health > 0 and building.stats != null and building.stats.building_id == &"wainwright": return true
	return false
## Whether `stockpile` may pay for track: any Depot, and a Keep only while its side has a Wainwright.
static func may_pay(stockpile: Node) -> bool:
	if not is_instance_valid(stockpile) or not stockpile.is_in_group("keeps"): return true
	return has_wainwright(stockpile,stockpile.team)
