extends MeshInstance3D
func configure(start: Vector3, end: Vector3, team: String) -> void:
	global_position = (start+end)*0.5
	look_at(end,Vector3.UP)
	scale = Vector3(1,1,start.distance_to(end))
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(1,0.82,0.3) if team == "player" else Color(1,0.2,0.15)
	material_override = material
	get_tree().create_timer(0.1).timeout.connect(queue_free)
