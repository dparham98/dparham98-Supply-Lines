extends SceneTree
# Headless (item 8 of docs/BALANCE_IMPLEMENTATION_HANDOFF.md, docs/ARMOUR_CLASS.md): every unit is light or armoured
# and buildings are their own class; heavy damage applies to armoured units and buildings by the flag, not by the
# Tank's id. The Ubermech's laser (40 every 1.5 s at 16 m, 8 against armour) fires at light units, flyers and armour;
# its missile pods (60 every 3 s at 6 to 34 m) only at armour and buildings, and it closes only to the range of the
# weapon that suits the target.
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
	return unit
func at(unit: Node3D, point: Vector3) -> void:
	unit.global_position = point
func run() -> void:
	var mech_stats: UnitStats = load("res://assets/units/ubermech.tres")
	if not check(mech_stats.validation_errors().is_empty() and mech_stats.max_health == 360 and mech_stats.movement_speed == 4.0 and mech_stats.vision == 30.0 and mech_stats.armoured,"The Ubermech has 360 health, speed 4, sight 30 and is armoured"): return
	if not check(mech_stats.energy_cost == 250 and mech_stats.iron_cost == 60,"The Ubermech still costs 250 E / 60 I"): return
	game = load("res://scenes/maps/resource_skirmish.tscn").instantiate()
	root.add_child(game)
	for i in range(3): await process_frame
	game.set_process(false)
	for group in ["units","depots","mines"]:
		for node in get_nodes_in_group(group): node.set_process(false)
	var base: Vector3 = game.depot.global_position+Vector3(0,0,60)
	var mech := spawn("ubermech","player",base)
	var tank := spawn("tank","enemy",base+Vector3(20,0,0))
	var dragon := spawn("azure_dragon","enemy",base+Vector3(0,0,30))
	var truck := spawn("cargo_vehicle","enemy",base+Vector3(0,0,-30))
	var infantry := spawn("infantry","enemy",base+Vector3(12,0,0))
	var drone := spawn("drone","enemy",base+Vector3(-12,0,0))
	await process_frame
	# Classes.
	var C := CombatResolver
	if not check(C.target_class(mech) == C.ARMOURED and C.target_class(tank) == C.ARMOURED and C.target_class(dragon) == C.ARMOURED and C.target_class(truck) == C.ARMOURED,"The Ubermech, Tank, Azure Dragon and trucks are armoured"): return
	if not check(C.target_class(infantry) == C.LIGHT and C.target_class(drone) == C.FLYER and C.target_class(game.depot) == C.BUILDING,"Infantry is light, the Drone a flyer, the Depot a building"): return
	var train_scene: PackedScene = load("res://scenes/gameplay/train.tscn")
	var train = train_scene.instantiate()
	if not check(train.armoured,"Trains are armoured"): return
	train.free()
	# Heavy damage by the flag: a Grenadier's 40 now lands on the Ubermech and the Dragon, as on the Tank.
	var grenadier := spawn("grenadier","enemy",base+Vector3(0,0,10))
	if not check(C.damage_for(grenadier,mech) == 40 and C.damage_for(grenadier,dragon) == 40 and C.damage_for(grenadier,infantry) == 20,"Heavy damage should follow the armour flag"): return
	# Weapons by class and range.
	if not check(mech.weapon_for(infantry) == 0 and C.damage_for(mech,infantry,0) == 40 and is_equal_approx(C.interval_for(mech,infantry,0),1.5),"The laser: 40 every 1.5 s at a light unit within 16 m"): return
	if not check(mech.weapon_for(drone) == 0 and C.damage_for(mech,drone,0) == 40,"The laser fires at flyers too"): return
	if not check(mech.weapon_for(tank) == 1 and C.damage_for(mech,tank,1) == 60 and is_equal_approx(C.interval_for(mech,tank,1),3.0),"The pods: 60 every 3 s at an armoured unit 20 m off"): return
	at(infantry,base+Vector3(20,0,0))
	if not check(mech.weapon_for(infantry) == -1 and not mech.in_attack_range(infantry),"Pods don't fire at light units: a light unit 20 m off is out of range"): return
	at(tank,base+Vector3(4,0,0))
	if not check(mech.weapon_for(tank) == 0 and C.damage_for(mech,tank,0) == 8,"Inside the pods' 6 m minimum the laser does 8 to armour"): return
	at(tank,base+Vector3(33,0,0))
	if not check(mech.weapon_for(tank) == 1,"The pods reach 34 m"): return
	at(tank,base+Vector3(36,0,0))
	if not check(mech.weapon_for(tank) == -1,"Nothing reaches past 34 m"): return
	# Buildings: pods only, from 6 to 34 m.
	if not check(mech.fires_at(game.depot) and not (mech_stats.targets & C.BUILDING),"The laser doesn't fire at buildings; the pods do"): return
	# Attack-move closes only to the range of the suited weapon: an armoured target at 30 m is in range, a light one not.
	at(tank,base+Vector3(30,0,0))
	at(infantry,base+Vector3(-30,0,0))
	if not check(mech.in_attack_range(tank) and not mech.in_attack_range(infantry),"At 30 m the pods are in range of the Tank, the laser not of the Infantry"): return
	# Other units keep firing at everything with one weapon.
	var deforester := spawn("infantry","player",base+Vector3(0,0,-12))
	at(infantry,base+Vector3(0,0,-20))
	if not check(deforester.weapon_for(infantry) == 0 and deforester.fires_at(game.depot) and deforester.fires_at(tank),"An ordinary unit's one weapon fires at every class"): return
	# A real shot from the laser lands 40 on a light unit.
	at(infantry,base+Vector3(10,0,0))
	at(tank,base+Vector3(200,0,0))
	at(drone,base+Vector3(200,0,20))
	at(dragon,base+Vector3(200,0,40))
	at(truck,base+Vector3(200,0,60))
	at(grenadier,base+Vector3(200,0,80))
	var before: int = infantry.health
	mech._cooldown = 0.0
	mech.command_attack(infantry)
	for i in range(240):
		mech._process(1.0/60)
		if infantry.health < before: break
	if not check(before-infantry.health == 40 or infantry.health <= 0,"The laser should take 40 off the Infantry, took %d" % (before-infantry.health)): return
	print("ARMOUR_CLASS_TEST_PASSED")
	quit(0)
