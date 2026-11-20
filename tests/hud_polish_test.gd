extends SceneTree
# Headless, on Two Lakes: the 2026-11-19 polish list (docs/HUD_POLISH.md). Warnings fade by themselves; the health
# number and fuel come back after a group selection; building sites join control groups and become the building;
# right-click lowers a manifest; Depot rings show with a building selected or the build page open; an empty tank keeps
# a vehicle in Depot range; an emptied crate leaves the map; plans need sight, Worksites don't; Depots wear their
# side's paint; the worker is the Deforester; the HUD's pictures are renders.
const HUD = preload("res://scripts/gameplay/skirmish_hud.gd")
const TeamPaint = preload("res://scripts/components/team_paint.gd")
var game: Node3D
var hud: CanvasLayer
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> bool:
	if value: return true
	push_error(message); quit(1); return false
func spawn(id: String, point: Vector3) -> Node3D:
	var unit = load("res://scenes/gameplay/"+id+".tscn").instantiate()
	unit.team = "player"
	game.get_node("Entities/Units").add_child(unit)
	unit.global_position = game.ground.tile_to_world(game.ground.find_nearest_open_tile(game.ground.get_tile_at_position(point)))
	return unit
func select_only(units: Array) -> void:
	game.get_node("DepotNetwork").select_depot(null)
	game.selected_building = null
	for unit in get_nodes_in_group("units"): unit.set_selected(units.has(unit))
	hud._process(0)
func info(id: String) -> Control:
	return hud.get_node("Bottom/Body/Row/Info/"+id)
