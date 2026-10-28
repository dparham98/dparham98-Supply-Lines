@tool
extends Node3D
## Root = ground focus; YawPivot = orbit; PitchPivot = tilt; Camera = projection.
enum StartupFocus { AUTHORED_POSITION, HEADQUARTERS, WHOLE_MAP }
@export_category("Starting View")
@export var startup_focus: StartupFocus = StartupFocus.HEADQUARTERS
@export_range(20, 300, 1) var default_zoom: float = 95.0
@export_range(30, 75, 1) var pitch_degrees: float = 50.0
@export_range(-180, 180, 1) var yaw_degrees: float = 0.0
@export_range(40, 300, 1) var minimum_camera_distance: float = 110.0
@export_category("Movement")
@export_range(5, 150, 1) var pan_speed: float = 65.0
@export_range(1, 5, 0.1) var fast_pan_multiplier: float = 2.5
@export_range(1, 30, 0.5) var pan_response: float = 12.0
@export_range(1, 30, 0.5) var movement_smoothing: float = 12.0
@export var edge_pan_enabled: bool = true
## Entering this band acts like holding the corresponding arrow key.
@export_range(4, 120, 1) var edge_margin: float = 64.0
@export_category("Zoom And Orbit")
@export_range(5, 80, 1) var min_zoom: float = 20.0
@export_range(100, 900, 1) var max_zoom: float = 480.0
@export_range(1.02, 1.4, 0.01) var wheel_zoom_factor: float = 1.15
@export_range(1, 30, 0.5) var zoom_smoothing: float = 14.0
@export var zoom_to_cursor: bool = true
@export_range(15, 180, 1) var rotation_speed_degrees: float = 75.0
@export_range(1, 30, 0.5) var rotation_smoothing: float = 14.0
@export_category("Map And Overview")
@export var map_bounds := Rect2(-250, -250, 500, 500)
@export var constrain_view_to_map: bool = true
@export_range(40, 80, 1) var overview_pitch_degrees: float = 60.0
@export_range(0, 0.3, 0.01) var overview_padding: float = 0.08
@export_category("Editor Preview")
@export_range(20, 600, 1) var preview_zoom: float = 140.0
@onready var yaw_pivot: Node3D = $YawPivot
@onready var pitch_pivot: Node3D = $YawPivot/PitchPivot
@onready var camera: Camera3D = $YawPivot/PitchPivot/Camera
var overview := false
var _focus_target := Vector3.ZERO
var _zoom_target := 95.0
var _yaw := 0.0
var _yaw_target := 0.0
var _pitch := 50.0
var _pitch_target := 50.0
var _pan_velocity := Vector3.ZERO
var _return_view: Dictionary = {}
var _dragging := false
var _drag_anchor := Vector3.ZERO
var _zoom_anchor_active := false
var _zoom_anchor_world := Vector3.ZERO
var _zoom_anchor_screen := Vector2.ZERO
var _editor_signature := Vector4(-1, -1, -1, -1)

func _ready() -> void:
	if Engine.is_editor_hint():
		_apply_editor_preview()
		return
	set_view(global_position, default_zoom, yaw_degrees, pitch_degrees)
	get_viewport().size_changed.connect(_on_viewport_resized)
	if startup_focus == StartupFocus.HEADQUARTERS: call_deferred("focus_hq")
	elif startup_focus == StartupFocus.WHOLE_MAP: call_deferred("show_overview")

func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		_apply_editor_preview()
		return
	if get_window().has_focus():
		var pan := Input.get_vector("camera_pan_left", "camera_pan_right", "camera_pan_forward", "camera_pan_back")
		var keyboard_panning := pan != Vector2.ZERO
		# Keyboard takes precedence so touching an edge never doubles its speed.
		if not keyboard_panning and edge_pan_enabled and not _dragging and not _pointer_blocks_edge_pan():
			pan = edge_pan_vector(get_viewport().get_mouse_position(), get_viewport().get_visible_rect().size)
		if _dragging: pan = Vector2.ZERO
		apply_navigation(pan.limit_length(), Input.get_axis("camera_rotate_left", "camera_rotate_right"), Input.is_action_pressed("camera_fast_pan"), delta)
	else:
		cancel_pointer_navigation()
		_pan_velocity = Vector3.ZERO
	advance_camera(delta)

