class_name CombatResolver
extends RefCounted
## Damage snapshots prevent duplicate hits when a mine belongs to multiple groups.
static func can_hit(attacker: Node3D, target: Node3D) -> bool:
	return is_instance_valid(target) and target != attacker and target.has_method("take_damage") and target.get("health") != null and target.health > 0 and target.get("team") != null and (target.is_in_group("mines") or (target.team != attacker.team and target.team != "neutral"))
## Forced fire (the Attack command on a friendly): anything alive that takes damage, whatever its team.
static func can_force(attacker: Node3D, target: Node3D) -> bool:
	return is_instance_valid(target) and target != attacker and target.has_method("take_damage") and target.get("health") != null and target.health > 0
static func can_attack(attacker: Node3D, target: Node3D, forced := false) -> bool:
	return can_force(attacker,target) if forced else can_hit(attacker,target)
## Target classes (item 8 of the balance handoff), as flags so a weapon can list the ones it fires at.
const LIGHT := 1
const ARMOURED := 2
const FLYER := 4
const BUILDING := 8
## A building; else an armoured unit (its `armoured` flag); else a flyer (the air layer); else light.
static func target_class(target: Node3D) -> int:
	if target.is_in_group("selectable_buildings"): return BUILDING
	if target.get("armoured") == true: return ARMOURED
	if target.has_method("mobility_layer") and target.mobility_layer() == MobilityRules.Layer.AIR: return FLYER
	return LIGHT
static func is_heavy(target: Node3D) -> bool:
	return target_class(target) in [ARMOURED,BUILDING]
## The weapon `attacker` is resolving a shot with: 0 the main weapon, 1 the second (unit_agent.firing_weapon).
static func _weapon_of(attacker: Node3D, weapon: int) -> int:
	if weapon >= 0: return weapon
	var firing = attacker.get("firing_weapon")
	return firing if firing != null else 0
static func damage_for(attacker: Node3D, target: Node3D, weapon := -1) -> int:
	var stats: UnitStats = attacker.unit_stats
	if stats != null and _weapon_of(attacker,weapon) == 1: return stats.second_damage
	return stats.heavy_target_damage if stats != null and stats.heavy_target_damage >= 0 and is_heavy(target) else attacker.attack_damage
static func interval_for(attacker: Node3D, target: Node3D, weapon := -1) -> float:
	var stats: UnitStats = attacker.unit_stats
	if stats != null and _weapon_of(attacker,weapon) == 1: return stats.second_interval
	return stats.heavy_target_interval if stats != null and stats.heavy_target_interval > 0 and is_heavy(target) else attacker.shot_interval
static func targets(attacker: Node3D) -> Array[Node3D]:
	var result: Array[Node3D] = []
	for group in ["units","selectable_buildings"]:
		for node in attacker.get_tree().get_nodes_in_group(group):
			if can_hit(attacker,node) and node.team != "neutral" and not result.has(node): result.append(node)
	return result
## A forced strike hurts its friendly primary target; splash still spares friendlies.
static func strike(attacker: Node3D, primary: Node3D, forced := false) -> void:
	var victims: Array[Node3D] = [primary]
	var radius: float = attacker.unit_stats.splash_radius if attacker.unit_stats != null else 0.0
	if radius > 0:
		for target in targets(attacker):
			if target != primary and target.global_position.distance_to(primary.global_position) <= radius: victims.append(target)
	for victim in victims:
		if can_hit(attacker,victim) or (forced and victim == primary and can_force(attacker,victim)): victim.take_damage(splash_damage(attacker,victim,primary))
## Damage to `victim`: the full hit for the target aimed at, the attacker's splash share of it for other units.
static func splash_damage(attacker: Node3D, victim: Node3D, primary) -> int:
	# Attack upgrades add to the weapon's base damage (docs/UPGRADES.md).
	var damage := Upgrades.with_attack(attacker,damage_for(attacker,victim))
	if victim == primary or not victim.is_in_group("units") or attacker.unit_stats == null: return damage
	return roundi(damage*attacker.unit_stats.splash_share)
## A shell or grenade bursting at `point`: the target it was fired at, when still there (`primary`, may be null),
## and every hostile within the splash radius of the burst, measured across the ground. Friendlies are spared.
static func strike_at(attacker: Node3D, primary, point: Vector3, forced := false) -> void:
	var victims: Array[Node3D] = []
	if is_instance_valid(primary): victims.append(primary)
	var radius: float = attacker.unit_stats.splash_radius if attacker.unit_stats != null else 0.0
	if radius > 0:
		for target in targets(attacker):
			if target != primary and Vector2(target.global_position.x-point.x,target.global_position.z-point.z).length() <= radius: victims.append(target)
	for victim in victims:
		if can_hit(attacker,victim) or (forced and victim == primary and can_force(attacker,victim)): victim.take_damage(splash_damage(attacker,victim,primary))
