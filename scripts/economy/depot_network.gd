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
## The mine built on a mine site (docs/MINE_SITES.md): the same mine with the model made for the cut in the rock.
## Left empty, a site gets mine_scene.
@export var site_mine_scene: PackedScene
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
## The mine scene for a spot: the portal mine on a mine site, the pithead on an ore field.
func mine_scene_for(spot: Rect2i) -> PackedScene:
	var on_site: bool = game.ground.get_terrain(spot.position) == game.ground.Terrain.MINE_SITE
	return site_mine_scene if on_site and site_mine_scene != null else mine_scene
## Where a mine placed at a point would stand: the whole mine site under the point, or the ordinary footprint
## about the point on an ore field (docs/MINE_SITES.md).
func mine_spot(point: Vector3) -> Rect2i:
	var cell = game.ground.get_tile_at_position(point)
	if cell != null and game.ground.get_terrain(cell) == game.ground.Terrain.MINE_SITE: return game.ground.mine_site_rect(cell)
	return Rect2i(footprint_start(point,engineering_rules.mine_footprint),engineering_rules.mine_footprint)
func footprint_start(point: Vector3, size: Vector2i) -> Vector2i:
	var cell = game.ground.get_tile_at_position(point)
	return Vector2i(-1,-1) if cell == null else cell-size/2
## `model_yaw` is the turn of the new Depot's model: 0 faces east, as built by Infantry; a deployed truck's
## Depot takes the truck's heading (deploy_yaw).
func can_place(point: Vector3, payer: Node3D, expansion := false, team := "player", ignore: Node = null, model_yaw := 0.0) -> bool:
	return can_place_size(point,payer,depot_size(),expansion) and depot_spacing_ok(point,team,ignore) and strip_clear(point,model_yaw)
const STRIP_NOTICE := "Keep the strip beside a Depot clear: Depot Trucks are built there."
var _strip := []
## The tiles a Depot centred on `point` keeps clear for building trucks (Depot.truck_side_cells), read from
## the Depot scene once.
func strip_cells(point: Vector3, model_yaw := 0.0) -> Array[Vector2i]:
	if _strip.is_empty():
		var preview = depot_scene.instantiate()
		var model: Node3D = preview.get_node("Visuals/Model")
		_strip = [model.transform,model.truck_side]
		preview.free()
	var centre := depot_centre(point)
	var place := Transform3D(Basis(Vector3.UP,model_yaw),Vector3(centre.x,point.y,centre.y))*(_strip[0] as Transform3D)
	var side: AABB = _strip[1]
	var result: Array[Vector2i] = []
	var a = game.ground.get_tile_at_position(place*side.position)
	var b = game.ground.get_tile_at_position(place*side.end)
	if a == null or b == null: return result
	for z in range(mini(a.y,b.y),maxi(a.y,b.y)+1):
		for x in range(mini(a.x,b.x),maxi(a.x,b.x)+1): result.append(Vector2i(x,z))
	return result
## Whether a new Depot's truck strip is free of buildings, plans and another Depot's strip. Units, terrain and
## rail are left to the truck build itself ("Exit blocked · waiting").
func strip_clear(point: Vector3, model_yaw := 0.0, ignore: Node = null) -> bool:
	var plans := get_tree().get_nodes_in_group("construction_plans").filter(func(p): return p != ignore and not p.finished)
	for cell in strip_cells(point,model_yaw):
		var tile: Dictionary = game.ground.tiles[cell.y*game.ground.grid_size.x+cell.x]
		if tile.has("apron"): return false
		if tile.occupied_by != null and not str(tile.occupied_by).begins_with("agent_"): return false
		for plan in plans:
			if Rect2i(plan.start,plan.spec.size).has_point(cell): return false
	return true
## Whether any tile of a footprint lies on a Depot's truck strip, standing or planned.
func on_strip(start: Vector2i, size: Vector2i) -> bool:
	var rect := Rect2i(start,size)
	for z in range(start.y,start.y+size.y):
		for x in range(start.x,start.x+size.x):
			if game.ground.is_tile_in_bounds(Vector2i(x,z)) and game.ground.tiles[z*game.ground.grid_size.x+x].has("apron"): return true
	for plan in get_tree().get_nodes_in_group("construction_plans"):
		if plan.finished or plan.kind != &"depot": continue
		for cell in strip_cells(plan.global_position):
			if rect.has_point(cell): return true
	return false
