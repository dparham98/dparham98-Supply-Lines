extends "res://scripts/components/character_animator.gd"
## The assignment selects the outfit. Activity and cargo select the tool or load.

const KIT := [&"Kerchief", &"Sunhat", &"WoodcuttingAxe", &"FarmingTool", &"MaterialLoad", &"FoodBasket", &"BuildingHammer"]
const WORK_CLIPS := [&"Walk", &"Chop", &"Gather", &"Carry", &"CarryFood", &"Build", &"Till"]
static var _clean_libraries: Dictionary = {}

var _kit_meshes: Dictionary = {}
var _worker: Node

func _ready() -> void:
	super._ready()
	var unit := get_parent().get_parent() if get_parent() != null else null
	if unit != null and unit.has_method("command_gather"):
		_worker = unit
	for key: StringName in KIT:
		var mesh := find_child(String(key), true, false) as MeshInstance3D
		if mesh != null:
			_kit_meshes[key] = mesh
	_install_clean_clips()
	_update_kit(&"idle")

func _install_clean_clips() -> void:
	if player == null: return
	var source := player.get_animation_library(&"")
	if source == null: return
	if not _clean_libraries.has(source):
		var clean := AnimationLibrary.new()
		for clip: StringName in WORK_CLIPS:
			if not source.has_animation(clip): continue
			var anim := source.get_animation(clip).duplicate() as Animation
			for i in range(anim.get_track_count() - 1, -1, -1):
				var path := anim.track_get_path(i)
				if anim.track_get_type(i) == Animation.TYPE_SCALE_3D and path.get_name_count() > 0 and path.get_name(path.get_name_count() - 1) in KIT:
					anim.remove_track(i)
			anim.loop_mode = Animation.LOOP_LINEAR
			clean.add_animation(clip, anim)
		_clean_libraries[source] = clean
	player.remove_animation_library(&"")
	player.add_animation_library(&"", _clean_libraries[source])

func _farm_assigned() -> bool:
	if _worker == null or _worker.order not in ["gather", "return"]: return false
	var field = _worker.source
	return is_instance_valid(field) and field.is_in_group("farms") and not field.is_queued_for_deletion()

func _load_clip() -> StringName:
	return &"CarryFood" if _worker.cargo_kind == &"food" else &"Carry"

func _working_clip() -> StringName:
	if _worker == null: return work_clip
	if _worker.state.begins_with("Felling"): return &"Chop"
	if _worker.order in ["construct", "repair"]: return &"Build"
	if _worker.order == "gather" and is_instance_valid(_worker.source):
		var source: Node = _worker.source
		if source.is_in_group("farms"): return &"Till"
		if source.is_in_group("material_piles") or source.resource_kind != &"wood": return &"Gather"
	return work_clip

func _shows_load(kind: StringName) -> bool:
	if _worker == null or _worker.cargo <= 0: return false
	# The worker finishes gathering before taking a load into her arms.
	if _worker.order == "gather" and is_instance_valid(_worker.source) and _worker.cargo_kind == _worker.source.resource_kind: return false
	if kind == &"work" and (_worker.order in ["construct", "repair", "fell"] or _worker.state.begins_with("Felling")): return false
	return true

func _clip_for(kind: StringName) -> StringName:
	if _shows_load(kind): return _load_clip()
	if kind == &"work": return _working_clip()
	return super._clip_for(kind)

func _pace(kind: StringName, clip: StringName) -> float:
	if clip in [&"Carry", &"CarryFood"]:
		return clampf(_value / 0.84, 0.5, 2.0) if kind == &"run" else 0.0
	if clip in [&"Till", &"Gather"] and _value > 0.0:
		return player.get_animation(clip).length / _value
	return super._pace(kind, clip)

func _process(delta: float) -> void:
	super._process(delta)
	_update_kit(motion())

func _update_kit(kind: StringName) -> void:
	var farm := _farm_assigned()
	var loaded := _shows_load(kind)
	var food: bool = loaded and _worker.cargo_kind == &"food"
	var activity := _working_clip() if kind == &"work" else &""
	var building := activity == &"Build"
	for key: StringName in _kit_meshes:
		var mesh: MeshInstance3D = _kit_meshes[key]
		mesh.scale = Vector3.ONE
		match key:
			&"Kerchief": mesh.visible = not farm
			&"Sunhat": mesh.visible = farm
			&"FoodBasket": mesh.visible = food
			&"MaterialLoad": mesh.visible = loaded and not food
			&"BuildingHammer": mesh.visible = building
			&"FarmingTool": mesh.visible = farm and not loaded and not building
			&"WoodcuttingAxe": mesh.visible = not farm and not loaded and not building and activity != &"Gather"
