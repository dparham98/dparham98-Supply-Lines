extends SceneTree
# Headless: the Generator's model (assets/models/buildings/generator.glb via scenes/models/generator_model.tscn)
# fits its 3 x 3 footprint with the fire door toward +Z, its clips start at frame 0, a construction plan shows
# it going up with the work, it runs (flywheel turning, fire lit) only while it burns fuel and stands cold
# otherwise, and a destroyed Generator leaves a wreck that plays Die, sinks and removes itself.
const Burst = preload("res://scripts/components/burst_effect.gd")
const ROOT := "Rig/generator_root/"
const MODEL := "res://scenes/models/generator_model.tscn"
var game: Node3D
var network: Node
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> bool:
	if ok: return true
	push_error(message); quit(1); return false
func site(kind: StringName, near: Vector3) -> Vector3:
	var spec: Dictionary = network.plan_spec(kind)
	for radius in range(8,100,4):
		for offset in [Vector3(radius,0,0),Vector3(-radius,0,0),Vector3(0,0,radius),Vector3(0,0,-radius)]:
			var point: Vector3 = near+offset
			var start: Vector2i = network.footprint_start(point,spec.size)
			if network.plan_terrain_valid(start,spec.size,kind) and not network.plan_overlaps(start,spec.size) and network.can_place_size(point,game.depot,spec.size): return point
	return Vector3.INF
