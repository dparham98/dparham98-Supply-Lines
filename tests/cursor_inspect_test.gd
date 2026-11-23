extends SceneTree
# Headless: the game cursor and inspecting wood (docs/CURSORS.md). The cursor images load at their size; the overlay
# shows the pointer over open ground, the ring over your units, the crosshair over an enemy, the magnifier over
# Forest, and the axe over Forest with a worker selected. A click on a Forest tile selects it: the HUD shows the tile's
# size, the wood left on it and in its whole wood, and follows felling until the tile is cut out. Coal works the same.
const Cursor = preload("res://scripts/ui/game_cursor.gd")
var game: Node3D
var hud: CanvasLayer
var overlay: Control
var manager: Node
var camera: Camera3D
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> bool:
	if value: return true
	push_error(message); quit(1); return false
func screen_of(point: Vector3) -> Vector2: return camera.unproject_position(point)
func hover(point: Vector3) -> String:
	overlay.hovered = overlay.hover_target(screen_of(point))
	return Cursor.kind_for(overlay.hovered,game)
func click(point: Vector3) -> void:
	for pressed in [true,false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = screen_of(point)
		event.pressed = pressed
		manager._unhandled_input(event)
	hud._process(0)
## A Forest (or Coal) cell near `near` with only its own kind of ground round it, so nothing else is picked there.
func cell_of(terrain: int, near: Vector3) -> Vector2i:
	var ground = game.ground
	var centre: Vector2i = ground.get_tile_at_position(near)
	for r in range(2,160):
		for dx in range(-r,r+1):
			for dz in [-r,r]:
				for cell in [centre+Vector2i(dx,dz),centre+Vector2i(dz,dx)]:
					if not ground.is_tile_in_bounds(cell) or ground.get_terrain(cell) != terrain: continue
					var clear := true
					for ox in range(-2,3):
						for oz in range(-2,3):
							if ground.get_terrain(cell+Vector2i(ox,oz)) != terrain: clear = false
					if clear and manager.pick_object(screen_of(ground.tile_to_world(cell))) == null: return cell
	return Vector2i(-1,-1)
func look_at_cell(cell: Vector2i) -> Vector3:
	var at: Vector3 = game.ground.tile_to_world(cell)
	var rig: Node = game.get_node("CameraRig")
	rig.focus_position(at,40)
	for frame in range(300): rig.advance_camera(1.0/60)
	return at
func run() -> void:
	root.size = Vector2i(1280,900)
	game = load("res://scenes/maps/lakes_skirmish.tscn").instantiate()
	root.add_child(game)
	for frame in range(3): await process_frame
	game.set_process(false)
	hud = game.get_node("Interface"); hud.set_process(false)
	overlay = hud.get_node("MapOverlay"); overlay.set_process(false)
	manager = root.get_node("SelectionManager")
	camera = get_root().get_camera_3d()
	game.get_node("CameraRig").set_process(false)
	for node in get_nodes_in_group("units"): node.set_process(false)
	# The images: 32 px, one per kind, installed as cursor shapes.
	for id in Cursor.IMAGES:
		var image: Texture2D = Cursor.IMAGES[id]
		if not check(image.get_width() == 32 and image.get_height() == 32,"%s cursor should be 32 px" % id): return
	if not check(Cursor._installed and Cursor.SHAPES.has(Cursor.shown),"The overlay installs the cursors and shows one: %s" % Cursor.shown): return
	# Over your Depot: the ring. Over open grass: the pointer.
	var depot: Node3D = game.depot
	look_at_cell(game.ground.get_tile_at_position(depot.global_position))
	if not check(hover(depot.global_position) == "select","Your Depot should show the select cursor: %s" % hover(depot.global_position)): return
	# An enemy unit: the crosshair.
	var foe: Node3D = load("res://scenes/gameplay/infantry.tscn").instantiate()
	foe.team = "enemy"
	game.get_node("Entities/Units").add_child(foe)
	foe.global_position = depot.global_position+Vector3(14,0,14)
	foe.set_process(false)
	await process_frame
	if not check(hover(foe.global_position+Vector3.UP) == "attack","An enemy should show the crosshair: %s" % hover(foe.global_position+Vector3.UP)): return
	foe.free()
	# A Forest tile: the magnifier, and with a worker selected, the axe.
	var forest := cell_of(3,depot.global_position)
	if not check(forest.x >= 0,"No open Forest near the Depot"): return
	var spot := look_at_cell(forest)
	forest = cell_of(3,spot)
	spot = game.ground.tile_to_world(forest)
	if not check(hover(spot) == "inspect" and overlay.hovered.is_in_group("forest_cells") and overlay.hovered.cell == forest,"Forest should show the inspect cursor"): return
	overlay.update_hover_card(screen_of(spot))
	if not check(overlay.card.get_node("Body/Name").text == "Forest" and overlay.card.get_node("Body/Line").text.begins_with("20 / 20 wood"),"The hover card names the Forest and its wood: %s" % overlay.card.get_node("Body/Line").text): return
	var worker: Node3D = get_nodes_in_group("units").filter(func(u): return u.team == "player" and u.can_gather and not u.is_cargo_vehicle and not u.is_depot_truck)[0]
	worker.set_selected(true)
	if not check(hover(spot) == "gather","Forest with a worker selected should show the axe"): return
	game.pending_unit_command = "move"
	if not check(hover(spot) == "pointer","An armed command keeps the pointer"): return
	game.pending_unit_command = ""
	worker.set_selected(false)
	# Open ground shows the pointer.
	var grass: Vector2i = cell_of(0,spot)
	if not check(grass.x >= 0 and hover(game.ground.tile_to_world(grass)) == "pointer","Open ground should show the pointer"): return
	# The overlay sets the shape it chose.
	overlay.hovered = null
	overlay._hover_mouse = screen_of(spot)
	Input.warp_mouse(screen_of(spot))
	Cursor.use(Cursor.kind_for(overlay.hover_target(screen_of(spot)),game))
	if not check(Cursor.shown == "inspect","The inspect shape should be in use"): return
	# A click on the Forest tile selects it; the HUD shows its size, its wood and the whole wood's.
	click(spot)
	var tile = game.selected_building
	if not check(is_instance_valid(tile) and tile.is_in_group("forest_cells") and tile.cell == forest,"The click should select the Forest tile: %s" % tile): return
	if not check(hud.selected_object() == tile and hud.name_label.text == "Forest tile","The HUD shows the Forest tile: %s" % hud.name_label.text): return
	var details: String = hud.info.get_node("Details").text
	if not check(hud.info.get_node("HealthText").text == "20 / 20 wood left","Wood left: %s" % hud.info.get_node("HealthText").text): return
	if not check(details.begins_with("Tile 1 × 1 m · cell %d, %d" % [forest.x,forest.y]),"Tile size: %s" % details): return
	var patch: Dictionary = game.ground.forest_patch(forest)
	if not check(patch.tiles > 25 and patch.wood > 0 and patch.wood <= patch.tiles*20,"The wood's size: %s" % [patch]): return
	if not check(details.contains("This wood: ") and details.contains("tiles"),"The whole wood: %s" % details): return
	if not check(hud.desired_buttons.is_empty(),"A Forest tile has no commands: %s" % [hud.desired_buttons]): return
	# Felling shows; a tile cut out drops out of the selection.
	game.ground.harvest_forest(forest,5)
	hud._process(0)
	if not check(hud.info.get_node("HealthText").text == "15 / 20 wood left","Wood left after felling: %s" % hud.info.get_node("HealthText").text): return
	game.ground.harvest_forest(forest,15)
	hud._process(0)
	if not check(hud.selected_object() == null,"A cut-out tile should not stay shown"): return
	# A click on a unit replaces it, and a click on a Coal tile shows the coal.
	var coal := cell_of(6,depot.global_position)
	if coal.x >= 0:
		var seam := look_at_cell(coal)
		coal = cell_of(6,seam)
		click(game.ground.tile_to_world(coal))
		if not check(hud.name_label.text == "Coal tile" and hud.info.get_node("Details").text.contains("This seam:"),"A Coal tile shows its coal: %s" % hud.name_label.text): return
	# Shift-click on a Forest tile keeps the selection as it was.
	worker.set_selected(true)
	game.selected_building = null
	var other := cell_of(3,spot)
	look_at_cell(other)
	for pressed in [true,false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = screen_of(game.ground.tile_to_world(other))
		event.pressed = pressed
		event.shift_pressed = true
		manager._unhandled_input(event)
	if not check(worker.is_selected and game.selected_building == null,"Shift-click on Forest should keep the selection"): return
	print("CURSOR_INSPECT_TEST_PASSED")
	quit(0)
