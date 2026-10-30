extends SceneTree
var game: Node3D
var hud: CanvasLayer
const TestOutput = preload("res://tests/test_output.gd")
const OUTPUT = ""
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> bool:
	if value: return true
	push_error(message); quit(1); return false
func click_at(point: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	root.push_input(motion,true)
	var event := InputEventMouseButton.new()
	event.position = point
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	root.push_input(event,true)
	# A human click spans multiple process frames. Do not emit button signals directly.
	for frame in range(5): await process_frame
	event = InputEventMouseButton.new()
	event.position = point
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = false
	root.push_input(event,true)
	for frame in range(3): await process_frame

func click(node: Control) -> void:
	var previous := Rect2()
	var stable := 0
	for frame in range(30):
		await process_frame
		var current := node.get_global_rect()
		if current == previous and node.is_visible_in_tree(): stable += 1
		else: stable = 0
		previous = current
		if stable >= 3: break
	await click_at(node.get_global_rect().get_center())
func shot(name: String) -> void:
	for frame in range(8): await process_frame
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	TestOutput.save_png(self, root.get_texture().get_image(), OUTPUT+name+".png")
func focus(point: Vector3, zoom: float = 55) -> void:
	var rig = game.get_node("CameraRig")
	rig.focus_position(point,zoom)
	for frame in range(180): rig.advance_camera(1.0/60)
func target(node: Node3D) -> Vector2:
	return game.get_viewport().get_camera_3d().unproject_position(node.global_position+Vector3.UP*1.5)
func right_click_at(point: Vector2) -> void:
	var motion := InputEventMouseMotion.new(); motion.position = point; root.push_input(motion,true)
	var event := InputEventMouseButton.new(); event.position = point; event.button_index = MOUSE_BUTTON_RIGHT; event.pressed = true
	root.push_input(event,true)
	for frame in range(5): await process_frame
	event = InputEventMouseButton.new(); event.position = point; event.button_index = MOUSE_BUTTON_RIGHT; event.pressed = false; root.push_input(event,true)
	for frame in range(3): await process_frame
func choose(option: OptionButton, index: int) -> void:
	await click(option)
	var popup := option.get_popup()
	var point := Vector2(popup.position)+Vector2(20,(index+0.5)*popup.size.y/popup.item_count)
	await click_at(point)
	if popup.visible: push_error("Popup did not close after item click")
func step(vehicle: Node3D, seconds: float) -> void:
	for i in range(ceili(seconds*60)): vehicle._process(1.0/60)
# Pin a payer the way a player does: Pin on the Build page, then click it on the map.
func pin(node: Node3D) -> void:
	if hud.global_pinned: await click(hud.build_menu.get_node("Actions/Pin"))
	await click(hud.build_menu.get_node("Actions/Pin"))
	await click_at(game.get_viewport().get_camera_3d().unproject_position(node.selection_point() if node.has_method("selection_point") else node.global_position))
func run() -> void:
	root.size = Vector2i(1280,900)
	game = load("res://scenes/maps/mobile_supply_exercise.tscn").instantiate()
	root.add_child(game); await process_frame
	game.set_process(false); hud = game.get_node("Interface")
	for group in ["units","depots","mines"]:
		for node in get_nodes_in_group(group): node.set_process(false)
	var rig = game.get_node("CameraRig"); rig.set_process(false)
	var truck = game.get_node("Entities/Units/MineSupply")
	var worker = game.get_node("Entities/Units/Infantry")
	focus(Vector3(153,0,155))
	await shot("mobile_supply_before")
	await click_at(rig.camera.unproject_position(truck.selection_point()))
	if not check(truck.is_selected,"Cargo selection failed"): return
	await click(hud.card.get_node("DeployCargo"))
	if not check(truck.supply_transition == "deploying","Deploy supplies GUI failed"): return
	step(truck,2.1)
	if not check(truck.supplies_available(),"Cargo deployment failed"): return
	await shot("mobile_supply_deployed")
	await click_at(rig.camera.unproject_position(worker.selection_point()))
	await click(hud.get_node("Bottom/Body/Header/GlobalBuild"))
	if not check(hud.pick_stops().is_empty(),"Pick stops shown before Pin"): return
	await pin(truck)
	if not check(hud.global_pinned and hud.global_payer == truck and hud.build_menu.visible,"Map pick did not pin the deployed cargo"): return
	await shot("mobile_supply_build")
	await click(hud.build_menu.get_node("Actions/Mine"))
	await click_at(rig.camera.unproject_position(Vector3(150,0,154)))
	for plan in get_nodes_in_group("construction_plans"): plan.try_complete()
	if not check(get_nodes_in_group("mines").size() == 2 and truck.stockpile.total() == 0 and game.depot.energy == 500 and game.depot.iron == 500,"Mobile Mine GUI payment failed"): return
	await click(hud.build_menu.get_node("Actions/Back"))
	truck.carried_energy = 10; truck.carried_iron = 10
	var mine = get_nodes_in_group("mines")[-1]; mine.take_damage(20); mine.set_process(false)
	await click(hud.card.get_node("Repair")); await click_at(target(mine))
	if not check(worker.repair_payer == truck,"Repair did not pay from the nearest covering stockpile"): return
	for frame in range(2400):
		worker._process(1.0/60)
		if mine.health == mine.max_health: break
	if not check(mine.health == mine.max_health and truck.energy == 6 and truck.iron == 8,"Mobile repair GUI failed"): return
	worker._stop_route(); worker.order = "idle"
	await click_at(rig.camera.unproject_position(truck.selection_point()))
	await click(hud.card.get_node("Move"))
	var held: Vector3 = truck.global_position
	await click_at(rig.camera.unproject_position(held+Vector3(0,0,4)))
	if not check(truck.supply_transition == "packing" and not truck.supplies_available(),"Move GUI did not pack supplies"): return
	step(truck,1)
	if not check(truck.global_position == held,"Move GUI left during packing"): return
	step(truck,3)
	if not check(truck.global_position != held,"Move GUI failed after packing"): return
	truck._stop_route(); truck.order = "idle"
	var forest = game.get_node("Entities/Units/ForestSupply")
	var forester = game.get_node("Entities/Units/ForestInfantry")
	focus(Vector3(100,0,28),42)
	await click_at(rig.camera.unproject_position(forest.selection_point()))
	await click(hud.card.get_node("DeployCargo")); step(forest,2.1)
	await click_at(rig.camera.unproject_position(forester.selection_point()))
	if not check(forester.is_selected,"Remote Infantry selection failed"): return
	# No picker: workers pay from and deliver to the nearest covering stockpile.
	if not check(SupplySource.candidates(get_tree(),forester.global_position,"player")[0] == forest and forest.name in hud.info.get_node("Details").text,"Nearest stockpile is not the deployed truck"): return
	await click(hud.card.get_node("Gather"))
	await click_at(rig.camera.unproject_position(game.ground.tile_to_world(Vector2i(345,275))))
	for frame in range(3600):
		forester._process(1.0/60)
		if forest.wood == 20: break
	if not check(forest.wood == 20 and forester.cargo == 0,"Gather card did not deliver to selected mobile source"): return
	forester.cargo_kind = &"wood"; forester.cargo = 10
	await click(hud.card.get_node("DropMaterials"))
	if not check(forester.cargo == 0 and get_nodes_in_group("material_piles").size() == 1,"Drop materials GUI failed"): return
	var pile = get_nodes_in_group("material_piles")[0]
	await shot("mobile_supply_pile")
	# Picking intersects the visible mesh, not the Label3D above it.
	var pile_mesh: MeshInstance3D = pile.get_node("Visuals/Crate")
	await click(hud.card.get_node("Gather")); await click_at(rig.camera.unproject_position(pile_mesh.global_transform*pile_mesh.get_aabb().get_center()))
	for frame in range(3600):
		forester._process(1.0/60)
		if forest.wood == 30: break
	if not check(forest.wood == 30 and get_nodes_in_group("material_piles").is_empty(),"Pile gather GUI did not stockpile materials"): return
	forester.cargo_kind = &"iron"; forester.cargo = 5
	await right_click_at(rig.camera.unproject_position(forest.selection_point()))
	if not check(forester.order == "return" and forester.return_depot == forest,"Right-click truck did not order delivery"): return
	for frame in range(600): forester._process(1.0/60)
	if not check(forest.iron == 5 and forester.cargo == 0,"Right-click truck delivery failed"): return
	await shot("mobile_supply_forestry")
	# Exercise a mobile-funded Barracks and its operating-Depot popup in the actual HUD.
	var train = game.get_node("Entities/Units/Train")
	train.carried_energy = 200; train.carried_iron = 90
	focus(Vector3(170,0,157),60)
	await click_at(rig.camera.unproject_position(train.selection_point()))
	await click(hud.card.get_node("DeployCargo")); step(train,2.1)
	await click_at(rig.camera.unproject_position(worker.selection_point()))
	await click(hud.get_node("Bottom/Body/Header/GlobalBuild"))
	await pin(train)
	if not check(hud.global_payer == train,"Map pick did not pin the deployed Train"): return
	var point := Vector3.ZERO
	var network = game.get_node("DepotNetwork")
	for x in range(-12,13,3):
		for z in range(-12,13,3):
			var candidate: Vector3 = train.global_position+Vector3(x,0,z)
			if network.can_place_size(candidate,train,Vector2i(5,5)): point = candidate
	await click(hud.build_menu.get_node("Actions/Barracks"))
	await click_at(rig.camera.unproject_position(point))
	for plan in get_nodes_in_group("construction_plans"): plan.try_complete()
	if not check(get_nodes_in_group("production_buildings").size() == 1 and train.energy == 100 and train.iron == 45,"Train-funded Barracks GUI failed"): return
	var building = get_nodes_in_group("production_buildings")[0]; building.set_process(false)
	await click(hud.build_menu.get_node("Actions/Back"))
	await click_at(target(building))
	if not check(hud.shown == building and building.assigned_depot == null,"Remote building selection/assignment wrong"): return
	await choose(hud.context.get_node("AssignedSource"),hud.assignment_sources.find(game.depot))
	if not check(building.assigned_depot == game.depot,"Operating Depot popup failed"): return
	await click(hud.card.get_node("PrintInfantry"))
	if not check(building.queue == 1 and game.depot.energy == 400 and game.depot.iron == 480 and train.energy == 100 and train.iron == 45,"Operating production charged mobile stock or ignored Depot choice"): return
	train._update_display(); building._process(0)
	await shot("mobile_supply_operating_depot")
	root.size = Vector2i(1440,960); await shot("mobile_supply_wide")
	print("MOBILE_SUPPLY_RUNTIME_CHECKS_PASSED"); quit(TestOutput.exit_code())
