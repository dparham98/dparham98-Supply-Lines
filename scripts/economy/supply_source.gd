class_name SupplySource
extends RefCounted
static func available(node, team: String) -> bool:
	if not is_instance_valid(node) or node.is_queued_for_deletion(): return false
	if not node.is_in_group("depots") and not node.is_in_group("mobile_supplies"): return false
	if node.health <= 0 or node.team != team: return false
	return node.is_in_group("depots") or (node.is_in_group("mobile_supplies") and node.supplies_available())
static func radius(node: Node3D) -> float:
	return node.rules.construction_radius if node.is_in_group("depots") else node.mobile_rules.supply_radius()
static func covers(node, point: Vector3, team: String) -> bool:
	return available(node,team) and node.global_position.distance_to(point) <= radius(node)
static func candidates(tree: SceneTree, point: Vector3, team: String) -> Array[Node3D]:
	var result: Array[Node3D] = []
	for group in ["depots","mobile_supplies"]:
		for node in tree.get_nodes_in_group(group):
			if covers(node,point,team): result.append(node)
	result.sort_custom(func(a,b):
		var da: float = a.global_position.distance_squared_to(point)
		var db: float = b.global_position.distance_squared_to(point)
		return a.get_instance_id() < b.get_instance_id() if is_equal_approx(da,db) else da < db)
	return result
static func can_receive(node, team: String) -> bool: return available(node,team)
