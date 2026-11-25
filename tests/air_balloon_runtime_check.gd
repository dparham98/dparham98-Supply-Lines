extends SceneTree
## Rendered (docs/AIR_BALLOON.md): the Air Balloon lifting off the Keep's dock with the Keep's Launch balloon tile, in
## flight with its card, and the four crates it set down.
const TestOutput = preload("res://tests/test_output.gd")
var game: Node3D
var hud: CanvasLayer
var rig: Node3D
func _initialize() -> void: call_deferred("run")
func shot(name: String) -> void:
	hud._process(0)
	for _frame in range(6): await process_frame
	await RenderingServer.frame_post_draw
	TestOutput.save_png(self,root.get_texture().get_image(),name+".png")
func look(point: Vector3, distance: float) -> void:
	rig.focus_position(point,distance)
	for _f in range(180): rig.advance_camera(1.0/60.0)
func run() -> void:
	root.size = Vector2i(1280,900)
	game = load("res://scenes/maps/arthurian_skirmish.tscn").instantiate()
	root.add_child(game)
	await process_frame
	hud = game.get_node("Interface")
	rig = game.get_node("CameraRig")
	rig.set_process(false)
	var keep := game.get_node("Entities/Buildings/Keep")
	for kind in [&"wood",&"wood",&"iron",&"iron"]:
		keep.stockpile.deposit(kind,ResourceStockpile.CRATE)
		CrateYard.pack(keep,kind)
	keep.stockpile.deposit(&"wood",50)
	var drop: Vector3 = keep.global_position+Vector3(SupplySource.radius(keep)+10.0,0,4.0)
	if not keep.launch_balloon(drop): push_error("The Keep should launch"); quit(1); return
	var balloon: Node3D = get_nodes_in_group("air_balloons")[-1]
	# 1. Lifting off the Keep, the Keep selected.
	for i in range(45): await process_frame
	look(keep.global_position+Vector3(0,0,4),30.0)
	game.selected_building = keep
	await shot("air_balloon_liftoff")
	# 2. In flight, the balloon selected.
	while is_instance_valid(balloon) and balloon.global_position.distance_to(keep.global_position) < 14.0: await process_frame
	game.selected_building = null

	for u in get_nodes_in_group("units"): u.set_selected(u == balloon)
	look(balloon.global_position,28.0)
	await shot("air_balloon_flight")
	# 3. Landed: the four crates at the drop point.
	var waited := 0
	while is_instance_valid(balloon) and waited < 60*40: await process_frame; waited += 1
	look(drop,22.0)
	await shot("air_balloon_crates")
	print("AIR_BALLOON_RUNTIME_CHECK_PASSED")
	quit(TestOutput.exit_code())
