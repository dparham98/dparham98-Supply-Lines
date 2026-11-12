extends SceneTree
# Headless: the fenced construction site model (docs/CONSTRUCTION_SITE_MODEL.md). Each footprint size's saved
# scene stays on its footprint, has lamps, loops its bunting and carries clutter only on the large sites. In the
# skirmish a plan stands the right site round itself; its lamps follow the site's state (amber waiting, green
# ready, blinking blue building), the clutter clears near the end, and the site goes with the plan. Rails get
# none. How it looks is for tests/construction_site_runtime_check.gd.
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
## Every mesh's box in the site's own space.
func bounds(node: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for mesh in node.find_children("*","MeshInstance3D",true,false):
		var local: Transform3D = node.global_transform.affine_inverse()*mesh.global_transform
		var part: AABB = local*mesh.get_aabb()
		box = part if first else box.merge(part)
		first = false
	return box
func run() -> void:
	# The saved scenes, one per footprint size.
	var plan_scene: Node3D = load("res://scenes/gameplay/construction_plan.tscn").instantiate()
	var scenes: Dictionary = plan_scene.site_scenes
	plan_scene.free()
	if not check(scenes.keys().size() == 5,"Expected site scenes for 2, 3, 6, 8 and 10: %s" % [scenes.keys()]): return
	for size: int in [2,3,6,8,10]:
		var model: Node3D = scenes[size].instantiate()
		root.add_child(model)
		var box := bounds(model)
		var h: float = size*0.5+0.12
		if not check(box.position.x >= -h and box.end.x <= h and box.position.z >= -h and box.end.z <= h,"The %dx%d site should stay on its footprint: %s" % [size,size,box]): return
		if not check(box.position.y >= -0.06 and box.end.y < 2.3,"The %dx%d site should stand low on the ground: %s" % [size,size,box]): return
		if not check(model.lamps.size() >= 4,"The %dx%d site should have lamps" % [size,size]): return
		if not check(model.player.get_animation(&"Idle").loop_mode == Animation.LOOP_LINEAR and model.player.is_playing(),"The bunting should sway in a looping Idle"): return
		if not check((model.props.size() > 0) == (size >= 6),"Only the large sites carry clutter: %dx%d has %d" % [size,size,model.props.size()]): return
		# The gate faces the camera (+Z): the front edge has a gap with no rope across it.
		var front_ropes := 0
		for rope in model.find_children("*rope_0_*","MeshInstance3D",true,false): front_ropes += 1
		if not check(front_ropes < size,"The %dx%d front should leave a gate: %d ropes" % [size,size,front_ropes]): return
		model.free()
	game = load("res://scenes/maps/resource_skirmish.tscn").instantiate()
	root.add_child(game)
	for i in range(3): await process_frame
	network = game.get_node("DepotNetwork")
	game.set_process(false)
	for unit in get_nodes_in_group("units"): unit.set_process(false)
	for depot in get_nodes_in_group("depots"): depot.set_process(false)
	var depot = game.depot
	depot.storage_capacity = 10000
	depot.energy = 5000; depot.iron = 5000
	# Each building's plan stands the site of its own size, centred on the footprint like the building.
	var expected := {&"iron_mine": 2, &"generator": 3, &"barracks": 6, &"tank_factory": 8, &"depot": 10}
	for kind in expected:
		var point: Vector3 = site(kind,depot.global_position+Vector3(0,0,-20 if kind == &"barracks" else 0))
		if kind == &"iron_mine":
			point = Vector3.INF
			var spec: Dictionary = network.plan_spec(kind)
			for dz in range(-40,41,2):
				for dx in range(-40,41,2):
					var p: Vector3 = depot.global_position+Vector3(dx,0,dz)
					var start: Vector2i = network.footprint_start(p,spec.size)
					if point == Vector3.INF and network.plan_terrain_valid(start,spec.size,kind) and not network.plan_overlaps(start,spec.size) and network.can_place_mine(p,depot): point = p
		if not check(point != Vector3.INF,"No site for %s" % kind): return
		var plan = network.queue_plan(point,kind)
		if not check(plan != null,"%s plan not placed" % kind): return
		plan.set_process(false)
		var fence: Node3D = plan.get_node_or_null("Visuals/Site")
		if not check(fence != null and fence.scene_file_path.ends_with("construction_site_%dx%d.tscn" % [expected[kind],expected[kind]]),"%s plan should stand the %dx%d site" % [kind,expected[kind],expected[kind]]): return
		var grid: Node3D = plan.get_node("Visuals/Grid")
		if not check(fence.position.x == grid.position.x and fence.position.z == grid.position.z,"The site should be centred on the footprint"): return
		var model: Node3D = plan.get_node_or_null("Visuals/Model")
		if model != null and not check(model.position == fence.position,"The rising building and the site should share a centre"): return
		if kind != &"barracks": plan.cancel()
	await process_frame
	# A rail plan has no site round it.
	var barracks_plan = get_nodes_in_group("construction_plans").filter(func(p): return p.kind == &"barracks")[0]
	var rail_spec: Dictionary = network.plan_spec(&"rail")
	if not check(not barracks_plan.site_scenes.has(rail_spec.size.x) or rail_spec.size.x != rail_spec.size.y,"Rails should get no site"): return
	# States: amber waiting, green ready, blue blinking while building; the grid fades behind the fence.
	var plan = barracks_plan
	var fence: Node3D = plan.get_node("Visuals/Site")
	plan.refresh_state()
	if not check(fence.state == &"waiting" and fence.lamp_material.emission.r > 0.9 and fence.lamp_material.emission_energy_multiplier > 0,"Lamps should glow amber while materials are short"): return
	var tint: Color = plan.get_node("Visuals/Grid").material_override.get_shader_parameter("tint")
	if not check(is_equal_approx(tint.a,plan.TINT_WAITING.a*plan.grid_opacity_with_site),"The grid should fade behind the fence: %s" % tint): return
	plan.receive(&"iron",plan.spec.iron)
	plan.refresh_state()
	if not check(fence.state == &"ready" and fence.lamp_material.emission.g > 0.9,"Lamps should turn green once the materials are on site"): return
	plan.work(null,5)
	if not check(plan.state.begins_with("Constructing") and fence.state == &"building" and fence.lamp_material.emission.b > 0.9,"Lamps should turn blue while building: %s" % plan.state): return
	# Blinking: on, then off half a period later, then on again.
	if not check(fence.lit(),"Lamps should start lit"): return
	fence._process(fence.blink_period*0.6)
	if not check(not fence.lit() and fence.lamp_material.emission_energy_multiplier == 0.0,"Lamps should blink off"): return
	fence._process(fence.blink_period*0.5)
	if not check(fence.lit() and fence.lamp_material.emission_energy_multiplier > 0.0,"Lamps should blink back on"): return
	# Clutter stays early and is cleared once the building is nearly up.
	if not check(fence.props.all(func(p): return p.visible),"Clutter should stand early in the build"): return
	while plan.progress_fraction() < fence.clear_props_at: plan.work(null,5)
	if not check(fence.props.all(func(p): return not p.visible),"Clutter should be cleared near the end: %.2f" % plan.progress_fraction()): return
	# Each site keeps its own lamp colours: another plan stays amber.
	var other_point := site(&"generator",depot.global_position+Vector3(20,0,0))
	var other = network.queue_plan(other_point,&"generator")
	other.set_process(false)
	other.refresh_state()
	if not check(other.get_node("Visuals/Site").lamp_material != fence.lamp_material and other.get_node("Visuals/Site").state == &"waiting" and fence.state == &"building","Sites should keep their own lamp colours"): return
	other.cancel()
	# Finishing removes the site with the plan.
	for i in range(200):
		if plan.finished: break
		plan.work(null,5)
	await process_frame
	if not check(not is_instance_valid(fence),"The site should go when the building is finished"): return
	print("CONSTRUCTION_SITE_MODEL_TEST_PASSED")
	quit(0)
