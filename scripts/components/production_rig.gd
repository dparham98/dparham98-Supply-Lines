extends Node3D
## Plays a production building's authored clips: the Barracks (docs/BARRACKS_MODEL.md) and the Tank Factory
## (docs/TANK_FACTORY_MODEL.md). Idle while nothing is made, Build scrubbed by construction progress, the
## production clip following production, and Die when the building is destroyed. The rest pose is the
## finished building with its door closed and nothing being made.
@export var player_path := NodePath("Rig/AnimationPlayer")
@export var idle_clip := &"Idle"
@export var build_clip := &"Build"
## The production clip ("Print" for the Barracks, "Produce" for the Tank Factory).
@export var print_clip := &"Print"
@export var death_clip := &"Die"
## Seconds into it when the new unit reaches the door; the real unit appears outside then.
## Production time is scaled onto 0..this, and the rest of the clip (the door closing) plays at normal speed.
@export_range(0.1,10,0.05) var print_spawn_seconds := 4.0
## Spawned on this model at death (fire, smoke, scrap); built on the same timeline as the clip.
@export var death_fx_scene: PackedScene
## The Tank Factory's turntable mount (an empty in the glb). The queued unit's own model stands on it while it
## is made, so the plant builds whatever was ordered. Buildings without one (the Barracks) ignore show_unit.
@export var vehicle_node := &""
## Shader for a unit being assembled: bare primer up to a rising weld seam, nothing above it.
@export var build_material: ShaderMaterial
## Clip seconds over which the unit forms bottom-up, from the first plate to the last one merging.
@export var form_from := 0.3
@export var form_to := 2.7
## The room a unit has on the mount, in the plant's metres. Lengthwise (along the unit, gun included) it must
## stay between the back wall and the closed door; a unit longer than that is scaled down to fit while inside.
@export var room_behind := 3.3
@export var room_ahead := 2.75
## A unit no longer than this is turned side-on with the turntable so it shows broadside in the well; a longer
## one (the Tank) keeps facing the door, as it would not fit across the hall.
@export var turn_length := 2.8
## Headroom above the mount at the top of the lift before the roof deck: taller units ride lower as they rise.
@export var headroom := 1.3
## How high the lift raises the mount at the top of its travel.
@export var lift_height := 2.4
@onready var player: AnimationPlayer = get_node(player_path)
var _dying := false
var _closing := false
var _mount: Node3D
## The unit model wanted on the mount, the one standing there, and its height above the mount.
var _wanted_unit: PackedScene
var _unit_scene: PackedScene
var unit_model: Node3D
var _unit_height := 1.0
var _unit_material: ShaderMaterial
var _unit_turns := true
var _mount_rest: Transform3D
func _ready() -> void:
	player.animation_finished.connect(_finished)
	if vehicle_node != &"": _mount = find_child(String(vehicle_node),true,false)
	if _mount != null: _mount_rest = _mount.transform
	show_idle()
func show_idle() -> void:
	if _dying or _closing: return
	_clear_unit()
	if player.is_playing() and player.assigned_animation == idle_clip: return
	player.play(idle_clip)
## Construction progress 0..1: from bare ground to the finished building.
func show_construction(fraction: float) -> void:
	if _dying: return
	_pose(build_clip,clampf(fraction,0.0,1.0)*player.get_animation(build_clip).length)
## Production progress 0..1 of the unit being made. At 1 it waits at the open door.
func show_print(fraction: float) -> void:
	if _dying or _closing: return
	var seconds := clampf(fraction,0.0,1.0)*print_spawn_seconds
	_pose(print_clip,seconds)
	if _wanted_unit != _unit_scene: _stand_unit(_wanted_unit)
	_place_unit()
	_form_unit(clampf((seconds-form_from)/(form_to-form_from),0.0,1.0))
## The model of the unit being made next (its scene's Visuals model). It takes the mount at the next show_print.
func show_unit(model_scene: PackedScene) -> void:
	_wanted_unit = model_scene
## The new unit has left: the door closes behind it, then the building idles again.
func unit_left() -> void:
	if _dying: return
	_clear_unit()
	_closing = true
	player.play(print_clip)
	player.seek(print_spawn_seconds,true)
func closing() -> bool:
	return _closing
func has_death_clip() -> bool:
	return player != null and player.has_animation(death_clip)
func dying() -> bool:
	return _dying
