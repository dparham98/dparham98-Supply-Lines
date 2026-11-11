extends SceneTree
# Rendered views of the sculpted landscape (docs/LANDSCAPE_LOOKDEV.md): the first slice at play zoom and close up,
# the rest of the map, its corner and the overview.
# Saves landscape_<view>.png, or <prefix>_<view>.png when LANDSCAPE_SHOT_PREFIX is set (used for the before set).
const TestOutput = preload("res://tests/test_output.gd")
const VIEWS := [
	["play_centre",Vector3(-152,0,-170),95.0],
	["play_west",Vector3(-186,0,-170),95.0],
	["play_east",Vector3(-118,0,-170),95.0],
	["wide",Vector3(-152,0,-170),150.0],
	["close_shore",Vector3(-189,0,-172),30.0],
	["close_forest",Vector3(-176,0,-160),30.0],
	["close_grass",Vector3(-150,0,-172),30.0],
	["close_mountain",Vector3(-122,0,-168),30.0],
	["close_desert",Vector3(-112,0,-186),30.0],
	# Beyond the first slice: the landscape covers the whole map.
	["map_centre",Vector3(0,0,0),95.0],
	["map_north_east",Vector3(150,0,-150),95.0],
	["map_south_west",Vector3(-150,0,150),95.0],
	["map_south_east",Vector3(170,0,190),95.0],
	["map_corner_water",Vector3(-215,0,215),60.0],
	["map_corner_wide",Vector3(-200,0,200),160.0],
	["map_corner_tight",Vector3(-232,0,240),25.0],
	["map_overview",Vector3(0,0,0),560.0],
]
func _initialize() -> void: call_deferred("run")
func run() -> void:
	root.size = Vector2i(1600,900)
	var prefix := OS.get_environment("LANDSCAPE_SHOT_PREFIX")
	if prefix.is_empty(): prefix = "landscape"
	var only := OS.get_environment("LANDSCAPE_SHOT_ONLY")
	var game: Node3D = load("res://scenes/maps/resource_skirmish.tscn").instantiate()
	root.add_child(game)
	for frame in range(4): await process_frame
	game.set_process(false)
	var hud := game.get_node_or_null("Interface")
	if hud and OS.get_environment("LANDSCAPE_SHOT_HUD").is_empty(): hud.visible = false
	var rig = game.get_node("CameraRig"); rig.set_process(false)
	var ground = game.get_node("Terrain/Ground")
	for view in VIEWS:
		if not only.is_empty() and not String(view[0]).contains(only): continue
		rig.focus_position(view[1],view[2])
		for frame in range(200): rig.advance_camera(1.0/60)
		for frame in range(6): await process_frame
		await RenderingServer.frame_post_draw
		print("%s: draw calls %d, primitives %d" % [view[0],Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)])
		if not TestOutput.save_png(self,root.get_texture().get_image(),"%s_%s.png" % [prefix,view[0]]): return
	# A Tank's lane through the wood: cleared cells lose their own trees and show churned earth.
	if only.is_empty() or "cleared".contains(only):
		for step in range(12):
			for side in range(4): ground.clear_forest(Vector2i(58+step,83+side+step/5))
		rig.focus_position(Vector3(-183,0,-164),30.0)
		for frame in range(200): rig.advance_camera(1.0/60)
		# Felling: step the fall by hand so the views do not depend on frame rate.
		var felled = game.get_node("Terrain").forest_state
		game.get_node("Terrain").set_process(false)
		var elapsed := 0.0
		for moment in [0.7,1.15,1.7,4.0]:
			felled.advance(moment-elapsed)
			elapsed = moment
			for frame in range(4): await process_frame
			await RenderingServer.frame_post_draw
			var label := "close_cleared" if moment > 3.0 else "felling_%03d" % roundi(moment*100.0)
			if not TestOutput.save_png(self,root.get_texture().get_image(),"%s_%s.png" % [prefix,label]): return
		if felled.is_felling():
			push_error("Felled trees should be gone after four seconds"); quit(1); return
	print("Draw calls %d, primitives %d" % [Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)])
	print("LANDSCAPE_LOOKDEV_RUNTIME_CHECK_PASSED"); quit(TestOutput.exit_code())
