extends SceneTree
# Headless: connecting two buildings with rail by real key presses and clicks (docs/RAIL_PLANNING.md). A click
# picks a building, the second pick suggests the track, Backspace takes a pick back and Enter lays the track. The
# Build page stays open while laying, so Enter and Backspace must reach track laying first.
var game: Node3D
var hud: CanvasLayer
var rails: Node
var rig: Node
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> bool:
	if value: return true
	push_error(message); quit(1); return false
func press(code: int) -> void:
	for down in [true,false]:
		var key := InputEventKey.new()
		key.keycode = code; key.physical_keycode = code; key.pressed = down
		Input.parse_input_event(key); Input.flush_buffered_events()
		await process_frame
func click_at(point: Vector2, shift := false) -> void:
	for down in [true,false]:
		var event := InputEventMouseButton.new()
		event.position = point; event.button_index = MOUSE_BUTTON_LEFT; event.pressed = down; event.shift_pressed = shift
		root.push_input(event,true)
		for frame in range(3): await process_frame
func look_at(point: Vector3) -> Vector2:
	rig.focus_position(point,45)
	for frame in range(180): rig.advance_camera(1.0/60)
	return rig.camera.unproject_position(point)
func run() -> void:
	root.size = Vector2i(1280,900)
	# A mechanics check on a map laid out for the old 35 m Depot range (docs/DEPOT_RANGE.md).
	var old_range: DepotRules = load("res://assets/economy/depot_rules.tres")
	old_range.construction_radius = 35.0
	game = load("res://scenes/maps/rail_exercise.tscn").instantiate()
	root.add_child(game)
	for frame in range(4): await process_frame
	game.set_process(false)
	hud = game.get_node("Interface")
	rails = game.get_node("RailNetwork")
	rig = game.get_node("CameraRig")
	rig.set_process(false)
	for group in ["units","depots"]:
		for node in get_nodes_in_group(group): node.set_process(false)
	hud.open_global_build()
	await process_frame
	# Before laying starts, R is still the Rail tile.
	await press(KEY_R)
	if not check(game.placing_rail and rails.route_from == null,"R should start laying track from the Build page"): return
	if not check(hud.build_menu.get_node("Actions/Rail").is_visible_in_tree(),"The test needs the Rail tile on screen"): return
	var depot: Node3D = game.get_node("Entities/Buildings/Depot")
	var east: Node3D = game.get_node("Entities/Buildings/EastDepot")
	var before: int = rails.pieces.size()
	var iron: int = depot.iron+east.iron
	# A click on open ground picks nothing; a click on a Depot picks it as the first building.
	await click_at(await look_at(depot.global_position+Vector3(0,0,-60)))
	if not check(rails.route_from == null and game.placing_rail,"Open ground should pick nothing"): return
	await click_at(await look_at(depot.global_position))
	if not check(rails.route_from == depot and rails.pending.is_empty(),"A click on the Depot should pick it: %s" % rails.route_from): return
	# Backspace takes the pick back.
	await press(KEY_BACKSPACE)
	if not check(rails.route_from == null and game.placing_rail,"Backspace should drop the first pick"): return
	await click_at(await look_at(depot.global_position))
	# The second building gets a suggested path, planned but not laid or paid.
	await click_at(await look_at(east.global_position))
	if not check(rails.route_to == east and not rails.pending.is_empty() and rails.pieces.size() == before and depot.iron+east.iron == iron,"A click on the second Depot should suggest track, not lay it"): return
	if not check(rails.plan_blocker().is_empty(),"The suggested track should be layable: "+rails.plan_blocker()): return
	# Backspace drops the second pick and its track, keeping the first.
	await press(KEY_BACKSPACE)
	if not check(rails.route_from == depot and rails.route_to == null and rails.pending.is_empty(),"Backspace should drop the second pick and its track"): return
	await click_at(await look_at(east.global_position))
	var planned: int = rails.pending.size()
	if not check(planned > 0,"The track should be suggested again"): return
	# Enter lays it and finishes; the Build page has its keys back.
	await press(KEY_ENTER)
	if not check(rails.pieces.size() == before+planned and rails.pending.is_empty() and not game.placing_rail and rails.route_from == null,"Enter should lay the track and finish laying"): return
	if not check(depot.iron+east.iron < iron,"A Depot should pay for the laid track"): return
	await process_frame
	await press(KEY_G)
	if not check(not game.placing_rail and game.global_plan_kind == &"generator","G should be the Generator tile again"): return
	print("RAIL_KEYS_TEST_PASSED"); quit()
