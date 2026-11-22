extends SceneTree
var errors: Array[String] = []
var checks := 0
const Paint = preload("res://scripts/components/team_paint.gd")

func expect(value: bool, message: String) -> void:
	checks += 1
	if not value:
		errors.append(message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var packed := load("res://scenes/models/arthurian_hound_model.tscn") as PackedScene
	expect(packed != null, "Model slot loads")
	if packed == null:
		finish({})
		return
	var first := packed.instantiate() as Node3D
	var second := packed.instantiate() as Node3D
	root.add_child(first)
	root.add_child(second)
	await process_frame
	expect(first.has_method("set_motion"), "Exposes the shared model animator")
	var skeletons := first.find_children("*", "Skeleton3D", true, false)
	expect(skeletons.size() == 1, "One skeleton")
	var player := first.get_node_or_null("Rig/AnimationPlayer") as AnimationPlayer
	expect(player != null, "Animation player at model path")
	var forward := 0.0
	if not skeletons.is_empty():
		var skeleton := skeletons[0] as Skeleton3D
		var head := skeleton.find_bone("Head")
		var body := skeleton.find_bone("Body")
		expect(head >= 0 and body >= 0, "Head and body joints exist")
		if head >= 0 and body >= 0:
			var h := first.to_local(skeleton.to_global(skeleton.get_bone_global_pose(head).origin))
			var b := first.to_local(skeleton.to_global(skeleton.get_bone_global_pose(body).origin))
			forward = h.z - b.z
			expect(forward < -0.1, "Head faces game forward -Z")
		expect(skeleton.get_bone_count() >= 16, "Full canine skeleton imported")
	if player:
		expect(player.has_animation("Rest"), "Rest clip present")
		expect(player.has_animation("Run"), "Run clip present")
		if player.has_animation("Rest") and player.has_animation("Run"):
			expect(player.get_animation("Rest").loop_mode == Animation.LOOP_LINEAR, "Rest loops")
			expect(player.get_animation("Run").loop_mode == Animation.LOOP_LINEAR, "Run loops")
			expect(absf(player.get_animation("Run").length - 20.0 / 24.0) < 0.06, "Run duration")
			for i in 4:
				first.set_motion(&"run", 1.45)
				await process_frame
			expect(first.current_clip() == &"Run", "Shared animator enters Run")
			for i in 4:
				first.set_motion(&"idle")
				await process_frame
			expect(first.current_clip() == &"Rest", "Shared animator returns to Rest")
	var team_surfaces := Paint.apply(first, "player")
	expect(team_surfaces > 0, "Team surfaces receive player paint")
	var unpainted := 0
	var repainted := 0
	for node in first.find_children("*", "MeshInstance3D", true, false):
		for i in node.mesh.get_surface_count():
			if node.mesh.surface_get_material(i).resource_name != "team_color" and node.get_surface_override_material(i) == null:
				unpainted += 1
	for node in second.find_children("*", "MeshInstance3D", true, false):
		for i in node.mesh.get_surface_count():
			if node.mesh.surface_get_material(i).resource_name == "team_color" and node.get_surface_override_material(i) == null:
				repainted += 1
	expect(unpainted > 0, "Fixed materials retain their own finish")
	expect(repainted > 0, "Second instance remains independent")
	var report := {"checks": checks, "errors": errors, "forward_head_offset": forward,
		"painted_surfaces": team_surfaces, "independent_surfaces": repainted}
	first.queue_free()
	second.queue_free()
	finish(report)

func finish(report: Dictionary) -> void:
	print(JSON.stringify(report))
	quit(1 if not errors.is_empty() else 0)
