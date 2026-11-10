extends SceneTree
# Headless: killing an Infantry or Scout removes the unit at once and leaves its model behind to play the
# death clip: it falls, lies there with oil spreading for a couple of seconds, then removes itself.
# A unit whose model has no death clip still just disappears.
const Burst = preload("res://scripts/components/burst_effect.gd")
const FX_LINGER_START := 2.0
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
func head_height(model: Node3D) -> float:
	var bone: int = model.skeleton.find_bone("head")
	model.skeleton.force_update_all_bone_transforms()
	return (model.skeleton.global_transform*model.skeleton.get_bone_global_pose(bone).origin).y
func at(model: Node3D, fx: Node3D, seconds: float) -> void:
	model.player.seek(seconds,true)
	fx.player.seek(seconds,true)
	fx._process(0.0)
func run() -> void:
	game = load("res://scenes/maps/resource_skirmish.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	for node in get_nodes_in_group("units"): node.set_process(false)
	var origin := Vector3(180,0,180)
	for setup in [["infantry",&"Die"],["scout",&"die"]]:
		var id: String = setup[0]
		var unit := actor(id,"player",origin)
		await process_frame
		var model: Node3D = unit.get_node("Visuals/Model")
		if not check(model.has_death_clip() and model.death_clip == setup[1],"%s has no death clip" % id): return
		var clip: Animation = model.player.get_animation(setup[1])
		if not check(clip.loop_mode == Animation.LOOP_NONE,"%s death should play once" % id): return
		if not check(clip.length > 3.9 and clip.length < 4.4,"%s death length %.2f" % [id,clip.length]): return
		var standing := head_height(model)
		if not check(standing > 1.2,"%s should start upright: %.2f" % [id,standing]): return
		var turned: Vector3 = model.global_position
		var facing: Basis = model.global_basis
		# Death: the unit is gone from the game immediately; the model stays exactly where it was.
		unit.take_damage(unit.health)
		if not check(unit.is_queued_for_deletion() and not unit.is_in_group("units"),"%s should leave the game at once" % id): return
		if not check(model.get_parent() == game and model.dying(),"%s corpse should be left in the world" % id): return
		if not check(model.global_position.is_equal_approx(turned) and model.global_basis.is_equal_approx(facing),"%s corpse moved when it was left behind" % id): return
		if not check(model.current_clip() == setup[1] and model.player.is_playing(),"%s should be playing death, got %s" % [id,model.current_clip()]): return
		var effects := model.get_children().filter(func(n): return n.get_script() == Burst)
		if not check(effects.size() == 1,"%s should have one oil effect" % id): return
		var fx: Node3D = effects[0]
		if not check(fx.player.has_animation("Death") and is_equal_approx(fx.player.get_animation("Death").length,clip.length),"%s effect should match the clip" % id): return
		var pool: Node3D = fx.get_node("Model/Oil_Pool")
		if not check(pool.scale.x < 0.01,"%s oil should not exist at the moment of death" % id): return
		await process_frame
		if not check(not is_instance_valid(unit),"%s unit should be freed" % id): return
		model.player.advance(0.2)    # past the blend out of the idle pose, which seek() does not advance
		if not check(is_instance_valid(model),"%s corpse should outlive the unit" % id): return
		# Between the shot and the end the animator must not fall back to idle.
		model._process(1.0/60)
		if not check(model.current_clip() == setup[1],"%s fell out of its death clip" % id): return
		# Down by the time it has finished falling, and still there a couple of seconds later.
		at(model,fx,FX_LINGER_START)
		var lying := head_height(model)
		if not check(lying < 0.75,"%s should be down at %.1f s, head at %.2f" % [id,FX_LINGER_START,lying]): return
		var pool_early: float = pool.scale.x
		at(model,fx,3.7)
		if not check(head_height(model) < 0.75,"%s corpse should still be lying there at 3.7 s" % id): return
		if not check(pool.scale.x > pool_early and pool.scale.x > 0.4,"%s oil should spread while it lies there: %.2f -> %.2f" % [id,pool_early,pool.scale.x]): return
		if not check(not model.flash_light.visible,"%s muzzle light should stay off" % id): return
		# The sparks flicker the light at some point during the death.
		var lit := false
		for i in range(100):
			at(model,fx,clip.length*i/100.0)
			lit = lit or fx.light.visible
		if not check(lit,"%s sparks should light up" % id): return
		# Then it is gone, with nothing left behind.
		at(model,fx,clip.length-0.02)
		if not check(fx.get_node("Model/Oil_Pool").scale.x < 0.1,"%s oil should clear with the corpse" % id): return
		model.player.advance(0.2)
		await process_frame
		await process_frame
		if not check(not is_instance_valid(model),"%s corpse should remove itself" % id): return
	# A model without a clip leaves nothing behind.
	var hostile := actor("hostile","enemy",origin)
	await process_frame
	var before := game.get_child_count()
	var prototype: Node3D = hostile.get_node("Visuals/Model")
	hostile.take_damage(hostile.health)
	await process_frame
	if not check(not is_instance_valid(hostile) and not is_instance_valid(prototype) and game.get_child_count() <= before,"A model with no death clip should simply go"): return
	print("CYBORG_DEATH_TEST_PASSED"); quit()