## Model-space bounds of every visible mesh under `node`, leaving out effects and parts shrunk away.
func extent(node: Node3D, space: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for mesh in node.find_children("*","MeshInstance3D",true,false):
		if _in_effect(mesh,node): continue
		if not (mesh as MeshInstance3D).is_visible_in_tree(): continue
		if mesh.global_transform.basis.get_scale().x < 0.01: continue
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
	return model.get_node(ROOT+name)
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
	# The clips: Idle and Run loop, Build and Die play once, and every track starts on frame 0.
	var probe: Node3D = load(MODEL).instantiate()
	root.add_child(probe)
	var player: AnimationPlayer = probe.player
	for clip in ["Idle","Run","Build","Die"]:
		if not check(player.has_animation(clip),"Generator clip %s missing: %s" % [clip,player.get_animation_list()]): return
		var animation := player.get_animation(clip)
		if not check((animation.loop_mode == Animation.LOOP_LINEAR) == (clip in ["Idle","Run"]),"%s loop mode wrong" % clip): return
		for track in range(animation.get_track_count()):
			if not check(animation.track_get_key_count(track) > 0 and is_zero_approx(animation.track_get_key_time(track,0)),"%s track %s does not start at frame 0" % [clip,animation.track_get_path(track)]): return
	probe.free()
	# A construction plan: nothing stands at the start, the furnace by half the work, all of it at the end.
	var point := site(&"generator",depot.global_position)
	if not check(point != Vector3.INF,"No Generator site"): return
	var plan = network.queue_plan(point,&"generator")
	if not check(plan != null,"Generator plan not placed"): return
	plan.set_process(false)
	var site_model: Node3D = plan.get_node_or_null("Visuals/Model")
	if not check(site_model != null and site_model.scene_file_path == MODEL,"The Generator plan should show its model"): return
	var grid: Node3D = plan.get_node("Visuals/Grid")
	if not check(Vector2(site_model.position.x,site_model.position.z).is_equal_approx(Vector2(grid.position.x,grid.position.z)),"Site model should stand on the footprint grid"): return
	if not check(part(site_model,"plinth").scale.y < 0.01 and part(site_model,"firebox").scale.y < 0.01,"Nothing should stand on a site before work starts"): return
	var iron: int = plan.spec.iron
	var energy: int = plan.spec.energy
	plan.added = {&"iron": iron/2}; plan.energy_paid = energy/2
	plan.refresh_label()
	var half: float = plan.progress_fraction()
	if not check(site_model.player.assigned_animation == &"Build" and absf(site_model.player.current_animation_position/site_model.player.get_animation(&"Build").length-half) < 0.01,"Build should follow construction progress: %.2f" % half): return
	if not check(part(site_model,"firebox").scale.y > 0.99 and part(site_model,"mast").scale.y < 0.01 and part(site_model,"flywheel").scale.y < 0.01,"Half built: furnace up, flywheel and mast not yet (progress %.2f)" % half): return
	plan.added = {&"iron": iron}; plan.energy_paid = energy
	plan.refresh_label()
	for name in ["boiler","chimney","flywheel","mast","dynamo"]:
		if not check(part(site_model,name).scale.is_equal_approx(Vector3.ONE),"Fully built site should show the %s" % name): return
	plan.added = {}; plan.energy_paid = 0
	var building: Node3D = plan.complete_from_stock()
	if not check(building != null,"Generator plan did not complete"): return
	building.set_process(false)
	await process_frame
	var model: Node3D = building.get_node("Visuals/Model")
	if not check(model.scene_file_path == MODEL and model.has_method("show_running"),"Generator does not use the rigged model"): return
	# Inside its footprint, on the ground, fire door toward +Z; the chimney is the tallest part.
	var box := extent(model,building)
	if not check(absf(box.position.y) < 0.05 and box.end.y > 3.9 and box.end.y < 4.4,"Generator height wrong: y %.2f..%.2f" % [box.position.y,box.end.y]): return
	if not check(box.position.x > -1.51 and box.end.x < 1.51 and box.position.z > -1.51 and box.end.z < 1.51,"Generator outside its 3 x 3 footprint: %s" % box): return
	if not check(box.size.x > 2.7 and box.size.z > 2.7,"Generator should fill its footprint: %s" % box): return
	var fire := part(model,"firebox/fire_glow")
	if not check(building.to_local(fire.global_position).z > 0.7,"The fire door should face +Z"): return
	# Cold until it burns fuel: no fire, flywheel still.
	if not building.assigned_depot: building.assign_source(depot)
	depot.wood = 0; depot.coal = 0
	building.reset_cycle()
	building._process(0.1)
	if not check(not building.active() and not model.running() and model.player.assigned_animation == &"Idle","A Generator without fuel should stand cold"): return
	model.player.advance(0.5)
	if not check(fire.scale.x < 0.01 and part(model,"dynamo/coil_glow").scale.x < 0.01 and part(model,"firebox/pilot").scale.x > 0.5,"Cold: fire out, coils dark, pilot lit"): return
	var still := part(model,"flywheel").transform
	model.player.advance(0.5)
	if not check(part(model,"flywheel").transform.is_equal_approx(still),"Cold: the flywheel should not turn"): return
	# Fuel arrives: it runs, the flywheel turns and drives the piston, the fire is lit.
	depot.wood = 10
	building._process(0.1)
	if not check(building.active() and model.running() and model.player.assigned_animation == &"Run","A Generator burning fuel should run"): return
	model.player.advance(1.0)
	var wheel_a := part(model,"flywheel").transform.basis
	var cross_a := part(model,"crosshead").position
	model.player.advance(0.25)
	if not check(not part(model,"flywheel").transform.basis.is_equal_approx(wheel_a),"Running: the flywheel should turn"): return
	if not check(part(model,"crosshead").position.distance_to(cross_a) > 0.05,"Running: the piston should pump"): return
	if not check(fire.scale.x > 0.9 and part(model,"dynamo/coil_glow").scale.x > 0.9,"Running: fire lit and coils glowing"): return
	# Out of fuel mid-cycle: back to Idle.
	depot.wood = 0
	building._process(0.1)
	if not check(not model.running() and model.player.assigned_animation == &"Idle","A Generator out of fuel should go cold"): return
	# Destroyed: the building goes at once, its model stays behind as a wreck and removes itself.
	var parent := building.get_parent()
	building.take_damage(building.max_health)
	if not check(not building.is_in_group("selectable_buildings") and not building.is_in_group("energy_generators"),"Destroyed Generator still selectable"): return
	if not check(model.get_parent() == parent and model.dying() and model.player.assigned_animation == &"Die","A destroyed Generator should leave its model playing Die"): return
	var effects := model.get_children().filter(func(n): return n.get_script() == Burst)
	if not check(effects.size() == 1 and effects[0].player.has_animation(&"Death"),"The wreck should carry its death effects"): return
	model.show_running(true)
	if not check(model.player.assigned_animation == &"Die","A wreck should ignore the running switch"): return
	await process_frame
	if not check(not is_instance_valid(building),"The Generator itself should be gone"): return
	var die_length: float = model.player.get_animation(&"Die").length
	model.player.advance(die_length-0.08)
	var low := extent(model,model)
	if not check(low.end.y < 0.1,"The wreck should have sunk out of sight by the end: top %.2f" % low.end.y): return
	model.player.advance(0.2)
	await process_frame
	if not check(not is_instance_valid(model),"The wreck should remove itself"): return
	print("GENERATOR_MODEL_TEST_PASSED")
	quit(0)
