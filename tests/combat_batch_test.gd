extends SceneTree
var game: Node3D
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> bool:
	if value: return true
	push_error(message); quit(1); return false
func actor(id: String, team: String, point: Vector3) -> Node3D:
	var unit = load("res://scenes/gameplay/"+id+".tscn").instantiate()
	unit.team = team
	game.add_child(unit)
	unit.set_process(false)
	for cell in unit._claimed.duplicate(): unit._release(cell)
	unit.global_position = point
	return unit
func click_at(point: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	root.push_input(motion,true)
	var event := InputEventMouseButton.new()
	event.position = point
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	root.push_input(event,true)
	# A human click spans multiple process frames. Do not emit button signals directly.
	for frame in range(5): await process_frame
	event = InputEventMouseButton.new()
	event.position = point
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = false
	root.push_input(event,true)
	for frame in range(3): await process_frame
func run() -> void:
	root.size = Vector2i(1280,900)
	game = load("res://scenes/maps/resource_skirmish.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	for group in ["units","depots","mines"]:
		for node in get_nodes_in_group(group): node.set_process(false)
	var origin := Vector3(180,0,180)
	var grenadier = actor("grenadier","player",origin)
	var target = actor("infantry","enemy",origin+Vector3(4,0,0))
	var tank = actor("tank","enemy",origin+Vector3(5,0,0))
	var friend = actor("infantry","player",origin+Vector3(4,0,1))
	var outside = actor("infantry","enemy",origin+Vector3(4,0,4))
	var mine = game.get_node("Entities/Buildings/IronMine")
	mine.global_position = origin+Vector3(4,0,2)
	mine.team = "enemy"
	var mine_hp: int = mine.health
	grenadier._shoot(target)
	if not check(target.health == 35 and tank.health == 110 and friend.health == 55 and outside.health == 55 and mine.health == mine_hp-40,"Splash class damage, radius, no friendly fire, or dedup failed"): return
	if not check(grenadier._cooldown == 3,"Grenadier interval incorrect"): return
	grenadier._shoot(target)
	if not check(target.health == 35,"Cooldown allowed duplicate shot"): return
	mine.team = "neutral"
	grenadier._cooldown = 0
	grenadier._shoot(target)
	if not check(mine.health == mine_hp-40,"Neutral mine received damage"): return
	var shooter = actor("tank","player",origin)
	shooter._shoot(tank)
	if not check(tank.health == 20 and shooter._cooldown == 3,"Tank heavy attack/cadence incorrect"): return
	shooter._cooldown = 0
	shooter._shoot(outside)
	if not check(outside.health == 55,"Out-of-range shot accepted"): return
	outside.global_position = origin+Vector3(-4,0,0)
	shooter._shoot(outside)
	if not check(outside.health == 43 and shooter._cooldown == 1,"Tank base attack incorrect"): return
	shooter.command_attack(friend)
	if not check(shooter.order != "attack","Friendly attack command accepted"): return
	for unit in [target,tank,friend,outside]: unit.free()
	# Actual walking advances while the moving unit shoots; claims/navigation stay intact.
	for id in ["scout","tank","motorcycle","infantry"]:
		var mover = actor(id,"player",origin)
		mover.grid_position = game.ground.get_tile_at_position(origin)
		mover._claim(mover.grid_position)
		var goal: Vector2i = game.ground.find_nearest_open_tile(mover.grid_position+Vector2i(0,2))
		mover._route.assign([goal])
		mover.order = "move"
		var victim = actor("tank","enemy",origin+Vector3(1,0,0))
		var before: int = victim.health
		mover._process(0.1)
		if not check(mover.global_position != origin and mover.order == "move","Movement was interrupted by combat"): return
		if not check((victim.health < before) == (id != "infantry"),"Moving-fire roster incorrect: "+id): return
		mover.free(); victim.free()
	# Explicit Attack card accepts buildings; infantry capture remains its right-click default.
	var infantry = game.get_node("Entities/Units/Infantry")
	infantry.set_selected(true)
	mine.team = "enemy"
	var rig = game.get_node("CameraRig")
	rig.set_process(false)
	rig.focus_position(mine.global_position)
	for frame in range(180): rig.advance_camera(1.0/60)
	for frame in range(8): await process_frame
	var hud = game.get_node("Interface")
	await click_at(hud.card.get_node("Attack").get_global_rect().get_center())
	if not check(game.pending_unit_command == "attack","Attack button input failed"): return
	await click_at(game.get_viewport().get_camera_3d().unproject_position(mine.global_position+Vector3.UP*1.5))
	if not check(infantry.order == "attack" and infantry.order_target == mine,"Attack card could not target a hostile building"): return
	# Resolved data does not remove explicit compatibility fallback for old prototypes.
	var fallback = actor("infantry","player",origin)
	fallback.unit_stats = load("res://assets/units/infantry.tres").duplicate()
	fallback.unit_stats.damage = -1; fallback.unit_stats.attack_interval = -1
	fallback.attack_damage = 16; fallback.shot_interval = 0.7
	fallback.apply_unit_stats()
	if not check(fallback._attack_enabled and fallback.attack_damage == 16 and fallback.shot_interval == 0.7,"Compatibility fallback lost"): return
	infantry.order_target = game.depot
	infantry._route.assign([game.ground.find_nearest_open_tile(infantry.grid_position+Vector2i(0,2))])
	infantry._process(0.1)
	if not check(infantry.order == "idle" and infantry._route.is_empty(),"Captured target pursuit did not stop"): return
	mine.team = "enemy"
	mine.health = 40
	grenadier._cooldown = 0
	grenadier._shoot(mine)
	if not check(mine.health == 0 and not mine.is_in_group("selectable_buildings"),"Building destruction failed"): return
	var occupied: Array = mine.cells.duplicate()
	await process_frame
	for cell in occupied:
		if not check(game.ground.tiles[cell.y*500+cell.x].occupied_by == null,"Destroyed building footprint not released"): return
	print("COMBAT_BATCH_CHECKS_PASSED")
	quit()
