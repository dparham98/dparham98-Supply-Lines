extends SceneTree
# UI phase C map overlay: when bars, progress, icons, rings, carry, routes, hover and pop-ups appear.
var game: Node3D
var hud: CanvasLayer
var overlay: Control
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> bool:
	if value: return true
	Input.action_release("map_show_all")
	push_error(message); quit(1); return false
func spawn(path: String, offset: Vector3) -> Node3D:
	var unit = load(path).instantiate()
	unit.position = game.depot.global_position+offset
	game.get_node("Entities/Units").add_child(unit)
	unit.set_process(false)
	return unit
func has_icon(entry: Dictionary, id: String) -> bool:
	for icon in entry.icons:
		if icon[0] == id: return true
	return false
func run() -> void:
	root.size = Vector2i(1280,900)
	game = load("res://scenes/maps/resource_skirmish.tscn").instantiate()
	root.add_child(game); await process_frame
	game.set_process(false)
	hud = game.get_node("Interface"); hud.set_process(false)
	overlay = hud.get_node("MapOverlay"); overlay.set_process(false)
	for group in ["units","depots"]:
		for node in get_nodes_in_group(group): node.set_process(false)
	var rig = game.get_node("CameraRig"); rig.set_process(false)
	var depot = game.depot
	rig.focus_position(depot.global_position+Vector3(4,0,12),45)
	for frame in range(180): rig.advance_camera(1.0/60)
	for node in get_nodes_in_group("units"): node.set_selected(false)
	game.selected_building = null
	var worker = game.get_node("Entities/Units/Infantry")
	# Labels: the always-on text labels are hidden at runtime.
	overlay._process(0)
	if not check(not worker.get_node("Status").visible and not depot.get_node("Progress").visible,"Actor text labels still shown"): return
	# Health bars: hidden at full health, shown when damaged, selected, hovered or with Alt.
	if not check(overlay.status_for(worker).health < 0,"Full-health unselected unit shows a bar"): return
	worker.health -= 10
	if not check(is_equal_approx(overlay.status_for(worker).health,float(worker.health)/worker.max_health),"Damaged unit has no bar"): return
	worker.health = worker.max_health
	worker.set_selected(true)
	if not check(overlay.status_for(worker).health >= 0,"Selected unit has no bar"): return
	worker.set_selected(false)
	overlay.hovered = worker
	if not check(overlay.status_for(worker).health >= 0,"Hovered unit has no bar"): return
	overlay.hovered = null
	Input.action_press("map_show_all")
	if not check(overlay.status_for(worker).health >= 0 and overlay.status_for(depot).health >= 0,"Alt does not show all bars"): return
	Input.action_release("map_show_all")
	# Buildings: production progress only while queued, storage warning, under attack, capture ring.
	if not check(overlay.status_for(depot).progress < 0,"Idle Depot shows progress"): return
	depot.energy = 1000; depot.iron = 1000
	depot.request_cargo(); depot.progress = depot.print_seconds*0.4
	if not check(is_equal_approx(overlay.status_for(depot).progress,0.4),"Producing Depot lacks progress"): return
	depot.queue = 0; depot.pending.clear(); depot.progress = 0; depot.energy = 500; depot.iron = 500
	depot.stockpile.set_amount(&"wood",depot.stockpile.amount(&"wood")+depot.stockpile.space())
	if not check(has_icon(overlay.status_for(depot),"depot"),"Full storage icon missing"): return
	depot.stockpile.set_amount(&"wood",0)
	if not check(not has_icon(overlay.status_for(depot),"depot"),"Storage icon shown below 90%"): return
	game.mark_attacked(depot)
	if not check(has_icon(overlay.status_for(depot),"attack"),"Under attack icon missing"): return
	game.attacked_at[depot.get_instance_id()] -= game.ATTACK_MARK_SECONDS+1
	if not check(not has_icon(overlay.status_for(depot),"attack"),"Under attack icon outlived its window"): return
	depot.capture_team = "enemy"; depot.capture_progress = depot.rules.capture_seconds*0.25
	if not check(is_equal_approx(overlay.status_for(depot).capture,0.25),"Capture ring missing"): return
	depot.capture_progress = 0; depot.capture_team = ""
	var mine = get_first_node_in_group("mines")
	if mine != null:
		var reserves: int = mine.remaining
		mine.remaining = 0
		if not check(has_icon(overlay.status_for(mine),"mine"),"Depleted mine icon missing"): return
		mine.remaining = reserves
	# Units: carried cargo and fuel warnings.
	worker.cargo = 6; worker.cargo_kind = &"wood"
	var carry: Dictionary = overlay.status_for(worker).carry
	if not check(not carry.is_empty() and is_equal_approx(carry.ratio,0.6) and carry.color == overlay.RESOURCE_COLORS[&"wood"],"Carry bar wrong"): return
	worker.cargo = 0
	var tank = spawn("res://scenes/gameplay/tank.tscn",Vector3(14,0,14))
	tank.fuel = 5
	if not check(has_icon(overlay.status_for(tank),"refuel"),"Low fuel icon missing"): return
	# Route line only for a selected routed vehicle.
	var truck = spawn("res://scenes/gameplay/cargo_vehicle.tscn",Vector3(-14,0,10))
	var outpost = load("res://scenes/gameplay/depot.tscn").instantiate()
	outpost.name = "MapOutpost"; outpost.team = "player"
	outpost.position = depot.global_position+Vector3(60,0,0)
	game.get_node("Entities/Buildings").add_child(outpost); outpost.set_process(false)
	truck.start_supply_route(depot,outpost,10,0,true)
	if not check(overlay.route_lines().is_empty(),"Route line for an unselected vehicle"): return
	truck.set_selected(true)
	if not check(overlay.route_lines().size() == 1,"Selected routed vehicle has no route line"): return
	truck.set_selected(false); truck.cancel_supply_route()
	# Hover card: real pointer position picks the actor and fills the card.
	var screen: Vector2 = game.get_viewport().get_camera_3d().unproject_position(depot.global_position)
	if not check(overlay.hover_target(screen) == depot,"Hover did not pick the Depot"): return
	overlay.hovered = depot
	overlay.update_hover_card(screen)
	if not check(overlay.card.visible and overlay.card.get_node("Body/Name").text == "Depot" and "Storage" in overlay.card.get_node("Body/Line").text and overlay.card.get_node("Body/Meter").visible,"Hover card wrong"): return
	var pile = game.get_node("Entities/Resources/TestingCoalPile")
	overlay.hovered = pile
	overlay.update_hover_card(screen)
	if not check(overlay.card.get_node("Body/Name").text == "Coal pile" and "left" in overlay.card.get_node("Body/Line").text,"Pile hover card wrong"): return
	overlay.hovered = null; overlay.update_hover_card(screen)
	if not check(not overlay.card.visible,"Hover card stayed without a target"): return
	# Delivery pop-ups come from real deliveries.
	worker.cargo = 10; worker.cargo_kind = &"iron"
	worker.global_position = depot.global_position+Vector3(0,0,depot.dropoff_range-1)
	worker.command_return(depot)
	for i in 120:
		worker._process(1.0/60)
		if worker.cargo == 0: break
	if not check(worker.cargo == 0 and overlay.popups.size() == 1 and overlay.popups[0].text == "+10 iron" and overlay.popups[0].node == depot,"Delivery pop-up missing: %s" % [overlay.popups]): return
	print("MAP_STATUS_TEST_PASSED")
	quit(0)
