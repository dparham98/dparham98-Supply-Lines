extends "res://scripts/gameplay/resource_node.gd"
## A Knights Farm (docs/KNIGHTS_ECONOMY.md). One Forester Maiden tills it and carries the Food to a Keep, as a
## worker mines: each work beat gives `farm_food_per_beat` Food, and it never runs out. A second worker is refused.
## It is a flat field: any unit walks over it and nothing is built on it. While an enemy ground unit stands on it,
## it yields nothing. With `farmers_permanent` its worker is its Farmer for good (unit_agent.gd).
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
## An enemy ground unit stands on the field, so it yields nothing (checked every `farm_raid_check_seconds`).
var raided := false
var _raid_wait := 0.0
var _rect := Rect2i()
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
			ground.set_field(cell,_key(),true)
	_rect = Rect2i(start,size)
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
	if not is_instance_valid(worker) or worker.health <= 0 or worker.is_queued_for_deletion(): return false
	# A Farmer stays this Farm's worker on its way to the Keep and back.
	if RULES.farmers_permanent and worker.get("farm") == self: return true
	return worker.get("order") == "gather" and worker.get("source") == self
## Takes `unit` as its worker; false when another worker is on it.
func take_worker(unit: Node3D) -> bool:
	if not accepts(unit): return false
	worker = unit
	return true
func can_extract(asking: String) -> bool:
	return asking == team and health > 0 and not is_queued_for_deletion() and not raided
## The field's cells; its Farmer tills it from the near edge (unit_agent.gd).
func field_rect() -> Rect2i:
	return _rect
## Whether `point` lies on the field.
func on_field(point: Vector3) -> bool:
	var cell = ground.get_tile_at_position(point)
	return cell != null and _rect.has_point(cell)
## Whether an enemy ground unit stands on the field now.
func enemy_on_field() -> bool:
	for unit in get_tree().get_nodes_in_group("units"):
		if unit.get("team") == team or unit.get("health") == null or unit.health <= 0 or unit.is_queued_for_deletion(): continue
		if unit.has_method("mobility_layer") and unit.mobility_layer() == MobilityRules.Layer.AIR: continue
		if on_field(unit.global_position): return true
	return false
func extract(requested: int, asking := "") -> int:
	if not can_extract(asking): return 0
	_work_left = 1.5
	return mini(maxi(0,requested),RULES.farm_food_per_beat)
func update_label() -> void:
	if not has_node("Label"): return
	var status := "enemy on the field: no Food" if raided else ("tilled" if worker_busy() else "no worker")
	$Label.text = "FARM · %s · %d/%d HP" % [status,health,max_health]
func _process(delta: float) -> void:
	_work_left = maxf(0.0,_work_left-delta)
	_raid_wait -= delta
	if _raid_wait <= 0.0:
		_raid_wait = RULES.farm_raid_check_seconds
		raided = enemy_on_field()
	update_label()
	var model := get_node_or_null("Visuals/Model")
	# The vineyard's irrigation carriages water the rows while its Farmer works it (scenes/models/farm_model.tscn).
	if model != null and model.has_method("show_running"): model.show_running(_work_left > 0.0)
func take_damage(hit: int) -> void:
	health = maxi(0,health-maxi(0,hit))
	update_label()
	if health <= 0:
		set_process(false)
		for group in get_groups(): remove_from_group(group)
		_leave_wreck()
		queue_free()
## The model stays behind to play its Die clip and death effect, as a Generator's does.
func _leave_wreck() -> void:
	var model := get_node_or_null("Visuals/Model")
	if model == null or not model.has_method("has_death_clip") or not model.has_death_clip() or get_parent() == null: return
	model.reparent(get_parent())
	model.play_death()
func _exit_tree() -> void:
	if not is_instance_valid(ground): return
	for cell in cells: ground.set_field(cell,_key(),false)
