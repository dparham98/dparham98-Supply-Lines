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
const LASER := "res://scenes/gameplay/ubermech_laser.tscn"
const ROUND := "res://scenes/gameplay/ubermech_pod_round.tscn"
const PORTS := ["Pod01","Pod04","Pod05","Pod02","Pod03","Pod06"]
const RELEASES := [12,17,22,27,32,37]
const DT := 1./120.

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
	for clip in [&"Rest",&"Walk",&"Shoot",&"PodVolley"]:
		if not check(model.player.has_animation(clip),"Production actor imports "+str(clip)): return
	check(is_equal_approx(model.run_reference_speed,STRIDE_SPEED),"Walk reference speed matches 3.10 m/s")
	model.set_process(false)
	model.player.callback_mode_process=AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
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
	test_weapon_meshes(model)
	test_weapon_motion(model)
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

func check_socket_surface(model, socket: String, material: String, radius: float) -> float:
	var sk: Skeleton3D=model.skeleton
	var joint:=sk.find_bone(socket)
	if not check(joint>=0,"Exported socket "+socket): return INF
	var tip:=joint_in_model(model,sk,joint,true)
	var axis:=tip.basis.y.normalized()
	var area:=0.
	var weighted:=Vector3.ZERO
	# Find the coplanar triangles of the luminous lens or enamel cap on the
	# actual imported mesh. Area weighting gives a triangulation-independent centre.
	for part: MeshInstance3D in model.find_children("*","MeshInstance3D",true,false):
		var transform: Transform3D=model.global_transform.affine_inverse()*part.global_transform
		for surface in part.mesh.get_surface_count():
			if part.mesh.surface_get_material(surface).resource_name!=material: continue
			var arrays:=part.mesh.surface_get_arrays(surface)
			var v: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
			var ids: PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
			for i in range(0,ids.size(),3):
				var a: Vector3=transform*v[ids[i]]
				if a.distance_to(tip.origin)>radius: continue
				var b: Vector3=transform*v[ids[i+1]]
				var c: Vector3=transform*v[ids[i+2]]
				if b.distance_to(tip.origin)>radius or c.distance_to(tip.origin)>radius: continue
				var normal: Vector3=(b-a).cross(c-a)
				if normal.length_squared()<1.e-17 or absf(normal.normalized().dot(axis))<.997: continue
				var center: Vector3=(a+b+c)/3.
				if absf((center-tip.origin).dot(axis))>.0015: continue
				var weight:=normal.length()*.5
				area+=weight
				weighted+=center*weight
	if not check(area>PI*radius*radius*.20,"Resolved emitting end face of "+socket): return INF
	var error: float=(weighted/area).distance_to(tip.origin)
	check(error<.003,"%s socket lies on the centre of its visible end face (%.5f m)" %[socket,error])
	return error

func test_weapon_meshes(model) -> void:
	var errors: Dictionary={"Muzzle":check_socket_surface(model,"Muzzle","glow_core",.132)}
	for port in PORTS:
		errors[port]=check_socket_surface(model,port,"enamel",.014)
	measures["mesh_socket_error_m"]=errors

func test_weapon_motion(model) -> void:
	var sk: Skeleton3D=model.skeleton
	var slide:=sk.find_bone("EmitterSlide")
	if not check(slide>=0,"Emitter coupling is bound to its independent slide"): return
	model.player.play(&"Shoot",0.)
	seek(model,12./30.)
	var charged:=sk.get_bone_pose_position(slide)
	seek(model,15./30.)
	var travel:=charged.distance_to(sk.get_bone_pose_position(slide))
	check(travel>.12,"Emitter coupling visibly travels between charged and recoil poses")
	model.player.play(&"PodVolley",0.)
	for i in PORTS.size():
		var port: String=PORTS[i]
		var cap:=sk.find_bone(port.replace("Pod","PodCap"))
		if not check(cap>=0,"Retractable cap for "+port): return
		seek(model,float(RELEASES[i])/30.)
		var loaded:=sk.get_bone_pose_position(cap)
		seek(model,float(RELEASES[i]+2)/30.)
		check(loaded.distance_to(sk.get_bone_pose_position(cap))>.14,"Visible cap retracts after "+port+" fires")
		seek(model,59./30.)
		check(loaded.distance_to(sk.get_bone_pose_position(cap))<.005,"Visible cap reloads into "+port)
	measures["emitter_slide_travel_m"]=travel
	model.player.stop()

