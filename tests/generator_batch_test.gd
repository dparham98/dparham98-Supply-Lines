extends SceneTree
var game: Node3D
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> bool:
	if value: return true
	push_error(message); quit(1); return false
func clear(stock: ResourceStockpile) -> void:
	for kind in ResourceStockpile.KINDS: stock.withdraw(kind,stock.amount(kind))
func run() -> void:
	game = load("res://scenes/maps/generator_exercise.tscn").instantiate()
	root.add_child(game); await process_frame
	game.set_process(false)
	for group in ["units","depots","energy_generators"]:
		for node in get_nodes_in_group(group): node.set_process(false)
	var generator = game.get_node("Entities/Buildings/Generator")
	var depot = game.depot
	var other = game.get_node("Entities/Buildings/EastDepot")
	clear(depot.stockpile); clear(other.stockpile)
	generator.reset_cycle(); other.wood = 100; other.coal = 100
	generator._process(100)
	if not check(depot.energy == 0 and not generator.active() and generator.cycle_elapsed == 0,"Empty generator produced free energy or borrowed fuel"): return
	depot.wood = 3; depot.coal = 2
	generator._process(1)
	if not check(depot.energy == 0 and depot.wood == 3 and generator.cycle_elapsed == 1 and depot.generation_rate() == 5,"Wood cycle burned early or rate wrong"): return
	generator._process(1)
	if not check(depot.energy == 10 and depot.wood == 2 and depot.coal == 2,"Wood conversion wrong"): return
	generator.set_fuel_preference("coal"); generator._process(4)
	if not check(depot.energy == 10 and depot.coal == 2 and depot.generation_rate() == 10,"Coal cycle burned early/rate wrong"): return
	generator._process(1)
	if not check(depot.energy == 60 and depot.coal == 1 and depot.wood == 2,"Coal conversion wrong"): return
	# Preference changes apply after the latched cycle, not to its elapsed timer.
	generator.set_fuel_preference("wood"); generator._process(1)
	generator.set_fuel_preference("coal"); generator._process(1)
	if not check(depot.energy == 70 and depot.wood == 1 and depot.coal == 1,"Mode switch changed an in-flight cycle"): return
	generator._process(5)
	if not check(depot.energy == 120 and depot.coal == 0,"Coal mode did not begin next cycle"): return
	generator._process(100)
	if not check(depot.energy == 120 and depot.wood == 1,"Coal-only mode burned wood fallback"): return
	generator.set_fuel_preference("either"); generator._process(2)
	if not check(depot.energy == 130 and depot.wood == 0,"Either did not prefer available wood"): return
	depot.coal = 1; generator._process(5)
	if not check(depot.energy == 180 and depot.coal == 0,"Either failed coal fallback"): return
	# Capacity changes during work pause progress and leave fuel untouched.
	clear(depot.stockpile); depot.wood = 2; generator.set_fuel_preference("wood")
	generator._process(1); depot.energy = depot.storage_capacity-depot.wood
	generator._process(100)
	if not check(generator.cycle_elapsed == 1 and depot.wood == 2 and depot.stockpile.space() == 0,"Full storage burned fuel or banked blocked time"): return
	depot.stockpile.withdraw(&"energy",10); generator._process(0.5)
	if not check(depot.wood == 2 and generator.cycle_elapsed == 1.5,"Blocked time leaked after freeing storage"): return
	generator._process(0.5)
	if not check(depot.wood == 1 and depot.stockpile.space() == 1,"Full-cycle completion lost/overflowed output"): return
	generator._process(100)
	if not check(depot.wood == 1 and generator.cycle_elapsed == 0,"Generator consumed fuel for partial output space"): return
	# Shared fuel can be removed by another actor; the cycle waits without creating stock.
	clear(depot.stockpile); depot.wood = 1; generator._process(1)
	depot.stockpile.withdraw(&"wood",1); generator._process(100)
	if not check(depot.energy == 0 and generator.cycle_elapsed == 1,"Missing fuel created energy or banked time"): return
	depot.wood = 1; generator._process(1)
	if not check(depot.energy == 10 and depot.wood == 0,"Restored fuel failed safe completion"): return
	depot.wood = 2; generator._process(1); generator.enabled = false; generator._process(100)
	if not check(generator.cycle_elapsed == 1 and depot.wood == 2 and depot.generation_rate() == 0,"Player pause advanced or consumed fuel"): return
	generator.enabled = true; generator._process(1)
	if not check(depot.energy == 20 and depot.wood == 1,"Resume lost pending cycle"): return
	# Capture resets only elapsed work, preserving the unconsumed stock.
	generator._process(1); depot.team = "enemy"; depot.ownership_changed.emit(); generator._process(100)
	if not check(depot.energy == 20 and depot.wood == 1 and generator.cycle_kind.is_empty(),"Captured Depot received old-team generation"): return
	depot.team = "player"; depot.ownership_changed.emit(); generator._process(1)
	if not check(depot.energy == 20 and generator.cycle_elapsed == 1,"Capture retained old-team elapsed cycle"): return
	# Explicit reassignment cannot move a half-finished cycle to a different wallet.
	if not check(generator.assign_source(other) and generator.cycle_elapsed == 0,"Reassignment retained cycle progress"): return
	var before: int = other.energy
	generator._process(2)
	if not check(other.energy == before+10 and other.wood == 99 and depot.energy == 20 and depot.wood == 1,"Reassignment moved or pooled inventory"): return
	if not check(not generator.assign_source(game.get_node("Entities/Units/Train")),"Generator accepted a mobile operating wallet"): return
	# Two generators racing for one wood cannot duplicate output.
	clear(depot.stockpile); depot.wood = 1; generator.assign_source(depot)
	var second = load("res://scenes/gameplay/energy_generator.tscn").instantiate()
	second.position = Vector3(180,0,170); second.assigned_depot = depot
	game.get_node("Entities/Buildings").add_child(second); second.set_process(false)
	generator._process(1); second._process(1); generator._process(1); second._process(1)
	if not check(depot.energy == 10 and depot.wood == 0,"Concurrent generators duplicated fuel/output"): return
	depot.wood = 1; second._process(0); second.take_damage(second.health)
	if not check(depot.wood == 1 and depot.energy == 10,"Destroyed generator lost pending fuel or emitted energy"): return
	# Large simulation steps run only available cycles, never free output.
	generator.reset_cycle(); depot.wood = 3; var energy: int = depot.energy
	generator._process(20)
	if not check(depot.energy == energy+30 and depot.wood == 0 and other.wood == 99,"Long tick created unbacked output"): return
	depot.take_damage(depot.health); await process_frame
	generator._process(10)
	if not check(not generator.source_valid() and not generator.active(),"Destroyed assigned Depot left generator active"): return
	game.queue_free(); await process_frame
	print("GENERATOR_BATCH_CHECKS_PASSED"); quit()
