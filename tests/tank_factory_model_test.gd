extends SceneTree
# Headless: the Tank Factory's model (assets/models/buildings/tank_factory.glb via
# scenes/models/tank_factory_model.tscn) fits its 8 x 8 footprint with the vehicle door toward +Z, its clips
# start at frame 0, a construction plan shows the plant going up with the work, production plays Produce
# with the queued unit's own model formed on the raised lift (the crane lowering plates onto it) and driven out as
# the door opens, a mixed queue swaps the model between units, and a destroyed Tank Factory leaves a wreck that
# plays Die, sinks and removes itself.
const Bounds = preload("res://scripts/units/selection_bounds.gd")
const Burst = preload("res://scripts/components/burst_effect.gd")
const HALL := "Rig/tank_factory_root/"
const MODEL := "res://scenes/models/tank_factory_model.tscn"
var game: Node3D
var network: Node
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> bool:
	if ok: return true
	push_error(message); quit(1); return false
func site(kind: StringName, near: Vector3) -> Vector3:
	var spec: Dictionary = network.plan_spec(kind)
	for radius in range(10,100,4):
		for offset in [Vector3(radius,0,0),Vector3(-radius,0,0),Vector3(0,0,radius),Vector3(0,0,-radius)]:
			var point: Vector3 = near+offset
			var start: Vector2i = network.footprint_start(point,spec.size)
			if network.plan_terrain_valid(start,spec.size,kind) and not network.plan_overlaps(start,spec.size) and network.can_place_size(point,game.depot,spec.size): return point
	return Vector3.INF
