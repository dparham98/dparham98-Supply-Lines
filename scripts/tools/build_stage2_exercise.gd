extends SceneTree
## Writes scenes/maps/stage2_exercise.tscn (docs/STAGE2_EXERCISE.md): Two Lakes with every Stage 2 and Stage 3 change
## standing ready to try, for both factions on the player's side at once.
## - Cyborgs: the West Depot well stocked, a Temple of Science (Minelaying) and a Foundry (the four upgrade lines) in
##   its range, two Derailers, a Drone, an Ubermech, Tanks, Grenadiers and line infantry.
## - Knights: two player Keeps, a Forge (Arms, Mail and Slow) and a Wainwright (track and trains) by the first, and
##   Grail Sentinels, Round Table and Questing Marines and Forester Maidens beside them.
## - A clump of enemy infantry stands guard in the open east of the base, for Slow, Mist, splash and armour.
## Everything else is Two Lakes as it is, the East Cyborg AI included. Run it headless from the project folder
## after the map or the building sizes change:
##   Godot --headless --path . --script res://scripts/tools/build_stage2_exercise.gd
const BASE := "res://scenes/maps/lakes_skirmish.tscn"
const OUTPUT := "res://scenes/maps/stage2_exercise.tscn"
const SCENES := {
	"keep": "res://scenes/gameplay/keep.tscn",
	"temple": "res://scenes/gameplay/temple_of_science.tscn",
	"foundry": "res://scenes/gameplay/foundry.tscn",
	"forge": "res://scenes/gameplay/forge.tscn",
	"wainwright": "res://scenes/gameplay/wainwright.tscn",
	"infantry": "res://scenes/gameplay/infantry.tscn",
	"grenadier": "res://scenes/gameplay/grenadier.tscn",
	"tank": "res://scenes/gameplay/tank.tscn",
	"motorcycle": "res://scenes/gameplay/motorcycle.tscn",
	"drone": "res://scenes/gameplay/drone.tscn",
	"ubermech": "res://scenes/gameplay/ubermech.tscn",
	"sentinel": "res://scenes/gameplay/grail_sentinel.tscn",
	"round_table": "res://scenes/gameplay/round_table_marine.tscn",
	"questing": "res://scenes/gameplay/questing_marine.tscn",
	"forester": "res://scenes/gameplay/forester_maiden.tscn",
}
## Stock, with the storage raised to hold it: enough for every research line's first levels and a few trains and mines on each side.
const DEPOT_STOCK := {"storage_capacity_override": 6000, "initial_energy": 2000, "initial_iron": 1200, "initial_wood": 300, "initial_coal": 300}
const KEEP_STOCK := {"storage_capacity_override": 6000, "initial_food": 1500, "initial_iron": 1200, "initial_wood": 600, "initial_coal": 300}
const KEEP_B_STOCK := {"storage_capacity_override": 2000, "initial_food": 300, "initial_iron": 400, "initial_wood": 100, "initial_coal": 0}
var game: Node3D
var network: Node
var taken: Array[Rect2] = []
func _initialize() -> void: call_deferred("run")
func fail(message: String) -> void:
	push_error(message)
	quit(1)
