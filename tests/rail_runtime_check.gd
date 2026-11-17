extends SceneTree
var game: Node3D
var hud: CanvasLayer
const TestOutput = preload("res://tests/test_output.gd")
const OUTPUT = ""
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> bool:
	if value: return true
	push_error(message); quit(1); return false
func click_at(point: Vector2, shifted := false) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	root.push_input(motion,true)
	var event := InputEventMouseButton.new()
	event.position = point
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.shift_pressed = shifted
	root.push_input(event,true)
	# A human click spans multiple process frames. Do not emit button signals directly.
	for frame in range(5): await process_frame
	event = InputEventMouseButton.new()
	event.position = point
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = false
	root.push_input(event,true)
	for frame in range(3): await process_frame

func drag(from: Vector2, to: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = from
	root.push_input(motion,true)
	var press := InputEventMouseButton.new()
	press.position = from; press.button_index = MOUSE_BUTTON_LEFT; press.pressed = true
	root.push_input(press,true)
	for frame in range(3): await process_frame
	for i in range(1,9):
		motion = InputEventMouseMotion.new()
		motion.position = from.lerp(to,i/8.0); motion.button_mask = MOUSE_BUTTON_MASK_LEFT
		root.push_input(motion,true)
		await process_frame
	var release := InputEventMouseButton.new()
	release.position = to; release.button_index = MOUSE_BUTTON_LEFT; release.pressed = false
	root.push_input(release,true)
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
func shift(down: bool) -> void:
	var key := InputEventKey.new()
	key.keycode = KEY_SHIFT; key.physical_keycode = KEY_SHIFT; key.pressed = down
	Input.parse_input_event(key); Input.flush_buffered_events()
func run() -> void:
	root.size = Vector2i(1280,900)
	game = load("res://scenes/maps/rail_exercise.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	hud = game.get_node("Interface")
	for group in ["units","depots"]:
		for node in get_nodes_in_group(group): node.set_process(false)
	var source = game.depot
	var destination = game.get_node("Entities/Buildings/EastDepot")
	var rails = game.get_node("RailNetwork")
	var network = game.get_node("DepotNetwork")
	var rig = game.get_node("CameraRig")
	rig.set_process(false)
	rig.focus_position(Vector3(185,0,150),55)
	for frame in range(180): rig.advance_camera(1.0/60)
	await click(hud.card.get_node("PrintTrain"))
	if not check(source.queue == 1 and source.pending[0] == "train" and source.energy == 350 and source.iron == 470,"Print Train GUI payment failed"): return
	await shot("rail_depot_card")
	await click(hud.get_node("Bottom/Body/Header/GlobalBuild"))
	await click(hud.build_menu.get_node("Actions/Rail"))
	if not check(game.placing_rail,"Rail Build button did not start laying track"): return
	# Connecting two buildings (docs/RAIL_PLANNING.md): click the Depot, then a build site; the game suggests the
	# track between them. Nothing is laid or paid until Enter lays it; the Depot then pays by length.
	var iron_before: int = source.iron
	var pieces_before: int = rails.pieces.size()
	var site: Node3D = null
	for offset in [Vector3(16,0,-18),Vector3(12,0,-20),Vector3(-16,0,-18),Vector3(20,0,-16)]:
		site = network.queue_plan(source.global_position+offset,&"generator")
		if site != null: break
	if not check(site != null,"No build site to connect"): return
	site.set_process(false)
	await click_at(rig.camera.unproject_position(source.global_position))
	if not check(rails.route_from == source and rails.pending.is_empty() and game.placing_rail,"A click on the Depot should pick it first: %s" % rails.route_from): return
	await shot("rail_pick")
	await click_at(rig.camera.unproject_position(site.global_position))
	if not check(rails.route_to == site and not rails.pending.is_empty() and rails.pieces.size() == pieces_before and source.iron == iron_before,"A click on the site should suggest track, not lay it"): return
	if not check(rails.plan_blocker().is_empty() and rails.plan_targets().has(source) and rails.plan_targets().has(site),"The suggested track should connect the Depot and the site: "+rails.plan_blocker()): return
	await shot("rail_plan")
	# Dragging the suggested track with the mouse pulls it through the cursor, adding pieces as needed.
	var grab_entry: Dictionary = rails.pending[rails.pending.size()/2]
	var grab_piece: Node3D = rails.probe(grab_entry.kind)
	var grab: Vector3 = (grab_entry.transform as Transform3D)*grab_piece.local_point(grab_piece.length()*0.5)
	var drop: Vector3 = grab+Vector3(-16,0,-12)
	await drag(rig.camera.unproject_position(grab),rig.camera.unproject_position(drop))
	if not check(rails.route_via != null and rails.near_plan(drop,2.6) and game.placing_rail,"Dragging the track should pull it through the cursor: %s, %d pieces" % [rails.route_via,rails.pending.size()]): return
	if not check(rails.plan_targets().has(source) and rails.plan_targets().has(site),"The dragged track should still connect the Depot and the site"): return
	var planned: int = rails.pending.size()
	var cost: int = rails.plan_cost()
	await shot("rail_drag")
	var enter := InputEventKey.new()
	enter.keycode = KEY_ENTER; enter.physical_keycode = KEY_ENTER; enter.pressed = true
	root.push_input(enter,true)
	for frame in range(3): await process_frame
	if not check(rails.pieces.size() == pieces_before+planned and rails.pending.is_empty() and source.iron == iron_before-cost and not game.placing_rail,"Enter should lay and pay the suggested track and finish laying"): return
	await shot("rail_construction")
	game.placing_rail = true
	# A fork on the fixture's west end, for art review.
	var west := {}
	for end in rails.free_ends("player"):
		if end.piece == game.get_node("Entities/Rails/Track0") and end.end == 0: west = end
	var fork = rails.fork_left_scene.instantiate()
	fork.assigned_depot = source; fork.transform = rails.transform_for("fork_left",west.position,west.out)
	game.get_node("Entities/Rails").add_child(fork)
	if not check(rails.pieces.has(fork) and fork.end_count() == 3 and not rails.connection(fork,0).is_empty(),"Fork not laid on the fixture's west end"): return
	rig.focus_position(fork.global_position,45)
	for frame in range(180): rig.advance_camera(1.0/60)
	await shot("rail_fork")
	rig.focus_position(Vector3(185,0,150),55)
	for frame in range(180): rig.advance_camera(1.0/60)
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE; escape.pressed = true
	root.push_input(escape,true)
	for frame in range(3): await process_frame
	if not check(not game.placing_rail,"Esc failed to finish rail placement"): return
	if hud.build_menu.visible: await click(hud.build_menu.get_node("Actions/Back"))
	var train = game.get_node("Entities/Units/Train")
	await click_at(rig.camera.unproject_position(train.selection_point()))
	if not check(train.is_selected and hud.card.get_node("Load").visible and hud.object_name(train) == "Train","Train selection did not show crate tiles"): return
	# Crates are map objects: two energy crates and one iron crate packed beside the source Depot.
	for kind in [&"energy",&"energy",&"iron"]: CrateYard.pack(source,kind)
	if not check(CrateYard.beside(source).size() == 3,"Crates were not set down beside the source Depot"): return
	var energy: int = destination.energy
	var iron: int = destination.iron
	await click(hud.card.get_node("Load"))
	if not check(hud.pick.visible and not hud.card.visible,"Load did not show the map prompt"): return
	await shot("rail_pick_prompt")
	var map = hud.get_node("Bottom/Body/Row/MapColumn/Map")
	await click_at(map.get_global_rect().position+map.world_to_map(source.global_position))
	if not check(train.order == "load" and train.job_target == source,"Minimap stop click did not order Load"): return
	await click(hud.card.get_node("Unload"))
	shift(true)
	hud.pick_stop(destination,Input.is_key_pressed(KEY_SHIFT))
	shift(false)
	game.pending_unit_command = ""
	if not check(train.order == "load" and train.shipment_pair() == [source,destination],"Train Load/Unload GUI failed"): return
	for frame in range(600):
		train._process(1.0/60)
		if train.order == "unload": break
	await shot("rail_train_loaded")
	if not check(train.crates.size() == 3 and CrateYard.beside(source).is_empty(),"Train did not load the crates beside the Depot"): return
	for frame in range(1200):
		train._process(1.0/60)
		if train.order == "idle": break
	if not check(train.order == "idle" and destination.energy == energy+50 and destination.iron == iron+25,"GUI-ordered train failed crate delivery"): return
	await shot("rail_train_delivered")
	root.size = Vector2i(1440,960)
	await shot("rail_train_wide")
	if not check(hud.info.get_node("Details").get_global_rect().end.y <= root.size.y,"Train HUD overflow"): return
	print("RAIL_RUNTIME_CHECKS_PASSED")
	quit(TestOutput.exit_code())
