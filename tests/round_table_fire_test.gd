extends SceneTree

const Flash := "res://scenes/models/round_table_muzzle_fx.tscn"
const Impact := "res://scenes/gameplay/round_table_impact.tscn"
const Bullet := "res://scenes/gameplay/infantry_bullet.tscn"
var spawned := {}

func _initialize() -> void: call_deferred("run")

func collect(node: Node) -> void:
	if node.scene_file_path in [Flash, Impact, Bullet]:
		spawned[node.scene_file_path] = node

func check(ok: bool, description: String) -> bool:
	if not ok:
		push_error(description)
		quit(1)
	return ok

func run() -> void:
	var game: Node3D = load("res://scenes/maps/arthurian_skirmish.tscn").instantiate()
	root.add_child(game)
	await process_frame
	for unit in get_nodes_in_group("units"): unit.set_process(false)
	var marine = game.get_node("Entities/Units/RoundTableMarine")
	var target = game.get_node("Entities/Units/HostileInfantry1")
	var tank = game.get_node("Entities/Units/EnemyTank")
	var questing = game.get_node("Entities/Units/QuestingMarine")
	node_added.connect(collect)
	target.global_position = marine.global_position + Vector3(11, 0, 0)
	var hp: int = target.health
	marine.command_attack(target)
	marine._shoot(target)
	if not check(target.health == hp - 6 and is_equal_approx(marine._cooldown, 0.5), "Expected immediate infantry damage and one reload"): return
	if not check(spawned.has(Impact) and spawned.has(Flash) and not spawned.has(Bullet), "Expected two local effects and no flying round"): return
	var flash: Node3D = spawned[Flash]
	var impact: Node3D = spawned[Impact]
	var model = marine.get_node("Visuals/Model")
	if not check(flash.global_position.distance_to(model.muzzle_position()) < 0.02, "Flash missed the rifle on the release frame"): return
	var contact: Vector3 = impact.global_position
	if not check(contact.distance_to(target.global_position) < 3.0, "Impact missed the target"): return
	target.global_position.x += 1.0
	await process_frame
	await process_frame
	if not check(impact.global_position.distance_to(contact + Vector3.RIGHT) < 0.05, "Impact did not follow the moving target"): return
	await create_timer(0.4).timeout
	if not check(target.health == hp - 6 and not is_instance_valid(impact) and not is_instance_valid(flash), "Burst must expire after a single damage event"): return
	spawned.clear()
	tank.global_position = questing.global_position + Vector3(11, 0, 0)
	hp = tank.health
	questing.command_attack(tank)
	questing._shoot(tank)
	if not check(tank.health == hp - 38 and spawned.has(Bullet) and not spawned.has(Impact), "Questing Marine lost its ordinary shot"): return
	print("ROUND_TABLE_FIRE_TEST_PASSED")
	game.queue_free()
	await process_frame
	quit(0)
