extends "res://scripts/gameplay/resource_node.gd"
## A Knights Farm (docs/KNIGHTS_ECONOMY.md). One Forester Maiden tills it and carries the Food to a Keep, as a
## worker mines: each work beat gives `farm_food_per_beat` Food, and it never runs out. A second worker is refused.
const RULES := preload("res://assets/economy/knights_rules.tres")
## Open work bays on the 4×4 model. Keys are standing cells relative to its
## first footprint cell; values are the target soil marks in farm-local X/Z.
const FURROWS := {
	Vector2i(4, 1): Vector2(1.60, -0.50), Vector2i(4, 2): Vector2(1.60, 0.50),
	Vector2i(-1, 2): Vector2(-1.74, 0.50), Vector2i(-1, 3): Vector2(-1.74, 1.48),
	Vector2i(1, 4): Vector2(-0.12, 1.62), Vector2i(2, 4): Vector2(0.32, 1.62),
	Vector2i(2, -1): Vector2(0.90, -1.60), Vector2i(3, -1): Vector2(1.31, -1.60),
}
## Right and forward distance of the outer cultivator tine as it enters the bed.
const TINE_OFFSET := Vector2(0.445, 0.575)
@export var team := "player"
var health := 300
var max_health: int:
	get: return RULES.farm_health
var assigned_depot: Node3D
var cells: Array[Vector2i] = []
## The Forester working it, if any.
var worker: Node3D
@onready var model: Node3D = $Visuals/Model
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
## Empty means the worker may take the plot.
func worker_refusal(unit: Node3D) -> String:
	if health <= 0 or is_queued_for_deletion(): return "Farm unavailable"
	if not is_instance_valid(unit) or unit.get("team") != team: return "Farm belongs to the other side"
	var stats := unit.get("unit_stats") as UnitStats
	if stats == null or stats.unit_id != &"forester_maiden" or unit.get("health") <= 0 or unit.is_queued_for_deletion():
		return "A Farm requires a Forester Maiden"
	if worker_busy() and worker != unit: return "Farm already has a worker"
	return ""
func accepts(unit: Node3D) -> bool:
	return worker_refusal(unit).is_empty()
func worker_busy() -> bool:
	return is_instance_valid(worker) and worker.health > 0 and worker.order in ["gather", "return"] and worker.source == self
## Takes `unit` as its worker; false when another worker is on it.
func take_worker(unit: Node3D) -> bool:
	if not accepts(unit): return false
	worker = unit
	return true
func can_extract(asking: String) -> bool:
	return asking == team and health > 0 and not is_queued_for_deletion()
func extract(requested: int, asking := "") -> int:
	if not can_extract(asking): return 0
	return mini(maxi(0,requested),RULES.farm_food_per_beat)
func has_furrow(cell: Vector2i) -> bool:
	return FURROWS.has(cell - cells[0])
## Test the nearest entrances first. The unit's usual path check owns obstacles,
## ground navigation, and occupancy; a blocked entrance falls through to another.
func tending_cells(near: Vector2i) -> Array[Vector2i]:
	var stands: Array[Vector2i] = []
	for offset: Vector2i in FURROWS:
		stands.append(cells[0] + offset)
	stands.sort_custom(func(a: Vector2i, b: Vector2i): return a.distance_squared_to(near) < b.distance_squared_to(near))
	return stands
## The worker takes the final part of her step inside the already claimed cell.
## Turn her shoulder so the right-hand blade lands on soil, clear of the rail.
func tending_pose(cell: Vector2i) -> Transform3D:
	var mark: Vector2 = FURROWS[cell - cells[0]]
	var soil := to_global(Vector3(mark.x, 0.0, mark.y))
	var center: Vector3 = ground.tile_to_world(cell)
	var inward := (soil - center).normalized()
	var stance := soil - inward * TINE_OFFSET.length()
	var facing := inward.rotated(Vector3.UP, atan2(TINE_OFFSET.x, TINE_OFFSET.y))
	return Transform3D(Basis.looking_at(facing), stance)
func update_label() -> void:
	if not has_node("Label"): return
	$Label.text = "FARM · %s · %d/%d HP" % ["tilled" if worker_busy() else "no worker",health,max_health]
func _process(_delta: float) -> void:
	update_label()
	model.show_state(worker_busy() and worker.order == "gather" and worker.state == "Farming", false)
func take_damage(hit: int) -> void:
	health = maxi(0,health-maxi(0,hit))
	update_label()
	if health <= 0 and not is_queued_for_deletion():
		set_process(false)
		for group in get_groups(): remove_from_group(group)
		model.reparent(get_parent())
		model.play_death()
		queue_free()
func _exit_tree() -> void:
	if not is_instance_valid(ground): return
	for cell in cells:
		if ground.tiles[cell.y*ground.grid_size.x+cell.x].occupied_by == _key(): ground.set_tile_feature(cell,"occupied_by",null)
