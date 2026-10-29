extends SceneTree
# Regressions for the post-merge review: Train warning, Drop queue, paused commands, labels, alerts.
var game: Node3D
var hud: CanvasLayer
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> bool:
	if value: return true
	paused = false
	push_error(message); quit(1); return false
func fixture(path: String) -> void:
	if is_instance_valid(game): game.free()
	game = load(path).instantiate()
	root.add_child(game); await process_frame
	game.set_process(false)
	hud = game.get_node("Interface"); hud.set_process(false)
	for group in ["units","depots"]:
		for node in get_nodes_in_group(group): node.set_process(false)
func select_only(unit: Node3D) -> void:
	game.selected_building = null
	for node in get_nodes_in_group("units"): node.set_selected(node == unit)
	hud._process(0)
func run() -> void:
	root.size = Vector2i(1280,900)
	# 1. A HUD route assignment keeps the Train round-trip fuel warning in the header.
	await fixture("res://scenes/maps/rail_exercise.tscn")
	game.vehicle_fuel_required = true
	var train = game.get_node("Entities/Units/Train")
	train.fuel = 0
	select_only(train)
	var destination = game.get_node("Entities/Buildings/EastDepot")
	hud.supply.get_node("Source").select(hud.route_depots.find(game.depot))
	hud.supply.get_node("Destination").select(hud.route_depots.find(destination))
	hud.supply.get_node("Amounts/Energy").value = 1
	hud.assign_route()
	if not check(train.route_active and not train.fuel_warning.is_empty() and "Train fuel warning" in game.message,"HUD route assignment hid the Train fuel warning: %s" % game.message): return
	await fixture("res://scenes/maps/resource_skirmish.tscn")
	var worker = game.get_node("Entities/Units/Infantry")
	# 2. Drop materials ends the queue as well as the current order.
	select_only(worker)
	worker.cargo = 5; worker.cargo_kind = &"iron"
	worker.queue_order({kind = "move", point = worker.global_position+Vector3(6,0,0)})
	worker.queue_order({kind = "move", point = worker.global_position+Vector3(9,0,0)})
	hud.card.get_node("DropMaterials").pressed.emit()
	for i in 10: worker._process(1.0/60)
	if not check(worker.order == "idle" and worker.order_queue.is_empty(),"Drop materials left queued orders running"): return
	# 3. While paused, armed commands are cancelled by pausing, by Esc and by a click.
	var manager = root.get_node("SelectionManager")
	var panel = hud.get_node("PlaytestPanel")
	game.pending_unit_command = "move"
	panel.toggle_pause()
	if not check(paused and not game.armed(),"Pausing kept an armed command"): return
	game.placing_depot = true
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE; esc.physical_keycode = KEY_ESCAPE; esc.pressed = true
	manager._unhandled_input(esc)
	if not check(not game.armed(),"Esc while paused kept an armed placement"): return
	game.pending_unit_command = "attack"
	manager.start_selection(Vector2(640,300))
	if not check(not game.armed() and manager.selecting,"Paused click did not cancel the command and select"): return
	manager.selecting = false
	panel.toggle_pause()
	game.pending_unit_command = "move"
	manager.start_selection(Vector2(640,300))
	if not check(game.armed() and not manager.selecting,"Unpaused armed command was cancelled by a click"): return
	game.cancel_armed()
	# 6. Button labels carry their key and stay unchanged between frames.
	select_only(worker)
	var stop: Button = hud.card.get_node("Stop")
	var first := stop.text
	hud._process(0); hud._process(0)
	if not check(first == "Stop [S]" and stop.text == first,"Stop label unstable: %s / %s" % [first,stop.text]): return
	if not check(hud.supply.get_node("MoveCargo").text.ends_with("[M]") and hud.supply.get_node("CancelRoute").text.ends_with("[X]"),"Fixed Supply panel labels lack keys"): return
	# 7. One Auto-refuel button: the Supply panel no longer has its own copy.
	if not check(not hud.supply.has_node("SupplyRefuel"),"Duplicate Supply panel Auto-refuel still present"): return
	# 8. Alert throttle times are pruned once they expire.
	var now := Time.get_ticks_msec()/1000.0
	game._alert_times["stale"] = now-game.ALERT_REPEAT_SECONDS-1
	game.alert("Fresh",Vector3.ZERO,"fresh")
	if not check(not game._alert_times.has("stale") and game._alert_times.has("fresh"),"Expired alert times not pruned"): return
	print("REVIEW_FIXES_TEST_PASSED")
	quit(0)
