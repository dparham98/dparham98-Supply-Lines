extends Node3D
## The land mine's model root (scenes/models/land_mine_model.tscn, docs/LAND_MINE_MODEL.md). Every state is
## posed here on the imported parts of assets/models/props/land_mine.glb; nothing is keyed.
## - Arming (the mine's first `arm_seconds`): the tilt rods swing up, the pressure plate rises, then the mine
##   beds in (sinks and throws up a ring of soil) while the fuse lamp blinks faster and faster.
## - Armed: bedded in, the lamp a slow dim pulse.
## - Detected by the enemy: an amber warning ring pulses round it (set_detected).
## land_mine.gd reports its age each frame through set_age().
## Rods unfold over this share of arming, the plate rises over the next, the mine beds in over the last.
const RODS := Vector2(0.08,0.45)
const PLATE := Vector2(0.30,0.60)
const SETTLE := Vector2(0.55,1.0)
@export_range(0,180,1) var rod_fold_degrees := 88.0
@export_range(0,0.2,0.005) var plate_drop := 0.03
@export_range(0,0.3,0.005) var settle_depth := 0.075
## The lamp blinks from this rate to the next (hertz) as it arms, then pulses slowly once armed.
@export var blink_hertz := Vector2(1.5,9.0)
@export_range(0.05,3,0.05) var armed_pulse_hertz := 0.4
@export_range(0,1,0.01) var armed_glow := 0.35
@export_range(0.1,5,0.1) var warning_hertz := 1.6
var _age := 0.0
var _arm_seconds := 3.0
var _detected := false
var _warning := 0.0
var _clock := 0.0
@onready var _root: Node3D = $Model/mine_root
@onready var _plate: Node3D = $Model/mine_root/mine_plate
@onready var _lamp: GeometryInstance3D = $Model/mine_root/mine_plate/mine_lamp
@onready var _soil: Node3D = $Model/mine_soil
@onready var _ring: GeometryInstance3D = $Model/mine_spotted
@onready var _rods: Array[Node3D] = [$Model/mine_root/mine_prong_1,$Model/mine_root/mine_prong_2,$Model/mine_root/mine_prong_3,$Model/mine_root/mine_prong_4]
var _rod_rest: Array[Basis] = []
@onready var _plate_rest: Vector3 = _plate.position
@onready var _root_rest: Vector3 = _root.position
func _ready() -> void:
	for rod in _rods: _rod_rest.append(rod.transform.basis)
	for node in [_ring,_soil]: node.set_meta(&"not_selectable",true)
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_pose(0.0)
## Seconds since it was laid, and how long it takes to arm (mine_rules.arm_seconds).
func set_age(age: float, arm_seconds: float) -> void:
	_age = age
	_arm_seconds = maxf(arm_seconds,0.01)
## The side whose view is drawn has it detected: show the warning ring.
func set_detected(on: bool) -> void:
	_detected = on
func detected() -> bool: return _detected
func arming() -> float: return clampf(_age/_arm_seconds,0.0,1.0)
func _process(delta: float) -> void:
	_clock += delta
	_pose(delta)
func _pose(delta: float) -> void:
	var p := arming()
	var rods := _phase(p,RODS)
	for i in _rods.size():
		_rods[i].transform.basis = _rod_rest[i]*Basis(Vector3.RIGHT,deg_to_rad(rod_fold_degrees)*(1.0-rods))
	_plate.position = _plate_rest-Vector3.UP*plate_drop*(1.0-_phase(p,PLATE))
	var settle := _phase(p,SETTLE)
	_root.position = _root_rest-Vector3.UP*settle_depth*settle
	_soil.scale = Vector3.ONE*maxf(settle,0.001)
	_soil.visible = settle > 0.0
	_lamp.set_instance_shader_parameter(&"glow",_lamp_glow(p))
	_warning = move_toward(_warning,1.0 if _detected else 0.0,delta*4.0)
	_ring.visible = _warning > 0.0
	if _ring.visible:
		var beat := 0.5+0.5*sin(TAU*warning_hertz*_clock)
		_ring.set_instance_shader_parameter(&"glow",_warning*(0.45+0.55*beat))
		_ring.scale = Vector3(1.0,1.0,1.0)*(1.0+0.06*beat)
## Arming: a blink that speeds up from blink_hertz.x to .y; armed: a slow dim pulse (brighter when spotted).
func _lamp_glow(p: float) -> float:
	if p < 1.0:
		var t := _age
		var phase := blink_hertz.x*t+(blink_hertz.y-blink_hertz.x)*t*t/(2.0*_arm_seconds)
		return 1.3 if fmod(phase,1.0) < 0.5 else 0.08
	var pulse := 0.5+0.5*sin(TAU*armed_pulse_hertz*_clock)
	return armed_glow*(0.4+0.6*pulse)+(0.5 if _detected else 0.0)
static func _phase(p: float, span: Vector2) -> float:
	return smoothstep(0.0,1.0,clampf((p-span.x)/(span.y-span.x),0.0,1.0))
