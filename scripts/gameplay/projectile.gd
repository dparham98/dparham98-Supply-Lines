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
var _left := 0.0
func configure(start: Vector3, end: Vector3, team: String) -> void:
	var path := end-start
	var span := path.length()
	var dir := path/span if span > 0.001 else -global_transform.basis.z
	global_position = start+dir*half_length
	look_at(global_position+dir,Vector3.FORWARD if absf(dir.y) > 0.99 else Vector3.UP)
	_left = maxf(span-half_length*2.0,0.0)
	_paint(player_color if team == "player" else enemy_color)
func _paint(trail: Color) -> void:
	for node in find_children("*","MeshInstance3D",true,false):
		var mesh_node := node as MeshInstance3D
		mesh_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color = trail if mesh_node.name.contains("trail") else core_color
		mesh_node.material_override = material
func _process(delta: float) -> void:
	var step := minf(speed*delta,_left)
	global_position += -global_transform.basis.z*step
	_left -= step
	if _left <= 0.0: queue_free()
