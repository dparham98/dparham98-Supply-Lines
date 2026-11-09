extends Node3D
## One maglev track piece (docs/MAGLEV_TRACKS.md): a straight or a 90-degree curve from the authored
## set, placed end to end. Its centre line runs from end 0 to end 1; each end has an outward heading.
## Pieces connect where an end meets another piece's end head-on. The piece marks the tiles under it
## so buildings keep off, and belongs to the Depot that paid for it like the old rail tiles did.
@export_enum("straight","curve") var kind := "straight"
## World scale of the authored set (true-scale metres times this).
@export var world_scale := 0.6
## Authored dimensions in metres: straight length, curve radius, track width.
@export var straight_length := 8.0
@export var curve_radius := 20.0
@export var track_width := 5.0
@export var assigned_depot_path: NodePath
var assigned_depot: Node3D
var cells: Array[Vector2i] = []
@onready var network = get_tree().get_first_node_in_group("rail_network")
func _ready() -> void:
	if assigned_depot == null and not assigned_depot_path.is_empty(): assigned_depot = get_node_or_null(assigned_depot_path)
	if not network.register(self): queue_free(); return
	add_to_group("rails")
	update_color()
func _exit_tree() -> void:
	if is_instance_valid(network): network.unregister(self)
## Centre-line length in world metres.
func length() -> float:
	return straight_length*world_scale if kind == "straight" else curve_radius*world_scale*PI*0.5
func half_width() -> float:
	return track_width*world_scale*0.5
## Local centre-line point at distance `d` from end 0. The curve bends toward local +X.
func local_point(d: float) -> Vector3:
	if kind == "straight": return Vector3(0,0,d)
	var r := curve_radius*world_scale
	var a := clampf(d/r,0.0,PI*0.5)
	return Vector3(r-r*cos(a),0,r*sin(a))
func local_tangent(d: float) -> Vector3:
	if kind == "straight": return Vector3(0,0,1)
	var a := clampf(d/(curve_radius*world_scale),0.0,PI*0.5)
	return Vector3(sin(a),0,cos(a))
func point_at(d: float) -> Vector3:
	return global_transform*local_point(d)
func tangent_at(d: float) -> Vector3:
	return (global_transform.basis*local_tangent(d)).normalized()
## The two ends: {position, out} where `out` points away from the piece along the track.
func ends() -> Array[Dictionary]:
	var total := length()
	return [
		{position = point_at(0.0), out = -tangent_at(0.0)},
		{position = point_at(total), out = tangent_at(total)}]
## Distance along the piece of the centre-line point nearest `point`, with that point's distance.
func nearest(point: Vector3) -> Dictionary:
	var best_d := 0.0
	var best_gap := INF
	var total := length()
	var steps := maxi(8,int(total/0.25))
	for i in range(steps+1):
		var d := total*i/steps
		var gap := Vector2(point.x,point.z).distance_to(Vector2(point_at(d).x,point_at(d).z))
		if gap < best_gap: best_gap = gap; best_d = d
	return {distance = best_d, gap = best_gap}
## Whether a point in the piece's local frame lies on the track: within half the width of the
## centre line and between the two ends (half-open, so joined pieces never share a tile).
func local_inside(p: Vector3) -> bool:
	var w := half_width()
	if kind == "straight": return absf(p.x) <= w and p.z >= -0.001 and p.z < length()-0.001
	var r := curve_radius*world_scale
	var rel := Vector2(p.x-r,p.z)
	if absf(rel.length()-r) > w: return false
	var a := atan2(rel.y,-rel.x)
	return a >= -0.0001 and a < PI*0.5-0.0001
## Ground cells under the piece, from its current transform; the network computes the same for a
## piece that is not placed yet.
func footprint_cells() -> Array[Vector2i]:
	return network.cells_for(kind,global_transform)
## Ownership shows on the authored Owner plate at the piece's middle: friendly cyan, hostile red.
func update_color() -> void:
	var plate: MeshInstance3D = get_node_or_null("Visuals/Owner")
	if plate == null: return
	if plate.material_override == null: plate.material_override = plate.mesh.material.duplicate()
	var friendly: bool = is_instance_valid(network) and network.friendly_piece(self,"player")
	plate.material_override.albedo_color = Color(0.3,0.9,1.0) if friendly else Color(0.9,0.3,0.25)
	plate.material_override.emission = plate.material_override.albedo_color
