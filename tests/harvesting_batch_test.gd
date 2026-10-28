extends SceneTree
var game: Node3D
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> bool:
	if value: return true
	push_error(message); quit(1); return false
func run() -> void:
	game = load("res://scenes/maps/harvesting_exercise.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	for group in ["units","depots","mines"]:
		for node in get_nodes_in_group(group): node.set_process(false)
	var ground = game.ground
	var network = game.get_node("DepotNetwork")
	var payer = game.depot
	var bare = game.get_node("Entities/Resources/OreDeposit")
	if not check(not bare.can_extract("player") and bare.extract(10,"player") == 0,"Bare deposit paid iron without mine"): return
	var point := Vector3(150,0,154)
	network.select_depot(payer)
	var energy: int = payer.energy
	var iron: int = payer.iron
	if not check(not network.construct_mine(payer.global_position+Vector3(12,0,12)) and payer.energy == energy and payer.iron == iron,"Mine built/charged on non-deposit terrain"): return
	if not check(network.can_place_mine(point,payer) and network.construct_mine(point) and payer.energy == energy-75 and payer.iron == iron-25,"Mine placement or local costs failed"): return
	var mine = get_nodes_in_group("mines")[-1]
	if not check(not mine.is_in_group("capturable_buildings") and mine.remaining == 1000,"Mine still capturable or wrong reserves"): return
	if not check(not network.construct_mine(point) and payer.iron == iron-25,"Overlapping mine double charged"): return
	if not check(mine.extract(10,"player") == 10 and mine.extract(15,"enemy") == 15 and mine.remaining == 975,"Shared extraction failed conservation"): return
	var footprint: Array[Vector2i] = mine.cells.duplicate()
	mine.take_damage(100)
	var worker = game.get_node("Entities/Units/Infantry")
	worker._stop_route()
	worker.global_position = mine.global_position+Vector3(4,0,0)
	worker.command_repair(mine,payer)
	worker._repair(worker.engineering_rules.repair_interval)
	if not check(mine.health == 910 and payer.energy == energy-77 and payer.iron == iron-26,"Friendly Infantry could not pay to repair shared mine"): return
	var enemy = load("res://scenes/gameplay/infantry.tscn").instantiate()
	enemy.team = "enemy"; enemy.position = mine.global_position+Vector3(4,0,1)
	game.add_child(enemy); enemy.set_process(false)
	payer.team = "enemy"
	enemy.command_repair(mine,payer)
	enemy._repair(enemy.engineering_rules.repair_interval)
	if not check(mine.health == 920 and payer.energy == energy-79 and payer.iron == iron-27,"Opposing Infantry could not repair shared mine"): return
	payer.team = "player"; enemy.free()
	if not check(CombatResolver.can_hit(worker,mine),"Shared mine cannot be explicitly attacked"): return
	mine.take_damage(mine.health)
	if not check(mine.extract(10,"player") == 0,"Destroyed mine paid iron"): return
	await process_frame
	for cell in footprint:
		if not check(not ground.iron_mines.has(cell) and ground.tiles[cell.y*500+cell.x].occupied_by == null and not ground.is_tile_valid(cell),"Mine removal damaged ore terrain/registration"): return
	network.select_depot(payer)
	if not check(network.construct_mine(point),"Mine rebuild rejected remaining deposit"): return
	mine = get_nodes_in_group("mines")[-1]
	if not check(mine.remaining == 975 and mine.extract(2000,"enemy") == 975 and mine.extract(10,"player") == 0,"Mine rebuild refilled or overpaid deposit"): return
	mine.take_damage(mine.health)
	await process_frame
	if not check(not network.can_place_mine(point,payer),"Exhausted footprint became a fresh mine"): return
	# Two users share exactly the same forest resource and clear only on depletion.
	var cell := Vector2i(346,275)
	var a = ground.forest_source(cell)
	var b = ground.forest_source(cell)
	if not check(a == b and a.remaining == 20 and a.extract(5,"player") == 5 and b.extract(5,"enemy") == 5 and ground.get_terrain(cell) == 3,"Forest sharing or partial harvest failed"): return
	if not check(a.extract(100,"player") == 10 and b.extract(5,"enemy") == 0 and ground.get_terrain(cell) == 0 and ground.can_traverse(cell) and ground.cleared_forest.has(cell),"Forest depletion failed conservation/navigation clearing"): return
	var tank_cell := Vector2i(345,275)
	var lost = ground.forest_source(tank_cell)
	if not check(lost.remaining == 20 and ground.clear_forest(tank_cell) and lost.remaining == 0 and lost.extract(20,"player") == 0,"Destructive clearing recovered wood"): return
	# A real engineer completes two trips and depletes an ordinary forest tile.
	worker = game.get_node("Entities/Units/ForestInfantry")
	var forest_depot = game.get_node("Entities/Buildings/ForestDepot")
	var harvest_cell := Vector2i(344,276)
	var source = ground.forest_source(harvest_cell)
	worker.command_gather(source)
	for i in range(12000):
		worker._process(1.0/60)
		if source.remaining == 0 and worker.cargo == 0: break
	if not check(forest_depot.wood == 20 and game.wood_delivered == 20 and source.remaining == 0 and ground.get_terrain(harvest_cell) == 0,"Infantry forest harvest/return did not deliver all 20 wood"): return
	print("HARVESTING_BATCH_CHECKS_PASSED")
	quit()
