extends SceneTree
var game: Node3D
var ground: Node3D
func _initialize() -> void: call_deferred("run")
func check(value: bool, text: String) -> bool:
	if value: return true
	push_error(text); quit(1); return false
func spawn(id: String, cell: Vector2i) -> Node3D:
	var unit = load("res://scenes/gameplay/"+id+".tscn").instantiate()
	unit.position = ground.tile_to_world(cell)
	game.add_child(unit)
	unit.set_process(false)
	return unit
func relocate(unit: Node3D, cell: Vector2i) -> void:
	unit._stop_route()
	for prior in unit._claimed.duplicate(): unit._release(prior)
	unit.global_position = ground.tile_to_world(cell)
	unit.grid_position = cell
	unit._claim(cell)
func run() -> void:
	game = load("res://scenes/maps/resource_skirmish.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	ground = game.ground
	for group in ["units","selectable_buildings"]:
		for node in get_nodes_in_group(group): node.set_process(false)
	var origin := Vector2i(350,275)
	var destination := Vector2i(340,275)
	if not check(ground.get_terrain(destination) == 3,"Fixture needs original forest"): return
	var scout = spawn("scout",origin)
	if not check(not ground.is_tile_valid(destination) and ground.can_traverse(destination,1),"Forest traversal layer incorrect"): return
	if not check(scout._plan(destination),"Scout cannot plan into forest"): return
	scout.order = "move"; scout.move_goal = ground.tile_to_world(destination)
	for i in range(300): scout._process(1.0/60)
	if not check(scout.global_position.distance_to(scout.move_goal) < 0.01 and ground.get_terrain(destination) == 3 and ground.cleared_forest.is_empty(),"Scout movement altered forest or failed"): return
	if not check(not ground.is_tile_valid(destination),"Scout forest occupation became buildable"): return
	scout.free()
	var tank = spawn("tank",origin)
	if not check(tank._plan(destination) and ground.cleared_forest.is_empty(),"Tank planning must not clear forest"): return
	var planned: Array[Vector2i] = tank._route.duplicate()
	tank.order = "move"; tank.move_goal = ground.tile_to_world(destination)
	for i in range(300): tank._process(1.0/60)
	if not check(tank.global_position.distance_to(tank.move_goal) < 0.01 and ground.get_terrain(destination) == 0,"Tank did not cross/clear forest"): return
	var count: int = ground.cleared_forest.size()
	if not check(count > 0 and not ground.is_tile_valid(destination),"Clearing lost the occupying Tank reservation"): return
	for cell in ground.cleared_forest:
		if not check(planned.has(cell) and ground.terrain_cells[cell.y*500+cell.x] == 3,"Clearing affected unvisited or source cells"): return
	# The saved tree batches are duplicated per match; crossed-cell patch instances disappear.
	var visuals = game.get_node("Terrain").forest_state
	var patch := Vector2i(destination.x/2,destination.y/2)
	var hidden := 0
	for part in range(visuals.batches.size()):
		for index in visuals.indices[part].get(patch,[]):
			if not check(visuals.batches[part].multimesh.get_instance_transform(index).basis.determinant() == 0,"Cleared tree instance remains visible"): return
			hidden += 1
	if not check((hidden > 0 or DisplayServer.get_name() == "headless") and ground._clearing_mask.get_pixel(destination.x,destination.y).r == 1,"Forest visuals did not update"): return
	tank.free()
	if not check(ground.is_tile_valid(destination),"Cleared cell stayed blocked after Tank left"): return
	var infantry = spawn("infantry",origin)
	if not check(infantry._plan(destination),"Infantry cannot use cleared lane"): return
	infantry.free()
	# Air and ground may share a cell, but two Drones cannot reserve the same air cell.
	var worker = game.get_node("Entities/Units/Infantry")
	var occupied: Vector2i = worker.grid_position
	var owner = ground.tiles[occupied.y*500+occupied.x].occupied_by
	var drone = spawn("drone",occupied)
	if not check(drone.grid_position == occupied and ground.tiles[occupied.y*500+occupied.x].occupied_by == owner and ground.air_occupancy[occupied] == drone._owner_key(),"Air/ground layers interfere"): return
	var other = spawn("drone",occupied)
	if not check(other.grid_position != occupied,"Two Drones spawned into one air reservation"): return
	other.free()
	for category in [1,3,4,5]:
		var cell := Vector2i.ZERO
		for index in range(ground.terrain_cells.size()):
			if ground.terrain_cells[index] == category: cell = Vector2i(index%500,index/500); break
		if not check(ground.can_traverse(cell,2) and not ground.is_tile_valid(cell),"Drone does not bypass terrain class "+str(category)): return
		var start := cell+Vector2i(2,0)
		if not ground.is_tile_in_bounds(start): start = cell-Vector2i(2,0)
		relocate(drone,start)
		drone.command_move(ground.tile_to_world(cell))
		for i in range(180): drone._process(1.0/60)
		if not check(drone.global_position.distance_to(ground.tile_to_world(cell)) < 0.01,"Drone failed to fly across terrain "+str(category)): return
	if not check(ground.cleared_forest.size() == count,"Drone flight cleared forest"): return
	var bank: int = game.depot.iron
	var drone_cell: Vector2i = drone.grid_position
	drone.take_damage(drone.health)
	if not check(not ground.air_occupancy.has(drone_cell) and game.depot.iron == bank,"Drone death failed air release or altered inventory"): return
	if not check(not ground.can_traverse(Vector2i(-1,20),2),"Drone can leave map bounds"): return
	# Factory may launch a Drone even if every normal ground exit is blocked.
	var center = ground.get_tile_at_position(game.depot.global_position)
	var blocked: Array[Vector2i] = []
	for radius in range(6,16):
		for offset in [Vector2i(0,radius),Vector2i(radius,0),Vector2i(-radius,0),Vector2i(0,-radius)]:
			var cell: Vector2i = center+offset
			if ground.is_tile_valid(cell): ground.set_tile_feature(cell,"occupied_by","test"); blocked.append(cell)
	if not check(ProductionExit.find_cell(ground,game.depot.global_position,Vector2i(8,8)).x < 0 and ProductionExit.find_cell(ground,game.depot.global_position,Vector2i(8,8),2).x >= 0,"Air production exit uses ground blockers"): return
	for cell in blocked: ground.set_tile_feature(cell,"occupied_by",null)
	# Verify the production queue uses its queued unit's air layer, not just the exit helper.
	var factory = load("res://scenes/gameplay/tank_factory.tscn").instantiate()
	var start: Vector2i = ground.find_buildable_footprint(Vector2i(435,425),Vector2i(8,8))
	factory.position = ground.tile_to_world(start+Vector2i(4,4))
	factory.assigned_depot = game.depot
	game.add_child(factory)
	factory.set_process(false)
	var exits: Array[Vector2i] = []
	var factory_center = ground.get_tile_at_position(factory.global_position)
	for radius in range(6,16):
		for offset in [Vector2i(0,radius),Vector2i(radius,0),Vector2i(-radius,0),Vector2i(0,-radius)]:
			var cell: Vector2i = factory_center+offset
			if ground.can_traverse(cell): ground.set_tile_feature(cell,"occupied_by","factory_test"); exits.append(cell)
	game.depot.energy = 1000; game.depot.iron = 500
	if not check(factory.request_unit(&"drone"),"Factory rejected Drone job"): return
	var old_count: int = get_nodes_in_group("units").size()
	factory._process(factory.stats.print_seconds)
	if not check(factory.queue == 0 and get_nodes_in_group("units").size() == old_count+1 and game.depot.energy == 940 and game.depot.iron == 495,"Factory failed paid air launch with blocked ground exits"): return
	for cell in exits: ground.set_tile_feature(cell,"occupied_by",null)
	await process_frame
	game.free()
	# Fresh match restores forest and gets independent batch and shader resources.
	game = load("res://scenes/maps/resource_skirmish.tscn").instantiate()
	root.add_child(game)
	if not check(game.ground.get_terrain(destination) == 3 and game.ground.cleared_forest.is_empty(),"Runtime forest changes leaked into next match"): return
	print("TERRAIN_ABILITIES_CHECKS_PASSED")
	quit()
