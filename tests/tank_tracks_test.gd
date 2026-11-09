extends SceneTree
# Headless: rolling Tank tracks (scripts/components/tank_rig.gd, docs/TANK_TRACKS.md). Travel
# follows ground speed at world scale, stops with the tank, runs the sides against each other in a
# turn, and the unit agent drives it. The moving picture is covered by tank_model_runtime_check.
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> bool:
	if value: return true
	push_error(message); quit(1); return false
func drive(model: Node3D, frames: int, speed: float, turn := 0.0) -> void:
	for i in range(frames):
		model.set_drive(speed,turn,1.0/60)
		model._process(1.0/60)
func run() -> void:
	var model = load("res://scenes/models/tank_model.tscn").instantiate()
	root.add_child(model)
	await process_frame
	var hull: Node3D = model.get_node("Tank/Tank_Root/Tank_Hull")
	for side in ["L","R"]:
		for part in ["Track_Links_","Road_Wheels_","Return_Rollers_"]:
			if not check(hull.get_node(part+side).material_override is ShaderMaterial,"%s%s has no running-gear material" % [part,side]): return
	if not check(model.track_travel_left() == 0.0 and model.link_phase(0.0) == 0.0,"Tracks should start at the authored pose"): return
	# One second at 3 m/s and world scale 0.6 is 5 model units on both sides.
	drive(model,60,3.0)
	if not check(absf(model.track_travel_left()-5.0) < 0.01 and absf(model.track_travel_right()-5.0) < 0.01,"Travel wrong: %.3f / %.3f" % [model.track_travel_left(),model.track_travel_right()]): return
	var sprocket: Node3D = hull.get_node("Drive_Sprocket_L")
	if not check(absf(angle_difference(sprocket.rotation.x,fposmod(model.track_travel_left()/model.end_wheel_radius,TAU))) < 0.01,"Sprocket does not roll with the track"): return
	# Stopped: no further travel once reports lapse.
	await process_frame; await process_frame
	var stopped: float = model.track_travel_left()
	for i in range(30): model._process(1.0/60)
	if not check(model.track_travel_left() == stopped,"Tracks kept rolling after the tank stopped"): return
	# A left turn on the spot runs the left track backward and the right forward, briefly.
	var right_before: float = model.track_travel_right()
	drive(model,1,0.0,deg_to_rad(45))
	await process_frame; await process_frame
	for i in range(5): model._process(1.0/60)
	if not check(model.track_travel_left() < stopped and model.track_travel_right() > right_before,"Pivot should counter-rotate the tracks"): return
	for i in range(30): model._process(1.0/60)
	var settled: float = model.track_travel_right()
	for i in range(30): model._process(1.0/60)
	if not check(model.track_travel_right() == settled,"Pivot did not end"): return
	model.free()
	# The unit agent reports Tank movement to the rig.
	var game = load("res://scenes/maps/resource_skirmish.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	var tank = load("res://scenes/gameplay/tank.tscn").instantiate()
	tank.position = game.depot.global_position+Vector3(-8,0,10)
	game.get_node("Entities/Units").add_child(tank); tank.set_process(false)
	await process_frame
	var rig = tank.get_node("Visuals/Model")
	tank._animate(1.0/60)
	for i in range(30):
		tank.global_position += Vector3(0,0,-0.05)
		tank._animate(1.0/60)
		rig._process(1.0/60)
	if not check(absf(rig.track_travel_left()-30*0.05/0.6) < 0.1,"Unit agent did not drive the tracks: %.3f" % rig.track_travel_left()): return
	print("TANK_TRACKS_TEST_PASSED"); quit()
