extends SceneTree
# Headless (item 6 of the Round 3 handoff; docs/ROUND3_HEARTH_WAIN.md):
# - A Keep no longer refills a Grail Sentinel's reserve. A manned, unraided Farm does (the Living Draught): 15 points
#   a 1.2 s beat to a Sentinel on or beside it, each such Sentinel taking 1 Food off the Farm's next payout. An
#   unmanned or raided Farm gives nothing.
# - The Dragon Yard trains a Hearth-Wain. It drives to a lakeshore and pitches (2 s): a 15 m Knights supply that pays
#   a Farm plan from its hold. A Forester Maiden builds a Forward Lakeside Farm there (3 Food a beat) and works it
#   into the Wain's hold. The Wain refills a Sentinel within 9 m from its Food, 10 points for 1 Food. Packed up, it
#   leaves the Farm dormant: no Food, and its label says so.
# - The Knights AI sends an idle Sentinel short of reserve to stand on a working Farm, keeps it off the rally point
#   while it refills, and lets it go once full.
var game: Node3D
var network: Node
var setup: Node
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> bool:
	if value: return true
	push_error(message); quit(1); return false
func open(path: String) -> void:
	if is_instance_valid(game): game.free()
	game = load(path).instantiate()
	root.add_child(game)
	for frame in range(3): await process_frame
	network = game.get_node("DepotNetwork")
	game.set_process(false)
	game.get_node("Interface").set_process(false)
	var ai = game.get_node_or_null("EnemyPlayer")
	if ai != null: ai.set_process(false)
	for group in ["units","depots","production_buildings","farms","houses","energy_generators","mines"]:
		for node in get_nodes_in_group(group): node.set_process(false)
	# Sight is not what this checks: plans and previews go anywhere.
	for fog in get_nodes_in_group("fog_of_war"): fog.free()
func two_lakes(player: StringName, enemy: StringName) -> void:
	setup.configured = true
	setup.mode = "ai"
	setup.map_id = "two_lakes"
	setup.factions = {"player": player, "enemy": enemy}
	await open(setup.map_path())
func place(node: Node3D, point: Vector3) -> void:
	for cell in node._claimed.duplicate(): node._release(cell)
	node._stop_route()
	node.grid_position = game.ground.nearest_actor_cell(game.ground.get_tile_at_position(point),node.mobility_layer(),node._owner_key())
	node.global_position = game.ground.tile_to_world(node.grid_position)
	node._claim(node.grid_position)
func step(nodes: Array, seconds: float, until := Callable()) -> float:
	var t := 0.0
	while t < seconds:
		for node in nodes:
			if is_instance_valid(node): node._process(1.0/30)
		t += 1.0/30
		if until.is_valid() and until.call(): break
	return t
## A plan finished at once from its materials, as the playtest tools do.
func stand(kind: StringName, point: Vector3, team := "player") -> Node3D:
	var plan = network.queue_plan(point,kind,null,false,false,team)
	if plan == null: return null
	var building = network.finish_plan(plan)
	plan.queue_free()
	return building
func stand_near(kind: StringName, keep: Node3D, team := "player") -> Node3D:
	for offset in [Vector3(0,0,16),Vector3(0,0,-16),Vector3(16,0,0),Vector3(-16,0,0),Vector3(-14,0,8),Vector3(14,0,-12),Vector3(-12,0,-14),Vector3(10,0,14),Vector3(18,0,0),Vector3(0,0,-18)]:
		var made := stand(kind,keep.global_position+offset,team)
		if made != null: return made
	return null
## Houses by `keep` until the side has room for a `id`.
func house_for(id: StringName, keep: Node3D, team := "player") -> bool:
	for i in range(8):
		if KnightHousing.room(self,team,id): return true
		var spot: Vector3 = keep.global_position+Vector3(cos(i*TAU/8),0,sin(i*TAU/8))*22.0
		var house := stand(&"house",spot,team)
		if house != null: house.set_process(false)
	return KnightHousing.room(self,team,id)
func spawn(scene: String, team: String, point: Vector3) -> Node3D:
	var unit = load(scene).instantiate()
	unit.team = team
	game.get_node("Entities/Units").add_child(unit)
	unit.set_process(false)
	place(unit,point)
	return unit
