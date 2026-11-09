extends SceneTree
# Headless: the Infantry's rigged model (assets/models/units/infantry.glb via scenes/models/infantry_model.tscn)
# faces -Z, stands 1.8 m on the ground, carries Rest/Run/Hack/Shoot clips, and the unit agent drives
# them: a step plays Run at the unit's pace, gathering plays Hack with the saw teeth running, a shot
# plays Shoot once and returns to Rest. Tracers leave the pistol bone.
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
	var unit := actor("infantry","player",origin)
	await process_frame
	var model = unit.get_node("Visuals/Model")
	if not check(model.scene_file_path == "res://scenes/models/infantry_model.tscn" and model.has_method("set_motion"),"Infantry does not use the animated model"): return
	var player: AnimationPlayer = model.player
	if not check(player != null and player.has_animation("Rest") and player.has_animation("Run") and player.has_animation("Hack") and player.has_animation("Shoot"),"Infantry clips missing: %s" % [player.get_animation_list() if player else []]): return
	for looping in ["Rest","Run","Hack"]:
		if not check(player.get_animation(looping).loop_mode == Animation.LOOP_LINEAR,"%s should loop" % looping): return
	if not check(player.get_animation("Shoot").loop_mode == Animation.LOOP_NONE,"Shoot should play once"): return
	if not check(model.skeleton != null and model.skeleton.get_bone_count() == 21,"Infantry skeleton missing"): return
	# The saw is picked out in bright steel so it reads against the dark coat.
	var saw: MeshInstance3D = model.get_node("Rig/infantry_rig2/Skeleton3D/chainsaw_rig")
	if not check(saw.material_override is StandardMaterial3D and saw.material_override.albedo_color.v > 0.6 and model.teeth.material_override is ShaderMaterial,"Saw should carry the bright steel override"): return
	# Size and facing: on the ground, about 1.8 m tall, within a tile, eyes toward -Z.
	var meshes := Bounds.meshes(unit)
	if not check(meshes.size() >= 5,"Infantry meshes missing: %d" % meshes.size()): return
	var low := INF; var high := -INF; var left := INF; var right := -INF
	for mesh in meshes:
		for i in range(8):
			var p: Vector3 = unit.global_transform.affine_inverse()*(mesh.global_transform*mesh.get_aabb().get_endpoint(i))
			low = minf(low,p.y); high = maxf(high,p.y); left = minf(left,p.x); right = maxf(right,p.x)
	if not check(absf(low) < 0.05 and high > 1.6 and high < 2.0 and right-left < 1.4,"Infantry size wrong: y %.2f..%.2f x %.2f..%.2f" % [low,high,left,right]): return
	var eye: MeshInstance3D = model.get_node("Rig/infantry_rig2/Skeleton3D/eye_lens_rig")
	var eye_local: Vector3 = unit.to_local(eye.global_transform*eye.get_aabb().get_center())
	if not check(eye_local.z < -0.05,"Infantry should face -Z; eye at %s" % eye_local): return
	# Idle before any report.
	step(unit,model,3)
	if not check(model.motion() == &"idle" and model.current_clip() == &"Rest" and player.is_playing(),"Idle should play Rest, got %s" % model.current_clip()): return
	# Walking plays Run at the unit's pace.
	unit.command_move(origin+Vector3(6,0,0))
	step(unit,model,30)
	if not check(unit.global_position != origin,"Infantry did not move"): return
	if not check(model.motion() == &"run" and model.current_clip() == &"Run","Walking should play Run, got %s/%s" % [model.motion(),model.current_clip()]): return
	if not check(is_equal_approx(player.speed_scale,unit.move_speed/model.run_reference_speed),"Run pace should follow move speed: %.2f" % player.speed_scale): return
	# Gathering plays Hack and runs the saw teeth.
	unit._stop_route(); unit.order = "idle"
	unit.state = "Gathering"; unit._work_timer = 0.0; unit._animate(); model._process(1.0/60)
	if not check(model.current_clip() == &"Hack","Gathering should play Hack, got %s" % model.current_clip()): return
	# Two swings per extraction: the 1.5 s one-swing clip runs so two fit the 1.2 s gather cycle.
	if not check(is_equal_approx(unit.harvest_interval,1.2),"Gather cycle should be 1.2 s, got %.2f" % unit.harvest_interval): return
	if not check(is_equal_approx(player.speed_scale,player.get_animation("Hack").length*2.0/unit.harvest_interval),"Hack pace should fit two swings per cycle: %.2f" % player.speed_scale): return
	if not check(player.current_animation_position < 0.05,"Hack should restart with the work cycle"): return
	if not check(model.teeth != null and is_equal_approx(model.teeth.get_instance_shader_parameter(&"speed"),model.teeth_speed),"Saw teeth should run while hacking"): return
	unit.state = "Idle"; unit._animate(); model._process(1.0/60)
	if not check(model.current_clip() == &"Rest" and is_zero_approx(model.teeth.get_instance_shader_parameter(&"speed")),"Teeth should stop and Rest resume when idle"): return
	# A shot plays Shoot once from the pistol, then Rest returns.
	var foe := actor("hostile","enemy",origin+Vector3(3,0,0))
	await process_frame
	var health_before: int = foe.health
	var muzzle: Vector3 = model.muzzle_position()
	if not check(muzzle.y > 0.5 and muzzle.y < 1.3 and Vector2(muzzle.x-unit.global_position.x,muzzle.z-unit.global_position.z).length() < 0.8,"Muzzle should be at the pistol: %s" % (muzzle-unit.global_position)): return
	step(unit,model,2)
	if not check(foe.health < health_before,"Infantry did not fire"): return
	if not check(model.acting() and model.current_clip() == &"Shoot","A shot should play Shoot, got %s" % model.current_clip()): return
	# The gun line, not the face, runs through the target: the pistol sits beside the body, so the body turns past it.
	step(unit,model,6)
	var gun_from: Vector3 = model.muzzle_position(); var gun_dir: Vector3 = model.gun_direction()
	gun_from.y = 0; gun_dir.y = 0; gun_dir = gun_dir.normalized()
	var to_foe: Vector3 = Vector3(foe.global_position.x,0,foe.global_position.z)-gun_from
	var miss: float = (to_foe-gun_dir*to_foe.dot(gun_dir)).length()
	if not check(model.has_gun_line() and to_foe.dot(gun_dir) > 0 and miss < 0.25,"Gun line misses the target by %.2f m (dir %s)" % [miss,gun_dir]): return
	var face_yaw: float = atan2(-(foe.global_position.x-unit.global_position.x),-(foe.global_position.z-unit.global_position.z))
	if not check(absf(angle_difference(unit.get_node("Visuals").rotation.y,face_yaw)) > deg_to_rad(2),"Body should turn past the face line so the offset gun lines up"): return
	# Between shots the gun stays up on the target; the next shot is a recoil from that pose, not from Rest.
	step(unit,model,45)
	if not check(not model.acting() and model.motion() == &"aim" and player.assigned_animation == "Shoot" and not player.is_playing(),"Gun should hold its aim between shots (motion %s, clip %s)" % [model.motion(),player.assigned_animation]): return
	var held: Vector3 = model.muzzle_position()
	if not check(held.y > 0.95,"Held aim should keep the pistol raised, muzzle y %.2f" % held.y): return
	var health_mid: int = foe.health
	for i in range(90):
		step(unit,model,1)
		if foe.health < health_mid: break
	if not check(foe.health < health_mid and model.acting() and player.is_playing() and player.current_animation == "Shoot","Second shot should play the recoil from the held pose"): return
	foe.free()
	await process_frame
	step(unit,model,45)
	if not check(not model.acting() and model.motion() == &"idle" and model.current_clip() == &"Rest","Rest should return once the target is gone, got %s" % model.current_clip()): return
	if not check(model.muzzle_position().y < 0.9,"Pistol should drop at Rest"): return
	print("INFANTRY_MODEL_TEST_PASSED"); quit()
