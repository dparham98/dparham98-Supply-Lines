extends SceneTree
var game: Node3D
var hud: CanvasLayer
const TestOutput = preload("res://tests/test_output.gd")
const OUTPUT = ""
func _initialize() -> void:
	call_deferred("run")
func shot(name: String) -> void:
	for frame in range(6): await process_frame
	await RenderingServer.frame_post_draw
	TestOutput.save_png(self, root.get_texture().get_image(), OUTPUT+name+".png")
func run() -> void:
	root.size = Vector2i(1280,900)
	game = load("res://scenes/maps/resource_skirmish.tscn").instantiate()
	root.add_child(game)
	hud = game.get_node("Interface")
	await process_frame
	var rig = game.get_node("CameraRig")
	rig.set_process(false)
	rig.focus_hq()
	for frame in range(180): rig.advance_camera(1.0/60)
	game.depot.storage_capacity = 10000
	game.depot.energy = 2000
	game.depot.iron = 2000
	var network = game.get_node("DepotNetwork")
	hud._process(0)
	hud.get_node("Bottom/Body/Header/GlobalBuild").pressed.emit()
	await shot("production_depot_build")
	for id in [&"barracks",&"tank_factory"]:
		var point := Vector3.ZERO
		var preview = network.production_scene(id).instantiate()
		var size: Vector2i = preview.stats.footprint
		preview.free()
		for x in range(-20,21,5):
			for z in range(-20,21,5):
				var candidate: Vector3 = game.depot.global_position+Vector3(x,0,z)
				if network.can_place_size(candidate,game.depot,size): point = candidate
		assert(point != Vector3.ZERO and network.construct_production(point,id))
	hud.close_build()
	var buildings = get_nodes_in_group("production_buildings")
	for building in buildings:
		network.select_depot(null)
		game.selected_building = building
		for frame in range(180): rig.advance_camera(1.0/60)
		await shot("production_"+str(building.stats.building_id))
		game.depot.storage_capacity = 10000
		game.depot.energy = 2000
		game.depot.iron = 2000
		for scene in building.stats.unit_scenes:
			assert(building.request_unit(building.unit_stats_for(scene).unit_id))
			building._process(3.1)
	root.size = Vector2i(1440,960)
	await shot("production_roster_wide")
	print("PRODUCTION_RENDER_CHECK_PASSED")
	quit(TestOutput.exit_code())
