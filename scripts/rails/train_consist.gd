extends Node3D
## Places a maglev consist on a track line (docs/MAGLEV_TRACKS.md): cargo cars from the authored set,
## each riding on two sleds that follow the centre line, so bodies bridge curves. The owner calls
## place() every frame with its track line and the distance of the first car's front sled along it.
## World scale of the authored set.
@export var world_scale := 0.6
## Authored metres: sled offset from each car's root, and pivot-to-pivot gaps between cars.
@export var cargo_sled_span := 3.0
@export var car_to_car_gap := 5.0
@export var sled_height := 1.0
@export var indicator_raise := 0.32
@export var car_paths: Array[NodePath] = [NodePath("Car1")]
var _cars: Array[Dictionary] = []
var _indicator_rest := {}
func _ready() -> void:
	for path in car_paths:
		var car := get_node_or_null(path)
		if car: _cars.append({node = car, span = cargo_sled_span, front = "sled_cargo_front", rear = "sled_cargo_rear", gap = car_to_car_gap})
	for car in _cars:
		var indicator: Node3D = car.node.find_child("cargo_car_indicator",true,false)
		if indicator: _indicator_rest[car.node.get_instance_id()] = indicator.position
func cars() -> Array[Dictionary]: return _cars
## Length from the first car's front sled to the last car's rear sled, in world metres.
func length() -> float:
	var total := 0.0
	for i in range(_cars.size()):
		total += _cars[i].span*2.0*world_scale
		if i < _cars.size()-1: total += _cars[i].gap*world_scale
	return total
## Distance back along the line at which the straight-line distance from `s` equals `chord`.
static func chord_back(track: Dictionary, s: float, chord: float) -> float:
	var p0: Vector3 = RailLine.point(track,s)[0]
	var lo := s-chord*1.25
	var hi := s-chord
	for i in range(32):
		var mid := (lo+hi)*0.5
		if RailLine.point(track,mid)[0].distance_to(p0) > chord: lo = mid
		else: hi = mid
	return (lo+hi)*0.5
## Sets every car on `track` with the first car's front sled at `s_front`; `load` (0-1) lights the
## cargo indicators car by car from the front.
func place(track: Dictionary, s_front: float, load := 0.0) -> void:
	if track.is_empty() or _cars.is_empty(): return
	var s := s_front
	var cargo_index := 0
	var cargo_total := maxi(1,_cars.size())
	for car in _cars:
		var span: float = car.span*world_scale
		var s_rear := chord_back(track,s,span*2.0)
		var front: Array = RailLine.point(track,s)
		var rear: Array = RailLine.point(track,s_rear)
		var head: Vector3 = (front[0]-rear[0])
		head.y = 0
		if head.length_squared() < 0.0001: head = front[1]
		head = head.normalized()
		var node: Node3D = car.node
		var mid: Vector3 = (front[0]+rear[0])*0.5
		node.global_transform = Transform3D(Basis.looking_at(head,Vector3.UP,true).scaled(Vector3.ONE*world_scale),Vector3(mid.x,0,mid.z))
		var sled_a: Node3D = node.find_child(car.front,true,false)
		var sled_b: Node3D = node.find_child(car.rear,true,false)
		if sled_a: sled_a.global_transform = Transform3D(Basis.looking_at(_flat(front[1]),Vector3.UP,true).scaled(Vector3.ONE*world_scale),Vector3(front[0].x,sled_height*world_scale,front[0].z))
		if sled_b: sled_b.global_transform = Transform3D(Basis.looking_at(_flat(rear[1]),Vector3.UP,true).scaled(Vector3.ONE*world_scale),Vector3(rear[0].x,sled_height*world_scale,rear[0].z))
		var indicator: Node3D = node.find_child("cargo_car_indicator",true,false)
		if indicator and _indicator_rest.has(node.get_instance_id()):
			var lit: bool = car.front == "sled_cargo_front" and load > float(cargo_index)/cargo_total+0.001
			indicator.position = _indicator_rest[node.get_instance_id()]+Vector3(0,indicator_raise if lit else 0.0,0)
			if car.front == "sled_cargo_front": cargo_index += 1
		s = chord_back(track,s_rear,car.gap*world_scale)
static func _flat(v: Vector3) -> Vector3:
	var f := Vector3(v.x,0,v.z)
	return f.normalized() if f.length_squared() > 0.0001 else Vector3.FORWARD
