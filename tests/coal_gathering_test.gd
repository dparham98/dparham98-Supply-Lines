extends SceneTree
# Headless: coal on the balanced map (docs/BALANCED_MAP.md). Coal cells block walking and building, hold a finite
# shared amount, cannot be reached through their forest, and once a way is cut an Infantry digs coal, carries it to
# a Depot and moves on through the field cell by cell. A Generator then burns the delivered coal.
const SCENE := "res://scenes/maps/balanced_skirmish.tscn"
var game: Node3D
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> bool:
	if value: return true
	push_error(message); quit(1); return false
func step(unit: Node3D, frames: int, done: Callable) -> bool:
	for i in range(frames):
		unit._process(1.0/60)
		if done.call(): return true
	return false
func run() -> void:
	game = load(SCENE).instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	for group in ["units", "depots", "mines"]:
		for node in get_nodes_in_group(group): node.set_process(false)
	var ground = game.ground
	var rules: HarvestingRules = ground.harvesting_rules
	var network = game.get_node("DepotNetwork")
	if not check(ground.Terrain.COAL == 6 and ground.TERRAIN_NAMES.size() == 7 and ground.TERRAIN_NAMES[6].begins_with("Coal"), "Coal is not a terrain category"): return

	# The field beside start A's safe expansion.
	var site: Vector3 = game.get_node("Sites/SafeExpansionA").position
	var field := {}
	for candidate in ground.coal_fields:
		if field.is_empty() or candidate.center.distance_to(site) < field.center.distance_to(site): field = candidate
	if not check(not field.is_empty() and field.cells.size()*rules.coal_per_tile == 1000 and ground.coal_field_remaining(field) == 1000, "A side field should hold 1,000 coal"): return
	var far: Vector2i = field.cells[0]
	if not check(ground.get_terrain(far) == 6 and not ground.is_tile_valid(far) and not ground.is_footprint_valid(far, Vector2i.ONE), "Coal cells must not be buildable"): return
	if not check(not ground.can_traverse(far, MobilityRules.Layer.GROUND) and not ground.can_traverse(far, MobilityRules.Layer.FOREST) and ground.can_traverse(far, MobilityRules.Layer.AIR), "Only air units may cross coal"): return
	if not check(ground.forest_amount(far) == 0 and ground.iron_amount(far) == 0 and not ground.ore_footprint_valid(far, Vector2i.ONE), "Coal cells are neither forest nor iron"): return

	# Finite and shared: both teams draw on the same cell.
	var shared = ground.coal_source(far)
	if not check(shared == ground.coal_source(far) and shared.resource_kind == &"coal" and shared.remaining == rules.coal_per_tile, "Coal cell handle or amount wrong"): return
	if not check(shared.extract(5, "player") == 5 and shared.extract(5, "enemy") == 5 and shared.remaining == rules.coal_per_tile-10 and ground.get_terrain(far) == 6, "Coal sharing or partial digging failed"): return
	if not check(shared.field_remaining() == 990, "Field total did not follow the cell"): return

	# Enclosed: the starting Infantry is refused, and nothing is dug.
	var first_worker: Node3D = game.get_node("Entities/Units/Infantry")
	first_worker.command_gather(shared)
	step(first_worker, 240, func(): return first_worker.state == "Coal unreachable")
	if not check(first_worker.state == "Coal unreachable" and first_worker.cargo == 0, "Coal inside uncut forest should be unreachable, state was '%s'" % first_worker.state): return
	first_worker.command_move(first_worker.global_position)

	# A second Depot at the safe expansion brings its own Infantry.
	var before := get_nodes_in_group("units")
	var depot: Node3D = network.establish(site, 100, 0)
	await process_frame
	await process_frame
	var worker: Node3D
	for unit in get_nodes_in_group("units"):
		if not before.has(unit): worker = unit
	if not check(is_instance_valid(depot) and depot.iron == 0 and depot.coal == 0 and worker != null and worker.team == "player", "New Depot should arrive with no iron and one Infantry"): return
	depot.set_process(false); worker.set_process(false)

	# Cut a lane three cells wide from the Depot's side of the belt to the field.
	var nearest: Vector2i = far
	var depot_cell: Vector2i = ground.get_tile_at_position(depot.global_position)
	for cell in field.cells:
		if cell.distance_squared_to(depot_cell) < nearest.distance_squared_to(depot_cell): nearest = cell
	var cut := 0
	for z in range(mini(nearest.y, depot_cell.y), maxi(nearest.y, depot_cell.y)+1):
		for x in range(nearest.x-1, nearest.x+2):
			if ground.clear_forest(Vector2i(x, z)): cut += 1
	if not check(cut >= 20, "Expected a forest belt between the safe expansion and its coal, cut only %d cells" % cut): return

	# The Infantry digs, delivers, and carries on into the next cell when the first is dug out.
	var terrain: Node3D = game.get_node("Terrain")
	if not check(terrain.coal_state != null and terrain.coal_state.indices[0].has(nearest), "Coal lumps are not bound to their cells"): return
	var source = ground.coal_source(nearest)
	worker.command_gather(source)
	var goal: int = rules.coal_per_tile+10
	step(worker, 60*240, func(): return depot.coal >= goal)
	if not check(depot.coal == goal, "Infantry delivered %d coal, expected %d (state '%s')" % [depot.coal, goal, worker.state]): return
	if not check(ground.get_terrain(nearest) == 0 and ground.can_traverse(nearest) and ground.is_tile_valid(nearest) and ground.cleared_coal.has(nearest) and ground.coal_source(nearest) == null, "A dug-out coal cell should become open ground"): return
	if not check(not terrain.coal_state.indices[0].has(nearest), "The dug-out cell kept its coal lumps"): return
	if not check(worker.source != source and is_instance_valid(worker.source) and field.cells.has(worker.source.cell) and worker.order in ["gather", "return"], "Infantry did not move on to the next cell of the field"): return
	if not check(ground.coal_field_remaining(field)+depot.coal+worker.cargo == 990, "Coal was created or lost: %d in the field, %d delivered, %d carried" % [ground.coal_field_remaining(field), depot.coal, worker.cargo]): return

	# The right-click order and the hover card reach coal through the same cell.
	var camera_rig: Node3D = game.get_node("CameraRig")
	var target_cell: Vector2i = worker.source.cell
	var target_point: Vector3 = ground.tile_to_world(target_cell)
	camera_rig.focus_position(target_point)
	for i in range(30): await process_frame
	var screen: Vector2 = root.get_camera_3d().unproject_position(target_point)
	var overlay = game.get_node("Interface/MapOverlay")
	var hovered: Node3D = overlay.hover_target(screen)
	if not check(hovered == ground.coal_source(target_cell) and overlay.hud_name(hovered).begins_with("Coal deposit"), "Pointing at a coal cell should name it"): return
	worker.command_move(worker.global_position)
	worker.set_selected(true)
	game.issue_order(screen)
	if not check(worker.order in ["gather", "return"] and worker.source == ground.coal_source(target_cell), "Right-clicking coal should order Infantry to dig it"): return
	worker.set_selected(false)

	# The field runs out: the last load is delivered and the worker stops.
	for cell in field.cells:
		if cell != worker.source.cell: ground.harvest_coal(cell, 100000)
	var stock: int = depot.coal
	var last: int = worker.source.remaining
	step(worker, 60*600, func(): return worker.order == "idle")
	if not check(worker.order == "idle" and worker.cargo == 0 and ground.coal_field_remaining(field) == 0 and depot.coal >= stock+last, "Infantry should deliver the last coal and stop: order %s, cargo %d" % [worker.order, worker.cargo]): return

	# A Generator assigned to that Depot burns the coal: one coal for a full cycle's energy.
	var generator: Node3D = load("res://scenes/gameplay/energy_generator.tscn").instantiate()
	generator.assigned_depot = depot
	generator.position = depot.global_position+Vector3(14, 0, 10)
	game.get_node("Entities/Buildings").add_child(generator)
	await process_frame
	if not check(is_instance_valid(generator) and generator.is_in_group("energy_generators"), "Generator could not be placed beside the new Depot"): return
	generator.set_process(false)
	generator.set_fuel_preference("coal")
	var coal: int = depot.coal
	var energy: int = depot.energy
	generator._process(generator.fuel_rules.coal_seconds*3.0)
	if not check(depot.coal == coal-3 and depot.energy == energy+3*generator.fuel_rules.coal_output, "Generator did not burn delivered coal for energy"): return
	print("COAL_GATHERING_TEST_PASSED")
	quit()
