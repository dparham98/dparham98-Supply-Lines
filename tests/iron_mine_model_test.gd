extends SceneTree
# Headless: the Iron Mine's model (assets/models/buildings/iron_mine.glb via scenes/models/iron_mine_model.tscn)
# fits its 2 x 2 footprint with its front toward +Z, its clips start at frame 0, a construction plan shows it
# going up with the work, it winds (skip lowered, sheave turning) while iron is taken from it and finishes its
# cycle before settling, goes dark once worked out, and a destroyed mine leaves a wreck that plays Die, sinks and
# removes itself.
const Burst = preload("res://scripts/components/burst_effect.gd")
const ROOT := "Rig/mine_root/"
const MODEL := "res://scenes/models/iron_mine_model.tscn"
var game: Node3D
var network: Node
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> bool:
	if ok: return true
	push_error(message); quit(1); return false
## The nearest valid mine site on iron deposit inside the starting Depot's range.
func site(near: Vector3) -> Vector3:
	var spec: Dictionary = network.plan_spec(&"iron_mine")
	var best := Vector3.INF
	for dz in range(-34,35):
		for dx in range(-34,35):
			var point: Vector3 = near+Vector3(dx,0,dz)
			if point.distance_to(near) >= best.distance_to(near): continue
			var start: Vector2i = network.footprint_start(point,spec.size)
			if network.plan_terrain_valid(start,spec.size,&"iron_mine") and not network.plan_overlaps(start,spec.size) and network.can_place_mine(point,game.depot): best = point
	return best
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
	# The clips: Idle, Work and Depleted loop, Build and Die play once, and every track starts on frame 0.
	var probe: Node3D = load(MODEL).instantiate()
	root.add_child(probe)
	var player: AnimationPlayer = probe.player
	for clip in ["Idle","Work","Depleted","Build","Die"]:
		if not check(player.has_animation(clip),"Mine clip %s missing: %s" % [clip,player.get_animation_list()]): return
		var animation := player.get_animation(clip)
		if not check((animation.loop_mode == Animation.LOOP_LINEAR) == (clip in ["Idle","Work","Depleted"]),"%s loop mode wrong" % clip): return
		for track in range(animation.get_track_count()):
			if not check(animation.track_get_key_count(track) > 0 and is_zero_approx(animation.track_get_key_time(track,0)),"%s track %s does not start at frame 0" % [clip,animation.track_get_path(track)]): return
	probe.free()
	# A construction plan: nothing stands at the start, the headframe by half the work, all of it at the end.
	var point := site(depot.global_position)
	if not check(point != Vector3.INF,"No Iron Mine site on iron deposit near the Depot"): return
	var plan = network.queue_plan(point,&"iron_mine")
	if not check(plan != null,"Iron Mine plan not placed"): return
	plan.set_process(false)
	var site_model: Node3D = plan.get_node_or_null("Visuals/Model")
	if not check(site_model != null and site_model.scene_file_path == MODEL,"The Iron Mine plan should show its model"): return
	var grid: Node3D = plan.get_node("Visuals/Grid")
	if not check(Vector2(site_model.position.x,site_model.position.z).is_equal_approx(Vector2(grid.position.x,grid.position.z)),"Site model should stand on the footprint grid"): return
	if not check(part(site_model,"collar").scale.y < 0.01 and part(site_model,"headframe").scale.y < 0.01,"Nothing should stand on a site before work starts"): return
	var iron: int = plan.spec.iron
	var energy: int = plan.spec.energy
	plan.added = {&"iron": iron/2}; plan.energy_paid = energy/2
	plan.refresh_label()
	var half: float = plan.progress_fraction()
	if not check(site_model.player.assigned_animation == &"Build" and absf(site_model.player.current_animation_position/site_model.player.get_animation(&"Build").length-half) < 0.01,"Build should follow construction progress: %.2f" % half): return
	if not check(part(site_model,"headframe").scale.y > 0.99 and part(site_model,"winch_house").scale.y < 0.01 and part(site_model,"lamp_post").scale.y < 0.01,"Half built: headframe up, winch house and lamp not yet (progress %.2f)" % half): return
	plan.added = {&"iron": iron}; plan.energy_paid = energy
	plan.refresh_label()
	for name in ["collar","headframe","sheave","skip","winch_house","drum","chute","ore_bin","lamp_post"]:
		if not check(part(site_model,name).scale.is_equal_approx(Vector3.ONE),"Fully built site should show the %s" % name): return
	plan.added = {}; plan.energy_paid = 0
	var building: Node3D = plan.complete_from_stock()
	if not check(building != null and building.is_in_group("mines"),"Iron Mine plan did not complete"): return
	building.set_process(false)
	await process_frame
	var model: Node3D = building.get_node("Visuals/Model")
	if not check(model.scene_file_path == MODEL and model.has_method("show_state"),"Iron Mine does not use the rigged model"): return
	# Inside its footprint, on the ground, front toward +Z; the sheave on the headframe is the tallest part.
	var box := extent(model,building)
	if not check(absf(box.position.y) < 0.05 and box.end.y > 3.6 and box.end.y < 4.1,"Iron Mine height wrong: y %.2f..%.2f" % [box.position.y,box.end.y]): return
	if not check(box.position.x > -1.01 and box.end.x < 1.01 and box.position.z > -1.01 and box.end.z < 1.01,"Iron Mine outside its 2 x 2 footprint: %s" % box): return
	if not check(box.size.x > 1.8 and box.size.z > 1.8,"Iron Mine should fill its footprint: %s" % box): return
	if not check(building.to_local(part(model,"ore_bin").global_position).z > 0.4 and building.to_local(part(model,"lamp_post").global_position).z > 0.4,"The ore bin and lamp should face +Z"): return
	var skip := part(model,"skip")
	var raised := skip.position
	# Nobody mining: Idle, lamp lit, skip hanging raised and empty.
	building._process(0.1)
	model.player.advance(0.5)
	if not check(model.player.assigned_animation == &"Idle" and not model.working(),"An unworked mine should stand idle"): return
	if not check(part(model,"lamp_post/lamp").scale.x > 0.5 and part(model,"skip/skip_ore").scale.x < 0.01 and skip.position.distance_to(raised) < 0.05,"Idle: lamp lit, skip raised and empty"): return
	# Infantry take iron: it winds, the skip drops into the shaft and the sheave turns.
	var before: int = building.remaining
	var taken: int = building.extract(5,"player")
	if not check(taken > 0 and building.remaining == before-taken,"Extraction should take iron"): return
	if not check(model.working() and model.player.assigned_animation == &"Work","A mine being worked should play Work"): return
	var wheel := part(model,"sheave").transform.basis
	model.player.advance(1.0)
	if not check(skip.position.y < raised.y-2.0,"Working: the skip should drop into the shaft (%.2f)" % skip.position.y): return
	if not check(not part(model,"sheave").transform.basis.is_equal_approx(wheel),"Working: the sheave should turn"): return
	# No more extraction: it finishes the winding cycle, then settles to Idle with the skip raised.
	building._process(building.work_hold+0.1)
	model._process(0.0)
	if not check(model.player.assigned_animation == &"Work","The mine should finish its winding cycle before settling"): return
	var work_length: float = model.player.get_animation(&"Work").length
	model.player.advance(work_length-model.player.current_animation_position+0.05)
	model._process(0.0)
	if not check(model.player.assigned_animation == &"Idle","After the cycle an unworked mine should go idle"): return
	if not check(skip.position.distance_to(raised) < 0.1,"The skip should be back up when the mine settles"): return
	# Worked out: dark, empty bin, Depleted.
	for cell in building.cells: building.ground.iron_reserves[cell] = 0
	building._process(0.1)
	# Advanced in steps, as frames do: a blend only completes on a later step than the one that ends it.
	for step in range(5): model.player.advance(0.1)
	if not check(building.remaining == 0 and model.depleted(),"A worked-out mine should play Depleted"): return
	if not check(part(model,"lamp_post/lamp").scale.x < 0.01 and part(model,"ore_bin/ore_heap").scale.x < 0.01,"Depleted: lamp out, bin empty"): return
	if not check(building.extract(5,"player") == 0 and model.depleted(),"A worked-out mine yields nothing and stays dark"): return
	# Destroyed: the building goes at once, its model stays behind as a wreck and removes itself.
	var parent := building.get_parent()
	building.take_damage(building.max_health)
	if not check(not building.is_in_group("selectable_buildings") and not building.is_in_group("mines"),"Destroyed mine still selectable"): return
	if not check(model.get_parent() == parent and model.dying() and model.player.assigned_animation == &"Die","A destroyed mine should leave its model playing Die"): return
	var effects := model.get_children().filter(func(n): return n.get_script() == Burst)
	if not check(effects.size() == 1 and effects[0].player.has_animation(&"Death"),"The wreck should carry its death effects"): return
	model.show_state(true,false)
	if not check(model.player.assigned_animation == &"Die","A wreck should ignore the working switch"): return
	await process_frame
	if not check(not is_instance_valid(building),"The mine itself should be gone"): return
	var die_length: float = model.player.get_animation(&"Die").length
	model.player.advance(die_length-0.08)
	var low := extent(model,model)
	if not check(low.end.y < 0.1,"The wreck should have sunk out of sight by the end: top %.2f" % low.end.y): return
	model.player.advance(0.2)
	await process_frame
	if not check(not is_instance_valid(model),"The wreck should remove itself"): return
	print("IRON_MINE_MODEL_TEST_PASSED")
	quit(0)
