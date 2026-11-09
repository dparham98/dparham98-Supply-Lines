extends SceneTree
# Headless: the Cargo vehicle's authored truck (assets/models/units/cargo_truck.glb via
# scenes/models/cargo_truck_model.tscn) faces -Z at Tank scale, and vehicle_rig.gd articulates it from
# what the vehicle does: wheels roll and steer with travel, the lid and ramp open while deployed or
# transferring at a stop, and the cargo indicator rises while anything is aboard.
const Bounds = preload("res://scripts/units/selection_bounds.gd")
var game: Node3D
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> bool:
	if ok: return true
	push_error(message); quit(1); return false
func actor(id: String, team: String, point: Vector3) -> Node3D:
	var unit = load("res://scenes/gameplay/"+id+".tscn").instantiate()
	unit.team = team
	game.get_node("Entities/Units").add_child(unit)
	unit.set_process(false)
	for cell in unit._claimed.duplicate(): unit._release(cell)
	unit.global_position = point
	return unit
func step(unit: Node3D, model: Node3D, frames: int, delta := 1.0/60) -> void:
	for i in range(frames):
		unit._process(delta)
		model._process(delta)
func run() -> void:
	game = load("res://scenes/maps/resource_skirmish.tscn").instantiate()
	root.add_child(game)
	for i in range(3): await process_frame
	game.set_process(false)
	for unit in get_nodes_in_group("units"): unit.set_process(false)
	for depot in get_nodes_in_group("depots"): depot.set_process(false)
	var depot = game.depot
	var origin: Vector3 = depot.global_position+Vector3(16,0,12)
	var truck := actor("cargo_vehicle","player",origin)
	await process_frame
	var model = truck.get_node("Visuals/Model")
	if not check(model.scene_file_path == "res://scenes/models/cargo_truck_model.tscn" and model.has_method("set_drive"),"Cargo vehicle does not use the truck model"): return
	if not check(model._wheels.size() == 6 and model._steers.size() == 2 and model.lid != null and model.ramp != null and model.indicator != null,"Truck rig nodes missing"): return
	# Facing and size: cab toward -Z, on the ground, about 4.8 m long and 2 m tall at world scale 0.6.
	var cab: Node3D = model.get_node("Rig/truck_root/chassis/cab")
	if not check(truck.to_local(cab.global_position).z < -0.5,"Cab should face -Z"): return
	var low := INF; var high := -INF; var front := INF; var back := -INF; var left := INF; var right := -INF
	for mesh in Bounds.meshes(truck):
		for i in range(8):
			var p: Vector3 = truck.global_transform.affine_inverse()*(mesh.global_transform*mesh.get_aabb().get_endpoint(i))
			low = minf(low,p.y); high = maxf(high,p.y); front = minf(front,p.z); back = maxf(back,p.z); left = minf(left,p.x); right = maxf(right,p.x)
	if not check(absf(low) < 0.05 and high < 2.2 and back-front > 4.6 and back-front < 5.0 and right-left < 2.1,"Truck size wrong: y %.2f..%.2f z %.2f..%.2f x %.2f..%.2f" % [low,high,front,back,left,right]): return
	# Standing still: nothing rolls, hatches shut, indicator down.
	step(truck,model,3)
	var indicator_rest: float = model.indicator.position.y
	if not check(not model.driving() and is_zero_approx(model.wheel_roll()) and is_zero_approx(model.lid_angle()) and is_zero_approx(model.ramp_angle()),"Parked truck should be still"): return
	# Driving east from a -Z heading: the wheels roll and the front wheels steer into the turn.
	truck.command_move(origin+Vector3(8,0,0))
	var max_steer := 0.0
	var rolled := false
	for i in range(90):
		step(truck,model,1)
		max_steer = maxf(max_steer,absf(model.steer_angle()))
		if not is_zero_approx(model.wheel_roll()): rolled = true
	if not check(truck.global_position != origin and rolled,"Wheels did not roll while driving"): return
	if not check(max_steer > deg_to_rad(5),"Front wheels did not steer into the turn: %.1f deg" % rad_to_deg(max_steer)): return
	var wheel: Node3D = model._wheels[2]
	if not check(is_equal_approx(wheel.rotation.x,model.wheel_roll()) and is_equal_approx(model._steers[0].rotation.y,model.steer_angle()),"Rig angles not applied to the nodes"): return
	# Deploying opens the lid and ramp; packing closes them.
	truck._stop_route(); truck.order = "idle"
	if not check(truck.deploy_supplies(),"Deploy refused"): return
	step(truck,model,150)
	if not check(truck.deployed and is_equal_approx(model.lid_angle(),deg_to_rad(model.lid_open_degrees)) and is_equal_approx(model.ramp_angle(),deg_to_rad(model.ramp_open_degrees)),"Deployed truck should open lid (%.0f) and ramp (%.0f)" % [rad_to_deg(model.lid_angle()),rad_to_deg(model.ramp_angle())]): return
	if not check(is_equal_approx(model.lid.rotation.x,model.lid_angle()) and is_equal_approx(model.ramp.rotation.x,model.ramp_angle()),"Hatch angles not applied"): return
	truck.pack_supplies()
	step(truck,model,150)
	if not check(not truck.deployed and is_zero_approx(model.lid_angle()) and is_zero_approx(model.ramp_angle()),"Packed truck should close its hatches"): return
	# Cargo aboard raises the indicator; unloading at the Depot opens the hatches during the transfer.
	for crate in [{kind = &"iron", amount = 25},{kind = &"iron", amount = 25}]: truck.crates.append(crate)
	truck._sync_reserved()
	step(truck,model,2)
	if not check(is_equal_approx(model.indicator.position.y,indicator_rest+model.indicator_raise),"Indicator should rise with crates aboard"): return
	for cell in truck._claimed.duplicate(): truck._release(cell)
	truck.global_position = depot.global_position+Vector3(depot.dropoff_range-0.5,0,0)
	truck.command_unload(depot)
	var opened_mid_transfer := false
	for i in range(200):
		step(truck,model,1,0.05)
		if truck.order == "unload" and truck.transfer_timer > 0.3 and model.lid_angle() > 0.1: opened_mid_transfer = true
		if truck.order == "idle" and truck.crates.is_empty(): break
	if not check(truck.crates.is_empty(),"Truck did not unload at the Depot: %s" % truck.state): return
	if not check(opened_mid_transfer,"Hatches should open during the transfer"): return
	step(truck,model,60)
	if not check(is_zero_approx(model.lid_angle()) and is_equal_approx(model.indicator.position.y,indicator_rest),"After unloading the hatches should shut and the indicator drop"): return
	print("CARGO_TRUCK_MODEL_TEST_PASSED"); quit()
