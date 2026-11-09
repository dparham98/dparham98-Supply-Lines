extends "res://scripts/components/turret_aim.gd"
## The Tank model root (scenes/models/tank_model.tscn): the turret from turret_aim.gd plus rolling
## tracks (docs/TANK_TRACKS.md). The unit agent reports travel through set_drive(); each side runs
## at ground speed, and a heading change runs the two sides against each other. Track links, road
## wheels and return rollers are single imported meshes moved by assets/shaders/tank_running_gear;
## the sprockets and idlers are single wheels and turn as nodes.
## Spacing of the links along the loop and wheel radii, in model units.
@export_range(0.05,2,0.001) var link_pitch := 0.503
@export_range(0.05,2,0.01) var road_wheel_radius := 0.46
@export_range(0.05,2,0.01) var return_roller_radius := 0.14
@export_range(0.05,2,0.01) var end_wheel_radius := 0.52
## Track speed each side gains or loses while the hull is turning, world m/s.
@export_range(0,20,0.1) var pivot_speed := 2.5
## RTS heading changes happen in a frame or two, so the counter-rotation is held this long.
@export_range(0,2,0.05) var pivot_hold := 0.25
var _speed := 0.0
var _drive_frame := -2
var _pivot := 0.0
var _pivot_left := 0.0
var _travel_left := 0.0
var _travel_right := 0.0
const HULL := "Tank/Tank_Root/Tank_Hull/"
@onready var _scale_source: Node3D = get_node(HULL+"Track_Links_L")
## Report this frame of travel: ground speed (m/s) and heading change (radians, positive turning left).
func set_drive(speed: float, turn: float, _delta: float) -> void:
	_speed = speed
	_drive_frame = Engine.get_process_frames()
	if absf(turn) > 0.0005:
		_pivot = signf(turn)*pivot_speed
		_pivot_left = pivot_hold
func set_hatches(_open: bool) -> void: pass
func set_load(_fraction: float) -> void: pass
func driving() -> bool:
	return Engine.get_process_frames()-_drive_frame <= 1 and _speed > 0.0
## Distance each track has run, in model units; positive is forward.
func track_travel_left() -> float: return _travel_left
func track_travel_right() -> float: return _travel_right
## Fraction of a link pitch for a travel distance: 0 is the authored pose.
func link_phase(travel: float) -> float: return fposmod(travel/link_pitch,1.0)
func _process(delta: float) -> void:
	super._process(delta)
	_pivot_left -= delta
	var pivot := _pivot if _pivot_left > 0.0 else 0.0
	var speed := _speed if driving() else 0.0
	if speed == 0.0 and pivot == 0.0: return
	var to_model: float = 1.0/maxf(_scale_source.global_transform.basis.get_scale().x,0.001)
	# The left track is on the inside of a left turn.
	_travel_left += (speed-pivot)*delta*to_model
	_travel_right += (speed+pivot)*delta*to_model
	_apply("L",_travel_left)
	_apply("R",_travel_right)
func _apply(side: String, travel: float) -> void:
	(get_node(HULL+"Track_Links_"+side) as GeometryInstance3D).set_instance_shader_parameter(&"roll",link_phase(travel))
	(get_node(HULL+"Road_Wheels_"+side) as GeometryInstance3D).set_instance_shader_parameter(&"roll",fposmod(travel/road_wheel_radius,TAU))
	(get_node(HULL+"Return_Rollers_"+side) as GeometryInstance3D).set_instance_shader_parameter(&"roll",fposmod(travel/return_roller_radius,TAU))
	var end_roll := fposmod(travel/end_wheel_radius,TAU)
	(get_node(HULL+"Drive_Sprocket_"+side) as Node3D).rotation.x = end_roll
	(get_node(HULL+"Idler_Wheel_"+side) as Node3D).rotation.x = end_roll
