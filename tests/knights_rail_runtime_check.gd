extends SceneTree
# Rendered check (docs/DRAGON_YARD_MODEL.md, docs/KNIGHTS_TRAIN_MODEL.md): the Dragon Yard half built, idle, at work
# raising a dragon and dying, then the Knights train car running (fire and smoke), standing and out of coal. Saves one
# sheet, knights_rail_art.png. The models are stepped by hand.
const TestOutput = preload("res://tests/test_output.gd")
const TILE := Vector2i(480,360)
var game: Node3D
var close: Camera3D
var tiles: Array[Image] = []
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> bool:
	if value: return true
	push_error(message); quit(1); return false
func grab() -> void:
	for frame in range(4): await process_frame
	var image: Image = root.get_texture().get_image()
	image.resize(TILE.x,TILE.y,Image.INTERPOLATE_LANCZOS)
	tiles.append(image)
func at(player: AnimationPlayer, clip: StringName, seconds: float) -> void:
	player.play(clip)
	player.seek(seconds,true)
	player.pause()
func look(from: Vector3, to: Vector3) -> void:
	close.global_position = from
	close.look_at(to)
func run() -> void:
	root.size = Vector2i(960,720)
	game = load("res://scenes/maps/resource_skirmish.tscn").instantiate()
	root.add_child(game)
	for frame in range(3): await process_frame
	game.set_process(false)
	for node in get_nodes_in_group("units"): node.set_process(false)
	game.get_node("CameraRig").set_process(false)
	if game.get("hud") != null: game.hud.visible = false
	close = Camera3D.new()
	game.add_child(close)
	close.fov = 40
	close.make_current()
	var origin := Vector3(180,0,180)
	# The Dragon Yard.
	var shop: Node3D = load("res://scenes/models/dragon_yard_model.tscn").instantiate()
	game.get_node("Entities").add_child(shop)
	shop.global_position = origin
	shop.set_process(false)
	for frame in range(2): await process_frame
	var player: AnimationPlayer = shop.get_node("Rig/AnimationPlayer")
	for clip in [&"Idle",&"Work"]:
		if not check(player.get_animation(clip).loop_mode == Animation.LOOP_LINEAR,"The Dragon Yard's %s should loop" % clip): return
	look(origin+Vector3(7,8,10),origin+Vector3(0,1.4,0))
	shop.show_construction(0.55)
	await grab()
	at(player,&"Idle",0.5)
	await grab()
	# Raising a dragon: Work loops at its own pace whatever the progress, and Idle comes back once the unit leaves.
	shop.show_print(0.1)
	if not check(player.is_playing() and player.current_animation == "Work","Producing, the Dragon Yard should play Work"): return
	shop.show_print(0.6)
	if not check(player.current_animation == "Work","Work should keep looping through production"): return
	at(player,&"Work",0.5)
	await grab()
	shop.unit_left()
	if not check(player.current_animation == "Idle","With the dragon gone, the Yard should idle again"): return
	shop.play_death()
	if not check(shop.get_children().any(func(c): return c.get("clip") == &"Death"),"The Dragon Yard's Die should spawn its death effects"): return
	player.seek(0.9,true)
	player.pause()
	for child in shop.get_children():
		if child.get("clip") == &"Death": child.player.seek(0.9,true); child.player.pause()
	await grab()
	shop.queue_free()
	# The Knights train car: running, standing, out of coal.
	var train: Node3D = load("res://scenes/models/knights_train_model.tscn").instantiate()
	game.get_node("Entities").add_child(train)
	train.global_position = origin
	train.set_process(false)
	for frame in range(2): await process_frame
	look(origin+Vector3(7,5.5,6),origin+Vector3(0,1.2,0))
	train.set_running(true)
	if not check(train.running(),"set_running(true) should run the train"): return
	train._process(0.9)
	await grab()
	train._process(0.25)
	await grab()
	train.set_running(false)
	train._process(0.5)
	await grab()
	train.set_out_of_fuel(true)
	train._process(0.5)
	if not check(not train.get_node("Car1").find_child("firebox_glow",true,false).visible,"Out of coal, the fire should go out"): return
	await grab()
	var sheet := Image.create(TILE.x*4,TILE.y*2,false,tiles[0].get_format())
	for i in range(tiles.size()):
		sheet.blit_rect(tiles[i],Rect2i(Vector2i.ZERO,TILE),Vector2i((i%4)*TILE.x,(i/4)*TILE.y))
	if not TestOutput.save_png(self,sheet,"knights_rail_art.png"): return
	print("KNIGHTS_RAIL_RUNTIME_CHECK_PASSED"); quit(TestOutput.exit_code())