func keep_of(team: String) -> Node3D:
	for node in get_nodes_in_group("keeps"):
		if node.team == team: return node
	return null
func maiden_of(team: String) -> Node3D:
	for unit in get_nodes_in_group("units"):
		if unit.team == team and unit.get("unit_stats") != null and unit.unit_stats.unit_id == &"forester_maiden" and not unit.farmer: return unit
	return null
func run() -> void:
	setup = root.get_node("MatchSetup")
	if not await draught(): return
	if not await hearth(): return
	if not await ai(): return
	# The data last: loading these stats before the first map can leave a script in use at exit.
	if not data(): return
	setup.configured = false
	game.free()
	print("HEARTH_WAIN_AND_FORWARD_FARM_TEST_PASSED")
	quit(0)
func data() -> bool:
	var rules: KnightsRules = load("res://assets/economy/knights_rules.tres")
	if not check(rules.hearth_radius == 15.0 and rules.hearth_medic_radius == 9.0 and rules.hearth_medic_points == 10 and rules.hearth_medic_food == 1,"Hearth: 15 m supply; Sentinels within 9 m, 10 points for 1 Food"): return false
	if not check(rules.draught_reach == 3.0 and rules.draught_points == 15 and rules.draught_beat_seconds == 1.2 and rules.draught_food == 1,"Living Draught: within 3 m, 15 points a 1.2 s beat, 1 Food each"): return false
	if not check(rules.housing.get(&"hearth_wain") == 1,"A Hearth-Wain takes 1 housing"): return false
	var stats: UnitStats = load("res://assets/units/hearth_wain.tres")
	if not check(stats.food_cost == 60 and stats.wood_cost == 35 and stats.iron_cost == 20 and stats.energy_cost == 0 and stats.build_seconds == 16.0,"A Hearth-Wain costs 60 F / 35 W / 20 I and trains in 16 s"): return false
	var yard: ProductionBuildingStats = load("res://assets/buildings/dragon_yard.tres")
	if not check(yard.unit_scenes.any(func(scene): return scene.resource_path == "res://scenes/gameplay/hearth_wain.tscn"),"The Dragon Yard trains Hearth-Wains"): return false
	return true
## A Keep gives nothing; a manned Farm's Living Draught does, and costs its payout a Food per Sentinel.
func draught() -> bool:
	await open("res://scenes/maps/arthurian_skirmish.tscn")
	var keep := keep_of("player")
	for kind in [&"food",&"wood",&"iron"]: keep.stockpile.deposit(kind,400)
	var sentinel := spawn("res://scenes/gameplay/grail_sentinel.tscn","player",keep.global_position+Vector3(0,0,8))
	var second := spawn("res://scenes/gameplay/grail_sentinel.tscn","player",keep.global_position+Vector3(2,0,8))
	for unit in [sentinel,second]:
		unit.heal_autocast = false
		unit.med_reserve = 50
	if not check(sentinel.med_refill_points == 8,"A Food crate refills 8 points a Food"): return false
	step([sentinel],5.0)
	if not check(sentinel.med_reserve == 50,"A Keep should not refill a Sentinel: %d" % sentinel.med_reserve): return false
	if not check(game.get_node("Interface").card.get_node_or_null("ProduceHearthWain") != null,"The Dragon Yard card has a Hearth-Wain tile"): return false
	# A Farm by the Keep, unmanned: nothing.
	var farm := stand_near(&"farm",keep)
	if not check(farm != null and farm.covered(),"A Farm should stand in the Keep's range"): return false
	farm.set_process(false)
	var on_field: Vector3 = farm.global_position
	place(sentinel,on_field)
	place(second,on_field+Vector3(2,0,0))
	if not check(farm.on_field(sentinel.global_position) and farm.distance_to_field(second.global_position) <= 3.0,"The Sentinels should stand on the Farm"): return false
	step([sentinel,second],3.0)
	if not check(sentinel.med_reserve == 50 and not farm.provides_draught(),"An unmanned Farm gives no Draught: %d" % sentinel.med_reserve): return false
	# Manned: 15 points a 1.2 s beat to each.
	var farmer := maiden_of("player")
	place(farmer,farm.global_position+Vector3(0,0,7))
	farmer.command_gather(farm)
	if not check(farmer.farmer and farm.provides_draught(),"The Maiden should till the Farm and it should give the Draught"): return false
	farm.extract(10,"player") # clears any earlier provisioning
	for unit in [sentinel,second]: unit._med_refill_timer = 0.0
	step([sentinel,second],1.25)
	if not check(sentinel.med_reserve == 65 and second.med_reserve == 65,"One beat should give each Sentinel 15 points: %d / %d" % [sentinel.med_reserve,second.med_reserve]): return false
	# Two Sentinels drew on it: its next payout is 2 Food short; the one after is whole again.
	var beat: int = farm.food_per_beat()
	if not check(farm.extract(10,"player") == beat-2 and farm.extract(10,"player") == beat,"Each Sentinel should take a Food off the next payout"): return false
	farm.update_label()
	if not check(farm.get_node("Label").text.contains("Provisioning Grail"),"The Farm's label should say it provisions: '%s'" % farm.get_node("Label").text): return false
	sentinel._med_refill_timer = 0.0
	step([sentinel,second],2.5)
	if not check(sentinel.med_reserve == 95,"Two more beats: %d" % sentinel.med_reserve): return false
	# Raided: nothing.
	farm.raided = true
	step([sentinel],3.0)
	if not check(sentinel.med_reserve == 95,"A raided Farm gives no Draught: %d" % sentinel.med_reserve): return false
	farm.raided = false
	# Beside the field but more than 3 m off it: nothing.
	place(second,farm.global_position+Vector3(0,0,(farm.field_rect().size.y*game.ground.tile_size)/2.0+5.0))
	var before: int = second.med_reserve
	step([second],3.0)
	if not check(farm.distance_to_field(second.global_position) > 3.0 and second.med_reserve == before,"More than 3 m off the field, no Draught: %.1f m, %d -> %d" % [farm.distance_to_field(second.global_position),before,second.med_reserve]): return false
	return true
