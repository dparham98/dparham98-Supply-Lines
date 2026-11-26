extends SceneTree
# Headless integration test for the Arthurian Knights faction:
# - All 6 UnitStats .tres resources and 8 possessed 3D models (the Chapterhouse included) + TeamPaint (including team_color_shadow)
# - Keep model animations (Idle, Build, Train, LaunchBalloon, Die + KeepDeathFx)
# - Keep founding from 50 Wood + 50 Iron site materials with zero covering stockpile/payer
# - Keep training Forester Maiden & Warhound; Chapterhouse training all 4 units with Food + Iron
# - Grail Sentinel medical healing (Keep Food -> carried 120 HP reserve -> refuses vehicles -> stops dry -> crate refill)
# - Warhound Forest mobility + Arthurian HUD command cards, StoragePanel Food legend & unit portraits.

const TeamPaint = preload("res://scripts/components/team_paint.gd")
const Burst = preload("res://scripts/components/burst_effect.gd")

var game: Node3D
var network: Node
var hud: CanvasLayer

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> bool:
	if ok: return true
	push_error(message)
	quit(1)
	return false

func extent(node: Node3D, space: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for mesh in node.find_children("*", "MeshInstance3D", true, false):
		var m := mesh as MeshInstance3D
		if m.mesh == null or not m.is_visible_in_tree(): continue
		for i in range(8):
			var p: Vector3 = space.global_transform.affine_inverse() * (m.global_transform * m.get_aabb().get_endpoint(i))
			if first:
				box = AABB(p, Vector3.ZERO)
				first = false
			else:
				box = box.expand(p)
	return box

func run() -> void:
	root.size = Vector2i(1280, 900)
	# 1. All 6 new UnitStats resources validate cleanly.
	for id in ["forester_maiden", "warhound", "round_table_marine", "grail_sentinel", "questing_marine", "azure_dragon"]:
		var stats: UnitStats = load("res://assets/units/%s.tres" % id)
		if not check(stats != null and stats.validation_errors().is_empty(), "Invalid UnitStats %s: %s" % [id, stats.validation_errors() if stats else "null"]): return

	# 2. All 8 Arthurian model wrappers load, animate, and accept TeamPaint.
	var model_expectations := {
		"keep_model": ["Idle", "Build", "Train", "LaunchBalloon", "Die"],
		"chapterhouse_model": ["Idle", "Build", "Print", "Die"],
		"forester_maiden_model": ["Walk", "Chop", "Gather", "Carry", "Build", "Till"],
		"warhound_model": ["Rest", "Run", "Attack", "Die"],
		"round_table_marine_model": ["Run", "Shoot"],
		"grail_sentinel_model": ["Run"],
		"questing_marine_model": ["Run"],
		"azure_dragon_model": ["Rest", "Walk", "FireBreath"],
	}
	for model_name in model_expectations:
		var model: Node3D = load("res://scenes/models/%s.tscn" % model_name).instantiate()
		root.add_child(model)
		await process_frame
		var box := extent(model, model)
		if not check(box.size.length() > 0.3, "%s empty AABB: %s" % [model_name, box]): return
		var player: AnimationPlayer = model.player
		if not check(player != null, "%s missing AnimationPlayer" % model_name): return
		for clip in model_expectations[model_name]:
			if not check(player.has_animation(clip), "%s missing clip %s (has %s)" % [model_name, clip, player.get_animation_list()]): return
		var painted := TeamPaint.apply(model, "player")
		if not check(painted >= 1, "%s painted 0 team surfaces" % model_name): return
		model.free()

	# 3. Keep model clips & wreck lifecycle check.
	var keep_probe: Node3D = load("res://scenes/models/keep_model.tscn").instantiate()
	root.add_child(keep_probe)
	await process_frame
	keep_probe.show_construction(0.5)
	if not check(keep_probe.player.assigned_animation == &"Build", "Keep model did not pose Build"): return
	keep_probe.show_print(0.5)
	if not check(keep_probe.player.assigned_animation == &"Train", "Keep model did not pose Train"): return
	keep_probe.play_launch_balloon()
	if not check(keep_probe.player.assigned_animation == &"LaunchBalloon", "Keep model did not play LaunchBalloon"): return
	keep_probe.unit_left()
	if not check(keep_probe.closing(), "Keep model did not close gate after unit_left()"): return
	if not check(keep_probe.has_death_clip(), "Keep model missing Die clip"): return
	keep_probe.play_death()
	var fx := keep_probe.get_children().filter(func(n): return n.get_script() == Burst)
	if not check(fx.size() == 1 and fx[0].player.has_animation(&"Death"), "Keep death FX missing or lacking Death clip"): return
	keep_probe.free()

	# 4. Load playable Arthurian skirmish scene cleanly.
	game = load("res://scenes/maps/arthurian_skirmish.tscn").instantiate()
	root.add_child(game)
	for _i in range(3): await process_frame
	network = game.get_node("DepotNetwork")
	hud = game.get_node("Interface")
	game.set_process(false)
	hud.set_process(false)
	for node in get_nodes_in_group("units"): node.set_process(false)
	for node in get_nodes_in_group("depots"): node.set_process(false)

	var keep := game.get_node("Entities/Buildings/Keep")
	var chapterhouse := game.get_node("Entities/Buildings/Chapterhouse")
	var forester := game.get_node("Entities/Units/ForesterMaiden1")
	var warhound := game.get_node("Entities/Units/Warhound")
	var marine := game.get_node("Entities/Units/RoundTableMarine")
	var sentinel := game.get_node("Entities/Units/GrailSentinel")
	var questing := game.get_node("Entities/Units/QuestingMarine")
	var dragon := game.get_node("Entities/Units/AzureDragon")
	var tank := game.get_node("Entities/Units/EnemyTank")

	if not check(keep.is_in_group("keeps") and keep.is_in_group("depots") and keep.food == 150, "Keep missing group or initial Food (150, docs/KNIGHTS_ECONOMY.md)"): return
	if not check(chapterhouse.assigned_depot == keep and chapterhouse.source_friendly(), "Chapterhouse should be assigned to Keep"): return
	if not check(forester.can_gather and forester.can_construct and not forester._attack_enabled, "Forester Maiden should be unarmed gather/builder worker"): return
	if not check(warhound.mobility_layer() == MobilityRules.Layer.FOREST, "Warhound should use FOREST mobility"): return
	if not check(sentinel.can_heal and sentinel.med_reserve == 200 and sentinel.heal_range == 9.0 and sentinel.heal_hp == 10, "Grail Sentinel should carry a 200 HP reserve and heal 10 HP a second at 9 m (docs/ARTHURIAN_KNIGHTS.md)"): return
	if not check(questing != null and dragon != null, "Missing Questing Marine or Azure Dragon"): return

	# 5. Forward Keep founding outside home Keep range using ONLY 50 Wood + 50 Iron site materials.
	var keep_spec: Dictionary = network.plan_spec(&"keep")
	if not check(keep_spec.wood == 50 and keep_spec.iron == 50 and keep_spec.energy == 0 and keep_spec.food == 0, "Keep plan_spec cost wrong: %s" % keep_spec): return
	var forward_point := Vector3.INF
	for r in range(55, 110, 4):
		for offset in [Vector3(0, 0, -r), Vector3(r, 0, 0), Vector3(-r, 0, 0), Vector3(0, 0, r), Vector3(r, 0, -r), Vector3(-r, 0, -r)]:
			var cand: Vector3 = keep.global_position + offset
			var st: Vector2i = network.footprint_start(cand, keep_spec.size)
			if network.plan_terrain_valid(st, keep_spec.size, &"keep") and not network.plan_overlaps(st, keep_spec.size) and network.depot_spacing_ok(cand) and network.covering_sources(st, keep_spec.size).is_empty():
				forward_point = cand
				break
		if forward_point != Vector3.INF: break
	if not check(forward_point != Vector3.INF, "No valid terrain found for Forward Keep test"): return
	var plan: Node3D = network.queue_plan(forward_point, &"keep")
	if not check(plan != null, "Forward Keep plan refused at %s" % forward_point): return
	plan.set_process(false)
	if not check(network.covering_sources(plan.start, keep_spec.size).is_empty(), "Forward Keep test site should be outside Home Keep range"): return

	var wood_pile = load("res://scenes/gameplay/material_pile.tscn").instantiate()
	wood_pile.material_kind = "wood"; wood_pile.amount = 50
	wood_pile.position = game.ground.tile_to_world(plan.start + Vector2i(1, 1))
	game.get_node("Entities/Resources").add_child(wood_pile, true)
	var iron_pile = load("res://scenes/gameplay/material_pile.tscn").instantiate()
	iron_pile.material_kind = "iron"; iron_pile.amount = 50
	iron_pile.position = game.ground.tile_to_world(plan.start + Vector2i(2, 1))
	game.get_node("Entities/Resources").add_child(iron_pile, true)
	if not check(plan.materials_covered(), "Forward Keep site should report materials covered with 50W + 50I"): return

	# Teleport Forester next to footprint edge and construct the entire Forward Keep tick by tick with ZERO energy/food payer!
	for c in forester._claimed.duplicate(): forester._release(c)
	forester.global_position = game.ground.tile_to_world(plan.start + Vector2i(-1, 2))
	forester._claim(game.ground.get_tile_at_position(forester.global_position))
	forester.command_construct(plan)
	var keeps_before := get_nodes_in_group("keeps").size()
	for _tick in range(40):
		forester._work_timer = forester.harvest_interval
		forester._process(0.0)
		if get_nodes_in_group("keeps").size() > keeps_before: break
	if not check(get_nodes_in_group("keeps").size() == keeps_before + 1, "Forester Maiden did not finish Forward Keep without a payer"): return
	var forward_keep := get_nodes_in_group("keeps")[keeps_before]
	forward_keep.set_process(false)
	if not check(forward_keep.food == 0 and forward_keep.energy == 0, "Newly founded Forward Keep should start empty: F=%d E=%d" % [forward_keep.food, forward_keep.energy]): return

	# 6. Keep training (Forester Maiden + Warhound) & Chapterhouse training (all 4 units) with Food + Iron.
	keep.food = 600; keep.iron = 400
	# Housing (docs/KNIGHTS_ECONOMY.md): the scene's units already fill the Keep's 10, so stand Houses in its range.
	for offset in [Vector3(16, 0, -14), Vector3(-16, 0, -14), Vector3(16, 0, 14)]:
		var house: Node3D = load("res://scenes/gameplay/house.tscn").instantiate()
		house.position = keep.global_position + offset
		game.get_node("Entities/Buildings").add_child(house)
		house.set_process(false)
	var food_0: int = keep.food; var iron_0: int = keep.iron
	if not check(keep.request_forester(), "Keep refused Forester Maiden"): return
	if not check(keep.food == food_0 - 45 and keep.iron == iron_0, "Forester cost wrong: F=%d I=%d" % [keep.food, keep.iron]): return
	if not check(keep.request_warhound(), "Keep refused Warhound"): return
	if not check(keep.food == food_0 - 75 and keep.iron == iron_0 - 5, "Warhound cost wrong"): return
	var units_before := get_nodes_in_group("units").size()
	for _s in range(25):
		keep._process(1.0)
		if keep.queue == 0: break
	if not check(keep.queue == 0 and get_nodes_in_group("units").size() == units_before + 2, "Keep did not finish training both units"): return

	for uid in [&"round_table_marine", &"grail_sentinel", &"questing_marine", &"azure_dragon"]:
		var prev_count := get_nodes_in_group("units").size()
		if not check(chapterhouse.request_unit(uid), "Chapterhouse refused %s" % uid): return
		for _s in range(40):
			chapterhouse._process(1.0)
			if chapterhouse.queue == 0: break
		if not check(chapterhouse.queue == 0 and get_nodes_in_group("units").size() == prev_count + 1, "Chapterhouse did not finish training %s" % uid): return

	# 7. Grail Sentinel Vitality Stimulus (item 6 of the balance handoff): heals from its carried reserve, one point for
	# one HP, 10 HP a second; the reserve refills inside a friendly Keep's range or beside a Food crate, 5 points for 1
	# Food, healing or not; no free regeneration; idle, it heals the most hurt friend within 9 m by itself.
	marine.health = 20 # needs 45 HP
	for c in sentinel._claimed.duplicate(): sentinel._release(c)
	for c in marine._claimed.duplicate(): marine._release(c)
	sentinel.global_position = keep.global_position + Vector3(0, 0, 8.0)
	marine.global_position = keep.global_position + Vector3(2.0, 0, 8.0)
	sentinel._claim(game.ground.get_tile_at_position(sentinel.global_position))
	marine._claim(game.ground.get_tile_at_position(marine.global_position))
	sentinel.heal_autocast = false

	var keep_food_before: int = keep.food
	sentinel.command_heal(marine)
	if not check(sentinel.order == "heal", "Sentinel did not accept heal command"): return
	for _h in range(5):
		sentinel._work_timer = sentinel.heal_interval
		sentinel._process(0.0)
	if not check(marine.health == marine.max_health and sentinel.med_reserve == 155 and keep.food == keep_food_before, "Sentinel should heal the Marine 45 HP from its reserve, 10 a pulse (hp=%d/%d, res=%d, food=%d->%d)" % [marine.health, marine.max_health, sentinel.med_reserve, keep_food_before, keep.food]): return
	sentinel.order = "idle"; sentinel.order_target = null
	for _r in range(3):
		sentinel._process(1.0)
	if not check(sentinel.med_reserve == 170 and keep.food == keep_food_before - 3, "Inside the Keep's range the reserve should refill 5 points for 1 Food (res=%d, food=%d->%d)" % [sentinel.med_reserve, keep_food_before, keep.food]): return

	# Field healing far away from Keep uses carried reserve, then stops completely when empty!
	sentinel.global_position = keep.global_position + Vector3(-120.0, 0, 0)
	marine.global_position = sentinel.global_position + Vector3(2.0, 0, 0)
	sentinel.med_reserve = 10
	marine.health = 30
	sentinel.command_heal(marine)
	for _t in range(4):
		sentinel._work_timer = sentinel.heal_interval
		sentinel._process(0.0)
	if not check(marine.health == 40 and sentinel.med_reserve == 0 and sentinel.state.begins_with("Medical reserve empty"), "Sentinel should heal 10 HP from reserve then stop with zero free regen (hp=%d, res=%d, state=%s)" % [marine.health, sentinel.med_reserve, sentinel.state]): return
	sentinel._process(5.0)
	if not check(sentinel.med_reserve == 0, "Away from a Keep and a Food crate the reserve should not refill (res=%d)" % sentinel.med_reserve): return

	# Refill from adjacent Food crate.
	sentinel.order = "idle"; sentinel.order_target = null
	var food_crate := CrateYard.spawn(self, game.ground.get_tile_at_position(sentinel.global_position + Vector3(2, 0, 0)), &"food", 5, "player")
	for _r in range(3):
		sentinel._process(1.0)
	if not check(sentinel.med_reserve == 15 and food_crate.amount == 2, "Sentinel should refill carried reserve from nearby Food crate (res=%d, crate=%d)" % [sentinel.med_reserve, food_crate.amount]): return

	# By itself: idle, it takes the most hurt friend within 9 m and heals it.
	sentinel.heal_autocast = true
	marine.health = 50
	for _p in range(2):
		sentinel._process(0.6)
	if not check(sentinel.order == "heal" and sentinel.order_target == marine and marine.health == 60, "An idle Sentinel should heal a hurt friend within 9 m by itself (order=%s, hp=%d)" % [sentinel.order, marine.health]): return

	# Refuses vehicles even if same team.
	var ally_tank = load("res://scenes/gameplay/tank.tscn").instantiate()
	ally_tank.team = "player"
	ally_tank.position = sentinel.global_position + Vector3(-3, 0, 0)
	game.get_node("Entities/Units").add_child(ally_tank, true)
	ally_tank.health = 50
	if not check(not MedicalWork.can_heal(ally_tank, "player"), "MedicalWork must refuse vehicles"): return

	# 8. Warhound forest mobility check.
	var forest_cell := Vector2i(-1, -1)
	for gz in range(40, 460, 2):
		for gx in range(40, 460, 2):
			var c := Vector2i(gx, gz)
			if game.ground.get_terrain(c) == game.ground.Terrain.FOREST:
				forest_cell = c
				break
		if forest_cell.x >= 0: break
	if not check(forest_cell.x >= 0 and game.ground.can_traverse(forest_cell, warhound.mobility_layer()) and not game.ground.can_traverse(forest_cell, marine.mobility_layer()), "Warhound should traverse forest while Marine stays blocked"): return

	# 9. HUD integration: Keep card, Chapterhouse card, Sentinel Heal card + portrait, StoragePanel Food legend, GlobalBuild Keep/Chapterhouse.
	game.selected_building = keep
	for u in get_nodes_in_group("units"): u.set_selected(false)
	hud._process(0)
	if not check(hud.card.get_node("TrainForester").visible and hud.card.get_node("TrainWarhound").visible and not hud.depot_panel.visible and hud.storage_panel.visible, "Keep HUD or StoragePanel wrong"): return
	if not check(hud.storage_panel.get_node("Storage/Legend/Food").visible, "Food legend should be visible on Keep StoragePanel"): return

	game.selected_building = chapterhouse
	hud._process(0)
	for btn in ["ProduceRoundTableMarine", "ProduceGrailSentinel", "ProduceQuestingMarine", "ProduceAzureDragon"]:
		if not check(hud.card.get_node(btn).visible, "Chapterhouse missing button %s" % btn): return

	game.selected_building = null
	sentinel.set_selected(true)
	hud._process(0)
	if not check(hud.card.get_node("Heal").visible and hud.get_node("Bottom/Body/Row/Ornament/Portrait").visible, "Sentinel Heal button or portrait missing"): return

	hud.get_node("Bottom/Body/Header/GlobalBuild").pressed.emit()
	hud._process(0)
	if not check(hud.build_menu.get_node("Actions/Keep").visible and hud.build_menu.get_node("Actions/Chapterhouse").visible, "Arthurian GlobalBuild buttons missing"): return

	print("ARTHURIAN_FACTION_TEST_PASSED")
	quit(0)
