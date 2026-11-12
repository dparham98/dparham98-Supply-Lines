extends "res://scripts/gameplay/resource_node.gd"
@export var rules: EngineeringRules
## Shared infrastructure: team does not restrict extraction, repair or explicit attack.
@export var team := "neutral"
## Seconds the pithead keeps winding after the last iron taken from it (docs/IRON_MINE_MODEL.md).
@export_range(0,10,0.1) var work_hold := 2.5
var health := 1000
var _work_left := 0.0
var _wreck: Node3D
var max_health: int:
	get: return rules.mine_health
var cells: Array[Vector2i] = []
@onready var ground = get_tree().get_first_node_in_group("terrain_grid")
func _ready() -> void:
	resource_kind = &"iron"; resource_name = "Shared iron mine"
	health = max_health
	var center = ground.get_tile_at_position(global_position)
	var start: Vector2i = center-rules.mine_footprint/2 if center != null else Vector2i(-1,-1)
	if not ground.ore_footprint_valid(start,rules.mine_footprint): push_error("Mine requires an empty iron-deposit footprint"); queue_free(); return
	global_position = ground.tile_to_world(start)+Vector3(rules.mine_footprint.x*0.5-0.5,0,rules.mine_footprint.y*0.5-0.5)
	for z in range(start.y,start.y+rules.mine_footprint.y):
		for x in range(start.x,start.x+rules.mine_footprint.x):
			var cell := Vector2i(x,z)
			cells.append(cell)
			ground.set_tile_feature(cell,"occupied_by",_key())
			ground.iron_mines[cell] = self
	add_to_group("mines"); add_to_group("selectable_buildings")
	# The ore rocks drawn on and around the footprint give way to the pithead.
	if ground.has_method("cover_ore"): ground.cover_ore(_key(),cells)
	amount = reserves()
	super._ready()
func reserves() -> int:
	var total := 0
	for cell in cells: total += ground.iron_amount(cell)
	return total
func can_extract(_team: String) -> bool: return health > 0 and not is_queued_for_deletion()
func extract(requested: int, extracting_team := "") -> int:
	if not can_extract(extracting_team): return 0
	var taken := 0
	for cell in cells: taken += ground.extract_iron(cell,maxi(0,requested-taken))
	remaining = reserves()
	if taken > 0: _work_left = work_hold
	_update_model()
	update_label()
	return taken
func update_label() -> void:
	$Label.text = "SHARED MINE · iron %d · %d/%d HP" % [remaining,health,max_health]
func _process(delta: float) -> void:
	remaining = reserves(); update_label()
	_work_left = maxf(0.0,_work_left-delta)
	_update_model()
## The animated model (docs/IRON_MINE_MODEL.md) winds while Infantry mine it and goes dark once it is worked out.
func _update_model() -> void:
	var model := get_node_or_null("Visuals/Model")
	if model != null and model.has_method("show_state"): model.show_state(_work_left > 0.0 and remaining > 0,remaining <= 0)
## The model stays behind as a wreck that plays its death clip and removes itself.
func _leave_wreck() -> void:
	var model := get_node_or_null("Visuals/Model")
	if model == null or not model.has_method("has_death_clip") or not model.has_death_clip() or get_parent() == null: return
	model.reparent(get_parent())
	model.play_death()
	_wreck = model
func _key() -> String: return "mine_%s" % get_instance_id()
func take_damage(amount_: int) -> void:
	health = maxi(0,health-maxi(0,amount_))
	if health <= 0:
		set_process(false)
		for group in get_groups(): remove_from_group(group)
		_leave_wreck()
		queue_free()
func _exit_tree() -> void:
	if not is_instance_valid(ground): return
	# The ore rocks come back once the wreck has sunk away.
	if ground.has_method("uncover_ore"):
		if is_instance_valid(_wreck) and _wreck.is_inside_tree(): _wreck.tree_exited.connect(ground.uncover_ore.bind(_key()),CONNECT_ONE_SHOT)
		else: ground.uncover_ore(_key())
	for cell in cells:
		if ground.iron_mines.get(cell) == self: ground.iron_mines.erase(cell)
		if ground.tiles[cell.y*500+cell.x].occupied_by == _key(): ground.set_tile_feature(cell,"occupied_by",null)