## Model-space bounds of every mesh under `node`, leaving out effects.
func extent(node: Node3D, space: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for mesh in node.find_children("*","MeshInstance3D",true,false):
		if _in_effect(mesh,node): continue
		if not (mesh as MeshInstance3D).is_visible_in_tree(): continue
		for i in range(8):
			var p: Vector3 = space.global_transform.affine_inverse()*(mesh.global_transform*mesh.get_aabb().get_endpoint(i))
			if first: box = AABB(p,Vector3.ZERO); first = false
			else: box = box.expand(p)
	return box
func _in_effect(mesh: Node, top: Node) -> bool:
	var node := mesh.get_parent()
	while node != null and node != top:
		if node.get_script() == Burst: return true
		node = node.get_parent()
	return false
func part(model: Node3D, name: String) -> Node3D:
	return model.get_node(HALL+name)
func run() -> void:
	game = load("res://scenes/maps/resource_skirmish.tscn").instantiate()
	root.add_child(game)
	for i in range(3): await process_frame
	network = game.get_node("DepotNetwork")
	game.set_process(false)
	for unit in get_nodes_in_group("units"): unit.set_process(false)
	for depot in get_nodes_in_group("depots"): depot.set_process(false)
	var depot = game.depot
	depot.storage_capacity = 10000
	depot.energy = 2000; depot.iron = 2000
	# The clips: Idle loops, the others play once, and every track starts on frame 0.
	var probe: Node3D = load(MODEL).instantiate()
	root.add_child(probe)
	var player: AnimationPlayer = probe.player
	for clip in ["Idle","Build","Produce","Die"]:
		if not check(player.has_animation(clip),"Tank Factory clip %s missing: %s" % [clip,player.get_animation_list()]): return
		var animation := player.get_animation(clip)
		if not check((animation.loop_mode == Animation.LOOP_LINEAR) == (clip == "Idle"),"%s loop mode wrong" % clip): return
		for track in range(animation.get_track_count()):
			if not check(animation.track_get_key_count(track) > 0 and is_zero_approx(animation.track_get_key_time(track,0)),"%s track %s does not start at frame 0" % [clip,animation.track_get_path(track)]): return
	probe.free()
	# A construction plan: nothing stands at the start, half the hall at half the work, all of it at the end.
	var point := site(&"tank_factory",depot.global_position)
	if not check(point != Vector3.INF,"No Tank Factory site"): return
	var plan = network.queue_plan(point,&"tank_factory")
	if not check(plan != null,"Tank Factory plan not placed"): return
	plan.set_process(false)
	var site_model: Node3D = plan.get_node_or_null("Visuals/Model")
	if not check(site_model != null and site_model.scene_file_path == MODEL,"The Tank Factory plan should show its model"): return
	var grid: Node3D = plan.get_node("Visuals/Grid")
	if not check(Vector2(site_model.position.x,site_model.position.z).is_equal_approx(Vector2(grid.position.x,grid.position.z)),"Site model should stand on the footprint grid"): return
	if not check(part(site_model,"plinth").scale.y < 0.01 and part(site_model,"roof").scale.y < 0.01,"Nothing should stand on a site before work starts"): return
	var iron: int = plan.spec.iron
	var energy: int = plan.spec.energy
	plan.added = {&"iron": iron/2}; plan.energy_paid = energy/2
	plan.refresh_label()
	var half: float = plan.progress_fraction()
	if not check(site_model.player.assigned_animation == &"Build" and absf(site_model.player.current_animation_position/site_model.player.get_animation(&"Build").length-half) < 0.01,"Build should follow construction progress: %.2f" % half): return
	if not check(part(site_model,"walls").scale.y > 0.01 and part(site_model,"roof").scale.y < 0.01 and part(site_model,"gantry").scale.y < 0.01,"Half built: walls going up, roof and crane not on yet"): return
	plan.added = {&"iron": iron}; plan.energy_paid = energy
	plan.refresh_label()
	if not check(part(site_model,"roof").scale.is_equal_approx(Vector3.ONE) and part(site_model,"stacks").scale.is_equal_approx(Vector3.ONE) and part(site_model,"gantry").scale.is_equal_approx(Vector3.ONE),"Fully built site should show the whole plant"): return
	if not check(site_model.get_parent() == plan.get_node("Visuals"),"Site model belongs to the plan"): return
	plan.added = {}; plan.energy_paid = 0
	var building: Node3D = plan.complete_from_stock()
	if not check(building != null,"Tank Factory plan did not complete"): return
	building.set_process(false)
	await process_frame
	if not check(not is_instance_valid(plan) or plan.is_queued_for_deletion(),"Plan should go when the Tank Factory stands"): return
	var model: Node3D = building.get_node("Visuals/Model")
	if not check(model.scene_file_path == MODEL and model.has_method("show_print") and model.print_clip == &"Produce","Tank Factory does not use the rigged model"): return
	# Inside its footprint, on the ground, door toward +Z; the crane on the roof is the tallest part.
	var box := extent(model,building)
	if not check(absf(box.position.y) < 0.05 and box.end.y > 5.5 and box.end.y < 6.3,"Tank Factory height wrong: y %.2f..%.2f" % [box.position.y,box.end.y]): return
	if not check(box.position.x > -4.01 and box.end.x < 4.01 and box.position.z > -4.01 and box.end.z < 4.01,"Tank Factory outside its 8 x 8 footprint: %s" % box): return
	if not check(box.size.x > 7.4 and box.size.z > 7.4,"Tank Factory should fill its footprint: %s" % box): return
	var door := part(model,"bay_door")
	if not check(building.to_local(door.global_position).z > 2.9,"The vehicle door should face +Z"): return
	var vehicle := part(model,"vehicle")
	var plates: Array[Node3D] = [part(model,"vehicle/veh_plate_1"),part(model,"vehicle/veh_plate_2"),part(model,"vehicle/veh_plate_3")]
	if not check(plates.all(func(p): return p.scale.x < 0.01) and model.unit_model == null and door.scale.is_equal_approx(Vector3.ONE),"Rest pose: no unit, no plates and door closed"): return
	var last_seat := plates[2].position
	if not check(model.player.is_playing() and model.player.assigned_animation == &"Idle","A Tank Factory with nothing queued should idle"): return
	# The factory reads each unit's model from its scene.
	for id in ["tank","motorcycle","drone"]:
		var unit_scene: PackedScene = load("res://scenes/gameplay/%s.tscn" % id)
		if not check(building.unit_model_scene(unit_scene).resource_path == "res://scenes/models/%s_model.tscn" % id,"The %s's model should be read from its scene" % id): return
	# Production: Produce follows the queue, the Tank's own model forms on the lift, then drives out of the door.
	if not check(building.request_unit(&"tank"),"Tank not queued"): return
	var print_seconds: float = building.stats.print_seconds
	var units_before := get_nodes_in_group("units").size()
	building._process(print_seconds*0.5)
	if not check(model.player.assigned_animation == &"Produce" and not model.player.is_playing(),"Produce should be posed by production progress"): return
	if not check(part(model,"turntable").position.y > 2.0,"The lift should hold the unit up near the roof while it is made"): return
	if not check(model.unit_model != null and model.unit_model.scene_file_path == "res://scenes/models/tank_model.tscn" and model.unit_model.get_parent() == vehicle,"The Tank's own model should stand on the turntable"): return
	if not check(model.unit_model.process_mode == Node.PROCESS_MODE_DISABLED,"The unit model in the factory is scenery only"): return
	var cut: float = model._unit_material.get_shader_parameter(&"cut_height")
	if not check(model.unit_forming() and cut > model.unit_model.global_position.y+0.05 and cut < model.unit_model.global_position.y+model._unit_height*vehicle.global_basis.get_scale().y-0.05,"Half made: the Tank should be part formed below the weld seam"): return
	if not check(plates[2].scale.x > 0.5 and plates[2].position.distance_to(last_seat) > 0.3 and door.scale.y > 0.99,"Half made: the last plate still on the crane, door closed"): return
	building._process(print_seconds*0.49)
	if not check(not model.unit_forming() and door.scale.y < 0.2 and building.to_local(vehicle.global_position).z > 2.5,"Nearly made: the finished Tank should be at the open door (z %.2f door %.2f)" % [building.to_local(vehicle.global_position).z,door.scale.y]): return
	if not check(plates.all(func(p): return p.scale.x < 0.01),"The plates should have merged into the unit"): return
	building._process(print_seconds*0.02)
	if not check(get_nodes_in_group("units").size() == units_before+1,"The unit was not produced"): return
	await process_frame
	if not check(model.closing() and model.player.is_playing() and model.unit_model == null,"The model should go with the unit and the door close"): return
	model.player.advance(model.player.get_animation(&"Produce").length)
	await process_frame
	if not check(not model.closing() and model.player.assigned_animation == &"Idle" and door.scale.y > 0.99,"After the unit leaves the door closes and the plant idles"): return
	# A mixed queue: each unit's own model, in turn.
	depot.energy = 5000; depot.iron = 5000
	if not check(building.request_unit(&"motorcycle") and building.request_unit(&"drone"),"Motorcycle and Drone not queued"): return
	building._process(print_seconds*0.3)
	if not check(model.unit_model != null and model.unit_model.scene_file_path == "res://scenes/models/motorcycle_model.tscn","A Motorcycle should be made on the turntable, not a Tank"): return
	building._process(print_seconds*0.71)
	await process_frame
	if not check(model.closing() and model.unit_model == null,"The Motorcycle should have left"): return
	building._process(print_seconds*0.1)
	if not check(model.unit_model == null,"The next unit waits for the door to close"): return
	model.player.advance(model.player.get_animation(&"Produce").length)
	await process_frame
	building._process(print_seconds*0.05)
	if not check(model.unit_model != null and model.unit_model.scene_file_path == "res://scenes/models/drone_model.tscn","Then a Drone should be made"): return
	if not check(model.unit_model.get_parent() == vehicle and not model.unit_model.top_level,"The Drone is formed on the turntable"): return
	# A flyer leaves through the roof: once formed it lifts off and rises to where the real Drone will hover.
	# Progress carried on while the door closed behind the Motorcycle (0.1 + 0.05 so far).
	building._process(print_seconds*0.7)
	var drone_model: Node3D = model.unit_model
	if not check(drone_model != null and drone_model.top_level and drone_model.process_mode == Node.PROCESS_MODE_INHERIT,"The finished Drone should lift off the turntable under its own power"): return
	if not check(drone_model.global_position.y > building.global_position.y+4.5 and absf(building.to_local(drone_model.global_position).z) < 2.0,"The Drone should be rising out of the roof well (%s)" % building.to_local(drone_model.global_position)): return
	if not check(door.scale.y > 0.99,"The door stays shut for a flyer"): return
	building._process(print_seconds*0.14)
	var hover: Vector3 = model._flight_to.origin
	if not check(drone_model.global_position.distance_to(hover) < 0.3 and hover.y > building.global_position.y+10.0,"Nearly made: the Drone should be up at its flying height (%.2f m off)" % drone_model.global_position.distance_to(hover)): return
	if not check(absf(drone_model.global_basis.get_scale().x-1.0) < 0.05 and door.scale.y > 0.99,"At full size, with the door still shut"): return
	var drones_before := get_nodes_in_group("units").filter(func(u): return u.scene_file_path == "res://scenes/gameplay/drone.tscn").size()
	building._process(print_seconds*0.02)
	var drones := get_nodes_in_group("units").filter(func(u): return u.scene_file_path == "res://scenes/gameplay/drone.tscn")
	if not check(drones.size() == drones_before+1,"The Drone was not produced"): return
	var real: Node3D = drones.back().get_node("Visuals/Model")
	if not check(real.global_position.distance_to(hover) < 0.05,"The real Drone should appear where the factory flew its model (%.2f m off)" % real.global_position.distance_to(hover)): return
	await process_frame
	if not check(model.unit_model == null and not model.closing() and model.player.assigned_animation == &"Idle" and door.scale.y > 0.99,"After a flyer leaves the plant idles with the door shut"): return
	# Clearing the queue part way empties the turntable.
	if not check(building.request_unit(&"motorcycle"),"Motorcycle not queued"): return
	building._process(print_seconds*0.3)
	if not check(model.unit_model != null,"The Motorcycle should be on the turntable"): return
	building.pending.clear()
	building._process(0.1)
	await process_frame
	if not check(model.unit_model == null,"With the queue gone the turntable should be empty"): return
	# Destroyed: the building goes at once, its model stays behind as a wreck and removes itself.
	building.take_damage(building.max_health)
	if not check(not building.is_in_group("selectable_buildings") and not building.is_in_group("production_buildings"),"Destroyed Tank Factory still selectable"): return
	if not check(model.get_parent() == game and model.dying() and model.player.assigned_animation == &"Die","A destroyed Tank Factory should leave its model playing Die"): return
	var effects := model.get_children().filter(func(n): return n.get_script() == Burst)
	if not check(effects.size() == 1 and effects[0].player.has_animation(&"Death"),"The wreck should carry its death effects"): return
	await process_frame
	if not check(not is_instance_valid(building),"The Tank Factory itself should be gone"): return
	var die_length: float = model.player.get_animation(&"Die").length
	model.player.advance(die_length-0.08)
	var low := extent(model,model)
	if not check(low.end.y < 0.1,"The wreck should have sunk out of sight by the end: top %.2f" % low.end.y): return
	model.player.advance(0.2)
	await process_frame
	if not check(not is_instance_valid(model),"The wreck should remove itself"): return
	print("TANK_FACTORY_MODEL_TEST_PASSED")
	quit(0)
