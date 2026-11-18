extends SceneTree
## Executed inside a temporary copy of the real project, using its imported GLB and actors.
const Paint = preload("res://scripts/components/team_paint.gd")
const DT := 1.0 / 60.0
const EXPECTED := {
	"cargo_body": Vector3(0, 2.5, 0),
	"cargo_car_indicator": Vector3(0, 3.6, -3.55),
	"sled_cargo_front": Vector3(0, 1, 3),
	"sled_cargo_rear": Vector3(0, 1, -3),
	"cargo_coupler_F": Vector3(0, 1.67, 5.5),
	"cargo_coupler_R": Vector3(0, 1.67, -5.5)
}
var game: Node3D
var train: Node3D
var model: Node3D
var car: Node3D
var front: Node3D
var rear: Node3D
var curve: Node3D
var rails: Node
var failures: Array[String] = []
var results := {}

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, detail: String) -> void:
	if not condition:
		failures.append(detail)
		printerr("CHECK FAILED: ", detail)

func numbers(v: Vector3) -> Array:
	return [v.x, v.y, v.z]

func paint_slots(actor: Node3D, team: String) -> int:
	var count := 0
	for instance: MeshInstance3D in actor.get_node("Visuals/Model").find_children("*","MeshInstance3D",true,false):
		for index in instance.mesh.get_surface_count():
			var base := instance.mesh.surface_get_material(index)
			var override := instance.get_surface_override_material(index)
			if base != null and base.resource_name == "team_color":
				check(override == Paint.paint_for(team), "Unexpected team paint on " + str(instance.name))
				count += 1
			else:
				check(override == null, "Unmarked neutral surface changed on " + str(instance.name))
	return count

func check_teams() -> void:
	var other := load("res://scenes/gameplay/train.tscn").instantiate() as Node3D
	other.team = "enemy"
	other.position = train.position + Vector3(5,0,0)
	train.get_parent().add_child(other)
	other.set_process(false)
	check(not train.get_node("Visuals/TeamMarker").visible and not other.get_node("Visuals/TeamMarker").visible, "Ownership review requires unselected actors")
	var blue := paint_slots(train, "player")
	check(blue > 0 and paint_slots(other, "enemy") == blue, "Two actors need identical paint slots")
	var crimson := Paint.paint_for("enemy") as StandardMaterial3D
	var cobalt := Paint.paint_for("player") as StandardMaterial3D
	check(crimson.albedo_color.r > crimson.albedo_color.b and cobalt.albedo_color.b > cobalt.albedo_color.r, "Review palette must be red and blue")
	var shared_count := 0
	var other_car: Node3D = other.get_node("Visuals/Model/Car1")
	for instance: MeshInstance3D in car.find_children("*", "MeshInstance3D", true, false):
		var matching := other_car.get_node(car.get_path_to(instance)) as MeshInstance3D
		check(matching.mesh == instance.mesh, "Instances do not share imported mesh " + str(instance.name))
		shared_count += 1
	other.team = "neutral"
	check(paint_slots(other, "neutral") == blue and paint_slots(train, "player") == blue, "Neutral reassignment leaked between actors")
	other.team = "enemy"
	check(paint_slots(other, "enemy") == blue and paint_slots(train, "player") == blue, "Red reassignment leaked between actors")
	results["team_color"] = {"painted_surfaces_per_actor": blue, "shared_mesh_instances_checked": shared_count,
		"red_rgba": crimson.albedo_color.to_html(), "blue_rgba": cobalt.albedo_color.to_html(),
		"reassignment": "simultaneous player + enemy, then enemy -> neutral -> enemy"}

func check_import() -> void:
	# Inspect the pristine imported hierarchy before train_consist has moved its bogies.
	var raw := load("res://assets/models/units/maglev_train_cargo.glb").instantiate() as Node3D
	root.add_child(raw)
	var contract_root := raw if raw.name == "train_cargo_root" else raw.find_child("train_cargo_root",true,false) as Node3D
	check(contract_root != null, "Missing train_cargo_root")
	var transforms := {}
	for id in EXPECTED:
		var part := raw.find_child(id,true,false) as Node3D
		check(part != null, "Missing runtime node " + id)
		if part == null: continue
		var pivot := raw.to_local(part.global_position)
		transforms[id] = numbers(pivot)
		check(pivot.distance_to(EXPECTED[id]) < 0.001, "%s pivot %s expected %s" % [id,pivot,EXPECTED[id]])
	results["imported_pivots_author_metres_xyz"] = transforms
	check(raw.transform.is_equal_approx(Transform3D.IDENTITY), "Imported root transform is not identity")
	check(raw.find_children("*","AnimationPlayer",true,false).is_empty() and raw.find_children("*","Skeleton3D",true,false).is_empty(), "Unexpected rig or animations")
	var lo := Vector3.INF
	var hi := -Vector3.INF
	for instance: MeshInstance3D in raw.find_children("*","MeshInstance3D",true,false):
		for index in instance.mesh.get_surface_count():
			var verts: PackedVector3Array = instance.mesh.surface_get_arrays(index)[Mesh.ARRAY_VERTEX]
			for local in verts:
				var pt := raw.to_local(instance.to_global(local))
				lo = lo.min(pt)
				hi = hi.max(pt)
	results["imported_mesh_bounds_xyz"] = {"min":numbers(lo), "max":numbers(hi), "size":numbers(hi-lo)}
	var coupler_plane := EXPECTED["cargo_coupler_F"] as Vector3
	results["axial_coupler_marker_margin_authored_m"] = [coupler_plane.z - hi.z, lo.z + coupler_plane.z]
	check(lo.y > 0 and lo.z >= -5.501 and hi.z <= 5.501, "Mesh extends beyond longitudinal coupling planes or below rail origin")
	raw.free()