## The lakeside field nearest the player's Keep outside every Keep's range (on Two Lakes about 130 m off).
func forward_field(keep: Node3D, size: Vector2i) -> Vector2i:
	var Farm = load("res://scripts/economy/farm.gd")
	var best := Vector2i(-1,-1)
	var best_distance := INF
	for z in range(20,480,2):
		for x in range(20,480,2):
			var start := Vector2i(x,z)
			var centre: Vector3 = game.ground.tile_to_world(start+size/2)
			var distance: float = centre.distance_to(keep.global_position)
			if distance >= best_distance or distance > 160.0: continue
			if get_nodes_in_group("keeps").any(func(k): return k.global_position.distance_to(centre) <= SupplySource.radius(k)+4.0): continue
			if not open_field(start,size) or not Farm.lakeside_at(game.ground,start,size): continue
			best = start; best_distance = distance
	return best
func open_field(start: Vector2i, size: Vector2i) -> bool:
	for z in range(start.y-1,start.y+size.y+1):
		for x in range(start.x-1,start.x+size.x+1):
			var cell := Vector2i(x,z)
			if not game.ground.is_tile_in_bounds(cell) or game.ground.get_terrain(cell) != 0 or not game.ground.is_tile_valid(cell): return false
	return true
## The Dragon Yard trains a Wain; it drives to a lakeshore and pitches; a Forward Lakeside Farm works into its hold;
## it refills a Sentinel from its Food; packed up, the Farm lies dormant.
func hearth() -> bool:
	await two_lakes(&"arthurian_knights",&"cyborgs")
	var keep := keep_of("player")
	for kind in [&"food",&"wood",&"iron"]: keep.stockpile.deposit(kind,600)
	var yard := stand_near(&"dragon_yard",keep)
	if not check(yard != null,"A Dragon Yard should stand by the Keep"): return false
	yard.set_process(false)
	if not check(yard.assign_source(keep),"The Dragon Yard should draw on the Keep"): return false
	if not check(house_for(&"hearth_wain",keep),"Houses should make room for a Hearth-Wain: %s" % KnightHousing.text(self,"player")): return false
	var food_before: int = keep.food
	if not check(yard.request_unit(&"hearth_wain"),"The Dragon Yard should take a Hearth-Wain: "+game.message): return false
	if not check(food_before-keep.food == 60,"A Hearth-Wain should take 60 Food: %d" % (food_before-keep.food)): return false
	var seconds := 0.0
	while yard.queue > 0 and seconds < 30.0:
		yard._process(1.0/30)
		seconds += 1.0/30
	var wains := get_nodes_in_group("hearth_wains")
	if not check(wains.size() == 1 and absf(seconds-16.0) < 0.1,"The Dragon Yard should train one Hearth-Wain in 16 s: %d in %.2f s" % [wains.size(),seconds]): return false
	var wain: Node3D = wains[0]
	wain.set_process(false)
	if not check(game.get_node("Interface").object_name(wain) == "Hearth-Wain" and SupplySource.radius(wain) == 15.0,"It is a Hearth-Wain with a 15 m supply"): return false
	# Its hold for the trip: wood for the Farm and Food for the Sentinel.
	wain.stockpile.deposit(&"wood",40)
	wain.stockpile.deposit(&"food",20)
	# To a lakeshore beyond every Keep's range.
	var size: Vector2i = load("res://assets/economy/knights_rules.tres").farm_footprint
	var field := forward_field(keep,size)
	if not check(field.x >= 0,"Two Lakes should have a lakeside field beyond the Keep's range"): return false
	var centre: Vector3 = game.ground.tile_to_world(field+size/2)
	var toward_keep: Vector3 = (keep.global_position-centre)*Vector3(1,0,1)
	var camp: Vector3 = centre+toward_keep.normalized()*9.0
	# The plan is refused before the Wain is there.
	if not check(network.queue_plan(centre,&"farm",null,false,false) == null,"A Farm beyond every Keep's range is refused while no Wain is pitched"): return false
	wain.command_move(camp)
	var drove := step([wain],120.0,func(): return wain.order != "move" and wain.global_position.distance_to(camp) < 4.0)
	if not check(wain.global_position.distance_to(camp) < 4.0,"The Wain should drive to the lakeshore: %.1f m off after %.0f s ('%s')" % [wain.global_position.distance_to(camp),drove,wain.state]): return false
	if not check(wain.deploy_supplies(),"The Wain should pitch"): return false
	step([wain],1.0)
	if not check(not wain.pitched(),"Pitching takes 2 s"): return false
	step([wain],1.1)
	if not check(wain.pitched() and SupplySource.covers(wain,centre,"player"),"Pitched, the Wain covers the field"): return false
	# A Maiden builds a Forward Lakeside Farm from the Wain's wood.
	var wood_before: int = wain.wood
	var plan = network.queue_plan(centre,&"farm",null,false,false)
	if not check(plan != null,"A Farm should be planned in the pitched Wain's range: "+game.message): return false
	var maiden := maiden_of("player")
	place(maiden,centre+toward_keep.normalized()*7.0)
	maiden.command_construct(plan)
	step([maiden,plan,wain],60.0,func(): return not is_instance_valid(plan) or plan.is_queued_for_deletion())
	var farm: Node3D = null
	for node in get_nodes_in_group("farms"):
		if node.global_position.distance_to(centre) < 3.0: farm = node
	if not check(farm != null,"The Maiden should build the Farm: '%s'" % maiden.state): return false
	farm.set_process(false)
	var rules: KnightsRules = load("res://assets/economy/knights_rules.tres")
	if not check(wood_before-wain.wood == rules.farm_wood_cost,"The Farm should take %d wood from the Wain's hold: %d" % [rules.farm_wood_cost,wood_before-wain.wood]): return false
	if not check(farm.lakeside and farm.food_per_beat() == 3 and farm.covered(),"A Forward Lakeside Farm: 3 Food a beat, covered by the Wain"): return false
	# She works it into the Wain's hold.
	maiden.command_gather(farm)
	if not check(maiden.farmer,"The Maiden should become its Farmer"): return false
	var food: int = wain.food
	step([maiden,farm],40.0,func(): return wain.food > food)
	if not check(wain.food > food and keep.food == food_before-60,"The Farm's Food should go to the Wain, not the Keep: %d -> %d" % [food,wain.food]): return false
	# The Wain refills a Sentinel within 9 m, more than 3 m off the field: 10 points for 1 Food.
	var away: Vector3 = wain.global_position+toward_keep.normalized()*4.0
	var sentinel := spawn("res://scenes/gameplay/grail_sentinel.tscn","player",away)
	sentinel.heal_autocast = false
	sentinel.med_reserve = 100
	if not check(MedicalWork.draught_farm(sentinel) == null and MedicalWork.hearth_for(sentinel) == wain,"The Sentinel should draw on the Wain, not the Farm: %.1f m from the Wain, %.1f m off the field" % [sentinel.global_position.distance_to(wain.global_position),farm.distance_to_field(sentinel.global_position)]): return false
	food = wain.food_on_hand()
	step([sentinel],0.85)
	if not check(sentinel.med_reserve == 110 and wain.food_on_hand() == food-1,"One Food should give 10 points: %d, Food %d -> %d" % [sentinel.med_reserve,food,wain.food_on_hand()]): return false
	# Packed up, the Farm lies dormant.
	wain.pack_supplies()
	step([wain],2.1)
	if not check(not wain.pitched() and not farm.covered(),"Packed, the Wain covers nothing"): return false
	if not check(farm.extract(10,"player") == 0,"A dormant Farm pays nothing"): return false
	farm._process(rules.farm_raid_check_seconds+0.1)
	if not check(farm.dormant and farm.get_node("Label").text.contains("Dormant"),"The Farm's label should say it is dormant: '%s'" % farm.get_node("Label").text): return false
	if not check(not farm.provides_draught(),"A dormant Farm gives no Draught"): return false
	return true
