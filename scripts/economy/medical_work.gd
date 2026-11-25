class_name MedicalWork
extends RefCounted
## Grail Sentinel field medicine (Vitality Stimulus, docs/ARTHURIAN_KNIGHTS.md): heals friendly non-vehicle units from
## a carried medical reserve, one reserve point for one health. The reserve refills only inside a friendly Keep's range
## or beside a crate of the refill resource (`med_refill_kind`, Food), `med_refill_points` points for
## `med_refill_cost` of it. There is no free regeneration unless the refill cost is set to 0.

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
	if step <= 0: return "Medical reserve empty · return to Keep or Food crate"
	healer.med_reserve -= step
	target.health += step
	target._update_display()
	return ""

## Refills the Sentinel's carried reserve once every `med_refill_interval` seconds, healing or not: from a covering
## friendly Keep's stock (no other Depot), or from a crate of the refill resource within 4 m.
static func refill_tick(healer: Node3D, delta: float) -> void:
	if not healer.get("can_heal") or not healer.is_inside_tree(): return
	if healer.med_reserve >= healer.med_reserve_capacity:
		healer._med_refill_timer = 0.0
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
	for source in SupplySource.candidates(healer.get_tree(), healer.global_position, healer.team):
		if not source.is_in_group("keeps"): continue
		if source.stockpile.amount(kind) >= cost and source.stockpile.withdraw(kind, cost) == cost:
			healer.med_reserve += gain
			return
	for crate in CrateYard.crates_near(healer.get_tree(), healer.global_position, 4.0, healer.team):
		if crate.resource_kind == kind and crate.amount >= cost and crate.extract(cost, healer.team) == cost:
			healer.med_reserve += gain
			return
