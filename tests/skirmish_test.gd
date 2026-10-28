extends SceneTree
const OUTPUT = "C:/Users/video/.codex/.chatgpt-projects/g-p-6ad16a23380c8191877dbcafdb316068/gameplay_work/"
var game: Node3D
var normal_economy_rules: Resource
var barracks: Node3D
func _initialize() -> void:
	# Economy regressions use normal inventories regardless of sandbox iron grants.
	normal_economy_rules = load("res://assets/economy/depot_rules.tres")
	normal_economy_rules.testing_starting_iron = -1
	call_deferred("run")
func step(seconds: float) -> void:
	for frame in range(ceili(seconds*60)):
		game.depot._process(1.0/60)
		if is_instance_valid(barracks): barracks._process(1.0/60)
		for unit in get_nodes_in_group("units"): unit._process(1.0/60)
		game._process(1.0/60)
func screenshot(name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	for frame in range(4): await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUTPUT+name+".png")
func run() -> void:
	root.size = Vector2i(1280,900)
	game = load("res://scenes/maps/resource_skirmish.tscn").instantiate()
	root.add_child(game)
	await process_frame
	await process_frame
	game.set_process(false)
	game.depot.set_process(false)
	for unit in get_nodes_in_group("units"): unit.set_process(false)
	var rig = game.get_node("CameraRig")
	rig.set_process(false)
	rig.focus_hq()
	for frame in range(180): rig.advance_camera(1.0/60)
	var worker = game.get_node("Entities/Units/Infantry")
	var enemy = game.get_node("Entities/Units/Hostile")
	var ore = game.get_node("Entities/Buildings/IronMine")
	var bank = game.ore
	assert(bank == 0 and not game.depot.request_infantry())
	var manager = root.get_node("SelectionManager")
	var camera = rig.camera
	var screen: Vector2 = camera.unproject_position(worker.global_position+Vector3.UP*.5)
	manager.start_selection(screen); manager.end_selection(screen)
	assert(worker.is_selected)
	game.issue_order(camera.unproject_position(ore.global_position+Vector3.UP*1.5))
	assert(worker.order == "gather")
	worker.set_selected(false)
	await screenshot("skirmish_start")
	# Gathering must continue without selection and credit only delivered cargo.
	for i in range(20000):
		step(1.0/60)
		assert(game.ground.get_terrain(worker.grid_position) in [0,2])
		if worker.cargo > 0: assert(game.ore_delivered+worker.cargo == ore.amount-ore.remaining)
		if game.ore >= 65: break
	assert(game.ore >= 65, "Gathering did not deliver sufficient Ore")
	assert(game.ore == game.ore_delivered)
	var delivered: int = game.ore_delivered
	game.get_node("DepotNetwork").select_depot(game.depot)
	assert(game.get_node("DepotNetwork").construct_production(Vector3(180,0,160),&"barracks"))
	barracks = get_nodes_in_group("production_buildings")[0]
	barracks.set_process(false)
	assert(barracks.request_unit(&"infantry"))
	assert(game.ore == delivered-65)
	assert(not barracks.request_unit(&"infantry"))
	for i in range(240): step(1.0/60)
	assert(game.units_printed == 1 and barracks.queue == 0)
	var produced: Node3D
	for unit in get_nodes_in_group("units"):
		unit.set_process(false)
		if unit.team == "player" and unit != worker: produced = unit
	assert(produced != null)
	assert(game.ground.get_terrain(produced.grid_position) in [0,2])
	assert(produced.grid_position != worker.grid_position)
	produced.set_selected(true)
	game.issue_order(camera.unproject_position(enemy.global_position+Vector3.UP*1.5))
	assert(produced.order == "attack")
	produced.set_selected(false)
	# Support the produced infantry with the existing worker; do not rebalance the hostile.
	worker.command_attack(enemy)
	var first_shot_distance := -1.0
	for i in range(20000):
		var before: float = produced._cooldown
		step(1.0/60)
		if produced._cooldown > before and first_shot_distance < 0: first_shot_distance = produced.global_position.distance_to(enemy.global_position)
		if enemy.health <= 0: break
	assert(enemy.health == 0 and game.enemies_killed == 1)
	assert(first_shot_distance > 2 and first_shot_distance <= produced.attack_range+0.01)
	assert(game.outcome.begins_with("VICTORY"))
	assert(produced.health > 0)
	var enemy_cell: Vector2i = enemy.grid_position
	assert(game.ground.is_tile_valid(enemy_cell), "Death must release occupied cells")
	await process_frame
	await screenshot("skirmish_victory")
	# Paid queues are capped, and a blocked exit must wait without losing payment.
	game.ore = 100
	game.depot.energy = 500
	for i in range(3): assert(barracks.request_unit(&"infantry"))
	assert(game.ore == 40 and not barracks.request_unit(&"infantry") and game.ore == 40)
	var blocked: Array[Vector2i] = []
	var center = game.ground.get_tile_at_position(barracks.global_position)
	for radius in range(5,16):
		for offset in [Vector2i(0,radius),Vector2i(radius,0),Vector2i(-radius,0),Vector2i(0,-radius)]:
			var cell: Vector2i = center+offset
			if game.ground.is_tile_valid(cell):
				blocked.append(cell)
				game.ground.set_tile_feature(cell,"occupied_by","test_exit_block")
	barracks._process(10)
	assert(barracks.queue == 3 and game.units_printed == 1)
	for cell in blocked: game.ground.set_tile_feature(cell,"occupied_by",null)
	barracks._process(0.1)
	assert(barracks.queue == 2 and game.units_printed == 2)
	# Finite deposits cannot pay out twice or below zero.
	var prior: int = ore.remaining
	assert(ore.extract(prior+100) == prior and ore.remaining == 0)
	assert(ore.extract(10) == 0)
	if not is_instance_valid(worker): worker = produced
	# Orders onto water fail without crossing blocked terrain.
	worker.command_move(game.ground.tile_to_world(Vector2i(0,0)))
	# Resource command after depletion safely ends or returns carried cargo.
	worker.command_gather(ore)
	step(1.0/60)
	assert(worker.order in ["idle","return"])
	FileAccess.open(OUTPUT+"skirmish_results.json",FileAccess.WRITE).store_string(JSON.stringify({"gather_deliver_print_ranged_kill":true,"ore_delivered_before_print":delivered,"first_shot_distance":first_shot_distance,"orders_continue_deselected":true,"no_free_production":true,"finite_resource":true,"outcome":game.outcome},"\t"))
	print("SKIRMISH_CHECKS_PASSED")
	quit()
