extends SceneTree
# Rendered check of the water on the balanced map: it is sunk below the ground behind a bank, the shore is a drawn
# line instead of 1 m steps, plants stand along it and the water moves. Nothing that can be walked on is lowered.
# Saves water_play, water_close and water_wide.
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
# How many of the cells within a distance of a cell are of the given kinds.
func around(cells: PackedByteArray, cell: Vector2i, reach: int, kinds: Array) -> int:
	var count := 0
	for dz in range(-reach,reach+1):
		for dx in range(-reach,reach+1):
			if cells[(cell.y+dz)*500+cell.x+dx] in kinds: count += 1
	return count
func run() -> void:
	root.size = Vector2i(1280,900)
	var game: Node3D = load("res://scenes/maps/balanced_skirmish.tscn").instantiate()
	root.add_child(game)
	for frame in range(4): await process_frame
	game.set_process(false)
	game.get_node("Interface").visible = false
	var rig = game.get_node("CameraRig"); rig.set_process(false)
	var ground = game.ground
	var cells := FileAccess.get_file_as_bytes(ground.cells_path)

	# The shore map agrees with the cells: well out on the water it says water, well inland it says land, and it
	# knows the Water cells' own edge.
	var field: Image = ground.material_override.get_shader_parameter("ground_blend").get_image()
	var checked := 0
	for z in range(6,494,5):
		for x in range(6,494,5):
			var wet := around(cells,Vector2i(x,z),3,[1])
			if wet != 0 and wet != 49: continue
			checked += 1
			var pixel := field.get_pixel(x,z)
			if not check((pixel.g > 0.5) == (wet == 49) and (pixel.b > 0.2) == (wet == 49),"Shore map disagrees with the map cells at %d,%d" % [x,z]): return
	if not check(checked > 5000,"Shore map was hardly checked"): return

	# Sunk water: the bed and the surface are saved scenery, and the bed is level under every cell that is not Water.
	var bed: MeshInstance3D = game.find_child("Bed",true,false)
	var surface: MeshInstance3D = game.find_child("Surface",true,false)
	if not check(bed != null and surface != null and bed.owner != null,"The water's bed and surface are not in the saved scenery"): return
	var lowest := 0.0
	var vertices: PackedVector3Array = bed.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	for vertex in vertices:
		lowest = minf(lowest,vertex.y)
		if vertex.y > -0.01: continue
		for offset in [Vector2(-0.001,-0.001),Vector2(0.001,-0.001),Vector2(-0.001,0.001),Vector2(0.001,0.001)]:
			var cell := Vector2i(floori(vertex.x+250.0+offset.x),floori(vertex.z+250.0+offset.y))
			if not check(cells[clampi(cell.y,0,499)*500+clampi(cell.x,0,499)] == 1,"The bed is lowered under a cell that is not Water: %s" % cell): return
	var level: float = surface.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX][0].y
	print("Bed: %d vertices, lowest %.2f m; water level %.2f m" % [vertices.size(),lowest,level])
	if not check(level < -0.1 and lowest < level-0.5,"The water is not sunk below the ground"): return

	# A stretch of shore with broad water on one side and broad open ground on the other.
	var shore := Vector2i(-1,-1)
	var best := 0
	for z in range(24,476,3):
		for x in range(24,476,3):
			if cells[z*500+x] != 1 or around(cells,Vector2i(x,z),1,[0,2]) == 0: continue
			var score := mini(around(cells,Vector2i(x,z),10,[1]),around(cells,Vector2i(x,z),10,[0,2]))
			if score > best: best = score; shore = Vector2i(x,z)
	if not check(shore.x >= 0,"Balanced map has no open shore"): return
	# The deepest water and the driest ground within 9 cells of it.
	var deep := shore
	var dry := shore
	for dz in range(-9,10):
		for dx in range(-9,10):
			var cell := shore+Vector2i(dx,dz)
			if around(cells,cell,4,[1]) > around(cells,deep,4,[1]): deep = cell
			if around(cells,cell,4,[0,2]) > around(cells,dry,4,[0,2]): dry = cell
	if not check(around(cells,deep,4,[1]) == 81 and around(cells,dry,4,[0,2]) == 81,"No broad water and ground beside the chosen shore"): return
	var at: Vector3 = ground.tile_to_world(shore)
	await shot(rig,at,72,"water_play")
	var close: Image = await shot(rig,at,24,"water_close")
	var camera := root.get_camera_3d()
	var out: Color = close.get_pixelv(Vector2i(camera.unproject_position(ground.tile_to_world(deep))))
	var inland: Color = close.get_pixelv(Vector2i(camera.unproject_position(ground.tile_to_world(dry))))
	if not check(out.b > out.r and out.b > out.g*0.9,"Deep water does not read as water: %s against ground %s" % [out,inland]): return
	# The ground beside the water is a bank: browner than the ground further in. The reddest sample on the line from
	# the dry ground to the deep water is compared.
	var reddest := -1.0
	for i in range(0,81):
		var sample := close.get_pixelv(Vector2i(camera.unproject_position(ground.tile_to_world(dry).lerp(ground.tile_to_world(deep),i/80.0))))
		reddest = maxf(reddest,sample.r-sample.g)
	print("Bank: red over green %.3f against %.3f inland" % [reddest,inland.r-inland.g])
	if not check(reddest > inland.r-inland.g+0.04,"No bank is drawn beside the water"): return
	# Reeds, rocks and lily pads stand along the shore.
	var dressing := game.find_child("Shore",true,false)
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
	var centre: Vector3 = ground.tile_to_world(deep)
	for i in range(40):
		var pixel := Vector2i(camera.unproject_position(centre+Vector3((i%8)-3.5,0,(i/8)-2.0)*0.8))
		if pixel.x < 0 or pixel.y < 0 or pixel.x >= 1280 or pixel.y >= 900: continue
		if absf(close.get_pixelv(pixel).get_luminance()-later.get_pixelv(pixel).get_luminance()) > 0.002: moved += 1
	print("Water samples that moved in a second: %d of 40" % moved)
	if not check(moved >= 8,"The water does not move"): return
	await shot(rig,at,150,"water_wide")
	print("WATER_RUNTIME_CHECK_PASSED"); quit(TestOutput.exit_code())
