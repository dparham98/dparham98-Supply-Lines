extends SceneTree
# Rendered check of the balanced map (docs/BALANCED_MAP.md): the map draws, coal reads as dark ground among trees,
# and the minimap shows the new layout. Saves balanced_overview, balanced_start, balanced_coal and
# balanced_contested, and prints how the frame rate compares with the original map on this machine.
const TestOutput = preload("res://tests/test_output.gd")
var game: Node3D
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> bool:
	if value: return true
	push_error(message); quit(1); return false
func look(rig: Node, at: Vector3, zoom: float) -> void:
	rig.focus_position(at,zoom)
	for frame in range(200): rig.advance_camera(1.0/60)
	for frame in range(4): await process_frame
func shot(rig: Node, at: Vector3, zoom: float, name: String) -> Image:
	await look(rig,at,zoom)
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	TestOutput.save_png(self,image,name+".png")
	return image
# Frames per second and triangles drawn with vertical sync off, as a rough comparison between maps.
func measure(rig: Node, at: Vector3, zoom: float) -> Array:
	await look(rig,at,zoom)
	for frame in range(20): await process_frame
	var began := Time.get_ticks_usec()
	for frame in range(120): await process_frame
	var seconds := (Time.get_ticks_usec()-began)/1000000.0
	return [120.0/seconds,Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)]
func run() -> void:
	root.size = Vector2i(1280,900)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	# The original map first, as the yardstick.
	var old: Node3D = load("res://scenes/maps/resource_skirmish.tscn").instantiate()
	root.add_child(old)
	for frame in range(4): await process_frame
	old.set_process(false)
	var old_rig = old.get_node("CameraRig"); old_rig.set_process(false)
	var old_play: Array = await measure(old_rig,old.depot.global_position,72)
	var old_map: Array = await measure(old_rig,Vector3.ZERO,480)
	root.remove_child(old); old.free()
	for frame in range(4): await process_frame

	game = load("res://scenes/maps/balanced_skirmish.tscn").instantiate()
	root.add_child(game)
	for frame in range(4): await process_frame
	game.set_process(false)
	var rig = game.get_node("CameraRig"); rig.set_process(false)
	var ground = game.ground
	var start: Vector3 = game.depot.global_position
	var safe: Vector3 = game.get_node("Sites/SafeExpansionA").position
	var field := {}
	var contested := {}
	for candidate in ground.coal_fields:
		if field.is_empty() or candidate.center.distance_to(safe) < field.center.distance_to(safe): field = candidate
		if contested.is_empty() or candidate.cells.size() > contested.cells.size(): contested = candidate
	if not check(not field.is_empty(),"Balanced map has no coal fields"): return

	var overview: Image = await shot(rig,Vector3.ZERO,480,"balanced_overview")
	var lit := 0
	for y in range(40,600,8):
		for x in range(40,1240,8):
			if overview.get_pixel(x,y).get_luminance() > 0.05: lit += 1
	if not check(lit > 4000,"Overview is mostly black: the map did not draw"): return
	# The minimap shows this map: coal markers are drawn for every field.
	var minimap: Control = game.get_node("Interface/Bottom/Body/Row/MapColumn/Map")
	var marker: Vector2 = minimap.global_position+minimap.world_to_map(field.center)
	var marked: Color = overview.get_pixelv(Vector2i(marker))
	if not check(marked.get_luminance() > 0.6,"Minimap has no coal marker at %s: %s" % [marker,marked]): return

	var base: Image = await shot(rig,start,72,"balanced_start")
	var grass: Color = base.get_pixelv(Vector2i(root.get_camera_3d().unproject_position(start+Vector3(-14,0,-8))))
	if not check(grass.g > grass.b and grass.get_luminance() > 0.08,"Ground beside the start does not read as grass: %s" % grass): return

	# Coal: looking straight down the seam's middle, the ground is far darker than the grass at the start.
	var coal: Image = await shot(rig,field.center,40,"balanced_coal")
	var camera := root.get_camera_3d()
	var dark := 0
	var samples := 0
	for cell in field.cells:
		var at: Vector2 = camera.unproject_position(ground.tile_to_world(cell))
		if at.x < 0 or at.y < 0 or at.x >= 1280 or at.y >= 600: continue
		samples += 1
		if coal.get_pixelv(Vector2i(at)).get_luminance() < grass.get_luminance()*0.7: dark += 1
	print("Coal cells that read dark: %d of %d on screen" % [dark,samples])
	if not check(samples >= 10 and dark >= samples*0.6,"Coal does not read as dark ground"): return
	await shot(rig,contested.center,95,"balanced_contested")

	var play: Array = await measure(rig,start,72)
	var forest: Array = await measure(rig,field.center,72)
	var map: Array = await measure(rig,Vector3.ZERO,480)
	print("Frame rate, vertical sync off (frames per second, triangles drawn):")
	print("  original map at play zoom      %6.0f  %9d" % old_play)
	print("  original map, whole map        %6.0f  %9d" % old_map)
	print("  balanced map, start at play zoom %4.0f  %9d" % play)
	print("  balanced map, coal forest      %6.0f  %9d" % forest)
	print("  balanced map, whole map        %6.0f  %9d" % map)
	print("BALANCED_MAP_RUNTIME_CHECK_PASSED"); quit(TestOutput.exit_code())
