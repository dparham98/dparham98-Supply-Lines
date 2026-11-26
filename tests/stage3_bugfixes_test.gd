extends SceneTree
# Headless (item 1 of the Round 3 handoff; docs/VEHICLE_REPAIR.md, docs/BASTION_TANK.md, docs/MELEE_PURSUIT.md):
# - A Forester Maiden repairs a damaged Keep, Farm and House, each tick 1 Wood and 1 Iron from the Keep, which holds
#   no energy.
# - The Bastion's roof gun deals 3 before armour with Vehicle Weapons I, 4 with II; Mail III takes that to 1, Mail II
#   to 2.
# - A Warhound ordered to attack a Scout fleeing at 8 m/s lands its bites on the move and kills it within 10 s.
var game: Node3D
var network: Node
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> bool:
	if value: return true
	push_error(message); quit(1); return false
func open(path: String) -> void:
	if is_instance_valid(game):
		game.queue_free()
		await process_frame
	game = load(path).instantiate()
	root.add_child(game)
	for frame in range(3): await process_frame
	network = game.get_node("DepotNetwork")
	game.set_process(false)
	game.get_node("Interface").set_process(false)
	var ai = game.get_node_or_null("EnemyPlayer")
	if ai != null: ai.set_process(false)
	for group in ["units","depots","production_buildings","farms","houses","energy_generators","mines"]:
		for node in get_nodes_in_group(group): node.set_process(false)
func spawn(id: String, point: Vector3, team := "player") -> Node3D:
	var unit = load("res://scenes/gameplay/"+id+".tscn").instantiate()
	unit.team = team
	game.get_node("Entities/Units").add_child(unit)
	unit.set_process(false)
	unit._stop_route()
	for cell in unit._claimed.duplicate(): unit._release(cell)
	unit.grid_position = game.ground.nearest_actor_cell(game.ground.get_tile_at_position(point),unit.mobility_layer(),unit._owner_key())
	unit.global_position = game.ground.tile_to_world(unit.grid_position)
	unit._claim(unit.grid_position)
	return unit
func step(nodes: Array, seconds: float, until := Callable()) -> float:
	var frames := ceili(seconds*60)
	for i in range(frames):
		for node in nodes:
			if is_instance_valid(node): node._process(1.0/60)
		if until.is_valid() and until.call(): return (i+1)/60.0
	return seconds
## A plan finished at once from its materials, as the playtest tools do.
func stand(kind: StringName, point: Vector3, team := "player") -> Node3D:
	var plan = network.queue_plan(point,kind,null,false,false,team)
	if plan == null: return null
	var building = network.finish_plan(plan)
	plan.queue_free()
	return building
func run() -> void:
	if not await repairs(): return
	if not await roof_gun(): return
	if not await pursuit(): return
	print("STAGE3_BUGFIXES_TEST_PASSED")
	quit()