## Why a building can't go at `start`, when the reason is a Depot's truck strip: its own footprint on one,
## or, for a Depot, a building or plan on the strip it would keep clear.
func strip_notice(point: Vector3, size: Vector2i, kind: StringName, model_yaw := 0.0) -> String:
	var start := footprint_start(point,size)
	if on_strip(start,size): return STRIP_NOTICE
	if kind == &"depot" and game.ground.is_footprint_valid(start,size) and not strip_clear(point,model_yaw): return STRIP_NOTICE
	return ""
## The heading a truck's Depot would take if it deployed now: its nearest 90 degrees.
func deploy_yaw(unit: Node3D) -> float:
	return snappedf(unit.get_node("Visuals").rotation.y,PI/2)+PI/2
var _depot_size := Vector2i.ZERO
## The Depot footprint, read once from the Depot scene.
func depot_size() -> Vector2i:
	if _depot_size == Vector2i.ZERO:
		var preview = depot_scene.instantiate()
		_depot_size = preview.footprint
		preview.free()
	return _depot_size
## Where a Depot placed at `point` stands once snapped to its footprint, as depot.gd places it.
func depot_centre(point: Vector3) -> Vector2:
	var size := depot_size()
	var start := footprint_start(point,size)
	var at: Vector3 = game.ground.tile_to_world(start)+Vector3(size.x*0.5-0.5,0,size.y*0.5-0.5)
	return Vector2(at.x,at.z)
## Whether a new Depot may stand at `point`: its snapped centre at least DepotRules.min_depot_spacing() (twice
## the Depot range, so ranges never overlap) from
## every Depot of `team`, every unfinished Depot plan, and every site a Depot truck of `team` has been
## ordered to deploy on, other than `ignore` (the plan or truck asking). Captured Depots are not checked
## (docs/DEPOT_SPACING.md).
func depot_spacing_ok(point: Vector3, team := "player", ignore: Node = null) -> bool:
	var spacing: float = depot_rules().min_depot_spacing()
	if spacing <= 0.0: return true
	var at := depot_centre(point)
	for depot in get_tree().get_nodes_in_group("depots"):
		if depot == ignore or depot.team != team or depot.is_queued_for_deletion(): continue
		if at.distance_to(Vector2(depot.global_position.x,depot.global_position.z)) < spacing: return false
	for plan in get_tree().get_nodes_in_group("construction_plans"):
		if plan == ignore or plan.finished or plan.kind != &"depot": continue
		if at.distance_to(depot_centre(plan.global_position)) < spacing: return false
	for unit in get_tree().get_nodes_in_group("units"):
		if unit == ignore or unit.get("is_depot_truck") != true or unit.team != team: continue
		for site in deploy_sites(unit):
			if at.distance_to(depot_centre(site)) < spacing: return false
	return true
## The sites a Depot truck is on its way to deploy on: its current order and any queued deploys.
func deploy_sites(unit: Node3D) -> Array[Vector3]:
	var sites: Array[Vector3] = []
	if unit.order == "deploy": sites.append(unit.move_goal)
	for entry in unit.order_queue:
		if entry.get("kind","") == "deploy" and entry.get("point") is Vector3: sites.append(entry.point)
	return sites
## The spacing rule in words, for every notice and status line that names it.
func spacing_reason() -> String:
	return "at least %.0f m from every other friendly Depot, so the ranges don't overlap" % depot_rules().min_depot_spacing()
## The notice for a Depot site that fails on spacing, or "" when spacing is not the problem.
func spacing_notice(point: Vector3, team := "player", ignore: Node = null) -> String:
	return "" if depot_spacing_ok(point,team,ignore) else "A new Depot must stand %s." % spacing_reason()
## Whether a Depot plan still keeps its spacing; other plans always do.
func plan_spacing_ok(plan: Node3D) -> bool:
	return plan.kind != &"depot" or depot_spacing_ok(plan.global_position,"player",plan)
