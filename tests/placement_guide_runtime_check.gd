extends SceneTree
# Rendered check of the placement guide (docs/PLACEMENT_GUIDE.md): saves guide_rail_start, guide_rail_lay and
# guide_place while laying rail and placing a Barracks, and checks the guide sits at the top centre, clear of the
# Depot and storage panels.
const TestOutput = preload("res://tests/test_output.gd")
var game: Node3D
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> bool:
	if value: return true
	push_error(message); quit(1); return false
func shot(name: String) -> void:
	for frame in range(4): await process_frame
	await RenderingServer.frame_post_draw
	TestOutput.save_png(self,root.get_texture().get_image(),name+".png")
func run() -> void:
	root.size = Vector2i(1280,900)
	game = load("res://scenes/maps/lakes_skirmish.tscn").instantiate()
	root.add_child(game)
	for frame in range(4): await process_frame
	var rig = game.get_node("CameraRig"); rig.set_process(false)
	rig.focus_position(game.depot.global_position,70)
	for frame in range(300): rig.advance_camera(1.0/60)
	var hud = game.get_node("Interface")
	var guide: Control = hud.get_node("Guide")
	var rails = game.get_node("RailNetwork")
	var network = game.get_node("DepotNetwork")
	game.placing_rail = true
	await shot("guide_rail_start")
	var box := guide.get_global_rect()
	if not check(guide.visible and absf(box.get_center().x-640) < 2 and box.position.y < 20 and box.size.x <= 900,"The guide should sit at the top centre: %s" % box): return
	for panel in ["DepotPanel","StoragePanel"]:
		var other: Control = hud.get_node(panel)
		if not check(not other.visible or not other.get_global_rect().intersects(box),"The guide should not cover the %s" % panel): return
	rails.pick_target(game.depot)
	var site: Node3D
	for r in range(30,90,6):
		site = network.queue_plan(game.depot.global_position+Vector3(0,0,-r),&"generator")
		if site != null: break
	rails.pick_target(site)
	await shot("guide_rail_lay")
	game.placing_rail = false
	game.global_plan_kind = &"barracks"
	await shot("guide_place")
	if not check(guide.visible,"The guide should show while placing"): return
	print("PLACEMENT_GUIDE_RUNTIME_CHECK_PASSED")
	quit(0)
