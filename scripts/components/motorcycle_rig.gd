extends "res://scripts/components/turret_aim.gd"
## The Motorcycle model root (scenes/models/motorcycle_model.tscn): the gun swivel from turret_aim.gd
## plus everything that moves on a ridden bike. The unit agent reports travel through set_drive();
## the wheels roll, the fork steers, the whole bike leans into the turn about its tyres, and the
## parking stand comes down when it stops. The gun tracks its target all the way round while the
## bike keeps riding, the rider looks where the gun points, and fire() kicks the barrel and the
## back of the bike and vents steam. Every part is a node of the imported model
## (assets/models/units/motorcycle.glb); only the death is a baked clip. See docs/MOTORCYCLE_MODEL.md.
## Wheel radii in the model's own units.
@export_range(0.05,2,0.01) var front_wheel_radius := 0.37
@export_range(0.05,2,0.01) var rear_wheel_radius := 0.38
@export_range(0,45,0.5) var steer_max_degrees := 15.0
## RTS heading changes happen in a frame or two, so they are gathered into one swing (degrees turned
## lately, left positive) that fades over steer_hold seconds. A jink left then right cancels out.
## The swing that steers the fork fully:
@export_range(1,360,1) var steer_full_turn := 40.0
@export_range(0.1,20,0.1) var steer_speed := 6.0
@export_range(0.05,2,0.05) var steer_hold := 0.4
## Share of the steer the handlebars follow. The rider's arms are rigid, so the grips cannot go far.
@export_range(0,1,0.05) var bar_follow := 0.35
@export_range(0,45,0.5) var lean_max_degrees := 18.0
## The swing that leans the bike fully, and the ground speed at which a lean is fully allowed.
@export_range(1,360,1) var lean_full_turn := 60.0
@export_range(0.1,20,0.1) var lean_full_speed := 2.0
@export_range(0.1,20,0.1) var lean_speed := 5.0
## Parked: the stand swings down and the bike settles onto it, toward its left.
@export_range(0,15,0.5) var park_lean_degrees := 5.0
@export_range(0,180,0.1) var stand_stow_degrees := 96.4
@export_range(0.05,3,0.05) var stand_time := 0.35
@export_range(0,2,0.05) var park_delay := 0.2
## The rider looks where the gun points, as far as a neck turns.
@export_range(0,120,1) var head_turn_degrees := 70.0
@export_range(0.1,20,0.1) var head_speed := 7.0
## Firing: how far the barrel slams back (model units), how fast, and how long it takes to run out.
@export_range(0,0.5,0.01) var recoil_distance := 0.12
@export_range(0.01,0.5,0.01) var recoil_kick_time := 0.04
@export_range(0.05,2,0.01) var recoil_return_time := 0.45
## The back of the bike hops as the gun goes off, then settles.
@export_range(0,10,0.1) var kick_degrees := 1.8
@export_range(0.5,10,0.1) var kick_hertz := 3.2
@export_range(0,20,0.1) var kick_damping := 6.0
## Engine rumble (model units) and the rider's slow sway keep a still bike from looking frozen.
@export_range(0,0.05,0.001) var rumble_height := 0.004
@export_range(1,40,0.5) var rumble_hertz := 17.0
@export_range(0,10,0.1) var sway_rider_degrees := 1.2
@export var death_clip := &"Die"
## Spawned on this model at death (sparks, oil, fire); built on the same timeline as the clip.
@export var death_fx_scene: PackedScene
var _dying := false
var _speed := 0.0
var _turn := 0.0
var _drive_frame := -2
var _roll_front := 0.0
var _roll_rear := 0.0
var _swing := 0.0
var _steer := 0.0
var _lean := 0.0
var _stand := 0.0
var _stopped := INF
var _head := 0.0
var _since_fire := INF
var _clock := randf()*10.0
const BIKE := "Rig/bike_root/"
const FORWARD := Vector3(0,0,1)
@onready var player: AnimationPlayer = get_node("Rig/AnimationPlayer")
@onready var _bike: Node3D = get_node("Rig/bike_root")
@onready var _frame: Node3D = get_node(BIKE+"frame")
@onready var _steer_pivot: Node3D = get_node(BIKE+"steer_F")
@onready var _bars: Node3D = get_node(BIKE+"steer_F/handlebar_F")
@onready var _wheel_front: Node3D = get_node(BIKE+"steer_F/wheel_F")
@onready var _wheel_rear: Node3D = get_node(BIKE+"wheel_R")
@onready var _stand_leg: Node3D = get_node(BIKE+"stand")
@onready var _barrel: Node3D = get_node(BIKE+"gun_swivel/gun_body/gun_barrel")
@onready var _torso: Node3D = get_node(BIKE+"rider_torso")
@onready var _head_node: Node3D = get_node(BIKE+"rider_torso/rider_head")
@onready var _bike_rest: Basis = _bike.transform.basis
@onready var _frame_rest: Vector3 = _frame.position
@onready var _steer_rest: Basis = _steer_pivot.transform.basis
@onready var _bars_rest: Basis = _bars.transform.basis
@onready var _stand_rest: Basis = _stand_leg.transform.basis
@onready var _barrel_rest: Vector3 = _barrel.position
@onready var _torso_rest: Basis = _torso.transform.basis
@onready var _head_rest: Basis = _head_node.transform.basis
## Report this frame of travel: ground speed (m/s) and heading change (radians this frame, positive
## turning left). Lapses after a frame without a call.
func set_drive(speed: float, turn: float, delta: float) -> void:
	_speed = speed
	_turn = turn
	_drive_frame = Engine.get_process_frames()
