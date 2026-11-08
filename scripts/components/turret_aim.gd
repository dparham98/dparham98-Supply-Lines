extends Node3D
## Turns a model's turret toward the point its owner is shooting at, and sways it idly otherwise.
## Sits on a model scene root (see scenes/models/tank_model.tscn); the owner calls aim_at() every
## frame it has a target. Only yaw turns: targets are on the ground, barrels stay level.
## The barrel's direction in the turret parent's frame at rest (glTF models face +Z before the wrapper turns them).
@export var barrel_axis := Vector3(0,0,1)
@export var turret_path: NodePath
## Where tracers start; falls back to the turret, then this node.
@export var muzzle_path: NodePath
@export_range(10,1080,1) var turn_speed_degrees := 240.0
## Idle sway: slow yaw swing around the rest direction so a parked tank is not frozen.
@export_range(0,45,0.5) var sway_degrees := 6.0
@export_range(0.5,60,0.5) var sway_period := 7.0
var _yaw := 0.0
var _time := 0.0
var _aim_point := Vector3.ZERO
var _aim_frame := -2
var _phase := randf()*TAU
var _rest := Basis.IDENTITY
@onready var turret: Node3D = get_node_or_null(turret_path)
@onready var muzzle: Node3D = get_node_or_null(muzzle_path)
func _ready() -> void:
	if turret: _rest = turret.transform.basis
## Call each frame while there is a target; aiming lapses after a frame without a call.
func aim_at(point: Vector3) -> void:
	_aim_point = point
	_aim_frame = Engine.get_process_frames()
func aiming() -> bool:
	return Engine.get_process_frames()-_aim_frame <= 1
func turret_yaw() -> float:
	return _yaw
func muzzle_position() -> Vector3:
	if muzzle: return muzzle.global_position
	return turret.global_position if turret else global_position
## Yaw the turret wants: toward the aim point in its parent's frame, or the sway angle.
func goal_yaw() -> float:
	if not aiming() or turret == null: return deg_to_rad(sway_degrees)*sin(TAU*_time/sway_period+_phase)
	var local: Vector3 = turret.get_parent().to_local(_aim_point)
	var flat := Vector2(local.x,local.z)
	if flat.length_squared() < 0.0001: return _yaw
	return atan2(flat.x,flat.y)-atan2(barrel_axis.x,barrel_axis.z)
func _process(delta: float) -> void:
	if turret == null: return
	_time += delta
	_yaw = wrapf(rotate_toward(_yaw,goal_yaw(),deg_to_rad(turn_speed_degrees)*delta),-PI,PI)
	turret.transform.basis = Basis(Vector3.UP,_yaw)*_rest
