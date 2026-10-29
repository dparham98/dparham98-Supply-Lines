extends Node
## Explicit source selection: never pool balances or fall back to another payer.
@export var depot_scene: PackedScene
@export var truck_scene: PackedScene
@export var generator_scene: PackedScene
@export var cargo_scene: PackedScene
@export var barracks_scene: PackedScene
@export var tank_factory_scene: PackedScene
@export var supply_rules: SupplyRules
@export var mine_scene: PackedScene
@export var engineering_rules: EngineeringRules
var preview_material: StandardMaterial3D
var selected: Node3D
var construction_builder: Node3D
var builder_required := false
@onready var game = get_parent()
func select_depot(node: Node3D) -> void:
	selected = node
	if not builder_required: game.selected_building = node if is_instance_valid(node) and node.is_in_group("depots") else null
	for depot in get_tree().get_nodes_in_group("depots"):
		depot.get_node("Territory").visible = depot == selected and depot.team == "player"
func owned_selected() -> bool:
	return SupplySource.available(selected,"player")
func footprint_start(point: Vector3, size: Vector2i) -> Vector2i:
	var cell = game.ground.get_tile_at_position(point)
	return Vector2i(-1,-1) if cell == null else cell-size/2
func can_place(point: Vector3, payer: Node3D, expansion := false) -> bool:
	var preview = depot_scene.instantiate()
	var size: Vector2i = preview.footprint
	preview.free()
	return can_place_size(point,payer,size,expansion)
func can_place_size(point: Vector3, payer: Node3D, size: Vector2i, expansion := false) -> bool:
	var start := footprint_start(point,size)
	if not game.ground.is_footprint_valid(start,size): return false
	if expansion: return true
	if not SupplySource.available(payer,"player"): return false
	for offset in [Vector2i.ZERO,Vector2i(size.x-1,0),Vector2i(0,size.y-1),size-Vector2i.ONE]:
		if game.ground.tile_to_world(start+offset).distance_to(payer.global_position) > SupplySource.radius(payer): return false
	return true
func construct(point: Vector3) -> bool:
	if not builder_valid(): game.notify("Builder must remain selected, alive and inside the paying stockpile range."); return false
	if not owned_selected() or not can_place(point,selected):
		game.notify("Select a friendly stockpile; all construction corners must be in its range on empty land."); return false
	var rules = depot_rules()
	if not selected.spend_local(rules.depot_energy_cost,rules.depot_iron_cost):
		game.notify("Selected stockpile lacks local construction resources."); return false
	var payer = selected
	establish(point,0,0)
	if builder_required: select_depot(payer)
	return true
func establish(point: Vector3, energy: int, iron: int) -> Node3D:
	var node = depot_scene.instantiate()
	node.position = point
	node.grant_construction_infantry = true
	node.initial_energy = energy
	node.initial_iron = iron
	game.get_node("Entities/Buildings").add_child(node,true)
	select_depot(node)
	return node
func deploy_selected_truck() -> bool:
	for unit in get_tree().get_nodes_in_group("units"):
		if unit.team != "player" or not unit.is_selected or not unit.is_depot_truck: continue
		return deploy_truck(unit,unit.global_position)
	game.notify("Select a Depot Truck to deploy.")
	return false
## Valid deploy site for this truck: an empty 8 × 8 footprint, ignoring the truck's own cells.
func can_deploy_at(unit: Node3D, point: Vector3) -> bool:
	var claimed: Array = unit._claimed.duplicate()
	for cell in claimed: unit._release(cell)
	var valid := can_place(point,null,true)
	for cell in claimed: unit._claim(cell)
	return valid
func deploy_truck(unit: Node3D, point: Vector3) -> bool:
	unit._stop_route()
	for cell in unit._claimed.duplicate(): unit._release(cell)
	if not can_place(point,null,true):
		unit._claim(unit.grid_position)
		game.notify("Truck needs an empty 8 × 8 footprint on buildable land."); return false
	var rules = unit.deployment_rules
	unit.remove_from_group("units")
	unit.queue_free()
	establish(point,rules.deployed_energy,rules.deployed_iron)
	game.notify("Truck consumed; new Depot established with its configured starter inventory.")
	return true

