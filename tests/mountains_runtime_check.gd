extends SceneTree
# Rendered check: the mountains near the player Depot show lit rock and shadow. Saves mountains_play, _close and _map.
const TestOutput = preload("res://tests/test_output.gd")
var game: Node3D
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> bool:
	if value: return true
	push_error(message); quit(1); return false
func shot(rig: Node, at: Vector3, zoom: float, name: String) -> Image:
	rig.focus_position(at,zoom)
	for frame in range(200): rig.advance_camera(1.0/60)
	for frame in range(4): await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	TestOutput.save_png(self,image,name+".png")
	return image
func run() -> void:
	root.size = Vector2i(1280,900)
	game = load("res://scenes/maps/resource_skirmish.tscn").instantiate()
	root.add_child(game)
	for frame in range(4): await process_frame
	game.set_process(false)
	var rig = game.get_node("CameraRig"); rig.set_process(false)
	var massif := Vector3(122.5,0,146.5)
	var view: Image = await shot(rig,massif,95,"mountains_play")
	var darkest := 1.0
	var brightest := 0.0
	for y in range(340,560,4):
		for x in range(300,800,4):
			var light := view.get_pixel(x,y).get_luminance()
			darkest = minf(darkest,light); brightest = maxf(brightest,light)
	print("Mountain light range %.3f to %.3f" % [darkest,brightest])
	if not check(brightest-darkest > 0.45,"Mountains show too little relief: %.3f to %.3f" % [darkest,brightest]): return
	await shot(rig,massif,35,"mountains_close")
	await shot(rig,Vector3.ZERO,480,"mountains_map")
	print("MOUNTAINS_RUNTIME_CHECK_PASSED"); quit(TestOutput.exit_code())
