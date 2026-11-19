extends SceneTree
# Rendered check of the Production speed panel (docs/PRODUCTION_POWER.md): a Barracks selected by a real click shows
# the panel under the Depot panels, at 1x and at 3x part way through an Infantry. Saves production_power_1x and _3x.
var game: Node3D
var hud: CanvasLayer
var network: Node
const TestOutput = preload("res://tests/test_output.gd")
const OUTPUT = "production_power_work/"
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> bool:
	if value: return true
	push_error(message); quit(1); return false
func click_at(point: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	root.push_input(motion,true)
	for pressed in [true,false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		root.push_input(event,true)
		for frame in range(4): await process_frame
func shot(name: String) -> void:
	for frame in range(10): await process_frame
	var panel: Control = hud.get_node("ProductionPanel")
	if not check(panel.get_global_rect().end.y <= root.size.y+1,"%s: the panel overflows the window" % name): return
	if not check(not panel.get_global_rect().intersects(hud.get_node("DepotPanel").get_global_rect()),"%s: the panel overlaps the Depot panel" % name): return
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	TestOutput.save_png(self, root.get_texture().get_image(), OUTPUT+name+".png")
func site(kind: StringName, near: Vector3) -> Vector3:
	var spec: Dictionary = network.plan_spec(kind)
	for radius in range(10,100,4):
		for offset in [Vector3(radius,0,0),Vector3(-radius,0,0),Vector3(0,0,radius),Vector3(0,0,-radius)]:
			var point: Vector3 = near+offset
			var start: Vector2i = network.footprint_start(point,spec.size)
			if network.plan_terrain_valid(start,spec.size,kind) and not network.plan_overlaps(start,spec.size) and network.can_place_size(point,game.depot,spec.size): return point
	return Vector3.INF
func run() -> void:
	root.size = Vector2i(1280,900)
	game = load("res://scenes/maps/resource_skirmish.tscn").instantiate()
	root.add_child(game)
	for frame in range(3): await process_frame
	game.set_process(false)
	hud = game.get_node("Interface")
	network = game.get_node("DepotNetwork")
	for group in ["units","depots"]:
		for node in get_nodes_in_group(group): node.set_process(false)
	var depot = game.depot
	depot.storage_capacity = 10000; depot.energy = 3000; depot.iron = 3000
	var point := site(&"barracks",depot.global_position)
	if not check(point != Vector3.INF,"No Barracks site"): return
	var plan = network.queue_plan(point,&"barracks")
	plan.set_process(false)
	var barracks: Node3D = plan.complete_from_stock()
	if not check(barracks != null,"Barracks not built"): return
	barracks.set_process(false)
	var rig = game.get_node("CameraRig")
	rig.set_process(false)
	rig.focus_position(barracks.global_position,40)
	for frame in range(180): rig.advance_camera(1.0/60)
	for frame in range(30): await process_frame
	await click_at(rig.camera.unproject_position(barracks.global_position+Vector3.UP*2.5))
	if not check(game.selected_building == barracks and hud.get_node("ProductionPanel").visible,"Clicking the Barracks should show its production panel"): return
	await shot("production_power_1x")
	for i in range(3): barracks.request_unit(&"infantry")
	hud.get_node("ProductionPanel/Body/PowerSlider").value = 3.0
	barracks._process(1.0)
	if not check(barracks.power == 3.0 and absf(barracks.progress-3.0) < 0.01,"3x should do 3 s of work in a second"): return
	await shot("production_power_3x")
	print("PRODUCTION_POWER_RUNTIME_PASSED")
	quit(0)
