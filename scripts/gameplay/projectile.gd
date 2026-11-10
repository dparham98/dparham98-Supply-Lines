extends Node3D
## A shot that flies from the muzzle to its aim point, then disappears. Same configure() as tracer.gd, so
## either can be handed to skirmish.show_shot(). Damage lands when the shot is fired (CombatResolver);
## this is only what the player sees. Meshes with "trail" in their name take the team colour.
@export_range(5,200,1) var speed := 42.0
## Half the model's length: the tail starts at the muzzle and the nose stops on the target.
@export_range(0,2,0.01) var half_length := 0.33
@export var core_color := Color(1,0.95,0.78)
@export var player_color := Color(1,0.68,0.2)
@export var enemy_color := Color(1,0.2,0.15)
## Leave the body in its authored, lit material; only the trail is repainted.
@export var keep_body_material := false
## Spawned where the shot lands, leaning back toward the shooter (the scene's -Z).
@export var impact_scene: PackedScene
var _left := 0.0
var _end := Vector3.ZERO
func configure(start: Vector3, end: Vector3, team: String) -> void:
	var path := end-start
	var span := path.length()
	var dir := path/span if span > 0.001 else -global_transform.basis.z
	global_position = start+dir*half_length
	look_at(global_position+dir,Vector3.FORWARD if absf(dir.y) > 0.99 else Vector3.UP)
	_left = maxf(span-half_length*2.0,0.0)
	_end = end
	_paint(player_color if team == "player" else enemy_color)
func _paint(trail: Color) -> void:
	for node in find_children("*","MeshInstance3D",true,false):
		var mesh_node := node as MeshInstance3D
		mesh_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var is_trail := mesh_node.name.contains("trail")
		if keep_body_material and not is_trail: continue
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color = trail if is_trail else core_color
		mesh_node.material_override = material
func _process(delta: float) -> void:
	var step := minf(speed*delta,_left)
	global_position += -global_transform.basis.z*step
	_left -= step
	if _left > 0.0: return
	_land()
	queue_free()
func _land() -> void:
	if impact_scene == null: return
	var impact: Node3D = impact_scene.instantiate()
	get_parent().add_child(impact)
	impact.global_position = _end
	var back := global_transform.basis.z
	back.y = 0.0
	if back.length_squared() > 0.001: impact.look_at(_end+back,Vector3.UP)
