extends Node3D

const Paint := preload("res://scripts/components/team_paint.gd")
const Shell := preload("res://scenes/gameplay/tank_shell.tscn")
const INSIDE := Vector3(-5.3, 0, 2.0)
const OUTSIDE := Vector3(-12.2, 0, 2.0)
@onready var model: Node3D = $Bastion/Visuals/Model
@onready var auxiliary: Node = $Bastion/CloseDefense
@onready var near_unit: Node3D = $NearUnit
@onready var far_unit: Node3D = $FarUnit
@onready var camera: Camera3D = $Camera
var close_view := false
var cooldown := 1.0
var aux_shots := 0
var main_shots := 0
var active_range := true


func _ready() -> void:
	model.sway_degrees = 0.0
	Paint.apply(model, "enemy")
	Paint.apply(near_unit, "player")
	Paint.apply(far_unit, "player")
	auxiliary.fired.connect(_count_secondary)
	near_unit.position = INSIDE
	_set_camera()
	var args := OS.get_cmdline_user_args()
	if "--capture" in args:
		_capture.call_deferred(args[args.find("--capture") + 1])


func _process(delta: float) -> void:
	# The main gun is ordered onto the distant range target. The roof gun picks its own target.
	model.aim_at(far_unit.global_position)
	cooldown -= delta
	if model.on_target() and cooldown <= 0:
		cooldown = 2.0
		main_shots += 1
		var target: Vector3 = far_unit.global_position + Vector3.UP * .88
		var projectile := show_shot(model.muzzle_position(), target, "enemy", Shell)
		projectile.on_impact = far_unit.take_damage.bind(12)
		model.fire()
	var metres := Vector2(near_unit.position.x,near_unit.position.z).length()
	$HUD/Status.text = "Roof turret   %d shots     ·     Near target   %.1f m\nMain cannon   %d shots" % [aux_shots,metres,main_shots]


func _count_secondary(_target: Node3D, _muzzle: Vector3, _end: Vector3) -> void:
	aux_shots += 1


func show_shot(start: Vector3, end: Vector3, team: String, projectile: PackedScene = null) -> Node3D:
	if projectile == null:
		push_error("A range weapon fired without selecting its projectile scene.")
		return null
	var shot: Node3D = projectile.instantiate()
	add_child(shot)
	shot.configure(start,end,team)
	return shot


func _set_camera() -> void:
	var centre := Vector3(0,1.2,-.45) if close_view else Vector3(-1.5,.5,-6.5)
	var away := Vector3(-.51,.53,-1) if close_view else Vector3(-.87,1.24,-.16)
	camera.position = centre + away.normalized()*55
	camera.look_at(centre,Vector3.UP)
	camera.size = 5.5 if close_view else 18.0


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_TAB:
				close_view = not close_view
				_set_camera()
			KEY_SPACE:
				active_range = not active_range
				near_unit.position = INSIDE if active_range else OUTSIDE
			KEY_H:
				$HUD.visible = not $HUD.visible
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var point = Plane(Vector3.UP,0).intersects_ray(camera.project_ray_origin(event.position),
				camera.project_ray_normal(event.position))
		if point is Vector3 and point.length() >= 3.8 and point.length() < 27.0:
			near_unit.global_position = point
			active_range = point.length() <= auxiliary.attack_range


func _capture(directory: String) -> void:
	# Wait for both live weapons to engage before taking a frame.
	var deadline := Time.get_ticks_msec() + 15000
	while (aux_shots < 2 or main_shots < 1) and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	if aux_shots < 2 or main_shots < 1:
		push_error("Range capture did not observe independent weapon fire")
		get_tree().quit(1)
		return
	$HUD.visible = false
	close_view = true
	_set_camera()
	await auxiliary.fired
	for i in 3:
		await RenderingServer.frame_post_draw
	var error := get_viewport().get_texture().get_image().save_png(directory.path_join("turret.png"))
	# Move the near unit through two bearings while the main weapon keeps its far target.
	if error == OK:
		for frame in 42:
			var angle := deg_to_rad(-68.0*cos(TAU*frame/42.0))
			near_unit.position = Vector3(sin(angle)*5.7,0,cos(angle)*5.7)
			for step in 5:
				await RenderingServer.frame_post_draw
			var path := directory.path_join("yaw_%02d.png" % frame)
			error = get_viewport().get_texture().get_image().save_png(path)
			if error != OK:
				break
	near_unit.position = INSIDE
	if error == OK:
		# A side view of the actual flight, between main-cannon shots.
		var centre := Vector3(-2.35,1.55,.5)
		camera.position = centre + Vector3(-.08,.36,-1).normalized()*50
		camera.look_at(centre,Vector3.UP)
		camera.size = 4.95
		cooldown = 2.5
		await auxiliary.fired
		for frame in 37:
			for step in 2:
				await RenderingServer.frame_post_draw
			error = get_viewport().get_texture().get_image().save_png(directory.path_join("bullet_%02d.png" % frame))
			if error != OK:
				break
	close_view = false
	_set_camera()
	$HUD.visible = true
	for i in 6:
		await RenderingServer.frame_post_draw
	if error == OK:
		error = get_viewport().get_texture().get_image().save_png(directory.path_join("range.png"))
	print("LIVE_RANGE main=",main_shots," auxiliary=",aux_shots)
	get_tree().quit(0 if error == OK else 1)
