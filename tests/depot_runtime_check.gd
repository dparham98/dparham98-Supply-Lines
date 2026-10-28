extends SceneTree
const TestOutput = preload("res://tests/test_output.gd")
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	root.size = Vector2i(1280,900)
	var game = load("res://scenes/maps/resource_skirmish.tscn").instantiate()
	root.add_child(game)
	await process_frame
	var rig = game.get_node("CameraRig")
	rig.focus_hq()
	for frame in range(180): rig.advance_camera(1.0/60)
	game.depot.iron = 100
	game.depot.request_truck()
	game.depot._process(3.1)
	game.get_node("DepotNetwork").select_depot(game.depot)
	for frame in range(8): await process_frame
	await RenderingServer.frame_post_draw
	TestOutput.save_png(self, root.get_texture().get_image(), "milestone2_runtime.png")
	print("DEPOT_RENDER_CHECK_PASSED")
	quit(TestOutput.exit_code())
