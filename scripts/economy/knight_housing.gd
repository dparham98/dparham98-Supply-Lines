class_name KnightHousing
extends RefCounted
## Knights housing (docs/KNIGHTS_ECONOMY.md). Side-wide: each standing Keep of the side gives `keep_room`, and each
## House gives `house_room` while it stands inside the range of one of the side's Keeps. Units alive and units
## queued in the side's Keeps and Chapterhouses use it. Training waits while there is no room.
const RULES := preload("res://assets/economy/knights_rules.tres")
static func rules() -> KnightsRules: return RULES
static func cost(id: StringName) -> int:
	return int(RULES.housing.get(id,0))
static func _standing(node: Node) -> bool:
	return is_instance_valid(node) and not node.is_queued_for_deletion() and node.get("health") != null and node.health > 0
static func cap(tree: SceneTree, team: String) -> int:
	var keeps: Array = tree.get_nodes_in_group("keeps").filter(func(k): return k.team == team and _standing(k))
	var total: int = keeps.size()*RULES.keep_room
	for house in tree.get_nodes_in_group("houses"):
		if house.team != team or not _standing(house): continue
		for keep in keeps:
			if SupplySource.covers(keep,house.global_position,team): total += RULES.house_room; break
	return total
static func used(tree: SceneTree, team: String) -> int:
	var total := 0
	for unit in tree.get_nodes_in_group("units"):
		if unit.team == team and _standing(unit) and unit.get("unit_stats") != null: total += cost(unit.unit_stats.unit_id)
	for keep in tree.get_nodes_in_group("keeps"):
		if keep.team != team: continue
		for kind in keep.pending: total += cost(StringName(kind))
	for building in tree.get_nodes_in_group("production_buildings"):
		if building.team != team: continue
		for scene in building.pending: total += cost(building.unit_stats_for(scene).unit_id)
	return total
## Whether the side has room to train one more `id`.
static func room(tree: SceneTree, team: String, id: StringName) -> bool:
	return cost(id) <= 0 or used(tree,team)+cost(id) <= cap(tree,team)
## Whether the side keeps any housing at all (a Knights side).
static func applies(tree: SceneTree, team: String) -> bool:
	return tree.get_nodes_in_group("keeps").any(func(k): return k.team == team)
static func text(tree: SceneTree, team: String) -> String:
	return "%d / %d" % [used(tree,team),cap(tree,team)]
