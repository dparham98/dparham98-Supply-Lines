extends SceneTree
## Rendered (docs/KNIGHTS_ECONOMY.md, House): a House beside a Chapterhouse, seen from the RTS camera's usual
## angle. The House's front door and loft window should face the camera (+Z), as the Chapterhouse's portal does.
const TestOutput = preload("res://tests/test_output.gd")
func _initialize() -> void: call_deferred("run")
func run() -> void:
	root.size = Vector2i(1280,900)
	var game: Node3D = load("res://scenes/maps/arthurian_skirmish.tscn").instantiate()
	root.add_child(game)
	for f in range(3): await process_frame
	for name in ["EnemyPlayer","KnightsPlayer"]:
		var ai = game.get_node_or_null(name)
		if ai != null: ai.set_process(false)
	var rig = game.get_node("CameraRig")
	rig.set_process(false)
	var keep: Node3D = null
	for node in get_nodes_in_group("keeps"):
		if node.team == "player": keep = node
	var spot: Vector3 = keep.global_position+Vector3(30,0,20)
	for pair in [["house",Vector3(-3,0,0)],["chapterhouse",Vector3(5,0,0)]]:
		var b: Node3D = load("res://scenes/gameplay/%s.tscn" % pair[0]).instantiate()
		b.set_script(null)
		game.get_node("Entities").add_child(b)
		b.global_position = spot+pair[1]
		if pair[0] == "house":
			# The GLB's door faces its -Z, so the Rig is turned half round to put it on +Z.
			var door: Vector3 = -b.get_node("Visuals/Model/Rig").global_basis.z
			if not door.is_equal_approx(Vector3.BACK):
				push_error("The House's door should face +Z, toward the camera (faces %s)" % door); quit(1); return
	rig.focus_position(spot,22.0)
	for _f in range(180): rig.advance_camera(1.0/60.0)
	for f in range(4): await process_frame
	await RenderingServer.frame_post_draw
	TestOutput.save_png(self,root.get_texture().get_image(),"house_facing.png")
	print("HOUSE_FACING_CHECK_PASSED")
	quit(0)
