extends SceneTree
# Rendered: the authored Depot Truck, the authored crate with resource bands, and the fold-out deploy
# (docs/DEPOT_MODEL.md). Saves depot_truck, depot_crates, depot_fold_0-3 and depot_build_0-5.
const TestOutput = preload("res://tests/test_output.gd")
var game: Node3D
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> bool:
	if value: return true
	push_error(message); quit(1); return false
func shot(file: String) -> void:
	for frame in range(6): await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(TestOutput.path(file))
func run() -> void:
	root.size = Vector2i(1280,900)
	game = load("res://scenes/maps/resource_skirmish.tscn").instantiate()
	root.add_child(game)
	for frame in range(3): await process_frame
	game.set_process(false)
	for unit in get_nodes_in_group("units"): unit.set_process(false)
	var network = game.get_node("DepotNetwork")
	var rig = game.get_node("CameraRig")
	rig.set_process(false)
	var start: Vector2i = game.ground.find_buildable_footprint(Vector2i(220,170),Vector2i(30,30))+Vector2i(10,10)
	var site: Vector3 = game.ground.tile_to_world(start+Vector2i(5,5))
	var truck: Node3D = network.truck_scene.instantiate()
	truck.position = site
	game.get_node("Entities/Units").add_child(truck)
	truck.set_process(false)
	truck.get_node("Visuals").rotation.y = deg_to_rad(-70)
	truck.set_selected(true)
	rig.focus_position(site,34)
	for frame in range(180): rig.advance_camera(1.0/60)
	await shot("depot_truck.png")
	# One crate of each kind, plus an empty one, on neighbouring tiles.
	var kinds := ["energy","iron","wood","coal",""]
	var crates: Array[Node3D] = []
	for i in range(kinds.size()):
		var crate: Node3D = CrateYard.spawn(self,start+Vector2i(2+i,14),StringName(kinds[i]),0 if kinds[i].is_empty() else 25,"player")
		crates.append(crate)
	rig.focus_position(game.ground.tile_to_world(start+Vector2i(4,14)),9)
	for frame in range(180): rig.advance_camera(1.0/60)
	await shot("depot_crates.png")
	for crate in crates: crate.free()
	rig.focus_position(site,38)
	for frame in range(180): rig.advance_camera(1.0/60)
	if not check(network.deploy_selected_truck(),"Deploy failed"): return
	var depot: Node3D = network.selected
	var fold: Node3D = depot.get_node("Visuals/Model")
	await shot("depot_fold_0.png")
	await create_timer(fold.line_up_seconds+0.2).timeout
	if not check(fold.player.is_playing(),"Fold-out did not start"): return
	fold.player.pause()
	for step in [[1,4.0],[2,7.0],[3,9.99]]:
		fold.player.seek(step[1],true)
		await shot("depot_fold_%d.png" % step[0])
	# Production: the tractor pulls out and the trailer is built beside the Depot.
	depot.set_process(false)
	depot.energy = 2000; depot.iron = 2000
	for cell in depot.truck_side_cells(): game.ground.set_tile_feature(cell,"occupied_by",null)
	fold.player.seek(fold.player.get_animation(&"deploy").length,true)
	if not check(depot.request_truck(),"Truck order refused"): return
	depot._process(0.1)
	if not check(not depot.truck_cells.is_empty(),"Truck side blocked in the render check"): return
	for step in [[0,3.0],[1,6.25],[2,8.5],[3,10.5],[4,14.1]]:
		depot.progress = step[1]
		fold.show_truck(step[1])
		await shot("depot_build_%d.png" % step[0])
	depot.progress = depot.current_seconds()
	depot._process(0.1)
	if not check(depot.queue == 0,"Truck not delivered"): return
	await shot("depot_build_5.png")
	print("DEPOT_TRUCK_MODEL_RUNTIME_CHECK_PASSED"); quit(TestOutput.exit_code())
