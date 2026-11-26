class_name KnightRail
extends RefCounted
## Knights rail (item 13 of the balance handoff, docs/KNIGHTS_RAIL.md). The Knights lay the same maglev track as the
## Cyborgs, paid in iron by a Keep, once the side has a standing Dragon Yard. Its Dragon Yard then builds a train at a
## covering Keep with friendly track in its loading area: one that burns coal by the metre instead of drawing a Depot's energy.
static func has_dragon_yard(from: Node, team: String) -> bool:
	if from == null or not from.is_inside_tree(): return false
	for building in from.get_tree().get_nodes_in_group("production_buildings"):
		if building.team == team and building.health > 0 and building.stats != null and building.stats.building_id == &"dragon_yard": return true
	return false
## Whether `stockpile` may pay for track: any Depot, and a Keep only while its side has a Dragon Yard.
static func may_pay(stockpile: Node) -> bool:
	if not is_instance_valid(stockpile) or not stockpile.is_in_group("keeps"): return true
	return has_dragon_yard(stockpile,stockpile.team)
## The Keep a Dragon Yard's train is built at and leaves from: a friendly Keep whose range covers the yard and has
## friendly track in its loading area, the yard's own paying Keep first. Null when there is none.
static func train_keep(yard: Node3D) -> Node3D:
	if not is_instance_valid(yard) or not yard.is_inside_tree(): return null
	var game = yard.get_tree().get_first_node_in_group("skirmish")
	var rails = game.get_node_or_null("RailNetwork") if game != null else null
	if rails == null: return null
	var keeps: Array = yard.get_tree().get_nodes_in_group("keeps").filter(func(keep): return keep.team == yard.team and keep.health > 0 and Vector2(keep.global_position.x-yard.global_position.x,keep.global_position.z-yard.global_position.z).length() <= SupplySource.radius(keep))
	keeps.sort_custom(func(a,b): return a == yard.get("assigned_depot") and b != yard.get("assigned_depot"))
	for keep in keeps:
		if not rails.loading_pieces(keep,yard.team).is_empty(): return keep
	return null
## Why a Dragon Yard can't start a train now, or "".
static func yard_train_refusal(yard: Node3D) -> String:
	var keep := train_keep(yard)
	if keep == null: return "Lay friendly track into the loading area of a Keep whose range covers this Dragon Yard first."
	return keep.train_refusal()
