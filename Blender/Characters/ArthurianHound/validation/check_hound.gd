extends SceneTree
## Verify the imported model's ground placement, dimensions, rig, paint and rest clip.
var errors: Array[String] = []
var checks := 0

func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		errors.append(message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var scene := load("res://export/arthurian_hound.glb") as PackedScene
	expect(scene != null, "GLB imports as a packed scene")
	if scene == null:
		finish({})
		return
	var hound := scene.instantiate() as Node3D
	root.add_child(hound)
	await process_frame
	var meshes := hound.find_children("*", "MeshInstance3D", true, false)
	var skeletons := hound.find_children("*", "Skeleton3D", true, false)
	var players := hound.find_children("*", "AnimationPlayer", true, false)
	expect(not meshes.is_empty(), "Contains visible meshes")
	expect(not skeletons.is_empty(), "Contains an animation skeleton")
	expect(not players.is_empty(), "Contains an animation player")
	var materials := {}
	var bounds := AABB()
	var first := true
	for node in meshes:
		var mesh_node := node as MeshInstance3D
		if mesh_node.mesh == null:
			continue
		for surface in mesh_node.mesh.get_surface_count():
			var mat := mesh_node.mesh.surface_get_material(surface)
			if mat != null:
				materials[mat.resource_name] = true
		var box := mesh_node.mesh.get_aabb()
		for x in [0.0, 1.0]:
			for y in [0.0, 1.0]:
				for z in [0.0, 1.0]:
					var p := mesh_node.global_transform * (box.position + box.size * Vector3(x, y, z))
					if first:
						bounds = AABB(p, Vector3.ZERO)
						first = false
					else:
						bounds = bounds.expand(p)
	expect(bounds.position.y > -0.12 and bounds.position.y < 0.12, "Origin rests near the floor")
	expect(bounds.size.y > 0.7 and bounds.size.y < 2.5, "Height is in a reasonable canine range")
	expect(materials.has("team_color"), "Includes team color material")
	if not players.is_empty():
		var player := players[0] as AnimationPlayer
		expect(player.has_animation("Rest"), "Provides Rest animation")
		if player.has_animation("Rest"):
			player.play("Rest")
			player.seek(0.0, true)
			await process_frame
	var report := {"checks": checks, "errors": errors, "bounds_position": bounds.position,
		"bounds_size": bounds.size, "mesh_count": meshes.size(), "materials": materials.keys()}
	hound.queue_free()
	finish(report)

func finish(report: Dictionary) -> void:
	print(JSON.stringify(report))
	quit(1 if not errors.is_empty() else 0)
