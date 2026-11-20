extends SceneTree
# Headless, on Two Lakes: fog of war (docs/FOG_OF_WAR.md). Each side sees round its own units and buildings, as far
# as each one's vision; the other side's units, buildings and shots show only inside the player's sight and cannot
# be picked from the minimap outside it; what a side has seen stays explored.
var game: Node3D
var fog: Node
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> bool:
	if value: return true
	push_error(message); quit(1); return false
func actor(id: String, team: String, point: Vector3) -> Node3D:
	var unit = load("res://scenes/gameplay/"+id+".tscn").instantiate()
	unit.team = team
	game.get_node("Entities/Units").add_child(unit)
	unit.set_process(false)
	unit.global_position = point
	return unit
func run() -> void:
	game = load("res://scenes/maps/lakes_skirmish.tscn").instantiate()
	root.add_child(game)
	for frame in range(3): await process_frame
	game.set_process(false)
	for node in get_nodes_in_group("units"): node.set_process(false)
	game.enemy_player().set_process(false)
	fog = game.fog_of_war()
	if not check(fog != null and fog.get_parent() == game,"Two Lakes should have its fog of war in the saved scene"): return
	fog.update_now()
	var depot: Node3D = game.depot
	var east: Vector3 = game.get_node("Sites/EnemyStart").global_position
	# Each side sees its own start and not the other's.
	if not check(fog.visible_to("player",depot.global_position) and not fog.visible_to("player",east),"The player should see the West start and not the East"): return
	if not check(fog.visible_to("enemy",east) and not fog.visible_to("enemy",depot.global_position),"The enemy should see the East start and not the West"): return
	# The enemy's starting units are hidden; the player's own and the shared mines are not.
	var hidden := 0
	for unit in get_nodes_in_group("units"):
		if unit.team == "enemy":
			if not check(not unit.visible,"%s should be hidden in the fog" % unit.name): return
			hidden += 1
		elif unit.team == "player":
			if not check(unit.visible,"%s is the player's own and should show" % unit.name): return
	if not check(hidden >= 2,"The East start's enemies should all be hidden: %d" % hidden): return
	var east_depot: Node3D = game.get_node("Entities/Buildings/EnemyDepot")
	if not check(not east_depot.visible,"The enemy's Depot should be hidden in the fog"): return
	for mine in get_nodes_in_group("mines"):
		if not check(mine.visible,"Shared mines always show"): return
	# Vision is each unit's own: from a lone Tank (52 m) a point 40 m off is in sight, from an Infantry (30 m) not.
	var spot := Vector3(0,0,150)
	var tank := actor("tank","player",spot)
	var foe := actor("infantry","enemy",spot+Vector3(40,0,0))
	fog.update_now()
	if not check(fog.visible_to("player",spot+Vector3(40,0,0)) and foe.visible,"A Tank should see an enemy 40 m away"): return
	tank.free()
	var rifle := actor("infantry","player",spot)
	fog.update_now()
	if not check(not fog.visible_to("player",spot+Vector3(40,0,0)) and not foe.visible,"An Infantry should not see 40 m"): return
	if not check(fog.explored_by("player",spot+Vector3(40,0,0)),"Ground once seen stays explored"): return
	# A hidden enemy cannot be picked from the minimap; once in sight it can.
	var pick = game.get_script().MapPick.new(foe.global_position,4.0)
	var camera: Camera3D = game.get_viewport().get_camera_3d()
	if not check(game.pick_distance(foe,camera,pick) == INF,"A hidden enemy should not be picked from the minimap"): return
	foe.global_position = spot+Vector3(10,0,0)
	fog.update_now()
	pick = game.get_script().MapPick.new(foe.global_position,4.0)
	if not check(foe.visible and game.pick_distance(foe,camera,pick) < INF,"An enemy in sight should show and be pickable"): return
	# Shots: the enemy's in the fog are hidden, the player's and those landing in sight show.
	var far_shot: Node3D = game.show_shot(east,east+Vector3(5,1,0),"enemy")
	var near_shot: Node3D = game.show_shot(east,spot,"enemy")
	var own_shot: Node3D = game.show_shot(east,east+Vector3(5,1,0),"player")
	if not check(not far_shot.visible and near_shot.visible and own_shot.visible,"Enemy shots should show only where the player sees them"): return
	# The shade drawn over the map: clear in sight, dark in fog.
	# (The image the texture is updated from; a headless run keeps no copy of the texture itself.)
	if not check((fog.overlay.material_override as ShaderMaterial).get_shader_parameter("shade") == fog.shade_texture(),"The overlay should draw the player's shade"): return
	var image: Image = fog._shade["player"]
	var at := func(point: Vector3) -> float:
		var cell: Vector2i = fog._cell(point)
		return image.get_pixelv(cell).a
	if not check(at.call(depot.global_position) < 0.5 and at.call(east) > 0.5,"The shade should be clear at the Depot and dark at the East start"): return
	rifle.free()
	foe.free()
	print("FOG_OF_WAR_TEST_PASSED")
	quit()
