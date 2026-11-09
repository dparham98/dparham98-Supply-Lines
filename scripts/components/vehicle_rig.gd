extends Node3D
## Rigid vehicle articulation for an authored model (scenes/models/cargo_truck_model.tscn): wheels
## roll with ground speed, the front wheels steer into turns, the cargo lid and rear ramp open while
## the vehicle is deployed or transferring, and the cargo indicator rises when something is aboard.
## The owner calls set_drive() every frame it moves, set_hatches() and set_load() when they change.
## Nothing here is created at runtime: every part is a node of the imported model.
@export var wheel_paths: Array[NodePath] = []
@export var steer_paths: Array[NodePath] = []
@export var lid_path: NodePath
@export var ramp_path: NodePath
@export var indicator_path: NodePath
## Wheel radius in the model's own units (before the wrapper's scale).
@export_range(0.05,5,0.01) var wheel_radius := 0.65
@export_range(0,80,1) var steer_max_degrees := 30.0
## Turn rate (deg/s of heading change) that steers the wheels fully.
@export_range(1,720,1) var steer_full_rate := 90.0
@export_range(0,180,1) var lid_open_degrees := 60.0
@export_range(-180,0,1) var ramp_open_degrees := -125.0
@export_range(0,2,0.01) var indicator_raise := 0.32
@export_range(10,720,1) var hatch_speed_degrees := 120.0
@export_range(0.1,20,0.1) var steer_speed := 6.0
## How long the wheels hold a steer after a heading change; RTS turns happen in a frame or two.
@export_range(0,2,0.05) var steer_hold := 0.4
var _speed := 0.0
var _turn := 0.0
var _drive_frame := -2
var _open := false
var _load := 0.0
var _roll := 0.0
var _steer := 0.0
var _steer_goal := 0.0
var _steer_hold_left := 0.0
var _lid := 0.0
var _ramp := 0.0
var _indicator_rest := Vector3.ZERO
var _wheels: Array[Node3D] = []
var _steers: Array[Node3D] = []
@onready var lid: Node3D = get_node_or_null(lid_path)
@onready var ramp: Node3D = get_node_or_null(ramp_path)
@onready var indicator: Node3D = get_node_or_null(indicator_path)
func _ready() -> void:
	for path in wheel_paths:
		var wheel := get_node_or_null(path)
		if wheel: _wheels.append(wheel)
	for path in steer_paths:
		var pivot := get_node_or_null(path)
		if pivot: _steers.append(pivot)
	if indicator: _indicator_rest = indicator.position
## Report this frame's travel: ground speed (m/s) and heading change (radians this frame, positive
## turning left). Lapses after a frame without a call.
func set_drive(speed: float, turn: float, delta: float) -> void:
	_speed = speed
	_turn = turn/delta if delta > 0.0 else 0.0
	_drive_frame = Engine.get_process_frames()
## Open the lid and ramp (deployed, loading or unloading) or close them for the road.
func set_hatches(open: bool) -> void:
	_open = open
## Fraction of cargo space in use; anything aboard raises the indicator.
func set_load(fraction: float) -> void:
	_load = clampf(fraction,0.0,1.0)
func driving() -> bool:
	return Engine.get_process_frames()-_drive_frame <= 1 and _speed > 0.0
func hatches_open() -> bool: return _open
func wheel_roll() -> float: return _roll
func steer_angle() -> float: return _steer
func lid_angle() -> float: return _lid
func ramp_angle() -> float: return _ramp
func _process(delta: float) -> void:
	# Wheels: roll by the ground distance covered; the wrapper's scale turns world metres into model units.
	var scale_factor: float = maxf(global_transform.basis.get_scale().x,0.001)
	var speed := _speed if driving() else 0.0
	var turn := _turn if driving() else 0.0
	_roll = fmod(_roll+speed*delta/(wheel_radius*scale_factor),TAU)
	for wheel in _wheels: wheel.rotation.x = _roll
	if absf(turn) > 0.001:
		_steer_goal = clampf(rad_to_deg(turn)/steer_full_rate,-1.0,1.0)*deg_to_rad(steer_max_degrees)
		_steer_hold_left = steer_hold
	else:
		_steer_hold_left -= delta
		if _steer_hold_left <= 0.0: _steer_goal = 0.0
	_steer = lerpf(_steer,_steer_goal,minf(1.0,steer_speed*delta))
	for pivot in _steers: pivot.rotation.y = _steer
	var step := deg_to_rad(hatch_speed_degrees)*delta
	_lid = move_toward(_lid,deg_to_rad(lid_open_degrees) if _open else 0.0,step)
	_ramp = move_toward(_ramp,deg_to_rad(ramp_open_degrees) if _open else 0.0,step)
	if lid: lid.rotation.x = _lid
	if ramp: ramp.rotation.x = _ramp
	if indicator: indicator.position = _indicator_rest+Vector3(0,indicator_raise if _load > 0.0 else 0.0,0)