func run() -> void:
	game = load("res://scenes/maps/lakes_skirmish.tscn").instantiate()
	root.add_child(game)
	for frame in range(3): await process_frame
	var ai = game.get_node_or_null("EnemyPlayer")
	if ai != null: ai.set_process(false)
	hud = game.get_node("Interface")
	var network = game.get_node("DepotNetwork")
	var depot: Node3D = game.depot
	var fog = game.fog_of_war()
	if fog != null: fog.update_now()

	# Warnings: shown for FEED_SECONDS, then faded out; nothing to close.
	if not check(HUD.warning_alpha(0.0) == 1.0 and HUD.warning_alpha(HUD.FEED_SECONDS) == 1.0 and HUD.warning_alpha(HUD.FEED_SECONDS+HUD.FEED_FADE_SECONDS) == 0.0,"Warnings should show, then fade"): return
	var mid := HUD.warning_alpha(HUD.FEED_SECONDS+HUD.FEED_FADE_SECONDS*0.5)
	if not check(mid > 0.4 and mid < 0.6,"Half way through the fade should be half seen: %.2f" % mid): return
	game.alert("Test warning",depot.global_position)
	hud.update_feed()
	var feed: Control = hud.get_node("Feed")
	if not check(feed.get_child(0).visible and feed.get_child(0).text == "Test warning","A new warning should show"): return
	game.alerts[0].time -= HUD.FEED_SECONDS+HUD.FEED_FADE_SECONDS+0.1
	hud.update_feed()
	if not check(not feed.get_child(0).visible,"An old warning should be gone"): return
	game.notify("Header message")
	hud._process(0)
	var header: Label = hud.get_node("Bottom/Body/Header/Message")
	if not check(header.text == "Header message" and header.modulate.a == 1.0,"A new header message should show"): return
	game.message_time -= HUD.FEED_SECONDS+HUD.FEED_FADE_SECONDS+0.1
	hud._process(0)
	if not check(header.modulate.a == 0.0,"An old header message should be faded out"): return

	# The health number and fuel come back on a single selection after a group selection hid them.
	var tank := spawn("tank",depot.global_position+Vector3(-8,0,10))
	var cargo := spawn("cargo_vehicle",depot.global_position+Vector3(-8,0,16))
	await process_frame
	select_only([tank,cargo])
	if not check(not info("HealthText").visible,"A group shows portraits instead of the health line"): return
	select_only([tank])
	if not check(info("HealthText").visible and info("HealthText").text.begins_with("Health ") and info("Bars").visible and info("Bars/Fuel").visible,"After a group, one vehicle should show its health number and fuel again"): return
	select_only([])
	game.get_node("DepotNetwork").select_depot(depot)
	hud._process(0)
	if not check(info("HealthText").visible and info("HealthText").text == "Health %d / %d" % [depot.health,depot.max_health],"A building should show its health as a number"): return

	# Pictures: renders for units and buildings, portraits for both.
	for id in ["infantry","tank","cargo","depot","barracks","tank_factory","generator","mine","pithead"]:
		if not check(hud.has_render(id) and ResourceLoader.exists(HUD.PORTRAIT_PATH % id),"No render or portrait for "+id): return
	if not check(hud.icon_name(depot) == "depot" and info("Head/Icon").texture.resource_path == HUD.RENDER_PATH % "depot","The Depot's icon should be its render"): return
	if not check(load("res://assets/units/infantry.tres").display_name == "Deforester","The worker should be called the Deforester"): return

	# Depot paint: the side's colour, changing with the side.
	var paint_surface := func(team: String) -> bool:
		for mesh in depot.get_node("Visuals/Model").find_children("*","MeshInstance3D",true,false):
			for i in mesh.mesh.get_surface_count():
				var base = mesh.mesh.surface_get_material(i)
				if base != null and base.resource_name == "team_color": return mesh.get_surface_override_material(i) == TeamPaint.paint_for(team)
		return false
	if not check(paint_surface.call("player"),"The Depot should wear the player's paint"): return
	depot.team = "enemy"; depot.ownership_changed.emit()
	if not check(paint_surface.call("enemy"),"A captured Depot should wear its new side's paint"): return
	depot.team = "player"; depot.ownership_changed.emit()

	# Depot rings: with any building selected, or the build page open; otherwise only the selected Depot's.
	var ring: Node3D = depot.get_node("Territory")
	var mine: Node3D = get_nodes_in_group("mines")[0]
	game.get_node("DepotNetwork").select_depot(null)
	game.selected_building = null
	network._process(0)
	if not check(not ring.visible,"With nothing selected the ring should hide"): return
	game.selected_building = mine
	network._process(0)
	if not check(ring.visible,"With a building selected every Depot ring should show"): return
	game.selected_building = null
	hud.global_build_open = true
	network._process(0)
	if not check(ring.visible,"With the build page open every Depot ring should show"): return
	hud.global_build_open = false
	network._process(0)

	# Manifest: right-click takes crates off.
	select_only([cargo])
	cargo.manifest.clear()
	cargo.manifest_add(&"iron"); cargo.manifest_add(&"iron"); cargo.manifest_add(&"coal")
	hud.lower_manifest(&"iron")
	if not check(cargo.manifest.get(&"iron",0) == 1 and cargo.manifest_total() == 2,"Right-click should take one iron crate off"): return
	hud.lower_manifest(&"coal",true)
	if not check(not cargo.manifest.has(&"coal"),"Shift+right-click should take every coal crate off"): return
	if not check(not cargo.manifest_remove(&"wood"),"Nothing to take off should say so"): return

	# An emptied crate leaves the map.
	var cell: Vector2i = game.ground.find_nearest_open_tile(game.ground.get_tile_at_position(depot.global_position+Vector3(-12,0,-4)))
	var crate = preload("res://scripts/economy/crate_yard.gd").spawn(self,cell,&"coal",3,"player")
	if not check(crate.extract(2) == 2 and is_instance_valid(crate) and not crate.is_queued_for_deletion(),"A part-emptied crate stays"): return
	if not check(crate.extract(5) == 1 and crate.is_queued_for_deletion() and not crate.is_in_group("supply_crates"),"An emptied crate should leave the map"): return

	# An empty tank keeps a vehicle in Depot range: it stops at the edge and its order waits.
	if not check(tank.fuel_active(),"Fuel should be on in Two Lakes"): return
	depot.energy = maxi(depot.energy,500)
	tank.fuel = 0
	var away: Vector3 = depot.global_position+(tank.global_position-depot.global_position).normalized()*60.0
	tank.command_move(away)
	for frame in range(900):
		tank._process(1.0/30)
		if tank.state == tank.NO_FUEL_EDGE: break
	if not check(tank.state == tank.NO_FUEL_EDGE,"A tank with no fuel should stop at the edge of Depot range: %s" % tank.state): return
	if not check(SupplySource.covers(depot,tank.global_position,"player"),"It should still be in Depot range"): return
	tank.fuel = tank.fuel_rules.reserve_capacity
	var before: float = tank.global_position.distance_to(depot.global_position)
	for frame in range(60): tank._process(1.0/30)
	if not check(tank.global_position.distance_to(depot.global_position) > before,"With fuel again it should go on"): return

	# Plans need sight; a truck's Worksite doesn't.
	var far := Vector3(-depot.global_position.x,0,-depot.global_position.z)
	if fog != null and not fog.visible_to("player",far):
		if not check(network.queue_plan(far,&"generator") == null and network.OUT_OF_SIGHT in game.message,"A plan out of sight should be refused"): return
		var site = network.queue_plan(far,&"generator",null,false,false)
		if site != null: site.cancel()
	else:
		if not check(false,"The far side of the map should be out of sight at the start"): return

	# A building site joins a control group, and the group holds the building once it stands.
	depot.energy = 800; depot.iron = 800
	var manager = root.get_node("SelectionManager")
	var plan: Node3D
	for ring_radius in range(6,22):
		for step in range(12):
			var angle := TAU*step/12.0
			var point: Vector3 = depot.global_position+Vector3(cos(angle),0,sin(angle))*ring_radius
			plan = network.queue_plan(point,&"generator")
			if plan != null: break
		if plan != null: break
	if not check(plan != null,"No spot for a Generator plan near the Depot"): return
	select_only([])
	game.selected_building = plan
	manager.save_group(5)
	if not check(manager.groups[5] == [plan],"A building site should join the control group"): return
	var building = plan.complete_from_stock()
	if not check(building != null and manager.groups[5] == [building],"The group should hold the finished building"): return
	await process_frame
	manager.recall_group(5)
	if not check(game.selected_building == building,"Recalling the group should select the building"): return
	# Production picks its paying Depot: no list to choose from, and it finds a Depot again after losing one.
	if not check(not hud.has_node("Bottom/Body/Row/Context/AssignedSource"),"The Assign Depot list should be gone"): return
	var barracks: Node3D
	depot.stockpile.withdraw(&"wood",depot.wood); depot.stockpile.withdraw(&"coal",depot.coal)
	depot.energy = 800; depot.iron = 800
	for ring_radius in range(8,26):
		for step in range(12):
			var angle := TAU*step/12.0
			var site = network.queue_plan(depot.global_position+Vector3(cos(angle),0,sin(angle))*ring_radius,&"barracks")
			if site != null:
				barracks = site.complete_from_stock()
				if barracks == null: site.cancel()
			if barracks != null: break
		if barracks != null: break
	if not check(barracks != null,"No spot for a Barracks near the Depot"): return
	barracks.set_process(false)
	barracks.assigned_depot = null
	if not check(barracks.source_friendly() and barracks.assigned_depot == depot,"A Barracks should take the covering Depot by itself"): return
	depot.team = "enemy"; depot.ownership_changed.emit()
	if not check(not barracks.source_friendly() and not barracks.request_unit(&"infantry"),"With no friendly Depot in range nothing pays"): return
	depot.team = "player"; depot.ownership_changed.emit()
	depot.energy = 0
	if not check(barracks.source_friendly() and barracks.payer_for(100,0) == null and not barracks.request_unit(&"infantry") and "No Depot in range has" in game.message,"A Depot that can't pay should be explained"): return
	depot.energy = 800
	if not check(barracks.request_unit(&"infantry") and barracks.assigned_depot == depot,"The Depot in range should pay"): return
	print("HUD_POLISH_TEST_PASSED")
	quit()
