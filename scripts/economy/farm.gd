extends "res://scripts/gameplay/resource_node.gd"
## A Knights Farm (docs/KNIGHTS_ECONOMY.md). One Forester Maiden tills it and carries the Food to a Keep, as a
## worker mines: each work beat gives `farm_food_per_beat` Food, and it never runs out. A second worker is refused.
const RULES := preload("res://assets/economy/knights_rules.tres")
@export var team := "player"
var health := 300
var max_health: int:
	get: return RULES.farm_health
var assigned_depot: Node3D
var cells: Array[Vector2i] = []
## The Forester working it, if any.
var worker: Node3D
var _work_left := 0.0
@onready var ground = get_tree().get_first_node_in_group("terrain_grid")
func _ready() -> void:
	resource_kind = &"food"; resource_name = "Farm"
	amount = 1000000
	health = max_health
	var size: Vector2i = RULES.farm_footprint
	var centre = ground.get_tile_at_position(global_position)
	var start: Vector2i = centre-size/2 if centre != null else Vector2i.ZERO
	global_position = ground.tile_to_world(start)+Vector3(size.x*0.5-0.5,0,size.y*0.5-0.5)
	for z in range(start.y,start.y+size.y):
		for x in range(start.x,start.x+size.x):
			var cell := Vector2i(x,z)
			cells.append(cell)
			ground.set_tile_feature(cell,"occupied_by",_key())
	add_to_group("farms"); add_to_group("selectable_buildings")
	super._ready()
	remove_from_group("iron_deposits")
	if not is_in_group("resources"): add_to_group("resources")
	preload("res://scripts/components/team_paint.gd").apply(get_node_or_null("Visuals/Model"),team)
func _key() -> String: return "farm_%s" % get_instance_id()
## Whether `unit` may work it: the side's own worker, and no other worker already on it.
func accepts(unit: Node3D) -> bool:
	if not is_instance_valid(unit) or unit.get("team") != team: return false
	return not worker_busy() or worker == unit
func worker_busy() -> bool:
	return is_instance_valid(worker) and worker.health > 0 and worker.get("order") == "gather" and worker.get("source") == self
## Takes `unit` as its worker; false when another worker is on it.
func take_worker(unit: Node3D) -> bool:
	if not accepts(unit): return false
	worker = unit
	return true
func can_extract(asking: String) -> bool:
	return asking == team and health > 0 and not is_queued_for_deletion()
func extract(requested: int, asking := "") -> int:
	if not can_extract(asking): return 0
	_work_left = 1.5
	return mini(maxi(0,requested),RULES.farm_food_per_beat)
func update_label() -> void:
	if not has_node("Label"): return
	$Label.text = "FARM · %s · %d/%d HP" % ["tilled" if worker_busy() else "no worker",health,max_health]
func _process(delta: float) -> void:
	_work_left = maxf(0.0,_work_left-delta)
	update_label()
	var model := get_node_or_null("Visuals/Model")
	if model != null and model.has_method("show_working"): model.show_working(_work_left > 0.0)
func take_damage(hit: int) -> void:
	health = maxi(0,health-maxi(0,hit))
	update_label()
	if health <= 0:
		set_process(false)
		for group in get_groups(): remove_from_group(group)
		queue_free()
func _exit_tree() -> void:
	if not is_instance_valid(ground): return
	for cell in cells:
		if ground.tiles[cell.y*ground.grid_size.x+cell.x].occupied_by == _key(): ground.set_tile_feature(cell,"occupied_by",null)
