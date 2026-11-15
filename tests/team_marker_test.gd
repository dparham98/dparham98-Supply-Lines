extends SceneTree
## Team markers (docs/TEAM_MARKERS.md): every unit scene carries one under Visuals, sized to its mesh,
## left out of picking and painted in its side's colour.
const TeamColors = preload("res://scripts/units/team_colors.gd")
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
		unit.free()
	# A unit made for another side (Depot production sets team before adding it) takes that side's colour.
	var infantry = load("res://scenes/gameplay/infantry.tscn").instantiate()
	infantry.team = "enemy"
	infantry._paint_team()
	assert(Color(infantry.get_node("Visuals/TeamMarker").get_instance_shader_parameter(&"team_color")).is_equal_approx(TeamColors.of("enemy")))
	infantry.free()
	assert(load("res://scripts/ui/map_overlay.gd").TEAM_COLORS == TeamColors.COLORS)
	print("TEAM_MARKER_CHECKS_PASSED")
	quit()
