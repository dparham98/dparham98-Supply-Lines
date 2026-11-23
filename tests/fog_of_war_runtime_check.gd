extends SceneTree
# Rendered look at fog of war on Two Lakes (docs/FOG_OF_WAR.md): ground outside the player's sight is dimmed, ground
# inside it is not, and an enemy unit shows only once it is in sight. Saves fog_edge (the edge of the West start's
# sight), fog_off (the same view with the fog's overlay hidden), fog_enemy (an enemy just inside sight) and
# fog_minimap (the minimap, enlarged).
const TestOutput = preload("res://tests/test_output.gd")
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> bool:
	if value: return true
	push_error(message); quit(1); return false
func shot(name: String) -> Image:
	for frame in range(4): await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	TestOutput.save_png(self,image,name+".png")
	return image
func brightness(image: Image, camera: Camera3D, point: Vector3) -> float:
	var at := Vector2i(camera.unproject_position(point))
	var total := 0.0
	for dx in range(-3,4):
		for dy in range(-3,4):
			var c := image.get_pixelv((at+Vector2i(dx,dy)).clamp(Vector2i.ZERO,image.get_size()-Vector2i.ONE))
			total += c.get_luminance()
	return total/49.0
func run() -> void:
	root.size = Vector2i(1600,900)
	var game = load("res://scenes/maps/lakes_skirmish.tscn").instantiate()
	root.add_child(game)
	for frame in range(3): await process_frame
	var fog = game.fog_of_war()
	var rig = game.get_node("CameraRig")
	var depot: Node3D = game.depot
	var reach: float = fog.depot_vision
	# Look along the edge of the Depot's sight, toward the middle of the map.
	var edge: Vector3 = depot.global_position+Vector3(reach,0,0)
	rig.focus_position(edge,60)
	for frame in range(200): rig.advance_camera(1.0/60)
	fog.update_now()
	var camera: Camera3D = root.get_camera_3d()
	var inside: Vector3 = depot.global_position+Vector3(reach*0.5,0,6)
	var outside: Vector3 = depot.global_position+Vector3(reach+16,0,6)
	if not check(fog.visible_to("player",inside) and not fog.visible_to("player",outside),"The sample points should straddle the edge of sight"): return
	var fogged: Image = await shot("fog_edge")
	fog.overlay.visible = false
	var clear: Image = await shot("fog_off")
	fog.overlay.visible = true
	var in_on := brightness(fogged,camera,inside)
	var in_off := brightness(clear,camera,inside)
	var out_on := brightness(fogged,camera,outside)
	var out_off := brightness(clear,camera,outside)
	print("FOG brightness in sight %.3f / %.3f, in fog %.3f / %.3f" % [in_on,in_off,out_on,out_off])
	if not check(absf(in_on-in_off) < 0.02,"Ground in sight should not be dimmed: %.3f against %.3f" % [in_on,in_off]): return
	if not check(out_on < out_off*0.7,"Ground in the fog should be dimmed: %.3f against %.3f" % [out_on,out_off]): return
	# An enemy at the edge: hidden outside sight, shown once inside it.
	var enemy: Node3D = load("res://scenes/gameplay/tank.tscn").instantiate()
	enemy.team = "enemy"
	game.get_node("Entities/Units").add_child(enemy)
	enemy.set_process(false)
	enemy.global_position = outside
	fog.update_now()
	if not check(not enemy.visible,"An enemy outside sight should be hidden"): return
	enemy.global_position = depot.global_position+Vector3(reach-6,0,6)
	fog.update_now()
	if not check(enemy.visible,"An enemy inside sight should show"): return
	var view: Image = await shot("fog_enemy")
	var minimap: Control = game.get_node("Interface").find_child("Map",true,false)
	var box := Rect2i(minimap.get_global_rect())
	var crop := view.get_region(box)
	crop.resize(box.size.x*3,box.size.y*3,Image.INTERPOLATE_NEAREST)
	TestOutput.save_png(self,crop,"fog_minimap.png")
	print("FOG_OF_WAR_RUNTIME_CHECK_PASSED")
	quit(TestOutput.exit_code())