func _input(event: InputEvent) -> void:
	# Finish a gesture we already own even if the pointer moves over a UI panel.
	if Engine.is_editor_hint() or not _dragging: return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_MIDDLE and not event.pressed:
		cancel_pointer_navigation()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion:
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE): drag_to(event.position)
		else: cancel_pointer_navigation()
		get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if Engine.is_editor_hint(): return
	if event is InputEventKey and event.echo: return
	if event.is_action_pressed("camera_overview"):
		if overview: return_from_overview()
		else: show_overview()
	elif event.is_action_pressed("camera_focus_hq"): focus_hq()
	elif event.is_action_pressed("camera_focus_selection"): focus_selection()
	elif event.is_action_pressed("camera_zoom_in") or event.is_action_pressed("camera_zoom_out"):
		var ticks := maxf(0.1, event.factor) if event is InputEventMouseButton else 1.0
		zoom_at_screen_position(get_viewport().get_mouse_position(), ticks if event.is_action_pressed("camera_zoom_in") else -ticks)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_MIDDLE:
		if event.pressed: begin_drag(event.position)
		else: cancel_pointer_navigation()
	elif event is InputEventMouseMotion and _dragging:
		if not Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE): cancel_pointer_navigation()
		else: drag_to(event.position)
	else: return
	get_viewport().set_input_as_handled()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT: cancel_pointer_navigation()

func _pointer_over_ui() -> bool:
	return get_viewport().gui_get_hovered_control() != null

func _pointer_blocks_edge_pan() -> bool:
	# Read-only overlays can occupy an edge without creating a dead strip.
	var control := get_viewport().gui_get_hovered_control()
	while control != null:
		if control.get_meta("edge_pan_passthrough", false): return false
		control = control.get_parent_control()
	return _pointer_over_ui()

func edge_pan_vector(mouse: Vector2, viewport_size: Vector2) -> Vector2:
	if viewport_size.x <= 0 or viewport_size.y <= 0 or not Rect2(Vector2.ZERO, viewport_size).has_point(mouse): return Vector2.ZERO
	var direction := Vector2.ZERO
	var margin := maxf(1, minf(edge_margin, minf(viewport_size.x, viewport_size.y) * 0.25))
	if mouse.x < margin: direction.x = -1
	elif mouse.x > viewport_size.x - margin: direction.x = 1
	if mouse.y < margin: direction.y = -1
	elif mouse.y > viewport_size.y - margin: direction.y = 1
	return direction.normalized()

func apply_navigation(pan: Vector2, rotation: float, fast: bool, delta: float) -> void:
	if overview and (pan != Vector2.ZERO or rotation != 0):
		overview = false
		# A map-sized footprint cannot pan; return to navigation scale first.
		_zoom_target = clampf(default_zoom, min_zoom, max_zoom)
		_pitch_target = pitch_degrees
	if pan != Vector2.ZERO or rotation != 0: _zoom_anchor_active = false
	var basis_ := Basis(Vector3.UP, _yaw)
	var speed := pan_speed * clampf(camera.size / default_zoom, 0.25, 5.0)
	if fast: speed *= fast_pan_multiplier
	var desired := (basis_.x * pan.x + basis_.z * pan.y) * speed
	var response := maxf(pan_response, 0.01)
	var decay := exp(-response * delta)
	# Exact integration of the acceleration response keeps pan distance frame-rate independent.
	_focus_target += desired * delta + (_pan_velocity - desired) * (1 - decay) / response
	_pan_velocity = desired + (_pan_velocity - desired) * decay
	_focus_target.y = 0
	_yaw_target = wrapf(_yaw_target + rotation * deg_to_rad(rotation_speed_degrees) * delta, -PI, PI)

