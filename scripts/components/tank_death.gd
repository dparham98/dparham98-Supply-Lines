extends "res://scripts/components/burst_effect.gd"
## One of the Tank's death effects (scenes/models/tank_death_*.tscn), added to the model root when the
## tank dies. tank.glb cannot carry clips, since re-exporting it would break the track shader's vertex
## order, so its motion is authored in the effect file on stand-in nodes (Drive_Hull, Drive_Turret,
## Drive_Mount) and copied onto the real ones each frame. Two more stand-ins carry numbers in their
## keyed scale: Drive_Scorch is how burnt the tank looks, and Drive_Hide drops below one half at the
## moment hide_parts come off.
## Darkens the whole tank; its alpha follows Drive_Scorch.
@export var scorch_material: StandardMaterial3D
## Parts of the real model that break away during this death, relative to the model root.
@export var hide_parts: Array[NodePath] = []
## Seconds over which the turret lets go of where it was aiming and takes the authored pose. Zero keeps the aim.
@export var turret_release := Vector2.ZERO
@onready var rig: Node3D = get_parent()
@onready var _hull: Node3D = rig.get_node(rig.HULL.trim_suffix("/"))
@onready var _turret: Node3D = rig.turret
@onready var _mount: Node3D = rig.get_node(rig.HULL+"Tank_Turret/Barrel_Mount")
@onready var _drive_hull: Node3D = get_node("Model/Drive_Hull")
@onready var _drive_turret: Node3D = get_node("Model/Drive_Hull/Drive_Turret")
@onready var _drive_mount: Node3D = get_node("Model/Drive_Hull/Drive_Turret/Drive_Mount")
@onready var _drive_scorch: Node3D = get_node("Model/Drive_Scorch")
@onready var _drive_hide: Node3D = get_node_or_null("Model/Drive_Hide")
var _aim_yaw := 0.0
var _scorch: StandardMaterial3D
var _neon: Array[Node3D] = []
func _ready() -> void:
	_aim_yaw = rig.turret_yaw()
	_scorch = scorch_material.duplicate()
	for node in rig.find_children("*","MeshInstance3D",true,false):
		if not is_ancestor_of(node) and not rig.muzzle.is_ancestor_of(node):
			(node as MeshInstance3D).material_overlay = _scorch
			if node.name.begins_with("Neon_"): _neon.append(node)
	player.animation_finished.connect(func(_name: StringName) -> void: rig.queue_free())
	super()
func _process(delta: float) -> void:
	super(delta)
	if not player.is_playing(): return
	_hull.transform = _drive_hull.transform
	_mount.transform = _drive_mount.transform
	var keep := 1.0
	if turret_release != Vector2.ZERO: keep -= smoothstep(turret_release.x,turret_release.y,player.current_animation_position)
	_turret.transform = Transform3D(_drive_turret.transform.basis*Basis(Vector3.UP,_aim_yaw*keep),_drive_turret.transform.origin)
	_scorch.albedo_color.a = clampf(_drive_scorch.scale.x,0.0,1.0)
	# The neon glows brighter than the scorch can darken, so it goes out once the tank is properly burnt.
	for node in _neon: node.visible = _scorch.albedo_color.a < 0.5
	if _drive_hide != null:
		for path in hide_parts: (rig.get_node(path) as Node3D).visible = _drive_hide.scale.x > 0.5
