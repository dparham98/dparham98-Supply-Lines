extends SceneTree
# Headless: inspecting enemies and selecting several buildings of one type (docs/SELECTION_INSPECT.md). A click on an
# enemy unit shows its stats with no orders; double-click on a Barracks selects your Barracks on screen, Shift-click
# removes or adds one, production goes to the one with the shortest queue, and power and rally apply to all.
var game: Node3D
var network: Node
var hud: CanvasLayer
var manager: Node
var camera: Camera3D
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> bool:
	if ok: return true
	push_error(message); quit(1); return false
func site(kind: StringName, near: Vector3, taken: Array) -> Vector3:
	var spec: Dictionary = network.plan_spec(kind)
	for radius in range(10,100,4):
		for offset in [Vector3(radius,0,0),Vector3(-radius,0,0),Vector3(0,0,radius),Vector3(0,0,-radius)]:
			var point: Vector3 = near+offset
			var start: Vector2i = network.footprint_start(point,spec.size)
			if taken.any(func(p): return p.distance_to(point) < 8.0): continue
			if network.plan_terrain_valid(start,spec.size,kind) and not network.plan_overlaps(start,spec.size) and network.can_place_size(point,game.depot,spec.size): return point
	return Vector3.INF
func build(kind: StringName, taken: Array) -> Node3D:
	var point := site(kind,game.depot.global_position,taken)
	if point == Vector3.INF: return null
	taken.append(point)
	var plan = network.queue_plan(point,kind)
	if plan == null: return null
	plan.set_process(false)
	var building: Node3D = plan.complete_from_stock()
	if building != null: building.set_process(false)
	return building
func click(node: Node3D, shift := false, double := false) -> void:
	var at: Vector2 = camera.unproject_position(node.global_position+Vector3.UP*1.0)
	manager.start_selection(at)
	manager._same_type_pending = double
	manager.end_selection(at,null,shift)
	hud._process(0)
