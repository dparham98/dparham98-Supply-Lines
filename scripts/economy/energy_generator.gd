extends Node3D
@export var rules: SupplyRules
@export var assigned_depot_path: NodePath
@export var team := "player"
@export var max_health := 300 # Provisional; no new enemy targeting.
@export var initial_health := -1
var health := 300
var assigned_depot: Node3D
var cells: Array[Vector2i] = []
@export var fuel_rules: GeneratorRules
@export_enum("wood","coal","either") var fuel_preference := "wood"
@export var enabled := true
var cycle_kind: StringName = &""
var cycle_elapsed := 0.0
var cycle_output := 0
var cycle_seconds := 0.0
var state := "Waiting for fuel"
func reset_cycle() -> void:
	cycle_kind = &""; cycle_elapsed = 0; cycle_output = 0; cycle_seconds = 0
func _source_changed() -> void:
	reset_cycle() # No fuel was withdrawn, so capture cannot lose reserved material.
func _disconnect_source() -> void:
	if is_instance_valid(assigned_depot) and assigned_depot.ownership_changed.is_connected(_source_changed): assigned_depot.ownership_changed.disconnect(_source_changed)
func choose_fuel() -> StringName:
	if not source_valid(): return &""
	if fuel_preference == "either":
		return &"wood" if assigned_depot.wood > 0 else (&"coal" if assigned_depot.coal > 0 else &"")
	var kind := StringName(fuel_preference)
	return kind if kind in [&"wood",&"coal"] and assigned_depot.stockpile.amount(kind) > 0 else &""
func set_fuel_preference(value: String) -> void:
	if value in ["wood","coal","either"]: fuel_preference = value
func output_rate() -> float:
	if not active(): return 0.0
	var kind := cycle_kind if not cycle_kind.is_empty() else choose_fuel()
	return float(cycle_output)/cycle_seconds if not cycle_kind.is_empty() else float(fuel_rules.output(kind))/fuel_rules.seconds(kind)
func cycle_ready() -> bool:
	return source_valid() and assigned_depot.stockpile.amount(cycle_kind) >= 1 and assigned_depot.stockpile.space() >= cycle_output
func describe_state() -> String:
	if health <= 0: return "Destroyed"
	if not source_valid(): return "Paused · assigned Depot unavailable"
	if not enabled: return "Paused by player"
	var kind := cycle_kind if not cycle_kind.is_empty() else choose_fuel()
	if kind.is_empty() or assigned_depot.stockpile.amount(kind) < 1: return "Waiting for "+(str(kind) if not kind.is_empty() else fuel_preference)+" fuel"
	var output: int = cycle_output if not cycle_kind.is_empty() else fuel_rules.output(kind)
	if assigned_depot.stockpile.space() < output: return "Paused · need %d free storage for full output" % output
	return "Burning %s · %d%%" % [kind,roundi(cycle_elapsed/cycle_seconds*100) if cycle_seconds > 0 else 0]

@onready var ground = get_tree().get_first_node_in_group("terrain_grid")
func _ready() -> void:
	health = max_health if initial_health < 0 else clampi(initial_health,1,max_health)
	add_to_group("selectable_buildings")
	if assigned_depot == null and not assigned_depot_path.is_empty(): assigned_depot = get_node_or_null(assigned_depot_path)
	var start: Vector2i = ground.get_tile_at_position(global_position)-rules.generator_footprint/2
	if not ground.is_footprint_valid(start,rules.generator_footprint):
		push_error("Generator requires an exact valid footprint")
		queue_free()
		return
	global_position = ground.tile_to_world(start)+Vector3(rules.generator_footprint.x*0.5-0.5,0,rules.generator_footprint.y*0.5-0.5)
	for z in range(start.y,start.y+rules.generator_footprint.y):
		for x in range(start.x,start.x+rules.generator_footprint.x):
			var cell := Vector2i(x,z)
			cells.append(cell)
			ground.set_tile_feature(cell,"occupied_by",_key())
	add_to_group("energy_generators")
	if is_instance_valid(assigned_depot): assigned_depot.ownership_changed.connect(_source_changed)
	_update_display()
func source_valid() -> bool:
	return is_instance_valid(assigned_depot) and not assigned_depot.is_queued_for_deletion() and assigned_depot.team == team and assigned_depot.health > 0
func active() -> bool:
	if not enabled or health <= 0 or not source_valid(): return false
	if not cycle_kind.is_empty(): return cycle_ready()
	var kind := choose_fuel()
	return not kind.is_empty() and assigned_depot.stockpile.space() >= fuel_rules.output(kind)
func _process(delta: float) -> void:
	if not source_valid(): reset_cycle()
	if not enabled or health <= 0 or not source_valid(): _update_display(); return
	var time_left := maxf(0,delta)
	# Recheck storage/fuel for every complete cycle; never bank blocked time.
	for iteration in range(1000):
		if cycle_kind.is_empty():
			var kind := choose_fuel()
			if kind.is_empty() or assigned_depot.stockpile.space() < fuel_rules.output(kind): break
			cycle_kind = kind; cycle_output = fuel_rules.output(kind); cycle_seconds = fuel_rules.seconds(kind)
		if not cycle_ready(): break
		var advance := minf(time_left,maxf(0,cycle_seconds-cycle_elapsed))
		cycle_elapsed += advance; time_left -= advance
		if cycle_elapsed+0.000001 < cycle_seconds: break
		# Fuel remains in the Depot until this atomic completion. No yield occurs here.
		if not cycle_ready(): break
		assigned_depot.stockpile.withdraw(cycle_kind,1)
		assigned_depot.stockpile.deposit(&"energy",cycle_output)
		reset_cycle()
		if time_left <= 0: break
	_update_display()
func _update_display() -> void:
	state = describe_state()
	$Status.text = "GENERATOR · %s" % state
func _key() -> String:
	return "generator_%s" % get_instance_id()
func _exit_tree() -> void:
	_disconnect_source()
	if not is_instance_valid(ground): return
	for cell in cells:
		if ground.tiles[cell.y*500+cell.x].occupied_by == _key(): ground.set_tile_feature(cell,"occupied_by",null)

func take_damage(amount: int) -> void:
	health = maxi(0,health-maxi(0,amount))
	if health <= 0:
		set_process(false)
		for group in get_groups(): remove_from_group(group)
		queue_free()

func assign_source(depot: Node3D) -> bool:
	if not is_instance_valid(depot) or not depot.is_in_group("depots") or not SupplySource.covers(depot,global_position,team): return false
	_disconnect_source()
	reset_cycle()
	assigned_depot = depot
	assigned_depot.ownership_changed.connect(_source_changed)
	_update_display()
	return true
