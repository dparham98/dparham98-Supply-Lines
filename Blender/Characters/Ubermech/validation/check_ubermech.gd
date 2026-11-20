extends SceneTree
## Run from the Supply Lines project after Godot imports the model. An optional
## path after -- receives the measurements and test results as JSON.
const ACTOR := "res://scenes/gameplay/ubermech.tscn"
const WRAPPER := "res://scenes/models/ubermech_model.tscn"
const GLB := "res://assets/models/units/ubermech.glb"
const TWO_LAKES := "res://scenes/maps/lakes_skirmish.tscn"
const TeamPaint := preload("res://scripts/components/team_paint.gd")
const Bounds := preload("res://scripts/units/selection_bounds.gd")
const STRIDE_SPEED := 3.10

var checks := 0
var issues: Array[String] = []
var measures := {}

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> bool:
	checks += 1
	if not ok:
		issues.append(label)
		push_error(label)
	return ok

func finish() -> void:
	var report := {"checks":checks, "success":issues.is_empty(), "failures":issues,
		"measurements":measures, "model_sha256":FileAccess.get_sha256(GLB),
		"godot":Engine.get_version_info().string}
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		var file := FileAccess.open(args[0],FileAccess.WRITE)
		if file:
			file.store_string(JSON.stringify(report,"  ")+"\n")
		else:
			push_error("Unable to save requested report")
			quit(1)
			return
	print(JSON.stringify(report))
	quit(0 if issues.is_empty() else 1)

func check_scene() -> bool:
	var actor := (load(ACTOR) as PackedScene).instantiate()
	var slot = actor.get_node("Visuals")
	var model = slot.get_node("Model")
	var model_ok := check(model.scene_file_path==WRAPPER and slot.model_scene.resource_path==WRAPPER,
			"Serialized model and replaceable editor slot both point at the Ubermech model")
	var visible_meshes := 0
	for mesh in model.find_children("*","MeshInstance3D",true,false):
		if mesh.visible and mesh.mesh and mesh.mesh.get_surface_count() > 0:
			visible_meshes += 1
	check(visible_meshes>0,"The actor has authored mesh geometry before entering the tree")
	check(model.find_children("*","CollisionShape3D",true,false).is_empty(),"Visual model adds no gameplay collider")
	var stats = actor.unit_stats
	check(stats.unit_id==&"ubermech" and stats.max_health==120 and stats.movement_speed==4. and stats.turn_rate==120.,
			"Health, speed and turning match the accepted Ubermech")
	check(stats.attack_range==20. and stats.damage==12 and stats.attack_interval==5. and stats.abilities.is_empty(),
			"Combat values and abilities match the accepted Ubermech")
	check(stats.energy_cost==250 and stats.iron_cost==60 and stats.build_seconds==40. and stats.vision==36.,
			"Production costs, time and vision match the accepted Ubermech")
	measures["authored_mesh_nodes"] = visible_meshes
	actor.free()
	return model_ok

func build_at_home(game):
	var depot = game.depot
	var network = game.get_node("DepotNetwork")
	depot.storage_capacity = 10000
	depot.energy = 2000
	depot.iron = 2000
	network.select_depot(depot)
	var placed := false
	for x in range(-16,17,2):
		for z in range(-16,17,2):
			var point: Vector3 = depot.global_position+Vector3(x,0,z)
			if network.can_place_size(point,depot,Vector2i(8,8)):
				placed = network.construct_production(point,&"tank_factory")
				if placed: break
		if placed: break
	if not check(placed,"Construct a tank factory on eligible land inside the live Two Lakes depot territory"):
		return null
	var factory = get_first_node_in_group("production_buildings")
	if not check(factory!=null and factory.stats.building_id==&"tank_factory","Factory uses native production script"):
		return null
	var energy: int = depot.energy
	var iron: int = depot.iron
	if not check(factory.request_unit(&"ubermech"),"Factory accepts the Ubermech order"):
		return null
	check(energy-depot.energy==250 and iron-depot.iron==60,"Factory charges the original costs")
	factory._process(39.5)
	check(factory.queue==1,"Factory holds paid unit until completion")
	factory._process(.6)
	for unit in get_nodes_in_group("units"):
		if unit.team=="player" and unit.unit_stats and unit.unit_stats.unit_id==&"ubermech":
			check(factory.queue==0 and unit.health==120,"The factory releases a full-health production unit")
			check(unit.fuel==0,"Two Lakes factory-spawned Ubermech follows the empty-tank policy")
			measures["factory_spawn_cell"] = [unit.grid_position.x,unit.grid_position.y]
			return unit
	check(false,"Factory spawned a player Ubermech")
	return null

