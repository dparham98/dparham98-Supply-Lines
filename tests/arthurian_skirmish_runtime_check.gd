extends SceneTree
## Renders live screenshots of scenes/maps/arthurian_skirmish.tscn to verify Keep, Chapterhouse,
## all 6 Arthurian units/mount, Food HUD panels, unit portrait, and TeamPaint under Two Lakes lighting.

const TestOutput = preload("res://tests/test_output.gd")
var game: Node3D
var hud: CanvasLayer
var rig: Node3D

func _initialize() -> void:
	call_deferred("run")

func shot(name: String) -> void:
	hud._process(0)
	for _frame in range(6):
		await process_frame
	await RenderingServer.frame_post_draw
	TestOutput.save_png(self, root.get_texture().get_image(), name + ".png")

func run() -> void:
	root.size = Vector2i(1280, 900)
	game = load("res://scenes/maps/arthurian_skirmish.tscn").instantiate()
	root.add_child(game)
	await process_frame
	hud = game.get_node("Interface")
	rig = game.get_node("CameraRig")
	rig.set_process(false)
	var keep := game.get_node("Entities/Buildings/Keep")
	var sentinel := game.get_node("Entities/Units/GrailSentinel")
	var chapterhouse := game.get_node("Entities/Buildings/Chapterhouse")

	# 1. Overview showing Keep (with Keep HUD), Chapterhouse, and all 6 Arthurian unit types.
	rig.focus_position(keep.global_position + Vector3(0.0, 0.0, 6.0), 46.0)
	for _f in range(180): rig.advance_camera(1.0 / 60.0)
	game.selected_building = keep
	for u in get_nodes_in_group("units"): u.set_selected(false)
	await shot("arthurian_overview_keep")

	# 2. Close lineup zoom showing Keep gatehouse + Forester, Warhound, Round Table Marine, Sentinel, Questing Marine, Dragon.
	rig.focus_position(keep.global_position + Vector3(3.0, 0.0, 9.0), 26.0)
	for _f in range(180): rig.advance_camera(1.0 / 60.0)
	game.selected_building = null
	sentinel.set_selected(true)
	await shot("arthurian_lineup_sentinel")

	# 3. Chapterhouse card + production menu + Global Build preview check.
	rig.focus_position(chapterhouse.global_position + Vector3(2.0, 0.0, 2.0), 34.0)
	for _f in range(180): rig.advance_camera(1.0 / 60.0)
	for u in get_nodes_in_group("units"): u.set_selected(false)
	game.selected_building = chapterhouse
	await shot("arthurian_chapterhouse")

	print("ARTHURIAN_RUNTIME_CHECK_PASSED")
	quit(TestOutput.exit_code())
