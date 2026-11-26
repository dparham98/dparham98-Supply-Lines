class_name TroopCars
extends RefCounted
## Troop cars (docs/ROUND3_TROOP_TRAINS.md): foot soldiers and workers of either side ride a friendly train. Each takes
## a crate slot (`RailRules.passenger_space`, 25 of the train's 300), shared with its crates. They board a stopped
## train at a station: inside a friendly Depot's or Keep's loading area, or at a Forward Railhead. They get off there
## (Disembark), or are thrown out when it derails.

## Whether `unit` can ride a train at all: a living ground unit on foot, with no fuel, no armour and not a giant.
## Deforester, Scout, Grenadier, Forester Maiden, Farmer, Warhound, the Marines and the Grail Sentinel can.
static func eligible(unit: Node) -> bool:
	if not is_instance_valid(unit) or not unit.is_in_group("units") or unit.get("health") == null or unit.health <= 0: return false
	if unit.is_in_group("rail_trains") or unit.get("is_cargo_vehicle") == true or unit.get("is_depot_truck") == true: return false
	if EngineeringWork.is_vehicle(unit) or unit.get("armoured") == true: return false
	var stats = unit.get("unit_stats")
	if stats == null or stats.giant: return false
	return unit.mobility_layer() == MobilityRules.Layer.GROUND
## Why `unit` can't board `train` now, or "".
static func refusal(unit: Node, train: Node) -> String:
	if not eligible(unit): return "Only foot soldiers and workers ride a train."
	if not is_instance_valid(train) or not train.is_in_group("rail_trains") or train.team != unit.team or train.health <= 0: return "Board a friendly train."
	return train.board_refusal()