func set_view(focus: Vector3, zoom: float, yaw: float, pitch: float) -> void:
	overview = false
	_focus_target = Vector3(focus.x, 0, focus.z)
	_zoom_target = clampf(zoom, min_zoom, max_zoom)
	_yaw = deg_to_rad(yaw)
	_yaw_target = _yaw
	_pitch = clampf(pitch, 30, 80)
	_pitch_target = _pitch
	_pan_velocity = Vector3.ZERO
	cancel_pointer_navigation()
	global_position = _focus_target
	camera.size = _zoom_target
	_apply_pose()
	_focus_target = _clamp_focus(_focus_target, camera.size, _yaw, _pitch)
	global_position = _focus_target

func advance_camera(delta: float) -> void:
	_yaw = lerp_angle(_yaw, _yaw_target, 1 - exp(-rotation_smoothing * delta))
	_pitch = lerpf(_pitch, _pitch_target, 1 - exp(-rotation_smoothing * delta))
	camera.size = lerpf(camera.size, _zoom_target, 1 - exp(-zoom_smoothing * delta))
	_apply_pose()
	if _zoom_anchor_active:
		var after = ground_point(_zoom_anchor_screen)
		if after != null:
			var correction: Vector3 = _zoom_anchor_world - after
			global_position += correction
			_focus_target += correction
		if absf(camera.size - _zoom_target) < 0.01: _zoom_anchor_active = false
	_focus_target = _clamp_focus(_focus_target, _zoom_target, _yaw_target, _pitch_target)
	global_position = global_position.lerp(_focus_target, 1 - exp(-movement_smoothing * delta))
	global_position = _clamp_focus(global_position, camera.size, _yaw, _pitch)
	_apply_pose()

func _apply_pose() -> void:
	yaw_pivot.rotation = Vector3(0, _yaw, 0)
	pitch_pivot.rotation = Vector3(-deg_to_rad(_pitch), 0, 0)
	var angle := deg_to_rad(_pitch)
	# Keep the entire orthographic near plane above terrain, including at overview zoom.
	var distance := maxf(minimum_camera_distance, (camera.size * 0.5 * cos(angle) + 30) / sin(angle))
	camera.position = Vector3(0, 0, distance)
	camera.rotation = Vector3.ZERO
	camera.force_update_transform()

func _aspect() -> float:
	var viewport_size := get_viewport().get_visible_rect().size
	return viewport_size.x / maxf(1, viewport_size.y)

func _clamp_focus(focus: Vector3, zoom: float, yaw: float, pitch: float) -> Vector3:
	if not constrain_view_to_map: return Vector3(focus.x, 0, focus.z)
	var half_width := zoom * 0.5 * _aspect()
	var half_depth := zoom * 0.5 / sin(deg_to_rad(pitch))
	var x := absf(cos(yaw)) * half_width + absf(sin(yaw)) * half_depth
	var z := absf(sin(yaw)) * half_width + absf(cos(yaw)) * half_depth
	var center := map_bounds.get_center()
	return Vector3(center.x if x * 2 >= map_bounds.size.x else clampf(focus.x, map_bounds.position.x + x, map_bounds.end.x - x), 0, center.y if z * 2 >= map_bounds.size.y else clampf(focus.z, map_bounds.position.y + z, map_bounds.end.y - z))

func ground_point(screen_position: Vector2) -> Variant:
	return Plane(Vector3.UP, 0).intersects_ray(camera.project_ray_origin(screen_position), camera.project_ray_normal(screen_position))

func zoom_at_screen_position(screen_position: Vector2, ticks: float) -> void:
	overview = false
	_pan_velocity = Vector3.ZERO
	_focus_target = global_position
	var anchor = ground_point(screen_position)
	_zoom_anchor_active = zoom_to_cursor and anchor != null
	if _zoom_anchor_active:
		_zoom_anchor_screen = screen_position
		_zoom_anchor_world = anchor
	_zoom_target = clampf(_zoom_target / pow(wheel_zoom_factor, ticks), min_zoom, max_zoom)

