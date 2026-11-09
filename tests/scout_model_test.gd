extends SceneTree
# Headless: the Scout's rigged model (assets/models/units/scout.glb via scenes/models/scout_model.tscn).
# Idle and run loop, the shot starts the shoot clip early so the flash lands on it, the muzzle light
# follows the flash bone like the Blender driver does, and tracers leave the muzzle.
const Bounds = preload("res://scripts/units/selection_bounds.gd")
var game: Node3D
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> bool:
	if value: return true
	push_error(message); quit(1); return false
func actor(id: String, team: String, point: Vector3) -> Node3D:
	var unit = load("res://scenes/gameplay/"+id+".tscn").instantiate()
	unit.team = team
	game.get_node("Entities/Units").add_child(unit)
	unit.set_process(false)
	for cell in unit._claimed.duplicate(): unit._release(cell)
	unit.global_position = point
	return unit
func advance(model: Node3D, seconds: float) -> void:
	for i in range(ceili(seconds*60)):
		model.player.advance(1.0/60)
		model._process(1.0/60)
func run() -> void:
	game = load("res://scenes/maps/resource_skirmish.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	for node in get_nodes_in_group("units"): node.set_process(false)
	var origin := Vector3(180,0,180)
	var unit := actor("scout","player",origin)
	await process_frame
	var model = unit.get_node("Visuals/Model")
	if not check(model.scene_file_path == "res://scenes/models/scout_model.tscn" and model.has_method("set_motion"),"Scout does not use the animated model"): return
	model.set_process(false)
	var player: AnimationPlayer = model.player
	for clip in ["idle","run"]:
		if not check(player.has_animation(clip) and player.get_animation(clip).loop_mode == Animation.LOOP_LINEAR,"%s should loop" % clip): return
	if not check(player.has_animation("shoot") and player.get_animation("shoot").loop_mode == Animation.LOOP_NONE,"Shoot should play once"): return
	if not check(model.skeleton.get_bone_count() == 39 and model.flash_light != null and not model.flash_light.shadow_enabled and model.flash_light.omni_range <= 4.0 and model.get_node("Rig/Skater rig/Skeleton3D/flash/Muzzle flash").material_override != null,"Scout rig, muzzle light or flash material missing"): return
	# Size: on the ground and about 1.67 m tall; the gun points to -Z.
	var low := INF; var high := -INF
	for mesh in Bounds.meshes(unit):
		for i in range(8):
			var y: float = (mesh.global_transform*mesh.get_aabb().get_endpoint(i)).y
			low = minf(low,y); high = maxf(high,y)
	if not check(low > -0.25 and high > 1.4 and high < 2.1,"Scout size wrong: %.2f..%.2f" % [low,high]): return
	if not check(model.to_local(model.muzzle_position()).z < -0.2,"Scout gun should point to -Z: %s" % model.to_local(model.muzzle_position())): return
	# The flash bone drives the light: off at rest.
	model.set_motion(&"idle")
	advance(model,0.1)
	if not check(not model.flash_light.visible and is_equal_approx(model.flash_light.light_energy,0.0),"Muzzle light on at rest"): return
	# A first shot jumps straight to the firing frame: damage, flash and light together.
	var enemy := actor("infantry","enemy",origin+Vector3(0,0,-2.5))
	await process_frame
	unit._cooldown = 0.0
	var before: int = enemy.health
	unit._shoot(enemy)
	if not check(enemy.health < before and player.current_animation == "shoot" and absf(player.current_animation_position-model.shot_lead_time) < 0.02,"First shot should jump to the firing frame: %.3f" % player.current_animation_position): return
	model._process(0.0)
	if not check(model.flash_light.visible and model.flash_light.light_energy > 1.0,"Muzzle light did not fire: %.2f" % model.flash_light.light_energy): return
	var to_enemy: Vector3 = enemy.global_position-unit.global_position; to_enemy.y = 0
	var barrel: Vector3 = model.gun_direction()
	var flat := Vector3(barrel.x,0,barrel.z).normalized()
	if not check(flat.dot(to_enemy.normalized()) > 0.9 and absf(barrel.y) < 0.5,"Barrel should point at the target: %s vs %s" % [barrel,to_enemy]): return
	# The light has gone within a quarter second.
	advance(model,0.25)
	if not check(not model.flash_light.visible,"Muzzle light stayed on"): return
	# The next shot winds up before the cooldown ends, from the top of the clip, and deals no early damage.
	player.stop(); model._action_left = 0.0
	unit._cooldown = model.shot_lead_time-0.01
	var health: int = enemy.health
	unit._shoot(enemy)
	if not check(player.current_animation == "shoot" and player.current_animation_position < 0.03 and enemy.health == health,"Wind-up wrong: %.3f" % player.current_animation_position): return
	print("SCOUT_MODEL_TEST_PASSED"); quit()
