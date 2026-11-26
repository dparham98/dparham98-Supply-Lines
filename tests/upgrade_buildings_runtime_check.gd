extends SceneTree
# Rendered check (docs/FOUNDRY_MODEL.md, docs/FORGE_MODEL.md): the Foundry and the Forge in the game, half built,
# idle, at two moments of their Research loop and half way through Die with their death effects. Saves one
# sheet, upgrade_buildings.png, with the Foundry's row on top. The models are stepped by hand.
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
	for id in ["foundry","forge"]:
		var model: Node3D = load("res://scenes/models/%s_model.tscn" % id).instantiate()
		game.get_node("Entities").add_child(model)
		model.global_position = origin
		model.set_process(false)
		for frame in range(2): await process_frame
		var player: AnimationPlayer = model.get_node("Rig/AnimationPlayer")
		if not check(player.has_animation(&"Research") and player.get_animation(&"Research").loop_mode == Animation.LOOP_LINEAR,"%s: Research should loop" % id): return
		if not check(player.get_animation(&"Idle").loop_mode == Animation.LOOP_LINEAR,"%s: Idle should loop" % id): return
		close.global_position = origin+Vector3(7.5,8.5,10.5)
		close.look_at(origin+Vector3(0,1.4,0))
		model.show_construction(0.55)
		await grab()
		at(player,&"Idle",1.0)
		await grab()
		model.show_research(true)
		if not check(model.researching(),"%s: show_research(true) should play Research" % id): return
		at(player,&"Research",1.0 if id == "foundry" else 0.55)
		await grab()
		at(player,&"Research",2.0 if id == "foundry" else 0.98)
		await grab()
		model.play_death()
		var fx: Node3D = null
		for child in model.get_children():
			if child.has_method("set") and child.get("clip") == &"Death": fx = child
		if not check(fx != null,"%s: Die should spawn its death effects" % id): return
		player.seek(0.9,true)
		player.pause()
		fx.player.seek(0.9,true)
		fx.player.pause()
		await grab()
		model.queue_free()
		for frame in range(2): await process_frame
	var sheet := Image.create(TILE.x*5,TILE.y*2,false,tiles[0].get_format())
	for i in range(tiles.size()):
		sheet.blit_rect(tiles[i],Rect2i(Vector2i.ZERO,TILE),Vector2i((i%5)*TILE.x,(i/5)*TILE.y))
	if not TestOutput.save_png(self,sheet,"upgrade_buildings.png"): return
	print("UPGRADE_BUILDINGS_RUNTIME_CHECK_PASSED"); quit(TestOutput.exit_code())
