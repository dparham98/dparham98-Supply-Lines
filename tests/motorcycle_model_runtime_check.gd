extends SceneTree
# Rendered check: the Motorcycle parked, riding, leaning, firing on the move and dying, at the game's
# camera distance and close up. Saves the ten views as one sheet, motorcycle_animation.png. Time is
# stopped and stepped by hand so every view is the same on every run.
const TestOutput = preload("res://tests/test_output.gd")
const Projectile = preload("res://scripts/gameplay/projectile.gd")
const Burst = preload("res://scripts/components/burst_effect.gd")
const TILE := Vector2i(640,450)
var game: Node3D
var rig: Node3D
var close: Camera3D
var tiles: Array[Image] = []
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> bool:
	if value: return true
	push_error(message); quit(1); return false
func step(unit: Node3D, model: Node3D, frames: int) -> void:
	for i in range(frames):
		unit._process(1.0/60)
		model._process(1.0/60)
## Close views are the whole frame scaled down. Views at the game's distance are cut out of the frame
## around the point at full size, so the bike is as many pixels tall as it is in play.
func grab(point := Vector3.INF) -> void:
	for frame in range(4): await process_frame
	var image: Image = root.get_texture().get_image()
	if point == Vector3.INF:
		image.resize(TILE.x,TILE.y,Image.INTERPOLATE_LANCZOS)
	else:
		var centre := Vector2i(rig.camera.unproject_position(point))
		var corner := (centre-TILE/2).clamp(Vector2i.ZERO,image.get_size()-TILE)
		image = image.get_region(Rect2i(corner,TILE))
	tiles.append(image)
func far(point: Vector3) -> void:
	rig.focus_position(point,20)
	for frame in range(240): rig.advance_camera(1.0/60)
	rig.camera.make_current()
	await grab(point)
func near(from: Vector3, at: Vector3, fov := 32.0) -> void:
	close.global_position = from
	close.look_at(at)
	close.fov = fov
	close.make_current()
	await grab()
func run() -> void:
	root.size = Vector2i(1280,900)
	game = load("res://scenes/maps/resource_skirmish.tscn").instantiate()
	root.add_child(game)
	for frame in range(3): await process_frame
	game.set_process(false)
	for node in get_nodes_in_group("units"): node.set_process(false)
	Engine.time_scale = 0.0
	rig = game.get_node("CameraRig")
	rig.set_process(false)
	close = Camera3D.new()
	game.add_child(close)
	if game.get("hud") != null: game.hud.visible = false
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
	if not check(model.scene_file_path == "res://scenes/models/motorcycle_model.tscn","Motorcycle still uses the placeholder"): return
	model.sway_degrees = 0.0
	# Parked, on its stand.
	step(unit,model,120)
	await far(origin)
	await near(origin+Vector3(-4.6,1.5,-2.4),origin+Vector3(0,0.9,0))
	# Riding straight.
	unit.command_move(origin+Vector3(0,0,-30))
	step(unit,model,70)
	var at := unit.global_position
	await near(at+Vector3(-3.0,1.7,-4.6),at+Vector3(0,0.95,0))
	# Leaning into a left turn, seen from ahead.
	unit.command_move(at+Vector3(-16,0,-1))
	step(unit,model,13)
	at = unit.global_position
	var heading: Vector3 = -(unit.get_node("Visuals") as Node3D).global_basis.z
	print("LEAN degrees ",rad_to_deg(model.lean_angle())," steer ",rad_to_deg(model.steer_angle()))
	await near(at+heading*6.0+Vector3(0,1.3,0),at+Vector3(0,0.95,0),28.0)
	# Firing on the move at a target off to the right.
	unit._stop_route(); unit.order = "idle"
	step(unit,model,30)
	unit.global_position = origin
	unit.get_node("Visuals").rotation.y = 0.0
	unit.command_move(origin+Vector3(0,0,-30))
	step(unit,model,45)
	heading = -(unit.get_node("Visuals") as Node3D).global_basis.z
	var foe: Node3D = load("res://scenes/gameplay/hostile.tscn").instantiate()
	foe.team = "enemy"
	game.get_node("Entities/Units").add_child(foe)
	foe.set_process(false)
	for cell in foe._claimed.duplicate(): foe._release(cell)
	foe.global_position = unit.global_position+heading*5.0+Vector3(-heading.z,0,heading.x)*2.4
	for frame in range(2): await process_frame
	var health: int = foe.health
	for i in range(200):
		step(unit,model,1)
		if foe.health < health: break
	if not check(foe.health < health,"Motorcycle did not fire"): return
	var spikes := game.get_children().filter(func(n): return n.get_script() == Projectile)
	if not check(spikes.size() == 1,"No rail spike in flight"): return
	spikes[0].set_process(false)
	var fx = model.muzzle
	step(unit,model,2)
	fx.player.advance(3.0/60)
	spikes[0]._process(1.0/60)
	at = unit.global_position
	await near(at+Vector3(-3.4,2.6,-4.4),at+Vector3(1.0,1.2,0),38.0)
	await far(at+Vector3(1,0,0))
	# The spike lands and sticks in the target.
	for i in range(10):
		if spikes[0].is_queued_for_deletion(): break
		spikes[0]._process(1.0/60)
	for frame in range(2): await process_frame
	var impact = game.get_children().filter(func(n): return n.get_script() == Burst)[0]
	impact.player.advance(0.12)
	var hit: Vector3 = impact.global_position
	var back := Vector3(at.x-hit.x,0,at.z-hit.z).normalized()
	await near(hit+back*3.4+Vector3(-back.z,0,back.x)*1.6+Vector3(0,0.8,0),hit+Vector3(0,-0.3,0),30.0)
	# Then the bike is killed while still riding.
	impact.queue_free()
	foe.queue_free()
	step(unit,model,20)
	fx.player.advance(20.0/60)
	var wreck_from: Vector3 = model.global_position
	unit.take_damage(unit.health)
	for frame in range(2): await process_frame
	var crash = model.get_children().filter(func(n): return n.get_script() == Burst)[0]
	model.player.advance(0.8); crash.player.advance(0.8)
	await near(wreck_from+Vector3(-7.5,5.0,-9.5),wreck_from+Vector3(0.3,0.6,-3.0),30.0)
	model.player.advance(2.0); crash.player.advance(2.0)
	await near(wreck_from+Vector3(-6.5,4.5,-10.5),wreck_from+Vector3(0.4,0.3,-4.2),30.0)
	await far(wreck_from+Vector3(0.4,0,-4.0))
	var sheet := Image.create(TILE.x*5,TILE.y*2,false,tiles[0].get_format())
	for i in range(tiles.size()):
		sheet.blit_rect(tiles[i],Rect2i(Vector2i.ZERO,TILE),Vector2i((i%5)*TILE.x,(i/5)*TILE.y))
	if not TestOutput.save_png(self,sheet,"motorcycle_animation.png"): return
	print("MOTORCYCLE_MODEL_RUNTIME_CHECK_PASSED"); quit(TestOutput.exit_code())
