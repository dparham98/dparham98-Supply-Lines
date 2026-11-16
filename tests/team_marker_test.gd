extends SceneTree
## Team markers (docs/TEAM_MARKERS.md): every unit scene carries one under Visuals, sized to its mesh,
## left out of picking, painted in its side's colour, and shown only while the unit is selected.
const TeamColors = preload("res://scripts/units/team_colors.gd")
const BUILDINGS := ["barracks","depot","energy_generator","iron_mine","tank_factory"]
const UNITS := ["infantry","scout","grenadier","tank","motorcycle","drone","ubermech","cargo_vehicle","depot_truck","hostile","train"]
func _initialize() -> void:
	var material = load("res://assets/materials/units/team_marker.tres")
	for id in UNITS:
		var unit = load("res://scenes/gameplay/%s.tscn" % id).instantiate()
		var marker := unit.get_node_or_null("Visuals/TeamMarker") as MeshInstance3D
		assert(marker != null, id)
		assert(marker.has_meta(&"not_selectable"), id)
		assert(marker.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, id)
		var mesh := marker.mesh as PlaneMesh
		assert(mesh != null and mesh.material == material, id)
		var half: Vector2 = marker.get_instance_shader_parameter(&"half_size")
		assert(half.is_equal_approx(mesh.size/2.0), id)
		# On the ground, apart from the Drone's, which hangs just under it at 12 m.
		var height: float = unit.get_node("Visuals").position.y+marker.position.y
		assert(absf(height-(11.85 if id == "drone" else 0.0)) < 0.5, id)
		unit._paint_team()
		assert(Color(marker.get_instance_shader_parameter(&"team_color")).is_equal_approx(TeamColors.of(unit.team)), id)
		# Hidden until selected; the marker is the selection indicator, so there is no separate ring.
		assert(not marker.visible and unit.get_node_or_null("SelectionRing") == null, id)
		unit.team = "player"
		unit.set_selected(true)
		assert(marker.visible, id)
		unit.set_selected(false)
		assert(not marker.visible, id)
		unit.free()
	# A unit made for another side (Depot production sets team before adding it) takes that side's colour.
	var infantry = load("res://scenes/gameplay/infantry.tscn").instantiate()
	infantry.team = "enemy"
	infantry._paint_team()
	# Enemy units cannot be selected, so their marker never shows.
	infantry.set_selected(true)
	assert(not infantry.get_node("Visuals/TeamMarker").visible)
	assert(Color(infantry.get_node("Visuals/TeamMarker").get_instance_shader_parameter(&"team_color")).is_equal_approx(TeamColors.of("enemy")))
	infantry.free()
	assert(load("res://scripts/ui/map_overlay.gd").TEAM_COLORS == TeamColors.COLORS)
	# Buildings carry a marker too, hidden in the scene, sized to cover the model's corners.
	for id in BUILDINGS:
		var building = load("res://scenes/gameplay/%s.tscn" % id).instantiate()
		var marker := building.get_node_or_null("Visuals/TeamMarker") as MeshInstance3D
		assert(marker != null and not marker.visible and marker.has_meta(&"not_selectable"), id)
		assert(marker.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF and absf(marker.position.y) < 0.2, id)
		var mesh := marker.mesh as PlaneMesh
		assert(mesh != null and mesh.material == material, id)
		var half: Vector2 = marker.get_instance_shader_parameter(&"half_size")
		assert(half.is_equal_approx(mesh.size/2.0), id)
		var box := AABB(); var first := true
		var stack: Array = [building.get_node("Visuals/Model")]
		while not stack.is_empty():
			var part = stack.pop_back()
			stack.append_array(part.get_children())
			if not part is MeshInstance3D or part.mesh == null: continue
			var t: Transform3D = Transform3D(); var node: Node = part
			while node != building: t = node.transform*t; node = node.get_parent()
			box = t*part.get_aabb() if first else box.merge(t*part.get_aabb()); first = false
		for corner in [box.position, box.end, Vector3(box.position.x,0,box.end.z), Vector3(box.end.x,0,box.position.z)]:
			assert(Vector2(corner.x-marker.position.x,corner.z-marker.position.z).length() <= half.x, id)
		building.free()
	# Selecting a building shows its marker in its side's colour; changing the selection hides it again.
	var game = load("res://scripts/gameplay/skirmish.gd").new()
	var depot = load("res://scenes/gameplay/depot.tscn").instantiate()
	var mine = load("res://scenes/gameplay/iron_mine.tscn").instantiate()
	depot.team = "enemy"
	game.selected_building = depot
	var depot_marker: GeometryInstance3D = depot.get_node("Visuals/TeamMarker")
	assert(depot_marker.visible and Color(depot_marker.get_instance_shader_parameter(&"team_color")).is_equal_approx(TeamColors.of("enemy")))
	game.selected_building = mine
	assert(not depot_marker.visible and mine.get_node("Visuals/TeamMarker").visible)
	game.selected_building = null
	assert(not mine.get_node("Visuals/TeamMarker").visible)
	depot.free(); mine.free(); game.free()
	print("TEAM_MARKER_CHECKS_PASSED")
	quit()
