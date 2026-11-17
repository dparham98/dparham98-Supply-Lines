extends SceneTree
# Rendered look at the Two Lakes map (docs/TWO_LAKES_MAP.md): the whole map, the West start, the Crossing and a
# pass. Saves two_lakes_overview, _start, _crossing, _crag and _pass, and prints the frame rate.
const TestOutput = preload("res://tests/test_output.gd")
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
func measure(rig: Node, at: Vector3, zoom: float) -> Array:
	await look(rig,at,zoom)
	for frame in range(20): await process_frame
	var began := Time.get_ticks_usec()
	for frame in range(120): await process_frame
	return [120.0/((Time.get_ticks_usec()-began)/1000000.0),Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)]
func run() -> void:
	root.size = Vector2i(1280,900)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var game: Node3D = load("res://scenes/maps/lakes_skirmish.tscn").instantiate()
	root.add_child(game)
	for frame in range(4): await process_frame
	game.set_process(false)
	var rig = game.get_node("CameraRig"); rig.set_process(false)
	var overview: Image = await shot(rig,Vector3.ZERO,480,"two_lakes_overview")
	var lit := 0
	for y in range(40,600,8):
		for x in range(40,1240,8):
			if overview.get_pixel(x,y).get_luminance() > 0.05: lit += 1
	if not check(lit > 4000,"Overview is mostly black: the map did not draw"): return
	game.get_node("Interface").visible = false
	var start: Vector3 = game.get_node("Sites/PlayerStart").global_position
	await shot(rig,start+Vector3(0,0,-8),72,"two_lakes_start")
	var crossing: Image = await shot(rig,Vector3(0,0,0),150,"two_lakes_crossing")
	# The middle is forest: darker and greener than open grass would be.
	var middle: Color = crossing.get_pixelv(Vector2i(root.get_camera_3d().unproject_position(Vector3(0,0,8))))
	if not check(middle.g > middle.r and middle.g > middle.b,"The Crossing does not read as forest: %s" % middle): return
	await shot(rig,Vector3(0,0,-22),60,"two_lakes_crag")
	await shot(rig,Vector3(0,0,-150),95,"two_lakes_pass")
	var play: Array = await measure(rig,start,72)
	var centre: Array = await measure(rig,Vector3.ZERO,95)
	var whole: Array = await measure(rig,Vector3.ZERO,480)
	print("Frame rate, vertical sync off (frames per second, triangles drawn):")
	print("  West start at play zoom  %5.0f  %9d" % play)
	print("  the Crossing             %5.0f  %9d" % centre)
	print("  whole map                %5.0f  %9d" % whole)
	print("TWO_LAKES_RUNTIME_CHECK_PASSED"); quit(TestOutput.exit_code())
