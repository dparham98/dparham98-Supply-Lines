extends SceneTree
# Rendered check of the Depot panels (docs/DEPOT_PANELS.md): with your Depot selected, the energy panel sits top
# left and the storage panel top right, both on screen, clear of the bottom HUD and of each other, with the alert
# feed below the storage panel. Saves depot_panels.png.
const TestOutput = preload("res://tests/test_output.gd")
var game: Node3D
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> bool:
	if value: return true
	push_error(message); quit(1); return false
func run() -> void:
	root.size = Vector2i(1280,900)
	game = load("res://scenes/maps/balanced_skirmish.tscn").instantiate()
	root.add_child(game)
	for frame in range(4): await process_frame
	var rig = game.get_node("CameraRig"); rig.set_process(false)
	rig.focus_position(game.depot.global_position,60)
	for frame in range(200): rig.advance_camera(1.0/60)
	game.selected_building = game.depot
	game.notify("A notice, to show where the alert feed sits.")
	for frame in range(6): await process_frame
	await RenderingServer.frame_post_draw
	TestOutput.save_png(self,root.get_texture().get_image(),"depot_panels.png")
	var hud = game.get_node("Interface")
	var screen := Rect2(Vector2.ZERO,Vector2(root.size))
	var energy: Rect2 = hud.depot_panel.get_global_rect()
	var storage: Rect2 = hud.storage_panel.get_global_rect()
	var bottom: Rect2 = hud.get_node("Bottom").get_global_rect()
	if not check(hud.depot_panel.visible and hud.storage_panel.visible,"Both panels should show for your Depot"): return
	if not check(screen.encloses(energy) and screen.encloses(storage),"The panels should be on screen: %s %s" % [energy,storage]): return
	if not check(energy.size.y > 60 and storage.size.y > 30 and energy.position.x < 40 and storage.end.x > root.size.x-40,"The panels should be top left and top right: %s %s" % [energy,storage]): return
	if not check(not energy.intersects(storage) and not energy.intersects(bottom) and not storage.intersects(bottom),"The panels should not overlap each other or the bottom HUD"): return
	if not check(hud.feed.get_global_rect().position.y >= storage.end.y,"The alert feed should sit below the storage panel"): return
	print("DEPOT_PANELS_RUNTIME_CHECK_PASSED energy=%s storage=%s" % [energy,storage])
	quit(0)
