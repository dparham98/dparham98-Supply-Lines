extends Node3D
## In this stationary yard the game track wrappers read the authored display states.
const Paint := preload("res://scripts/components/team_paint.gd")

## Frame, visible group, focus point, orthographic span, pitch and yaw.
const SHOTS := [
	["hero", "Yard", Vector3(29.4, 0.48, 8.7), 7.8, 31.0, 204.0],
	["yard", "Yard", Vector3(14.6, 0.0, 11.2), 72.0, 50.0, 0.0],
	["straight", "Straight", Vector3(0, 0.25, 2.4), 4.9, 29.0, -119.0],
	["curve", "Curve", Vector3(5.7, 0.1, 6.6), 14.8, 48.0, -16.0],
	["left", "Left", Vector3(4.7, 0.1, 7.2), 17.6, 47.0, 19.0],
	["right", "Right", Vector3(-4.7, 0.1, 7.2), 17.6, 47.0, -19.0],
	["new", "NewStraight", Vector3(0, 0.27, 2.4), 6.4, 29.0, -123.0],
	["old", "OldStraight", Vector3(0, 0.27, 2.4), 6.4, 29.0, -123.0],
]
var shot := 0


func register(_piece: Node3D) -> bool:
	return true


func unregister(_piece: Node3D) -> void:
	pass


func powered(piece: Node3D, team: String) -> bool:
	return team == "player" and piece.get_meta("review_power", "on") == "on"


func friendly_piece(piece: Node3D, team: String) -> bool:
	return team == "enemy" and piece.get_meta("review_power", "on") == "hostile"


func _ready() -> void:
	$Yard/LeftTurnout.set_route(1)
	$Left/Track.set_route(1)
	_place_on($Yard/CurveTrain, $Yard/Curve, 0, 11.0, "enemy")
	_place_on($Yard/MainTrain, $Yard/Inbound0, 0, 4.2, "player")
	_show(0)
	if "--capture" in OS.get_cmdline_user_args():
		_capture.call_deferred()


func _place_on(train: Node3D, track: Node3D, lane: int, front: float, team: String) -> void:
	var points := PackedVector3Array()
	var cumulative := PackedFloat32Array()
	var distance := 0.0
	for i in range(161):
		var offset: float = track.length(lane) * i / 160.0
		var point: Vector3 = track.point_at(offset, lane)
		if i > 0:
			distance += point.distance_to(points[i - 1])
		points.append(point)
		cumulative.append(distance)
	train.place({"points": points, "cum": cumulative, "total": distance, "start": 0.0}, front)
	Paint.apply(train, team)


func _show(index: int) -> void:
	shot = posmod(index, SHOTS.size())
	var view: Array = SHOTS[shot]
	for item in [$Yard, $Straight, $Curve, $Left, $Right, $NewStraight, $OldStraight]:
		item.visible = String(item.name) == view[1]
	var gameplay_ground: bool = view[0] == "yard"
	$Ground.visible = not gameplay_ground
	$GameplayGround.visible = gameplay_ground
	$Fill.visible = not gameplay_ground
	var pitch := deg_to_rad(float(view[4]))
	var yaw := deg_to_rad(float(view[5]))
	var centre: Vector3 = view[2]
	var away := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch))
	var camera: Camera3D = $Camera
	var distance := 110.0 if gameplay_ground else 62.0
	camera.position = centre + away * distance
	camera.look_at(centre, Vector3.UP)
	camera.size = view[3]


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_RIGHT, KEY_SPACE:
				_show(shot + 1)
			KEY_LEFT:
				_show(shot - 1)


func _capture() -> void:
	var args := OS.get_cmdline_user_args()
	var destination := args[args.find("--capture") + 1]
	if DirAccess.make_dir_recursive_absolute(destination) != OK:
		get_tree().quit(1)
		return
	await get_tree().create_timer(0.40).timeout
	for i in SHOTS.size():
		_show(i)
		for frame in 5:
			await RenderingServer.frame_post_draw
		var path := destination.path_join(str(SHOTS[i][0]) + ".png")
		if get_viewport().get_texture().get_image().save_png(path) != OK:
			get_tree().quit(1)
			return
	get_tree().quit()
