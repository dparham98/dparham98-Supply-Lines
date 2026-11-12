extends SceneTree
# Depot and Depot Truck deaths (docs/DEPOT_MODEL.md): each leaves its model behind as a wreck, gone from
# selection and targeting at once. The death's stand-ins start exactly on the model's own pose, so nothing
# jumps when it dies; then the Depot's roof falls in and burns while the truck's trailer rolls over and a
# front wheel is thrown, both models are scorched, sink, and remove themselves.
const Driven = preload("res://scripts/components/driven_death.gd")
var game: Node3D
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> bool:
	if value: return true
	push_error(message); quit(1); return false
func effect_of(model: Node3D) -> Node:
	for child in model.get_children():
		if child.get_script() == Driven: return child
	return null
## Each driven part's own pose, by stand-in.
func poses(effect: Node) -> Array:
	var out := []
	for pair in effect.driven_parts(): out.append((pair[1] as Node3D).transform)
	return out
func run_to(effect: Node, seconds: float) -> void:
	effect.player.seek(seconds,true)
	effect._process(0.0)
func spawn_truck(near: Vector2i) -> Node3D:
	var network = game.get_node("DepotNetwork")
	var truck: Node3D = network.truck_scene.instantiate()
	var start: Vector2i = game.ground.find_buildable_footprint(near,Vector2i(10,10))
	truck.position = game.ground.tile_to_world(start+Vector2i(5,5))
	game.get_node("Entities/Units").add_child(truck)
	truck.set_process(false)
	return truck
func run() -> void:
	game = load("res://scenes/maps/resource_skirmish.tscn").instantiate()
	root.add_child(game)
	for frame in range(3): await process_frame
	game.set_process(false)
	var network = game.get_node("DepotNetwork")
	# ---- the Depot Truck
	var truck := spawn_truck(Vector2i(220,170))
	var truck_model: Node3D = truck.get_node("Visuals/Model")
	if not check(truck_model.has_death_clip(),"The Depot Truck should have a death"): return
	var tractor: Node3D = truck_model.get_node("Rig/warehouse_root/warehouse_power_unit")
	var deck: Node3D = truck_model.get_node("Rig/warehouse_root/warehouse_deck")
	var wheel: Node3D = truck_model.get_node("Rig/warehouse_root/warehouse_power_unit/warehouse_wheel_FL")
	var rest := {}
	for node in truck_model.get_node("Rig").find_children("*","Node3D",true,false): rest[node] = node.transform
	var deck_up := deck.global_basis.y.normalized()
	truck.take_damage(truck.health)
	if not check(not is_instance_valid(truck) or truck.is_queued_for_deletion(),"The truck should be gone at once"): return
	if not check(truck_model.get_parent() == game and truck_model.dying(),"The truck should leave its model as a wreck"): return
	var effect := effect_of(truck_model)
	if not check(effect != null and effect.player.has_animation(&"Death"),"The wreck should carry its death"): return
	if not check(effect.driven_parts().size() >= 15,"The truck's death drives too few parts: %d" % effect.driven_parts().size()): return
	for pair in effect.driven_parts():
		var part: Node3D = pair[1]
		if not check(part.transform.is_equal_approx(rest[part]) or (part.transform.origin.distance_to(rest[part].origin) < 0.01 and part.transform.basis.is_equal_approx(rest[part].basis)),"%s should start on its own pose (%s against %s)" % [part.name,part.transform,rest[part]]): return
	var wheel_start := wheel.global_position
	run_to(effect,2.2)
	if not check(rad_to_deg(deck.global_basis.y.normalized().angle_to(deck_up)) > 40.0,"The trailer should have rolled over"): return
	if not check(wheel.global_position.distance_to(wheel_start) > 2.0,"A front wheel should be thrown off"): return
	if not check(effect._scorch.albedo_color.a > 0.5,"The wreck should be burnt"): return
	run_to(effect,effect.player.get_animation(&"Death").length-0.05)
	if not check(tractor.global_position.y < truck_model.global_position.y-2.5,"The wreck should sink out of sight"): return
	effect.player.advance(1.0)
	await process_frame
	await process_frame
	if not check(not is_instance_valid(truck_model),"The truck's wreck should remove itself"): return
	# ---- the Depot: deploy one, let it finish unfolding, then destroy it.
	var builder := spawn_truck(Vector2i(160,230))
	builder.set_selected(true)
	if not check(network.deploy_selected_truck(),"Deploy failed"): return
	var depot: Node3D = network.selected
	depot.set_process(false)
	var model: Node3D = depot.get_node("Visuals/Model")
	await create_timer(model.line_up_seconds+0.2).timeout
	model.player.advance(model.player.current_animation_length)
	await process_frame
	if not check(model.has_death_clip() and not model.deploying(),"The Depot should have unfolded and have a death"): return
	var ridge: Node3D = model.find_child("warehouse_ridge",true,false)
	var tarp: Node3D = model.find_child("warehouse_tarp_L",true,false)
	var depot_tractor: Node3D = model.get_node("Warehouse/warehouse_root/warehouse_power_unit")
	rest.clear()
	for node in model.get_node("Warehouse").find_children("*","Node3D",true,false): rest[node] = node.transform
	var ridge_y := ridge.global_position.y
	var tarp_y := tarp.global_position.y
	var tractor_local := depot_tractor.transform
	depot.take_damage(depot.max_health)
	if not check(not depot.is_in_group("depots") and not depot.is_in_group("selectable_buildings"),"A destroyed Depot should not be selectable or a Depot any more"): return
	if not check(model.get_parent() == game and model.dying(),"The Depot should leave its model as a wreck"): return
	effect = effect_of(model)
	if not check(effect != null and effect.driven_parts().size() >= 40,"The Depot's death drives too few parts"): return
	if not check(effect.driven_parts().all(func(p): return model.get_node("Warehouse").is_ancestor_of(p[1])),"Only the Depot's own parts are driven, not the truck being built"): return
	for pair in effect.driven_parts():
		var part: Node3D = pair[1]
		if not check(part.transform.origin.distance_to(rest[part].origin) < 0.01 and part.transform.basis.is_equal_approx(rest[part].basis),"%s should start on its own pose (%s against %s)" % [part.name,part.transform,rest[part]]): return
	if not check(not model.assembly.visible and not model.player.is_playing(),"The Depot's own clips stop when it dies"): return
	run_to(effect,2.0)
	if not check(ridge.global_position.y < ridge_y-2.5,"The ridge should have fallen (%.2f from %.2f)" % [ridge.global_position.y,ridge_y]): return
	if not check(tarp.global_position.y < tarp_y-1.0,"The roof should have fallen in"): return
	if not check(depot_tractor.transform.is_equal_approx(tractor_local),"The tractor stays where it was, wherever that is"): return
	if not check(effect._scorch.albedo_color.a > 0.5,"The wreck should be burnt"): return
	run_to(effect,effect.player.get_animation(&"Death").length-0.05)
	if not check(ridge.global_position.y < model.global_position.y,"The wreck should sink out of sight"): return
	effect.player.advance(1.0)
	await process_frame
	await process_frame
	if not check(not is_instance_valid(model),"The Depot's wreck should remove itself"): return
	print("DEPOT_DEATH_TEST_PASSED")
	quit(0)
