extends SceneTree
# Rendered check of the water on the balanced map: the shore is a drawn line with a bank and shallows instead of
# 1 m steps, and the water moves. Saves water_play, water_close and water_wide.
const TestOutput = preload("res://tests/test_output.gd")
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
	var game: Node3D = load("res://scenes/maps/balanced_skirmish.tscn").instantiate()
	root.add_child(game)
	for frame in range(4): await process_frame
	game.set_process(false)
	var rig = game.get_node("CameraRig"); rig.set_process(false)
	var ground = game.ground
	# A shore cell with open ground beside it: water with grass or desert two cells to the west.
	var cells := FileAccess.get_file_as_bytes(ground.cells_path)
	var shore := Vector2i(-1,-1)
	var best := 0
	for z in range(20,480,3):
		for x in range(20,480,3):
			if cells[z*500+x] != 1 or not (cells[z*500+x-2] in [0,2]): continue
			# Prefer a shore with plenty of both water and open ground around it.
			var water := 0
			var open := 0
			for dz in range(-12,13,4):
				for dx in range(-12,13,4):
					var kind := cells[(z+dz)*500+x+dx]
					if kind == 1: water += 1
					elif kind == 0 or kind == 2: open += 1
			if mini(water,open) > best: best = mini(water,open); shore = Vector2i(x,z)
	if not check(shore.x >= 0,"Balanced map has no open shore"): return
	var at: Vector3 = ground.tile_to_world(shore)
	var play: Image = await shot(rig,at,72,"water_play")
	var close: Image = await shot(rig,at,24,"water_close")
	var camera := root.get_camera_3d()
	# Well out from the shore the water is blue and darker than the ground well inland.
	var out: Color = close.get_pixelv(Vector2i(camera.unproject_position(at+Vector3(7,0,0))))
	var inland: Color = close.get_pixelv(Vector2i(camera.unproject_position(at+Vector3(-7,0,0))))
	if not check(out.b > out.r and out.get_luminance() < inland.get_luminance(),"Water 7 m out does not read as water: %s against ground %s" % [out,inland]): return
	# The shore map agrees with the cells: well out on the water it says water, well inland it says land.
	var field: Image = ground.material_override.get_shader_parameter("ground_blend").get_image()
	var checked := 0
	for z in range(6,494,5):
		for x in range(6,494,5):
			var wet := 0
			for dz in [-3,0,3]:
				for dx in [-3,0,3]:
					if cells[(z+dz)*500+x+dx] == 1: wet += 1
			if wet != 0 and wet != 9: continue
			checked += 1
			if not check((field.get_pixel(x,z).g > 0.5) == (wet == 9),"Shore map disagrees with the map cells at %d,%d" % [x,z]): return
	if not check(checked > 5000,"Shore map was hardly checked"): return
	# The ground beside the water is a bank: browner than the grass further in. The drawn shore wanders, so the
	# reddest of a run of samples across it is compared.
	var reddest := 0.0
	for i in range(0,33):
		var sample := close.get_pixelv(Vector2i(camera.unproject_position(at+Vector3(-4.0+i*0.25,0,0))))
		reddest = maxf(reddest,sample.r-sample.g)
	print("Bank: red over green %.3f against %.3f inland" % [reddest,inland.r-inland.g])
	if not check(reddest > inland.r-inland.g+0.04,"No bank is drawn beside the water"): return
	# Reeds, rocks and lily pads stand along the shore.
	var dressing := game.get_node_or_null("Terrain/Landmarks/Shore")
	if dressing == null: dressing = game.find_child("Shore",true,false)
	var pieces := 0
	if dressing != null:
		for batch in dressing.get_children(): pieces += batch.multimesh.instance_count
	print("Shore pieces: %d" % pieces)
	if not check(pieces > 200,"The shore is bare"): return
	# The water moves: two frames a second apart differ out on the water.
	for frame in range(60): await process_frame
	await RenderingServer.frame_post_draw
	var later := root.get_texture().get_image()
	var moved := 0
	for i in range(40):
		var pixel := Vector2i(camera.unproject_position(at+Vector3(3.0+i*0.2,0,(i%5)-2.0)))
		if pixel.x < 0 or pixel.y < 0 or pixel.x >= 1280 or pixel.y >= 600: continue
		if absf(close.get_pixelv(pixel).get_luminance()-later.get_pixelv(pixel).get_luminance()) > 0.002: moved += 1
	print("Water samples that moved in a second: %d of 40" % moved)
	if not check(moved >= 8,"The water does not move"): return
	await shot(rig,at,150,"water_wide")
	print("WATER_RUNTIME_CHECK_PASSED"); quit(TestOutput.exit_code())
