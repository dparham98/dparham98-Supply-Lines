extends SceneTree
func _initialize() -> void:
	call_deferred("build_scenes")
func own(root: Node, child: Node) -> void:
	child.owner = root
	if not child.scene_file_path.is_empty(): return
	for c in child.get_children(): own(root, c)
func save_scene(root: Node, path: String) -> void:
	for c in root.get_children(): own(root, c)
	var packed := PackedScene.new()
	assert(packed.pack(root) == OK)
	assert(ResourceSaver.save(packed, path) == OK)
	root.free()
func node(name_: String, parent: Node = null) -> Node3D:
	var n := Node3D.new()
	n.name = name_
	if parent: parent.add_child(n)
	return n
func material(name_: String, color: Color, unshaded := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color.srgb_to_linear()
	m.roughness = 0.94
	m.vertex_color_use_as_albedo = true
	if unshaded: m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	assert(ResourceSaver.save(m, "res://assets/materials/terrain/" + name_ + ".tres") == OK)
	return m
func cone(name_: String, r: float, h: float, top: float, m: Material) -> Mesh:
	var mesh := CylinderMesh.new()
	mesh.bottom_radius = r
	mesh.top_radius = top
	mesh.height = h
	mesh.radial_segments = 6
	mesh.rings = 1
	mesh.material = m
	assert(ResourceSaver.save(mesh, "res://assets/meshes/terrain/" + name_ + ".tres") == OK)
	return mesh
func mesh_node(name_: String, mesh: Mesh, parent: Node, pos := Vector3.ZERO) -> MeshInstance3D:
	var n := MeshInstance3D.new()
	n.name = name_
	n.mesh = mesh
	n.position = pos
	parent.add_child(n)
	return n
func instance(path: String, name_: String, parent: Node) -> Node:
	var n := load(path).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE) as Node
	n.name = name_
	parent.add_child(n)
	return n
func visual_slot(model: String, parent: Node) -> void:
	var slot := node("Visuals", parent)
	slot.set_script(load("res://scripts/components/visual_asset_slot.gd"))
	slot.set("model_scene", load(model))
	slot.editor_description = "Assign your imported model scene to Model Scene in the Inspector. Keep the model rooted at its feet."
	instance(model, "Model", slot)

