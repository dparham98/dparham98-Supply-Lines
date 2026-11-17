extends SceneTree
# Headless: track planning by real key presses and clicks (docs/RAIL_PLANNING.md). The Build page stays open
# while laying, and its tiles use R and G too, so the keys must reach track laying first. Tab cycles the piece,
# R turns it 90 degrees, G picks a fork's joining end, a click plans a piece, Backspace takes it back and Enter
# lays the plan once it connects two targets.
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
func look_at_end(end: Dictionary) -> Vector2:
	rig.focus_position(end.position,45)
	for frame in range(180): rig.advance_camera(1.0/60)
	return rig.camera.unproject_position(end.position+end.out*1.0)
func free_end(piece: Node, index: int) -> Dictionary:
	for end in rails.free_ends("player"):
		if end.piece == piece and end.end == index: return end
	return {}
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
	if not check(game.placing_rail and game.rail_piece == "straight","R should start laying track from the Build page"): return
	if not check(hud.build_menu.get_node("Actions/Rail").is_visible_in_tree(),"The test needs the Rail tile on screen"): return
	# While laying, Tab cycles every piece and comes back round, and does not move GUI focus.
	for piece in ["left","right","fork_left","fork_right","straight"]:
		await press(KEY_TAB)
		if not check(game.rail_piece == piece,"Tab should reach %s, got %s" % [piece,game.rail_piece]): return
	# R turns a piece 90 degrees, four times round to where it began.
	var heading: Vector3 = game.rail_heading
	await press(KEY_R)
	if not check(game.rail_heading.is_equal_approx(Vector3(-heading.z,0,heading.x)) and game.placing_rail and game.rail_piece == "straight","R should turn the piece 90 degrees"): return
	for i in range(3): await press(KEY_R)
	if not check(game.rail_heading.is_equal_approx(heading),"Four turns should come back round"): return
	# G does nothing on a straight, and must not start a Generator.
	await press(KEY_G)
	if not check(game.placing_rail and game.global_plan_kind.is_empty() and game.rail_fork_join == 0,"G on a straight should do nothing"): return
	# A curve chosen by key is the piece a click plans; nothing is laid or paid yet.
	var west: Dictionary = free_end(game.get_node("Entities/Rails/Track0"),0)
	if not check(not west.is_empty(),"Fixture has no free west end"): return
	await press(KEY_TAB)
	var before: int = rails.pieces.size()
	var payer: Node3D = game.get_node("Entities/Buildings/Depot")
	var iron: int = payer.iron
	await click_at(await look_at_end(west))
	if not check(rails.pending.size() == 1 and rails.pending[0].kind == "curve" and rails.pieces.size() == before,"A click after Tab should plan a curve, not lay it"): return
	if not check(game.placing_rail and game.rail_piece == "left","Planning should stay armed with the same piece"): return
	# Backspace takes it back.
	await press(KEY_BACKSPACE)
	if not check(rails.pending.is_empty() and game.placing_rail,"Backspace should remove the planned piece"): return
	# At a track end R mirrors a curve to the other hand and back, without turning it. Free, it turns it.
	rails.set_process(false)
	rails.preview_snapped = true
	var turned_to: Vector3 = game.rail_heading
	await press(KEY_R)
	if not check(game.rail_piece == "right" and game.rail_heading.is_equal_approx(turned_to),"R at a track end should mirror the left curve: %s" % game.rail_piece): return
	await press(KEY_R)
	if not check(game.rail_piece == "left","R again should mirror it back"): return
	rails.preview_snapped = false
	await press(KEY_R)
	if not check(game.rail_piece == "left" and not game.rail_heading.is_equal_approx(turned_to),"A free curve should turn, not mirror"): return
	for i in range(3): await press(KEY_R)
	rails.set_process(true)
	await click_at(await look_at_end(west))
	if not check(rails.pending.size() == 1,"The curve should plan again"): return
	# On to a fork: G walks its three joining ends and stays in track laying.
	for i in range(2): await press(KEY_TAB)
	if not check(game.rail_piece == "fork_left","Tab should reach the left fork"): return
	for join in [1,2,0,1,2]:
		await press(KEY_G)
		if not check(game.placing_rail and game.global_plan_kind.is_empty() and game.rail_fork_join == join,"G should move a fork to join %d" % join): return
	# The fixture's track joins both Depots, so the curve joined to it already connects two targets: Enter lays
	# it and finishes. The Build page has its keys back.
	if not check(rails.plan_blocker().is_empty(),"The plan joined to the fixture line should connect two Depots: "+rails.plan_blocker()): return
	await press(KEY_ENTER)
	if not check(rails.pieces.size() == before+1 and rails.pieces[before].kind == "curve" and rails.pending.is_empty() and not game.placing_rail,"Enter should lay the plan and finish laying"): return
	if not check(payer.iron < iron or game.get_node("Entities/Buildings/EastDepot").iron < iron,"A Depot should pay for the laid track"): return
	await process_frame
	await press(KEY_G)
	if not check(not game.placing_rail and game.global_plan_kind == &"generator","G should be the Generator tile again"): return
	print("RAIL_KEYS_TEST_PASSED"); quit()
