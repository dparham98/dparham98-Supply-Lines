extends SceneTree
# Rendered: the ore rocks give way to mines (docs/IRON_MINE_MODEL.md). Shots of the skirmish's own mine, and of a
# second deposit spot bare, as a mine site and as a finished mine. Also checks the rocks on covered cells really have
# no size in their batches, and that they are back once a site is cancelled. Pictures only; judge them by eye.
const TestOutput = preload("res://tests/test_output.gd")
var game: Node3D
var network: Node
var rig: Node
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> bool:
	if value: return true
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
func shot(at: Vector3, distance: float, name: String) -> void:
	rig.focus_position(at,distance)
	for frame in range(150): rig.advance_camera(1.0/60)
	for frame in range(6): await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(TestOutput.path(name+".png"))
## Sized rocks standing on covered cells: none should be left.
func visible_on_covered(state: OreStateVisuals) -> int:
	var count := 0
	for part in range(state.batches.size()):
		var multimesh := state.batches[part].multimesh
		for cell in game.ground.ore_covered:
			for index in state.by_cell[part].get(cell,[]):
				if multimesh.get_instance_transform(index).basis.get_scale().y > 0.001: count += 1
	return count
func run() -> void:
	root.size = Vector2i(1280,900)
	game = load("res://scenes/maps/resource_skirmish.tscn").instantiate()
	root.add_child(game)
	for frame in range(3): await process_frame
	network = game.get_node("DepotNetwork")
	game.set_process(false)
	for unit in get_nodes_in_group("units"): unit.set_process(false)
	for depot in get_nodes_in_group("depots"): depot.set_process(false)
	game.get_node("Interface").visible = false
	var depot = game.depot
	depot.storage_capacity = 10000
	depot.energy = 2000; depot.iron = 2000
	rig = game.get_node("CameraRig")
	rig.set_process(false)
	rig.min_zoom = 4.0
	var state: OreStateVisuals = game.get_node("Terrain").ore_state
	if not check(state.hidden_count() > 0 and visible_on_covered(state) == 0,"Rocks under the starting mine should have no size"): return
	var start_mine: Node3D = game.get_node("Entities/Buildings/IronMine")
	start_mine.set_process(false)
	await shot(start_mine.global_position+Vector3(0,1,0),9,"ore_cover_start_mine")
	await shot(start_mine.global_position,30,"ore_cover_start_mine_far")
	# A spot away from the starting mine, so the two don't share a shot.
	var point := site(depot.global_position+Vector3(-8,0,24))
	if not check(point != Vector3.INF,"No mine site"): return
	await shot(point+Vector3(0,1,0),9,"ore_cover_bare")
	var before: int = state.hidden_count()
	var plan = network.queue_plan(point,&"iron_mine")
	plan.set_process(false)
	await shot(point+Vector3(0,1,0),9,"ore_cover_site")
	if not check(state.hidden_count() > before and visible_on_covered(state) == 0,"A mine site should hide its rocks"): return
	plan.cancel()
	await process_frame
	if not check(state.hidden_count() == before,"A cancelled site should give its rocks back"): return
	for part in range(state.batches.size()):
		for cell in state.by_cell[part]:
			for index in state.by_cell[part][cell]:
				if game.ground.ore_covered.has(cell): continue
				var now: Transform3D = state.batches[part].multimesh.get_instance_transform(index)
				var was: Transform3D = state.originals[part][index]
				if not check(now.is_equal_approx(was),"An uncovered rock should stand as it was baked"): return
	plan = network.queue_plan(point,&"iron_mine")
	plan.set_process(false)
	var mine: Node3D = plan.complete_from_stock()
	if not check(mine != null,"Mine plan did not complete"): return
	mine.set_process(false)
	await process_frame
	await shot(mine.global_position+Vector3(0,1,0),9,"ore_cover_mine")
	await shot(mine.global_position,30,"ore_cover_mine_far")
	print("ORE_COVER_RUNTIME_CHECK_PASSED"); quit(TestOutput.exit_code())
