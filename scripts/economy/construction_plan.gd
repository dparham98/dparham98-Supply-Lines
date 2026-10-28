extends Node3D
# An unpaid intention. No terrain claim, collision body, resource reservation or actor orders.
var kind: StringName
var spec: Dictionary
var start := Vector2i.ZERO
var payer: Node3D
var pinned := false
var state := "Waiting for friendly Depot coverage"
var finished := false
var elapsed := 0.0
@onready var network = get_tree().get_first_node_in_group("skirmish").get_node("DepotNetwork")
func _ready() -> void:
	add_to_group("construction_plans")
	var size: Vector2i = spec.size
	$Visuals/Grid.scale = Vector3(size.x,1,size.y)
	$Visuals/Grid.position = Vector3(size.x*0.5-0.5-size.x/2,0.2,size.y*0.5-0.5-size.y/2)
	$Visuals/Grid.material_override = $Visuals/Grid.mesh.material.duplicate()
	$Visuals/Grid.material_override.set_shader_parameter("cells",Vector2(size))
	$Label.position = $Visuals/Grid.position+Vector3(0,1.5,0)
	refresh_label()
func _process(delta: float) -> void:
	elapsed += delta
	if elapsed < 0.25: return
	elapsed = 0
	try_complete()
func try_complete() -> Node3D:
	if finished: return null
	if not network.plan_terrain_valid(start,spec.size,kind):
		state = "Waiting for footprint to clear"; refresh_label(); return null
	var source = network.plan_payer(self)
	if source == null:
		state = "Waiting for pinned Depot coverage / funds" if pinned else "Waiting for friendly Depot coverage / funds"
		refresh_label(); return null
	var building = network.complete_plan(self,source)
	if building != null:
		finished = true
		remove_from_group("construction_plans")
		if network.game.selected_building == self:
			network.game.selected_building = building if kind != &"rail" else null
			if kind == &"depot": network.select_depot(building)
		network.game.notify("%s built from %s local stock." % [spec.title,source.name])
		queue_free()
	return building
func refresh_label() -> void:
	$Label.text = "PLAN · %s · %d E / %d I\n%s" % [spec.title,spec.energy,spec.iron,state]
func cancel() -> void:
	if finished: return
	finished = true
	remove_from_group("construction_plans")
	if network.game.selected_building == self: network.game.selected_building = null
	network.game.notify("Construction plan cancelled. No resources were spent.")
	queue_free()
