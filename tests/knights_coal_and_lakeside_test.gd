extends SceneTree
# Headless (item 5 of the Round 3 handoff; docs/ROUND3_KNIGHTS_COAL.md):
# - Forge research and the Dragon Yard's Azure Dragon cost Coal from the Keep, and wait without it.
# - A Stoke Brazier finishes a 15 s Round Table Marine in 9.375 s, burning 1 Coal every 4 s; with no Coal it
#   prints at 1x and says so, and once the Coal runs out it goes on at 1x.
# - A Farm within 8 m of lake water gives 3 Food a beat, an inland one 2, and the placement preview says so.
# - The Knights AI opens a Coal Mine once it has a Forge (not before), gathers toward the next research's Coal
#   plus the Braziers' floor, and lights its Braziers while the Keep holds more than 100 Coal.
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
	for group in ["units","depots","production_buildings","farms","houses","energy_generators","mines","fog_of_war"]:
		for node in get_nodes_in_group(group): node.set_process(false)
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
## Queues a Marine, first clearing away the ones already made so housing never runs short.
func marine(hall: Node3D, keep: Node3D) -> bool:
	for unit in get_nodes_in_group("units"):
		if unit.team == "player" and unit.get("unit_stats") != null and unit.unit_stats.unit_id == &"round_table_marine": unit.queue_free()
	return house_for(&"round_table_marine",keep) and hall.request_unit(&"round_table_marine")
## Seconds of 1/60 s frames until `building` hands over its head unit.
func run_until_produced(building: Node3D, limit: float, during := Callable()) -> float:
	var start: int = building.queue
	var seconds := 0.0
	while building.queue == start and seconds < limit:
		building._process(1.0/60)
		seconds += 1.0/60
		if during.is_valid(): during.call(seconds)
	return seconds
func empty(keep: Node3D, kind: StringName) -> void:
	var held: int = keep.stockpile.amount(kind)
	if held > 0: keep.stockpile.withdraw(kind,held)
func run() -> void:
	setup = root.get_node("MatchSetup")
	if not await forge_and_dragon(): return
	if not await brazier(): return
	if not await lakeside(): return
	if not await ai(): return
	# The data last: loading these stats before the first map left a script (fuel_rules.gd) in use at exit.
	if not data(): return
	setup.configured = false
	game.free()
	print("KNIGHTS_COAL_AND_LAKESIDE_TEST_PASSED")
	quit(0)
func data() -> bool:
	for line in [&"arms",&"mail"]:
		for n in range(1,4):
			var entry: ResearchStats = load("res://assets/research/upgrades/%s_%d.tres" % [line,n])
			if not check(entry.coal_cost == 75*n,"%s %d should cost %d Coal: %d" % [line,n,75*n,entry.coal_cost]): return false
	var slow: ResearchStats = load("res://assets/research/slow.tres")
	if not check(slow.food_cost == 100 and slow.iron_cost == 125 and slow.coal_cost == 75,"Slow: 100 F / 125 I / 75 C"): return false
	if not check(load("res://assets/units/azure_dragon.tres").coal_cost == 25,"The Azure Dragon costs 25 Coal"): return false
	for id in ["chapterhouse","dragon_yard","forge"]:
		var stats: ProductionBuildingStats = load("res://assets/buildings/%s.tres" % id)
		if not check(stats.can_stoke_brazier and stats.stoked_speed == 1.6 and stats.brazier_coal_interval == 4.0,"%s should stoke a brazier at 1.6x for 1 Coal / 4 s" % id): return false
	for id in ["barracks","tank_factory"]:
		if not check(not load("res://assets/buildings/%s.tres" % id).can_stoke_brazier,"The Cyborgs' %s has no brazier" % id): return false
	var rules: KnightsRules = load("res://assets/economy/knights_rules.tres")
	if not check(rules.lakeside_water_distance == 8.0 and rules.lakeside_food_per_beat == 3 and rules.farm_food_per_beat == 2,"Lakeside: within 8 m, 3 Food a beat (inland 2)"): return false
	return true
