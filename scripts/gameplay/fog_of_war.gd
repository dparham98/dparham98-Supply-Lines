extends Node3D
## Fog of war (docs/FOG_OF_WAR.md). Each team sees round its own units and buildings. The map itself is always
## drawn, dimmed outside the viewer's sight (`Overlay`, assets/shaders/fog_of_war.gdshader, and the minimap); the
## other side's units, buildings, crates, track and shots show only inside it. What a team has ever seen is kept
## too (`explored_by`), for the enemy player's memory.
## Vision cells, in metres: the map's 500 m are 250 cells across.
@export_range(0.5,10,0.5) var cell_metres := 2.0
## Seconds between updates.
@export_range(0.05,2,0.05) var interval := 0.2
## Sight round units with no vision of their own (trucks, trains), Depots, other buildings and build sites.
@export_range(0,200,1) var unit_vision := 20.0
@export_range(0,200,1) var depot_vision := 36.0
@export_range(0,200,1) var building_vision := 24.0
@export_range(0,200,1) var site_vision := 12.0
## The side whose view is drawn. Any other name (a spectator, docs/MAIN_MENU.md) sees everything.
@export var viewer := "player"
const TEAMS := ["player","enemy"]
const HIDDEN_GROUPS := ["units","selectable_buildings","supply_crates","construction_plans","rails"]
var _size := Vector2i.ZERO
var _origin := Vector2.ZERO
## Per team: an RGBA8 image whose alpha is 1 in fog and 0 in sight, and an L8 image of everything ever seen.
var _shade := {}
var _explored := {}
var _texture: ImageTexture
## No fog anywhere, for a viewer who is on neither side.
var _clear: Image
var _left := 0.0
@onready var ground = get_tree().get_first_node_in_group("terrain_grid")
@onready var overlay: MeshInstance3D = $Overlay
func _ready() -> void:
	add_to_group("fog_of_war")
	var metres: Vector2 = Vector2(ground.grid_size)*ground.tile_size
	_size = Vector2i(ceili(metres.x/cell_metres),ceili(metres.y/cell_metres))
	var corner: Vector3 = ground.to_global(Vector3(-metres.x*0.5,0,-metres.y*0.5))
	_origin = Vector2(corner.x,corner.z)
	for team in TEAMS:
		_shade[team] = Image.create(_size.x,_size.y,false,Image.FORMAT_RGBA8)
		_explored[team] = Image.create(_size.x,_size.y,false,Image.FORMAT_L8)
	_clear = Image.create(_size.x,_size.y,false,Image.FORMAT_RGBA8)
	_clear.fill(Color(0,0,0,0))
	_texture = ImageTexture.create_from_image(_shade.get(viewer,_clear))
	var material := overlay.material_override as ShaderMaterial
	material.set_shader_parameter("shade",_texture)
	material.set_shader_parameter("map_rect",Vector4(_origin.x,_origin.y,_size.x*cell_metres,_size.y*cell_metres))
	update_now()
func _process(delta: float) -> void:
	_left -= delta
	if _left > 0.0: return
	_left = interval
	update_now()
## Works out what each team sees now, then shows and hides the other side's things for the viewer.
func update_now() -> void:
	for team in TEAMS: _shade[team].fill(Color(0,0,0,1))
	for group in ["units","selectable_buildings","construction_plans"]:
		for node in get_tree().get_nodes_in_group(group):
			var team = node.get("team")
			if not team in TEAMS or node.is_queued_for_deletion(): continue
			if node.get("health") != null and node.health <= 0: continue
			_stamp(team,node.global_position,sight(node))
	_texture.update(_shade.get(viewer,_clear))
	for group in HIDDEN_GROUPS:
		for node in get_tree().get_nodes_in_group(group):
			var team = _team_of(node)
			if team == null or team == viewer or team == "neutral": continue
			node.visible = visible_to(viewer,node.global_position)
## How far `node` sees, in metres.
func sight(node: Node3D) -> float:
	if node.is_in_group("construction_plans"): return site_vision
	if node.is_in_group("depots"): return depot_vision
	if node.is_in_group("selectable_buildings"): return building_vision
	var own = node.get("vision")
	return own if own is float and own > 0.0 else unit_vision
func _team_of(node: Node):
	if node.is_in_group("rails"):
		var depot = node.get("assigned_depot")
		return depot.team if is_instance_valid(depot) else null
	return node.get("team")
func _cell(point: Vector3) -> Vector2i:
	return Vector2i(floori((point.x-_origin.x)/cell_metres),floori((point.z-_origin.y)/cell_metres))
## Clears the fog in a disc of `radius` metres round `point`, row by row.
func _stamp(team: String, point: Vector3, radius: float) -> void:
	var centre := _cell(point)
	var cells := radius/cell_metres
	var rows := int(cells)
	var shade: Image = _shade[team]
	var explored: Image = _explored[team]
	for dy in range(-rows,rows+1):
		var half := int(sqrt(maxf(0.0,cells*cells-dy*dy)))
		var row := Rect2i(centre.x-half,centre.y+dy,half*2+1,1)
		shade.fill_rect(row,Color(0,0,0,0))
		explored.fill_rect(row,Color.WHITE)
func _inside(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < _size.x and cell.y < _size.y
## Whether `team` sees `point` now.
func visible_to(team: String, point: Vector3) -> bool:
	if not _shade.has(team): return true
	var cell := _cell(point)
	return _inside(cell) and _shade[team].get_pixelv(cell).a < 0.5
## Whether `team` has ever seen `point`.
func explored_by(team: String, point: Vector3) -> bool:
	if not _explored.has(team): return true
	var cell := _cell(point)
	return _inside(cell) and _explored[team].get_pixelv(cell).r > 0.5
## Whether the viewer may see `node`: their own and neutral things always, the other side's inside sight.
func shows(node: Node3D) -> bool:
	var team = _team_of(node)
	return team == null or team == viewer or team == "neutral" or visible_to(viewer,node.global_position)
## The viewer's fog, for the minimap: alpha 1 in fog, 0 in sight.
func shade_texture() -> Texture2D: return _texture
## The fog's first corner and size, in world space (y is 0).
func map_corner() -> Vector3: return Vector3(_origin.x,0,_origin.y)
func map_size() -> Vector3: return Vector3(_size.x*cell_metres,0,_size.y*cell_metres)
