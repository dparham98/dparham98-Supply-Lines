extends SceneTree
# Coal mines (docs/COAL_MINES.md): coal lies in the ground and is taken through a mine built on its seam, the old
# pithead. Checks that a mine fits on a seam and only one to a seam, that it yields the whole seam's coal without
# opening the ground, that a worker gathers coal from it, and that coal cannot be dug by hand while the rule is on.
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> bool:
	if value: return true
	push_error(message); quit(1); return false
func run() -> void:
	var game: Node3D = load("res://scenes/maps/lakes_skirmish.tscn").instantiate()
	root.add_child(game)
	await process_frame
	await process_frame
	var ground = game.ground
	var network = game.get_node("DepotNetwork")
	var rules = network.engineering_rules
	var depot = game.get_node("Entities/Buildings/Depot")
	if not check(ground.harvesting_rules.coal_needs_mine,"Coal should need a mine by default"): return
	# The starter seam beside the West start. No mine stands on any seam at the start.
	var seam := {}
	for field in ground.coal_fields:
		if not check(ground.coal_mine_at(field.cells[0]) == null,"A coal seam starts with a mine on it"): return
		if seam.is_empty() or field.center.distance_to(depot.global_position) < seam.center.distance_to(depot.global_position): seam = field
	var whole: int = ground.coal_field_remaining(seam)
	if not check(whole == seam.cells.size()*ground.harvesting_rules.coal_per_tile and whole >= 500,"The starter seam holds %d coal" % whole): return
	# A 2 x 2 block of the seam for the mine.
	var size: Vector2i = rules.mine_footprint
	var start := Vector2i(-1,-1)
	for cell in seam.cells:
		if ground.ore_footprint_valid(cell,size): start = cell; break
	if not check(start.x >= 0,"No place for a mine on the starter seam"): return
	if not check(not ground.ore_footprint_valid(start-Vector2i(3,0),size),"A mine fits half off the seam"): return
	if not check(not ground.is_footprint_valid(start,size),"An ordinary building fits on coal"): return
	var centre: Vector3 = ground.tile_to_world(start+size/2)
	if not check(network.mine_scene_for(network.mine_spot(centre)) == network.mine_scene,"A coal seam should get the pithead"): return
	var mine: Node3D = network.mine_scene.instantiate()
	mine.rules = rules
	mine.position = centre
	game.get_node("Entities/Buildings").add_child(mine)
	await process_frame
	if not check(is_instance_valid(mine) and mine.on_coal and mine.resource_kind == &"coal" and mine.is_in_group("mines"),"The mine on coal is not a coal mine"): return
	if not check(mine.reserves() == whole and ground.coal_mine_at(seam.cells[0]) == mine,"The coal mine does not hold its whole seam: %d" % mine.reserves()): return
	if not check(not ground.ore_footprint_valid(seam.cells[seam.cells.size()-1],Vector2i.ONE),"A second mine fits on a seam that has one"): return
	# Taking coal empties the seam, shared between sides, and leaves the ground as it was.
	if not check(mine.extract(30,"player") == 30 and mine.extract(30,"enemy") == 30 and mine.reserves() == whole-60,"The coal mine is not shared or loses coal"): return
	for cell in seam.cells:
		if not check(ground.get_terrain(cell) == ground.Terrain.COAL and not ground.cleared_coal.has(cell),"Mining opened the ground at %s" % cell): return
	# A worker sent to the mine brings coal home, once the trees round the seam are felled.
	var middle: Vector2i = ground.get_tile_at_position(seam.center)
	for dz in range(-12,13):
		for dx in range(-12,13): ground.clear_forest(middle+Vector2i(dx,dz))
	var worker = game.get_node("Entities/Units/Infantry")
	var before: int = depot.coal
	worker.command_gather(mine)
	for i in range(60*240):
		worker._process(1.0/60)
		mine._process(1.0/60)
		if depot.coal > before: break
	if not check(depot.coal > before and worker.cargo_kind == &"coal","The worker brought no coal from the mine (state '%s')" % worker.state): return
	# Emptied, the mine is worked out and the seam is still ground nobody walks on.
	mine.extract(mine.reserves()+10,"player")
	if not check(mine.reserves() == 0 and mine.extract(5,"player") == 0 and ground.get_terrain(seam.cells[0]) == ground.Terrain.COAL,"An emptied seam should stay as it is"): return
	# By hand: the old rule still works when it is switched back on.
	var other := {}
	for field in ground.coal_fields:
		if field != seam and (other.is_empty() or field.center.distance_to(depot.global_position) < other.center.distance_to(depot.global_position)): other = field
	ground.harvesting_rules.coal_needs_mine = false
	if not check(ground.harvest_coal(other.cells[0],10) == 10,"Digging by hand should still work with the rule off"): return
	ground.harvesting_rules.coal_needs_mine = true
	print("COAL_MINE_TEST_PASSED"); quit()
