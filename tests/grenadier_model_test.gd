extends SceneTree
# Headless: the Grenadier's rigged model (assets/models/units/grenadier.glb via scenes/models/grenadier_model.tscn)
# faces -Z, stands about 1.85 m on the ground, carries Rest/Run/Shoot/Die clips, and the unit agent drives them:
# a step plays Run at the unit's pace, a shot brings the launcher to the shoulder with a muzzle flash and light,
# and a death leaves the model behind to fall, bleed oil and remove itself.
const Bounds = preload("res://scripts/units/selection_bounds.gd")
var game: Node3D
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> bool:
	if value: return true
	push_error(message); quit(1); return false
func actor(id: String, team: String, point: Vector3) -> Node3D:
	var unit = load("res://scenes/gameplay/"+id+".tscn").instantiate()
	unit.team = team
	game.get_node("Entities/Units").add_child(unit)
	unit.set_process(false)
	for cell in unit._claimed.duplicate(): unit._release(cell)
	unit.global_position = point
	return unit
func step(unit: Node3D, model: Node3D, frames: int) -> void:
	for i in range(frames):
		unit._process(1.0/60)
		model._process(1.0/60)
		if model.player: model.player.advance(1.0/60)
func run() -> void:
	game = load("res://scenes/maps/resource_skirmish.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	for node in get_nodes_in_group("units"): node.set_process(false)
	var origin := Vector3(180,0,180)
	var unit := actor("grenadier","player",origin)
	await process_frame
	var model = unit.get_node("Visuals/Model")
	if not check(model.scene_file_path == "res://scenes/models/grenadier_model.tscn" and model.has_method("set_motion"),"Grenadier does not use the animated model"): return
	var player: AnimationPlayer = model.player
	for clip in ["Rest","Run","Shoot","Die"]:
		if not check(player.has_animation(clip),"Grenadier clip %s missing: %s" % [clip,player.get_animation_list()]): return
	for looping in ["Rest","Run"]:
		if not check(player.get_animation(looping).loop_mode == Animation.LOOP_LINEAR,"%s should loop" % looping): return
	for once in ["Shoot","Die"]:
		if not check(player.get_animation(once).loop_mode == Animation.LOOP_NONE,"%s should play once" % once): return
	if not check(absf(player.get_animation("Run").length-0.75) < 0.01,"Run length: %.3f" % player.get_animation("Run").length): return
	var flash_bone: int = model.skeleton.find_bone("flash")
	if not check(flash_bone >= 0 and model.flash_light != null and model.skeleton.find_bone("gun") >= 0,"Launcher bones or muzzle light missing"): return
	# Loops close on themselves, so no clip jerks as it wraps.
	for clip in ["Rest","Run"]:
		var anim: Animation = player.get_animation(clip)
		for t in range(anim.get_track_count()):
			if anim.track_get_type(t) != Animation.TYPE_ROTATION_3D or anim.track_get_key_count(t) < 2: continue
			var a: Quaternion = anim.track_get_key_value(t,0); var b: Quaternion = anim.track_get_key_value(t,anim.track_get_key_count(t)-1)
			if not check(absf(a.dot(b)) > 0.999,"%s does not close on %s" % [clip,anim.track_get_path(t)]): return
	for clip in ["Rest","Run"]:
		player.play(clip); player.seek(0.1,true); model.skeleton.force_update_all_bone_transforms()
		if not check(model.skeleton.get_bone_pose_scale(flash_bone).x < 0.05,"%s should keep the flash shut" % clip): return
	# Size and facing, measured at Rest.
	player.play("Rest"); player.seek(0.0,true); model.skeleton.force_update_all_bone_transforms()
	var meshes := Bounds.meshes(unit)
	if not check(meshes.size() >= 10,"Grenadier meshes missing: %d" % meshes.size()): return
	var low := INF; var high := -INF; var left := INF; var right := -INF
	for mesh in meshes:
		for i in range(8):
			var p: Vector3 = unit.global_transform.affine_inverse()*(mesh.global_transform*mesh.get_aabb().get_endpoint(i))
			low = minf(low,p.y); high = maxf(high,p.y); left = minf(left,p.x); right = maxf(right,p.x)
	if not check(absf(low) < 0.1 and high > 1.6 and high < 2.1 and right-left < 1.6,"Grenadier size wrong: y %.2f..%.2f x %.2f..%.2f" % [low,high,left,right]): return
	var head: int = model.skeleton.find_bone("head")
	if not check(head >= 0,"Head bone missing"): return
	var goggles: MeshInstance3D = model.get_node("Rig/grenadier_rig/Skeleton3D/goggles")
	var goggle_local: Vector3 = goggles.get_aabb().get_center()
	var head_local: Vector3 = model.skeleton.get_bone_global_rest(head).origin
	if not check(unit.to_local(model.skeleton.to_global(goggle_local)).z < unit.to_local(model.skeleton.to_global(head_local)).z,"Grenadier should face -Z"): return
	# Carried low at Rest.
	if not check(model.muzzle_position().y < 0.6,"Launcher should hang low at Rest, muzzle y %.2f" % model.muzzle_position().y): return
	step(unit,model,3)
	if not check(model.motion() == &"idle" and model.current_clip() == &"Rest" and player.is_playing(),"Idle should play Rest, got %s" % model.current_clip()): return
	# Walking plays Run at the unit's pace.
	unit.command_move(origin+Vector3(6,0,0))
	step(unit,model,30)
	if not check(unit.global_position != origin,"Grenadier did not move"): return
	if not check(model.motion() == &"run" and model.current_clip() == &"Run","Walking should play Run, got %s/%s" % [model.motion(),model.current_clip()]): return
	if not check(is_equal_approx(player.speed_scale,unit.move_speed/model.run_reference_speed),"Run pace should follow move speed: %.2f" % player.speed_scale): return
	unit._stop_route(); unit.order = "idle"
	var foe := actor("hostile","enemy",origin+Vector3(4,0,0))
	await process_frame
	unit.global_position = origin
	var health_before: int = foe.health
	step(unit,model,2)
	if not check(foe.health < health_before,"Grenadier did not fire"): return
	if not check(model.acting() and model.current_clip() == &"Shoot","A shot should play Shoot, got %s" % model.current_clip()): return
	if not check(model.skeleton.get_bone_pose_scale(flash_bone).x > 0.5 and model.flash_light.visible and model.flash_light.light_energy > 0.4,"The shot should light the muzzle flash (scale %.2f)" % model.skeleton.get_bone_pose_scale(flash_bone).x): return
	var muzzle: Vector3 = model.muzzle_position()-unit.global_position
	if not check(muzzle.y > 1.2 and muzzle.y < 2.0 and Vector2(muzzle.x,muzzle.z).length() < 1.4,"The launcher should be shouldered when it fires: %s" % muzzle): return
	# One grenade leaves the barrel, lobs above the straight line, tumbles, and bursts where it lands.
	var shots := game.get_children().filter(func(n): return n.scene_file_path == "res://scenes/gameplay/grenade_round.tscn")
	if not check(shots.size() == 1,"One grenade should fire, got %d" % shots.size()): return
	var grenade: Node3D = shots[0]
	if not check(grenade.global_position.distance_to(model.muzzle_position()) < 0.7,"The grenade should leave the barrel"): return
	var body: Node3D = grenade.get_node("Model/grenade_round")
	var body_start: Basis = body.transform.basis
	var chord_from: Vector3 = grenade.global_position
	var chord_to: Vector3 = grenade._end
	var peak := 0.0
	for i in range(300):
		if grenade.is_queued_for_deletion(): break
		grenade._process(1.0/60)
		var along: float = clampf((grenade.global_position-chord_from).dot(chord_to-chord_from)/chord_from.distance_squared_to(chord_to),0.0,1.0)
		peak = maxf(peak,grenade.global_position.y-lerpf(chord_from.y,chord_to.y,along))
		if i == 5 and not check(not body.transform.basis.is_equal_approx(body_start),"The grenade should tumble"): return
	if not check(grenade.is_queued_for_deletion(),"The grenade should land"): return
	if not check(peak > 0.1*chord_from.distance_to(chord_to),"The grenade should arc, rose %.2f m" % peak): return
	var blasts := game.get_children().filter(func(n): return n.scene_file_path == "res://scenes/gameplay/grenade_blast.tscn")
	if not check(blasts.size() == 1 and blasts[0].global_position.distance_to(chord_to) < 0.05,"One blast should go off where the grenade lands"): return
	var blast: Node3D = blasts[0]
	if not check(blast.player.has_animation("Impact") and blast.flash.scale.x > 0.5 and blast.light.visible,"The blast should start with a flash"): return
	blast.player.advance(blast.player.current_animation_length+0.1)
	await process_frame
	await process_frame
	if not check(not is_instance_valid(blast),"The blast should remove itself"): return
	# The barrel line runs through the target even though the launcher sits off to her right.
	step(unit,model,6)
	var gun_from: Vector3 = model.muzzle_position(); var gun_dir: Vector3 = model.gun_direction()
	gun_from.y = 0; gun_dir.y = 0; gun_dir = gun_dir.normalized()
	var to_foe: Vector3 = Vector3(foe.global_position.x,0,foe.global_position.z)-gun_from
	var miss: float = (to_foe-gun_dir*to_foe.dot(gun_dir)).length()
	if not check(model.has_gun_line() and to_foe.dot(gun_dir) > 0 and miss < 0.45,"Gun line misses the target by %.2f m (dir %s)" % [miss,gun_dir]): return
	var barrel: Vector3 = (model.skeleton.global_transform.basis*model.skeleton.get_bone_global_pose(flash_bone).basis.y).normalized()
	if not check(barrel.dot(model.gun_direction()) > 0.995,"Gun line should follow the barrel, dot %.4f" % barrel.dot(model.gun_direction())): return
	# Between shots the launcher stays up; once the target is gone it comes back down.
	step(unit,model,80)
	if not check(not model.acting() and model.motion() == &"aim" and player.assigned_animation == "Shoot" and not player.is_playing(),"Launcher should hold its aim between shots (motion %s, clip %s)" % [model.motion(),player.assigned_animation]): return
	if not check(model.muzzle_position().y > 1.2 and model.skeleton.get_bone_pose_scale(flash_bone).x < 0.05 and not model.flash_light.visible,"Held aim should keep the launcher up with the flash out"): return
	foe.free()
	await process_frame
	step(unit,model,45)
	if not check(not model.acting() and model.motion() == &"idle" and model.current_clip() == &"Rest","Rest should return once the target is gone, got %s" % model.current_clip()): return
	# Death: the unit is gone at once, the model plays out where it stood, the launcher drops, and it removes itself.
	var where: Vector3 = model.global_position
	unit.take_damage(unit.health)
	if not check(unit.is_queued_for_deletion() and not unit.is_in_group("units"),"The unit should leave the game at once"): return
	if not check(model.get_parent() == game and model.dying() and model.current_clip() == &"Die","The corpse should stay and play Die"): return
	if not check(model.global_position.is_equal_approx(where),"The corpse moved when it was left behind"): return
	await process_frame
	if not check(not is_instance_valid(unit),"The unit should be freed"): return
	var effects := model.get_children().filter(func(n): return n.get_script() == preload("res://scripts/components/burst_effect.gd"))
	if not check(effects.size() == 1,"Oil effect missing"): return
	player.advance(0.2) # seek() alone does not finish the blend into the clip
	player.seek(2.0,true); model.skeleton.force_update_all_bone_transforms()
	var gun: int = model.skeleton.find_bone("gun")
	var dropped: Transform3D = model.skeleton.get_bone_global_pose(gun)
	if not check(dropped.origin.y < 0.3 and absf(dropped.basis.y.normalized().y) < 0.25,"The launcher should be lying on the ground: y %.2f" % dropped.origin.y): return
	if not check(model.skeleton.get_bone_global_pose(head).origin.y < 0.75,"She should be down by 2 s, head at %.2f" % model.skeleton.get_bone_global_pose(head).origin.y): return
	player.seek(player.get_animation("Die").length-0.02,true)
	player.advance(0.2)
	await process_frame
	await process_frame
	if not check(not is_instance_valid(model),"The corpse should remove itself"): return
	print("GRENADIER_MODEL_TEST_PASSED"); quit()
