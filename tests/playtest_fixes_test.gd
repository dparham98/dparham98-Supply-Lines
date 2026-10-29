extends SceneTree
# Fixes from the 2026-10-29 physical playtest: fixed hover line, hotkeys everywhere, validated
# Depot Truck deploys, building groups, no edge pan over the HUD, supply picker, Depot hover bars,
# armed-command cursor and attack-move.
var game: Node3D
var hud: CanvasLayer
var overlay: Control
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> bool:
	if value: return true
	push_error(message); quit(1); return false
func select(unit: Node3D, building: Node3D = null) -> void:
	game.selected_building = building
	for node in get_nodes_in_group("units"): node.set_selected(node == unit)
	hud._process(0)
func screen(point: Vector3) -> Vector2:
	return game.get_viewport().get_camera_3d().unproject_position(point)
func spawn(path: String, offset: Vector3) -> Node3D:
	var unit = load(path).instantiate()
	unit.position = game.depot.global_position+offset
	game.get_node("Entities/Units").add_child(unit)
	unit.set_process(false)
	return unit
func run_until(unit: Node3D, condition: Callable, seconds: float) -> bool:
	for i in range(ceili(seconds*60)):
		if not is_instance_valid(unit): return condition.call()
		unit._process(1.0/60)
		if condition.call(): return true
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
	var worker = game.get_node("Entities/Units/Infantry")
	# 1. A long hover text stays on one clipped line and never changes the HUD height.
	select(worker)
	for frame in 4: await process_frame
	hud.hover_label.text = "Attack [A]\nClick a hostile unit or building. Shift queues, Esc cancels, and this line is long."
	for frame in 4: await process_frame
	if not check(is_equal_approx(hud.get_node("Bottom").size.y,260) and hud.hover_label.size.y <= 20,"Hover text moved the HUD (%.0f / %.0f)" % [hud.get_node("Bottom").size.y,hud.hover_label.size.y]): return
	# 1a. The grid never moves: the option row above it is reserved, armed or not.
	var grid_y: float = hud.card.global_position.y
	var cargo = spawn("res://scenes/gameplay/cargo_vehicle.tscn",Vector3(-14,0,10))
	select(cargo)
	game.pending_unit_command = "load"
	hud._process(0)
	for frame in 4: await process_frame
	var armed_y: float = hud.card.global_position.y
	game.pending_unit_command = ""
	select(worker)
	if not check(is_equal_approx(armed_y,grid_y) and is_equal_approx(hud.get_node("Bottom").size.y,260),"Arming Load moved the grid (%.0f to %.0f)" % [grid_y,armed_y]): return
	cargo.free()
	# 2. Every command tile, build tile and header action shows its hotkey.
	var missing := []
	for panel in [hud.card,hud.build_menu.get_node("Actions")]:
		for button in panel.get_children():
			if button is Button and (button.shortcut == null or not button.has_node("Key") or button.get_node("Key").text.is_empty()): missing.append(button.name)
	for id in ["GlobalBuild","Focus"]:
		var header: Button = hud.get_node("Bottom/Body/Header/"+id)
		if header.shortcut == null or not header.text.ends_with(" · "+hud.hotkey_text(header)): missing.append(id)
	if not check(missing.is_empty(),"Actions without a shown hotkey: %s" % [missing]): return
	if not check(hud.build_menu.get_node("Actions/Back/Key").text == "Escape" and hud.build_menu.get_node("Actions/Depot/Key").text == "D","Build tile keys wrong"): return
	# 3a. The supply picker only appears with a choice, and the notes say what it is.
	select(worker)
	if not check(not hud.commands.get_node("OptionRow/LocalSource").visible and "Pays from and delivers to" in hud.info.get_node("Details").text,"Single-source picker shown or unexplained"): return
	# 3. Depot Truck: Deploy is a placement; only a valid footprint is accepted or queued.
	var truck = spawn("res://scenes/gameplay/depot_truck.tscn",Vector3(-20,0,20))
	select(truck)
	hud.card.get_node("DeployTruck").pressed.emit()
	if not check(game.pending_unit_command == "deploy" and overlay.armed_kind() == "deploy","Deploy did not arm a placement"): return
	game.issue_card_order(screen(depot.global_position),true)
	if not check(truck.order_queue.is_empty() and truck.order != "deploy" and "Can't deploy" in game.message and game.pending_unit_command == "deploy","An invalid deploy site was accepted"): return
	var site: Vector3 = truck.global_position
	for offset in [Vector3(-12,0,24),Vector3(-24,0,12),Vector3(-24,0,30),Vector3(-6,0,36)]:
		if game.get_node("DepotNetwork").can_deploy_at(truck,depot.global_position+offset): site = depot.global_position+offset; break
	if not check(game.get_node("DepotNetwork").can_deploy_at(truck,site),"No valid test deploy site"): return
	var depots_before := get_nodes_in_group("depots").size()
	game.issue_card_order(screen(site))
	if not check(truck.order == "deploy" and game.pending_unit_command.is_empty(),"A valid deploy site was refused"): return
	if not check(run_until(truck,func(): return get_nodes_in_group("depots").size() == depots_before+1,40),"Truck did not drive to and deploy at the site"): return
	# 4. Ctrl+number saves a selected building; the number recalls it.
	var manager = root.get_node("SelectionManager")
	select(null,depot)
	manager.save_group(4)
	select(worker)
	manager.recall_group(4)
	if not check(game.selected_building == depot and not worker.is_selected,"Building control group not recalled"): return
	# 5. Edge pan doesn't pass through the bottom HUD.
	if not check(not hud.get_node("Bottom").get_meta("edge_pan_passthrough",false),"Bottom HUD still passes edge pan"): return
	# 7. Hovering a Depot shows its health bar and the resource-split storage bar.
	overlay.hovered = depot
	var entry: Dictionary = overlay.status_for(depot)
	if not check(entry.health >= 0 and not entry.storage.is_empty(),"Hovered Depot lacks health or storage bars"): return
	overlay.update_hover_card(screen(depot.global_position))
	if not check(overlay.card.get_node("Body/Health").visible and overlay.card.get_node("Body/Storage").visible,"Hover card lacks health or storage bars"): return
	overlay.hovered = null
	# 8. Armed commands get a cursor indicator.
	game.pending_unit_command = "attack"
	overlay._process(0)
	if not check(overlay.armed_kind() == "attack" and overlay.ARMED_ICONS.has("attack"),"No cursor indicator for an armed command"): return
	game.pending_unit_command = ""
	overlay._process(0)
	# 9. Attack on open ground is attack-move: stop to fire at foes in range, then carry on.
	var tank = spawn("res://scenes/gameplay/tank.tscn",Vector3(14,0,14))
	var hostile = game.get_node("Entities/Units/Hostile")
	hostile.global_position = tank.global_position+Vector3(4,0,0)
	select(tank)
	game.pending_unit_command = "attack"
	var goal: Vector3 = tank.global_position+Vector3(10,0,-6)
	game.issue_card_order(screen(goal))
	if not check(tank.order == "attack_move" and tank.waypoint_points().size() == 1,"Ground Attack did not attack-move"): return
	var start_health: int = hostile.health
	tank._cooldown = 0
	tank._process(1.0/60)
	if not check(hostile.health < start_health and tank.state.contains("engaging"),"Attack-move did not engage a foe in range"): return
	hostile.global_position = tank.global_position+Vector3(-60,0,0)
	if not check(run_until(tank,func(): return tank.order == "idle",30) and tank.global_position.distance_to(goal) < 2.5,"Attack-move did not continue to its goal"): return
	print("PLAYTEST_FIXES_TEST_PASSED")
	quit(0)