func can_place_size(point: Vector3, payer: Node3D, size: Vector2i, expansion := false) -> bool:
	var start := footprint_start(point,size)
	if not game.ground.is_footprint_valid(start,size): return false
	if expansion: return true
	if not SupplySource.available(payer,"player"): return false
	return range_covers_footprint(payer,start,size)
## Whether a stockpile's range covers a footprint: the footprint's centre is inside the range, as the
## Territory ring shows it (docs/DEPOT_RANGE.md). Every corner used to have to be inside; with the 17.5 m
## range that left almost no room round a Depot, so plans waited for energy beside it for ever.
func range_covers_footprint(source, start: Vector2i, size: Vector2i) -> bool:
	var centre: Vector3 = game.ground.tile_to_world(start)+Vector3(size.x*0.5-0.5,0,size.y*0.5-0.5)
	return Vector2(centre.x-source.global_position.x,centre.z-source.global_position.z).length() <= SupplySource.radius(source)
func construct(point: Vector3) -> bool:
	if not builder_valid(): game.notify("Builder must remain selected, alive and inside the paying stockpile range."); return false
	if not owned_selected() or not can_place(point,selected):
		var spaced := spacing_notice(point)
		if spaced.is_empty(): spaced = strip_notice(point,depot_size(),&"depot")
		game.notify(spaced if not spaced.is_empty() else "Select a friendly stockpile; the building's centre must be inside its range, on empty land."); return false
	var rules = depot_rules()
	if not selected.spend_local(rules.depot_energy_cost,rules.depot_iron_cost):
		game.notify("Selected stockpile lacks local construction resources."); return false
	var payer = selected
	establish(point,0,0)
	if builder_required: select_depot(payer)
	return true
func establish(point: Vector3, energy: int, iron: int, model_yaw := 0.0) -> Node3D:
	var node = depot_scene.instantiate()
	node.position = point
	node.get_node("Visuals").rotation.y = model_yaw
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
## Valid deploy site for this truck: an empty Depot footprint, ignoring the truck's own cells.
func can_deploy_at(unit: Node3D, point: Vector3) -> bool:
	var claimed: Array = unit._claimed.duplicate()
	for cell in claimed: unit._release(cell)
	var valid := can_place(point,null,true,unit.team,unit,deploy_yaw(unit))
	for cell in claimed: unit._claim(cell)
	return valid
func deploy_truck(unit: Node3D, point: Vector3) -> bool:
	unit._stop_route()
	for cell in unit._claimed.duplicate(): unit._release(cell)
	if not can_place(point,null,true,unit.team,unit,deploy_yaw(unit)):
		unit._claim(unit.grid_position)
		var spaced := spacing_notice(point,unit.team,unit)
		if spaced.is_empty(): spaced = strip_notice(point,depot_size(),&"depot",deploy_yaw(unit))
		game.notify(spaced if not spaced.is_empty() else "Truck needs an empty Depot footprint on buildable land."); return false
	var rules = unit.deployment_rules
	# The Depot takes the truck's nearest 90 degree heading; its model turns and pulls up from where the truck stood.
	var visuals: Node3D = unit.get_node("Visuals")
	var yaw: float = visuals.rotation.y
	var heading := snappedf(yaw,PI/2)
	var trailer: Node3D = visuals.get_node_or_null("Model/Rig")
	var from: Vector3 = trailer.global_position if trailer != null else unit.global_position
	from.y = point.y
	unit.remove_from_group("units")
	unit.queue_free()
	var depot := establish(point,rules.deployed_energy,rules.deployed_iron,heading+PI/2)
	depot.get_node("Visuals/Model").play_deploy(from,angle_difference(heading,yaw))
	game.notify("Truck consumed; new Depot established with its configured starter inventory.")
	return true

