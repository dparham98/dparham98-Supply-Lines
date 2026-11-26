extends SceneTree
# Headless (item 2 of the Round 3 handoff, docs/ROUND3_UNIT_STATS.md):
# - The 13 units' vision, range, damage and upgrade bonuses are as the table says; attack upgrades add each weapon's
#   own bonus a level.
# - In fog, a Grenadier (sight 14, range 19) holds fire at a target 17 m off until a friend spots it, and when it fires
#   the other side sees its spot for 1.2 s.
# - The Azure Dragon is a light giant: a Grenadier deals it 20 (not 40), a Tank 12 (not 50); a Grail Sentinel can heal
#   it; two breaths kill a 60 HP Grenadier.
# - The Forester Maiden is defensive: idle she picks no target, hit she fights back. One Warhound beats one Forester
#   that fights back, and loses to two.
var game: Node3D
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> bool:
	if value: return true
	push_error(message); quit(1); return false
func open(path: String) -> void:
	if is_instance_valid(game):
		game.queue_free()
		await process_frame
	game = load(path).instantiate()
	root.add_child(game)
	for frame in range(3): await process_frame
	game.set_process(false)
	game.get_node("Interface").set_process(false)
	var ai = game.get_node_or_null("EnemyPlayer")
	if ai != null: ai.set_process(false)
	for group in ["units","depots","production_buildings","farms","houses","energy_generators","mines","fog_of_war"]:
		for node in get_nodes_in_group(group): node.set_process(false)
func spawn(id: String, point: Vector3, team := "player") -> Node3D:
	var unit = load("res://scenes/gameplay/"+id+".tscn").instantiate()
	unit.team = team
	game.get_node("Entities/Units").add_child(unit)
	unit.set_process(false)
	unit._stop_route()
	for cell in unit._claimed.duplicate(): unit._release(cell)
	unit.grid_position = game.ground.nearest_actor_cell(game.ground.get_tile_at_position(point),unit.mobility_layer(),unit._owner_key())
	unit.global_position = game.ground.tile_to_world(unit.grid_position)
	unit._claim(unit.grid_position)
	return unit
func alive(node) -> bool:
	return is_instance_valid(node) and node.health > 0
func step(nodes: Array, seconds: float, until := Callable()) -> float:
	var frames := ceili(seconds*60)
	for i in range(frames):
		for node in nodes:
			if is_instance_valid(node) and node.is_inside_tree(): node._process(1.0/60)
		if until.is_valid() and until.call(): return (i+1)/60.0
	return seconds
func run() -> void:
	if not table(): return
	if not await fog_and_flash(): return
	if not await dragon(): return
	if not await foresters(): return
	print("TIERED_VISION_AND_DRAGON_TEST_PASSED")
	quit()
## unit: [vision, range, damage, interval, attack bonus, heavy damage, heavy bonus]
const TABLE := {
	"infantry": [20.0,15.0,8,1.0,1,-1,1], "scout": [42.0,10.0,8,2.0,1,-1,1], "grenadier": [14.0,19.0,20,3.0,2,40,4],
	"motorcycle": [26.0,12.0,16,2.0,2,-1,1], "drone": [32.0,-1.0,-1,-1.0,1,-1,1], "tank": [18.0,30.0,12,1.5,2,50,5],
	"ubermech": [24.0,16.0,40,1.5,4,8,1], "forester_maiden": [24.0,2.4,5,1.2,0,-1,1], "warhound": [44.0,3.2,5,1.0,1,-1,1],
	"round_table_marine": [19.0,18.0,6,0.5,1,3,1], "grail_sentinel": [22.0,10.0,5,1.0,1,-1,1],
	"questing_marine": [15.0,21.0,16,2.0,2,38,4], "azure_dragon": [28.0,9.0,32,2.4,3,45,5],
}
func table() -> bool:
	for id in TABLE:
		var want: Array = TABLE[id]
		var stats: UnitStats = load("res://assets/units/%s.tres" % id)
		var have := [stats.vision,stats.attack_range,stats.damage,stats.attack_interval,stats.attack_upgrade_bonus,stats.heavy_target_damage,stats.heavy_upgrade_bonus]
		for i in range(want.size()):
			if not check(is_equal_approx(float(have[i]),float(want[i])),"%s: field %d should be %s, not %s" % [id,i,want[i],have[i]]): return false
	var uber: UnitStats = load("res://assets/units/ubermech.tres")
	if not check(uber.second_damage == 60 and uber.second_upgrade_bonus == 6 and uber.max_health == 360,"Ubermech pods 60 (+6), 360 HP"): return false
	var drone: UnitStats = load("res://assets/units/drone.tres")
	if not check(drone.max_health == 40 and drone.detect_range == 20.0,"Drone 40 HP, detects at 20 m"): return false
	var hound: UnitStats = load("res://assets/units/warhound.tres")
	if not check(hound.detect_range == 15.0 and hound.fire_while_moving,"Warhound detects at 15 m and bites on the move"): return false
	var dragon: UnitStats = load("res://assets/units/azure_dragon.tres")
	if not check(dragon.max_health == 240 and dragon.giant and not dragon.armoured and dragon.heavy_target_interval == 2.4,"Dragon: 240 HP, a giant, not armoured"): return false
	if not check(load("res://assets/units/forester_maiden.tres").defensive_only,"The Forester Maiden is defensive only"): return false
	return true
