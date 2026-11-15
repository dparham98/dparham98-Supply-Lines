extends SceneTree
# Rendered check of team markers (docs/TEAM_MARKERS.md): none show with nothing selected, the player's units show theirs
# when selected, and a selected Depot shows its own. Saves markers_none, markers_units and markers_depot.
const TestOutput = preload("res://tests/test_output.gd")
var game: Node3D
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> bool:
	if value: return true
	push_error(message); quit(1); return false
func shot(name: String) -> Image:
	for frame in range(4): await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	TestOutput.save_png(self,image,name+".png")
	return image
# Map pixels (above the HUD) that turned greener than in the unselected picture.
func greener(image: Image, before: Image) -> int:
	var count := 0
	for y in range(0,600,2):
		for x in range(0,image.get_width(),2):
			var c := image.get_pixel(x,y); var b := before.get_pixel(x,y)
			if c.g-b.g > 0.03 and c.g-c.r > b.g-b.r: count += 1
	return count
func run() -> void:
	root.size = Vector2i(1280,900)
	game = load("res://scenes/maps/balanced_skirmish.tscn").instantiate()
	root.add_child(game)
	for frame in range(4): await process_frame
	game.set_process(false)
	var rig = game.get_node("CameraRig"); rig.set_process(false)
	rig.focus_position(game.depot.global_position,60)
	for frame in range(200): rig.advance_camera(1.0/60)
	# The game opens with the Depot selected; clear it for the picture with nothing selected.
	if not check(game.selected_building == game.depot and game.depot.get_node("Visuals/TeamMarker").visible,"The Depot selected at the start should show its marker"): return
	game.selected_building = null
	var units: Array = get_nodes_in_group("units").filter(func(u): return u.team == "player")
	if not check(units.all(func(u): return not u.get_node("Visuals/TeamMarker").visible),"Markers should be hidden at the start"): return
	var none: Image = await shot("markers_none")
	for unit in units: unit.set_selected(true)
	var selected := greener(await shot("markers_units"),none)
	if not check(units.all(func(u): return u.get_node("Visuals/TeamMarker").visible),"Selected units should show their markers"): return
	for unit in units: unit.set_selected(false)
	game.selected_building = game.depot
	var depot := greener(await shot("markers_depot"),none)
	if not check(game.depot.get_node("Visuals/TeamMarker").visible,"The selected Depot should show its marker"): return
	print("pixels turned green: units %d, depot %d" % [selected,depot])
	if not check(selected > 40 and depot > 2000,"Markers should add their colour to the picture"): return
	print("TEAM_MARKER_RUNTIME_CHECK_PASSED")
	quit(0)