func construct_generator(point: Vector3) -> bool:
	if not builder_valid(): game.notify("Builder must remain selected, alive and inside the paying stockpile range."); return false
	if not owned_selected() or not can_place_size(point,selected,supply_rules.generator_footprint):
		var strip := strip_notice(point,supply_rules.generator_footprint,&"generator")
		game.notify(strip if not strip.is_empty() else "Generator requires empty land entirely in the selected stockpile range.")
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
	var truck := deploying_truck()
	ghost.visible = not game.global_plan_kind.is_empty() or game.placing_depot or game.placing_generator or not game.placing_structure.is_empty() or truck != null
	if not ghost.visible: return
	var camera := game.get_viewport().get_camera_3d()
	var mouse := game.get_viewport().get_mouse_position()
	var point = Plane(Vector3.UP,0).intersects_ray(camera.project_ray_origin(mouse),camera.project_ray_normal(mouse))
	if point == null: ghost.visible = false; return
	if not game.global_plan_kind.is_empty(): update_global_preview(point)
	elif truck != null: update_deploy_preview(point,truck)
	else: update_preview(point,game.placing_generator)
## The selected player Depot Truck while Deploy waits for a site, or null.
func deploying_truck() -> Node3D:
	if game.pending_unit_command != "deploy": return null
	for unit in get_tree().get_nodes_in_group("units"):
		if unit.team == "player" and unit.is_selected and unit.get("is_depot_truck") == true: return unit
	return null
## A Depot about to be placed shows its range around where it will stand, so the player can see what it
## will cover. Other placements hide it.
func show_range(depot: bool) -> void:
	var ring: Node3D = game.get_node("ConstructionPreview/Range")
	ring.visible = depot
	if depot: ring.scale = Vector3.ONE*depot_rules().construction_radius
## Deploy preview: the Depot footprint and range where the truck would set it down.
func update_deploy_preview(point: Vector3, truck: Node3D) -> bool:
	var ghost = game.get_node("ConstructionPreview")
	var size := depot_size()
	var start := footprint_start(point,size)
	ghost.position = game.ground.tile_to_world(start)+Vector3(size.x*0.5-0.5,0.2,size.y*0.5-0.5)
	ghost.get_node("Footprint").scale = Vector3(size.x,1,size.y)
	show_range(true)
	var valid := can_deploy_at(truck,point)
	if preview_material == null:
		preview_material = ghost.get_node("Footprint").mesh.material.duplicate()
		ghost.get_node("Footprint").material_override = preview_material
	preview_material.albedo_color = Color(0.2,1,0.4,0.45) if valid else Color(1,0.15,0.1,0.45)
	var reason := ""
	if not valid: reason = " · " + (spacing_reason() if not depot_spacing_ok(point,truck.team,truck) else "needs empty buildable land")
	ghost.get_node("Status").text = "%s · Depot%s" % ["DEPLOY" if valid else "BLOCKED",reason]
	return valid
func update_preview(point: Vector3, generator: bool) -> bool:
	var ghost = game.get_node("ConstructionPreview")
	var size: Vector2i = supply_rules.generator_footprint
	var energy_cost: int = supply_rules.generator_energy_cost
	var iron_cost: int = supply_rules.generator_iron_cost
	if not generator:
		var instance = depot_scene.instantiate()
		size = instance.footprint
		instance.free()
		if owned_selected():
			energy_cost = depot_rules().depot_energy_cost
			iron_cost = depot_rules().depot_iron_cost
	if game.placing_structure == &"iron_mine":
		size = mine_spot(point).size
		energy_cost = engineering_rules.mine_energy_cost
		iron_cost = engineering_rules.mine_iron_cost
	elif not game.placing_structure.is_empty():
		var instance = production_scene(game.placing_structure).instantiate()
		size = instance.stats.footprint
		energy_cost = instance.stats.energy_cost
		iron_cost = instance.stats.iron_cost
		instance.free()
	var start := footprint_start(point,size)
	ghost.position = game.ground.tile_to_world(start)+Vector3(size.x*0.5-0.5,0.2,size.y*0.5-0.5)
	ghost.get_node("Footprint").scale = Vector3(size.x,1,size.y)
	show_range(not generator and game.placing_structure.is_empty())
	var valid: bool = builder_valid() and owned_selected() and can_place_size(point,selected,size) and selected.energy >= energy_cost and selected.iron >= iron_cost
	if not generator and game.placing_structure.is_empty(): valid = valid and depot_spacing_ok(point)
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
	if not can_place_size(point,selected,stats.footprint):
		var strip := strip_notice(point,stats.footprint,kind)
		game.notify(strip if not strip.is_empty() else "Production building needs empty land inside the paying stockpile range."); return false
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
	var spot := mine_spot(point)
	if not game.ground.ore_footprint_valid(spot.position,spot.size): return false
	return range_covers_footprint(payer,spot.position,spot.size)