## The wreck plays out, sinks out of sight and removes itself.
func play_death() -> void:
	_dying = true
	_closing = false
	_clear_unit()
	player.play(death_clip)
	player.seek(0.0,true)
	if death_fx_scene: add_child(death_fx_scene.instantiate())
func _finished(clip: StringName) -> void:
	if clip == death_clip: queue_free()
	elif clip == print_clip and _closing:
		_closing = false
		show_idle()
func _pose(clip: StringName, seconds: float) -> void:
	if player.is_playing(): player.pause()
	if player.assigned_animation != clip: player.assigned_animation = clip
	player.seek(seconds,true)
## Stands a fresh copy of this unit model on the mount, facing the door. It is scenery only: its own scripts and
## animation stay still.
func _stand_unit(model_scene: PackedScene) -> void:
	_clear_unit()
	_unit_scene = model_scene
	if _mount == null or model_scene == null: return
	unit_model = model_scene.instantiate()
	unit_model.name = "Unit"
	unit_model.process_mode = Node.PROCESS_MODE_DISABLED
	# Unit models face -Z; the mount's front (toward the door) is +Z.
	unit_model.rotation.y = PI
	_mount.add_child(unit_model)
	# Measure it facing the door, in the mount's frame: how long (back to gun tip) and how tall it is.
	var box := AABB()
	var first := true
	for mesh in _unit_meshes():
		if not mesh.is_visible_in_tree(): continue
		var part: AABB = (unit_model.transform*unit_model.global_transform.affine_inverse()*mesh.global_transform)*mesh.get_aabb()
		box = part if first else box.merge(part)
		first = false
	var room := room_behind+room_ahead
	var fit := minf(1.0,room/maxf(box.size.z,0.01))
	unit_model.scale = Vector3.ONE*fit
	_unit_height = maxf(box.end.y*fit,0.1)
	_unit_turns = box.size.z*fit <= turn_length
	# Centred in its room lengthwise when it is long, otherwise on the mount as it stands.
	var shift := 0.0
	if box.position.z*fit < -room_behind or box.end.z*fit > room_ahead:
		shift = (room_ahead-room_behind)*0.5-(box.position.z+box.end.z)*0.5*fit
	unit_model.set_meta(&"factory_shift",shift)
	_place_unit()
	if build_material != null:
		_unit_material = build_material.duplicate()
		for mesh in _unit_meshes(): mesh.set_meta(&"factory_override",mesh.material_override)
## Keeps the unit in the hall as the lift and turntable move it: a long unit is turned back to face the door, and
## a tall one rides lower near the top of the lift.
func _place_unit() -> void:
	if unit_model == null or _mount == null: return
	var raised := clampf((_mount.position.y-_mount_rest.origin.y)/lift_height,0.0,1.0)
	var sink := maxf(0.0,_unit_height-headroom)*raised
	var yaw := 0.0 if _unit_turns else -(_mount_rest.basis.inverse()*_mount.basis).get_euler().y
	var facing := Basis(Vector3.UP,PI+yaw)
	unit_model.transform = Transform3D(facing.scaled(unit_model.scale),Basis(Vector3.UP,yaw)*Vector3(0,-sink,float(unit_model.get_meta(&"factory_shift",0.0))))
## 0 nothing yet, 1 complete: the weld seam rises up the unit, which is primer below it. Complete, it wears its
## own colours.
func _form_unit(formed: float) -> void:
	if unit_model == null or _unit_material == null: return
	var done := formed >= 1.0
	_unit_material.set_shader_parameter(&"cut_height",unit_model.global_position.y+_mount.global_basis.get_scale().y*_unit_height*formed)
	for mesh in _unit_meshes():
		mesh.material_override = mesh.get_meta(&"factory_override") if done else _unit_material
func _unit_meshes() -> Array[GeometryInstance3D]:
	var result: Array[GeometryInstance3D] = []
	if unit_model == null: return result
	for node in unit_model.find_children("*","GeometryInstance3D",true,false): result.append(node)
	return result
func _clear_unit() -> void:
	if unit_model != null:
		unit_model.queue_free()
		unit_model = null
	_unit_scene = null
## Whether the unit on the mount is still being formed (in primer, cut by the weld seam).
func unit_forming() -> bool:
	return unit_model != null and _unit_material != null and _unit_meshes().any(func(m): return m.material_override == _unit_material)
