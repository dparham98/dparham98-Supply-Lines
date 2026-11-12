extends SceneTree
# Headless: mines and mine sites hide the baked ore rocks on and around their footprint (docs/IRON_MINE_MODEL.md).
# The skirmish's own mine covers its cells, a mine site covers its footprint until it is cancelled, a finished mine
# keeps them covered when its site goes, and a destroyed mine gives them back only once its wreck has sunk away.
# Whether the rocks really vanish on screen is for tests/ore_cover_runtime_check.gd.
var game: Node3D
var network: Node
var ground: Node3D
var ore_state: OreStateVisuals
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> bool:
	if ok: return true
	push_error(message); quit(1); return false
func site(near: Vector3) -> Vector3:
	var spec: Dictionary = network.plan_spec(&"iron_mine")
	var best := Vector3.INF
	for dz in range(-34,35):
		for dx in range(-34,35):
			var point: Vector3 = near+Vector3(dx,0,dz)
			if point.distance_to(near) >= best.distance_to(near): continue
			var start: Vector2i = network.footprint_start(point,spec.size)
			if network.plan_terrain_valid(start,spec.size,&"iron_mine") and not network.plan_overlaps(start,spec.size) and network.can_place_mine(point,game.depot): best = point
	return best
func covered(cells: Array) -> bool:
	for cell in cells:
		if not ground.ore_covered.has(cell): return false
	return true
func footprint(plan: Node3D) -> Array:
	var cells := []
	for z in range(plan.start.y,plan.start.y+plan.spec.size.y):
		for x in range(plan.start.x,plan.start.x+plan.spec.size.x): cells.append(Vector2i(x,z))
	return cells
func run() -> void:
	game = load("res://scenes/maps/resource_skirmish.tscn").instantiate()
	root.add_child(game)
	for i in range(3): await process_frame
	network = game.get_node("DepotNetwork")
	ground = game.ground
	ore_state = game.get_node("Terrain").ore_state
	game.set_process(false)
	for unit in get_nodes_in_group("units"): unit.set_process(false)
	for depot in get_nodes_in_group("depots"): depot.set_process(false)
	var depot = game.depot
	depot.storage_capacity = 10000
	depot.energy = 2000; depot.iron = 2000
	if not check(ore_state != null and not ore_state.batches.is_empty(),"The ore rock batches should be bound"): return
	# The skirmish's own mine covers its footprint and the cells round it, and rocks stood there.
	var start_mine: Node3D = game.get_node("Entities/Buildings/IronMine")
	if not check(covered(start_mine.cells),"The starting mine should cover its ore rocks"): return
	var corner: Vector2i = start_mine.cells[0]-Vector2i.ONE
	if not check(ground.ore_covered.has(corner),"The cover should reach a cell beyond the footprint"): return
	var at_start: int = ore_state.hidden_count()
	if not check(at_start > 0,"The starting mine stands on ore rocks, so some should be hidden"): return
	var cells_at_start: int = ground.ore_covered.size()
	# A mine site covers its footprint; cancelling it gives the rocks back.
	var point := site(depot.global_position)
	if not check(point != Vector3.INF,"No mine site near the Depot"): return
	var plan = network.queue_plan(point,&"iron_mine")
	if not check(plan != null,"Mine plan not placed"): return
	plan.set_process(false)
	var cells := footprint(plan)
	if not check(covered(cells) and ore_state.hidden_count() > at_start,"A mine site should hide the ore rocks on its footprint"): return
	plan.cancel()
	await process_frame
	if not check(ground.ore_covered.size() == cells_at_start and ore_state.hidden_count() == at_start,"A cancelled site should give its rocks back"): return
	# A finished mine keeps them hidden after its site is gone.
	plan = network.queue_plan(point,&"iron_mine")
	plan.set_process(false)
	var mine: Node3D = plan.complete_from_stock()
	if not check(mine != null,"Mine plan did not complete"): return
	mine.set_process(false)
	await process_frame
	if not check(not is_instance_valid(plan),"The site should be gone"): return
	if not check(covered(mine.cells) and ore_state.hidden_count() > at_start,"A finished mine should keep its rocks hidden"): return
	var with_mine: int = ore_state.hidden_count()
	# Destroyed: still hidden while the wreck plays, back once it has sunk away.
	var model: Node3D = mine.get_node("Visuals/Model")
	mine.take_damage(mine.max_health)
	await process_frame
	if not check(not is_instance_valid(mine) and is_instance_valid(model),"The mine should be gone and its wreck left"): return
	if not check(ore_state.hidden_count() == with_mine,"Rocks should stay hidden under the wreck"): return
	model.player.advance(model.player.get_animation(&"Die").length+0.1)
	await process_frame
	await process_frame
	if not check(not is_instance_valid(model),"The wreck should remove itself"): return
	if not check(ground.ore_covered.size() == cells_at_start and ore_state.hidden_count() == at_start,"The rocks should come back once the wreck is gone"): return
	if not check(covered(start_mine.cells),"The starting mine's rocks should stay hidden throughout"): return
	print("ORE_COVER_TEST_PASSED")
	quit(0)