func construct_mine(point: Vector3) -> bool:
	if not builder_valid() or not can_place_mine(point,selected):
		var strip := strip_notice(point,engineering_rules.mine_footprint,&"iron_mine")
		game.notify(strip if not strip.is_empty() else "Mine requires a complete empty iron-deposit footprint inside the paying stockpile range."); return false
	if not selected.spend_local(engineering_rules.mine_energy_cost,engineering_rules.mine_iron_cost): game.notify("Paying stockpile lacks local mine resources."); return false
	var spot := mine_spot(point)
	var mine = mine_scene_for(spot).instantiate()
	mine.rules = engineering_rules; mine.position = game.ground.tile_to_world(spot.position+spot.size/2)
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
	if kind == &"generator": return {"title":"Generator","size":supply_rules.generator_footprint,"energy":supply_rules.generator_energy_cost,"iron":supply_rules.generator_iron_cost,"scene":generator_scene,"model":_model_scene(generator_scene)}
	if kind == &"iron_mine": return {"title":"Iron Mine","size":engineering_rules.mine_footprint,"energy":engineering_rules.mine_energy_cost,"iron":engineering_rules.mine_iron_cost,"scene":mine_scene,"model":_model_scene(mine_scene)}
	if kind == &"rail":
		# Maglev pieces are laid directly by RailNetwork.place, not queued as plans.
		var rails = game.get_node("RailNetwork")
		return {"title":"Maglev track","size":Vector2i.ONE,"energy":rails.rules.rail_energy_cost,"iron":rails.cost("straight"),"scene":rails.straight_scene}
	var scene := production_scene(kind)
	if scene == null: return {}
	var preview = scene.instantiate()
	var stats: ProductionBuildingStats = preview.stats
	var visuals = preview.get_node_or_null("Visuals")
	var model: PackedScene = visuals.model_scene if visuals != null and "model_scene" in visuals else null
	preview.free()
	return {"title":stats.display_name,"size":stats.footprint,"energy":stats.energy_cost,"iron":stats.iron_cost,"scene":scene,"model":model}
var _model_scenes := {}
## The model a building scene shows in its Visuals slot, so its construction site can stand it up.
func _model_scene(scene: PackedScene) -> PackedScene:
	if scene == null: return null
	if not _model_scenes.has(scene):
		var preview = scene.instantiate()
		var visuals = preview.get_node_or_null("Visuals")
		_model_scenes[scene] = visuals.model_scene if visuals != null and "model_scene" in visuals else null
		preview.free()
	return _model_scenes[scene]
## A Depot plan also needs the strip it will keep clear to be free (strip_clear).
func plan_terrain_valid(start: Vector2i, size: Vector2i, kind: StringName, ignore: Node = null) -> bool:
	if kind == &"iron_mine": return game.ground.ore_footprint_valid(start,size)
	if not game.ground.is_footprint_valid(start,size): return false
	return kind != &"depot" or strip_clear(game.ground.tile_to_world(start+size/2),0.0,ignore)
## Whether a footprint overlaps another unfinished plan, or the strip a planned Depot will keep clear.
func plan_overlaps(start: Vector2i, size: Vector2i) -> bool:
	var rect := Rect2i(start,size)
	for plan in get_tree().get_nodes_in_group("construction_plans"):
		if plan.finished: continue
		if rect.intersects(Rect2i(plan.start,plan.spec.size)): return true
		if plan.kind == &"depot":
			for cell in strip_cells(plan.global_position):
				if rect.has_point(cell): return true
	return false
