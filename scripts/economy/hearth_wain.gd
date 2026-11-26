extends "res://scripts/economy/cargo_vehicle.gd"
## The Knights' Hearth-Wain (docs/ROUND3_HEARTH_WAIN.md): a barded draught-steed and wagon trained at the Dragon Yard.
## On the move it is a Cargo vehicle with a 100-unit hold (four crates of Food, Wood, Iron or Coal): it loads,
## unloads and runs routes between Keeps and other pitched Wains as a Cargo truck does, and burns no fuel.
## Pitched (Deploy, 2 s each way) it is a Knights supply source of `hearth_radius` (15 m), spending only from its
## hold: it pays plans in its range, and costs and Stoke Braziers for a Chapterhouse, Dragon Yard or Forge in it;
## workers drop off there; Farms may stand and work in its range (Forward Farms); and it refills Grail Sentinels
## within `hearth_medic_radius` from its Food (MedicalWork.refill_tick).
const RULES := preload("res://assets/economy/knights_rules.tres")
## A production building listens for this as it does on a Depot. A Wain is never captured, so it never fires: a
## building whose Wain packs up or dies picks another payer, keeping its queue.
signal ownership_changed
var food: int:
	get: return stockpile.amount(&"food")
func _ready() -> void:
	super._ready()
	add_to_group("hearth_wains")
	preload("res://scripts/components/team_paint.gd").apply(get_node_or_null("Visuals/Model"),team)
func supply_radius() -> float:
	return RULES.hearth_radius
## Whether it is pitched now: deployed, settled and standing still.
func pitched() -> bool:
	return supplies_available()
## Spends `costs` from its hold while pitched; false, spending nothing, when it is packed or short.
func spend_resources(costs: Dictionary) -> bool:
	if not pitched(): return false
	var due := {}
	for kind in costs:
		if costs[kind] > 0: due[kind] = costs[kind]
	return stockpile.spend(due)
## Food it can feed a Sentinel's reserve with: loose Food, then Food crates aboard.
func food_on_hand() -> int:
	return stockpile.amount(&"food")+crate_units(&"food")
## Takes `amount` Food, loose first, then from Food crates aboard; false, taking nothing, when it has less.
func take_food(amount: int) -> bool:
	if amount <= 0: return true
	if food_on_hand() < amount: return false
	var due := amount-stockpile.withdraw(&"food",mini(amount,stockpile.amount(&"food")))
	for crate in crates.duplicate():
		if due <= 0: break
		if crate.kind != &"food" or crate.amount <= 0: continue
		var used := mini(due,int(crate.amount))
		crate.amount -= used
		due -= used
		if crate.amount <= 0: crates.erase(crate)
	_sync_reserved()
	return true
func _update_display() -> void:
	super._update_display()
	$Status.text = "HEARTH-WAIN · %d/%d · %s" % [health,max_health,"Hearth pitched" if pitched() else state]
	$Cargo.text = "F %d / W %d / I %d / C %d" % [food,carried_wood,carried_iron,carried_coal]+(" · %d/%d crates" % [crates.size(),crate_slots()] if not crates.is_empty() else "")
