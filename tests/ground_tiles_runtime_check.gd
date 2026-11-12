extends SceneTree
# Rendered check: grass and desert show tile detail up close, open grass has no black spots from an invalid normal, and the noise behind the ground has no jumps. Saves ground_tiles_close, _play_bare, _play, _map, _forest and _water.
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
# Draws the relief height itself over open grass. It is a smooth field, so any sharp step between neighbouring
# pixels is a seam in the noise, which shows in the game as a dark streak. This view holds a seam the old hash made.
func check_noise_is_continuous(rig: Node) -> bool:
	# Where the sculpted landscape covers the map it draws the ground, with the same relief noise; its plants and
	# stones are hidden so only the ground is measured.
	var tiles: Array = []
	var landscape := game.get_node_or_null("Terrain/Landmarks/Landscape")
	if landscape != null and game.get_node("Terrain/Ground").material_override.get_shader_parameter("landscape_region").z > 0.0:
		tiles = landscape.get_node("Ground").get_children()
		for part in ["Scatter","Forest"]: landscape.get_node(part).visible = false
	var material: ShaderMaterial = tiles[0].material_override if not tiles.is_empty() else game.get_node("Terrain/Ground").material_override
	var indent := " " if not tiles.is_empty() else "  "
	var marker := indent+"float height = layered_noise(relief_uv, 3);\n"
	var albedo := " ALBEDO = mix(color, rock, rockiness);\n" if not tiles.is_empty() else " ALBEDO = color;\n"
	if not check(material.shader.code.contains(marker) and material.shader.code.contains(albedo),"Shader changed: the noise check cannot find the relief height"): return false
	var debug := Shader.new()
	debug.code = material.shader.code.replace(marker,marker+indent+"NOISE_VIEW = vec3(height);\n").replace("void fragment() {\n","void fragment() {\n vec3 NOISE_VIEW = vec3(0.0);\n").replace(albedo," ALBEDO = vec3(0.0); EMISSION = NOISE_VIEW; ROUGHNESS = 1.0; SPECULAR = 0.0;\n")
	material.shader = debug
	for tile in tiles: tile.material_override = material
	var image: Image = await shot(rig,Vector3(128.5,0,100.5),26,"ground_tiles_noise")
	var step := 0.0
	for y in range(0,580):
		for x in range(0,1279):
			step = maxf(step,absf(image.get_pixel(x,y).r-image.get_pixel(x+1,y).r))
			step = maxf(step,absf(image.get_pixel(x,y).r-image.get_pixel(x,y+1).r))
	print("Largest noise step %.4f" % step)
	return check(step < 0.02,"The ground noise has a seam: step %.4f" % step)
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
	# The ground alone: the landscape's small plants and stones are dark in their own shade, which is not a fault.
	var scatter: Node3D = game.get_node_or_null("Terrain/Landmarks/Landscape/Scatter")
	if scatter: scatter.visible = false
	var bare: Image = await shot(rig,Vector3(140.5,0,120.5),95,"ground_tiles_play_bare")
	if scatter: scatter.visible = true
	var darkest := 1.0
	for y in range(20,280):
		for x in range(20,1260): darkest = minf(darkest,bare.get_pixel(x,y).get_luminance())
	var play: Image = await shot(rig,Vector3(140.5,0,120.5),95,"ground_tiles_play")
	print("Darkest open grass %.3f" % darkest)
	if not check(darkest > 0.08,"Open grass has a black spot: %.3f" % darkest): return
	await shot(rig,Vector3.ZERO,480,"ground_tiles_map")
	await shot(rig,Vector3(178.5,0,-101.5),20,"ground_tiles_forest")
	await shot(rig,Vector3(-60,0,-20),20,"ground_tiles_water")
	if not await check_noise_is_continuous(rig): return
	print("GROUND_TILES_RUNTIME_CHECK_PASSED"); quit(TestOutput.exit_code())
