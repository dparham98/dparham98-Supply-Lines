extends Node3D
## One maglev track piece (docs/MAGLEV_TRACKS.md): a straight, a 90-degree curve or a fork from the
## authored set, placed end to end. A piece has one or two lanes, each a centre line running away
## from end 0. Straights and curves have ends 0 and 1. Forks have an entry (end 0), a straight exit
## (end 1, lane 0) and a branch exit (end 2, lane 1). Pieces connect where one end meets another's
## head-on, and mark the tiles under them so buildings keep off.
@export_enum("straight","curve","fork_left","fork_right") var kind := "straight"
## World scale of the authored set (true-scale metres times this).
@export var world_scale := 0.6
## Authored dimensions in metres: straight length, curve radius, track width, fork straight leg.
@export var straight_length := 8.0
@export var curve_radius := 20.0
@export var track_width := 5.0
@export var fork_straight_length := 24.0
## How far an unused switch blade drops, in authored metres.
@export var blade_drop := 0.46
@export var assigned_depot_path: NodePath
## The Depot that paid for the piece. Whether the line is usable depends on connected Depots.
var assigned_depot: Node3D
var cells: Array[Vector2i] = []
## Which lane a fork's switch is set to.
var route_lane := 0
@onready var network = get_tree().get_first_node_in_group("rail_network")
@onready var blade_straight: Node3D = find_child("*_blade_straight",true,false)
@onready var blade_branch: Node3D = find_child("*_blade_branch",true,false)
func _ready() -> void:
	if assigned_depot == null and not assigned_depot_path.is_empty(): assigned_depot = get_node_or_null(assigned_depot_path)
	if not network.register(self): queue_free(); return
	add_to_group("rails")
	update_color()
func _exit_tree() -> void:
	if is_instance_valid(network): network.unregister(self)
func is_fork() -> bool: return kind.begins_with("fork")
func lane_count() -> int: return 2 if is_fork() else 1
func end_count() -> int: return 3 if is_fork() else 2
## The two ends a lane runs between, start first.
func lane_ends(lane: int) -> Array:
	return [0,lane+1] if is_fork() else [0,1]
## The lanes that can be entered from an end.
func lanes_at(end: int) -> Array:
	if not is_fork(): return [0]
	return [0,1] if end == 0 else [end-1]
func _lane_is_straight(lane: int) -> bool:
	return kind == "straight" or (is_fork() and lane == 0)
func _side() -> float:
	return -1.0 if kind == "fork_right" else 1.0
## Centre-line length of a lane in world metres.
func length(lane := 0) -> float:
	if kind == "straight": return straight_length*world_scale
	if is_fork() and lane == 0: return fork_straight_length*world_scale
	return curve_radius*world_scale*PI*0.5
func total_length() -> float:
	var total := 0.0
	for lane in range(lane_count()): total += length(lane)
	return total
func half_width() -> float:
	return track_width*world_scale*0.5
## Local centre-line point at distance `d` from end 0. Curves bend toward local +X, right forks toward -X.
func local_point(d: float, lane := 0) -> Vector3:
	if _lane_is_straight(lane): return Vector3(0,0,d)
	var r := curve_radius*world_scale
	var a := clampf(d/r,0.0,PI*0.5)
	return Vector3(_side()*(r-r*cos(a)),0,r*sin(a))
func local_tangent(d: float, lane := 0) -> Vector3:
	if _lane_is_straight(lane): return Vector3(0,0,1)
	var a := clampf(d/(curve_radius*world_scale),0.0,PI*0.5)
	return Vector3(_side()*sin(a),0,cos(a))
func point_at(d: float, lane := 0) -> Vector3:
	return global_transform*local_point(d,lane)
func tangent_at(d: float, lane := 0) -> Vector3:
	return (global_transform.basis*local_tangent(d,lane)).normalized()
## An end in the piece's own space: {position, out}, `out` pointing away from the piece.
func local_end(index: int) -> Dictionary:
	if index == 0: return {position = local_point(0.0), out = -local_tangent(0.0)}
	var lane := index-1 if is_fork() else 0
	var total := length(lane)
	return {position = local_point(total,lane), out = local_tangent(total,lane)}
## Every end in world space: {position, out}.
func ends() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for index in range(end_count()):
		var end := local_end(index)
		result.append({position = global_transform*(end.position as Vector3), out = (global_transform.basis*(end.out as Vector3)).normalized()})
	return result
## Distance along the nearest lane (or only `only_lane`) to `point`: {distance, gap, lane}.
func nearest(point: Vector3, only_lane := -1) -> Dictionary:
	var best := {distance = 0.0, gap = INF, lane = 0}
	for lane in range(lane_count()):
		if only_lane >= 0 and lane != only_lane: continue
		var total := length(lane)
		var steps := maxi(8,int(total/0.25))
		for i in range(steps+1):
			var d := total*i/steps
			var at := point_at(d,lane)
			var gap := Vector2(point.x,point.z).distance_to(Vector2(at.x,at.z))
			if gap < best.gap: best = {distance = d, gap = gap, lane = lane}
	return best
## Whether a local point lies on the track: within half the width of a lane and between its ends
## (both exclusive, so pieces joined at any two ends never share a tile).
func local_inside(p: Vector3) -> bool:
	for lane in range(lane_count()):
		if _inside_lane(p,lane): return true
	return false
func _inside_lane(p: Vector3, lane: int) -> bool:
	var w := half_width()
	if _lane_is_straight(lane): return absf(p.x) <= w and p.z > 0.001 and p.z < length(lane)-0.001
	var r := curve_radius*world_scale
	var rel := Vector2(p.x*_side()-r,p.z)
	if absf(rel.length()-r) > w: return false
	var a := atan2(rel.y,-rel.x)
	return a > 0.0001 and a < PI*0.5-0.0001
## Ground cells under the piece, from its current transform; the network computes the same for a
## piece that is not placed yet.
func footprint_cells() -> Array[Vector2i]:
	return network.cells_for(kind,global_transform)
## Moves a fork's switch blades to show the lane in use: its blade up, the other dropped.
func set_route(lane: int) -> void:
	if not is_fork() or lane == route_lane: return
	route_lane = lane
	var tween := create_tween().set_parallel()
	tween.tween_property(blade_straight,"position:y",-blade_drop if lane == 1 else 0.0,0.3)
	tween.tween_property(blade_branch,"position:y",0.0 if lane == 1 else -blade_drop,0.3)
## The plate at the piece's middle shows power: cyan powered, dark without power, red for a hostile line.
func update_color() -> void:
	var plate: MeshInstance3D = get_node_or_null("Visuals/Owner")
	if plate == null or not is_instance_valid(network): return
	if plate.material_override == null: plate.material_override = plate.mesh.material.duplicate()
	var colour := Color(0.12,0.14,0.16)
	if network.powered(self,"player"): colour = Color(0.3,0.9,1.0)
	elif network.friendly_piece(self,"enemy") and not network.friendly_piece(self,"player"): colour = Color(0.9,0.3,0.25)
	plate.material_override.albedo_color = colour
	plate.material_override.emission = colour