## The Knights AI parks an idle Sentinel short of reserve on a working Farm, holds it there, and lets it go when full.
func ai() -> bool:
	await two_lakes(&"cyborgs",&"arthurian_knights")
	var knights = game.enemy_player()
	knights.set_process(false)
	var keep: Node3D = knights.home()
	for kind in [&"food",&"wood",&"iron"]: keep.stockpile.deposit(kind,600)
	var farm := stand_near(&"farm",keep,"enemy")
	if not check(farm != null,"A Farm should stand by the AI's Keep"): return false
	farm.set_process(false)
	var farmer := maiden_of("enemy")
	place(farmer,farm.global_position+Vector3(0,0,7))
	farmer.command_gather(farm)
	if not check(farm.provides_draught(),"The AI's Farm should be tilled and give the Draught"): return false
	var sentinel := spawn("res://scenes/gameplay/grail_sentinel.tscn","enemy",keep.global_position+Vector3(30,0,0))
	sentinel.heal_autocast = false
	knights._sort(knights.own_units())
	if not check(knights.army.has(sentinel),"The Sentinel should join the AI's army"): return false
	# Full: it stays.
	knights._medics()
	if not check(not knights.kept_off_rally(sentinel) and sentinel.order != "move","A full Sentinel should not go to the Farm"): return false
	# Short: it goes, and fight() leaves it be.
	sentinel.med_reserve = 30
	knights._medics()
	if not check(knights.kept_off_rally(sentinel) and sentinel.order == "move" and farm.distance_to_field(sentinel.move_goal) <= 0.5,"A Sentinel short of reserve should go to the Farm: %s" % sentinel.order): return false
	var arrived := step([sentinel],60.0,func(): return farm.distance_to_field(sentinel.global_position) <= 1.5 and sentinel.order != "move")
	if not check(farm.distance_to_field(sentinel.global_position) <= 1.5,"The Sentinel should reach the Farm: %.1f m off after %.0f s ('%s')" % [farm.distance_to_field(sentinel.global_position),arrived,sentinel.state]): return false
	knights.fight(keep)
	if not check(sentinel.order != "move" or farm.distance_to_field(sentinel.move_goal) <= 0.5,"fight() should not call a refilling Sentinel to the rally point"): return false
	step([sentinel,farmer],20.0,func(): return sentinel.med_reserve >= sentinel.med_reserve_capacity)
	if not check(sentinel.med_reserve == sentinel.med_reserve_capacity,"It should refill on the Farm: %d" % sentinel.med_reserve): return false
	# Full: let go, and fight() calls it back.
	knights._medics()
	if not check(not knights.kept_off_rally(sentinel),"A full Sentinel should be let go"): return false
	knights.fight(keep)
	var rally: Vector3 = knights.rally_point(keep)
	if not check(sentinel.order == "move" and sentinel.move_goal.distance_to(rally) < 10.0,"Once full it should head back to the rally point: %s" % sentinel.order): return false
	return true
