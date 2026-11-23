extends RefCounted
## BALANCE PROTOTYPE: Knights housing. A Keep houses KEEP; each House standing inside a friendly Keep's range houses HOUSE.
static var enabled := true
static var keep_room := 10
static var house_room := 8
static var cost := {&"forester_maiden": 1, &"warhound": 1, &"round_table_marine": 2, &"grail_sentinel": 2, &"questing_marine": 2, &"azure_dragon": 4}
static func cap(tree: SceneTree, team: String) -> int:
	var keeps: Array = tree.get_nodes_in_group("keeps").filter(func(k): return k.team == team and k.health > 0 and not k.is_queued_for_deletion())
	var total: int = keeps.size()*keep_room
	for house in tree.get_nodes_in_group("houses"):
		if house.team != team or house.health <= 0 or house.is_queued_for_deletion(): continue
		for keep in keeps:
			if keep.global_position.distance_to(house.global_position) <= keep.rules.construction_radius: total += house_room; break
	return total
static func used(tree: SceneTree, team: String) -> int:
	var total := 0
	for unit in tree.get_nodes_in_group("units"):
		if unit.team == team and unit.health > 0 and unit.get("unit_stats") != null: total += cost.get(unit.unit_stats.unit_id,0)
	for keep in tree.get_nodes_in_group("keeps"):
		if keep.team != team: continue
		for kind in keep.pending: total += cost.get(StringName(kind),0)
	for building in tree.get_nodes_in_group("production_buildings"):
		if building.team != team: continue
		for scene in building.pending: total += cost.get(building.unit_stats_for(scene).unit_id,0)
	return total
static func room(tree: SceneTree, team: String, id: StringName) -> bool:
	return not enabled or used(tree,team)+cost.get(id,0) <= cap(tree,team)