func test_paint(unit):
	var model = unit.get_node("Visuals/Model")
	var painted := 0
	var fixed := 0
	var optics := 0
	for mesh: MeshInstance3D in model.find_children("*","MeshInstance3D",true,false):
		for i in mesh.mesh.get_surface_count():
			var original: Material = mesh.mesh.surface_get_material(i)
			if original.resource_name in TeamPaint.material_names(model):
				painted += 1
				check(mesh.get_active_material(i)==TeamPaint.paint_for(unit.team),"Team panel uses "+unit.team+" paint")
			else:
				fixed += 1
				check(mesh.get_active_material(i)==original,"Unpainted material retained on "+str(original.resource_name))
				if original.resource_name=="glow_red": optics += 1
	check(painted>=1 and fixed>painted and optics>0,"Armour panels, static body surfaces and red emitters are present")
	return {"painted":painted,"fixed":fixed,"red_emissive":optics}

func joint_in_model(model, sk: Skeleton3D, bone: int, for_rest: bool) -> Transform3D:
	var t := sk.get_bone_global_rest(bone) if for_rest else sk.get_bone_global_pose(bone)
	return model.global_transform.affine_inverse()*sk.global_transform*t

func seek(model, seconds: float) -> void:
	model.player.seek(seconds,true)
	model.skeleton.force_update_all_bone_transforms()

func gait(model) -> void:
	var player: AnimationPlayer = model.player
	var sk: Skeleton3D = model.skeleton
	var length := player.get_animation(model.run_clip).length
	var feet: Array[int] = []
	var local_contacts: Array[Vector3] = []
	for side in ["R","L"]:
		var bone := sk.find_bone("Foot."+side)
		if bone<0: bone=sk.find_bone("Foot_"+side)
		if not check(bone>=0,"Walk includes rigid "+side+" ankle articulation"): return
		feet.append(bone)
		var rest := joint_in_model(model,sk,bone,true)
		local_contacts.append(rest.affine_inverse()*Vector3(rest.origin.x,0.,rest.origin.z-.12))
	var samples := 96
	var dt := length/samples
	var result := {}
	player.stop()
	player.play(model.run_clip,0.)
	player.advance(0.)
	for k in feet.size():
		var local_path := PackedVector3Array()
		var world_path := PackedVector3Array()
		for i in range(samples+1):
			var time := dt*i
			seek(model,time)
			var p: Vector3 = joint_in_model(model,sk,feet[k],false)*local_contacts[k]
			local_path.append(p)
			world_path.append(p+Vector3.FORWARD*STRIDE_SPEED*time)
		var min_y := INF
		var max_y := -INF
		var min_z := INF
		var max_z := -INF
		for p in local_path:
			min_y=minf(min_y,p.y)
			max_y=maxf(max_y,p.y)
			min_z=minf(min_z,p.z)
			max_z=maxf(max_z,p.z)
		# Find the most stable quarter-cycle with the heel close to the
		# floor, accounting for the enclosing actor's real forward motion.
		var best := INF
		var window := samples/4
		for start in range(samples-window+1):
			var err := 0.
			for j in range(start,start+window+1):
				err=maxf(err,world_path[start].distance_to(world_path[j]))
				err=maxf(err,absf(world_path[j].y))
			best=minf(best,err)
		check(min_y>-.045 and max_y-min_y>.08,"Each foot clears the ground during recovery")
		check(max_z-min_z>.65,"Each foot travels through a full fore-aft step")
		check(best<.085,"A planted sole stays put at 3.10 m/s, measured %.3f m" % best)
		check(local_path[0].distance_to(local_path[-1])<.025,"Foot paths close at the Walk seam")
		result[sk.get_bone_name(feet[k])]={"lift_m":max_y-min_y,"min_sole_m":min_y,
			"travel_m":max_z-min_z,"planted_error_m":best}
	measures["walk"] = result

