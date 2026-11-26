class_name EngineeringWork
extends RefCounted
## A vehicle: a unit that runs on fuel (Tank, Derailer, Drone, Ubermech, trucks and trains). Infantry and other
## people have no fuel rules. Infantry repair vehicles as they do buildings (docs/VEHICLE_REPAIR.md).
static func is_vehicle(node: Node) -> bool:
	return is_instance_valid(node) and node.is_in_group("units") and node.get("fuel_rules") != null
## What `team` may repair: its own buildings and vehicles, and any mine.
static func repairable(target: Node, team: String) -> bool:
	if not is_instance_valid(target) or target.health <= 0: return false
	if target.is_in_group("selectable_buildings"): return target.team == team or target.is_in_group("mines")
	return is_vehicle(target) and target.team == team
## Whether `payer` is a Knights stockpile (a Keep or a pitched Hearth-Wain). It holds no energy, so it pays for a
## repair in Wood and Iron.
static func pays_wood(payer: Node) -> bool:
	return is_instance_valid(payer) and (payer.is_in_group("keeps") or payer.is_in_group("hearth_wains"))
static func payer_for(target: Node3D, team: String) -> Node3D:
	# A vehicle has no Depot of its own: the nearest stockpile whose range covers it.
	if is_vehicle(target):
		var covering := SupplySource.candidates(target.get_tree(),target.global_position,team)
		return covering[0] if not covering.is_empty() else null
	if target.is_in_group("depots"): return target if target.team == team else null
	if target.is_in_group("production_buildings") or target.is_in_group("energy_generators"):
		return target.assigned_depot if is_instance_valid(target.assigned_depot) and target.assigned_depot.team == team else null
	# A Farm, House or Railhead has no wallet of its own: the nearest friendly Keep or pitched Hearth-Wain covering it.
	if target.is_in_group("farms") or target.is_in_group("houses") or target.is_in_group("railheads"):
		for node in SupplySource.candidates(target.get_tree(),target.global_position,team):
			if pays_wood(node): return node
		return null
	# Mines have no fixed production wallet: latch the nearest covering friendly Depot once.
	var nearest: Node3D
	var distance := INF
	for depot in target.get_tree().get_nodes_in_group("depots"):
		var d: float = depot.global_position.distance_to(target.global_position)
		if depot.team == team and depot.health > 0 and d <= depot.rules.construction_radius and d < distance: nearest = depot; distance = d
	return nearest
static func tick(unit: Node3D, target: Node3D, payer: Node3D) -> bool:
	if target == unit or not repairable(target,unit.team) or target.health >= target.max_health: return false
	if not SupplySource.available(payer,unit.team): return false
	# A vehicle is paid for by a stockpile whose range covers both the repairer and the vehicle.
	if payer.is_in_group("mobile_supplies") or is_vehicle(target):
		if not SupplySource.covers(payer,unit.global_position,unit.team) or not SupplySource.covers(payer,target.global_position,unit.team): return false
	else:
		if target.is_in_group("depots") and payer != target: return false
		if (target.is_in_group("production_buildings") or target.is_in_group("energy_generators")) and payer != target.assigned_depot: return false
		if target.is_in_group("mines") and payer.global_position.distance_to(target.global_position) > payer.rules.construction_radius: return false
	if unit.global_position.distance_to(target.global_position) > unit.engineering_rules.repair_range: return false
	var amount: int = mini(unit.engineering_rules.repair_hp,target.max_health-target.health)
	if amount <= 0: return false
	var rules: EngineeringRules = unit.engineering_rules
	var paid: bool = payer.spend_resources({&"wood": rules.repair_wood, &"iron": rules.repair_iron}) if pays_wood(payer) else payer.spend_local(rules.repair_energy,rules.repair_iron)
	if not paid: return false
	target.health += amount
	return true
