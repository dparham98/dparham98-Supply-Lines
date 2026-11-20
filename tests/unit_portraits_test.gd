extends SceneTree
# Selecting Infantry shows its full helmet in the Ornament at narrow and wide window sizes.
# Selecting a Depot restores the emblem.
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> bool:
	if value: return true
	push_error(message); quit(1); return false
func run() -> void:
	var game: Node3D = load("res://scenes/maps/resource_skirmish.tscn").instantiate()
	root.add_child(game)
	for frame in range(3): await process_frame
	game.set_process(false)
	var hud = game.get_node("Interface")
	var portrait: TextureRect = hud.get_node("Bottom/Body/Row/Ornament/Portrait")
	var infantry: Node3D
	for unit in get_nodes_in_group("units"):
		unit.set_process(false); unit.set_selected(false)
		if infantry == null and unit.team == "player" and unit.unit_stats != null and unit.unit_stats.unit_id == &"infantry": infantry = unit
	if not check(infantry != null,"No Infantry"): return
	infantry.set_selected(true)
	game.selected_building = null
	for frame in range(3): await process_frame
	if not check(portrait.visible and portrait.texture != null and portrait.texture.resource_path == "res://assets/ui/portraits/infantry.png","The Infantry portrait should show"): return
	var narrow_width := 0.0
	for window_size in [Vector2i(1280,900), Vector2i(1920,1080)]:
		root.size = window_size
		for frame in range(3): await process_frame
		var artwork := portrait.get_global_rect()
		var ornament := (portrait.get_parent() as Control).get_global_rect()
		if not check(artwork.has_area() and ornament.encloses(artwork),"The portrait should fit inside its frame"): return
		if not check(absf(artwork.get_center().x - ornament.get_center().x) <= 1.0,"The portrait should remain centered"): return
		# In cover mode, a frame wider than the image trims its top and bottom.
		if portrait.stretch_mode == TextureRect.STRETCH_KEEP_ASPECT_COVERED:
			if not check(artwork.size.aspect() <= portrait.texture.get_size().aspect()+0.001,"The HUD must retain the crown and chin at %s" % str(window_size)): return
		if narrow_width > 0.0 and not check(artwork.size.x > narrow_width,"The wide layout should expose more of the shoulders"): return
		narrow_width = artwork.size.x
	infantry.set_selected(false)
	game.selected_building = game.depot
	for frame in range(3): await process_frame
	if not check(not portrait.visible,"A Depot has no portrait"): return
	print("UNIT_PORTRAITS_TEST_PASSED")
	quit(0)
