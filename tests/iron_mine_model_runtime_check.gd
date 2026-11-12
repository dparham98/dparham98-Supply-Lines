extends SceneTree
# Rendered: the Iron Mine (docs/IRON_MINE_MODEL.md) at the game's camera and close up: a site going up, the
# finished mine idle, winding while it is mined, worked out, and the collapse; also the skirmish's own mine on its
# deposit. Saves iron_mine_*.png. Also checks the finished mine is pickable on its headframe. Pictures only;
# judge them by eye.
const Bounds = preload("res://scripts/units/selection_bounds.gd")
const TestOutput = preload("res://tests/test_output.gd")
const Burst = preload("res://scripts/components/burst_effect.gd")
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
## Steps the clip as frames would, so blends complete and Work hands over at the end of its cycle.
func step(model: Node3D, seconds: float, effects: Node = null) -> void:
	var left := seconds
	while left > 0.0:
		var dt := minf(0.05,left)
		model.player.advance(dt)
		model._process(dt)
		if effects != null: effects.player.advance(dt)
		left -= dt
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
	rig.min_zoom = 4.0      # close-ups below the player's zoom limit
	# The skirmish's own mine on its deposit, as the player first sees it.
	var start_mine: Node3D = game.get_node("Entities/Buildings/IronMine")
	start_mine.set_process(false)
	await shot(start_mine.global_position,30,"iron_mine_start")
	await shot(start_mine.global_position+Vector3(0,1,0),9,"iron_mine_start_close")
	var point := site(depot.global_position)
	if not check(point != Vector3.INF,"No Iron Mine site"): return
	# A site half built, at the game's distance and close.
	var plan = network.queue_plan(point,&"iron_mine")
	plan.set_process(false)
	plan.added = {&"iron": int(plan.spec.iron*0.5)}; plan.energy_paid = int(plan.spec.energy*0.5)
	plan.refresh_label()
	var centre: Vector3 = plan.get_node("Visuals/Model").global_position
	await shot(centre,30,"iron_mine_site")
	await shot(centre+Vector3(0,1,0),8,"iron_mine_site_close")
	plan.added = {}; plan.energy_paid = 0
	var building: Node3D = plan.complete_from_stock()
	if not check(building != null,"Iron Mine plan did not complete"): return
	building.set_process(false)
	await process_frame
	var model: Node3D = building.get_node("Visuals/Model")
	# Idle: nobody mining.
	building._process(0.1)
	step(model,0.5)
	await shot(building.global_position,30,"iron_mine_idle")
	var screen: Vector2 = rig.camera.unproject_position(building.global_position+Vector3(0.3,2.0,0.0))
	if not check(Bounds.hit_distance(building,rig.camera,screen) < INF,"Iron Mine not pickable on its headframe"): return
	await shot(building.global_position+Vector3(0,1.4,0),8,"iron_mine_idle_close")
	# Mined: the skip rising with a load, then tipping it into the chute.
	building.extract(5,"player")
	step(model,1.7)
	await shot(building.global_position+Vector3(0,1.4,0),8,"iron_mine_working_close")
	step(model,0.75)
	await shot(building.global_position+Vector3(0,1.4,0),8,"iron_mine_tipping_close")
	await shot(building.global_position,30,"iron_mine_working")
	# Worked out.
	for cell in building.cells: building.ground.iron_reserves[cell] = 0
	building._work_left = 0.0
	building._process(0.1)
	step(model,3.8)
	await shot(building.global_position+Vector3(0,1.4,0),8,"iron_mine_depleted_close")
	# The collapse, part way and as a wreck.
	building.take_damage(building.max_health)
	var effects: Node = model.get_children().filter(func(n): return n.get_script() == Burst)[0]
	step(model,0.95,effects)
	await shot(model.global_position+Vector3(0,1.4,0),11,"iron_mine_dying")
	step(model,1.0,effects)
	await shot(model.global_position+Vector3(1.2,0.5,0),11,"iron_mine_wreck")
	print("IRON_MINE_MODEL_RUNTIME_CHECK_PASSED"); quit(TestOutput.exit_code())
