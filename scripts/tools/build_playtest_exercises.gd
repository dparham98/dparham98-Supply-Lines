extends SceneTree
## Writes the two Stage 2 and 3 play-test scenes (docs/PLAYTEST_EXERCISES.md), both on Two Lakes with the East Cyborg
## AI as it is, a guard of enemy infantry in the open east of the base and two enemy mines laid beside it:
## - scenes/maps/cyborg_exercise.tscn: the West Cyborg start, well stocked, with a Temple of Science (Minelaying), a
##   Foundry (the four upgrade lines) and a Tank Factory standing, and Derailers, a Drone, an Ubermech, Tanks,
##   Grenadiers and Infantry. It inherits lakes_skirmish.tscn.
## - scenes/maps/knights_exercise.tscn: the West start as the Knights hold it (a Keep for the Depot), with a
##   Chapterhouse, Forge, Dragon Yard and Houses by it, a second Keep further out joined to the first by laid track,
##   coal in both Keeps for trains, and Grail Sentinels, Round Table and Questing Marines, Warhounds and Foresters. A
##   Knights start can't be inherited from Two Lakes (its Depot can't be taken out), so this one is Two Lakes' text
##   with the West Depot and starting units swapped; re-run this after Two Lakes changes.
## Run it headless from the project folder:
##   Godot --headless --path . --script res://scripts/tools/build_playtest_exercises.gd
const BASE := "res://scenes/maps/lakes_skirmish.tscn"
const CYBORG_OUT := "res://scenes/maps/cyborg_exercise.tscn"
const KNIGHTS_OUT := "res://scenes/maps/knights_exercise.tscn"
const SCENES := {
	"keep": "res://scenes/gameplay/keep.tscn",
	"temple": "res://scenes/gameplay/temple_of_science.tscn",
	"foundry": "res://scenes/gameplay/foundry.tscn",
	"factory": "res://scenes/gameplay/tank_factory.tscn",
	"forge": "res://scenes/gameplay/forge.tscn",
	"dragon_yard": "res://scenes/gameplay/dragon_yard.tscn",
	"chapterhouse": "res://scenes/gameplay/chapterhouse.tscn",
	"house": "res://scenes/gameplay/house.tscn",
	"land_mine": "res://scenes/gameplay/land_mine.tscn",
	"infantry": "res://scenes/gameplay/infantry.tscn",
	"grenadier": "res://scenes/gameplay/grenadier.tscn",
	"tank": "res://scenes/gameplay/tank.tscn",
	"motorcycle": "res://scenes/gameplay/motorcycle.tscn",
	"drone": "res://scenes/gameplay/drone.tscn",
	"ubermech": "res://scenes/gameplay/ubermech.tscn",
	"sentinel": "res://scenes/gameplay/grail_sentinel.tscn",
	"round_table": "res://scenes/gameplay/round_table_marine.tscn",
	"questing": "res://scenes/gameplay/questing_marine.tscn",
	"warhound": "res://scenes/gameplay/warhound.tscn",
	"forester": "res://scenes/gameplay/forester_maiden.tscn",
}
const PIECES := {"straight": "res://scenes/gameplay/track_straight.tscn", "curve": "res://scenes/gameplay/track_curve.tscn", "fork_left": "res://scenes/gameplay/track_fork_left.tscn", "fork_right": "res://scenes/gameplay/track_fork_right.tscn"}
## Stock, with the storage raised to hold it: enough for the research lines' first levels and a few of everything.
const DEPOT_STOCK := {"storage_capacity_override": 6000, "initial_energy": 2000, "initial_iron": 1200, "initial_wood": 300, "initial_coal": 300}
const KEEP_STOCK := {"storage_capacity_override": 6000, "initial_food": 1500, "initial_iron": 1200, "initial_wood": 600, "initial_coal": 300}
const KEEP_B_STOCK := {"storage_capacity_override": 2000, "initial_food": 300, "initial_iron": 400, "initial_wood": 100, "initial_coal": 120}
const CYBORG_UNITS := [["motorcycle",2],["drone",1],["ubermech",1],["tank",2],["grenadier",2],["infantry",4]]
const KNIGHT_UNITS := [["sentinel",3],["round_table",4],["questing",2],["warhound",2],["forester",3]]
const GUARD := [["infantry",4],["grenadier",2]]
var game: Node3D
var network: Node
var taken: Array[Rect2] = []
func _initialize() -> void: call_deferred("run")
func fail(message: String) -> void:
	push_error(message)
	quit(1)