## A spot on the map at least `clear` m from every building and unit, with open ground 30 m east of it.
func quiet_spot(clear: float) -> Variant:
	var things: Array = get_nodes_in_group("selectable_buildings")+get_nodes_in_group("units")
	for z in range(-200,201,10):
		for x in range(-200,201,10):
			var at := Vector3(x,0,z)
			if things.any(func(node): return node.global_position.distance_to(at) < clear): continue
			var ok := true
			for dx in [0,10,17,20,30]:
				var cell = game.ground.get_tile_at_position(at+Vector3(dx,0,0))
				if cell == null or not game.ground.is_footprint_valid(cell,Vector2i(2,2)): ok = false; break
			if ok: return at
	return null
func fog_and_flash() -> bool:
	await open("res://scenes/maps/lakes_skirmish.tscn")
	var fog = get_first_node_in_group("fog_of_war")
	if not check(fog != null and is_equal_approx(fog.muzzle_reveal_seconds,1.2) and is_equal_approx(fog.muzzle_reveal_radius,3.0),"Two Lakes' fog should reveal a shot for 1.2 s within 3 m"): return false
	var at = quiet_spot(70.0)
	if not check(at != null,"No quiet open ground on Two Lakes"): return false
	# A player Grenadier (sight 14) and an enemy one 17 m east of it: neither sees the other.
	var target = spawn("grenadier",at)
	var shooter = spawn("grenadier",at+Vector3(17,0,0),"enemy")
	fog.update_now()
	if not check(not fog.visible_to("enemy",target.global_position) and not fog.visible_to("player",shooter.global_position),"At 17 m two Grenadiers shouldn't see each other"): return false
	var health: int = target.health
	step([shooter],4.0)
	if not check(target.health == health and shooter._cooldown <= 0.0,"Unspotted, the enemy Grenadier should hold its fire: %d HP, '%s'" % [target.health,shooter.state]): return false
	# An enemy Scout 13 m behind it (out of the player Grenadier's sight) spots the target.
	var spotter = spawn("scout",at+Vector3(30,0,0),"enemy")
	spotter._attack_enabled = false
	fog.update_now()
	if not check(fog.visible_to("enemy",target.global_position) and not fog.visible_to("player",spotter.global_position),"The Scout should spot the target, unseen itself"): return false
	var fired := func(): return shooter._cooldown > 0.0
	step([shooter],4.0,fired)
	if not check(fired.call(),"Spotted, the enemy Grenadier should fire: '%s'" % shooter.state): return false
	if not check(fog.visible_to("player",shooter.global_position),"Its shot should show the Grenadier to the player"): return false
	fog.advance(1.0)
	fog.update_now()
	if not check(fog.visible_to("player",shooter.global_position),"The flash should still show it after 1 s"): return false
	fog.advance(0.3)
	fog.update_now()
	if not check(not fog.visible_to("player",shooter.global_position),"The flash should be gone after 1.3 s"): return false
	return true