func queue_plan(point: Vector3, kind: StringName, payer: Node3D = null, pin_payer := false) -> Node3D:
	var spec := plan_spec(kind)
	if spec.is_empty(): return null
	if kind == &"rail": game.notify("Maglev track is laid piece by piece from the Build page, not planned."); return null
	var start := footprint_start(point,spec.size)
	if kind == &"iron_mine":
		# A mine planned on a mine site takes the whole site.
		var spot := mine_spot(point)
		spec = spec.duplicate()
		spec.size = spot.size; start = spot.position
		spec.scene = mine_scene_for(spot); spec.model = _model_scene(spec.scene)
	if not plan_terrain_valid(start,spec.size,kind) or plan_overlaps(start,spec.size):
		var strip := strip_notice(point,spec.size,kind)
		game.notify(strip if not strip.is_empty() else "Plan needs valid empty terrain and cannot overlap another plan. Mines require iron deposits.")
		return null
	if kind == &"depot" and not depot_spacing_ok(point):
		game.notify(spacing_notice(point))
		return null
	var plan = PLAN_SCENE.instantiate()
	plan.kind = kind; plan.spec = spec; plan.start = start
	plan.payer = payer; plan.pinned = pin_payer or payer != null
	plan.position = game.ground.tile_to_world(start+spec.size/2)
	game.get_node("Entities/Buildings").add_child(plan,true)
	if kind == &"rail": game.notify("Rail plan placed. A covering Depot pays it when the tile is clear.")
	else: game.notify("%s plan placed. Deliver %d iron to its footprint, then order Infantry to construct; a covering stockpile pays the energy as they build." % [spec.title,spec.iron])
	return plan
## Depots and deployed Cargo trucks pay plans in their range; rails need a Depot.
func plan_source_valid(plan: Node3D, source) -> bool:
	if not SupplySource.available(source,"player"): return false
	if source.energy < plan.spec.energy or source.iron < plan.spec.iron: return false
	return can_place_mine(plan.global_position,source) if plan.kind == &"iron_mine" else can_place_size(plan.global_position,source,plan.spec.size)
func plan_payer(plan: Node3D) -> Node3D:
	if plan.pinned: return plan.payer if plan_source_valid(plan,plan.payer) else null
	# Auto is explicitly selected in the global menu: nearest eligible Depot, stable tie order.
	for source in SupplySource.candidates(get_tree(),plan.global_position,"player"):
		if plan_source_valid(plan,source): return source
	return null
func complete_plan(plan: Node3D, payer: Node3D) -> Node3D:
	# Revalidate immediately before one atomic local payment; no awaiting or pooled balance.
	if plan.finished or not plan_terrain_valid(plan.start,plan.spec.size,plan.kind,plan) or not plan_source_valid(plan,payer): return null
	if not plan_spacing_ok(plan): return null
	var building = plan.spec.scene.instantiate()
	if plan.kind == &"depot":
		building.initial_energy = 0; building.initial_iron = 0
		building.grant_construction_infantry = true
	elif plan.kind == &"generator": building.rules = supply_rules; building.assigned_depot = payer if payer.is_in_group("depots") else null
	elif plan.kind == &"iron_mine": building.rules = engineering_rules
	else: building.assigned_depot = payer if payer.is_in_group("depots") else null
	if not payer.spend_local(plan.spec.energy,plan.spec.iron): building.free(); return null
	building.position = plan.global_position
	if plan.kind == &"rail": game.add_child(building,true)
	else: game.get_node("Entities/Buildings").add_child(building,true)
	return building
func update_global_preview(point: Vector3) -> bool:
	var spec := plan_spec(game.global_plan_kind)
	var ghost = game.get_node("ConstructionPreview")
	var start := footprint_start(point,spec.size)
	if game.global_plan_kind == &"iron_mine":
		var spot := mine_spot(point)
		spec = spec.duplicate()
		spec.size = spot.size; start = spot.position
	ghost.position = game.ground.tile_to_world(start)+Vector3(spec.size.x*0.5-0.5,0.2,spec.size.y*0.5-0.5)
	ghost.get_node("Footprint").scale = Vector3(spec.size.x,1,spec.size.y)
	show_range(game.global_plan_kind == &"depot")
	var valid := plan_terrain_valid(start,spec.size,game.global_plan_kind) and not plan_overlaps(start,spec.size)
	var spaced: bool = game.global_plan_kind != &"depot" or depot_spacing_ok(point)
	valid = valid and spaced
	if preview_material == null:
		preview_material = ghost.get_node("Footprint").mesh.material.duplicate()
		ghost.get_node("Footprint").material_override = preview_material
	# A plan placed over piles adopts them: the preview says whether they already cover the build.
	var on_site := materials_inside(Rect2i(start,spec.size))
	var covered: bool = game.global_plan_kind != &"rail" and spec.iron > 0 and on_site.get(&"iron",0) >= spec.iron
	preview_material.albedo_color = (Color(0.35,0.95,0.5,0.55) if covered else Color(1,0.75,0.1,0.5)) if valid else Color(1,0.15,0.1,0.45)
	var site_line := "" if game.global_plan_kind == &"rail" else " · iron on site %d/%d%s" % [on_site.get(&"iron",0),spec.iron," · READY" if covered else ""]
	if not spaced: site_line = " · "+spacing_reason()
	elif not valid and not strip_notice(point,spec.size,game.global_plan_kind).is_empty(): site_line = " · keep the Depot Truck strip clear"
	elif valid and spec.energy > 0 and covering_sources(start,spec.size).is_empty(): site_line += " · no Depot range covers it: nothing pays its energy yet"
	ghost.get_node("Status").text = "%s · %s · %d E / %d I%s" % ["PLAN" if valid else "BLOCKED",spec.title,spec.energy,spec.iron,site_line]
	return valid
