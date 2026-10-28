extends SceneTree
const Bounds = preload("res://scripts/units/selection_bounds.gd")
var game: Node3D
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> bool:
	if ok: return true
	push_error(message); quit(1); return false
func mouse(point: Vector2, pressed: bool, button := MOUSE_BUTTON_LEFT) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	root.push_input(motion,true)
	var event := InputEventMouseButton.new()
	event.position = point; event.button_index = button; event.pressed = pressed
	root.push_input(event,true)
func run() -> void:
	root.size = Vector2i(1280,900)
	game = load("res://scenes/maps/resource_skirmish.tscn").instantiate()
	root.add_child(game)
	for i in range(4): await process_frame
	var worker = game.get_node("Entities/Units/Infantry")
	var scout = load("res://scenes/gameplay/scout.tscn").instantiate()
	scout.position = worker.position + Vector3(6,0,0)
	game.get_node("Entities/Units").add_child(scout)
	await process_frame
	for unit in get_nodes_in_group("units"): unit.set_process(false)
	for depot in get_nodes_in_group("depots"): depot.set_process(false)
	var rig = game.get_node("CameraRig")
	rig.set_process(false); rig.focus_position(worker.position)
	for i in range(180): rig.advance_camera(1.0/60)
	var camera: Camera3D = rig.camera
	var manager = root.get_node("SelectionManager")
	var hud = game.hud
	var a: Rect2 = Bounds.screen_rect(worker,camera)
	var b: Rect2 = Bounds.screen_rect(scout,camera)
	var box := a.merge(b).grow(5)
	mouse(box.position,true)
	mouse(box.end,false)
	await process_frame
	if not check(worker.is_selected and scout.is_selected,"Mixed unit drag selection failed"): return
	if not check(not game.selected_building,"Box must exclude buildings"): return
	mouse(box.end,true); mouse(box.position,false)
	if not check(worker.is_selected and scout.is_selected,"Reverse mixed drag selection failed"): return
	var destination: Vector3 = worker.position + Vector3(0,0,8)
	game.pending_unit_command = "move"
	game.issue_card_order(camera.unproject_position(destination))
	if not check(worker.order == "move" and scout.order == "move","Group movement failed"): return
	var worker_start: Vector3 = worker.global_position
	var scout_start: Vector3 = scout.global_position
	for frame in range(120):
		worker._process(1.0/60); scout._process(1.0/60)
	if not check(worker.global_position.distance_to(worker_start) > 0.5 and scout.global_position.distance_to(scout_start) > 0.5,"Group units failed to follow navigation paths"): return
	if not check(worker.grid_position != scout.grid_position,"Group movement overlapped occupancy cells"): return
	var screen := camera.unproject_position(worker.selection_point())
	mouse(screen,true); mouse(screen,false)
	await process_frame
	hud.build_open = true; hud.refresh_build_menu(); game.placing_generator = true
	var energy: int = game.depot.energy
	var edge := camera.unproject_position(game.depot.global_position+Vector3(3.8,0.4,3.8))
	if not check(Bounds.hit_distance(game.depot,camera,edge) < INF,"Depot visible edge not pickable"): return
	mouse(edge,true); mouse(edge,false)
	await process_frame
	if not check(game.selected_building == game.depot and not hud.build_open and not game.placing_generator,"Selection must replace armed Build menu"): return
	if not check(game.depot.energy == energy,"Selection spent construction funds"): return
	mouse(screen,true); mouse(screen,false)
	await process_frame
	var order: String = worker.order
	var ui: Vector2 = hud.get_node("Bottom").get_global_rect().get_center()
	mouse(ui,true,MOUSE_BUTTON_RIGHT); mouse(ui,false,MOUSE_BUTTON_RIGHT)
	if not check(worker.order == order,"UI right click issued a world order"): return
	mouse(box.position,true); mouse(ui,false)
	if not check(not manager.selecting and worker.is_selected,"UI release must cancel world drag"): return
	mouse(box.position,true)
	mouse(box.position,true,MOUSE_BUTTON_MIDDLE)
	if not check(not manager.selecting,"Camera gesture did not cancel drag"): return
	print("SELECTION_USABILITY_CHECKS_PASSED")
	quit()