func run() -> void:
	if not await cyborgs(): return
	if not await knights(): return
	print("PLAYTEST_EXERCISES_BUILT")
	quit()
func open_base() -> void:
	if is_instance_valid(game):
		game.queue_free()
		await process_frame
	taken.clear()
	game = load(BASE).instantiate()
	root.add_child(game)
	for frame in range(3): await process_frame
	var ai = game.get_node_or_null("EnemyPlayer")
	if ai != null: ai.set_process(false)
	network = game.get_node("DepotNetwork")
	for node in game.get_tree().get_nodes_in_group("selectable_buildings"): reserve(node.global_position,10.0)
func header(ids: Array) -> String:
	var text := ""
	for id in ids: text += "[ext_resource type=\"PackedScene\" path=\"%s\" id=\"x_%s\"]\n" % [SCENES[id],id]
	return text
## The guard and the two enemy mines beside it, east of the West start.
func guard_nodes(home: Vector3) -> String:
	var guard_at = open_point(home+Vector3(75,0,0),home)
	if guard_at == null: return ""
	var spots := unit_spots(guard_at,count(GUARD),1.6)
	if spots.size() < count(GUARD): return ""
	var text := units(GUARD,spots,"enemy","Guard")
	# Two mines on the way to the guard, 12 m short of it: hidden once armed, shown by a detector near them.
	for i in range(2):
		var at: Vector3 = guard_at+Vector3(-12,0,-3+6*i)
		text += "[node name=\"EnemyMine%d\" parent=\"Entities\" instance=ExtResource(\"x_land_mine\")]\nposition = %s\nteam = \"enemy\"\n" % [i+1,var_to_str(at)]
	print("guard at ",guard_at)
	return text

# --- The Cyborg exercise -------------------------------------------------------------------------------------------

func cyborgs() -> bool:
	await open_base()
	var depot: Node3D = game.get_node("Entities/Buildings/Depot")
	var sites := {}
	for pair in [["temple",Vector2i(6,6)],["foundry",Vector2i(6,6)],["factory",Vector2i(6,6)]]:
		sites[pair[0]] = site(depot,pair[1],9.0)
		if sites[pair[0]] == null: fail("No site for the %s" % pair[0]); return false
	var spots := unit_spots(depot.global_position+Vector3(0,0,22),count(CYBORG_UNITS),3.0)
	if spots.size() < count(CYBORG_UNITS): fail("No room for the Cyborg units"); return false
	var guard := guard_nodes(depot.global_position)
	if guard.is_empty(): fail("No open ground for the guard"); return false
	var text := "[gd_scene format=3]\n[ext_resource type=\"PackedScene\" path=\"%s\" id=\"base\"]\n" % BASE
	text += header(["temple","foundry","factory","land_mine","infantry","grenadier","tank","motorcycle","drone","ubermech"])
	text += "\n[node name=\"CyborgExercise\" instance=ExtResource(\"base\")]\n"
	text += "editor_description = \"Built by scripts/tools/build_playtest_exercises.gd (docs/PLAYTEST_EXERCISES.md): the Cyborgs' Stage 2 and 3 changes on Two Lakes, with an enemy guard and two enemy mines to the east.\"\n"
	text += "message = \"Cyborg exercise: Temple (Minelaying), Foundry (upgrades) and Tank Factory stand by the Depot. Enemy guard and two hidden enemy mines to the east.\"\n"
	text += "[node name=\"Depot\" parent=\"Entities/Buildings\"]\n"+props(DEPOT_STOCK)
	text += building("TempleOfScience","temple",sites.temple,"../Depot")
	text += building("Foundry","foundry",sites.foundry,"../Depot")
	text += building("TankFactory","factory",sites.factory,"../Depot")
	text += units(CYBORG_UNITS,spots,"player","")
	text += guard
	save(CYBORG_OUT,text)
	print("Cyborg exercise: Temple %s, Foundry %s, Tank Factory %s" % [sites.temple,sites.foundry,sites.factory])
	return true

# --- The Knights exercise ------------------------------------------------------------------------------------------

