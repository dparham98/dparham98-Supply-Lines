extends SceneTree
# Headless: the explicit Attack command (A / Attack button, then click) fires on friendly units and
# buildings so they die and play their death animations; right-click, plain attack orders, auto-targeting
# and splash still spare friendlies.
var game: Node3D
var rig: Node
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
func screen(node: Node3D) -> Vector2:
	return rig.camera.unproject_position(node.global_position+Vector3.UP*1.2)
## Fires the shooter's attack order until it ends or `limit` shots go by.
func fire(shooter: Node3D, limit := 60) -> void:
	for shot in range(limit):
		if shooter.order != "attack": return
		shooter._cooldown = 0
		shooter._attack_order()
func site(network: Node, kind: StringName, near: Vector3) -> Vector3:
	var spec: Dictionary = network.plan_spec(kind)
	for radius in range(10,100,4):
		for offset in [Vector3(radius,0,0),Vector3(-radius,0,0),Vector3(0,0,radius),Vector3(0,0,-radius)]:
			var point: Vector3 = near+offset
			var start: Vector2i = network.footprint_start(point,spec.size)
			if network.plan_terrain_valid(start,spec.size,kind) and not network.plan_overlaps(start,spec.size) and network.can_place_size(point,game.depot,spec.size): return point
	return Vector3.INF
func run() -> void:
	root.size = Vector2i(1280,900)
	game = load("res://scenes/maps/resource_skirmish.tscn").instantiate()
	root.add_child(game)
	for frame in range(3): await process_frame
	game.set_process(false)
	for group in ["units","depots","mines","selectable_buildings"]:
		for node in get_nodes_in_group(group):
			node.set_process(false)
			if node.get("is_selected") != null: node.is_selected = false
	var origin := Vector3(180,0,180)
	var shooter = actor("infantry","player",origin)
	var friend = actor("infantry","player",origin+Vector3(3,0,0))
	var bystander = actor("infantry","player",origin+Vector3(3.5,0,1))
	shooter.is_selected = true
	rig = game.get_node("CameraRig")
	rig.set_process(false)
	rig.focus_position(origin+Vector3(3,0,0),24)
	for frame in range(150): rig.advance_camera(1.0/60)
	await process_frame
	# Unchanged: plain attack orders and right-click leave friendlies alone.
	shooter.command_attack(friend)
	if not check(shooter.order != "attack","A plain attack order on a friendly should be refused"): return
	game.issue_order(screen(friend))
	if not check(shooter.order != "attack","Right-click on a friendly should not attack it"): return
	# The Attack command on a friendly unit forces fire until it dies.
	game.pending_unit_command = "attack"
	game.issue_card_order(screen(friend))
	if not check(shooter.order == "attack" and shooter.order_target == friend and shooter.attack_forced,"The Attack command should accept a friendly unit (order %s target %s)" % [shooter.order,shooter.order_target]): return
	var bystander_health: int = bystander.health
	fire(shooter)
	if not check(friend._dead and not friend.is_in_group("units"),"The friendly unit should die under forced fire"): return
	if not check(bystander.health == bystander_health,"Forced fire should only hurt its own target"): return
	if not check(shooter.order == "idle" and shooter._nearest_opponent() == null,"After the kill the shooter should stop, not turn on other friendlies"): return
	# Forced fire belongs to that order only: attack-move afterwards does not shoot friendlies.
	shooter.attack_forced = true
	if not check(not shooter._may_hit(bystander),"Forced fire should not carry over to other targets"): return
	shooter.attack_forced = false
	# Queued with Shift, the forced flag rides in the queue.
	game.pending_unit_command = "attack"
	shooter.order = "move"
	game.issue_card_order(screen(bystander),true)
	if not check(shooter.order_queue.size() == 1 and shooter.order_queue[0].get("forced") == true,"A queued friendly attack should keep its forced flag"): return
	shooter.order_queue.clear()
	shooter.order = "idle"
	game.pending_unit_command = ""
	# A friendly Barracks: the Attack command destroys it and its wreck plays Die.
	var network: Node = game.get_node("DepotNetwork")
	game.depot.storage_capacity = 10000
	game.depot.energy = 2000; game.depot.iron = 2000
	var point := site(network,&"barracks",game.depot.global_position)
	if not check(point != Vector3.INF,"No Barracks site"): return
	var plan = network.queue_plan(point,&"barracks")
	plan.set_process(false)
	var barracks: Node3D = plan.complete_from_stock()
	if not check(barracks != null and barracks.team == "player","Friendly Barracks not built"): return
	barracks.set_process(false)
	await process_frame
	var model: Node3D = barracks.get_node("Visuals/Model")
	rig.focus_position(barracks.global_position,30)
	for frame in range(150): rig.advance_camera(1.0/60)
	await process_frame
	game.pending_unit_command = "attack"
	game.issue_card_order(rig.camera.unproject_position(barracks.global_position+Vector3(0,2.5,0)))
	if not check(shooter.order == "attack" and shooter.order_target == barracks,"The Attack command should accept a friendly building (order %s target %s)" % [shooter.order,shooter.order_target]): return
	shooter.global_position = barracks.global_position+Vector3(0,0,shooter.attack_range-1)
	fire(shooter,400)
	if not check(barracks.health <= 0 and not barracks.is_in_group("selectable_buildings"),"The friendly Barracks should be destroyed (health %d)" % barracks.health): return
	if not check(model.get_parent() == game and model.dying(),"The destroyed Barracks should leave its wreck playing Die"): return
	print("FRIENDLY_ATTACK_TEST_PASSED")
	quit(0)
