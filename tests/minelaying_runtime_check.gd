extends SceneTree
# Rendered check (docs/MINES.md, docs/LAND_MINE_MODEL.md): a Derailer with two mines in its trays, laying one
# (five steps through the 2 s lay), the mine arming, armed, spotted by the enemy, and its blast. Saves the
# views as one sheet, minelaying_animation.png. Time is stopped and stepped by hand.
const TestOutput = preload("res://tests/test_output.gd")
const TILE := Vector2i(560,420)
var game: Node3D
var close: Camera3D
var tiles: Array[Image] = []
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> bool:
	if value: return true
	push_error(message); quit(1); return false
func step(nodes: Array, frames: int) -> void:
	for i in range(frames):
		for node in nodes: if is_instance_valid(node): node._process(1.0/30)
func grab() -> void:
	for frame in range(4): await process_frame
	var image: Image = root.get_texture().get_image()
	image.resize(TILE.x,TILE.y,Image.INTERPOLATE_LANCZOS)
	tiles.append(image)
func near(from: Vector3, at: Vector3, fov := 34.0) -> void:
	close.global_position = from
	close.look_at(at)
	close.fov = fov
	close.make_current()
	await grab()
func run() -> void:
	root.size = Vector2i(1120,840)
	game = load("res://scenes/maps/resource_skirmish.tscn").instantiate()
	root.add_child(game)
	for frame in range(3): await process_frame
	game.set_process(false)
	game.vehicle_fuel_required = false
	for node in get_nodes_in_group("units"): node.set_process(false)
	for node in get_nodes_in_group("enemies"): node.queue_free()
	game.get_node("CameraRig").set_process(false)
	close = Camera3D.new()
	game.add_child(close)
	if game.get("hud") != null: game.hud.visible = false
	Research.complete(game,"player",Research.MINELAYING)
	var origin := Vector3(180,0,180)
	var unit: Node3D = load("res://scenes/gameplay/motorcycle.tscn").instantiate()
	unit.team = "player"
	unit.start_fuelled = true
	game.get_node("Entities/Units").add_child(unit)
	unit.set_process(false)
	for cell in unit._claimed.duplicate(): unit._release(cell)
	unit.global_position = origin
	for frame in range(3): await process_frame
	var model = unit.get_node("Visuals/Model")
	model.set_process(false)
	Engine.time_scale = 0.0
	unit.mines = 2
	step([unit,model],40)
	if not check(model.mines_shown() == 2,"Both trays should show a mine"): return
	await near(origin+Vector3(-3.2,3.6,3.6),origin+Vector3(0,0.6,0))
	# Lay one at a point 6 m ahead: it rides past and stops with the point behind it.
	var point := origin+Vector3(0,0,-6)
	unit.command_lay_mine(point)
	var shots := [0.1,0.3,0.55,0.8]
	var mine: Node3D = null
	for i in range(30*30):
		step([unit,model],1)
		if unit.order == "lay_mine" and unit._work_timer > 0.0 and not shots.is_empty() and unit._work_timer/unit.mine_rules.lay_seconds >= shots[0]:
			shots.pop_front()
			var at: Vector3 = unit.global_position
			await near(at+Vector3(-4.6,4.4,2.6)+(point-at)*0.3,at.lerp(point,0.4)+Vector3(0,0.7,0))
		var laid := get_nodes_in_group("land_mines")
		if not laid.is_empty(): mine = laid[0]; break
	if not check(mine != null and shots.is_empty(),"The Derailer should lay a mine (%s)" % unit.state): return
	print("LAID at ",mine.global_position," asked ",point," bike at ",unit.global_position)
	if not check(Vector2(mine.global_position.x-point.x,mine.global_position.z-point.z).length() < 0.01,"The mine goes on the point clicked"): return
	mine.set_process(false)
	var mine_model = mine.get_node("Visuals/Model")
	mine_model.set_process(false)
	# Arming, a second in; then armed.
	step([mine,mine_model],30)
	await near(point+Vector3(-1.6,1.4,1.6),point)
	step([mine,mine_model],70)
	step([unit,model],30)
	await near(point+Vector3(-1.6,1.4,1.6),point)
	if not check(mine.armed,"The mine should be armed after 3 s"): return
	# Seen by the enemy over a Drone: the spotted ring.
	mine._viewer = "enemy"
	var drone: Node3D = load("res://scenes/gameplay/drone.tscn").instantiate()
	drone.team = "enemy"
	game.get_node("Entities/Units").add_child(drone)
	drone.set_process(false)
	drone.global_position = point+Vector3(8,0,0)
	for frame in range(2): await process_frame
	mine._look = 0.0
	step([mine,mine_model],20)
	if not check(mine_model.detected(),"An enemy-detected mine should show the spotted ring"): return
	await near(point+Vector3(-3.0,4.0,3.0),point)
	drone.queue_free()
	# The blast, 0.15 s and 0.6 s in.
	unit.global_position = origin+Vector3(30,0,30)
	mine.take_damage(100)
	for frame in range(2): await process_frame
	var blast: Node3D = null
	for node in game.get_node("Entities").get_children():
		if node.name == "Blast": blast = node
	if not check(blast != null,"The mine's blast should play"): return
	blast.player.advance(0.15)
	await near(point+Vector3(-6,5,6),point+Vector3(0,0.8,0),40.0)
	blast.player.advance(0.45)
	await near(point+Vector3(-6,5,6),point+Vector3(0,0.5,0),40.0)
	var sheet := Image.create(TILE.x*5,TILE.y*2,false,tiles[0].get_format())
	for i in range(tiles.size()):
		sheet.blit_rect(tiles[i],Rect2i(Vector2i.ZERO,TILE),Vector2i((i%5)*TILE.x,(i/5)*TILE.y))
	if not TestOutput.save_png(self,sheet,"minelaying_animation.png"): return
	print("MINELAYING_RUNTIME_CHECK_PASSED"); quit(TestOutput.exit_code())