func dragon() -> bool:
	await open("res://scenes/maps/resource_skirmish.tscn")
	var near: Vector3 = game.depot.global_position+Vector3(-20,0,0)
	var dragon = spawn("azure_dragon",near,"enemy")
	var grenadier = spawn("grenadier",near+Vector3(-8,0,0))
	var tank = spawn("tank",near+Vector3(0,0,8))
	if not check(CombatResolver.target_class(dragon) == CombatResolver.LIGHT and not CombatResolver.is_heavy(dragon),"The Dragon is a light target"): return false
	if not check(CombatResolver.splash_damage(grenadier,dragon,dragon) == 20,"A Grenadier should deal the Dragon 20, not %d" % CombatResolver.splash_damage(grenadier,dragon,dragon)): return false
	if not check(CombatResolver.splash_damage(tank,dragon,dragon) == 12,"A Tank should deal the Dragon 12, not %d" % CombatResolver.splash_damage(tank,dragon,dragon)): return false
	dragon.health -= 50
	if not check(MedicalWork.can_heal(dragon,"enemy"),"A Grail Sentinel can heal a hurt Dragon"): return false
	var breath: int = CombatResolver.splash_damage(dragon,grenadier,grenadier)
	if not check(breath == 32 and breath < grenadier.max_health and breath*2 >= grenadier.max_health,"Two breaths (%d) should kill a %d HP Grenadier, one not" % [breath,grenadier.max_health]): return false
	# Upgrades add each weapon's own bonus: the Grenadier's 20 (+2) and 40 (+4), the Tank's 12 (+2) and 50 (+5).
	Research.complete(game,"player",&"infantry_weapons_1")
	Research.complete(game,"player",&"vehicle_weapons_1")
	var building: Node3D = game.depot
	var foe = spawn("infantry",near+Vector3(-4,0,4),"enemy")
	if not check(CombatResolver.splash_damage(grenadier,foe,foe) == 22,"Infantry Weapons I: a Grenadier's 20 -> 22"): return false
	if not check(CombatResolver.upgrade_bonus(grenadier,building) == 4 and CombatResolver.upgrade_bonus(tank,building) == 5 and CombatResolver.splash_damage(tank,foe,foe) == 14,"Heavy bonuses 4 and 5; a Tank's 12 -> 14"): return false
	return true
func foresters() -> bool:
	await open("res://scenes/maps/resource_skirmish.tscn")
	var near: Vector3 = game.depot.global_position+Vector3(-20,0,0)
	# Idle, a Forester picks no target, even an enemy next to her.
	var maiden = spawn("forester_maiden",near,"enemy")
	var deforester = spawn("infantry",near+Vector3(-2,0,0))
	deforester._attack_enabled = false
	var health: int = deforester.health
	step([maiden],3.0)
	if not check(deforester.health == health and maiden.order == "idle","An idle Forester shouldn't attack by herself: '%s'" % maiden.state): return false
	deforester.queue_free()
	await process_frame
	# One Warhound against one Forester who fights back: the Warhound wins.
	var hound = spawn("warhound",near+Vector3(-6,0,0))
	hound.command_attack(maiden)
	var over := func(): return not alive(maiden) or not alive(hound)
	step([hound,maiden],30.0,over)
	if not check(alive(hound) and not alive(maiden),"One Warhound should beat one Forester: hound %s, Forester %s" % [hound.health if is_instance_valid(hound) else "gone",maiden.health if is_instance_valid(maiden) else "gone"]): return false
	print("Warhound beat one Forester with %d of %d HP left" % [hound.health,hound.max_health])
	if not check(hound.health < hound.max_health,"The Forester should have fought back"): return false
	hound.queue_free()
	await process_frame
	# Against two (the second ordered in), it loses.
	var a = spawn("forester_maiden",near,"enemy")
	var b = spawn("forester_maiden",near+Vector3(0,0,3),"enemy")
	var dog = spawn("warhound",near+Vector3(-6,0,0))
	dog.command_attack(a)
	b.command_attack(dog)
	var done := func(): return not alive(dog) or (not alive(a) and not alive(b))
	step([dog,a,b],30.0,done)
	if not check(not alive(dog) and (alive(a) or alive(b)),"One Warhound should lose to two Foresters"): return false
	return true
