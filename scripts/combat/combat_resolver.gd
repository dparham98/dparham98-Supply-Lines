class_name CombatResolver
extends RefCounted
## Damage snapshots prevent duplicate hits when a mine belongs to multiple groups.
static func can_hit(attacker: Node3D, target: Node3D) -> bool:
	return is_instance_valid(target) and target != attacker and target.has_method("take_damage") and target.get("health") != null and target.health > 0 and target.get("team") != null and (target.is_in_group("mines") or (target.team != attacker.team and target.team != "neutral"))
static func is_heavy(target: Node3D) -> bool:
	return target.is_in_group("selectable_buildings") or (target.get("unit_stats") != null and target.unit_stats.unit_id == &"tank")
static func damage_for(attacker: Node3D, target: Node3D) -> int:
	var stats: UnitStats = attacker.unit_stats
	return stats.heavy_target_damage if stats != null and stats.heavy_target_damage >= 0 and is_heavy(target) else attacker.attack_damage
static func interval_for(attacker: Node3D, target: Node3D) -> float:
	var stats: UnitStats = attacker.unit_stats
	return stats.heavy_target_interval if stats != null and stats.heavy_target_interval > 0 and is_heavy(target) else attacker.shot_interval
static func targets(attacker: Node3D) -> Array[Node3D]:
	var result: Array[Node3D] = []
	for group in ["units","selectable_buildings"]:
		for node in attacker.get_tree().get_nodes_in_group(group):
			if can_hit(attacker,node) and node.team != "neutral" and not result.has(node): result.append(node)
	return result
static func strike(attacker: Node3D, primary: Node3D) -> void:
	var victims: Array[Node3D] = [primary]
	var radius: float = attacker.unit_stats.splash_radius if attacker.unit_stats != null else 0.0
	if radius > 0:
		for target in targets(attacker):
			if target != primary and target.global_position.distance_to(primary.global_position) <= radius: victims.append(target)
	for victim in victims:
		if can_hit(attacker,victim): victim.take_damage(damage_for(attacker,victim))
