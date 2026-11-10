extends SceneTree
# Headless: a dead tank leaves the game at once and its model plays one of three deaths on the real hull,
# turret and barrel, then removes itself. The cook-off throws the turret clear, the bleed-out sheds a track
# and rolls over, and the overload spins the turret and blows the hatches.
const Death = preload("res://scripts/components/tank_death.gd")
const H := "Tank/Tank_Root/Tank_Hull/"
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
func at(fx: Node3D, seconds: float) -> void:
	fx.player.seek(seconds,true)
	fx._process(0.0)
func kill(index: int, origin: Vector3) -> Node3D:
	var unit := actor("tank","player",origin)
	await process_frame
	var model: Node3D = unit.get_node("Visuals/Model")
	var only: Array[PackedScene] = [model.death_scenes[index]]
	model.death_scenes = only
	# Aimed off to one side, the way a tank in a fight would be.
	model._yaw = 0.9
	model.turret.transform.basis = Basis(Vector3.UP,0.9)
	var where: Vector3 = model.global_position
	unit.take_damage(unit.health)
	if not check(unit.is_queued_for_deletion() and not unit.is_in_group("units"),"Death %d: the unit should leave the game at once" % index): return null
	if not check(model.get_parent() == game and model.dying(),"Death %d: the wreck should stay in the world" % index): return null
	if not check(model.global_position.is_equal_approx(where),"Death %d: the wreck moved when it was left behind" % index): return null
	await process_frame
	if not check(not is_instance_valid(unit),"Death %d: the unit should be freed" % index): return null
	return model
func finishes(model: Node3D, fx: Node3D, index: int) -> bool:
	at(fx,fx.player.current_animation_length-0.02)
	if not check(not fx.light.visible,"Death %d: the light should be out at the end" % index): return false
	if not check(model.get_node(H.trim_suffix("/")).global_position.y < -1.5,"Death %d: the wreck should have sunk" % index): return false
	fx.player.advance(0.2)
	await process_frame
	await process_frame
	return check(not is_instance_valid(model),"Death %d: the wreck should remove itself" % index)
