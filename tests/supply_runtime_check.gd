extends SceneTree
const TestOutput = preload("res://tests/test_output.gd")
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	root.size = Vector2i(1440,960)
	var game = load("res://scenes/maps/supply_routes.tscn").instantiate()
	root.add_child(game)
	await process_frame
	var rig = game.get_node("CameraRig")
	rig.focus_hq()
	for frame in range(180): rig.advance_camera(1.0/60)
	var network = game.get_node("DepotNetwork")
	network.select_depot(game.depot)
	var point := Vector3.ZERO
	for x in range(-20,21,5):
		for z in range(-20,21,5):
			var candidate: Vector3 = game.depot.global_position+Vector3(x,0,z)
			if network.can_place_size(candidate,game.depot,network.supply_rules.generator_footprint): point = candidate
	assert(point != Vector3.ZERO and network.construct_generator(point))
	var vehicle = game.get_node("Entities/Units/CargoVehicle")
	vehicle.set_selected(true)
	assert(vehicle.start_supply_route(game.depot,game.get_node("Entities/Buildings/Outpost"),60,40,false))
	for frame in range(10): await process_frame
	await RenderingServer.frame_post_draw
	TestOutput.save_png(self, root.get_texture().get_image(), "milestone3_runtime.png")
	# A second frame exercises saved placement feedback without mouse-input claims.
	game.get_node("DepotNetwork").set_process(false)
	game.get_node("ConstructionPreview").visible = true
	network.update_preview(game.depot.global_position+Vector3(0,0,18),true)
	for frame in range(4): await process_frame
	await RenderingServer.frame_post_draw
	TestOutput.save_png(self, root.get_texture().get_image(), "milestone3_preview.png")
	print("SUPPLY_RENDER_CHECK_PASSED")
	quit(TestOutput.exit_code())
