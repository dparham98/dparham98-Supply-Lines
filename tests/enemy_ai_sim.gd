extends SceneTree
# Headless, on Two Lakes, in game time: the enemy player (docs/ENEMY_AI.md) plays the East start with nobody
# opposing it. It builds its Generator and Barracks, makes workers and an army, puts up a Tank Factory, and sends its
# first wave after first_wave_seconds with at least first_wave_size units. The player's own units are held still.
# Prints a line a minute. SUPPLY_LINES_AI_MINUTES sets how long it runs (default 10); SUPPLY_LINES_AI_DEBUG=1 also
# prints each unit and the site being built.
# Not part of the headless suite, which runs in real time. Run it with --fixed-fps 30, so ten game minutes take about
# two minutes:
#   godot --headless --fixed-fps 30 --path . --script res://tests/enemy_ai_sim.gd
var game: Node3D
var ai: Node
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> bool:
	if value: return true
	push_error(message); quit(1); return false
func count(group: String, test: Callable) -> int:
	return get_nodes_in_group(group).filter(test).size()
func built(title: String) -> int:
	return count("selectable_buildings",func(node): return node.get("team") == "enemy" and _title(node) == title)
func _title(node: Node) -> String:
	if node.is_in_group("production_buildings"): return node.stats.display_name
	if node.is_in_group("depots"): return "Depot"
	if node.is_in_group("generators") or node.get("fuel_rules") != null: return "Generator"
	return node.name
func run() -> void:
	game = load("res://scenes/maps/lakes_skirmish.tscn").instantiate()
	root.add_child(game)
	for frame in range(3): await process_frame
	ai = game.enemy_player()
	if not check(ai != null,"Two Lakes should have its enemy player in the saved scene"): return
	var depot: Node3D = ai.home()
	if not check(depot != null and depot.global_position.distance_to(game.get_node("Sites/EnemyStart").global_position) < 1.0,"The enemy should start with a Depot on the East start"): return
	if not check(depot.energy == game.depot.energy and depot.iron == game.depot.iron and depot.wood == game.depot.wood and depot.coal == game.depot.coal,"The enemy's Depot should hold what the player's does"): return
	var units: Array = ai.own_units()
	if not check(units.size() == 2,"The enemy should start with an Infantry and a Cargo truck: %d units" % units.size()): return
	for unit in get_nodes_in_group("units"):
		if unit.team == "player": unit.set_process(false)
	var minutes := int(OS.get_environment("SUPPLY_LINES_AI_MINUTES")) if OS.has_environment("SUPPLY_LINES_AI_MINUTES") else 10
	var started := Time.get_ticks_msec()
	var wave_at := -1.0
	var wave_size := 0
	for minute in range(1,minutes+1):
		for frame in range(30*60): await process_frame
		depot = ai.home()
		if depot == null: break
		var plan_kind: String = str(ai.plan.kind) if is_instance_valid(ai.plan) else "-"
		print("AI %2d min · step %d (%s) · Gen %d Bar %d Fac %d mines %d · workers %d army %d wave %d scout %s · %d E %d I %d W %d C" % [minute,ai.build_step,plan_kind,built("Generator"),built("Barracks"),built("Tank Factory"),count("mines",func(m): return m.on_coal),ai.workers.size(),ai.army.size(),ai.wave.size(),"yes" if ai.scout != null else "no",depot.energy,depot.iron,depot.wood,depot.coal])
		if OS.has_environment("SUPPLY_LINES_AI_DEBUG"):
			if is_instance_valid(ai.plan): print("   plan %s at %s · %s · iron short %d" % [ai.plan.kind,ai.plan.global_position,ai.plan.state,ai.plan.shortfall(&"iron")])
			for unit in ai.own_units(): print("   %s %s · %s · %s · cargo %d %s" % [unit.name,unit.global_position,unit.order,unit.state,unit.get("cargo") if unit.get("cargo") != null else 0,unit.get("cargo_kind")])
		if ai.waves_sent > 0 and wave_at < 0: wave_at = ai.elapsed; wave_size = ai.last_wave
	print("AI ran %d game minutes in %.1f s" % [minutes,(Time.get_ticks_msec()-started)/1000.0])
	if not check(ai.home() != null,"The enemy should keep its Depot"): return
	if not check(built("Generator") >= 1 and built("Barracks") >= 1,"By then the enemy should have a Generator and a Barracks"): return
	if not check(ai.workers.size() >= 2,"The enemy should have made workers"): return
	if minutes >= 10:
		if not check(wave_at >= ai.first_wave_seconds and wave_size >= ai.first_wave_size,"The first wave should go after %d s with %d units: at %.0f s with %d" % [ai.first_wave_seconds,ai.first_wave_size,wave_at,wave_size]): return
	print("ENEMY_AI_SIM_PASSED")
	quit()
