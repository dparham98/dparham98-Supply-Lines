extends SceneTree
# Not part of the headless suite, which runs in real time: these battles take minutes of game time. Run with a
# fixed step:
#   godot --headless --fixed-fps 30 --path . --script res://tests/ubermech_battles_sim.gd
# The check of item 8 of docs/BALANCE_IMPLEMENTATION_HANDOFF.md (docs/ARMOUR_CLASS.md): three Ubermechs beat
# 10 Deforesters, 28 Scouts and 5 Tanks, each on its own, and lose to 11 Grenadiers. All on attack-move, on
# see_to_shoot_battles_sim.gd's arena with the fog of war. Prints UBERMECH_BATTLES_PASSED when every check holds.
const A := "player"
const B := "enemy"
const STEP_FRAMES := 6
const BIG := ["tank","ubermech","azure_dragon"]
var game: Node3D
var keep_children: Array = []
var now := 0.0
func _initialize() -> void: call_deferred("run")
func run() -> void:
	game = load("res://scenes/maps/resource_skirmish.tscn").instantiate()
	root.add_child(game)
	for i in range(3): await process_frame
	var ground = game.get_node("Terrain/Ground")
	for group in ["units","selectable_buildings","depots"]:
		for node in get_nodes_in_group(group): node.queue_free()
	for node in game.get_node("Entities/Resources").get_children(): node.queue_free()
	for i in range(3): await process_frame
	game.set_process(false)
	game.get_node("Interface").process_mode = Node.PROCESS_MODE_DISABLED
	for z in range(150,350):
		for x in range(20,480):
			var tile: Dictionary = ground.tiles[z*500+x]
			tile.occupied_by = null
			ground._open_cell(Vector2i(x,z))
	game.add_child(load("res://scenes/gameplay/fog_of_war.tscn").instantiate())
	for i in range(2): await process_frame
	keep_children = game.get_children()
	var failures := 0
	var mechs := [{unit = "ubermech", n = 3}]
	for foe in [["infantry",10],["scout",28],["tank",5]]:
		var r := await battle("3 Ubermechs vs %d %s" % [foe[1],foe[0]],mechs,[{unit = foe[0], n = foe[1]}],240.0)
		if r.winner != "a": failures += 1; print("  FAIL: the Ubermechs should win")
	var r := await battle("3 Ubermechs vs 11 Grenadiers",mechs,[{unit = "grenadier", n = 11}],240.0)
	if r.winner != "b": failures += 1; print("  FAIL: the Grenadiers should win")
	if failures == 0: print("UBERMECH_BATTLES_PASSED")
	quit(0 if failures == 0 else 1)
func spawn(side: String, group: Dictionary, front_x: float, dir: float, row_offset: float) -> float:
	var id: String = group.unit
	var n: int = group.n
	var gap: float = 4.0 if id in BIG else 2.0
	var width: int = clampi(ceili(sqrt(n)*1.6),1,16)
	var members: Array = []
	var scene: PackedScene = load("res://scenes/gameplay/%s.tscn" % id)
	var rows := ceili(float(n)/width)
	for i in range(n):
		var row := i/width
		var in_row := mini(width,n-row*width)
		var unit = scene.instantiate()
		unit.team = side
		unit.position = Vector3(front_x-dir*(row_offset+row*gap),0,(i%width-(in_row-1)*0.5)*gap)
		if "start_fuelled" in unit: unit.start_fuelled = true
		game.get_node("Entities/Units").add_child(unit,true)
		members.append(unit)
	group["members"] = members
	group["side"] = side
	return row_offset+rows*gap+1.0
func alive(members: Array) -> Array:
	return members.filter(func(u): return is_instance_valid(u) and not u.is_queued_for_deletion() and u.health > 0)
func side_units(groups: Array, side: String) -> Array:
	var result: Array = []
	for group in groups:
		if group.side == side: result.append_array(alive(group.members))
	return result
func nearest(from: Vector3, units: Array) -> Node3D:
	var best: Node3D
	var best_d := INF
	for unit in units:
		var d := from.distance_squared_to(unit.global_position)
		if d < best_d: best = unit; best_d = d
	return best
func centroid(units: Array) -> Vector3:
	var total := Vector3.ZERO
	for unit in units: total += unit.global_position
	return total/maxf(1.0,units.size())
