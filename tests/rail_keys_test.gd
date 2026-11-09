extends SceneTree
# Headless: track laying by real key presses and clicks. The Build page stays open while laying, and its
# tiles use R and G too, so the keys must reach track laying first (docs/MAGLEV_TRACKS.md).
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
func click_at(point: Vector2) -> void:
	for down in [true,false]:
		var event := InputEventMouseButton.new()
		event.position = point; event.button_index = MOUSE_BUTTON_LEFT; event.pressed = down
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
	# While laying, R cycles every piece and comes back round.
	for piece in ["left","right","fork_left","fork_right","straight"]:
		await press(KEY_R)
		if not check(game.rail_piece == piece,"R should reach %s, got %s" % [piece,game.rail_piece]): return
	# F turns a free piece.
	var heading: Vector3 = game.rail_heading
	await press(KEY_F)
	if not check(game.rail_heading.is_equal_approx(Vector3(-heading.z,0,heading.x)) and game.placing_rail,"F should turn a free piece"): return
	# G does nothing on a straight, and must not start a Generator.
	await press(KEY_G)
	if not check(game.placing_rail and game.global_plan_kind.is_empty() and game.rail_fork_join == 0,"G on a straight should do nothing"): return
	# A curve chosen by key is the piece a click lays.
	var west: Dictionary = free_end(game.get_node("Entities/Rails/Track0"),0)
	if not check(not west.is_empty(),"Fixture has no free west end"): return
	await press(KEY_R)
	var before: int = rails.pieces.size()
	await click_at(await look_at_end(west))
	if not check(rails.pieces.size() == before+1 and rails.pieces[before].kind == "curve","A click after R should lay a curve"): return
	# On to a fork: G walks its three joining ends and stays in track laying. Only the branch exit fits at the
	# east end, inside the Depot radius, and the click lays it there.
	for i in range(2): await press(KEY_R)
	if not check(game.rail_piece == "fork_left","R should reach the left fork"): return
	for join in [1,2,0,1,2]:
		await press(KEY_G)
		if not check(game.placing_rail and game.global_plan_kind.is_empty() and game.rail_fork_join == join,"G should move a fork to join %d" % join): return
	var far: Dictionary = free_end(game.get_node("Entities/Rails/Track6"),1)
	if not check(not far.is_empty(),"Fixture has no free east end"): return
	before = rails.pieces.size()
	await click_at(await look_at_end(far))
	if not check(rails.pieces.size() == before+1 and rails.pieces[before].kind == "fork_left","A click after R should lay a fork"): return
	# Finished laying: the Build page has its keys back.
	game.cancel_armed()
	await process_frame
	await press(KEY_G)
	if not check(not game.placing_rail and game.global_plan_kind == &"generator","G should be the Generator tile again"): return
	print("RAIL_KEYS_TEST_PASSED"); quit()