func forge_and_dragon() -> bool:
	await open("res://scenes/maps/arthurian_skirmish.tscn")
	var keep = game.get_node("Entities/Buildings/Keep")
	for kind in [&"food",&"iron"]: keep.stockpile.deposit(kind,600)
	var forge := stand_near(&"forge",keep)
	if not check(forge != null,"A Forge should stand by the Keep"): return false
	forge.set_process(false)
	var arms: ResearchStats = forge.research_by_id(&"arms_1")
	if not check(forge.cost_text(arms) == "100 F · 150 I · 75 C","Arms I costs '%s'" % forge.cost_text(arms)): return false
	empty(keep,&"coal")
	if not check(forge.research_blocker(&"arms_1").contains("75 C"),"Without Coal Arms I should wait: '%s'" % forge.research_blocker(&"arms_1")): return false
	keep.stockpile.deposit(&"coal",100)
	if not check(forge.request_research(&"arms_1") and keep.coal == 25,"Arms I should take 75 Coal from the Keep (%d left)" % keep.coal): return false
	var yard := stand_near(&"dragon_yard",keep)
	if not check(yard != null,"A Dragon Yard should stand by the Keep"): return false
	yard.set_process(false)
	if not check(house_for(&"azure_dragon",keep),"Houses should make room for a Dragon: %s" % KnightHousing.text(self,"player")): return false
	empty(keep,&"coal")
	if not check(not yard.request_unit(&"azure_dragon") and game.message.contains("25 C"),"Without Coal the Dragon should wait: '%s'" % game.message): return false
	keep.stockpile.deposit(&"coal",30)
	if not check(yard.request_unit(&"azure_dragon") and keep.coal == 5,"The Dragon should take 25 Coal from the Keep (%d left)" % keep.coal): return false
	return true
func brazier() -> bool:
	await open("res://scenes/maps/arthurian_skirmish.tscn")
	var keep = game.get_node("Entities/Buildings/Keep")
	var hall = game.get_node("Entities/Buildings/Chapterhouse")
	for kind in [&"food",&"iron"]: keep.stockpile.deposit(kind,600)
	empty(keep,&"coal")
	var hud = game.get_node("Interface")
	if not check(hud.card.get_node_or_null("StokeBrazier") != null,"The command card has a Stoke Brazier tile"): return false
	if not check(house_for(&"round_table_marine",keep),"Houses should make room for a Marine: %s" % KnightHousing.text(self,"player")): return false
	hall.set_brazier(true)
	if not check(hall.brazier_on,"The Chapterhouse's brazier should be on"): return false
	# No Coal: 15 s at 1x, and the status says why.
	if not check(marine(hall,keep),"A Marine should queue: "+game.message): return false
	var notes: Array[String] = []
	var seconds := run_until_produced(hall,30,func(t): if notes.is_empty() and t > 1.0: notes.append(hall.get_node("Status").text))
	if not check(absf(seconds-15.0) < 0.03,"With no Coal a Marine takes 15 s: %.3f" % seconds): return false
	if not check(notes.size() == 1 and notes[0].contains("Brazier unlit · needs Coal"),"The status should say the brazier needs Coal: %s" % [notes]): return false
	# One Coal: 4 s at 1.6x (6.4 s of work), then the other 8.6 s at 1x.
	keep.stockpile.deposit(&"coal",1)
	if not check(marine(hall,keep),"A second Marine should queue: "+game.message): return false
	seconds = run_until_produced(hall,30)
	if not check(absf(seconds-12.6) < 0.05 and keep.coal == 0,"One Coal should burn 4 s, then 1x: %.3f s, %d Coal left" % [seconds,keep.coal]): return false
	# Plenty of Coal: 15 / 1.6 = 9.375 s, burning 3 Coal (at 0, 4 and 8 s).
	keep.stockpile.deposit(&"coal",100)
	if not check(marine(hall,keep),"A third Marine should queue: "+game.message): return false
	notes.clear()
	seconds = run_until_produced(hall,30,func(t): if notes.is_empty() and t > 1.0: notes.append(hall.get_node("Status").text))
	if not check(absf(seconds-9.375) < 0.03,"A stoked Marine takes 9.375 s: %.3f" % seconds): return false
	if not check(keep.coal == 97,"It should burn 3 Coal: %d left" % keep.coal): return false
	if not check(notes.size() == 1 and notes[0].contains("Brazier lit"),"The status should say the brazier is lit: %s" % [notes]): return false
	# Off: 1x and nothing burnt.
	hall.set_brazier(false)
	if not check(marine(hall,keep),"A fourth Marine should queue: "+game.message): return false
	seconds = run_until_produced(hall,30)
	if not check(absf(seconds-15.0) < 0.03 and keep.coal == 97,"With the brazier off a Marine takes 15 s and burns nothing: %.3f s, %d Coal" % [seconds,keep.coal]): return false
	return true