func run() -> void:
	game = load("res://scenes/maps/resource_skirmish.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	for node in get_nodes_in_group("units"): node.set_process(false)
	var origin := Vector3(180,0,180)
	var spare: Node3D = load("res://scenes/models/tank_model.tscn").instantiate()
	var kinds: int = spare.death_scenes.size()
	spare.free()
	if not check(kinds == 3,"The tank should have three deaths"): return
	# Left to chance, every death turns up. Missing one of three in 45 tries is about a one in three million fluke.
	var chosen := {}
	for i in range(45):
		var wreck: Node3D = load("res://scenes/models/tank_model.tscn").instantiate()
		root.add_child(wreck)
		wreck.play_death()
		chosen[wreck.get_child(wreck.get_child_count()-1).name] = true
		wreck.free()
	if not check(chosen.size() == 3,"Random pick only produced %s" % [chosen.keys()]): return
	var clips := [["TankDeathCookoff",6.0],["TankDeathBleed",5.5],["TankDeathOverload",5.0]]
	for index in range(3):
		var model: Node3D = await kill(index,origin)
		if model == null: return
		var effects := model.get_children().filter(func(n): return n.get_script() == Death)
		if not check(effects.size() == 1 and effects[0].name == clips[index][0],"Death %d: wrong effect" % index): return
		var fx: Node3D = effects[0]
		var clip: Animation = fx.player.get_animation("Death")
		if not check(clip.loop_mode == Animation.LOOP_NONE and absf(clip.length-clips[index][1]) < 0.1,"Death %d: length %.2f" % [index,clip.length]): return
		var hull: Node3D = model.get_node(H.trim_suffix("/"))
		var turret: Node3D = model.turret
		var mount: Node3D = model.get_node(H+"Tank_Turret/Barrel_Mount")
		# The stand-ins start exactly where the real parts rest, and the aim carries over.
		at(fx,0.0)
		if not check(hull.transform.is_equal_approx(Transform3D.IDENTITY),"Death %d: hull should start at rest, got %s" % [index,hull.transform]): return
		if not check(turret.position.distance_to(Vector3(0,2.16,-0.5)) < 0.01,"Death %d: turret should start in its ring, got %s" % [index,turret.position]): return
		if not check(mount.position.distance_to(Vector3(0,0.46,1.95)) < 0.01,"Death %d: mount should start at rest, got %s" % [index,mount.position]): return
		if not check((turret.transform.basis*Vector3.FORWARD).dot(Basis(Vector3.UP,0.9)*Vector3.FORWARD) > 0.999,"Death %d: the turret should keep its aim at first" % index): return
		# Nothing on the wreck answers to the game any more, and it burns on from here.
		model.aim_at(origin+Vector3(0,0,30))
		var held: Basis = turret.transform.basis
		model._process(0.1)
		if not check(turret.transform.basis.is_equal_approx(held),"Death %d: the turret should not aim once dead" % index): return
		var pool: Node3D = fx.get_node("Model/Oil_Pool")
		if not check(pool.scale.x < 0.01,"Death %d: no oil at the first moment" % index): return
		var scorch: StandardMaterial3D = model.get_node(H.trim_suffix("/")).material_overlay
		if not check(scorch != null and scorch.albedo_color.a < 0.05,"Death %d: the tank should start unburnt" % index): return
		if not check(model.muzzle.find_children("*","MeshInstance3D",true,false).all(func(m): return m.material_overlay == null),"Death %d: the muzzle flash should not be scorched" % index): return
		match index:
			0:
				at(fx,0.5)
				if not check(turret.position.distance_to(Vector3(0,2.16,-0.5)) < 0.3,"Cook-off: the turret should still be on at 0.5 s"): return
				if not check(scorch.albedo_color.a < 0.05,"Cook-off: no burning before the blast"): return
				var lit := false
				for i in range(14):
					at(fx,0.8+i*0.03)
					lit = lit or fx.light.light_energy > 8.0
				if not check(lit,"Cook-off: the blast should flare"): return
				at(fx,1.5)
				if not check(turret.global_position.y > 3.0,"Cook-off: the turret should be in the air, y %.2f" % turret.global_position.y): return
				at(fx,3.0)
				var flat := Vector2(turret.global_position.x-model.global_position.x,turret.global_position.z-model.global_position.z).length()
				if not check(turret.global_position.y < 0.5 and flat > 3.0,"Cook-off: the turret should land clear of the hull, y %.2f, %.2f away" % [turret.global_position.y,flat]): return
				if not check(scorch.albedo_color.a > 0.7,"Cook-off: the hull should be charred"): return
				if not check(fx.light.visible and pool.scale.x > 2.0,"Cook-off: fire and oil should be going at 3 s"): return
				if not check(mount.global_position.y > 0.0,"Cook-off: the barrel should stay above ground"): return
			1:
				var track: Node3D = model.get_node(H+"Track_Links_L")
				at(fx,0.2)
				if not check(track.visible,"Bleed-out: the track should be on at first"): return
				at(fx,0.7)
				if not check(not track.visible and model.get_node(H+"Track_Links_R").visible,"Bleed-out: only one track should come off"): return
				at(fx,3.0)
				var roll := rad_to_deg(hull.transform.basis.get_euler().z)
				if not check(absf(roll) > 3.0,"Bleed-out: the hull should list, %.1f degrees" % roll): return
				if not check((turret.transform.basis*Vector3.FORWARD).dot(Basis(Vector3.UP,0.9)*Vector3.FORWARD) > 0.6,"Bleed-out: the turret should droop from where it aimed"): return
				if not check(pool.scale.x > 3.0,"Bleed-out: oil should spread: %.2f" % pool.scale.x): return
			2:
				var seen := []
				# Close together, so that a whole turn between samples cannot look like standing still.
				for i in range(12):
					at(fx,0.8+i*0.1)
					seen.append(turret.transform.basis*Vector3.FORWARD)
				for i in range(11):
					if not check(seen[i].dot(seen[i+1]) < 0.99,"Overload: the turret should keep spinning"): return
				var hatch: Node3D = model.get_node(H+"Tank_Turret/Turret_Hatch")
				at(fx,1.9)
				if not check(hatch.visible and model.get_node(H+"Hull_Driver_Hatch").visible,"Overload: hatches should be on before the blast"): return
				at(fx,2.3)
				if not check(not hatch.visible and not model.get_node(H+"Hull_Driver_Hatch").visible,"Overload: hatches should blow"): return
				at(fx,3.0)
				if not check(scorch.albedo_color.a > 0.5 and pool.scale.x > 1.0,"Overload: burnt and leaking by 3 s"): return
		if not await finishes(model,fx,index): return
	print("TANK_DEATH_TEST_PASSED"); quit()