func check_animator(unit):
	var model = unit.get_node("Visuals/Model")
	if not check(unit._animator()==model and model.player!=null and model.skeleton!=null,
			"Existing unit-agent animation path resolves model, skeleton and AnimationPlayer"): return
	if not check(model.player.has_animation("Rest") and model.player.has_animation("Walk") and model.player.has_animation("Shoot"),
			"Production actor imports Rest, Walk and Shoot"): return
	check(is_equal_approx(model.run_reference_speed,STRIDE_SPEED),"Walk reference speed matches 3.10 m/s")
	model.set_process(false)
	unit._animate()
	model._process(0.)
	check(model.current_clip()==&"Rest","Stationary actor rests")
	var origin: Vector3 = unit.global_position
	var walked := false
	unit.fuel=unit.fuel_rules.reserve_capacity
	for heading: Vector2i in [Vector2i.UP,Vector2i.DOWN,Vector2i.LEFT,Vector2i.RIGHT]:
		var goal: Vector2i = unit.grid_position+heading*4
		if not unit.ground.can_traverse(goal,unit.mobility_layer()): continue
		unit.command_move(unit.ground.tile_to_world(goal))
		for tick in 240:
			unit._process(1./60.)
			model._process(1./60.)
			model.player.advance(1./60.)
			if model.current_clip()==&"Walk" and is_equal_approx(model.player.speed_scale,unit.move_speed/STRIDE_SPEED):
				walked=true
			if unit.order=="idle": break
		if walked: break
	var distance := origin.distance_to(unit.global_position)
	check(walked and distance>2. and unit.order=="idle","A terrain move order walks at production speed and arrives")
	measures["factory_yard_walk_m"] = distance
	gait(model)
	model.play_action(&"shoot",model.gun_sample_time)
	seek(model,model.gun_sample_time)
	var tip: Vector3 = model.to_local(model.muzzle_position())
	var direction: Vector3 = model.global_basis.inverse()*model.gun_direction()
	check(model.acting() and model.current_clip()==&"Shoot" and model.has_gun_line(),"Existing Shoot action supplies a gun line")
	check(tip.z<-.80 and direction.z<-.85 and absf(direction.x)<.22,"The readied arm and muzzle point forward along Godot -Z")
	measures["firing_muzzle_local"] = [tip.x,tip.y,tip.z]
	measures["firing_direction_local"] = [direction.x,direction.y,direction.z]
	model._process(model.player.get_animation(model.shoot_clip).length+.1)
	model.set_motion(&"idle")
	model._process(0.)
	check(model.current_clip()==&"Rest","Actor resumes idle after Shoot")

