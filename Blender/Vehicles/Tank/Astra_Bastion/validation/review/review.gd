extends Node3D

const Paint := preload("res://scripts/components/team_paint.gd")
const SHOTS := [
	["front", "Front three-quarter", -153.0, 24.0, 5.5],
	["side", "Side", -92.0, 7.0, 6.15],
	["rear", "Rear three-quarter", -32.0, 25.0, 5.45],
	["teams", "Red and blue teams", -153.0, 25.0, 10.7],
	["original", "Accepted tank", -153.0, 24.0, 5.5],
	["gameplay", "Two Lakes · starting zoom", 0.0, 50.0, 72.0],
]
@onready var red: Node3D = $Red
@onready var blue: Node3D = $Blue
@onready var accepted: Node3D = $Accepted
@onready var camera: Camera3D = $Camera
var selected := 0
var swapped := false
var orbit := 0.0
var multiplier := 1.0


func _ready() -> void:
	for model in [red,blue,accepted]:
		model.sway_degrees = 0.0
		model.set_process(false)
	_show(0)
	var args := OS.get_cmdline_user_args()
	if args.has("--capture"):
		var directory := args[args.find("--capture") + 1]
		_capture.call_deferred(directory, args.has("--calibrate"))
	else:
		_paint()


func _paint() -> void:
	Paint.apply(red, "player" if swapped else "enemy")
	Paint.apply(blue, "enemy" if swapped else "player")


func _show(index: int) -> void:
	selected = posmod(index, SHOTS.size())
	var shot: Array = SHOTS[selected]
	var name_key: String = shot[0]
	var gameplay := name_key == "gameplay"
	$Terrain.visible = gameplay
	$Backdrop.visible = not gameplay
	$Fill.visible = not gameplay
	red.visible = name_key != "original"
	blue.visible = name_key in ["teams", "gameplay"]
	accepted.visible = name_key in ["original","gameplay"]
	var centre := Vector3(0,1.04,-0.72)
	var angle := deg_to_rad(float(shot[2]) + orbit)
	var pitch := deg_to_rad(float(shot[3]))
	var away := Vector3(sin(angle)*cos(pitch),sin(pitch),cos(angle)*cos(pitch))
	var right := Vector3(cos(angle),0,-sin(angle))
	red.position = Vector3.ZERO
	blue.position = Vector3.ZERO
	accepted.position = Vector3.ZERO
	for model in [red,blue,accepted]:
		model.rotation.y = 0
	if name_key == "teams":
		red.position = -right * 3.42
		blue.position = right * 3.42
	elif gameplay:
		accepted.position = Vector3(-12,0,0)
		blue.position = Vector3(12,0,0)
		for model in [red,blue,accepted]:
			model.rotation.y = deg_to_rad(143)
		centre = Vector3.ZERO
	if name_key == "side":
		centre = Vector3(0,0.97,-0.98)
	camera.position = centre + away * (110.0 if gameplay else 45.0)
	camera.look_at(centre, Vector3.UP)
	camera.size = float(shot[4]) * multiplier
	$Help/Legend.text = "%s     ·     ← → view     A D orbit     Wheel zoom     C swap paint     H hide legend" % shot[1]


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_LEFT, KEY_RIGHT, KEY_SPACE:
				orbit = 0.0
				multiplier = 1.0
				_show(selected + (-1 if event.keycode == KEY_LEFT else 1))
			KEY_A, KEY_D:
				orbit += -12.0 if event.keycode == KEY_A else 12.0
				_show(selected)
			KEY_C:
				swapped = not swapped
				_paint()
			KEY_H:
				$Help.visible = not $Help.visible
	if event is InputEventMouseButton and event.pressed:
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
			multiplier = clampf(multiplier * (0.90 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.11), 0.5, 3.0)
			_show(selected)


func _materials(model: Node3D) -> Dictionary:
	var state := {}
	for node in model.find_children("*","MeshInstance3D",true,false):
		var instance := node as MeshInstance3D
		if not instance.mesh:
			continue
		for i in instance.mesh.get_surface_count():
			var base := instance.mesh.surface_get_material(i)
			var active := instance.get_active_material(i)
			if not base or not active:
				continue
			var key := "%s/%d" % [model.get_path_to(node),i]
			state[key] = {"slot": base.resource_name, "id": active.get_instance_id()}
	return state


func _check_paint() -> Dictionary:
	var red_count := Paint.apply(red,"enemy")
	var blue_count := Paint.apply(blue,"player")
	if red_count <= 0 or blue_count != red_count:
		return {}
	var red_before := _materials(red)
	var blue_before := _materials(blue)
	Paint.apply(blue,"neutral")
	var blue_after := _materials(blue)
	if red_before != _materials(red):
		return {}
	var changed := 0
	var unpainted := 0
	for key in blue_before:
		if blue_before[key].slot == "team_color":
			var verified: bool = blue_before[key].id == Paint.paint_for("player").get_instance_id()
			verified = verified and red_before[key].id == Paint.paint_for("enemy").get_instance_id()
			verified = verified and blue_after[key].id == Paint.paint_for("neutral").get_instance_id()
			if not verified:
				return {}
			changed += 1
		else:
			if blue_before[key].id != blue_after[key].id:
				return {}
			unpainted += 1
	Paint.apply(blue,"player")
	return {"changed_team_surfaces": changed, "other_surfaces_unchanged": unpainted,
		"red_instance_unchanged_after_blue_repaint": true,
		"blue_restored": blue_before == _materials(blue)}


func _capture(directory: String, calibrate: bool) -> void:
	$Help.visible = false
	var paint := {} if calibrate else _check_paint()
	if not calibrate and (paint.is_empty() or not paint.blue_restored):
		push_error("Per-instance team paint review failed.")
		get_tree().quit(1)
		return
	var report := {"renderer":RenderingServer.get_current_rendering_method(),
		"version":Engine.get_version_info().string, "paint":paint,
		"camera":{"game_span_m":72.0,"game_pitch_deg":50,"game_yaw_deg":0,"game_distance_m":110},
		"frames":[]}
	if DirAccess.make_dir_recursive_absolute(directory) != OK:
		push_error("Could not make capture directory.")
		get_tree().quit(1)
		return
	for i in SHOTS.size():
		_show(i)
		for frame in 8:
			await RenderingServer.frame_post_draw
		var name_key: String = SHOTS[i][0]
		if get_viewport().get_texture().get_image().save_png(directory.path_join(name_key+".png")) != OK:
			push_error("Capture failed for "+name_key)
			get_tree().quit(1)
			return
		report.frames.append(name_key)
	var file := FileAccess.open(directory.path_join("review_checks.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  ")+"\n")
	file.close()
	print("BASTION_REVIEW_CAPTURED ",report)
	get_tree().quit()