## Piles and crates inside a footprint that still hold something (docs/SITE_CONSTRUCTION.md).
func stores_inside(rect: Rect2i) -> Array[Node3D]:
	var result: Array[Node3D] = []
	for group in ["material_piles","supply_crates"]:
		for node in get_tree().get_nodes_in_group(group):
			if not is_instance_valid(node) or node.is_queued_for_deletion() or node.remaining <= 0: continue
			var cell = game.ground.get_tile_at_position(node.global_position)
			if cell != null and rect.has_point(cell): result.append(node)
	return result
func materials_inside(rect: Rect2i) -> Dictionary:
	var result := {}
	for node in stores_inside(rect): result[node.resource_kind] = result.get(node.resource_kind,0)+node.remaining
	return result
## Whether a stockpile's range covers the plan's footprint (its centre).
func source_covers_plan(source, plan: Node3D) -> bool:
	return SupplySource.available(source,"player") and range_covers_footprint(source,plan.start,plan.spec.size)
## The friendly stockpiles whose range covers a footprint, nearest first.
func covering_sources(start: Vector2i, size: Vector2i) -> Array[Node3D]:
	var centre: Vector3 = game.ground.tile_to_world(start)+Vector3(size.x*0.5-0.5,0,size.y*0.5-0.5)
	var result: Array[Node3D] = []
	for source in SupplySource.candidates(get_tree(),centre,"player"):
		if range_covers_footprint(source,start,size): result.append(source)
	return result
## Energy comes from one covering Depot or deployed Cargo vehicle; materials never do.
func plan_energy_source_valid(plan: Node3D, source, due: int) -> bool:
	return source_covers_plan(source,plan) and source.energy >= due
## Stands the building up once a site's work is done. Nothing is spent here: the materials came off
## the site and the energy was charged tick by tick.
func finish_plan(plan: Node3D) -> Node3D:
	if plan.finished or not plan_terrain_valid(plan.start,plan.spec.size,plan.kind,plan) or not plan_spacing_ok(plan): return null
	var payer = plan.payer if is_instance_valid(plan.payer) and plan.payer.is_in_group("depots") else null
	var building = plan.spec.scene.instantiate()
	if plan.kind == &"depot":
		building.initial_energy = 0; building.initial_iron = 0
		building.grant_construction_infantry = true
	elif plan.kind == &"generator": building.rules = supply_rules; building.assigned_depot = payer
	elif plan.kind == &"iron_mine": building.rules = engineering_rules
	else: building.assigned_depot = payer
	building.position = plan.global_position
	if plan.kind == &"rail": game.add_child(building,true)
	else: game.get_node("Entities/Buildings").add_child(building,true)
	return building
## Moves leftover piles and crates off a finished footprint to the nearest free cells around it.
func clear_site(plan: Node3D) -> void:
	var ring: int = maxi(plan.spec.size.x,plan.spec.size.y)/2+1
	for node in stores_inside(plan.footprint()):
		var cell = CrateYard.free_cell(get_tree(),plan.global_position,ring,6)
		if cell != null: node.global_position = game.ground.tile_to_world(cell)
