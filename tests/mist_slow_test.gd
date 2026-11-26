extends SceneTree
# Headless (item 14 of docs/BALANCE_IMPLEMENTATION_HANDOFF.md, docs/MIST_AND_SLOW.md): a Grail Sentinel casts Mist for
# 40 reserve points at a point within 20 m. For 8 s units in the 8 m cloud can be seen, and targeted, only from within
# 8 m. Slow, researched at the Forge, costs 25 points: enemy units within 5 m move at 60% of their speed for 5 s.
var game: Node3D
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> bool:
	if value: return true
	push_error(message); quit(1); return false
func spawn(id: String, team: String, point: Vector3) -> Node3D:
	var unit = load("res://scenes/gameplay/%s.tscn" % id).instantiate()
	unit.team = team
	unit.position = point
	game.get_node("Entities/Units").add_child(unit,true)
	unit.set_process(false)
	return unit
func place(unit: Node3D, point: Vector3) -> void:
	unit.global_position = point
func cast(sentinel: Node3D, kind: String, point: Vector3) -> bool:
	sentinel.command_spell(kind,point)
	for i in range(30*30):
		sentinel._process(1.0/30)
		if sentinel.order == "idle": return true
	return false
func run() -> void:
	var forge = load("res://scenes/gameplay/forge.tscn").instantiate()
	var research: Array = forge.research
	forge.free()
	if not check(research.any(func(r): return r.research_id == Research.SLOW and r.food_cost == 100 and r.iron_cost == 100),"The Forge should research Slow for 100 F / 100 I"): return
	game = load("res://scenes/maps/arthurian_skirmish.tscn").instantiate()
	root.add_child(game)
	for i in range(3): await process_frame
	for name in ["EnemyPlayer","KnightsPlayer"]:
		var ai = game.get_node_or_null(name)
		if ai != null: ai.set_process(false)
	var fog = get_first_node_in_group("fog_of_war")
	if fog != null: fog.set_process(false)
	var keep: Node3D = null
	for node in get_nodes_in_group("keeps"):
		if node.team == "player": keep = node
	var spot: Vector3 = keep.global_position+Vector3(40,0,30)
	var sentinel := spawn("grail_sentinel","player",spot+Vector3(-10,0,0))
	place(sentinel,spot+Vector3(-10,0,0))
	sentinel.med_reserve = 200
	var marine := spawn("round_table_marine","player",spot)
	place(marine,spot)
	var watcher := spawn("infantry","enemy",spot+Vector3(0,0,14))
	place(watcher,spot+Vector3(0,0,14))
	sentinel.command_attack(watcher,true)
	if not check(sentinel.order == "idle" and not sentinel.fires_at(watcher) and sentinel.projectile_scene == null,"Sentinel must refuse even forced fire"): return
	marine.health -= 10
	place(marine,sentinel.global_position + Vector3.RIGHT * 3.0)
	sentinel.command_heal(marine)
	sentinel._process(0.1)
	var caster_model = sentinel.get_node("Visuals/Model")
	caster_model._process(0.1)
	if not check(caster_model.current_clip() == &"Heal","The grail should stay offered while tending a patient"): return
	sentinel._process(1.0)
	if not check(marine.health == marine.max_health and caster_model.get_node_or_null("GrailPulse") != null,"A successful heal should launch a pulse"): return
	place(marine,spot)
	sentinel.med_reserve = 200
	if fog != null: fog.update_now()
	if not check(watcher.team_sees(marine),"Before the Mist the enemy 14 m off should see the Marine"): return
	# Mist.
	if not check(cast(sentinel,"mist",spot) and sentinel.med_reserve == 160,"Mist should cost 40 reserve points (%d left, %s)" % [sentinel.med_reserve,sentinel.state]): return
	var mists := get_nodes_in_group("mists")
	if not check(mists.size() == 1 and mists[0].global_position.distance_to(spot) < 0.1,"One Mist should stand on the point"): return
	var mist = mists[0]
	mist.set_process(false)
	# The art: the Sentinel raises its arm with a burst of light, and the cloud's look follows its seconds.
	var model = sentinel.get_node("Visuals/Model")
	if not check(model.acting() and model.current_clip() == &"Mist","The Sentinel should play its Cast clip (%s)" % model.current_clip()): return
	if not check(model.grail.get_children().any(func(n): return n.name.begins_with("SentinelCastMist")),"The Mist cast burst should show on the Sentinel"): return
	var look = mist.get_node("Visuals")
	if not check(look.progress().x < 0.2 and look.scale.x < mist.radius,"The Mist should start billowing in"): return
	if not check(not watcher.team_sees(marine),"In the Mist the Marine is hidden from an enemy 14 m off"): return
	if fog != null:
		fog.update_now()
		if not check(fog.shows(marine) or fog.viewer == "player","The viewer's own units always show"): return
	place(watcher,spot+Vector3(0,0,7))
	if not check(watcher.team_sees(marine),"An enemy within 8 m sees into the Mist"): return
	place(watcher,spot+Vector3(0,0,14))
	mist._process(8.1)
	await process_frame
	if not check(get_nodes_in_group("mists").is_empty() and watcher.team_sees(marine),"After 8 s the Mist is gone and the Marine seen again"): return
	# Slow: needs the research.
	if not check(sentinel.spell_blocker("slow").contains("Research"),"Slow needs the research first"): return
	Research.complete(game,"player",Research.SLOW)
	var near := spawn("infantry","enemy",spot+Vector3(3,0,0))
	var far := spawn("infantry","enemy",spot+Vector3(8,0,0))
	place(near,spot+Vector3(3,0,0))
	place(far,spot+Vector3(8,0,0))
	if not check(cast(sentinel,"slow",spot) and sentinel.med_reserve == 135,"Slow should cost 25 reserve points (%d left)" % sentinel.med_reserve): return
	if not check(model.current_clip() == &"Slow" and model.hourglass.get_child_count() == 1,"Slow uses the shield glass"): return
	var fields := root.find_children("*","Node3D",true,false).filter(func(n): return n.name.begins_with("SlowField"))
	if not check(fields.size() == 1 and is_equal_approx(fields[0].radius,5.0),"One Slow sigil of 5 m should mark the point"): return
	if not check(is_equal_approx(near.speed_scale(),0.6) and is_equal_approx(far.speed_scale(),1.0) and is_equal_approx(marine.speed_scale(),1.0),"Only enemy units within 5 m are slowed to 60%"): return
	near._process(5.1)
	if not check(is_equal_approx(near.speed_scale(),1.0),"The Slow wears off after 5 s"): return
	# Not enough reserve.
	sentinel.med_reserve = 20
	if not check(sentinel.spell_blocker("mist").contains("reserve") and sentinel.spell_blocker("slow").contains("reserve"),"Casting needs the reserve points"): return
	# The card.
	var hud = game.get_node("Interface")
	game.selected_building = null
	for node in get_nodes_in_group("units"): node.set_selected(node == sentinel)
	hud._process(0)
	if not check(not hud.desired_buttons.has("Attack") and hud.desired_buttons.has("Mist") and hud.desired_buttons.has("Slow"),"The Sentinel card should show Mist and Slow: %s" % [hud.desired_buttons]): return
	for id in {"Mist":"sl_mist.png","Slow":"sl_slow.png"}.keys():
		var icon: Texture2D = hud.card.get_node(id).icon
		if not check(icon != null and icon.resource_path.get_file() == "sl_%s.png" % id.to_lower(),"The %s tile should show its own card" % id): return
	game.queue_free()
	await process_frame
	print("MIST_SLOW_TEST_PASSED")
	quit(0)