func knights() -> bool:
	await open_base()
	# The Knights hold the West start: a Keep where the Depot stands, as the menu's Knights start does.
	var depot: Node3D = game.get_node("Entities/Buildings/Depot")
	var home: Vector3 = depot.global_position
	depot.get_parent().remove_child(depot)
	depot.free()
	for name in ["Infantry","StarterTruck"]:
		var unit = game.get_node_or_null("Entities/Units/"+name)
		if unit != null: unit.get_parent().remove_child(unit); unit.free()
	var keep: Node3D = load(SCENES.keep).instantiate()
	keep.name = "Keep"
	keep.position = home
	keep.storage_capacity_override = 6000
	game.get_node("Entities/Buildings").add_child(keep)
	await process_frame
	keep.stockpile.deposit(&"iron",2000)
	# Keep B stands well away from where the guard will be, so the guard doesn't go for it.
	var guard_at = open_point(home+Vector3(75,0,0),home)
	var keep_b_at = keep_site([home],home,90.0,115.0,guard_at if guard_at != null else home)
	if keep_b_at == null: fail("No site for the second Keep"); return false
	var keep_b: Node3D = load(SCENES.keep).instantiate()
	keep_b.name = "KeepB"
	keep_b.position = keep_b_at
	game.get_node("Entities/Buildings").add_child(keep_b)
	await process_frame
	var sites := {}
	for pair in [["chapterhouse",Vector2i(6,6)],["forge",Vector2i(6,6)],["dragon_yard",Vector2i(6,6)]]:
		sites[pair[0]] = site(keep,pair[1],9.0)
		if sites[pair[0]] == null: fail("No site for the %s" % pair[0]); return false
	var houses: Array = []
	for i in range(3):
		var at = site(keep,KnightHousing.rules().house_footprint,9.0)
		if at == null: fail("No site for House %d" % (i+1)); return false
		houses.append(at)
	# The buildings stand while the track is planned, so it goes round them; a standing Dragon Yard lets the Keep pay
	# for track. Then the suggested line is laid from the Keep to Keep B.
	var standing := [["dragon_yard",sites.dragon_yard],["chapterhouse",sites.chapterhouse],["forge",sites.forge]]
	for at in houses: standing.append(["house",at])
	for pair in standing:
		var node: Node3D = load(SCENES[pair[0]]).instantiate()
		node.position = pair[1]
		game.get_node("Entities/Buildings").add_child(node)
	await process_frame
	var rails = game.get_node("RailNetwork")
	if rails.suggest_route(keep,keep_b) <= 0: fail("No track path from the Keep to Keep B"); return false
	var plan: Array = []
	for entry in rails.pending: plan.append({kind = entry.kind, transform = entry.transform})
	var laid: Array = rails.commit_plan(keep)
	if laid.size() != plan.size(): fail("The suggested track could not be laid: %s" % game.message); return false
	await process_frame
	if rails.loading_pieces(keep,"player").is_empty() or rails.loading_pieces(keep_b,"player").is_empty(): fail("The track doesn't reach both Keeps' loading areas"); return false
	var spots := unit_spots(home+Vector3(0,0,22),count(KNIGHT_UNITS),2.5)
	if spots.size() < count(KNIGHT_UNITS): fail("No room for the Knights units"); return false
	var guard := guard_nodes(home)
	if guard.is_empty(): fail("No open ground for the guard"); return false
	# Two Lakes' text with the West Depot and its two starting units taken out.
	var text := FileAccess.get_file_as_string(BASE)
	var cut := RegEx.create_from_string("\\[node name=\"(Depot|Infantry|StarterTruck)\" parent=\"Entities/(Buildings|Units)\"[^\\n]*\\]\\n(?:[a-z_/]+ = [^\\n]*\\n)*")
	var found := cut.search_all(text)
	if found.size() != 3: fail("Two Lakes' West Depot and units weren't found as expected (%d)" % found.size()); return false
	text = cut.sub(text,"",true)
	var root_line := RegEx.create_from_string("\\[node name=\"[^\"]+\" type=\"Node3D\" groups=\\[\"skirmish\"\\]\\]\\n")
	var root_match := root_line.search(text)
	if root_match == null: fail("No root node in Two Lakes"); return false
	text = text.replace(root_match.get_string(),"[node name=\"KnightsExercise\" type=\"Node3D\" groups=[\"skirmish\"]]\n")
	text = RegEx.create_from_string("(?m)^editor_description = \"Two Lakes[^\\n]*$").sub(text,"editor_description = \"Built by scripts/tools/build_playtest_exercises.gd (docs/PLAYTEST_EXERCISES.md) from Two Lakes: the Knights hold the West start with their Stage 2 and 3 buildings, track laid to a second Keep, and an enemy guard and two enemy mines to the east.\"")
	text = RegEx.create_from_string("(?m)^message = \"[^\\n]*$").sub(text,"message = \"Knights exercise: Keep, Chapterhouse, Forge, Dragon Yard and Houses at home; track runs to Keep B. Enemy guard and two hidden enemy mines to the east.\"")
	var extra := header(["keep","chapterhouse","forge","dragon_yard","house","land_mine","sentinel","round_table","questing","warhound","forester","infantry","grenadier"])
	var kinds := {}
	for entry in plan: kinds[entry.kind] = true
	for kind in kinds: extra += "[ext_resource type=\"PackedScene\" path=\"%s\" id=\"x_track_%s\"]\n" % [PIECES[kind],kind]
	var last_resource := text.rfind("[ext_resource")
	var after := text.find("\n",last_resource)+1
	text = text.substr(0,after)+extra+text.substr(after)
	var nodes := "[node name=\"Keep\" parent=\"Entities/Buildings\" instance=ExtResource(\"x_keep\")]\nposition = %s\n" % var_to_str(home)+props(KEEP_STOCK)
	nodes += "[node name=\"KeepB\" parent=\"Entities/Buildings\" instance=ExtResource(\"x_keep\")]\nposition = %s\n" % var_to_str(keep_b_at)+props(KEEP_B_STOCK)
	nodes += building("Chapterhouse","chapterhouse",sites.chapterhouse,"../Keep")
	nodes += building("Forge","forge",sites.forge,"../Keep")
	nodes += building("DragonYard","dragon_yard",sites.dragon_yard,"../Keep")
	for i in range(houses.size()): nodes += "[node name=\"House%d\" parent=\"Entities/Buildings\" instance=ExtResource(\"x_house\")]\nposition = %s\n" % [i+1,var_to_str(houses[i])]
	nodes += "[node name=\"Rails\" type=\"Node3D\" parent=\"Entities\"]\n"
	for i in range(plan.size()):
		nodes += "[node name=\"Track%d\" parent=\"Entities/Rails\" instance=ExtResource(\"x_track_%s\")]\ntransform = %s\nassigned_depot_path = NodePath(\"../../Buildings/Keep\")\n" % [i,plan[i].kind,var_to_str(plan[i].transform)]
	nodes += units(KNIGHT_UNITS,spots,"player","")
	nodes += guard
	var at := text.find("[node name=\"RailPreview\"")
	if at < 0: fail("No RailPreview node in Two Lakes"); return false
	text = text.substr(0,at)+nodes+text.substr(at)
	save(KNIGHTS_OUT,text)
	print("Knights exercise: Keep B %s, Chapterhouse %s, Forge %s, Dragon Yard %s, Houses %s, %d track pieces" % [keep_b_at,sites.chapterhouse,sites.forge,sites.dragon_yard,houses,plan.size()])
	return true

