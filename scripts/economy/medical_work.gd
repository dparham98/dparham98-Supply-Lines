class_name MedicalWork
extends RefCounted
## Grail Sentinel field medicine (Vitality Stimulus): heals friendly non-vehicle units using
## local Keep Food when covered, or a finite carried medical reserve (no free regeneration).

static func can_heal(target: Node, team: String) -> bool:
	return is_instance_valid(target) and not target.is_queued_for_deletion() and target.is_in_group("units") and target.get("team") == team and target.health > 0 and target.health < target.max_health and not EngineeringWork.is_vehicle(target)

static func food_payer(healer: Node3D, food_cost: int) -> Node3D:
	if food_cost <= 0 or not healer.is_inside_tree(): return null
	for source in SupplySource.candidates(healer.get_tree(), healer.global_position, healer.team):
		if source.stockpile.amount(&"food") >= food_cost:
			return source
	return null

## Performs one heal pulse. Returns "" when healing succeeded, or a status message when dry.
static func tick(healer: Node3D, target: Node3D) -> String:
	if not can_heal(target, healer.team): return "No valid patient"
	var payer := food_payer(healer, healer.heal_food_cost)
	if payer != null and payer.stockpile.withdraw(&"food", healer.heal_food_cost) == healer.heal_food_cost:
		target.health = mini(target.max_health, target.health + healer.heal_hp)
		target._update_display()
		return ""
	if healer.med_reserve > 0:
		var step := mini(healer.heal_hp, mini(healer.med_reserve, target.max_health - target.health))
		if step > 0:
			healer.med_reserve -= step
			target.health += step
			target._update_display()
			return ""
	return "Medical reserve empty · return to Keep or Food crate"

## Refills the Sentinel's carried medical reserve from a covering Keep or adjacent Food crate.
static func refill_tick(healer: Node3D, delta: float) -> void:
	if not healer.get("can_heal") or not healer.is_inside_tree(): return
	if healer.med_reserve >= healer.med_reserve_capacity or healer.order == "heal":
		healer._med_refill_timer = 0.0
		return
	healer._med_refill_timer += delta
	if healer._med_refill_timer < 1.0: return
	healer._med_refill_timer = 0.0
	var payer := food_payer(healer, 1)
	if payer != null and payer.stockpile.withdraw(&"food", 1) == 1:
		healer.med_reserve = mini(healer.med_reserve_capacity, healer.med_reserve + healer.heal_hp)
		return
	for crate in CrateYard.crates_near(healer.get_tree(), healer.global_position, 4.0, healer.team):
		if crate.resource_kind == &"food" and crate.extract(1, healer.team) == 1:
			healer.med_reserve = mini(healer.med_reserve_capacity, healer.med_reserve + healer.heal_hp)
			return