## A field `size` at `start` all on grass.
func open_field(start: Vector2i, size: Vector2i) -> bool:
	for z in range(start.y,start.y+size.y):
		for x in range(start.x,start.x+size.x):
			var cell := Vector2i(x,z)
			if not game.ground.is_tile_in_bounds(cell) or game.ground.get_terrain(cell) != 0 or not game.ground.is_tile_valid(cell): return false
	return true
func farm_at(start: Vector2i, size: Vector2i, team: String) -> Node3D:
	var farm = load("res://scenes/gameplay/farm.tscn").instantiate()
	farm.team = team
	farm.position = game.ground.tile_to_world(start+size/2)
	game.get_node("Entities/Buildings").add_child(farm)
	farm.set_process(false)
	return farm
func lakeside() -> bool:
	setup.configured = true
	setup.mode = "ai"
	setup.map_id = "two_lakes"
	setup.factions = {"player": &"arthurian_knights", "enemy": &"cyborgs"}
	await open(setup.map_path())
	var Farm = load("res://scripts/economy/farm.gd")
	var size: Vector2i = load("res://assets/economy/knights_rules.tres").farm_footprint
	var keep: Node3D = null
	for node in get_nodes_in_group("keeps"):
		if node.team == "player": keep = node
	if not check(keep != null,"The Knights should start with a Keep on Two Lakes"): return false
	for kind in [&"food",&"wood",&"iron"]: keep.stockpile.deposit(kind,500)
	# An open field by the water and one far from it.
	var wet := Vector2i(-1,-1)
	var dry := Vector2i(-1,-1)
	for z in range(20,480,2):
		for x in range(20,480,2):
			var start := Vector2i(x,z)
			if (wet.x >= 0 and dry.x >= 0) or not open_field(start,size): continue
			var by_water: bool = Farm.lakeside_at(game.ground,start,size)
			if by_water and wet.x < 0: wet = start
			# The inland field is taken in the starting Keep's own range, so its preview needs no other Keep.
			elif not by_water and dry.x < 0 and keep.global_position.distance_to(game.ground.tile_to_world(start+size/2)) <= 20.0: dry = start
	if not check(wet.x >= 0 and dry.x >= 0,"Two Lakes should have open fields by a lake and inland: %s %s" % [wet,dry]): return false
	var lake_farm := farm_at(wet,size,"player")
	var inland_farm := farm_at(dry,size,"player")
	if not check(lake_farm.lakeside and not inland_farm.lakeside,"Only the field by the lake is lakeside"): return false
	# Since item 6 a Farm with no Keep or pitched Hearth-Wain over it lies dormant and pays nothing
	# (tests/hearth_wain_and_forward_farm_test.gd); the starting Keep covers the inland field.
	if not check(lake_farm.food_per_beat() == 3 and lake_farm.extract(10,"player") == (3 if lake_farm.covered() else 0),"A lakeside Farm gives 3 Food a beat"): return false
	if not check(inland_farm.food_per_beat() == 2 and inland_farm.extract(10,"player") == 2,"An inland Farm gives 2 Food a beat"): return false
	lake_farm.update_label(); inland_farm.update_label()
	if not check(lake_farm.get_node("Label").text.begins_with("LAKESIDE FARM · 3 Food/beat") and inland_farm.get_node("Label").text.begins_with("FARM ·"),"Labels: '%s' / '%s'" % [lake_farm.get_node("Label").text,inland_farm.get_node("Label").text]): return false
	# Water just past 8 m from the field's edge does not count.
	var reach: int = 8
	var beyond := false
	for z in range(wet.y-reach-1,wet.y+size.y+reach+1):
		for x in range(wet.x-reach-1,wet.x+size.x+reach+1):
			if game.ground.get_terrain(Vector2i(x,z)) == 1: beyond = true
	if not check(beyond,"The lakeside field has water near it"): return false
	lake_farm.queue_free(); inland_farm.queue_free()
	await process_frame
	# The placement preview: a Keep's range over each field, with the fog lifted (sight is not what this checks).
	for fog in get_nodes_in_group("fog_of_war"): fog.free()
	game.global_plan_kind = &"farm"
	var texts := {}
	for spot in [wet,dry]:
		var centre: Vector3 = game.ground.tile_to_world(spot+size/2)
		var helper: Node3D = null
		if keep.global_position.distance_to(centre) > 20.0:
			for offset in [Vector3(16,0,0),Vector3(-16,0,0),Vector3(0,0,16),Vector3(0,0,-16),Vector3(18,0,10),Vector3(-18,0,-10),Vector3(10,0,18),Vector3(-10,0,-18)]:
				if helper == null: helper = stand(&"keep",centre+offset)
			if not check(helper != null,"A Keep should stand near the field at %s" % spot): return false
			helper.set_process(false)
			for kind in [&"food",&"wood",&"iron"]: helper.stockpile.deposit(kind,500)
		var valid: bool = network.update_global_preview(centre)
		if not check(valid,"The Farm should be placeable at %s: %s" % [spot,network.placement_text]): return false
		texts[spot] = network.placement_text
		if helper != null: helper.queue_free(); await process_frame
	game.global_plan_kind = &""
	if not check(texts[wet].contains("Lakeside bonus: +50% Food"),"The lakeside preview names the bonus: %s" % texts[wet]): return false
	if not check(not texts[dry].contains("Lakeside"),"The inland preview does not: %s" % texts[dry]): return false
	return true