func inspect_release(fx: Node3D, model, target, port_index: int, expected_clip: String) -> Dictionary:
	var is_laser:=expected_clip=="Shoot"
	var socket: String="Muzzle" if is_laser else PORTS[port_index]
	var pose_time: float=model.player.current_animation_position
	var due: float=.4 if is_laser else float(RELEASES[port_index])/30.
	var sk: Skeleton3D=model.skeleton
	var joint:=sk.find_bone(socket)
	if not check(joint>=0,"Active rig has "+socket): return {}
	sk.force_update_all_bone_transforms()
	var end: Vector3=target.global_position+Vector3.UP*1.7+target.get_node("Visuals").position
	var tip: Transform3D=sk.global_transform*sk.get_bone_global_pose(joint)
	var start:=fx.global_position
	var axis:=tip.basis.y.normalized()
	check(model.current_clip()==StringName(expected_clip),"Release uses "+expected_clip)
	check(absf(pose_time-due)<DT*1.9,"Release at the authored time for %s (%.5f vs %.5f)"%[socket,pose_time,due])
	if is_laser:
		check(fx.get_node("Impact").global_position.distance_to(end)<.015,"Laser reaches its target at discharge")
		check(fx.get_node("Lens").is_visible_in_tree() and fx.get_node("Span/Core").is_visible_in_tree(),"Laser displays beam and lens flare")
	else:
		# The existing projectile starts half a model length beyond the socket.
		start=fx.to_global(Vector3.BACK*fx.half_length)
		check(not fx.damage_on_impact and not fx.on_impact.is_valid(),"Each pod round is visual-only")
		check(fx.get_node("Nose").is_visible_in_tree() and fx.get_node("Exhaust").is_visible_in_tree(),"Pod round carries its body and exhaust")
		var launch_position:=fx.global_position
		var hp: int=target.health
		fx._process(.025)
		check(fx.global_position.distance_to(end)<launch_position.distance_to(end),"Pod round visibly travels toward the target")
		fx._process(4.)
		check(target.health==hp and fx.is_queued_for_deletion(),"The round clears on arrival with no further damage")
	var error:=start.distance_to(tip.origin)
	var bearing:=Vector2(end.x-start.x,end.z-start.z).normalized()
	var alignment:=Vector2(axis.x,axis.z).normalized().dot(bearing)
	check(error<.016,"Effect starts at %s (%.5f m)" %[socket,error])
	check(alignment>.995,"%s points toward the target at discharge" %socket)
	return {"socket":socket,"clip_s":pose_time,"origin_error_m":error,"horizontal_alignment":alignment}