func repairs() -> bool:
	await open("res://scenes/maps/arthurian_skirmish.tscn")
	var rules: EngineeringRules = load("res://assets/economy/engineering_rules.tres")
	var keep = game.get_node("Entities/Buildings/Keep")
	keep.stockpile.deposit(&"wood",400)
	keep.stockpile.deposit(&"iron",400)
	var farm: Node3D = null
	var house: Node3D = null
	for offset in [Vector3(0,0,14),Vector3(0,0,-14),Vector3(14,0,0),Vector3(-14,0,0)]:
		if farm == null: farm = stand(&"farm",keep.global_position+offset)
		elif house == null: house = stand(&"house",keep.global_position+offset)
	if not check(farm != null and house != null,"A Farm and a House should stand by the Keep"): return false
	for node in [farm,house]: node.set_process(false)
	var maiden = spawn("forester_maiden",keep.global_position+Vector3(8,0,8))
	for target in [keep,farm,house]:
		if not check(EngineeringWork.payer_for(target,"player") == keep,"%s should be repaired from the Keep" % target.name): return false
		target.health = target.max_health-30
		var wood: int = keep.wood
		var iron: int = keep.iron
		maiden.command_repair(target)
		if not check(maiden.order == "repair" and maiden.repair_payer == keep,"The Forester should repair %s from the Keep: %s, payer %s" % [target.name,maiden.order,maiden.repair_payer]): return false
		step([maiden],30.0,func(): return target.health >= target.max_health)
		if not check(target.health == target.max_health,"%s should be repaired by the Forester: %d / %d, '%s'" % [target.name,target.health,target.max_health,maiden.state]): return false
		var ticks := ceili(30.0/rules.repair_hp)
		if not check(wood-keep.wood == ticks*rules.repair_wood and iron-keep.iron == ticks*rules.repair_iron and keep.energy == 0,"Repairing %s should cost %d W and %d I, not %d W and %d I" % [target.name,ticks*rules.repair_wood,ticks*rules.repair_iron,wood-keep.wood,iron-keep.iron]): return false
	# No Wood, no repair.
	keep.stockpile.spend({&"wood":keep.wood})
	house.health = house.max_health-30
	maiden.command_repair(house)
	step([maiden],5.0)
	if not check(house.health == house.max_health-30 and maiden.state.contains("funds"),"Without Wood the repair should wait: %d, '%s'" % [house.health,maiden.state]): return false
	return true
func roof_gun() -> bool:
	await open("res://scenes/maps/resource_skirmish.tscn")
	var tank = spawn("tank",game.depot.global_position+Vector3(14,0,14))
	var gun = tank.get_node("CloseDefense")
	if not check(gun.shot_damage() == 3,"The roof gun should deal 3 with no upgrades, not %d" % gun.shot_damage()): return false
	Research.complete(game,"player",&"vehicle_weapons_1")
	if not check(gun.shot_damage() == 3,"With Vehicle Weapons I the roof gun should deal 3, not %d" % gun.shot_damage()): return false
	Research.complete(game,"player",&"vehicle_weapons_2")
	if not check(gun.shot_damage() == 4,"With Vehicle Weapons II the roof gun should deal 4, not %d" % gun.shot_damage()): return false
	var marine = spawn("round_table_marine",game.depot.global_position+Vector3(20,0,20),"enemy")
	Research.complete(game,"enemy",&"mail_1")
	Research.complete(game,"enemy",&"mail_2")
	if not check(Upgrades.after_armour(marine,gun.shot_damage()) == 2,"Mail II should take the roof gun's 4 to 2"): return false
	Research.complete(game,"enemy",&"mail_3")
	if not check(Upgrades.after_armour(marine,gun.shot_damage()) == 1,"Mail III should take the roof gun's 4 to 1"): return false
	return true
func pursuit() -> bool:
	await open("res://scenes/maps/resource_skirmish.tscn")
	var stats: UnitStats = load("res://assets/units/warhound.tres")
	if not check(stats.fire_while_moving,"The Warhound should fire on the move"): return false
	# Open ground west of the Depot: the Scout runs 60 m west, the Warhound 3 m behind it.
	var start: Vector3 = game.depot.global_position+Vector3(-20,0,0)
	var hound = spawn("warhound",start)
	var scout = spawn("scout",start+Vector3(-3,0,0),"enemy")
	scout._attack_enabled = false
	scout.command_move(start+Vector3(-60,0,0))
	scout._process(1.0/60)
	if not check(scout.is_moving(),"The Scout should be running: '%s'" % scout.state): return false
	hound.command_attack(scout)
	var dead := func(): return not is_instance_valid(scout) or scout.health <= 0
	var seconds := step([hound,scout],10.0,dead)
	if not check(dead.call(),"The Warhound should kill the fleeing Scout within 10 s: Scout %s, hound '%s' %.1f m behind" % [str(scout.health) if is_instance_valid(scout) else "gone",hound.state,hound.global_position.distance_to(scout.global_position) if is_instance_valid(scout) else 0.0]): return false
	print("Warhound killed the fleeing Scout in %.1f s" % seconds)
	return true
