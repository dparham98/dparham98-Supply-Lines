extends SceneTree
var game: Node3D
var hud: CanvasLayer
var worker: Node3D
var mine: Node3D
const OUTPUT = "C:/Users/video/.codex/.chatgpt-projects/g-p-6ad16a23380c8191877dbcafdb316068/"
func _initialize() -> void:
	call_deferred("run")
func focus(point: Vector3) -> void:
	var rig = game.get_node("CameraRig")
	rig.focus_position(point)
	for frame in range(180): rig.advance_camera(1.0/60)
func select_unit(unit: Node3D) -> void:
	game.get_node("DepotNetwork").select_depot(null)
	for candidate in get_nodes_in_group("units"): candidate.set_selected(candidate == unit)
	hud._process(0)
func shot(name: String) -> void:
	hud._process(0)
	for frame in range(6): await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUTPUT+name+".png")
func step() -> void:
	worker._process(1.0/60)
	mine._process(1.0/60)
func run() -> void:
	root.size = Vector2i(1280,900)
	game = load("res://scenes/maps/engineering_exercise.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	hud = game.get_node("Interface")
	worker = game.get_node("Entities/Units/Infantry")
	mine = game.get_node("Entities/Buildings/IronMine")
	var wood = game.get_node("Entities/Resources/WoodStand")
	var generator = game.get_node("Entities/Buildings/DamagedGenerator")
	for unit in get_nodes_in_group("units"): unit.set_process(false)
	for building in get_nodes_in_group("selectable_buildings"): building.set_process(false)
	game.get_node("CameraRig").set_process(false)
	select_unit(worker)
	focus(generator.global_position)
	await shot("engineering_commands")
	worker.command_repair(generator)
	for i in range(90*60):
		step()
		if generator.health >= 220: break
	await shot("engineering_repair")
	worker.command_gather(wood)
	for i in range(90*60):
		step()
		if worker.cargo >= 10: break
	focus(wood.global_position)
	await shot("engineering_wood")
	worker.command_gather(mine)
	for i in range(90*60):
		step()
		if worker.cargo >= 10: break
	worker._stop_route()
	for unit in get_nodes_in_group("units"): unit.set_selected(false)
	game.selected_building = mine
	focus(mine.global_position)
	await shot("engineering_mine")
	var network = game.get_node("DepotNetwork")
	var start = game.ground.find_buildable_footprint(Vector2i(450,440),Vector2i(8,8))
	network.establish(game.ground.tile_to_world(start+Vector2i(4,4)),0,0)
	var cargo = network.cargo_scene.instantiate()
	cargo.position = game.depot.global_position+Vector3(0,0,8)
	game.get_node("Entities/Units").add_child(cargo)
	cargo.set_process(false)
	select_unit(cargo)
	hud.supply.get_node("Amounts/Energy").value = 0
	hud.supply.get_node("Amounts/Iron").value = 0
	hud.supply.get_node("Amounts/Wood").value = 10
	await shot("engineering_cargo_wood")
	root.size = Vector2i(1440,960)
	await shot("engineering_wide")
	print("ENGINEERING_RENDER_CHECK_PASSED")
	quit()
