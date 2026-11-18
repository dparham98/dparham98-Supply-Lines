extends SceneTree
## Team paint on unit models (docs/TEAM_MARKERS.md): the team surfaces of each model take the paint of
## the unit's side, nothing else is overridden, and models with no team surface are left alone.
const TeamPaint = preload("res://scripts/components/team_paint.gd")
## Unit scene and the least number of surfaces it paints.
const PAINTED := {"infantry": 1, "scout": 1, "grenadier": 1, "motorcycle": 2, "drone": 2, "cargo_vehicle": 3, "depot_truck": 3, "train": 1}
const UNPAINTED := ["tank", "ubermech", "hostile"]
func _initialize() -> void:
	for id in PAINTED:
		for team in ["player","enemy"]:
			var unit = load("res://scenes/gameplay/%s.tscn" % id).instantiate()
			unit.team = team
			unit._paint_team()
			var model: Node = unit.get_node("Visuals/Model")
			var names := TeamPaint.material_names(model)
			var painted := 0
			for node in model.find_children("*","MeshInstance3D",true,false):
				var mesh_node := node as MeshInstance3D
				if mesh_node.mesh == null: continue
				for i in mesh_node.mesh.get_surface_count():
					var base := mesh_node.mesh.surface_get_material(i)
					var override := mesh_node.get_surface_override_material(i)
					if base != null and base.resource_name in names:
						assert(override == TeamPaint.paint_for(team), "%s %s" % [id, base.resource_name])
						painted += 1
					else:
						assert(override == null or not override.resource_name.begins_with("team_paint"), id)
			assert(painted >= PAINTED[id], "%s painted %d" % [id, painted])
			unit.free()
	for id in UNPAINTED:
		var unit = load("res://scenes/gameplay/%s.tscn" % id).instantiate()
		unit._paint_team()
		assert(TeamPaint.apply(unit.get_node("Visuals/Model"),"enemy") == 0, id)
		unit.free()
	# A side the game does not know is painted neutral.
	assert(TeamPaint.paint_for("someone") == TeamPaint.paint_for("neutral"))
	print("TEAM_PAINT_CHECKS_PASSED")
	quit()