func construct_generator(point: Vector3) -> bool:
	if not builder_valid(): game.notify("Builder must remain selected, alive and inside the paying stockpile range."); return false
	if not owned_selected() or not can_place_size(point,selected,supply_rules.generator_footprint):
		game.notify("Generator requires empty land entirely in the selected stockpile range.")
		return false
	if not selected.spend_local(supply_rules.generator_energy_cost,supply_rules.generator_iron_cost):
		game.notify("Selected stockpile lacks local generator resources.")
		return false
	var generator = generator_scene.instantiate()
	generator.rules = supply_rules
	generator.assigned_depot = selected if selected.is_in_group("depots") else null
	generator.team = selected.team
	generator.position = point
	game.get_node("Entities/Buildings").add_child(generator,true)
	game.notify("Generator built from %s. Choose a covering Depot in its HUD to operate." % selected.name)
	return true
func _process(_delta: float) -> void:
	var ghost = game.get_node_or_null("ConstructionPreview")
	if ghost == null: return
	ghost.visible = not game.global_plan_kind.is_empty() or game.placing_rail or game.placing_depot or game.placing_generator or not game.placing_structure.is_empty()
	if not ghost.visible: return
	var camera := game.get_viewport().get_camera_3d()
	var mouse := game.get_viewport().get_mouse_position()
	var point = Plane(Vector3.UP,0).intersects_ray(camera.project_ray_origin(mouse),camera.project_ray_normal(mouse))
	if point == null: ghost.visible = false; return
	if not game.global_plan_kind.is_empty(): update_global_preview(point)
	else: update_preview(point,game.placing_generator)
func update_preview(point: Vector3, generator: bool) -> bool:
	var ghost = game.get_node("ConstructionPreview")
	var size: Vector2i = supply_rules.generator_footprint
	var energy_cost: int = supply_rules.generator_energy_cost
	var iron_cost: int = supply_rules.generator_iron_cost
	if not generator and not game.placing_rail:
		var instance = depot_scene.instantiate()
		size = instance.footprint
		instance.free()
		if owned_selected():
			energy_cost = depot_rules().depot_energy_cost
			iron_cost = depot_rules().depot_iron_cost
	if game.placing_structure == &"iron_mine":
		size = engineering_rules.mine_footprint
		energy_cost = engineering_rules.mine_energy_cost
		iron_cost = engineering_rules.mine_iron_cost
	elif not game.placing_structure.is_empty():
		var instance = production_scene(game.placing_structure).instantiate()
		size = instance.stats.footprint
		energy_cost = instance.stats.energy_cost
		iron_cost = instance.stats.iron_cost
		instance.free()
	if game.placing_rail:
		size = Vector2i.ONE
		energy_cost = game.get_node("RailNetwork").rules.rail_energy_cost
		iron_cost = game.get_node("RailNetwork").rules.rail_iron_cost
	var start := footprint_start(point,size)
	ghost.position = game.ground.tile_to_world(start)+Vector3(size.x*0.5-0.5,0.2,size.y*0.5-0.5)
	ghost.get_node("Footprint").scale = Vector3(size.x,1,size.y)
	var valid: bool = builder_valid() and owned_selected() and can_place_size(point,selected,size) and selected.energy >= energy_cost and selected.iron >= iron_cost
	if game.placing_rail: valid = builder_valid() and game.get_node("RailNetwork").can_build(start,selected) and selected.energy >= energy_cost and selected.iron >= iron_cost
	if game.placing_structure == &"iron_mine": valid = builder_valid() and can_place_mine(point,selected) and selected.energy >= energy_cost and selected.iron >= iron_cost
	if preview_material == null:
		preview_material = ghost.get_node("Footprint").mesh.material.duplicate()
		ghost.get_node("Footprint").material_override = preview_material
	preview_material.albedo_color = Color(0.2,1,0.4,0.45) if valid else Color(1,0.15,0.1,0.45)
	ghost.get_node("Status").text = "%s · payer %s · %d E / %d I" % ["VALID" if valid else "BLOCKED / FUNDS",selected.name if owned_selected() else "none",energy_cost,iron_cost]
	return valid

func clear_builder() -> void:
	construction_builder = null
	builder_required = false
func bind_builder(unit: Node3D, payer: Node3D) -> void:
	construction_builder = unit
	builder_required = true
	select_depot(payer)
