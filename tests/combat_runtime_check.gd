extends SceneTree
const TestOutput = preload("res://tests/test_output.gd")
var game: Node3D
func _initialize() -> void: call_deferred("run")
func run() -> void:
	root.size = Vector2i(1280,900)
	game = load("res://scenes/maps/resource_skirmish.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	for group in ["units","selectable_buildings"]:
		for node in get_nodes_in_group(group): node.set_process(false)
	var rig = game.get_node("CameraRig")
	rig.set_process(false)
	var hud = game.get_node("Interface")
	game.get_node("DepotNetwork").select_depot(null)
	for id in ["tank","grenadier"]:
		var unit = load("res://scenes/gameplay/"+id+".tscn").instantiate()
		unit.position = Vector3(180,0,180)
		game.add_child(unit)
		unit.set_process(false)
		for node in get_nodes_in_group("units"): node.set_selected(node == unit)
		rig.focus_position(unit.global_position)
		for i in range(180): rig.advance_camera(1.0/60)
		hud._process(0)
		for i in range(8): await process_frame
		await RenderingServer.frame_post_draw
		var details = hud.info.get_node("Details")
		assert(details.get_global_rect().end.y <= root.size.y)
		TestOutput.save_png(self, root.get_texture().get_image(), "combat_"+id+".png")
		unit.free()
	print("COMBAT_RENDER_CHECK_PASSED")
	quit(TestOutput.exit_code())
