extends PanelContainer
# Development-only playtest tools (docs/PLAYTEST_TOOLS.md). F10 toggles the panel when the
# skirmish enables playtest_tools and this is a debug build. Changes are immediate and unpaid.
@export var spawn_scenes: Array[PackedScene] = []
@export var resource_step := 100
@onready var game = get_tree().get_first_node_in_group("skirmish")
@onready var status: Label = $Body/Status
var spawn_armed := false
func _ready() -> void:
	visible = false
	# Restart reloads the scene; never carry a paused or fast tree into it.
	get_tree().paused = false
	Engine.time_scale = 1.0
	for kind in ["energy","iron","wood","coal"]:
		get_node("Body/Resources/"+kind.capitalize()).pressed.connect(add_resource.bind(StringName(kind)))
	$Body/Fuel/Fill.pressed.connect(set_fuel.bind(true))
	$Body/Fuel/Empty.pressed.connect(set_fuel.bind(false))
	var units: OptionButton = $Body/Spawn/Unit
	units.clear()
	for scene in spawn_scenes: units.add_item(scene.resource_path.get_file().get_basename().capitalize())
	$Body/Spawn/Place.pressed.connect(func(): spawn_armed = true; report("Click open ground to spawn. Shift keeps placing; Esc or right-click stops."))
	$Body/Speed/Pause.pressed.connect(toggle_pause)
	for speed in [1,2,4]:
		get_node("Body/Speed/X%d" % speed).pressed.connect(set_speed.bind(float(speed)))
func enabled() -> bool:
	return game != null and game.get("playtest_tools") == true and OS.is_debug_build()
func report(text: String) -> void:
	status.text = text
func _process(_delta: float) -> void:
	if not visible: return
	var target = resource_target()
	$Body/Target.text = "Target: %s" % (target_name(target) if target != null else "select a friendly Depot or Cargo vehicle")
	$Body/Speed/Pause.text = "Resume" if get_tree().paused else "Pause"
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("playtest_tools") and not event.is_echo():
		if not enabled(): return
		visible = not visible
		spawn_armed = spawn_armed and visible
		get_viewport().set_input_as_handled()
		return
	if not spawn_armed: return
	if (event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE) or (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT):
		spawn_armed = false
		report("Spawning stopped.")
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			var camera := get_viewport().get_camera_3d()
			var point = Plane(Vector3.UP,0).intersects_ray(camera.project_ray_origin(event.position),camera.project_ray_normal(event.position))
			if point != null: spawn_at(point)
			spawn_armed = event.shift_pressed
		get_viewport().set_input_as_handled()
# Resources go to the selected friendly Depot, else the selected friendly Cargo vehicle or Train.
func resource_target() -> Node:
	var building = game.selected_building
	if is_instance_valid(building) and building.is_in_group("depots") and building.team == "player": return building
	for unit in get_tree().get_nodes_in_group("units"):
		if unit.team == "player" and unit.is_selected and unit.is_cargo_vehicle: return unit
	return null
func target_name(target: Node) -> String:
	return "%s · E%d I%d W%d C%d / %d" % [target.name,target.stockpile.amount(&"energy"),target.stockpile.amount(&"iron"),target.stockpile.amount(&"wood"),target.stockpile.amount(&"coal"),target.stockpile.capacity]
func add_resource(kind: StringName) -> int:
	var target = resource_target()
	if target == null: report("Select a friendly Depot or Cargo vehicle first."); return 0
	var added: int = target.stockpile.deposit(kind,resource_step)
	report("Added %d %s to %s." % [added,kind,target.name] if added > 0 else "%s storage is full." % target.name)
	return added
func set_fuel(full: bool) -> int:
	var changed := 0
	for unit in get_tree().get_nodes_in_group("units"):
		if unit.team != "player" or not unit.is_selected or not unit.fuel_active(): continue
		unit.fuel = unit.fuel_rules.reserve_capacity if full else 0.0
		if full: unit.out_of_fuel = false
		changed += 1
	report(("Filled" if full else "Emptied")+" fuel on %d vehicle(s)." % changed if changed > 0 else "Select a fuel-using vehicle first.")
	return changed
func spawn_at(point: Vector3) -> Node3D:
	var index: int = $Body/Spawn/Unit.selected
	if index < 0 or index >= spawn_scenes.size(): return null
	var unit = spawn_scenes[index].instantiate()
	unit.team = "enemy" if $Body/Spawn/Team.selected == 1 else "player"
	unit.position = point
	game.get_node("Entities/Units").add_child(unit,true)
	report("Spawned %s (%s)." % [unit.name,unit.team])
	return unit
func toggle_pause() -> void:
	get_tree().paused = not get_tree().paused
	report("Paused. Camera, selection and this panel still work; orders wait." if get_tree().paused else "Resumed.")
func set_speed(scale: float) -> void:
	Engine.time_scale = scale
	report("Game speed %d×." % int(scale))
