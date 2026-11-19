extends SceneTree
# Rendered check of the placement guide (docs/PLACEMENT_GUIDE.md): saves guide_rail_start, guide_rail_lay and
# guide_place while laying rail and placing a Barracks, and checks the guide sits in the bottom panel, off the map,
# in place of the info columns. guide_place also shows the Depot's stock above it.
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
	var guide: Control = hud.get_node("Bottom/Body/Row/Guide")
	var rails = game.get_node("RailNetwork")
	var network = game.get_node("DepotNetwork")
	game.placing_rail = true
	await shot("guide_rail_start")
	var box := guide.get_global_rect()
	var bottom: Rect2 = hud.get_node("Bottom").get_global_rect()
	if not check(guide.visible and bottom.encloses(box),"The guide should sit inside the bottom panel, off the map: %s in %s" % [box,bottom]): return
	if not check(not hud.info.visible and not hud.context.visible and box.end.x <= hud.get_node("Bottom/Body/Row/Commands").get_global_rect().position.x,"The guide takes the info columns' place, beside the command card"): return
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