# --- Helpers -------------------------------------------------------------------------------------------------------

func save(path: String, text: String) -> void:
	var file := FileAccess.open(path,FileAccess.WRITE)
	file.store_string(text)
	file.close()
func count(groups: Array) -> int:
	var n := 0
	for entry in groups: n += entry[1]
	return n
func props(values: Dictionary) -> String:
	var text := ""
	for key in values: text += "%s = %d\n" % [key,values[key]]
	return text
func building(node_name: String, id: String, at: Vector3, payer: String) -> String:
	return "[node name=\"%s\" parent=\"Entities/Buildings\" instance=ExtResource(\"x_%s\")]\nposition = %s\nassigned_depot_path = NodePath(\"%s\")\n" % [node_name,id,var_to_str(at),payer]
func units(groups: Array, spots: Array[Vector3], team: String, prefix: String) -> String:
	var text := ""
	var i := 0
	for entry in groups:
		for n in range(entry[1]):
			var node_name: String = prefix+str(entry[0]).to_pascal_case()+str(n+1)
			text += "[node name=\"%s\" parent=\"Entities/Units\" instance=ExtResource(\"x_%s\")]\nposition = %s\n" % [node_name,entry[0],var_to_str(spots[i])]
			if team != "player": text += "team = \"%s\"\n" % team
			i += 1
	return text
func reserve(centre: Vector3, size: float) -> void:
	taken.append(Rect2(centre.x-size*0.5-1.0,centre.z-size*0.5-1.0,size+2.0,size+2.0))
