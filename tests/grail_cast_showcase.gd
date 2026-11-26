extends SceneTree
## Run with --fixed-fps 30 -s tests/grail_cast_showcase.gd to replay the three orders.
## --write-movie captures the same sequence for review.

func _initialize() -> void:
	call_deferred("run")

func frames(count: int) -> void:
	for i in range(count): await process_frame

func run() -> void:
	var game = load("res://scenes/maps/arthurian_skirmish.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.get_node("Interface").hide()
	var camera_rig = game.get_node("CameraRig")
	camera_rig.set_process(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var caster = game.get_node("Entities/Units/GrailSentinel")
	var patient = game.get_node("Entities/Units/RoundTableMarine")
	var enemy = preload("res://scenes/gameplay/grenadier.tscn").instantiate()
	enemy.team = "enemy"
	game.get_node("Entities/Units").add_child(enemy)
	for unit in get_nodes_in_group("units"):
		unit.set_process(false)
		unit.visible = unit in [caster, patient]
		unit.get_node("Status").hide()
	for ai_name in ["EnemyPlayer","KnightsPlayer"]:
		var ai = game.get_node_or_null(ai_name)
		if ai != null: ai.set_process(false)
	var spot: Vector3 = caster.global_position
	var aim := spot + Vector3(2.15,0,1.0)
	patient.global_position = aim
	enemy.global_position = aim
	caster.heal_autocast = false
	caster.set_process(true)
	caster._face(aim)
	patient._face(spot)
	enemy._face(spot)
	var camera: Camera3D = root.get_camera_3d()
	var normal_transform := camera.transform
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 3.7
	var focus := spot + Vector3(0.90,1.0,0.28)
	camera.global_position = focus + Vector3(0.5,2.6,7)
	camera.look_at(focus)
	var label := Label.new()
	label.position = Vector2(28,20)
	label.add_theme_font_size_override("font_size",32)
	label.add_theme_constant_override("outline_size",6)
	var overlay := CanvasLayer.new()
	overlay.layer = 100
	root.add_child(overlay)
	overlay.add_child(label)
	label.text = "Heal"
	patient.health = patient.max_health - 21
	await frames(12)
	caster.command_heal(patient)
	await frames(77)
	if patient.health <= patient.max_health - 21:
		push_error("The showcase patient did not receive Heal.")
		quit(1)
		return
	label.text = "Mist"
	caster.command_spell("mist",aim)
	await frames(68)
	for mist in get_nodes_in_group("mists"): mist.queue_free()
	patient.hide()
	enemy.show()
	enemy.get_node("Status").hide()
	Research.complete(game,"player",Research.SLOW)
	label.text = "Slow"
	caster.command_spell("slow",aim)
	await frames(73)
	if not is_equal_approx(enemy.speed_scale(),caster.spell_rules.slow_factor):
		push_error("The showcase target did not receive Slow.")
		quit(1)
		return
	# Replay from the ordinary RTS camera height to show the two area effects together.
	camera.transform = normal_transform
	camera_rig.focus_position(spot + Vector3(2,0,0),18.0)
	for i in range(180): camera_rig.advance_camera(1.0 / 60.0)
	patient.global_position = spot + Vector3(-3,0,2)
	patient.show()
	patient.health = patient.max_health - 10
	label.text = "Heal"
	caster.command_heal(patient)
	await frames(42)
	label.text = "Mist"
	caster.command_spell("mist",spot + Vector3(-5,0,0))
	await frames(36)
	label.text = "Slow"
	caster.command_spell("slow",aim)
	await frames(52)
	game.queue_free()
	overlay.queue_free()
	await process_frame
	print("GRAIL_CAST_SHOWCASE_PASSED")
	quit(0)