func build_scenes() -> void:
	var tree := node("Tree")
	mesh_node("Trunk", cone("tree_trunk", 0.16, 1.4, 0.14, material("tree_bark", Color("65513c"))), tree, Vector3(0, 0.7, 0))
	mesh_node("LowerCanopy", cone("tree_canopy", 0.95, 2.2, 0, material("tree_canopy", Color("426b35"))), tree, Vector3(0, 1.8, 0))
	mesh_node("Crown", cone("tree_crown", 0.67, 1.65, 0, material("tree_crown", Color("5c8040"))), tree, Vector3(0, 2.65, 0))
	save_scene(tree, "res://scenes/terrain/tree.tscn")
	var mountain := node("Mountain")
	mesh_node("Rock", cone("mountain_rock", 2.7, 5, 0.15, material("mountain_rock", Color("777c75"))), mountain, Vector3(0, 2.5, 0))
	save_scene(mountain, "res://scenes/terrain/mountain.tscn")
	var ore := node("OreDeposit")
	mesh_node("OreRock", cone("ore_rock", 0.7, 1.2, 0.25, material("ore_rock", Color("a45b35"))), ore, Vector3(0, 0.6, 0))
	save_scene(ore, "res://scenes/terrain/ore_deposit.tscn")
	# Saved scenery is shared by the editor and runtime; no runtime scatter is needed.
	var baker = load("res://scripts/tools/terrain_baker.gd").new()
	var landmarks: Node3D = baker.build(load("res://scenes/terrain/tree.tscn"), load("res://scenes/terrain/mountain.tscn"), load("res://scenes/terrain/ore_deposit.tscn"))
	save_scene(landmarks, "res://scenes/maps/terrain_landmarks.tscn")
	var terrain := node("Terrain")
	terrain.set_script(load("res://scripts/terrain/terrain_assets.gd"))
	terrain.set("tree_scene", load("res://scenes/terrain/tree.tscn"))
	terrain.set("mountain_scene", load("res://scenes/terrain/mountain.tscn"))
	terrain.set("ore_scene", load("res://scenes/terrain/ore_deposit.tscn"))
	terrain.editor_description = "Ground contains terrain rules; Landmarks is the saved visible scenery. Edit asset slots and press Rebuild terrain scenery."
	var plane := PlaneMesh.new()
	plane.size = Vector2(500, 500)
	var ground := mesh_node("Ground", plane, terrain)
	ground.material_override = load("res://assets/materials/terrain/terrain_surface.tres")
	ground.set_script(load("res://scripts/terrain/terrain_grid.gd"))
	ground.add_to_group("terrain_grid", true)
	var body := StaticBody3D.new()
	body.name = "GroundCollision"
	ground.add_child(body)
	var shape := CollisionShape3D.new()
	shape.name = "GroundBounds"
	var box := BoxShape3D.new()
	box.size = Vector3(500, 0.1, 500)
	shape.shape = box
	body.add_child(shape)
	instance("res://scenes/maps/terrain_landmarks.tscn", "Landmarks", terrain)
	save_scene(terrain, "res://scenes/maps/terrain.tscn")
	var lighting := node("Lighting")
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-55, -30, 0)
	sun.light_color = Color("fff1d5")
	sun.light_energy = 0.85
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 600
	lighting.add_child(sun)
	var env := WorldEnvironment.new()
	env.name = "AmbientSky"
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("293942")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color("b8c4c8")
	env.environment.ambient_light_energy = 0.4
	lighting.add_child(env)
	save_scene(lighting, "res://scenes/maps/lighting.tscn")
	for kind in ["infantry", "enemy", "headquarters"]:
		var placeholder := node("PlaceholderModel")
		var boxmesh := BoxMesh.new()
		boxmesh.size = Vector3(10, 5, 10) if kind == "headquarters" else Vector3.ONE
		boxmesh.material = material(kind + "_placeholder", Color.BLUE if kind == "headquarters" else (Color.RED if kind == "enemy" else Color.GREEN), true)
		mesh_node("Body", boxmesh, placeholder, Vector3(0, boxmesh.size.y * 0.5, 0))
		save_scene(placeholder, "res://scenes/models/" + kind + "_placeholder.tscn")
		var actor := node("Headquarters" if kind == "headquarters" else kind.capitalize())
		actor.set_script(load("res://scripts/buildings/headquarters.gd" if kind == "headquarters" else "res://scripts/units/" + kind + ".gd"))
		actor.editor_description = "Reusable gameplay scene. Visuals is the model slot; root is the ground pivot. Place instances in the world normally."
		if kind == "headquarters": actor.add_to_group("headquarters", true)
		else:
			actor.add_to_group("units", true)
			actor.set("grid_position", Vector2i(48, 29 if kind == "enemy" else 28))
			if kind == "enemy":
				actor.set("team", "enemy")
				actor.set("health", 200)
		visual_slot("res://scenes/models/" + kind + "_placeholder.tscn", actor)
		if kind != "headquarters":
			var ringmesh := TorusMesh.new()
			ringmesh.inner_radius = 0.66
			ringmesh.outer_radius = 0.75
			ringmesh.rings = 16
			ringmesh.ring_segments = 6
			ringmesh.material = material("selection_ring", Color("a8ed57"), true)
			var ring := mesh_node("SelectionRing", ringmesh, actor, Vector3(0, 0.05, 0))
			ring.visible = false
		save_scene(actor, "res://scenes/" + ("buildings" if kind == "headquarters" else "units") + "/" + kind + ".tscn")
	var rig := node("CameraRig")
	rig.set_script(load("res://scripts/camera/rts_camera.gd"))
	var yaw := node("YawPivot", rig)
	var pitch := node("PitchPivot", yaw)
	pitch.rotation_degrees = Vector3(-50, 0, 0)
	var camera := Camera3D.new()
	camera.name = "Camera"
	camera.position = Vector3(0, 0, 110)
	camera.rotation_degrees = Vector3.ZERO
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 140
	camera.far = 3000
	camera.near = 0.1
	camera.current = true
	pitch.add_child(camera)
	save_scene(rig, "res://scenes/camera/rts_camera.tscn")
	_make_hud()
	var world := node("SupplyLinesWorld")
	world.editor_description = "Main map. Open Terrain, Lighting, CameraRig or actor scenes to edit their reusable components."
	instance("res://scenes/maps/terrain.tscn", "Terrain", world)
	instance("res://scenes/maps/lighting.tscn", "Lighting", world)
	instance("res://scenes/camera/rts_camera.tscn", "CameraRig", world)
	var entities := node("Entities", world)
	var buildings := node("Buildings", entities)
	var units := node("Units", entities)
	var hq := instance("res://scenes/buildings/headquarters.tscn", "Headquarters", buildings) as Node3D
	hq.position = Vector3(-197, 0, -227)
	var infantry := instance("res://scenes/units/infantry.tscn", "Infantry", units) as Node3D
	infantry.position = Vector3(-201.5, 0, -221.5)
	var enemy := instance("res://scenes/units/enemy.tscn", "Enemy", units) as Node3D
	enemy.position = Vector3(-201.5, 0, -220.5)
	instance("res://scenes/ui/terrain_hud.tscn", "Interface", world)
	save_scene(world, "res://scenes/maps/supply_lines_world.tscn")
	print("MODULAR_SCENES_BUILT")
	quit(0)

func _make_hud() -> void:
	var hud := CanvasLayer.new()
	hud.name = "TerrainHUD"
	hud.set_script(load("res://scripts/ui/terrain_hud.gd"))
	var panel := PanelContainer.new()
	panel.name = "Legend"
	panel.position = Vector2(16, 16)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.09, 0.1, 0.9)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel", style)
	hud.add_child(panel)
	var vbox := VBoxContainer.new()
	vbox.name = "Contents"
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(vbox)
	var title := Label.new()
	title.text = "SUPPLY LINES · TERRAIN"
	vbox.add_child(title)
	var names := ["Grass", "Water", "Desert", "Forest", "Mountains", "Ore deposit (unassigned)"]
	var colors := [Color("587039"), Color("3187a0"), Color("caaa68"), Color("4b833d"), Color("888d87"), Color("b26740")]
	for i in range(6):
		var row := HBoxContainer.new()
		row.name = names[i].split(" ")[0]
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var swatch := ColorRect.new()
		swatch.color = colors[i]
		swatch.custom_minimum_size = Vector2(12, 12)
		swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(swatch)
		var label := Label.new()
		label.text = names[i]
		label.add_theme_font_size_override("font_size", 14)
		row.add_child(label)
		vbox.add_child(row)
	var info := Label.new()
	info.name = "TerrainInfo"
	info.text = "Point at the map to inspect terrain"
	info.add_theme_font_size_override("font_size", 13)
	vbox.add_child(info)
	var help := Label.new()
	help.text = "M: whole map   F: HQ\nArrows / screen edges: pan · Wheel: zoom"
	help.add_theme_font_size_override("font_size", 12)
	vbox.add_child(help)
	save_scene(hud, "res://scenes/ui/terrain_hud.tscn")
