extends Node3D
## The Scout's shotgun shot (docs/SCOUT_MODEL.md): a flash cone at the muzzle that shrinks away, and the scene's
## Pellet meshes spraying out in a spread toward the aim point. Same configure() as tracer.gd, so
## skirmish.show_shot() can hand it out. Damage lands when the shot is fired; this is only what the player sees.
@export_range(5,200,1) var speed := 70.0
## Each pellet leaves up to this far off the aim line, across and up or down at half that.
@export_range(0,30,0.5) var spread_degrees := 7.0
@export_range(0.02,1,0.01) var cone_seconds := 0.12
@export var player_material: Material
@export var enemy_material: Material
var _pellets: Array[Node3D] = []
var _directions: Array[Vector3] = []
var _reach: Array[float] = []
var _flown := 0.0
var _age := 0.0
@onready var _cone: Node3D = $Cone
func configure(start: Vector3, end: Vector3, team: String) -> void:
	global_position = start
	var path := end-start
	var span := path.length()
	if span > 0.001: look_at(end,Vector3.FORWARD if absf(path.y/span) > 0.99 else Vector3.UP)
	var material := player_material if team == "player" else enemy_material
	var spread := deg_to_rad(spread_degrees)
	for node in get_children():
		if not node.name.begins_with("Pellet"): continue
		var direction := (Basis(Vector3.UP,randf_range(-spread,spread))*Basis(Vector3.RIGHT,randf_range(-spread,spread)*0.5)*Vector3.FORWARD).normalized()
		_pellets.append(node)
		_directions.append(direction)
		_reach.append(maxf(span*randf_range(0.85,1.1),0.5))
		node.basis = Basis.looking_at(direction)
		node.position = Vector3.ZERO
		if material: node.material_override = material
func _process(delta: float) -> void:
	_age += delta
	_flown += speed*delta
	var fade := clampf(_age/cone_seconds,0.0,1.0)
	_cone.scale = Vector3.ONE*maxf(1.0-fade,0.001)
	_cone.visible = fade < 1.0
	var flying := false
	for i in _pellets.size():
		var out := _flown < _reach[i]
		_pellets[i].visible = out
		if out:
			_pellets[i].position = _directions[i]*_flown
			flying = true
	if not flying and fade >= 1.0: queue_free()