func clear_of_taken(centre: Vector3, size: Vector2i) -> bool:
	var rect := Rect2(centre.x-size.x*0.5,centre.z-size.y*0.5,size.x,size.y)
	return not taken.any(func(other): return other.intersects(rect))
func centre_of(point: Vector3, size: Vector2i) -> Vector3:
	var start: Vector2i = network.footprint_start(point,size)
	return game.ground.tile_to_world(start)+Vector3(size.x*0.5-0.5,0,size.y*0.5-0.5)
## The free site of `size` in `payer`'s range nearest it, at least `least` m off, 14 m from every mine, clear of the
## truck strip and of the sites already chosen.
func site(payer: Node3D, size: Vector2i, least: float):
	var mines: Array = game.get_tree().get_nodes_in_group("mines")
	var best = null
	var best_distance := INF
	for dz in range(-30,31):
		for dx in range(-30,31):
			var distance := Vector2(dx,dz).length()
			if distance < least or distance >= best_distance: continue
			var point: Vector3 = payer.global_position+Vector3(dx,0,dz)
			if not network.can_place_size(point,payer,size): continue
			var start: Vector2i = network.footprint_start(point,size)
			if network.on_strip(start,size): continue
			var centre := centre_of(point,size)
			if not clear_of_taken(centre,size): continue
			if mines.any(func(node): return node.global_position.distance_to(centre) < 14.0): continue
			best = centre
			best_distance = distance
	if best != null: reserve(best,maxf(size.x,size.y))
	return best
func snapped_keep(point: Vector3) -> Vector3:
	var at: Vector2 = network.depot_centre(point)
	return Vector3(at.x,0,at.y)
## A Keep site between `least` and `most` m from `from`, the Depot spacing from every point in `others`, on the West
## half, 16 m from every mine and 60 m from `avoid`; the one nearest `least`.
func keep_site(others: Array, from: Vector3, least: float, most: float, avoid: Vector3):
	var spacing: float = network.depot_rules().min_depot_spacing()+1.0
	var size: Vector2i = network.depot_size()
	var mines: Array = game.get_tree().get_nodes_in_group("mines")
	var best = null
	var best_score := INF
	for dz in range(-int(most),int(most)+1,2):
		for dx in range(-int(most),int(most)+1,2):
			var distance := Vector2(dx,dz).length()
			if distance < least or distance > most: continue
			var point: Vector3 = snapped_keep(from+Vector3(dx,0,dz))
			if point.x > -40.0 or point.distance_to(avoid) < 60.0: continue
			if not network.can_place_size(point,null,size,true): continue
			if others.any(func(other): return Vector2(other.x-point.x,other.z-point.z).length() < spacing): continue
			if not clear_of_taken(point,size): continue
			if mines.any(func(node): return node.global_position.distance_to(point) < 16.0): continue
			var score := absf(distance-least)
			if score < best_score: best = point; best_score = score
	if best != null: reserve(best,size.x)
	return best
## Open, buildable ground nearest `point`, at least 50 m from `away`.
func open_point(point: Vector3, away: Vector3):
	for radius in range(0,40,2):
		for step in range(16):
			var angle := TAU*step/16.0
			var at := point+Vector3(cos(angle),0,sin(angle))*radius
			if at.distance_to(away) < 50.0: continue
			var start: Vector2i = network.footprint_start(at+Vector3(-6,0,0),Vector2i(20,12))
			if game.ground.is_footprint_valid(start,Vector2i(20,12)) and clear_of_taken(at,Vector2i(8,8)): return at
	return null
## Up to `n` walkable cells in rows round `centre`, `gap` m apart, clear of the chosen sites.
func unit_spots(centre: Vector3, n: int, gap: float) -> Array[Vector3]:
	var spots: Array[Vector3] = []
	var per_row := 6
	for ring in range(0,24):
		for i in range(per_row):
			if spots.size() >= n: return spots
			var row := (ring+1)/2*(1 if ring%2 == 0 else -1)
			var at := centre+Vector3((i-per_row*0.5+0.5)*gap,0,row*gap)
			var cell = game.ground.get_tile_at_position(at)
			if cell == null or not game.ground.is_footprint_valid(cell,Vector2i(1,1),true) or not clear_of_taken(at,Vector2i(1,1)): continue
			spots.append(Vector3(snappedf(at.x,0.5),0,snappedf(at.z,0.5)))
	return spots
