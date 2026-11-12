extends "res://scripts/components/burst_effect.gd"
## A death authored on stand-ins, for models whose own GLB cannot carry it: the Depot and the Depot Truck
## (docs/DEPOT_MODEL.md), whose files hold clips assembled from several Blender files. Added to the model
## root when it dies. Every Drive_<part> node in the effect's Model is keyed in its parent's space, nested
## as the parts are, so each frame its transform is copied onto the model's part of that name. Drive_Scorch
## carries how burnt the model looks in its keyed scale. When the clip ends the whole model goes.
## Darkens the model; its alpha follows Drive_Scorch.
@export var scorch_material: StandardMaterial3D
## Parts left where they are although they have a stand-in (the Depot's tractor may be away building a
## truck); parts under them still follow theirs.
@export var held_parts: PackedStringArray = []
## Where the model's parts are, from the model root (its imported GLB), so parts of the same name elsewhere
## in the model (the Depot's truck being built) are left alone.
@export var parts_path := NodePath(".")
@onready var rig: Node3D = get_parent()
var _pairs: Array = []
var _scorch: StandardMaterial3D
var _drive_scorch: Node3D
func _ready() -> void:
	var model := get_node("Model")
	_drive_scorch = model.get_node_or_null("Drive_Scorch")
	for drive in model.find_children("Drive_*","Node3D",true,false):
		if drive == _drive_scorch: continue
		var part_name := String(drive.name).trim_prefix("Drive_")
		if held_parts.has(part_name): continue
		var part := _find_part(part_name)
		if part != null: _pairs.append([drive,part])
	if scorch_material != null:
		_scorch = scorch_material.duplicate()
		for node in rig.find_children("*","MeshInstance3D",true,false):
			if not is_ancestor_of(node): (node as MeshInstance3D).material_overlay = _scorch
	player.animation_finished.connect(func(_name: StringName) -> void: rig.queue_free())
	super()
## The model's own part of that name, not one of this effect's.
func _find_part(part_name: String) -> Node3D:
	for node in rig.get_node(parts_path).find_children(part_name,"Node3D",true,false):
		if not is_ancestor_of(node) and node != self: return node
	return null
## Stand-ins that found their part, as [stand-in, part] pairs.
func driven_parts() -> Array:
	return _pairs
func _process(delta: float) -> void:
	super(delta)
	for pair in _pairs: (pair[1] as Node3D).transform = (pair[0] as Node3D).transform
	if _scorch != null and _drive_scorch != null: _scorch.albedo_color.a = clampf(_drive_scorch.scale.x,0.0,1.0)
