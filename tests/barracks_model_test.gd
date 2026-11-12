extends SceneTree
# Headless: the Barracks' model (assets/models/buildings/barracks.glb via scenes/models/barracks_model.tscn)
# fits its 6 x 6 footprint with the bay door toward +Z, its clips start at frame 0, a construction plan
# shows the hall going up with the work, production plays Print with the door opening as the unit leaves,
# and a destroyed Barracks leaves a wreck that plays Die, sinks and removes itself.
const Bounds = preload("res://scripts/units/selection_bounds.gd")
const Burst = preload("res://scripts/components/burst_effect.gd")
const HALL := "Rig/barracks_root/"
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
	var probe: Node3D = load("res://scenes/models/barracks_model.tscn").instantiate()
	root.add_child(probe)
	var player: AnimationPlayer = probe.player
	for clip in ["Idle","Build","Print","Die"]:
		if not check(player.has_animation(clip),"Barracks clip %s missing: %s" % [clip,player.get_animation_list()]): return
		var animation := player.get_animation(clip)
		if not check((animation.loop_mode == Animation.LOOP_LINEAR) == (clip == "Idle"),"%s loop mode wrong" % clip): return
		for track in range(animation.get_track_count()):
			if not check(animation.track_get_key_count(track) > 0 and is_zero_approx(animation.track_get_key_time(track,0)),"%s track %s does not start at frame 0" % [clip,animation.track_get_path(track)]): return
	probe.free()
	# A construction plan: nothing stands at the start, half the hall at half the work, all of it at the end.
	var point := site(&"barracks",depot.global_position)
	if not check(point != Vector3.INF,"No Barracks site"): return
	var plan = network.queue_plan(point,&"barracks")
	if not check(plan != null,"Barracks plan not placed"): return
	plan.set_process(false)
	var site_model: Node3D = plan.get_node_or_null("Visuals/Model")
	if not check(site_model != null and site_model.scene_file_path == "res://scenes/models/barracks_model.tscn","The Barracks plan should show the Barracks model"): return
	var grid: Node3D = plan.get_node("Visuals/Grid")
	if not check(Vector2(site_model.position.x,site_model.position.z).is_equal_approx(Vector2(grid.position.x,grid.position.z)),"Site model should stand on the footprint grid"): return
	if not check(part(site_model,"plinth").scale.y < 0.01 and part(site_model,"roof").scale.y < 0.01,"Nothing should stand on a site before work starts"): return
	var iron: int = plan.spec.iron
	var energy: int = plan.spec.energy
	plan.added = {&"iron": iron/2}; plan.energy_paid = energy/2
	plan.refresh_label()
	var half: float = plan.progress_fraction()
	if not check(site_model.player.assigned_animation == &"Build" and absf(site_model.player.current_animation_position/site_model.player.get_animation(&"Build").length-half) < 0.01,"Build should follow construction progress: %.2f" % half): return
	if not check(part(site_model,"walls").scale.y > 0.01 and part(site_model,"roof").scale.y < 0.01,"Half built: walls going up, roof not on yet"): return
	plan.added = {&"iron": iron}; plan.energy_paid = energy
	plan.refresh_label()
	if not check(part(site_model,"roof").scale.is_equal_approx(Vector3.ONE) and part(site_model,"mast").scale.is_equal_approx(Vector3.ONE),"Fully built site should show the whole hall"): return
	if not check(site_model.get_parent() == plan.get_node("Visuals"),"Site model belongs to the plan"): return
	plan.added = {}; plan.energy_paid = 0
	var building: Node3D = plan.complete_from_stock()
	if not check(building != null,"Barracks plan did not complete"): return
	building.set_process(false)
	await process_frame
	if not check(not is_instance_valid(plan) or plan.is_queued_for_deletion(),"Plan should go when the Barracks stands"): return
	var model: Node3D = building.get_node("Visuals/Model")
	if not check(model.scene_file_path == "res://scenes/models/barracks_model.tscn" and model.has_method("show_print"),"Barracks does not use the rigged model"): return
	# Inside its footprint, on the ground, door toward +Z, below the Depot's height but for the mast.
	var box := extent(model,building)
	if not check(absf(box.position.y) < 0.05 and box.end.y > 5.5 and box.end.y < 7.0,"Barracks height wrong: y %.2f..%.2f" % [box.position.y,box.end.y]): return
	if not check(box.position.x > -3.01 and box.end.x < 3.01 and box.position.z > -3.01 and box.end.z < 3.01,"Barracks outside its 6 x 6 footprint: %s" % box): return
	if not check(box.size.x > 5.5 and box.size.z > 5.5,"Barracks should fill its footprint: %s" % box): return
	var door := part(model,"bay_door")
	if not check(building.to_local(door.global_position).z > 2.3,"The bay door should face +Z"): return
	var figure := part(model,"cradle/print_figure")
	if not check(figure.scale.x < 0.01 and door.scale.is_equal_approx(Vector3.ONE),"Rest pose: cradle empty and door closed"): return
	if not check(model.player.is_playing() and model.player.assigned_animation == &"Idle","A Barracks with nothing queued should idle"): return
	# Production: Print follows the queue, the figure forms, then the door opens as the unit leaves.
	if not check(building.request_unit(&"infantry"),"Infantry not queued"): return
	var print_seconds: float = building.stats.print_seconds
	var units_before := get_nodes_in_group("units").size()
	building._process(print_seconds*0.5)
	if not check(model.player.assigned_animation == &"Print" and not model.player.is_playing(),"Print should be posed by production progress"): return
	if not check(figure.scale.y > 0.2 and figure.scale.y < 0.95 and door.scale.y > 0.99,"Half printed: figure forming behind a closed door (figure %.2f door %.2f)" % [figure.scale.y,door.scale.y]): return
	building._process(print_seconds*0.49)
	if not check(door.scale.y < 0.2 and figure.scale.x > 0.5,"Nearly printed: the figure should wait at the open door"): return
	building._process(print_seconds*0.02)
	if not check(get_nodes_in_group("units").size() == units_before+1,"The unit was not produced"): return
	if not check(model.closing() and model.player.is_playing() and figure.scale.x < 0.01,"The figure should be gone and the door closing"): return
	model.player.advance(model.player.get_animation(&"Print").length)
	await process_frame
	if not check(not model.closing() and model.player.assigned_animation == &"Idle" and door.scale.y > 0.99,"After the unit leaves the door closes and the hall idles"): return
	# Destroyed: the building goes at once, its model stays behind as a wreck and removes itself.
	building.take_damage(building.max_health)
	if not check(not building.is_in_group("selectable_buildings") and not building.is_in_group("production_buildings"),"Destroyed Barracks still selectable"): return
	if not check(model.get_parent() == game and model.dying() and model.player.assigned_animation == &"Die","A destroyed Barracks should leave its model playing Die"): return
	var effects := model.get_children().filter(func(n): return n.get_script() == Burst)
	if not check(effects.size() == 1 and effects[0].player.has_animation(&"Death"),"The wreck should carry its death effects"): return
	await process_frame
	if not check(not is_instance_valid(building),"The Barracks itself should be gone"): return
	var die_length: float = model.player.get_animation(&"Die").length
	model.player.advance(die_length-0.08)
	var low := extent(model,model)
	if not check(low.end.y < 0.1,"The wreck should have sunk out of sight by the end: top %.2f" % low.end.y): return
	model.player.advance(0.2)
	await process_frame
	if not check(not is_instance_valid(model),"The wreck should remove itself"): return
	print("BARRACKS MODEL OK")
	quit(0)