func builder_valid() -> bool:
	if not builder_required: return not is_instance_valid(selected) or selected.is_in_group("depots") # Mobile construction requires Infantry.
	return is_instance_valid(construction_builder) and construction_builder.health > 0 and construction_builder.team == "player" and construction_builder.can_construct and construction_builder.is_selected and owned_selected() and construction_builder.global_position.distance_to(selected.global_position) <= SupplySource.radius(selected)

func production_scene(kind: StringName) -> PackedScene:
	if kind == &"barracks": return barracks_scene
	if kind == &"tank_factory": return tank_factory_scene
	return null
func construct_production(point: Vector3, kind: StringName) -> bool:
	if kind == &"iron_mine": return construct_mine(point)
	var scene := production_scene(kind)
	if scene == null or not builder_valid() or not owned_selected(): return false
	var preview = scene.instantiate()
	var stats: ProductionBuildingStats = preview.stats
	preview.free()
	if not can_place_size(point,selected,stats.footprint): game.notify("Production building needs empty land inside the paying stockpile range."); return false
	if not selected.spend_local(stats.energy_cost,stats.iron_cost): game.notify("Paying stockpile lacks local construction resources."); return false
	var building = scene.instantiate()
	building.position = point
	building.team = selected.team
	building.assigned_depot = selected if selected.is_in_group("depots") else null
	game.get_node("Entities/Buildings").add_child(building,true)
	game.notify("%s built from %s; production requires an assigned covering Depot." % [stats.display_name,selected.name])
	return true

func can_place_mine(point: Vector3, payer: Node3D) -> bool:
	if not SupplySource.available(payer,"player"): return false
	var size: Vector2i = engineering_rules.mine_footprint
	var start := footprint_start(point,size)
	if not game.ground.ore_footprint_valid(start,size): return false
	for offset in [Vector2i.ZERO,Vector2i(size.x-1,0),Vector2i(0,size.y-1),size-Vector2i.ONE]:
		if game.ground.tile_to_world(start+offset).distance_to(payer.global_position) > SupplySource.radius(payer): return false
	return true
func construct_mine(point: Vector3) -> bool:
	if not builder_valid() or not can_place_mine(point,selected): game.notify("Mine requires a complete empty iron-deposit footprint inside the paying stockpile range."); return false
	if not selected.spend_local(engineering_rules.mine_energy_cost,engineering_rules.mine_iron_cost): game.notify("Paying stockpile lacks local mine resources."); return false
	var mine = mine_scene.instantiate()
	mine.rules = engineering_rules; mine.position = point
	game.get_node("Entities/Buildings").add_child(mine,true)
	game.notify("Shared iron mine built. Any player's Infantry can gather or repair it.")
	return true

func depot_rules() -> DepotRules:
	return load("res://assets/economy/depot_rules.tres")

# Global planning is separate from explicit selected-builder construction.
const PLAN_SCENE = preload("res://scenes/gameplay/construction_plan.tscn")
func plan_spec(kind: StringName) -> Dictionary:
	if kind == &"depot":
		var preview = depot_scene.instantiate()
		var size: Vector2i = preview.footprint
		preview.free()
		return {"title":"Depot","size":size,"energy":depot_rules().depot_energy_cost,"iron":depot_rules().depot_iron_cost,"scene":depot_scene}
	if kind == &"generator": return {"title":"Generator","size":supply_rules.generator_footprint,"energy":supply_rules.generator_energy_cost,"iron":supply_rules.generator_iron_cost,"scene":generator_scene}
	if kind == &"iron_mine": return {"title":"Iron Mine","size":engineering_rules.mine_footprint,"energy":engineering_rules.mine_energy_cost,"iron":engineering_rules.mine_iron_cost,"scene":mine_scene}
	if kind == &"rail":
		var rails = game.get_node("RailNetwork")
		return {"title":"Rail","size":Vector2i.ONE,"energy":rails.rules.rail_energy_cost,"iron":rails.rules.rail_iron_cost,"scene":rails.segment_scene}
	var scene := production_scene(kind)
	if scene == null: return {}
	var preview = scene.instantiate()
	var stats: ProductionBuildingStats = preview.stats
	preview.free()
	return {"title":stats.display_name,"size":stats.footprint,"energy":stats.energy_cost,"iron":stats.iron_cost,"scene":scene}