func battle(name: String, a: Array, b: Array, limit: float) -> Dictionary:
	game.vehicle_fuel_required = false
	now = 0.0
	var groups: Array = []
	var offset := 0.0
	for group in a:
		var g: Dictionary = group.duplicate(true)
		offset = spawn(A,g,-40.0,1.0,offset)
		groups.append(g)
	offset = 0.0
	for group in b:
		var g: Dictionary = group.duplicate(true)
		offset = spawn(B,g,40.0,-1.0,offset)
		groups.append(g)
	for i in range(2): await process_frame
	var hp0 := 0
	for group in groups:
		if group.side == A:
			for unit in group.members: hp0 += unit.max_health
	var winner := "draw"
	while now < limit:
		for i in range(STEP_FRAMES): await process_frame
		now += STEP_FRAMES/30.0
		var units_a := side_units(groups,A)
		var units_b := side_units(groups,B)
		var armed_a := units_a.filter(func(u): return u._attack_enabled)
		var armed_b := units_b.filter(func(u): return u._attack_enabled)
		if armed_a.is_empty() or armed_b.is_empty():
			winner = "b" if armed_a.is_empty() and not armed_b.is_empty() else ("a" if armed_b.is_empty() and not armed_a.is_empty() else "draw")
			break
		for group in groups:
			var mine: Array = alive(group.members)
			var foes: Array = units_b if group.side == A else units_a
			var friends: Array = units_a if group.side == A else units_b
			match group.get("ctrl","amove"):
				"amove": _amove(mine,foes)
				"kite": _kite(group,mine,foes)
				"follow": _follow(group,mine,friends)
	var left_a := side_units(groups,A)
	var hp := 0
	var max_left := 0
	for unit in left_a:
		hp += unit.health; max_left += unit.max_health
	var result := {winner = winner, a_hp = hp, a_hp0 = hp0, a_left = left_a.size(), b_left = side_units(groups,B).size()}
	# Damage A took: what its survivors lost, plus every unit it lost at full health.
	result["a_taken"] = (max_left-hp)+(hp0-max_left)
	print("%s -> %s in %.1f s · A left %d (%d/%d HP) · B left %d" % [name,winner,now,result.a_left,hp,hp0,result.b_left])
	for unit in get_nodes_in_group("units"): unit.queue_free()
	for child in game.get_children():
		if not keep_children.has(child): child.queue_free()
	for i in range(4): await process_frame
	return result
func _amove(mine: Array, foes: Array) -> void:
	for unit in mine:
		var foe := nearest(unit.global_position,foes)
		if foe == null: continue
		if unit.state == "Attack-moving · engaging": continue
		if unit.order == "idle" or (unit.order == "attack_move" and unit.move_goal.distance_to(foe.global_position) > 6.0 and int(now*5)%5 == 0):
			unit.command_attack_move(foe.global_position)
# Fall back from the nearest foe whenever it is inside `kite_at`, firing on the move; stand when it is outside.
func _kite(group: Dictionary, mine: Array, foes: Array) -> void:
	for unit in mine:
		var foe := nearest(unit.global_position,foes)
		if foe == null: continue
		var d: float = unit.global_position.distance_to(foe.global_position)
		var kite_at: float = group.get("kite_at",unit.attack_range-4.0)
		var resume: float = kite_at+2.0
		if d < kite_at:
			var away: Vector3 = unit.global_position-centroid(foes.filter(func(f): return f.global_position.distance_to(unit.global_position) < kite_at+10.0))
			away.y = 0
			away = away.normalized() if away.length() > 0.01 else Vector3.LEFT
			var goal: Vector3 = unit.global_position+away*30.0
			goal.x = clampf(goal.x,-225.0,225.0)
			goal.z = clampf(goal.z,-95.0,95.0)
			if unit.order != "move" or unit.move_goal.distance_to(goal) > 10.0: unit.command_move(goal)
		elif unit.order == "move" and d >= resume:
			unit._stop_route()
			unit.order = "idle"
		elif unit.order == "idle" and d > unit.attack_range+1.0:
			unit.command_attack_move(foe.global_position)
		elif unit.order == "attack_move" and d < kite_at+1.0:
			unit._stop_route(); unit.order = "idle"
# Stay with the friendly fighting units (a spotter).
func _follow(group: Dictionary, mine: Array, friends: Array) -> void:
	var fighters: Array = friends.filter(func(u): return not mine.has(u))
	if fighters.is_empty(): return
	var centre := centroid(fighters)
	for unit in mine:
		if unit.global_position.distance_to(centre) > 4.0 and (unit.order != "move" or unit.move_goal.distance_to(centre) > 4.0): unit.command_move(centre)
