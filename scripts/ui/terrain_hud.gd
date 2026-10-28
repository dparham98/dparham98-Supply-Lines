extends CanvasLayer
@onready var terrain_label: Label = $Legend/Contents/TerrainInfo
var hover_timer := 0.0
var ground: MeshInstance3D
func _ready() -> void:
	ground = get_tree().get_first_node_in_group("terrain_grid")
func _process(delta: float) -> void:
	hover_timer += delta
	if hover_timer < 0.12 or ground == null: return
	hover_timer = 0
	var camera := get_viewport().get_camera_3d()
	if camera == null: return
	var mouse := get_viewport().get_mouse_position()
	var hit = Plane(Vector3.UP, 0).intersects_ray(camera.project_ray_origin(mouse), camera.project_ray_normal(mouse))
	if hit == null: return
	var cell = ground.get_tile_at_position(hit)
	if cell != null:
		var allowed := "buildable" if ground.is_tile_valid(cell) else "blocked / occupied"
		terrain_label.text = "%s · %s" % [ground.TERRAIN_NAMES[ground.get_terrain(cell)], allowed]
