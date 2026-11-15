extends SceneTree
# The strip beside a Depot where Depot Trucks are built is kept free of buildings (docs/DEPOT_MODEL.md),
# so a truck build cannot stall behind one. Units still cross it, and it is freed with the Depot.
var game: Node3D
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> bool:
	if value: return true
	push_error(message); quit(1); return false
## Somewhere a Depot facing `yaw` could go, `away` metres or more from the authored one, searching outward.
func open_depot_site(network, yaw: float, away: float) -> Vector3:
	for radius in range(int(away),200,6):
		for step in range(0,360,15):
			var point: Vector3 = game.depot.global_position+Vector3(cos(deg_to_rad(step)),0,sin(deg_to_rad(step)))*radius
			if network.can_place(point,null,true,"player",null,yaw) and game.ground.is_footprint_valid(network.footprint_start(point,network.depot_size())-Vector2i(4,4),network.depot_size()+Vector2i(8,8)): return point
	return Vector3.INF
func run() -> void:
	game = load("res://scenes/maps/resource_skirmish.tscn").instantiate()
	root.add_child(game)
	for frame in range(3): await process_frame
	game.set_process(false)
	var ground = game.ground
	var depot: Node3D = game.depot
	depot.set_process(false)
	var network = game.get_node("DepotNetwork")
	var apron: Array[Vector2i] = depot.apron_cells
	if not check(not apron.is_empty() and apron == depot.truck_side_cells(),"The Depot should reserve its whole truck strip"): return
	if not check(network.strip_cells(depot.global_position) == apron,"Placement should predict the strip an east-facing Depot reserves"): return
	var cell: Vector2i = apron[apron.size()/2]
	# No building fits over the strip: the footprint test, a mine on ore and a Barracks plan all refuse it.
	if not check(not ground.is_footprint_valid(cell,Vector2i.ONE) and ground.is_apron(cell),"A footprint over the truck strip should be refused"): return
	var size: Vector2i = network.plan_spec(&"barracks").size
	var over: Vector3 = ground.tile_to_world(cell)
	if not check(not network.plan_terrain_valid(network.footprint_start(over,size),size,&"barracks"),"A Barracks over the truck strip should be refused"): return
	if not check(network.strip_notice(over,size,&"barracks") == network.STRIP_NOTICE,"Refusing a building on the strip should say why"): return
	var tile: Dictionary = ground.tiles[cell.y*ground.grid_size.x+cell.x]
	if not check(tile.terrain_buildable and tile.occupied_by == null,"The middle of the strip should be open, buildable ground"): return
	# An ore tile on a strip takes no mine either.
	var ore_cell := Vector2i(-1,-1)
	for i in range(ground.tiles.size()):
		if ground.get_terrain(Vector2i(i%ground.grid_size.x,i/ground.grid_size.x)) == ground.Terrain.ORE and ground.tiles[i].occupied_by == null: ore_cell = Vector2i(i%ground.grid_size.x,i/ground.grid_size.x); break
	if not check(ore_cell.x >= 0 and ground.ore_footprint_valid(ore_cell,Vector2i.ONE),"The map should have open ore"): return
	ground.tiles[ore_cell.y*ground.grid_size.x+ore_cell.x]["apron"] = "test"
	if not check(not ground.ore_footprint_valid(ore_cell,Vector2i.ONE),"A mine on a truck strip should be refused"): return
	ground.tiles[ore_cell.y*ground.grid_size.x+ore_cell.x].erase("apron")
	# Units still walk across it, but none is set down there.
	if not check(not ground.navigation_grid.is_point_solid(cell),"Units should still cross the truck strip"): return
	if not check(not ground.is_apron(ProductionExit.find_cell(ground,depot.global_position,depot.footprint)),"Units should not be set down on the truck strip"): return
	# The truck build itself still claims the strip, and starts.
	if not check(depot._begin_truck(),"A truck should still start on its own reserved strip"): return
	depot._release_truck_side()
	if not check(tile.get("apron") == depot._key(),"Releasing a truck build should keep the reservation"): return
	# An idle unit of the Depot's side standing on the strip is sent off it when a truck waits.
	var worker: Node3D = load("res://scenes/gameplay/infantry.tscn").instantiate()
	worker.position = over
	game.get_node("Entities/Units").add_child(worker)
	await process_frame
	worker.set_process(false)
	if not check(ground.is_apron(worker.grid_position) and worker.order == "idle","The test unit should stand idle on the strip"): return
	if not check(not depot._begin_truck(),"A unit on the strip should hold up the truck"): return
	depot._clear_idle_units()
	if not check(worker.order == "move" and not ground.is_apron(ground.get_tile_at_position(worker.move_goal)),"An idle unit on the strip should be sent off it"): return
	worker.queue_free(); await process_frame
	# A Depot turned another way keeps its strip on the turned side, as placement predicts.
	var turned: Vector3 = open_depot_site(network,PI,60)
	if not check(turned != Vector3.INF,"No open site for a turned Depot"): return
	var second: Node3D = network.establish(turned,0,0,PI)
	second.set_process(false)
	if not check(not second.apron_cells.is_empty() and second.apron_cells == network.strip_cells(turned,PI) and second.apron_cells != network.strip_cells(turned,0.0),"A turned Depot should reserve the strip on its turned side"): return
	second.get_parent().remove_child(second); second.free()
	# A Depot can't be placed with a building plan on its strip, and no plan goes on a planned Depot's strip.
	var site: Vector3 = open_depot_site(network,0.0,60)
	if not check(site != Vector3.INF,"No open Depot site"): return
	var strip: Array[Vector2i] = network.strip_cells(site)
	var on: Vector3 = ground.tile_to_world(strip[strip.size()/2])
	var plan = network.queue_plan(on,&"generator")
	if not check(plan != null,"A Generator plan should go on open ground"): return
	if not check(not network.can_place(site,null,true) and network.strip_notice(site,network.depot_size(),&"depot") == network.STRIP_NOTICE,"A Depot should not be placed with a plan on its truck strip"): return
	plan.get_parent().remove_child(plan); plan.free()
	var depot_plan = network.queue_plan(site,&"depot")
	if not check(depot_plan != null and network.plan_terrain_valid(depot_plan.start,depot_plan.spec.size,&"depot",depot_plan),"A Depot plan should go on open ground with a clear strip"): return
	if not check(network.plan_overlaps(network.footprint_start(on,Vector2i(2,2)),Vector2i(2,2)) and network.queue_plan(on,&"generator") == null,"No plan should go on a planned Depot's truck strip"): return
	depot_plan.get_parent().remove_child(depot_plan); depot_plan.free()
	# Removing the Depot frees the strip for building again.
	depot.get_parent().remove_child(depot)
	if not check(not tile.has("apron") and ground.is_footprint_valid(cell,Vector2i.ONE),"A removed Depot should free its truck strip"): return
	depot.free()
	print("DEPOT_APRON_TEST_PASSED")
	quit(0)