func run() -> void:
	game = load(BASE).instantiate()
	root.add_child(game)
	for frame in range(3): await process_frame
	var ai = game.get_node_or_null("EnemyPlayer")
	if ai != null: ai.set_process(false)
	network = game.get_node("DepotNetwork")
	var depot: Node3D = game.get_node("Entities/Buildings/Depot")
	for node in game.get_tree().get_nodes_in_group("selectable_buildings"): reserve(node.global_position,10.0)
	# The Cyborg buildings in the Depot's range, on the side away from the starter mine.
	var temple = site(depot,Vector2i(6,6),9.0)
	if temple == null: fail("No site for the Temple"); return
	var foundry = site(depot,Vector2i(6,6),9.0)
	if foundry == null: fail("No site for the Foundry"); return
	# The Keeps: the first 55 to 80 m from the Depot, the second 55 to 80 m on from the first, both on the map's
	# West half and keeping the Depot spacing from each other and the Depot.
	var keep_a = keep_site([depot.global_position],depot.global_position,55.0,80.0)
	if keep_a == null: fail("No site for the first Keep"); return
	var keep_b = keep_site([depot.global_position,keep_a],keep_a,55.0,90.0)
	if keep_b == null: fail("No site for the second Keep"); return
	# A stand-in Keep, so the Forge's and Wainwright's sites are checked against its range.
	var stand_in: Node3D = load(SCENES.keep).instantiate()
	stand_in.position = keep_a
	game.get_node("Entities/Buildings").add_child(stand_in)
	await process_frame
	var forge = site(stand_in,Vector2i(6,6),9.0)
	if forge == null: fail("No site for the Forge"); return
	var wainwright = site(stand_in,Vector2i(4,4),9.0)
	if wainwright == null: fail("No site for the Wainwright"); return
	# Units in blocks beside their buildings, and the enemy guard in the open between the base and the lakes.
	var cyborgs := [["motorcycle",2],["drone",1],["ubermech",1],["tank",2],["grenadier",2],["infantry",4]]
	var knights := [["sentinel",3],["round_table",4],["questing",2],["forester",2]]
	var cyborg_spots := unit_spots(depot.global_position+Vector3(0,0,22),count(cyborgs),3.0)
	var knight_spots := unit_spots(keep_a+Vector3(0,0,16),count(knights),2.5)
	var guard_at = open_point(depot.global_position+Vector3(75,0,0),depot.global_position)
	if guard_at == null: fail("No open ground for the enemy guard"); return
	var guard_spots := unit_spots(guard_at,6,1.6)
	if cyborg_spots.size() < count(cyborgs) or knight_spots.size() < count(knights) or guard_spots.size() < 6: fail("Not enough open ground for the units: %d/%d, %d/%d, %d/6" % [cyborg_spots.size(),count(cyborgs),knight_spots.size(),count(knights),guard_spots.size()]); return
	var text := "[gd_scene format=3]\n"
	text += "[ext_resource type=\"PackedScene\" path=\"%s\" id=\"base\"]\n" % BASE
	for id in SCENES: text += "[ext_resource type=\"PackedScene\" path=\"%s\" id=\"%s\"]\n" % [SCENES[id],id]
	text += "\n[node name=\"Stage2Exercise\" instance=ExtResource(\"base\")]\n"
	text += "editor_description = \"Built by scripts/tools/build_stage2_exercise.gd (docs/STAGE2_EXERCISE.md): Two Lakes with both factions' Stage 2 and 3 buildings and units on the player's side, and an enemy guard to try them on.\"\n"
	text += "message = \"Stage 2/3 exercise: Cyborgs by the Depot, Knights by the Keeps to the %s. Enemy guard to the east. See docs/STAGE2_EXERCISE.md.\"\n" % compass(keep_a-depot.global_position)
	text += "[node name=\"Depot\" parent=\"Entities/Buildings\"]\n"+props(DEPOT_STOCK)
	text += building("TempleOfScience","temple",temple,"../Depot")
	text += building("Foundry","foundry",foundry,"../Depot")
	text += "[node name=\"Keep\" parent=\"Entities/Buildings\" instance=ExtResource(\"keep\")]\nposition = %s\n" % var_to_str(snapped_keep(keep_a))+props(KEEP_STOCK)
	text += "[node name=\"KeepB\" parent=\"Entities/Buildings\" instance=ExtResource(\"keep\")]\nposition = %s\n" % var_to_str(snapped_keep(keep_b))+props(KEEP_B_STOCK)
	text += building("Forge","forge",forge,"../Keep")
	text += building("Wainwright","wainwright",wainwright,"../Keep")
	text += units(cyborgs,cyborg_spots,"player","")
	text += units(knights,knight_spots,"player","")
	text += units([["infantry",4],["grenadier",2]],guard_spots,"enemy","Guard")
	var file := FileAccess.open(OUTPUT,FileAccess.WRITE)
	file.store_string(text)
	file.close()
	print("Stage 2 exercise written: Temple %s, Foundry %s, Keep %s, Keep B %s, Forge %s, Wainwright %s, guard %s" % [temple,foundry,keep_a,keep_b,forge,wainwright,guard_at])
	print("STAGE2_EXERCISE_BUILT")
	quit()
func count(groups: Array) -> int:
	var n := 0
	for entry in groups: n += entry[1]
	return n
func props(values: Dictionary) -> String:
	var text := ""
	for key in values: text += "%s = %d\n" % [key,values[key]]
	return text
func building(node_name: String, id: String, at: Vector3, payer: String) -> String:
	return "[node name=\"%s\" parent=\"Entities/Buildings\" instance=ExtResource(\"%s\")]\nposition = %s\nassigned_depot_path = NodePath(\"%s\")\n" % [node_name,id,var_to_str(at),payer]
func units(groups: Array, spots: Array[Vector3], team: String, prefix: String) -> String:
	var text := ""
	var i := 0
	for entry in groups:
		for n in range(entry[1]):
			var node_name: String = prefix+str(entry[0]).to_pascal_case()+str(n+1)
			text += "[node name=\"%s\" parent=\"Entities/Units\" instance=ExtResource(\"%s\")]\nposition = %s\n" % [node_name,entry[0],var_to_str(spots[i])]
			if team != "player": text += "team = \"%s\"\n" % team
			i += 1
	return text
func compass(offset: Vector3) -> String:
	if absf(offset.x) > absf(offset.z): return "east" if offset.x > 0 else "west"
	return "south" if offset.z > 0 else "north"
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
## half, 16 m from every mine; the one nearest `least`.
func keep_site(others: Array, from: Vector3, least: float, most: float):
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
			if point.x > -40.0: continue
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
			var start: Vector2i = network.footprint_start(at,Vector2i(8,8))
			if game.ground.is_footprint_valid(start,Vector2i(8,8)) and clear_of_taken(at,Vector2i(8,8)): return at
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
