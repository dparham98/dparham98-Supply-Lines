class_name MedicalWork
extends RefCounted
## Grail Sentinel field medicine (Vitality Stimulus, docs/ARTHURIAN_KNIGHTS.md): heals friendly non-vehicle units from
## a carried medical reserve, one reserve point for one health. Since Round 3 (docs/ROUND3_HEARTH_WAIN.md) a Keep
## never refills it. It refills on or beside a working Farm (the Living Draught), near a pitched Hearth-Wain from
## its Food, or beside a crate of the refill resource (`med_refill_kind`, Food), `med_refill_points` points for
## `med_refill_cost` of it. There is no free regeneration unless the refill cost is set to 0.
const KNIGHTS := preload("res://assets/economy/knights_rules.tres")

static func can_heal(target: Node, team: String) -> bool:
	return is_instance_valid(target) and not target.is_queued_for_deletion() and target.is_in_group("units") and target.get("team") == team and target.health > 0 and target.health < target.max_health and not EngineeringWork.is_vehicle(target)

## The most hurt friend (lowest share of its health) within the healer's heal range, or null.
static func most_hurt(healer: Node3D) -> Node3D:
	if not healer.is_inside_tree(): return null
	var best: Node3D = null
	var worst := 1.0
	for unit in healer.get_tree().get_nodes_in_group("units"):
		if unit == healer or not can_heal(unit,healer.team): continue
		if unit.global_position.distance_to(healer.global_position) > healer.heal_range: continue
		var share: float = float(unit.health)/unit.max_health
		if share < worst: worst = share; best = unit
	return best

## Performs one heal pulse from the carried reserve. Returns "" when healing succeeded, or a status message when dry.
static func tick(healer: Node3D, target: Node3D) -> String:
	if not can_heal(target, healer.team): return "No valid patient"
	var step := mini(healer.heal_hp, mini(healer.med_reserve, target.max_health - target.health))
	if step <= 0: return "Medical reserve empty · refill at a working Farm, Hearth-Wain or Food crate"
	healer.med_reserve -= step
	target.health += step
	target._update_display()
	return ""

## Where the Sentinel's reserve refills from now, as a word for its state: "farm", "hearth", "crate" or "".
static func refill_source(healer: Node3D) -> String:
	if draught_farm(healer) != null: return "farm"
	if hearth_for(healer) != null: return "hearth"
	return ""
## A working friendly Farm the Sentinel stands on or within `draught_reach` of, or null.
static func draught_farm(healer: Node3D) -> Node3D:
	for farm in healer.get_tree().get_nodes_in_group("farms"):
		if farm.get("team") != healer.team or not farm.has_method("provides_draught") or not farm.provides_draught(): continue
		if farm.distance_to_field(healer.global_position) <= KNIGHTS.draught_reach: return farm
	return null
## The nearest pitched friendly Hearth-Wain within `hearth_medic_radius` that still has Food, or null.
static func hearth_for(healer: Node3D) -> Node3D:
	var best: Node3D = null
	for wain in healer.get_tree().get_nodes_in_group("hearth_wains"):
		if wain.team != healer.team or not wain.pitched() or wain.food_on_hand() < KNIGHTS.hearth_medic_food: continue
		var distance: float = wain.global_position.distance_to(healer.global_position)
		if distance <= KNIGHTS.hearth_medic_radius and (best == null or distance < best.global_position.distance_to(healer.global_position)): best = wain
	return best
## Refills the Sentinel's carried reserve, healing or not, from the first of these it has:
## - a working Farm: `draught_points` every `draught_beat_seconds`, cutting the Farm's next payout;
## - a pitched Hearth-Wain: `hearth_medic_points` for `hearth_medic_food` of its Food, at `hearth_medic_rate` a second;
## - a crate of the refill resource within 4 m: `med_refill_points` for `med_refill_cost` every `med_refill_interval`.
static func refill_tick(healer: Node3D, delta: float) -> void:
	if not healer.get("can_heal") or not healer.is_inside_tree(): return
	if healer.med_reserve >= healer.med_reserve_capacity:
		healer._med_refill_timer = 0.0
		return
	var farm := draught_farm(healer)
	if farm != null:
		healer._med_refill_timer += delta
		if healer._med_refill_timer < KNIGHTS.draught_beat_seconds: return
		healer._med_refill_timer = 0.0
		healer.med_reserve = mini(healer.med_reserve_capacity,healer.med_reserve+KNIGHTS.draught_points)
		farm.provision(healer)
		return
	var wain := hearth_for(healer)
	if wain != null:
		healer._med_refill_timer += delta
		if healer._med_refill_timer < KNIGHTS.hearth_medic_points/KNIGHTS.hearth_medic_rate: return
		healer._med_refill_timer = 0.0
		if wain.take_food(KNIGHTS.hearth_medic_food): healer.med_reserve = mini(healer.med_reserve_capacity,healer.med_reserve+KNIGHTS.hearth_medic_points)
		return
	healer._med_refill_timer += delta
	if healer._med_refill_timer < healer.med_refill_interval: return
	healer._med_refill_timer = 0.0
	var gain: int = mini(healer.med_refill_points, healer.med_reserve_capacity - healer.med_reserve)
	var cost: int = healer.med_refill_cost
	var kind: StringName = healer.med_refill_kind
	if cost <= 0 or kind == &"":
		healer.med_reserve += gain
		return
	for crate in CrateYard.crates_near(healer.get_tree(), healer.global_position, 4.0, healer.team):
		if crate.resource_kind == kind and crate.amount >= cost and crate.extract(cost, healer.team) == cost:
			healer.med_reserve += gain
			return
