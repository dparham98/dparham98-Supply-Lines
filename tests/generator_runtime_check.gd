extends SceneTree
var game: Node3D
var hud: CanvasLayer
const TestOutput = preload("res://tests/test_output.gd")
const OUTPUT = ""
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> bool:
	if value: return true
	push_error(message); quit(1); return false
func click_at(point: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	root.push_input(motion,true)
	var event := InputEventMouseButton.new()
	event.position = point
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	root.push_input(event,true)
	# A human click spans multiple process frames. Do not emit button signals directly.
	for frame in range(5): await process_frame
	event = InputEventMouseButton.new()
	event.position = point
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = false
	root.push_input(event,true)
	for frame in range(3): await process_frame

func click(node: Control) -> void:
	var previous := Rect2()
	var stable := 0
	for frame in range(30):
		await process_frame
		var current := node.get_global_rect()
		if current == previous and node.is_visible_in_tree(): stable += 1
		else: stable = 0
		previous = current
		if stable >= 3: break
	await click_at(node.get_global_rect().get_center())
func shot(name: String) -> void:
	for frame in range(8): await process_frame
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	TestOutput.save_png(self, root.get_texture().get_image(), OUTPUT+name+".png")
func focus(point: Vector3, zoom: float = 55) -> void:
	var rig = game.get_node("CameraRig")
	rig.focus_position(point,zoom)
	for frame in range(180): rig.advance_camera(1.0/60)
func target(node: Node3D) -> Vector2:
	return game.get_viewport().get_camera_3d().unproject_position(node.global_position+Vector3.UP*1.5)
func right_click_at(point: Vector2) -> void:
	var motion := InputEventMouseMotion.new(); motion.position = point; root.push_input(motion,true)
	var event := InputEventMouseButton.new(); event.position = point; event.button_index = MOUSE_BUTTON_RIGHT; event.pressed = true
	root.push_input(event,true)
	for frame in range(5): await process_frame
	event = InputEventMouseButton.new(); event.position = point; event.button_index = MOUSE_BUTTON_RIGHT; event.pressed = false; root.push_input(event,true)
	for frame in range(3): await process_frame
func choose(option: OptionButton, index: int) -> void:
	await click(option)
	var popup := option.get_popup()
	var point := Vector2(popup.position)+Vector2(20,(index+0.5)*popup.size.y/popup.item_count)
	await click_at(point)
	if popup.visible: push_error("Popup did not close after item click")
func step(vehicle: Node3D, seconds: float) -> void:
	for i in range(ceili(seconds*60)): vehicle._process(1.0/60)
func run() -> void:
	root.size = Vector2i(1280,900)
	game = load("res://scenes/maps/generator_exercise.tscn").instantiate()
	root.add_child(game); await process_frame
	game.set_process(false); hud = game.get_node("Interface")
	for group in ["units","depots","energy_generators"]:
		for node in get_nodes_in_group(group): node.set_process(false)
	var rig = game.get_node("CameraRig"); rig.set_process(false)
	var generator = game.get_node("Entities/Buildings/Generator")
	var depot = game.depot
	generator.reset_cycle(); depot.energy = 500; depot.wood = 20; depot.coal = 10
	focus(generator.global_position,60)
	await click_at(target(generator))
	if not check(hud.shown == generator and hud.context.get_node("GeneratorMode").visible,"Generator fuel HUD selection failed"): return
	await shot("generator_wood")
	await choose(hud.context.get_node("GeneratorMode"),1)
	if not check(generator.fuel_preference == "coal","Coal popup selection failed"): return
	generator._process(4)
	if not check(depot.energy == 500 and depot.coal == 10 and generator.cycle_kind == &"coal" and generator.cycle_elapsed == 4,"Coal cycle produced early"): return
	await shot("generator_coal")
	await choose(hud.context.get_node("GeneratorMode"),0)
	await click(hud.card.get_node("ToggleGenerator"))
	generator._process(100)
	if not check(not generator.enabled and generator.cycle_elapsed == 4 and depot.coal == 10,"Pause GUI consumed fuel or progressed"): return
	await shot("generator_paused")
	await click(hud.card.get_node("ToggleGenerator")); generator._process(1)
	if not check(generator.enabled and depot.energy == 550 and depot.coal == 9 and depot.wood == 20,"Resume GUI lost the pending coal cycle"): return
	generator._process(2)
	if not check(depot.energy == 560 and depot.wood == 19,"Wood preference did not apply next cycle"): return
	await choose(hud.context.get_node("GeneratorMode"),2)
	if not check(generator.fuel_preference == "either","Either popup failed"): return
	depot.wood = 0; depot.coal = 1; generator._process(5)
	if not check(depot.energy == 610 and depot.coal == 0,"Either did not use available coal"): return
	generator._process(100)
	if not check(depot.energy == 610 and not generator.active(),"Empty generator created energy"): return
	await shot("generator_empty")
	depot.wood = 1; depot.energy = depot.storage_capacity-depot.iron-depot.wood
	generator._process(100)
	if not check(depot.stockpile.space() == 0 and depot.wood == 1 and generator.cycle_elapsed == 0,"Full storage consumed fuel"): return
	await shot("generator_full")
	depot.stockpile.withdraw(&"energy",10); generator._process(2)
	if not check(depot.stockpile.space() == 1 and depot.wood == 0,"Freed storage did not accept full output"): return
	var other = game.get_node("Entities/Buildings/EastDepot")
	# Move the camera only; source assignment remains an explicit HUD choice.
	await choose(hud.context.get_node("AssignedSource"),hud.assignment_sources.find(other))
	if not check(generator.assigned_depot == other,"Generator operating Depot popup failed"): return
	other.wood = 1; var old: int = depot.energy; var old_other: int = other.energy
	generator._process(2)
	if not check(depot.energy == old and other.energy == old_other+10 and other.wood == 0,"Generator assignment charged wrong stockpile"): return
	await shot("generator_assigned_depot")
	root.size = Vector2i(1440,960); await shot("generator_wide")
	print("GENERATOR_RUNTIME_CHECKS_PASSED"); quit(TestOutput.exit_code())
