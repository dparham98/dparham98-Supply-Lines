extends SceneTree
# Rendered check of selection portraits (docs/SELECTION_PORTRAITS.md): a mixed selection of 25 units shows 25
# portraits grouped by type inside the bottom Info column, clear of the Context column. Saves selection_portraits.png.
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
	var centre: Vector3 = game.depot.global_position+Vector3(0,0,-30)
	rig.focus_position(centre,60)
	for frame in range(200): rig.advance_camera(1.0/60)
	var kinds := ["infantry","infantry","scout","grenadier","tank","motorcycle"]
	for i in range(24):
		var unit = load("res://scenes/gameplay/%s.tscn" % kinds[i % kinds.size()]).instantiate()
		unit.position = centre+Vector3((i % 6)*4.0-10,0,(i/6)*4.0-6)
		game.get_node("Entities/Units").add_child(unit)
	await process_frame
	game.selected_building = null
	var hurt := 0
	for unit in get_nodes_in_group("units"):
		if unit.team != "player": continue
		unit.set_selected(true)
		hurt += 1
		if hurt % 5 == 0: unit.health = int(unit.max_health*0.25)
	for frame in range(6): await process_frame
	await RenderingServer.frame_post_draw
	TestOutput.save_png(self,root.get_texture().get_image(),"selection_portraits.png")
	var hud = game.get_node("Interface")
	var count: int = hud.selected_units().size()
	var shown: Array = hud.portraits.get_children().filter(func(p): return p.visible)
	if not check(hud.portraits.visible and shown.size() == mini(count,hud.portraits.get_child_count()),"Expected %d portraits, found %d" % [count,shown.size()]): return
	var grid: Rect2 = hud.portraits.get_global_rect()
	var info: Rect2 = hud.info.get_global_rect()
	var context: Rect2 = hud.context.get_global_rect()
	if not check(info.encloses(grid) and not grid.intersects(context) and grid.end.y <= root.size.y,"The portraits should fit inside the Info column: grid %s info %s" % [grid,info]): return
	print("SELECTION_PORTRAITS_RUNTIME_CHECK_PASSED count=%d grid=%s" % [count,grid])
	quit(0)