func run() -> void:
	root.size = Vector2i(1280,900)
	game = load("res://scenes/maps/balanced_skirmish.tscn").instantiate()
	root.add_child(game)
	for i in range(3): await process_frame
	network = game.get_node("DepotNetwork")
	hud = game.get_node("Interface")
	manager = root.get_node("SelectionManager")
	game.set_process(false)
	hud.set_process(false)
	for unit in get_nodes_in_group("units"): unit.set_process(false)
	for depot in get_nodes_in_group("depots"): depot.set_process(false)
	var depot = game.depot
	depot.storage_capacity = 100000
	depot.energy = 20000; depot.iron = 20000
	var rig = game.get_node("CameraRig"); rig.set_process(false)
	camera = rig.camera
	# --- An enemy unit, brought beside the Depot, is inspected by a click.
	var enemy: Node3D
	for unit in get_nodes_in_group("units"):
		if unit.team != "player": enemy = unit; break
	if not check(enemy != null,"The map needs an enemy unit"): return
	var taken: Array = []
	var barracks: Array[Node3D] = []
	for i in range(3):
		var building := build(&"barracks",taken)
		if not check(building != null,"Barracks %d could not be placed" % (i+1)): return
		barracks.append(building)
	rig.focus_position(depot.global_position,110)
	for frame in range(300): rig.advance_camera(1.0/60)
	# A spot clear of the Depot and the Barracks.
	for offset in [Vector3(0,0,-16),Vector3(0,0,16),Vector3(16,0,0),Vector3(-16,0,0),Vector3(16,0,16),Vector3(-16,0,-16),Vector3(16,0,-16),Vector3(-16,0,16)]:
		var spot: Vector3 = depot.global_position+offset
		if barracks.all(func(b): return b.global_position.distance_to(spot) > 9.0): enemy.global_position = spot; break
	for unit in get_nodes_in_group("units"):
		if unit != enemy and unit.global_position.distance_to(enemy.global_position) < 5.0: unit.global_position += Vector3(40,0,0)
	var own: Node3D = get_nodes_in_group("units").filter(func(u): return u.team == "player")[0]
	own.set_selected(true)
	click(enemy)
	if not check(game.selected_building == enemy and hud.selected_object() == enemy and hud.selected_units().is_empty(),"A click on an enemy unit should inspect it and drop your units"): return
	if not check(not enemy.is_selected and hud.desired_buttons.is_empty(),"An enemy unit takes no orders: %s" % [hud.desired_buttons]): return
	if not check("INSPECT" in hud.commands.get_node("Title").text and hud.info.get_node("HealthText").text == "Health %d / %d" % [enemy.health,enemy.max_health],"The card should show the enemy's stats: %s" % hud.commands.get_node("Title").text): return
	if not check(hud.name_label.text == hud.object_name(enemy) and game.rally_building() == null,"The name shows the enemy unit's type: %s" % hud.name_label.text): return
	# Health and stats only: nothing about its fuel, cargo or what it is doing.
	enemy.fuel = 0.0
	enemy.out_of_fuel = true
	hud._process(0)
	var shown_bars: Array = hud.bars.get_children().filter(func(bar): return bar.visible)
	if not check(shown_bars.is_empty() and hud.info.get_node("Details").text.is_empty() and not hud.info.get_node("Storage").visible,"An enemy unit should not show fuel or cargo: bars %s, details '%s'" % [shown_bars.map(func(bar): return str(bar.name)),hud.info.get_node("Details").text]): return
	if not check(hud.state_label.text == hud.team_label(enemy) and hud.context.get_node("Stats").visible,"An enemy unit shows its team and stats, not its state: '%s'" % hud.state_label.text): return
	var mark: Dictionary = game.get_node("Interface/MapOverlay").status_for(enemy)
	if not check(mark.icons.is_empty() and mark.carry.is_empty() and mark.storage.is_empty(),"The marks over an enemy unit should not show fuel or cargo: %s" % [mark.icons]): return
	enemy.out_of_fuel = false
	# Right-click with nothing of yours selected gives no order and sets no rally.
	game.issue_order(camera.unproject_position(depot.global_position+Vector3(10,0,10)))
	if not check(enemy.order_queue.is_empty(),"Right-click must not order an enemy unit"): return
	# A dead enemy is no longer shown.
	var health: int = enemy.health
	enemy.health = 0
	if not check(hud.selected_object() == null,"A dead enemy is no longer shown"): return
	enemy.health = health
	enemy.global_position += Vector3(0,0,-60)
	# --- Barracks: a click selects one, double-click all three on screen.
	click(barracks[0])
	if not check(game.selected_building == barracks[0] and game.building_selection() == [barracks[0]],"A click selects one Barracks"): return
	click(barracks[1],false,true)
	var all: Array[Node3D] = game.building_selection()
	if not check(all.size() == 3 and all[0] == barracks[1] and barracks.all(func(b): return all.has(b)),"Double-click should select all three Barracks, the clicked one first: %d" % all.size()): return
	if not check(game.selected_building == barracks[1] and hud.name_label.text == "3 × %s" % hud.object_name(barracks[1]),"The name counts them: %s" % hud.name_label.text): return
	if not check(hud.portraits.visible and hud.portrait_units.size() == 3,"Three portraits should show"): return
	if not check(barracks.all(func(b): return b.get_node("Visuals/TeamMarker").visible),"Every selected Barracks shows its team marker"): return
	# Production goes to the shortest queue.
	barracks[1].request_unit(&"infantry")
	barracks[1].request_unit(&"infantry")
	barracks[0].request_unit(&"infantry")
	hud.card.get_node("PrintInfantry").pressed.emit()
	if not check(barracks[2].queue == 1 and barracks[1].queue == 2 and barracks[0].queue == 1,"The order goes to the idle Barracks: %d %d %d" % [barracks[0].queue,barracks[1].queue,barracks[2].queue]): return
	hud.card.get_node("PrintInfantry").pressed.emit()
	if not check(barracks[0].queue == 2 or barracks[2].queue == 2,"The next goes to a Barracks with one queued"): return
	# Power applies to all.
	hud._process(0)
	hud.production_panel.get_node("Body/PowerSlider").value = 2.0
	if not check(barracks.all(func(b): return b.power == 2.0),"Power should apply to every selected Barracks"): return
	# A rally applies to all.
	game.set_rally(camera.unproject_position(depot.global_position+Vector3(12,0,12)))
	if not check(barracks.all(func(b): return b.rally_points.size() == 1),"The rally should apply to every selected Barracks"): return
	# Shift-click removes one; Shift-click adds it back.
	click(barracks[2],true)
	all = game.building_selection()
	if not check(all.size() == 2 and not all.has(barracks[2]) and not barracks[2].get_node("Visuals/TeamMarker").visible,"Shift-click should remove that Barracks"): return
	click(barracks[2],true)
	if not check(game.building_selection().size() == 3,"Shift-click should add it again"): return
	# Shift-click on a different type starts again with it.
	click(depot,true)
	if not check(game.building_selection() == [depot] and not barracks[0].get_node("Visuals/TeamMarker").visible,"Shift-click on another type selects only it"): return
	# A control group keeps several buildings.
	click(barracks[0],false,true)
	manager.save_group(4)
	click(depot)
	manager.recall_group(4)
	if not check(game.building_selection().size() == 3,"A control group should keep all three Barracks"): return
	# A portrait click keeps only that building.
	hud._process(0)
	var keep: Node3D = hud.portrait_units[1]
	hud.pick_portrait(1)
	if not check(game.building_selection() == [keep] and game.selected_building == keep,"A portrait click keeps only that Barracks"): return
	print("INSPECT_SELECT_TEST_PASSED")
	quit(0)
