extends "res://scripts/components/character_animator.gd"
## Drives the Forester Maiden GLB inside Supply Lines: strips baked glTF scale keys on
## replaceable KIT meshes so outfit/tool visibility matches gathering, carrying, and constructing.

const KIT := [&"Kerchief", &"Sunhat", &"WoodcuttingAxe", &"FarmingTool", &"MaterialLoad", &"BuildingHammer"]
const WORK_CLIPS := [&"Walk", &"Chop", &"Gather", &"Carry", &"Build", &"Till"]
static var _clean_libraries: Dictionary = {}

var _kit_meshes: Dictionary = {}

func _ready() -> void:
	super._ready()
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

func _owner_unit() -> Node:
	var parent := get_parent()
	return parent.get_parent() if parent != null else null

func _is_carrying() -> bool:
	var unit := _owner_unit()
	if unit == null: return false
	var cargo = unit.get("cargo")
	return cargo is int and cargo > 0

func _is_constructing() -> bool:
	var unit := _owner_unit()
	if unit == null: return false
	return str(unit.get("order")) == "construct"

func _clip_for(kind: StringName) -> StringName:
	match kind:
		&"run": return &"Carry" if _is_carrying() else run_clip
		&"work": return &"Build" if _is_constructing() else work_clip
	return idle_clip

func _process(delta: float) -> void:
	super._process(delta)
	_update_kit(motion())

func _update_kit(kind: StringName) -> void:
	var loaded := _is_carrying()
	var building := _is_constructing() and kind == &"work"
	for key: StringName in _kit_meshes:
		var mesh: MeshInstance3D = _kit_meshes[key]
		if not is_instance_valid(mesh): continue
		mesh.scale = Vector3.ONE
		match key:
			&"Kerchief": mesh.visible = true
			&"Sunhat": mesh.visible = false
			&"FarmingTool": mesh.visible = false
			&"MaterialLoad": mesh.visible = loaded
			&"BuildingHammer": mesh.visible = building
			&"WoodcuttingAxe": mesh.visible = not (loaded or building)