func set_hatches(_open: bool) -> void: pass
func set_load(_fraction: float) -> void: pass
func driving() -> bool:
	return Engine.get_process_frames()-_drive_frame <= 1 and _speed > 0.0
## The unit takes a target and fires on it in the same frame, and the spike starts at the muzzle. So a
## newly taken target swings the gun straight onto it, and the spike leaves along the barrel; after
## that the swivel tracks at its turn rate.
func aim_at(point: Vector3) -> void:
	var fresh := not aiming()
	super.aim_at(point)
	if not fresh or turret == null or _dying: return
	_yaw = wrapf(goal_yaw(),-PI,PI)
	turret.transform.basis = Basis(Vector3.UP,_yaw)*_rest
## One spike leaves the gun: steam from the muzzle node, the barrel slams back, the rear hops.
func fire() -> void:
	_since_fire = 0.0
	if muzzle != null and muzzle.has_method("play"): muzzle.play()
func has_death_clip() -> bool:
	return player != null and player.has_animation(death_clip)
func dying() -> bool:
	return _dying
## The unit has already gone and this model is its wreck: play the crash out, then remove it.
## Nothing here writes to the model's nodes from now on; the clip owns them.
func play_death() -> void:
	_dying = true
	_barrel.position = _barrel_rest
	player.animation_finished.connect(func(clip: StringName) -> void: if clip == death_clip: queue_free())
	player.play(death_clip)
	if death_fx_scene: add_child(death_fx_scene.instantiate())
func wheel_roll() -> float: return _roll_rear
func steer_angle() -> float: return _steer
## Radians about the bike's forward axis; positive is leaning to its left.
func lean_angle() -> float: return _lean
## 0 with the stand down on the ground, 1 with it folded away.
func stand_stowed() -> float: return _stand
func head_yaw() -> float: return _head
func _process(delta: float) -> void:
	if _dying: return
	super._process(delta)
	_clock += delta
	var moving := driving()
	var speed := _speed if moving else 0.0
	var turn := _turn if moving else 0.0
	# Wheels: roll by the ground distance covered; the wrapper's scale turns world metres into model units.
	var to_model: float = 1.0/maxf(global_transform.basis.get_scale().x,0.001)
	_roll_front = fmod(_roll_front+speed*delta*to_model/front_wheel_radius,TAU)
	_roll_rear = fmod(_roll_rear+speed*delta*to_model/rear_wheel_radius,TAU)
	_wheel_front.rotation.x = _roll_front
	_wheel_rear.rotation.x = _roll_rear
	# One fading swing steers the fork and leans the bike.
	_swing = (_swing+rad_to_deg(turn))*exp(-delta/steer_hold)
	_steer = lerpf(_steer,clampf(_swing/steer_full_turn,-1.0,1.0)*deg_to_rad(steer_max_degrees),minf(1.0,steer_speed*delta))
	_steer_pivot.transform.basis = _steer_rest*Basis(Vector3.UP,_steer)
	_bars.transform.basis = Basis(Vector3.UP,-_steer*(1.0-bar_follow))*_bars_rest
	# The stand folds away as the bike moves off and comes down a moment after it stops.
	_stopped = 0.0 if moving else _stopped+delta
	_stand = move_toward(_stand,0.0 if _stopped > park_delay else 1.0,delta/stand_time)
	_stand_leg.transform.basis = _stand_rest*Basis(Vector3.RIGHT,deg_to_rad(stand_stow_degrees)*smoothstep(0.0,1.0,_stand))
	# Lean into the turn while riding; settle left onto the stand when parked.
	var into_turn := clampf(_swing/lean_full_turn,-1.0,1.0)*deg_to_rad(lean_max_degrees)*clampf(speed/lean_full_speed,0.0,1.0)
	var parked := deg_to_rad(park_lean_degrees)*(1.0-smoothstep(0.0,1.0,_stand))
	_lean = lerpf(_lean,into_turn+parked,minf(1.0,lean_speed*delta))
	_bike.transform.basis = _bike_rest*Basis(FORWARD,-_lean)*Basis(Vector3.RIGHT,_kick(delta))
	_frame.position = _frame_rest+Vector3.UP*rumble_height*sin(TAU*rumble_hertz*_clock)*(1.0 if moving else 0.5)
	_torso.transform.basis = _torso_rest*Basis(FORWARD,deg_to_rad(sway_rider_degrees)*sin(1.7*_clock)-_lean*0.2)
	var look := clampf(turret_yaw(),-deg_to_rad(head_turn_degrees),deg_to_rad(head_turn_degrees)) if aiming() else 0.0
	_head = lerpf(_head,look,minf(1.0,head_speed*delta))
	_head_node.transform.basis = _head_rest*Basis(Vector3.UP,_head)
## Barrel recoil, and the pitch that lifts the back of the bike, for this frame.
func _kick(delta: float) -> float:
	if _since_fire == INF: return 0.0
	_since_fire += delta
	if _since_fire >= maxf(recoil_kick_time+recoil_return_time,5.0/kick_damping):
		_since_fire = INF
		_barrel.position = _barrel_rest
		return 0.0
	var back: float = smoothstep(0.0,recoil_kick_time,_since_fire)*(1.0-smoothstep(0.0,recoil_return_time,_since_fire-recoil_kick_time))
	_barrel.position = _barrel_rest-barrel_axis*back*recoil_distance
	return deg_to_rad(kick_degrees)*exp(-kick_damping*_since_fire)*sin(TAU*kick_hertz*_since_fire)
