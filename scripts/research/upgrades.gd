class_name Upgrades
extends RefCounted
## Attack and armour upgrades (item 11 of the balance handoff, docs/UPGRADES.md). Each line has three levels,
## researched in order at a Foundry (Cyborgs) or a Forge (Knights), and holds for the whole side. Level n of a line
## is the research `<line>_<n>`.
## - Attack: each level adds 10% of a weapon's base damage, rounded, at least 1.
## - Armour: each level takes 1 off every hit the unit takes, never below 1.
const INFANTRY_WEAPONS := &"infantry_weapons"
const INFANTRY_ARMOUR := &"infantry_armour"
const VEHICLE_WEAPONS := &"vehicle_weapons"
const VEHICLE_ARMOUR := &"vehicle_armour"
const ARMS := &"arms"
const MAIL := &"mail"
const LEVELS := 3
## The research id of `level` of `line`.
static func research_id(line: StringName, level: int) -> StringName:
	return StringName("%s_%d" % [line,level])
## How many levels of `line` `team` has, counting up from 1.
static func level(from: Node, team: String, line: StringName) -> int:
	var done := 0
	for n in range(1,LEVELS+1):
		if not Research.has(from,team,research_id(line,n)): break
		done = n
	return done
## The Cyborg lines a unit falls under: vehicles (anything with fuel) or infantry. The Knights' Arms and Mail
## cover every Knights unit. A side only ever researches its own faction's lines, so the two add up safely.
static func attack_level(unit: Node) -> int:
	if not is_instance_valid(unit) or not unit.is_in_group("units"): return 0
	var team: String = unit.team
	var cyborg := VEHICLE_WEAPONS if EngineeringWork.is_vehicle(unit) else INFANTRY_WEAPONS
	return level(unit,team,cyborg)+level(unit,team,ARMS)
static func armour_level(unit: Node) -> int:
	if not is_instance_valid(unit) or not unit.is_in_group("units"): return 0
	var team: String = unit.team
	var cyborg := VEHICLE_ARMOUR if EngineeringWork.is_vehicle(unit) else INFANTRY_ARMOUR
	return level(unit,team,cyborg)+level(unit,team,MAIL)
## `base` damage from `attacker` with its attack upgrades.
static func with_attack(attacker: Node, base: int) -> int:
	var n := attack_level(attacker)
	if n <= 0 or base <= 0: return base
	return base+n*maxi(1,roundi(base*0.1))
## A hit of `amount` on `unit` after its armour upgrades.
static func after_armour(unit: Node, amount: int) -> int:
	var n := armour_level(unit)
	if n <= 0 or amount <= 0: return amount
	return maxi(1,amount-n)