func plan_terrain_valid(start: Vector2i, size: Vector2i, kind: StringName) -> bool:
	return game.ground.ore_footprint_valid(start,size) if kind == &"iron_mine" else game.ground.is_footprint_valid(start,size)
func plan_overlaps(start: Vector2i, size: Vector2i) -> bool:
	var rect := Rect2i(start,size)
	for plan in get_tree().get_nodes_in_group("construction_plans"):
		if not plan.finished and rect.intersects(Rect2i(plan.start,plan.spec.size)): return true
	return false
func queue_plan(point: Vector3, kind: StringName, payer: Node3D = null, pin_payer := false) -> Node3D:
	var spec := plan_spec(kind)
	if spec.is_empty(): return null
	var start := footprint_start(point,spec.size)
	if not plan_terrain_valid(start,spec.size,kind) or plan_overlaps(start,spec.size):
		game.notify("Plan needs valid empty terrain and cannot overlap another plan. Mines require iron deposits.")
		return null
	var plan = PLAN_SCENE.instantiate()
	plan.kind = kind; plan.spec = spec; plan.start = start
	plan.payer = payer; plan.pinned = pin_payer or payer != null
	plan.position = game.ground.tile_to_world(start+spec.size/2)
	game.get_node("Entities/Buildings").add_child(plan,true)
	game.notify("%s plan placed. No resources spent until one friendly covering Depot can pay." % spec.title)
	return plan
func plan_source_valid(plan: Node3D, source) -> bool:
	if not SupplySource.available(source,"player") or not source.is_in_group("depots"): return false
	if source.energy < plan.spec.energy or source.iron < plan.spec.iron: return false
	if plan.kind == &"rail": return game.get_node("RailNetwork").can_build(plan.start,source)
	return can_place_mine(plan.global_position,source) if plan.kind == &"iron_mine" else can_place_size(plan.global_position,source,plan.spec.size)
func plan_payer(plan: Node3D) -> Node3D:
	if plan.pinned: return plan.payer if plan_source_valid(plan,plan.payer) else null
	# Auto is explicitly selected in the global menu: nearest eligible Depot, stable tie order.
	for source in SupplySource.candidates(get_tree(),plan.global_position,"player"):
		if plan_source_valid(plan,source): return source
	return null
func complete_plan(plan: Node3D, payer: Node3D) -> Node3D:
	# Revalidate immediately before one atomic local payment; no awaiting or pooled balance.
	if plan.finished or not plan_terrain_valid(plan.start,plan.spec.size,plan.kind) or not plan_source_valid(plan,payer): return null
	var building = plan.spec.scene.instantiate()
	if plan.kind == &"depot":
		building.initial_energy = 0; building.initial_iron = 0
		building.grant_construction_infantry = true
	elif plan.kind == &"generator": building.rules = supply_rules; building.assigned_depot = payer
	elif plan.kind == &"iron_mine": building.rules = engineering_rules
	else: building.assigned_depot = payer
	if not payer.spend_local(plan.spec.energy,plan.spec.iron): building.free(); return null
	building.position = plan.global_position
	if plan.kind == &"rail": game.add_child(building,true)
	else: game.get_node("Entities/Buildings").add_child(building,true)
	return building
func update_global_preview(point: Vector3) -> bool:
	var spec := plan_spec(game.global_plan_kind)
	var ghost = game.get_node("ConstructionPreview")
	var start := footprint_start(point,spec.size)
	ghost.position = game.ground.tile_to_world(start)+Vector3(spec.size.x*0.5-0.5,0.2,spec.size.y*0.5-0.5)
	ghost.get_node("Footprint").scale = Vector3(spec.size.x,1,spec.size.y)
	var valid := plan_terrain_valid(start,spec.size,game.global_plan_kind) and not plan_overlaps(start,spec.size)
	if preview_material == null:
		preview_material = ghost.get_node("Footprint").mesh.material.duplicate()
		ghost.get_node("Footprint").material_override = preview_material
	preview_material.albedo_color = Color(1,0.75,0.1,0.5) if valid else Color(1,0.15,0.1,0.45)
	ghost.get_node("Status").text = "%s · %s · %d E / %d I on completion" % ["PLAN" if valid else "BLOCKED",spec.title,spec.energy,spec.iron]
	return valid
