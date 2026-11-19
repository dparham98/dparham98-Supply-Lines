extends SceneTree
# Rendered check of the cursor labels (docs/CURSOR_LABELS.md): the rail prompt and the placement label keep one
# readable screen size at every camera zoom. For each zoom it renders the map with the rail label shown and hidden,
# measures the height of what changed and saves cursor_label_<zoom>.png.
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
	if not name.is_empty(): TestOutput.save_png(self,image,name+".png")
	return image
## How many rows the label covers: around where it projects, the run of rows in which many pixels change when it is
## shown. Water and trees elsewhere animate between frames, but change only a few pixels a row.
func label_rows(a: Image, b: Image, at: Vector2) -> int:
	var rows := 0
	var best := 0
	for y in range(maxi(0,int(at.y)-60),mini(620,int(at.y)+60)):
		var count := 0
		for x in range(maxi(0,int(at.x)-560),mini(a.get_width(),int(at.x)+560)):
			var p := a.get_pixel(x,y); var q := b.get_pixel(x,y)
			if absf(p.r-q.r)+absf(p.g-q.g)+absf(p.b-q.b) > 0.3: count += 1
		rows = rows+1 if count >= 25 else 0
		best = maxi(best,rows)
	return best
func run() -> void:
	root.size = Vector2i(1280,900)
	game = load("res://scenes/maps/lakes_skirmish.tscn").instantiate()
	root.add_child(game)
	for frame in range(4): await process_frame
	game.set_process(false)
	game.selected_building = null
	var rails = game.get_node("RailNetwork"); rails.set_process(false)
	var rig = game.get_node("CameraRig"); rig.set_process(false)
	var preview: Node3D = game.get_node("RailPreview")
	var label: Label3D = preview.get_node("Status")
	var placement: Label3D = game.get_node("ConstructionPreview/Status")
	if not check(label.fixed_size and placement.fixed_size,"Cursor labels should keep a fixed screen size"): return
	preview.visible = true
	for child in preview.get_children(): child.visible = child == label
	label.text = rails.route_status()
	var heights: Array[int] = []
	for zoom in [30.0,95.0,400.0]:
		rig.focus_position(game.depot.global_position+Vector3(0,0,30),zoom)
		for frame in range(300): rig.advance_camera(1.0/60)
		label.global_position = rig.global_position+Vector3.UP*2.0
		label.visible = true
		var with: Image = await shot("cursor_label_%d" % int(zoom))
		label.visible = false
		var without: Image = await shot("")
		var height := label_rows(with,without,rig.camera.unproject_position(label.global_position))
		print("  zoom %d: label %d px tall" % [int(zoom),height])
		heights.append(height)
	if not check(heights.min() >= 16,"The label should be readable at every zoom: %s px tall" % [heights]): return
	if not check(heights.max() <= heights.min()*1.25,"The label should keep its size as the camera zooms: %s px tall" % [heights]): return
	print("CURSOR_LABEL_RUNTIME_CHECK_PASSED")
	quit(0)
