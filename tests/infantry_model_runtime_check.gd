extends SceneTree
# Rendered check: the Infantry's rigged model renders in the skirmish, is picked by selection bounds,
# and each clip poses the rig. Saves infantry_idle, infantry_run, infantry_hack and infantry_shoot.
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
func pose(player: AnimationPlayer, clip: String, time: float) -> void:
	player.play(clip); player.seek(time,true); player.pause()
	for frame in range(3): await process_frame
func run() -> void:
	root.size = Vector2i(1280,900)
	game = load("res://scenes/maps/resource_skirmish.tscn").instantiate()
	root.add_child(game)
	for frame in range(3): await process_frame
	game.set_process(false)
	for unit in get_nodes_in_group("units"): unit.set_process(false)
	var unit = load("res://scenes/gameplay/infantry.tscn").instantiate()
	unit.position = game.depot.global_position+Vector3(-8,0,10)
	game.get_node("Entities/Units").add_child(unit); unit.set_process(false)
	for frame in range(3): await process_frame
	var model = unit.get_node("Visuals/Model")
	if not check(model.scene_file_path == "res://scenes/models/infantry_model.tscn","Infantry still uses the prototype"): return
	var player: AnimationPlayer = model.player
	if not check(player != null and player.has_animation("Hack"),"Infantry clips missing"): return
	model.set_process(false)
	var rig = game.get_node("CameraRig")
	rig.set_process(false)
	rig.focus_position(unit.global_position+Vector3(0,0.9,0),9)
	for frame in range(180): rig.advance_camera(1.0/60)
	var screen: Vector2 = rig.camera.unproject_position(unit.selection_point())
	if not check(Bounds.hit_distance(unit,rig.camera,screen) < INF,"Infantry model not pickable at its selection point"): return
	var rect := Bounds.screen_rect(unit,rig.camera)
	if not check(rect.size.y > 60 and rect.size.y < 700,"Infantry screen height odd: %s" % rect): return
	var arm: int = model.skeleton.find_bone("forearm.R")
	await pose(player,"Rest",0.0)
	var rest_pose: Transform3D = model.skeleton.get_bone_global_pose(arm)
	await shot("infantry_idle")
	await pose(player,"Run",0.17)
	await shot("infantry_run")
	await pose(player,"Hack",0.5)
	var hack_pose: Transform3D = model.skeleton.get_bone_global_pose(arm)
	if not check(rest_pose.origin.distance_to(hack_pose.origin) > 0.05,"Hack does not move the saw arm"): return
	await shot("infantry_hack")
	await pose(player,"Shoot",0.14)
	model._update_flash_light()
	if not check(model.flash_light.visible,"Muzzle light should be on at the shot"): return
	await shot("infantry_shoot")
	print("INFANTRY_MODEL_RUNTIME_CHECK_PASSED"); quit(TestOutput.exit_code())
