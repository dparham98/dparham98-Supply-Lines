extends SceneTree
## Folds a unit model's static pieces into the moving part each rides on, and saves the result as a model scene of
## its own (docs/PERFORMANCE.md, Merged models). Every MeshInstance3D is a transform the engine updates each frame the
## unit moves and at least one draw call per pass, so a model made of 59 pieces costs far more than one of 15.
##
## For each entry in MODELS:
## - `keep` names the pieces that must stay their own nodes: the ones a script or a death clip moves, hides, recolours
##   or looks up by name. Everything else that is a MeshInstance3D with no children of its own is folded into its
##   nearest kept MeshInstance3D ancestor, one surface per material (so team paint, found by material name, still works).
## - Effects scenes inside the model (muzzle flashes) stay instances and are left alone.
## - The merged meshes are saved beside the GLB in `assets/models/units/merged/`, the scene at `out`.
## The source scene, the GLB and the Blender files are not changed. Run it again whenever the model changes:
##   Godot --headless --path . --script res://scripts/tools/merge_model_parts.gd [-- <id> ...]
const MODELS := {
	"tank": {
		"source": "res://scenes/models/tank_model.tscn",
		"out": "res://scenes/models/tank_model_merged.tscn",
		"keep": ["Tank_Hull","Tank_Turret","Barrel_Mount","Tank_Barrel","Turret_Hatch","Aux_Turret","Hull_Driver_Hatch",
			"Drive_Sprocket_L","Drive_Sprocket_R","Idler_Wheel_L","Idler_Wheel_R",
			"Track_Links_L","Track_Links_R","Road_Wheels_L","Road_Wheels_R","Return_Rollers_L","Return_Rollers_R",
			"Neon_Headlamp_L","Neon_Headlamp_R","Neon_Sensor_Lens"],
	},
}
const MESH_DIR := "res://assets/models/units/merged/"

func _initialize() -> void: call_deferred("run")

func run() -> void:
	var ids: Array = OS.get_cmdline_user_args()
	if ids.is_empty(): ids = MODELS.keys()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(MESH_DIR))
	for id in ids:
		if not MODELS.has(id): push_error("No merge entry for %s" % id); quit(1); return
		var err := merge(id,MODELS[id])
		if err != OK: push_error("Merging %s failed: %s" % [id,error_string(err)]); quit(1); return
	print("MERGE_MODEL_PARTS_DONE")
	quit()

## Inside an effects scene (a node instanced from another scene, below the model's own GLB).
func _in_effect(model: Node, node: Node) -> bool:
	var at := node
	while at != model and at != null:
		if not at.scene_file_path.is_empty() and not at.scene_file_path.ends_with(".glb"): return true
		at = at.get_parent()
	return false

func merge(id: String, entry: Dictionary) -> Error:
	var model: Node3D = load(entry.source).instantiate()
	root.add_child(model)
	var keep: Array = entry.keep
	var folded := 0
	var groups := {}  # kept MeshInstance3D -> Array of [MeshInstance3D, Transform3D relative to it]
	for node in model.find_children("*","MeshInstance3D",true,false):
		if _in_effect(model,node): continue
		if keep.has(String(node.name)):
			if not groups.has(node): groups[node] = [[node,Transform3D.IDENTITY]]
			continue
		if node.get_child_count() > 0: push_error("%s has children and is not kept" % node.name); return ERR_INVALID_DATA
		var target: Node = node.get_parent()
		while target != model and not (target is MeshInstance3D and keep.has(String(target.name))): target = target.get_parent()
		if target == model: push_error("%s has no kept piece to fold into" % node.name); return ERR_INVALID_DATA
		if not groups.has(target): groups[target] = [[target,Transform3D.IDENTITY]]
		groups[target].append([node,(target as Node3D).global_transform.affine_inverse()*(node as Node3D).global_transform])
	for target in groups:
		var parts: Array = groups[target]
		if parts.size() == 1: continue
		var by_material := {}  # Material -> SurfaceTool
		var order: Array = []
		for part in parts:
			var piece: MeshInstance3D = part[0]
			if piece.mesh == null: continue
			for s in piece.mesh.get_surface_count():
				var material: Material = piece.get_active_material(s)
				if not by_material.has(material):
					var tool := SurfaceTool.new()
					by_material[material] = tool
					order.append(material)
				(by_material[material] as SurfaceTool).append_from(piece.mesh,s,part[1])
		var mesh := ArrayMesh.new()
		for material in order:
			var tool: SurfaceTool = by_material[material]
			tool.set_material(material)
			tool.commit(mesh)
		var path := MESH_DIR+"%s_%s.res" % [id,String(target.name).to_lower()]
		var err := ResourceSaver.save(mesh,path)
		if err != OK: return err
		mesh.take_over_path(path)
		(target as MeshInstance3D).mesh = mesh
		(target as MeshInstance3D).material_override = null
		for part in parts:
			if part[0] != target:
				part[0].get_parent().remove_child(part[0])
				part[0].free()
				folded += 1
	# Pieces kept as they were keep their meshes in files too, so the scene stays small text.
	for node in model.find_children("*","MeshInstance3D",true,false):
		if _in_effect(model,node) or node.mesh == null: continue
		var own: String = node.mesh.resource_path
		if not own.is_empty() and not own.contains("::"): continue
		var path := MESH_DIR+"%s_%s.res" % [id,String(node.name).to_lower()]
		var err := ResourceSaver.save(node.mesh,path)
		if err != OK: return err
		node.mesh.take_over_path(path)
	# Everything in the model becomes the new scene's own, except inside the effects scenes.
	for node in model.find_children("*","",true,false):
		if _in_effect(model,node) and not (not node.scene_file_path.is_empty() and not node.scene_file_path.ends_with(".glb")): continue
		node.owner = model
		if node.scene_file_path.ends_with(".glb"): node.scene_file_path = ""
	var packed := PackedScene.new()
	var err := packed.pack(model)
	if err != OK: return err
	err = ResourceSaver.save(packed,entry.out)
	var meshes := model.find_children("*","MeshInstance3D",true,false).filter(func(m): return not _in_effect(model,m))
	var surfaces := 0
	for m in meshes: surfaces += m.mesh.get_surface_count() if m.mesh else 0
	print("%s: folded %d pieces; %d model pieces, %d surfaces -> %s" % [id,folded,meshes.size(),surfaces,entry.out])
	model.free()
	return err