func begin_drag(screen_position: Vector2) -> void:
	var anchor = ground_point(screen_position)
	if anchor == null: return
	overview = false
	_dragging = true
	_drag_anchor = anchor
	_zoom_anchor_active = false
	_pan_velocity = Vector3.ZERO
	_focus_target = global_position

func drag_to(screen_position: Vector2) -> void:
	if not _dragging: return
	var point = ground_point(screen_position)
	if point == null: return
	_focus_target = _clamp_focus(global_position + _drag_anchor - point, camera.size, _yaw, _pitch)
	global_position = _focus_target
	_apply_pose()

func cancel_pointer_navigation() -> void:
	_dragging = false
	_zoom_anchor_active = false

func focus_position(point: Vector3, zoom: float = -1) -> void:
	overview = false
	cancel_pointer_navigation()
	_pan_velocity = Vector3.ZERO
	_focus_target = Vector3(point.x, 0, point.z)
	if zoom > 0: _zoom_target = clampf(zoom, min_zoom, max_zoom)
	_pitch_target = pitch_degrees

func focus_hq() -> void:
	var hq := get_tree().get_first_node_in_group("headquarters") as Node3D
	focus_position(hq.global_position if hq else Vector3.ZERO, default_zoom)

func focus_selection() -> void:
	var targets: Array[Vector3] = []
	for unit in get_tree().get_nodes_in_group("units"):
		if unit.get("is_selected") == true and unit.get("team") == "player": targets.append(unit.global_position)
	if targets.is_empty(): return
	var center := Vector3.ZERO
	var minimum: Vector3 = targets[0]
	var maximum: Vector3 = targets[0]
	for point in targets: center += point
	center /= targets.size()
	for point in targets:
		minimum = minimum.min(point)
		maximum = maximum.max(point)
	var span := maximum - minimum
	var width := absf(cos(_yaw_target)) * span.x + absf(sin(_yaw_target)) * span.z
	var depth := absf(sin(_yaw_target)) * span.x + absf(cos(_yaw_target)) * span.z
	focus_position(center, maxf(default_zoom, maxf(width / _aspect(), depth * sin(deg_to_rad(pitch_degrees))) * 1.3))

func overview_zoom() -> float:
	var vertical := map_bounds.size.y * sin(deg_to_rad(overview_pitch_degrees))
	return maxf(vertical, map_bounds.size.x / _aspect()) * (1 + overview_padding)

func show_overview() -> void:
	if not overview: _return_view = {"focus": _focus_target, "zoom": _zoom_target, "yaw": _yaw_target, "pitch": _pitch_target}
	overview = true
	cancel_pointer_navigation()
	_pan_velocity = Vector3.ZERO
	var center := map_bounds.get_center()
	_focus_target = Vector3(center.x, 0, center.y)
	_zoom_target = overview_zoom()
	_yaw_target = 0
	_pitch_target = overview_pitch_degrees

func return_from_overview() -> void:
	if not overview: return
	overview = false
	cancel_pointer_navigation()
	_pan_velocity = Vector3.ZERO
	if _return_view.is_empty():
		focus_hq()
		return
	_focus_target = _return_view["focus"]
	_zoom_target = _return_view["zoom"]
	_yaw_target = _return_view["yaw"]
	_pitch_target = _return_view["pitch"]

func _on_viewport_resized() -> void:
	cancel_pointer_navigation()
	if overview: _zoom_target = overview_zoom()

func _apply_editor_preview() -> void:
	if camera == null: return
	var signature := Vector4(preview_zoom, pitch_degrees, yaw_degrees, minimum_camera_distance)
	if signature == _editor_signature: return
	_editor_signature = signature
	_yaw = deg_to_rad(yaw_degrees)
	_pitch = pitch_degrees
	camera.size = preview_zoom
	_apply_pose()