func check_shot_from_actor(game, unit, enemy):
	var model=unit.get_node("Visuals/Model")
	var initial: Vector3=enemy.global_position
	enemy.global_position=unit.global_position+Vector3.FORWARD*11.+Vector3.RIGHT*4.
	unit.fuel=unit.fuel_rules.reserve_capacity
	unit.command_attack(enemy)
	var before: int=enemy.health
	var unconfirmed: int=game.get_child_count()
	unit._cooldown=.30
	unit._attack_order()
	check(model.current_clip()==&"Shoot" and model.acting(),"In-range attack enters its wind-up before the cooldown expires")
	model.player.advance(.04)
	unit.command_move(unit.global_position)
	model.set_motion(&"idle")
	model._process(DT)
	model.player.advance(.50)
	check(not model.acting() and model.current_clip()==&"Rest" and enemy.health==before and game.get_child_count()==unconfirmed,
			"Interrupting the wind-up returns to rest without spending a strike")
	unit._cooldown=0.
	unit.command_attack(enemy)
	var strikes: Array[float]=[]
	var shots: Array[Dictionary]=[]
	var rounds:=0
	var lasers:=0
	# Exercise ordinary orders, cooldown, animation lead and the renderer hook
	# with a fixed tick. The model runs before its AnimationPlayer child.
	for tick in range(1250):
		var child_count: int=game.get_child_count()
		var hp: int=enemy.health
		unit._process(DT)
		model._process(DT)
		if hp!=enemy.health:
			strikes.append(tick*DT)
			check(hp-enemy.health==12,"A confirmed attack deals one 12-damage strike")
		for i in range(child_count,game.get_child_count()):
			var fx=game.get_child(i)
			if fx.scene_file_path==LASER:
				lasers+=1
				shots.append(inspect_release(fx,model,enemy,0,"Shoot"))
			elif fx.scene_file_path==ROUND:
				if check(rounds<6,"Volley has at most six visual rounds"):
					shots.append(inspect_release(fx,model,enemy,rounds,"PodVolley"))
				rounds+=1
			else:
				check(fx.scene_file_path!=game.tracer_scene.resource_path,"Ubermech uses its own weapon visuals")
		model.player.advance(DT)
	check(lasers==2 and rounds==6 and shots.size()==8,"Three attacks produce laser, six-port volley, laser")
	if shots.size()==8:
		check(shots[0].get("socket")=="Muzzle" and shots[-1].get("socket")=="Muzzle","Laser bookends the six distinct port releases")
	check(before-enemy.health==36 and strikes.size()==3,"The entire six-round volley resolves exactly once")
	for i in range(1,strikes.size()):
		check(absf(strikes[i]-strikes[i-1]-5.)<DT*2,"Strike cooldown remains five seconds")
	measures["combat"]={"damage":before-enemy.health,"strike_times_s":strikes,"releases":shots}
	# A different instance starts on its own laser, even after this walker
	# has used its laser again and would next choose its pod.
	var peer_count: int=game.get_child_count()
	enemy.fuel=enemy.fuel_rules.reserve_capacity
	enemy._cooldown=0.
	enemy.command_attack(unit)
	enemy._attack_order()
	check(game.get_child_count()==peer_count+1 and game.get_child(-1).scene_file_path==LASER,
			"Second Ubermech independently opens combat with its own laser")
	unit.command_move(unit.global_position)
	model.set_motion(&"run",STRIDE_SPEED)
	model._process(3.)
	model._process(DT)
	check(model.current_clip()==&"Walk","Movement resumes after either arm finishes its action")
	unit.command_attack(enemy)
	unit._cooldown=.25
	unit._attack_order()
	check(model.acting() and model.current_clip()==&"PodVolley","Next attack winds up the alternate arm")
	var before_cancel: int=game.get_child_count()
	var hp_before_cancel: int=enemy.health
	unit.command_move(unit.global_position)
	model.set_motion(&"run",STRIDE_SPEED)
	model._process(DT)
	model.player.advance(1.5)
	model._process(DT)
	check(model.current_clip()==&"Walk" and not model.acting() and
			game.get_child_count()==before_cancel and enemy.health==hp_before_cancel,
			"An interrupted pod wind-up resumes walking without launching any rounds")
	unit.command_attack(enemy)
	unit._cooldown=0.
	unit._attack_order()
	check(game.get_child_count()==before_cancel+1 and game.get_child(-1).scene_file_path==ROUND and
			model.current_clip()==&"PodVolley" and hp_before_cancel-enemy.health==12,
			"Reissuing the attack after interruption still fires the pod")
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
