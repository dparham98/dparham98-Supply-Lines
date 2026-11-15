extends SceneTree
# The strip beside a Depot where Depot Trucks are built is kept free of buildings (docs/DEPOT_MODEL.md),
# so a truck build cannot stall behind one. Units still cross it, and it is freed with the Depot.
var game: Node3D
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> bool:
	if value: return true
	push_error(message); quit(1); return false
func run() -> void:
	game = load("res://scenes/maps/resource_skirmish.tscn").instantiate()
	root.add_child(game)
	for frame in range(3): await process_frame
	game.set_process(false)
	var ground = game.ground
	var depot: Node3D = game.depot
	var network = game.get_node("DepotNetwork")
	var apron: Array[Vector2i] = depot.apron_cells
	if not check(not apron.is_empty() and apron == depot.truck_side_cells(),"The Depot should reserve its whole truck strip"): return
	var cell: Vector2i = apron[apron.size()/2]
	# No building fits over the strip: the footprint test, a mine on ore and a Barracks plan all refuse it.
	if not check(not ground.is_footprint_valid(cell,Vector2i.ONE),"A footprint over the truck strip should be refused"): return
	var size: Vector2i = network.plan_spec(&"barracks").size
	var over: Vector3 = ground.tile_to_world(cell)
	if not check(not network.plan_terrain_valid(network.footprint_start(over,size),size,&"barracks"),"A Barracks over the truck strip should be refused"): return
	var tile: Dictionary = ground.tiles[cell.y*ground.grid_size.x+cell.x]
	var terrain_ok: bool = tile.terrain_buildable
	if not check(terrain_ok and tile.occupied_by == null,"The middle of the strip should be open, buildable ground"): return
	# Units still walk across it.
	if not check(not ground.navigation_grid.is_point_solid(cell),"Units should still cross the truck strip"): return
	# The truck build itself still claims the strip, and starts.
	if not check(depot._begin_truck(),"A truck should still start on its own reserved strip"): return
	depot._release_truck_side()
	if not check(tile.get("apron") == "depot_%s" % depot.get_instance_id(),"Releasing a truck build should keep the reservation"): return
	# Removing the Depot frees the strip for building again.
	depot.get_parent().remove_child(depot)
	if not check(not tile.has("apron") and ground.is_footprint_valid(cell,Vector2i.ONE),"A removed Depot should free its truck strip"): return
	depot.free()
	print("DEPOT_APRON_TEST_PASSED")
	quit(0)
