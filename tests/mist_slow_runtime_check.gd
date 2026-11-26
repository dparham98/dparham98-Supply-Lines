extends SceneTree
## Rendered (docs/MIST_AND_SLOW.md): a Grail Sentinel casting Mist (the arm raised with the burst of light), the Mist
## rolling over a squad a second later and thinning in its last second, then the Slow sigil under enemy infantry,
## with the Sentinel's card showing the Mist and Slow tiles.
const TestOutput = preload("res://tests/test_output.gd")
var game: Node3D
var hud: CanvasLayer
var rig: Node3D
func _initialize() -> void: call_deferred("run")
func shot(name: String) -> void:
	hud._process(0)
	for _frame in range(3): await process_frame
	await RenderingServer.frame_post_draw
	TestOutput.save_png(self,root.get_texture().get_image(),name+".png")
func look(point: Vector3, distance: float) -> void:
	rig.focus_position(point,distance)
	for _f in range(180): rig.advance_camera(1.0/60.0)
func spawn(id: String, team: String, point: Vector3) -> Node3D:
	var unit = load("res://scenes/gameplay/%s.tscn" % id).instantiate()
	unit.team = team
	game.get_node("Entities/Units").add_child(unit,true)
	unit.global_position = point
	unit.set_process(false)
	return unit
## Steps the caster until it casts, then lets the world run for `seconds` (the spell, the model and its burst).
func cast(sentinel: Node3D, kind: String, point: Vector3) -> void:
	sentinel.command_spell(kind,point)
	for i in range(600):
		sentinel._process(1.0/30)
		if sentinel.order == "idle": return
func run_for(seconds: float) -> void:
	var t := 0.0
	while t < seconds:
		await process_frame
		t += get_root().get_process_delta_time()
func run() -> void:
	root.size = Vector2i(1280,900)
	Engine.max_fps = 60
	game = load("res://scenes/maps/arthurian_skirmish.tscn").instantiate()
	root.add_child(game)
	await process_frame
	hud = game.get_node("Interface")
	rig = game.get_node("CameraRig")
	rig.set_process(false)
	for name in ["EnemyPlayer","KnightsPlayer"]:
		var ai = game.get_node_or_null(name)
		if ai != null: ai.set_process(false)
	var keep: Node3D = null
	for node in get_nodes_in_group("keeps"):
		if node.team == "player": keep = node
	var spot: Vector3 = keep.global_position+Vector3(40,0,30)
	var sentinel := spawn("grail_sentinel","player",spot+Vector3(-9,0,4))
	sentinel.med_reserve = 200
	for x in range(-2,3):
		for z in range(-1,2):
			spawn("round_table_marine","player",spot+Vector3(x*2.4,0,z*2.4))
	look(spot+Vector3(-4,0,2),26.0)
	for node in get_nodes_in_group("units"): node.set_selected(node == sentinel)
	# 1. The cast: the arm at the top with the burst, the Mist just billowing in.
	cast(sentinel,"mist",spot)
	await run_for(0.24)
	await shot("mist_slow_cast")
	# 2. The Mist rolling over the squad.
	await run_for(1.5)
	await shot("mist_slow_mist")
	# 3. Its last second, thinning.
	var mist = get_nodes_in_group("mists")[0]
	mist.seconds = 0.5
	await run_for(0.05)
	await shot("mist_slow_mist_thinning")
	await run_for(0.6)
	# 4. Slow under enemy infantry, a second in.
	Research.complete(game,"player",Research.SLOW)
	var target := spot+Vector3(0,0,-12)
	for i in range(5): spawn("infantry","enemy",target+Vector3((i-2)*1.8,0,(i%2)*1.5))
	look(target+Vector3(-3,0,4),26.0)
	cast(sentinel,"slow",target)
	await run_for(1.0)
	await shot("mist_slow_slow")
	game.queue_free()
	await process_frame
	print("MIST_SLOW_RUNTIME_CHECK_PASSED")
	quit(0)
