extends SceneTree
# Rendered look at mine sites on the trial map (docs/MINE_SITES.md): a bare site reads as stained stone in a cut in
# the mountain, and a mine built in it faces out of the rock. Saves mine_site_bare, mine_site_built and
# mine_site_east.
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
func middle(game: Node3D, site: Rect2i) -> Vector3:
	return game.ground.tile_to_world(site.position)+Vector3(site.size.x*0.5-0.5,0,site.size.y*0.5-0.5)
func build(game: Node3D, site: Rect2i) -> Node3D:
	var mine: Node3D = load("res://scenes/gameplay/iron_mine.tscn").instantiate()
	mine.rules = game.get_node("DepotNetwork").engineering_rules
	mine.position = game.ground.tile_to_world(site.position)
	game.get_node("Entities/Buildings").add_child(mine)
	return mine
func run() -> void:
	root.size = Vector2i(1280,900)
	var game: Node3D = load("res://scenes/maps/mine_site_exercise.tscn").instantiate()
	root.add_child(game)
	for frame in range(4): await process_frame
	game.set_process(false)
	game.get_node("Interface").visible = false
	var rig = game.get_node("CameraRig"); rig.set_process(false)
	var ground = game.ground
	# The site in front of SiteDepot, and the nearest one that faces east.
	var depot: Vector3 = game.get_node("Entities/Buildings/SiteDepot").global_position
	var near := Rect2i()
	var east := Rect2i()
	for i in range(250000):
		var cell := Vector2i(i%500,i/500)
		if ground.get_terrain(cell) != ground.Terrain.MINE_SITE: continue
		var site: Rect2i = ground.mine_site_rect(cell)
		if site.position != cell: continue
		if near.size == Vector2i.ZERO or middle(game,site).distance_to(depot) < middle(game,near).distance_to(depot): near = site
		if ground.mine_site_facing(site.position,site.size) == Vector2i(1,0) and (east.size == Vector2i.ZERO or middle(game,site).distance_to(depot) < middle(game,east).distance_to(depot)): east = site
	if not check(near.size != Vector2i.ZERO and east.size != Vector2i.ZERO,"Trial map lacks the sites this check looks at"): return
	var centre := middle(game,near)
	var facing: Vector2i = ground.mine_site_facing(near.position,near.size)
	var out := Vector3(facing.x,0,facing.y)
	var bare: Image = await shot(rig,centre+out*4.0,30,"mine_site_bare")
	var camera := root.get_camera_3d()
	# A bare site is rust-stained: redder than the open ground beyond its front strip.
	var floor_colour: Color = bare.get_pixelv(Vector2i(camera.unproject_position(centre+out*1.0)))
	var grass: Color = bare.get_pixelv(Vector2i(camera.unproject_position(centre+out*7.0)))
	print("Site %s against ground %s" % [floor_colour,grass])
	if not check(floor_colour.r-floor_colour.g > grass.r-grass.g+0.05,"A bare mine site does not stand out from the ground"): return
	build(game,near)
	for frame in range(4): await process_frame
	await shot(rig,centre+out*4.0,30,"mine_site_built")
	build(game,east)
	for frame in range(4): await process_frame
	await shot(rig,middle(game,east)+Vector3(4,0,0),30,"mine_site_east")
	print("MINE_SITES_RUNTIME_CHECK_PASSED"); quit(TestOutput.exit_code())