func check_selection(unit, game):
	var marker: MeshInstance3D = unit.get_node("Visuals/TeamMarker")
	unit.set_selected(true)
	check(marker.visible and marker.has_meta(&"not_selectable"),"Selecting the production unit enables only its ground marker")
	var half: Vector2 = marker.get_instance_shader_parameter("half_size")
	check(half.is_equal_approx(marker.mesh.size/2.),"Ground-marker shape fits its mesh")
	var model = unit.get_node("Visuals/Model")
	var local_box := AABB()
	var first := true
	for mesh: MeshInstance3D in Bounds.meshes(unit):
		var transform: Transform3D = model.global_transform.affine_inverse()*mesh.global_transform
		for i in mesh.mesh.get_surface_count():
			var arrays := mesh.mesh.surface_get_arrays(i)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			for v in vertices:
				var p: Vector3 = transform*v
				local_box = AABB(p,Vector3.ZERO) if first else local_box.expand(p)
				first=false
	check(absf(local_box.position.y)<.015 and local_box.size.y>4.6,"Boots stand at ground height and the actor reads as a giant")
	check(unit.get_node("Status").position.y>local_box.end.y,"Floating status clears the rig")
	check(half.x>=maxf(-local_box.position.x,local_box.end.x)-.025 and half.y>=maxf(-local_box.position.z,local_box.end.z)-.025,
			"Resting silhouette fits over its ground marker")
	measures["authored_bounds_m"] = {"min":[local_box.position.x,local_box.position.y,local_box.position.z],
		"max":[local_box.end.x,local_box.end.y,local_box.end.z],"marker_size":[2*half.x,2*half.y]}
	var foot_idx: int = model.skeleton.find_bone("Foot.L")
	if foot_idx<0: foot_idx=model.skeleton.find_bone("Foot_L")
	if foot_idx>=0:
		var foot := joint_in_model(model,model.skeleton,foot_idx,true)
		check(half.x>absf(foot.origin.x)+.42 and half.y>.63,"Ground marker spans the boot footprint")
	var rig = game.get_node("CameraRig")
	rig.set_process(false)
	rig.focus_position(unit.global_position+Vector3.UP*2.,20.)
	for _i in range(180): rig.advance_camera(1./60.)
	var screen: Vector2 = rig.camera.unproject_position(unit.global_position+Vector3.UP*3.1)
	check(Bounds.hit_distance(unit,rig.camera,screen)<INF,"RTS picking hits the torso at gameplay distance")
	unit.set_selected(false)
	check(not marker.visible,"Deselection hides the ground marker")

func check_shot_from_actor(game, player, enemy):
	var model=player.get_node("Visuals/Model")
	var before: int=enemy.health
	var initial: Vector3=enemy.global_position
	enemy.global_position=player.global_position+Vector3.FORWARD*11.
	player.fuel=player.fuel_rules.reserve_capacity
	player._cooldown=0.
	player.command_attack(enemy)
	var before_children: int=game.get_child_count()
	player._attack_order()
	if check(game.get_child_count()>before_children,"An ordinary Ubermech attack order spawns its existing shot effect"):
		var tracer=game.get_child(-1)
		check(tracer.scene_file_path==game.tracer_scene.resource_path,"Existing map tracer is preserved")
		var start: Vector3=tracer.global_transform*Vector3(0,0,.5)
		var error:=start.distance_to(model.muzzle_position())
		check(error<.012,"World-space shot starts at the animated muzzle (%.4f m)" % error)
		check(enemy.health<before and model.current_clip()==&"Shoot","The existing attack system deals damage and plays the firing clip")
		measures["shot"]={"muzzle_error_m":error,"damage":before-enemy.health}
	enemy.global_position=initial

func run() -> void:
	if not check_scene():
		finish()
		return
	check(ProjectSettings.get_setting("application/run/main_scene")==TWO_LAKES,"Exercise the actual F5 map")
	root.size=Vector2i(1280,900)
	var game=(load(TWO_LAKES) as PackedScene).instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	for u in get_nodes_in_group("units"): u.set_process(false)
	var enemy=game.get_node("Entities/Units/EnemyUbermech")
	var player=build_at_home(game)
	if player:
		player.set_process(false)
		check(enemy.team=="enemy" and enemy.get_node("Visuals/Model").scene_file_path==WRAPPER,"Authored enemy inherits the replacement")
		measures["player_paint"]=test_paint(player)
		measures["enemy_paint"]=test_paint(enemy)
		check_animator(player)
		check_selection(player,game)
		check_shot_from_actor(game,player,enemy)
	game.free()
	finish()
