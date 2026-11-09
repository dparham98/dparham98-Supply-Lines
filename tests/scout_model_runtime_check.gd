extends SceneTree
# Rendered check: the Scout's rigged model renders in the skirmish and is picked by selection bounds.
# Saves scout_idle, scout_run, scout_windup, scout_flash, scout_flash_game, scout_shell and close views.
const TestOutput = preload("res://tests/test_output.gd")
const Bounds = preload("res://scripts/units/selection_bounds.gd")
var game: Node3D
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> bool:
	if value: return true
	push_error(message); quit(1); return false
func shot(name: String) -> void:
	for frame in range(4): await process_frame
	root.get_texture().get_image().save_png(TestOutput.path(name+".png"))
func pose(model: Node3D, clip: String, time: float) -> void:
	model.player.play(clip); model.player.seek(time,true); model.player.pause()
	model._update_flash_light()
	for frame in range(3): await process_frame
func run() -> void:
	root.size = Vector2i(1280,900)
	game = load("res://scenes/maps/resource_skirmish.tscn").instantiate()
	root.add_child(game)
	for frame in range(3): await process_frame
	game.set_process(false)
	for unit in get_nodes_in_group("units"): unit.set_process(false)
	var unit = load("res://scenes/gameplay/scout.tscn").instantiate()
	unit.position = game.depot.global_position+Vector3(-8,0,10)
	game.get_node("Entities/Units").add_child(unit); unit.set_process(false)
	for frame in range(3): await process_frame
	var model = unit.get_node("Visuals/Model")
	if not check(model.scene_file_path == "res://scenes/models/scout_model.tscn","Scout still uses the prototype"): return
	model.set_process(false)
	unit.get_node("Visuals").rotation.y = deg_to_rad(-150)
	var rig = game.get_node("CameraRig")
	rig.set_process(false)
	rig.focus_position(unit.global_position+Vector3(0,0.9,0),5)
	for frame in range(180): rig.advance_camera(1.0/60)
	var screen: Vector2 = rig.camera.unproject_position(unit.selection_point())
	if not check(Bounds.hit_distance(unit,rig.camera,screen) < INF,"Scout model not pickable at its selection point"): return
	await pose(model,"idle",0.0)
	await shot("scout_idle")
	await pose(model,"run",0.4)
	await shot("scout_run")
	await pose(model,"shoot",0.25)
	await shot("scout_windup")
	await pose(model,"shoot",model.shot_lead_time)
	if not check(model.flash_light.visible and model.flash_light.light_energy > 1.0,"Muzzle light did not fire"): return
	await shot("scout_flash")
	await pose(model,"shoot",1.0)
	if not check(not model.flash_light.visible,"Muzzle light stayed on"): return
	await shot("scout_shell")
	# Close look at the face, unlit and lit, from in front of the gun.
	var close := Camera3D.new()
	close.fov = 32
	game.add_child(close)
	var front: Vector3 = -unit.get_node("Visuals").global_transform.basis.z
	close.global_position = unit.global_position+front*3.4+Vector3.UP*1.75+front.cross(Vector3.UP)*0.5
	close.look_at(unit.global_position+Vector3.UP*1.05)
	close.make_current()
	await pose(model,"shoot",0.25)
	await shot("scout_close_windup")
	await pose(model,"shoot",model.shot_lead_time)
	await shot("scout_close_flash")
	await pose(model,"run",0.4)
	await shot("scout_close_run")
	rig.camera.make_current()
	close.queue_free()
	# At normal play distance, flash on.
	rig.focus_position(unit.global_position,40)
	for frame in range(180): rig.advance_camera(1.0/60)
	await pose(model,"shoot",model.shot_lead_time)
	await shot("scout_flash_game")
	print("SCOUT_MODEL_RUNTIME_CHECK_PASSED"); quit(TestOutput.exit_code())
