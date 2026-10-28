class_name EngineeringWork
extends RefCounted
static func payer_for(target: Node3D, team: String) -> Node3D:
	if target.is_in_group("depots"): return target if target.team == team else null
	if target.is_in_group("production_buildings") or target.is_in_group("energy_generators"):
		return target.assigned_depot if is_instance_valid(target.assigned_depot) and target.assigned_depot.team == team else null
	# Mines have no fixed production wallet: latch the nearest covering friendly Depot once.
	var nearest: Node3D
	var distance := INF
	for depot in target.get_tree().get_nodes_in_group("depots"):
		var d: float = depot.global_position.distance_to(target.global_position)
		if depot.team == team and depot.health > 0 and d <= depot.rules.construction_radius and d < distance: nearest = depot; distance = d
	return nearest
static func tick(unit: Node3D, target: Node3D, payer: Node3D) -> bool:
	if not is_instance_valid(target) or not target.is_in_group("selectable_buildings") or (target.team != unit.team and not target.is_in_group("mines")) or target.health <= 0 or target.health >= target.max_health: return false
	if not SupplySource.available(payer,unit.team): return false
	if payer.is_in_group("mobile_supplies"):
		if not SupplySource.covers(payer,unit.global_position,unit.team) or not SupplySource.covers(payer,target.global_position,unit.team): return false
	else:
		if target.is_in_group("depots") and payer != target: return false
		if (target.is_in_group("production_buildings") or target.is_in_group("energy_generators")) and payer != target.assigned_depot: return false
		if target.is_in_group("mines") and payer.global_position.distance_to(target.global_position) > payer.rules.construction_radius: return false
	if unit.global_position.distance_to(target.global_position) > unit.engineering_rules.repair_range: return false
	var amount: int = mini(unit.engineering_rules.repair_hp,target.max_health-target.health)
	if amount <= 0 or not payer.spend_local(unit.engineering_rules.repair_energy,unit.engineering_rules.repair_iron): return false
	target.health += amount
	return true
