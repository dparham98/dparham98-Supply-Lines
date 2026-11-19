extends SceneTree
# Headless: unit portraits (docs/UNIT_PORTRAITS.md). A selected Infantry shows its painted portrait in the Ornament
# frame; a selected Depot shows none.
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> bool:
	if value: return true
	push_error(message); quit(1); return false
func run() -> void:
	var game: Node3D = load("res://scenes/maps/resource_skirmish.tscn").instantiate()
	root.add_child(game)
	for frame in range(3): await process_frame
	game.set_process(false)
	var hud = game.get_node("Interface")
	var portrait: TextureRect = hud.get_node("Bottom/Body/Row/Ornament/Portrait")
	var infantry: Node3D
	for unit in get_nodes_in_group("units"):
		unit.set_process(false); unit.set_selected(false)
		if infantry == null and unit.team == "player" and unit.unit_stats != null and unit.unit_stats.unit_id == &"infantry": infantry = unit
	if not check(infantry != null,"No Infantry"): return
	infantry.set_selected(true)
	game.selected_building = null
	for frame in range(3): await process_frame
	if not check(portrait.visible and portrait.texture != null and portrait.texture.resource_path == "res://assets/ui/portraits/infantry.png","The Infantry portrait should show"): return
	infantry.set_selected(false)
	game.selected_building = game.depot
	for frame in range(3): await process_frame
	if not check(not portrait.visible,"A Depot has no portrait"): return
	print("UNIT_PORTRAITS_TEST_PASSED")
	quit(0)
