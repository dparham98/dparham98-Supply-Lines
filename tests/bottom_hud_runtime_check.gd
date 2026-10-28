extends SceneTree
var game: Node3D
var hud: CanvasLayer
const OUTPUT = "C:/Users/video/.codex/.chatgpt-projects/g-p-6ad16a23380c8191877dbcafdb316068/"
func _initialize() -> void:
	call_deferred("run")
func shot(name: String) -> void:
	hud._process(0)
	for frame in range(6): await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUTPUT+name+".png")
func select_unit(unit: Node3D) -> void:
	game.get_node("DepotNetwork").select_depot(null)
	for candidate in get_nodes_in_group("units"): candidate.set_selected(candidate == unit)
	hud._process(0)
func run() -> void:
	root.size = Vector2i(1280,900)
	game = load("res://scenes/maps/supply_routes.tscn").instantiate()
	root.add_child(game)
	await process_frame
	hud = game.get_node("Interface")
	var rig = game.get_node("CameraRig")
	rig.set_process(false)
	rig.focus_hq()
	for frame in range(180): rig.advance_camera(1.0/60)
	await shot("bottom_hud_depot")
	var worker = game.get_node("Entities/Units/Infantry")
	select_unit(worker)
	await shot("bottom_hud_infantry")
	hud.card.get_node("Build").pressed.emit()
	await shot("bottom_hud_build")
	select_unit(game.get_node("Entities/Units/CargoVehicle"))
	await shot("bottom_hud_cargo")
	root.size = Vector2i(1440,960)
	await shot("bottom_hud_wide")
	print("BOTTOM_HUD_RENDER_CHECK_PASSED")
	quit()
