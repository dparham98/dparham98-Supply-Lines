extends SceneTree
# Rendered check: grass and desert show tile detail up close. Saves ground_tiles_close, _play and _map.
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
# Mean brightness step between neighbouring pixels: near zero on the old blurred ground.
func detail(image: Image, area: Rect2i) -> float:
	var total := 0.0
	for y in range(area.position.y,area.end.y):
		for x in range(area.position.x,area.end.x):
			total += absf(image.get_pixel(x,y).get_luminance()-image.get_pixel(x+1,y).get_luminance())
	return total/area.get_area()
func run() -> void:
	root.size = Vector2i(1280,900)
	game = load("res://scenes/maps/resource_skirmish.tscn").instantiate()
	root.add_child(game)
	for frame in range(4): await process_frame
	game.set_process(false)
	var rig = game.get_node("CameraRig"); rig.set_process(false)
	# A grass and desert border south-west of the player Depot.
	var close: Image = await shot(rig,Vector3(140.5,0,120.5),20,"ground_tiles_close")
	var grass := detail(close,Rect2i(100,100,200,150))
	var desert := detail(close,Rect2i(1000,250,150,150))
	print("Detail grass %.4f desert %.4f" % [grass,desert])
	if not check(grass > 0.012,"Grass shows no tile detail: %.4f" % grass): return
	if not check(desert > 0.008,"Desert shows no tile detail: %.4f" % desert): return
	await shot(rig,Vector3(140.5,0,120.5),95,"ground_tiles_play")
	await shot(rig,Vector3.ZERO,480,"ground_tiles_map")
	print("GROUND_TILES_RUNTIME_CHECK_PASSED"); quit(TestOutput.exit_code())
