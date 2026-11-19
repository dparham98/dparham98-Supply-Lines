extends SceneTree
# Rendered check: the Bastion's roof gun is easy to see when it fires (docs/BASTION_TANK.md). Each shot lights a
# flash at its muzzle, the round flies plain, with no tracer, and a small burst shows where it lands.
# Saves roof_gun_flash, roof_gun_round and roof_gun_hit.
const TestOutput = preload("res://tests/test_output.gd")
var game: Node3D
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> bool:
	if value: return true
	push_error(message); quit(1); return false
func shot(name: String) -> void:
	await process_frame
	root.get_texture().get_image().save_png(TestOutput.path(name+".png"))
func run() -> void:
	root.size = Vector2i(1280,900)
	game = load("res://scenes/maps/resource_skirmish.tscn").instantiate()
	root.add_child(game)
	for frame in range(3): await process_frame
	game.set_process(false)
	for unit in get_nodes_in_group("units"): unit.set_process(false)
	var units: Node = game.get_node("Entities/Units")
	var tank = load("res://scenes/gameplay/tank.tscn").instantiate()
	tank.position = game.depot.global_position+Vector3(-8,0,14)
	units.add_child(tank); tank.set_process(false)
	var foe = load("res://scenes/gameplay/hostile.tscn").instantiate()
	foe.team = "enemy"
	foe.position = tank.position+Vector3(7,0,-2)
	units.add_child(foe); foe.set_process(false)
	var roof: Node = tank.get_node("CloseDefense")
	roof.set_process(false)
	var rig = game.get_node("CameraRig")
	rig.set_process(false)
	rig.focus_position(tank.global_position+Vector3(3,0,-1),20)
	for frame in range(180): rig.advance_camera(1.0/60)
	var flash = tank.get_node("Visuals/Model").find_child("AuxMuzzleFx",true,false)
	if not check(flash != null,"The roof gun has no muzzle flash"): return
	# Turn onto the foe, then catch the frame the round leaves the muzzle.
	var fired := []
	roof.fired.connect(func(_t, _o, _e): fired.append(true))
	for frame in range(120):
		if not fired.is_empty(): break
		roof._process(1.0/60)
	if not check(not fired.is_empty(),"The roof gun did not fire"): return
	if not check(flash.player.is_playing() and flash.flash.scale.x > 0.01,"The muzzle flash should be lit as the round leaves"): return
	await shot("roof_gun_flash")
	var bullets := root.find_children("*","",true,false).filter(func(n): return n.scene_file_path == "res://scenes/gameplay/aux_bullet.tscn")
	if not check(not bullets.is_empty(),"No round in flight"): return
	var round: Node3D = bullets[0]
	if not check(round.find_children("*trail*","",true,false).is_empty(),"The round should have no tracer"): return
	for frame in range(10): round._process(1.0/60)
	await shot("roof_gun_round")
	var health: int = foe.health
	for frame in range(120):
		if not is_instance_valid(round) or round.is_queued_for_deletion(): break
		round._process(1.0/60)
	var bursts := root.find_children("*","",true,false).filter(func(n): return n.scene_file_path == "res://scenes/gameplay/aux_bullet_impact.tscn")
	if not check(foe.health < health and bursts.size() == 1,"The hit should hurt and show a burst: %d bursts" % bursts.size()): return
	if not check(bursts[0].global_position.distance_to(foe.global_position) < 2.0,"The burst should be on the target"): return
	# The frame the burst is at its biggest.
	var peak := 0.0
	var best := 0.0
	for frame in range(40):
		var t := frame/60.0
		bursts[0].player.seek(t,true)
		if bursts[0].flash.scale.x > best: best = bursts[0].flash.scale.x; peak = t
	bursts[0].player.seek(peak,true)
	bursts[0].player.pause()
	await shot("roof_gun_hit")
	print("ROOF_GUN_RUNTIME_CHECK_PASSED")
	quit(0)