func ai() -> bool:
	setup.configured = true
	setup.mode = "ai"
	setup.map_id = "two_lakes"
	setup.factions = {"player": &"cyborgs", "enemy": &"arthurian_knights"}
	await open(setup.map_path())
	var knights = game.enemy_player()
	knights.set_process(false)
	var keep: Node3D = knights.home()
	for kind in [&"food",&"wood",&"iron"]: keep.stockpile.deposit(kind,600)
	knights._sort(knights.own_units())
	for old in knights.plans.values():
		if is_instance_valid(old): old.cancel()
	knights.plans.clear()
	# One Keep, no Forge, no Dragon Yard: no coal work.
	knights.coal_economy(keep)
	if not check(knights.coal_plan == null and knights.coal_hand == null,"Before a Forge, a second Keep or a Dragon Yard there is no coal work"): return false
	var forge := stand_near(&"forge",keep,"enemy")
	var hall := stand_near(&"chapterhouse",keep,"enemy")
	if not check(forge != null and hall != null,"The Knights AI should have a Forge and a Chapterhouse"): return false
	forge.set_process(false); hall.set_process(false)
	await process_frame
	if not check(knights.has_forge(),"The Forge counts"): return false
	knights.coal_economy(keep)
	if not check(is_instance_valid(knights.coal_plan) or _coal_mine(knights) != null,"With a Forge it should open a Coal Mine"): return false
	# Coal it gathers toward: Arms I's 75 on top of the Braziers' 100, more than the trains' 120.
	knights.upgrades_army = 0
	if not check(knights.coal_target() == 175,"Coal target with Arms I next: %d" % knights.coal_target()): return false
	Research.complete(game,"enemy",&"arms_1")
	Research.complete(game,"enemy",&"mail_1")
	if not check(knights.coal_target() >= 175,"Coal target after level 1: %d" % knights.coal_target()): return false
	# Braziers: lit above 100 Coal, out at 100, paid by the Keep each building draws on.
	for building in [hall,forge]:
		if not check(building.assign_source(keep),"%s should draw on the Keep" % building.name): return false
	empty(keep,&"wood")
	empty(keep,&"coal")
	keep.stockpile.deposit(&"coal",150)
	knights._braziers()
	if not check(hall.brazier_on and forge.brazier_on,"Above 100 Coal its Braziers burn"): return false
	empty(keep,&"coal")
	keep.stockpile.deposit(&"coal",100)
	knights._braziers()
	if not check(not hall.brazier_on and not forge.brazier_on,"At 100 Coal they are out"): return false
	return true
func _coal_mine(knights: Node) -> Node3D:
	return knights._nearest_mine(knights.home().global_position,&"coal")