func tick_until_idle() -> void:
	for frame in range(2400):
		train._process(DT)
		if train.order == "idle": return
	check(false, "Timed out waiting for an actual cargo/movement order")

func add_track(kind: String, previous: Dictionary) -> Node3D:
	var placed: Node3D = rails.scene_for(kind).instantiate()
	var xf: Transform3D = rails.transform_for(kind,previous.position,previous.out)
	# Open terrain cells only inside this disposable fixture, as in the project's fork-power test.
	for cell in rails.cells_for(kind,xf):
		var tile: Dictionary = game.ground.tiles[cell.y*500+cell.x]
		tile.terrain = 0
		tile.buildable = true
	placed.assigned_depot = game.depot
	placed.transform = xf
	game.get_node("Entities/Rails").add_child(placed, true)
	check(rails.pieces.has(placed), "Test rail did not register: " + kind)
	return placed

func sample_overhang() -> float:
	# Measured from actual imported vertices while both bogies are well inside the real curve.
	var maximum := 0.0
	var r: float = curve.curve_radius * curve.world_scale
	for instance: MeshInstance3D in car.find_children("*","MeshInstance3D",true,false):
		for i in instance.mesh.get_surface_count():
			var vertices: PackedVector3Array = instance.mesh.surface_get_arrays(i)[Mesh.ARRAY_VERTEX]
			for vertex in vertices:
				var pt := curve.to_local(instance.to_global(vertex))
				maximum = maxf(maximum, absf(Vector2(pt.x-r,pt.z).length()-r))
	return maximum

func drive_to(point: Vector3, label: String, preceding_heading := Vector3.ZERO) -> Dictionary:
	var prior := train.global_position
	var path_length := 0.0
	var center_error := 0.0
	var height_error := 0.0
	var span_error := 0.0
	var alignment_error := 0.0
	var heading_error := 0.0
	var max_yaw := 0.0
	var overhang := 0.0
	var on_curve := 0
	train.command_move(point)
	for frame in range(2400):
		train._process(DT)
		if frame == 1 and preceding_heading != Vector3.ZERO:
			var turn := rad_to_deg(preceding_heading.angle_to(car.global_basis.z.normalized()))
			check(turn > 175.0, "Return route did not orient the nose back along the line")
			results["new_return_route_heading_change_deg"] = turn
		path_length += train.global_position.distance_to(prior)
		prior = train.global_position
		var track: Dictionary = train._line if not train._line.is_empty() else train._rest_line
		var arc_front: Array = RailLine.point(track,train._s)
		var s_rear: float = model.chord_back(track,train._s,model.length())
		var arc_rear: Array = RailLine.point(track,s_rear)
		for pair in [[front,arc_front],[rear,arc_rear]]:
			var sled: Node3D = pair[0]
			var p: Vector3 = pair[1][0]
			var actual: Vector3 = sled.global_position
			center_error = maxf(center_error,Vector2(actual.x-p.x,actual.z-p.z).length())
			height_error = maxf(height_error,absf(actual.y-model.sled_height*model.world_scale))
			var forward := sled.global_basis.z.normalized()
			alignment_error = maxf(alignment_error,rad_to_deg(forward.angle_to(pair[1][1])))
		span_error = maxf(span_error,absf(front.global_position.distance_to(rear.global_position)-model.length()))
		var rig_dir := (front.global_position-rear.global_position).normalized()
		heading_error = maxf(heading_error,rad_to_deg(car.global_basis.z.normalized().angle_to(rig_dir)))
		if train.piece == curve and train.along > 5.0 and train.along < curve.length()-5.0:
			on_curve += 1
			max_yaw = maxf(max_yaw,rad_to_deg(front.global_basis.z.angle_to(rear.global_basis.z)))
			if on_curve % 5 == 1: overhang = maxf(overhang,sample_overhang())
		if train.order == "idle": break
	var end_error := train.global_position.distance_to(point)
	check(train.order == "idle" and end_error < 0.26 and on_curve > 0 and path_length > curve.length(), label + " did not traverse the full curve")
	check(center_error < 0.0005 and height_error < 0.0001 and span_error < 0.002, label + " alignment or span error")
	check(alignment_error < 0.015 and heading_error < 0.015 and max_yaw > 10.0, label + " articulation did not follow the rail tangent")
	check(overhang <= curve.half_width()+0.005, label + " body exceeds guideway width at measured curve poses: " + str(overhang))
	return {"travelled_m":path_length, "target_error_m":end_error, "curve_interior_frames":on_curve,
		"max_sled_centreline_error_m":center_error, "max_ride_height_error_m":height_error,
		"max_sled_span_error_m":span_error, "max_sled_tangent_error_deg":alignment_error,
		"max_body_forward_error_deg":heading_error, "max_bogie_relative_yaw_deg":max_yaw,
		"max_radial_extent_from_centreline_m":overhang}

