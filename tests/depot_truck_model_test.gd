extends SceneTree
# Depot Truck, crate and fold-out deploy (docs/DEPOT_MODEL.md): the truck uses the authored hauler, the
# crate uses the authored crate, and a deployed Depot takes the truck's 90 degree heading and unfolds.
var game: Node3D
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> bool:
	if value: return true
	push_error(message); quit(1); return false
func tractor_direction(depot: Node3D) -> Vector3:
	var unit: Node3D = depot.get_node("Visuals/Model/Warehouse/warehouse_root/warehouse_power_unit")
	var flat: Vector3 = unit.global_position-depot.global_position
	flat.y = 0
	return flat.normalized()
func run() -> void:
	game = load("res://scenes/maps/resource_skirmish.tscn").instantiate()
	root.add_child(game)
	for frame in range(3): await process_frame
	game.set_process(false)
	var network = game.get_node("DepotNetwork")
	var truck: Node3D = network.truck_scene.instantiate()
	var start: Vector2i = game.ground.find_buildable_footprint(Vector2i(220,170),Vector2i(10,10))
	var site: Vector3 = game.ground.tile_to_world(start+Vector2i(5,5))
	truck.position = site
	game.get_node("Entities/Units").add_child(truck)
	truck.set_process(false)
	var model: Node3D = truck.get_node("Visuals/Model")
	if not check(model.scene_file_path == "res://scenes/models/depot_truck_model.tscn","Truck still uses the prototype"): return
	if not check(truck.get_node("Visuals").scale == Vector3.ONE,"Truck model should not be stretched"): return
	if not check(model._wheels.size() == 8 and model._steers.size() == 2,"Truck wheels missing: %d" % model._wheels.size()): return
	if not check(model.find_child("warehouse_crate_01",true,false) == null and model.find_child("warehouse_col_L1",true,false) == null,"Closed truck should not include hidden Depot parts"): return
	var far := -INF
	var near := INF
	for mesh in model.find_children("*","MeshInstance3D",true,false):
		for i in range(8):
			var z: float = truck.to_local(mesh.global_transform*mesh.get_aabb().get_endpoint(i)).z
			far = maxf(far,z); near = minf(near,z)
	if not check(absf(far+near) < 0.1 and far-near > 15.0 and far-near < 15.6,"Truck is not centred or is the wrong length: %.2f..%.2f" % [near,far]): return
	var crate: Node3D = load("res://scenes/gameplay/supply_crate.tscn").instantiate()
	root.add_child(crate)
	var crate_model: Node3D = crate.get_node("Visuals/Model")
	if not check(crate_model.scene_file_path == "res://scenes/models/supply_crate_model.tscn","Crate still uses the placeholder"): return
	var box: AABB = crate_model.find_children("*","MeshInstance3D",true,false)[0].get_aabb()
	if not check(box.size.x*0.4 < 1.0 and box.size.z*0.4 < 1.0,"A crate must fit its one tile"): return
	crate.material_kind = "iron"; crate.amount = 5; crate.refresh()
	if not check(crate.get_node("Visuals/Bands/Iron").visible,"Resource band not shown"): return
	crate.free()
	# Truck 20 degrees off due north: deploys facing north, and its model starts from the truck.
	truck.get_node("Visuals").rotation.y = deg_to_rad(20)
	truck.set_selected(true)
	if not check(network.deploy_selected_truck(),"Deploy failed"): return
	var depot: Node3D = network.selected
	var fold: Node3D = depot.get_node("Visuals/Model")
	var player: AnimationPlayer = fold.player
	if not check(fold.deploying() and player.assigned_animation == &"deploy" and not player.is_playing(),"Fold-out should wait for the line-up"): return
	if not check(absf(rad_to_deg(fold.rotation.y)-20.0) < 0.5 and fold.position.length() > 1.0,"Fold-out should start from the truck: %s %s" % [fold.position,fold.rotation]): return
	var crate_part: Node3D = fold.find_child("warehouse_crate_01",true,false)
	if not check(crate_part.scale.x < 0.01,"Fold-out should start closed"): return
	await create_timer(fold.line_up_seconds+0.2).timeout
	if not check(fold.position.length() < 0.01 and absf(fold.rotation.y) < 0.01 and player.is_playing(),"Line-up did not finish"): return
	var direction := tractor_direction(depot)
	if not check(direction.distance_to(Vector3(0,0,-1)) < 0.02,"Tractor should face the truck heading: %s" % direction): return
	player.seek(player.current_animation_length-0.001,true)
	await create_timer(0.1).timeout
	if not check(not fold.deploying() and crate_part.scale.x > 0.99,"Fold-out should end on the finished Depot"): return
	print("DEPOT_TRUCK_MODEL_TEST_PASSED"); quit()
