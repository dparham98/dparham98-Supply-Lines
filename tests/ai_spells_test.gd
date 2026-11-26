extends SceneTree
# Headless, on Two Lakes (docs/MIST_AND_SLOW.md, docs/KNIGHTS_AI.md): the Knights AI's Forge researches Slow after
# level 1 of Arms and Mail; a Grail Sentinel casts Slow on a clump of the other side's units, not on a scattered few;
# and casts Mist over a group of friends while the other side's units in reach are all further off than Mist lets
# them see in, keeping reserve for healing. Two Sentinels don't cast on the same spot.
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
	unit.global_position = point
	return unit
## A round of spells, with the fog brought up to date first (the AI sees by it).
func think(ai: Node) -> void:
	var fog = game.fog_of_war()
	if fog != null: fog.update_now()
	ai._spells()
func run() -> void:
	var setup = root.get_node("MatchSetup")
	setup.configured = true
	setup.mode = "ai"
	setup.map_id = "two_lakes"
	setup.factions = {"player": &"cyborgs", "enemy": &"arthurian_knights"}
	game = load(setup.map_path()).instantiate()
	root.add_child(game)
	for frame in range(3): await process_frame
	var ai: Node = game.enemy_player()
	ai.set_process(false)
	for node in get_nodes_in_group("units"): node.set_process(false)
	# Research: Slow after level 1 of each line.
	ai.upgrades_army = 0
	var wanted: Array = ai.research_wanted()
	wanted.erase(Research.MINING_TRAINS)
	if not check(wanted.slice(0,3) == [&"arms_1",&"mail_1",Research.SLOW],"Slow comes after Arms I and Mail I: %s" % [wanted]): return
	# A field in the open, away from both bases.
	var here := Vector3(0,0,0)
	var sentinel := spawn("grail_sentinel","enemy",here)
	await process_frame
	ai._sort(ai.own_units())
	if not check(ai.army.has(sentinel),"The Sentinel is in the army"): return
	# Scattered foes 20 m off: no Slow (and Slow not researched yet).
	var foes: Array[Node3D] = []
	for i in range(3): foes.append(spawn("infantry","player",here+Vector3(18,0,-12+12*i)))
	think(ai)
	if not check(sentinel.order != "slow","No Slow before the research"): return
	Research.complete(game,"enemy",Research.SLOW)
	think(ai)
	if not check(sentinel.order != "slow","No Slow on a scattered few"): return
	# Clumped: Slow on them.
	for i in range(3): foes[i].global_position = here+Vector3(18,0,i*1.5)
	think(ai)
	if not check(sentinel.order == "slow","A clump of 3 is slowed: %s" % sentinel.state): return
	for i in range(60): sentinel._process(1.0/30)
	if not check(sentinel.order == "idle" and foes.all(func(foe): return foe.speed_scale() < 1.0),"The Sentinel casts Slow and the clump is slowed: %s" % sentinel.state): return
	# A second Sentinel doesn't cast on the same spot.
	var second := spawn("grail_sentinel","enemy",here+Vector3(0,0,3))
	await process_frame
	ai._sort(ai.own_units())
	think(ai)
	if not check(second.order != "slow" and sentinel.order != "slow","No second Slow on the same spot"): return
	# Short of reserve beyond what it keeps for healing: no cast.
	ai._casts.clear()
	sentinel.med_reserve = sentinel.spell_cost("slow")+ai.spell_keep-1
	second.med_reserve = sentinel.med_reserve
	think(ai)
	if not check(sentinel.order != "slow" and second.order != "slow","It keeps %d reserve for healing" % ai.spell_keep): return
	# Mist: four friends round a Sentinel, the foes 20 m off and scattered.
	second.queue_free()
	sentinel.med_reserve = sentinel.med_reserve_capacity
	for i in range(3): foes[i].global_position = here+Vector3(20,0,-12+12*i)
	for i in range(3): spawn("round_table_marine","enemy",here+Vector3(-2+2*i,0,2))
	await process_frame
	ai._sort(ai.own_units())
	think(ai)
	if not check(sentinel.order == "mist","Mist over four friends under fire from 20 m: %s" % sentinel.state): return
	for i in range(30): sentinel._process(1.0/30)
	if not check(not get_nodes_in_group("mists").is_empty(),"The Mist is cast"): return
	# A foe close enough to see in: no Mist.
	for mist in get_nodes_in_group("mists"): mist.free()
	ai._casts.clear()
	foes[0].global_position = here+Vector3(10,0,0)
	think(ai)
	if not check(sentinel.order != "mist","No Mist with a foe 10 m off"): return
	setup.configured = false
	print("AI_SPELLS_TEST_PASSED")
	quit(0)