func run() -> void:
	check_import()
	game = load("res://scenes/maps/rail_exercise.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	for group in ["units","depots"]:
		for actor in get_nodes_in_group(group): actor.set_process(false)
	rails = game.get_node("RailNetwork")
	train = game.get_node("Entities/Units/Train")
	model = train.get_node("Visuals/Model")
	car = model.get_node("Car1")
	front = car.find_child("sled_cargo_front",true,false)
	rear = car.find_child("sled_cargo_rear",true,false)
	var indicator := car.find_child("cargo_car_indicator",true,false) as Node3D
	if front == null or rear == null or indicator == null:
		push_error("Required train parts unavailable")
		quit(1)
		return
	check(model.cars().size() == 1 and is_equal_approx(model.world_scale,0.6) and car.global_basis.get_scale().is_equal_approx(Vector3.ONE * 0.6), "Unexpected consist count or wrapper scale")
	check(train.storage_capacity == 300 and train.crate_slots() == 12 and train.fuel_rules == null, "Cargo/power contract changed")
	results["consist"] = {"cars":model.cars().size(), "wrapper_scale":model.world_scale, "capacity":train.storage_capacity,
		"crate_slots":train.crate_slots(), "sled_chord_world_m":model.length(), "speed_m_per_s":train.move_speed,
		"ride_height_pivot_world_m":front.global_position.y}
	check_teams()
	var rest := indicator.position
	train.manifest_add(&"iron")
	train.command_load(game.depot)
	tick_until_idle()
	var partial_rise := indicator.position.y-rest.y
	check(train.crate_units() == 25 and is_equal_approx(partial_rise,0.32), "First loaded crate did not raise the indicator")
	train.manifest_fill(&"iron")
	train.command_load(game.depot)
	tick_until_idle()
	var rise := indicator.position.y-rest.y
	check(train.crate_units() == 300 and train.crates.size() == 12 and is_equal_approx(rise,0.32), "Cargo indicator did not rise with a full manifest")
	var end: Dictionary = game.get_node("Entities/Rails/Track0").ends()[0]
	curve = add_track("curve",end)
	var branch := add_track("straight",curve.ends()[1])
	var extension := add_track("straight",branch.ends()[1])
	var outbound_goal: Vector3 = extension.point_at(3.0)
	var original_goal: Vector3 = game.get_node("Entities/Rails/Track4").point_at(2.5)
	results["curve_radius_world_m"] = curve.curve_radius*curve.world_scale
	results["guideway_half_width_world_m"] = curve.half_width()
	results["outbound"] = drive_to(outbound_goal,"outbound")
	var outward_heading := car.global_basis.z.normalized()
	results["inbound"] = drive_to(original_goal,"inbound",outward_heading)
	var east: Node3D = game.get_node("Entities/Buildings/EastDepot")
	var before: int = east.iron
	train.command_unload(east)
	tick_until_idle()
	check(train.crates.is_empty() and east.iron-before == 300 and indicator.position.is_equal_approx(rest), "Unload failed to deliver cargo and restore indicator")
	results["cargo"] = {"iron_delivered":east.iron-before, "indicator_rise_authored_m":rise,
		"indicator_rise_at_one_crate_authored_m":partial_rise,
		"indicator_rise_world_m":rise*model.world_scale, "unloaded_indicator_local":numbers(indicator.position)}
	results["failures"] = failures
	print("STREAMLINER_MEASUREMENTS=" + JSON.stringify(results))
	quit(0 if failures.is_empty() else 1)
