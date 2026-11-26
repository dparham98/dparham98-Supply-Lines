extends "res://scripts/rails/train_consist.gd"
## The Knights' coal train (docs/KNIGHTS_TRAIN_MODEL.md): the Streamliner's consist (train_consist.gd places the
## car on the track) with a firebox and a stack. train.gd calls set_running() and set_out_of_fuel() each frame
## for a coal_fuelled train. While it runs, the fire behind the firebox door roars and smoke puffs from the stack.
## Standing, the fire burns low with a thin wisp. Out of coal, only banked embers show and there is no smoke.
## Seconds between smoke puffs while running, and how long each one lasts.
@export var puff_every := 0.32
@export var puff_seconds := 1.6
## How far a puff rises and how far it trails back along the car, in the car's authored metres.
@export var puff_rise := 2.2
@export var puff_trail := 2.6
var _running := false
var _out_of_fuel := false
var _clock := 0.0
var _glow: Node3D
var _embers: Node3D
var _puffs: Array[Node3D] = []
var _puff_rest: Array[Vector3] = []
func _ready() -> void:
	super._ready()
	_glow = find_child("firebox_glow",true,false)
	_embers = find_child("firebox_embers",true,false)
	for i in range(1,10):
		var puff := find_child("stack_smoke_%d" % i,true,false) as Node3D
		if puff == null: break
		_puffs.append(puff)
		_puff_rest.append(puff.position)
	_show(0.0)
## Whether the train is moving along its route.
func set_running(running: bool) -> void:
	_running = running
## Whether its coal tank is empty.
func set_out_of_fuel(empty: bool) -> void:
	_out_of_fuel = empty
func running() -> bool: return _running and not _out_of_fuel
func out_of_fuel() -> bool: return _out_of_fuel
## Toward the car's tail, flat, in the puff's parent space: from the front sled to the rear one.
func _trail(puff: Node3D) -> Vector3:
	var front := find_child("sled_cargo_front",true,false) as Node3D
	var rear := find_child("sled_cargo_rear",true,false) as Node3D
	if front == null or rear == null or not puff.is_inside_tree(): return Vector3.ZERO
	var parent := puff.get_parent() as Node3D
	var back := parent.to_local(rear.global_position)-parent.to_local(front.global_position)
	back.y = 0.0
	return back.normalized() if back.length_squared() > 0.0001 else Vector3.ZERO
func _process(delta: float) -> void:
	_clock += delta
	_show(_clock)
func _show(t: float) -> void:
	var burning := not _out_of_fuel
	var roar := running()
	if _glow != null:
		_glow.visible = burning
		var flicker := 1.0+0.12*sin(t*23.0)+0.08*sin(t*37.0)
		_glow.scale = Vector3.ONE*(flicker if roar else 0.55+0.05*sin(t*5.0))
	if _embers != null: _embers.visible = true
	# Puffs share one cycle, spread evenly across it. Standing, only every other puff shows, small and slow.
	var count := _puffs.size()
	for i in range(count):
		var puff := _puffs[i]
		var every := puff_every if roar else puff_every*4.0
		var u := fposmod(t/(every*count)+float(i)/count,1.0)
		var life := minf(1.0,u*every*count/puff_seconds)
		var shown := burning and (roar or i % 2 == 0) and life < 1.0
		puff.visible = shown
		if not shown: continue
		var size := (0.4+1.6*life)*(1.0-smoothstep(0.7,1.0,life))*(1.0 if roar else 0.45)
		puff.position = _puff_rest[i]+Vector3.UP*puff_rise*life*(1.0 if roar else 0.6)+_trail(puff)*puff_trail*life*(1.0 if roar else 0.2)
		puff.scale = Vector3.ONE*maxf(size,0.01)
