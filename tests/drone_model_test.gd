extends SceneTree
# Headless: the Drone's animated model (assets/models/units/drone.glb via scenes/models/drone_model.tscn) faces -Z,
# hovers at flight height with its rotors turning, leans into Run while moving at the unit's pace, and on death
# loses a duct, spirals down to the ground, burns, and removes itself after the unit has left the game.
const Bounds = preload("res://scripts/units/selection_bounds.gd")
const ROTORS := ["FL","FR","RL","RR"]
var game: Node3D
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> bool:
	if value: return true
	push_error(message); quit(1); return false
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
	var unit: Node3D = load("res://scenes/gameplay/drone.tscn").instantiate()
	unit.team = "player"
	game.get_node("Entities/Units").add_child(unit)
	unit.set_process(false)
	for cell in unit._claimed.duplicate(): unit._release(cell)
	unit.global_position = origin
	await process_frame
	var model = unit.get_node("Visuals/Model")
	if not check(model.scene_file_path == "res://scenes/models/drone_model.tscn" and model.has_method("set_motion"),"Drone does not use the animated model"): return
	var player: AnimationPlayer = model.player
	for clip in ["Rest","Run","Die"]:
		if not check(player.has_animation(clip),"Drone clip %s missing: %s" % [clip,player.get_animation_list()]): return
	for looping in ["Rest","Run"]:
		if not check(player.get_animation(looping).loop_mode == Animation.LOOP_LINEAR,"%s should loop" % looping): return
	if not check(player.get_animation("Die").loop_mode == Animation.LOOP_NONE,"Die should play once"): return
	# Loops close on themselves, so nothing jerks as they wrap, whole rotor turns included.
	for clip in ["Rest","Run"]:
		var anim: Animation = player.get_animation(clip)
		for t in range(anim.get_track_count()):
			if anim.track_get_key_count(t) < 2: continue
			var last := anim.track_get_key_count(t)-1
			if anim.track_get_type(t) == Animation.TYPE_ROTATION_3D:
				var a: Quaternion = anim.track_get_key_value(t,0); var b: Quaternion = anim.track_get_key_value(t,last)
				if not check(absf(a.dot(b)) > 0.999,"%s does not close on %s" % [clip,anim.track_get_path(t)]): return
			elif anim.track_get_type(t) == Animation.TYPE_POSITION_3D:
				var p: Vector3 = anim.track_get_key_value(t,0); var q: Vector3 = anim.track_get_key_value(t,last)
				if not check(p.distance_to(q) < 0.002,"%s does not close on %s" % [clip,anim.track_get_path(t)]): return
	var body: Node3D = model.get_node("Rig/drone_root")
	var sensor: Node3D = body.get_node("sensor")
	var duct: Node3D = body.get_node("duct_FL")
	# Hovering 12 m up, the size of the concept, sensor to the front.
	player.play("Rest"); player.advance(1.0); player.seek(0.0,true)
	var meshes := Bounds.meshes(unit)
	if not check(meshes.size() >= 13,"Drone meshes missing: %d" % meshes.size()): return
	var low := INF; var high := -INF; var left := INF; var right := -INF
	for mesh in meshes:
		for i in range(8):
			var p: Vector3 = unit.global_transform.affine_inverse()*(mesh.global_transform*mesh.get_aabb().get_endpoint(i))
			low = minf(low,p.y); high = maxf(high,p.y); left = minf(left,p.x); right = maxf(right,p.x)
	if not check(low > 11.5 and low < 12.5 and high > 13.2 and high < 14.2 and right-left > 2.2 and right-left < 3.4,"Drone size wrong: y %.2f..%.2f x %.2f..%.2f" % [low,high,left,right]): return
	if not check(unit.to_local(sensor.global_position).z < -0.25,"Drone should face -Z, sensor at z %.2f" % unit.to_local(sensor.global_position).z): return
	# Every rotor turns, and neighbouring rotors turn opposite ways.
	var turn := {}
	for rotor in ROTORS:
		var part: Node3D = body.get_node("duct_%s/rotor_%s" % [rotor,rotor])
		player.seek(0.0,true); var a: Quaternion = part.quaternion
		player.seek(1.0/96,true); var b: Quaternion = part.quaternion
		turn[rotor] = (a.inverse()*b).get_euler().y
		if not check(absf(turn[rotor]) > 0.2,"Rotor %s does not turn" % rotor): return
	if not check(signf(turn["FL"]) != signf(turn["FR"]) and signf(turn["FL"]) == signf(turn["RR"]),"Rotors should counter-rotate: %s" % turn): return
	# It hovers: the hull rises and falls through Rest.
	player.seek(0.5,true); var up: float = body.position.y
	player.seek(1.5,true); var down: float = body.position.y
	if not check(up-down > 0.08,"Rest should bob, moved %.3f" % (up-down)): return
	step(unit,model,3)
	if not check(model.motion() == &"idle" and model.current_clip() == &"Rest" and player.is_playing(),"Idle should play Rest, got %s" % model.current_clip()): return
	# Moving plays Run at the unit's pace, nose down.
	unit.command_move(origin+Vector3(8,0,0))
	step(unit,model,30)
	if not check(unit.global_position != origin,"Drone did not move"): return
	if not check(model.motion() == &"run" and model.current_clip() == &"Run","Moving should play Run, got %s/%s" % [model.motion(),model.current_clip()]): return
	if not check(is_equal_approx(player.speed_scale,clampf(unit.move_speed/model.run_reference_speed,0.5,2.0)),"Run pace should follow move speed: %.2f" % player.speed_scale): return
	player.advance(0.5)
	var hull_forward: Vector3 = (body.global_basis*Vector3(0,0,1)).normalized()
	if not check(hull_forward.y < -0.1,"Run should lean nose down, forward y %.2f" % hull_forward.y): return
	unit._stop_route(); unit.order = "idle"
	step(unit,model,30)
	if not check(model.motion() == &"idle" and model.current_clip() == &"Rest","Rest should return when it stops, got %s" % model.current_clip()): return
	# Death: the unit is gone at once and the model falls from where it was.
	var where: Vector3 = model.global_position
	unit.take_damage(unit.health)
	if not check(unit.is_queued_for_deletion() and not unit.is_in_group("units"),"The unit should leave the game at once"): return
	if not check(model.get_parent() == game and model.dying() and model.current_clip() == &"Die","The wreck should stay and play Die"): return
	if not check(model.global_position.is_equal_approx(where),"The wreck moved when it was left behind"): return
	await process_frame
	if not check(not is_instance_valid(unit),"The unit should be freed"): return
	var effects := model.get_children().filter(func(n): return n.get_script() == preload("res://scripts/components/burst_effect.gd"))
	if not check(effects.size() == 1,"Crash effect missing"): return
	var ground: float = where.y-12.0
	player.advance(0.4) # seek() alone does not finish the blend into the clip
	player.seek(1.0,true)
	var falling: float = body.global_position.y-ground
	if not check(falling > 4.0 and falling < 12.5,"It should be part way down at 1 s, %.2f m up" % falling): return
	if not check(duct.global_position.distance_to(body.global_position) > 1.5,"The front-left duct should have torn away"): return
	player.seek(2.8,true)
	var wrecked: float = body.global_position.y-ground
	if not check(wrecked > 0.3 and wrecked < 1.3,"The hull should be on the ground, %.2f m up" % wrecked): return
	if not check(duct.global_position.y-ground > 0.0 and duct.global_position.y-ground < 4.0,"The torn duct should be coming down, %.2f m up" % (duct.global_position.y-ground)): return
	player.seek(player.get_animation("Die").length-0.02,true)
	player.advance(0.2)
	await process_frame
	await process_frame
	if not check(not is_instance_valid(model),"The wreck should remove itself"): return
	print("DRONE_MODEL_TEST_PASSED"); quit()
