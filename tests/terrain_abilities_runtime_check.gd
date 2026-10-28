extends SceneTree
var game: Node3D
var hud: CanvasLayer
const TestOutput = preload("res://tests/test_output.gd")
const OUTPUT = ""
func _initialize() -> void: call_deferred("run")
func check(value: bool, text: String) -> bool:
	if value: return true
	push_error(text); quit(1); return false
func click(point: Vector2, button: int) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	root.push_input(motion,true)
	var event := InputEventMouseButton.new()
	event.position = point; event.button_index = button; event.pressed = true
	root.push_input(event,true)
	for i in range(5): await process_frame
	event = InputEventMouseButton.new()
	event.position = point; event.button_index = button; event.pressed = false
	root.push_input(event,true)
	for i in range(5): await process_frame
func shot(name: String) -> void:
	hud._process(0)
	for i in range(8): await process_frame
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	TestOutput.save_png(self, root.get_texture().get_image(), OUTPUT+name+".png")
func run() -> void:
	root.size = Vector2i(1280,900)
	game = load("res://scenes/maps/terrain_abilities_exercise.tscn").instantiate()
	root.add_child(game)
	for i in range(5): await process_frame
	game.set_process(false)
	hud = game.get_node("Interface")
	for node in get_nodes_in_group("units"): node.set_process(false)
	var rig = game.get_node("CameraRig")
	rig.set_process(false)
	rig.focus_position(Vector3(97.5,0,25.5),42)
	for i in range(180): rig.advance_camera(1.0/60)
	var drone = game.get_node("Entities/Units/FlyingDrone")
	var tank = game.get_node("Entities/Units/ForestTank")
	var scout = game.get_node("Entities/Units/ForestScout")
	var goal: Vector3 = game.ground.tile_to_world(Vector2i(340,275))
	await click(rig.camera.unproject_position(drone.selection_point()),MOUSE_BUTTON_LEFT)
	if not check(drone.is_selected,"Could not select Drone at airborne model"): return
	await click(rig.camera.unproject_position(goal),MOUSE_BUTTON_RIGHT)
	if not check(drone.order == "move","Drone right-click forest order failed"): return
	for i in range(240): drone._process(1.0/60)
	if not check(drone.global_position.distance_to(goal) < 0.01 and game.ground.cleared_forest.is_empty(),"Drone did not arrive or modified forest"): return
	await shot("terrain_drone_flight")
	drone.set_selected(false); scout.set_selected(true)
	hud._process(0)
	await click(rig.camera.unproject_position(game.ground.tile_to_world(Vector2i(340,274))),MOUSE_BUTTON_RIGHT)
	if not check(scout.order == "move","Scout right-click forest order failed"): return
	for i in range(300): scout._process(1.0/60)
	if not check(game.ground.get_terrain(Vector2i(340,274)) == 3,"Scout modified forest"): return
	await shot("terrain_scout_forest")
	scout.set_selected(false); tank.set_selected(true)
	await shot("terrain_tank_before")
	await click(rig.camera.unproject_position(game.ground.tile_to_world(Vector2i(340,276))),MOUSE_BUTTON_RIGHT)
	if not check(tank.order == "move","Tank right-click forest order failed"): return
	for i in range(360): tank._process(1.0/60)
	game.ground._process(0)
	if not check(game.ground.get_terrain(Vector2i(340,276)) == 0,"Tank did not clear clicked forest"): return
	await shot("terrain_tank_after")
	if not check(hud.info.get_node("Details").get_global_rect().end.y <= root.size.y,"Tank HUD overflow"): return
	root.size = Vector2i(1440,960)
	await shot("terrain_abilities_wide")
	print("TERRAIN_ABILITIES_RUNTIME_CHECKS_PASSED")
	quit(TestOutput.exit_code())
