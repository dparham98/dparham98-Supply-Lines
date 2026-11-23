extends SceneTree
# Depot range and Generator assignment (docs/DEPOT_RANGE.md): the halved range, Generators taking the
# Depot they stand in, no Assign Depot command, and the range ring in the Deploy preview.
var game: Node3D
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> bool:
	if value: return true
	push_error(message); quit(1); return false
func run() -> void:
	root.size = Vector2i(1280,900)
	game = load("res://scenes/maps/resource_skirmish.tscn").instantiate()
	root.add_child(game)
	for frame in range(3): await process_frame
	game.set_process(false)
	var depot: Node3D = game.depot
	var network = game.get_node("DepotNetwork")
	var hud = game.get_node("Interface")
	if not check(is_equal_approx(depot.rules.construction_radius,26.25) and is_equal_approx(SupplySource.radius(depot),26.25) and is_equal_approx(depot.get_node("Territory").scale.x,26.25),"The Depot range should be 26.25 m"): return
	# No Assign Depot anywhere.
	if not check(not InputMap.has_action("command_assign_depot") and not hud.card.has_node("AssignDepot"),"Assign Depot should be gone"): return
	# A Generator with no Depot given takes the one whose range it stands in.
	var second: Node3D = network.establish(depot.global_position+Vector3(30,0,0),0,0)
	second.set_process(false)
	var generator: Node3D = load("res://scenes/gameplay/energy_generator.tscn").instantiate()
	generator.rules = network.supply_rules
	generator.position = depot.global_position+Vector3(11,0,8)
	game.get_node("Entities/Buildings").add_child(generator)
	await process_frame
	if not check(generator.assigned_depot == depot,"A Generator should take the nearest Depot covering it, got %s" % generator.assigned_depot): return
	if not check(SupplySource.covers(second,generator.global_position,"player"),"The test needs the second Depot to cover the Generator too"): return
	# Its Depot lost, it takes the other covering one.
	depot.team = "enemy"
	generator._process(0.6)
	if not check(generator.assigned_depot == second,"A Generator should find another covering Depot when its own is lost"): return
	depot.team = "player"
	# Outside every range it has no Depot.
	var lone: Node3D = load("res://scenes/gameplay/energy_generator.tscn").instantiate()
	lone.rules = network.supply_rules
	lone.position = depot.global_position+Vector3(-40,0,-30)
	game.get_node("Entities/Buildings").add_child(lone)
	await process_frame
	if not lone.is_queued_for_deletion():
		if not check(lone.assigned_depot == null,"A Generator outside every range should have no Depot"): return
	# Placing a building shows every friendly Depot's range, and so does any building selected (docs/HUD_POLISH.md);
	# with nothing selected and nothing being placed, none shows.
	network.select_depot(null)
	game.selected_building = null
	game.global_plan_kind = &"generator"
	network._process(0.0)
	if not check(depot.get_node("Territory").visible and second.get_node("Territory").visible,"Placing a building should show every friendly Depot's range"): return
	game.global_plan_kind = &""
	network._process(0.0)
	if not check(not depot.get_node("Territory").visible and not second.get_node("Territory").visible,"With nothing selected and nothing placed, no range should show"): return
	network.select_depot(depot)
	network._process(0.0)
	if not check(depot.get_node("Territory").visible and second.get_node("Territory").visible,"With a Depot selected every friendly Depot's range should show"): return
	# Deploy preview: a selected Depot Truck waiting for a site shows the footprint and the range ring.
	var truck: Node3D = load("res://scenes/gameplay/depot_truck.tscn").instantiate()
	truck.position = depot.global_position+Vector3(-90,0,-90)
	game.get_node("Entities/Units").add_child(truck)
	await process_frame
	truck.set_process(false)
	for unit in get_nodes_in_group("units"): unit.set_selected(unit == truck)
	game.pending_unit_command = "deploy"
	if not check(network.deploying_truck() == truck,"Deploy should find the selected truck"): return
	network._process(0.0)
	if not check(depot.get_node("Territory").visible and second.get_node("Territory").visible,"Choosing a Deploy site should show every friendly Depot's range"): return
	var ghost = game.get_node("ConstructionPreview")
	var far: Vector3 = truck.global_position
	var valid: bool = network.update_deploy_preview(far,truck)
	var ring: Node3D = ghost.get_node("Range")
	if not check(ring.visible and is_equal_approx(ring.scale.x,26.25),"The Deploy preview should show the range ring"): return
	if not check(network.placement_text.begins_with("DEPLOY" if valid else "BLOCKED"),"The Deploy preview status is wrong: "+network.placement_text): return
	# Next to the existing Depot it is blocked by spacing, and says so.
	if not check(not network.update_deploy_preview(depot.global_position+Vector3(40,0,0),truck) and network.placement_text.contains("52.5 m") and network.placement_text.contains("overlap"),"A Deploy site too close should be blocked for spacing: "+network.placement_text): return
	# Other placements hide the ring.
	game.pending_unit_command = ""
	network.update_preview(depot.global_position,true)
	if not check(not ring.visible,"A Generator placement should not show the Depot range"): return
	print("DEPOT_RANGE_TEST_PASSED")
	quit(0)
