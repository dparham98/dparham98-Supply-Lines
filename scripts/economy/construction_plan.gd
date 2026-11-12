extends Node3D
## A queued build (docs/SITE_CONSTRUCTION.md). Its materials must reach the site as piles or crates
## inside the footprint; Infantry ordered to construct build them in at their work pace while one
## covering stockpile pays the energy tick by tick. Rails keep the Depot-paid instant rule.
## While pending there is no terrain claim, collision body or resource reservation.
var kind: StringName
var spec: Dictionary
var start := Vector2i.ZERO
## The pinned energy payer, or the one latched when construction starts.
var payer: Node3D
var pinned := false
var state := "Waiting for materials on site"
var finished := false
var elapsed := 0.0
## Materials built in so far, by kind, and energy charged so far.
var added := {}
var energy_paid := 0
## How close a vehicle or worker must get to the plan's centre to use the site.
var dropoff_range := 3.0
const TINT_WAITING := Color(1,0.72,0.12,0.65)
const TINT_READY := Color(0.35,0.95,0.5,0.7)
const TINT_BUILDING := Color(0.45,0.8,1,0.7)
@onready var network = get_tree().get_first_node_in_group("skirmish").get_node("DepotNetwork")
func _ready() -> void:
	add_to_group("construction_plans")
	var size: Vector2i = spec.size
	$Visuals/Grid.scale = Vector3(size.x,1,size.y)
	$Visuals/Grid.position = Vector3(size.x*0.5-0.5-size.x/2,0.2,size.y*0.5-0.5-size.y/2)
	$Visuals/Grid.material_override = $Visuals/Grid.mesh.material.duplicate()
	$Visuals/Grid.material_override.set_shader_parameter("cells",Vector2(size))
	$Label.position = $Visuals/Grid.position+Vector3(0,1.5,0)
	dropoff_range = maxi(size.x,size.y)*0.5+2.5
	_add_site_model()
	refresh_label()
func _process(delta: float) -> void:
	elapsed += delta
	if elapsed < 0.25: return
	elapsed = 0
	if kind == &"rail": complete_from_stock(); return
	refresh_state()
## Material kinds and amounts the whole build needs.
func materials() -> Dictionary:
	var result := {}
	if spec.get("iron",0) > 0: result[&"iron"] = spec.iron
	if spec.get("wood",0) > 0: result[&"wood"] = spec.wood
	return result
func needed(material: StringName) -> int:
	return maxi(0,materials().get(material,0)-added.get(material,0))
func all_added() -> bool:
	for material in materials():
		if needed(material) > 0: return false
	return true
func next_material() -> StringName:
	for material in materials():
		if needed(material) > 0: return material
	return &""
func footprint() -> Rect2i:
	return Rect2i(start,spec.size)
func inside(point: Vector3) -> bool:
	var cell = network.game.ground.get_tile_at_position(point)
	return cell != null and footprint().has_point(cell)
## Piles and crates inside the footprint that still hold something.
func site_stores() -> Array[Node3D]:
	return network.stores_inside(footprint())
func on_site(material: StringName) -> int:
	var total := 0
	for node in site_stores():
		if node.resource_kind == material: total += node.remaining
	return total
## Whether the piles on the site hold everything the build still needs.
func materials_covered() -> bool:
	for material in materials():
		if on_site(material) < needed(material): return false
	return true
## What is still worth delivering: needed beyond what already lies on the site.
func shortfall(material: StringName) -> int:
	return maxi(0,needed(material)-on_site(material))
## Adds materials to the site: into a pile of that kind inside the footprint, or a new pile on a
## free footprint cell. Takes only the shortfall; returns what it took.
func receive(material: StringName, amount: int) -> int:
	var accepted := mini(amount,shortfall(material))
	if accepted <= 0: return 0
	for node in site_stores():
		if node.is_in_group("material_piles") and node.resource_kind == material:
			node.add(accepted)
			refresh_label()
			return accepted
	var pile = network.game.pile_scene.instantiate()
	pile.material_kind = str(material); pile.amount = accepted
	pile.position = pile_point()
	network.game.get_node("Entities/Resources").add_child(pile,true)
	refresh_label()
	return accepted
## The footprint cell nearest the centre without a pile on it, else the centre.
func pile_point() -> Vector3:
	var ground = network.game.ground
	var taken := {}
	for node in site_stores():
		var cell = ground.get_tile_at_position(node.global_position)
		if cell != null: taken[cell] = true
	var best: Vector3 = global_position
	var best_distance := INF
	for x in range(start.x,start.x+spec.size.x):
		for z in range(start.y,start.y+spec.size.y):
			var cell := Vector2i(x,z)
			if taken.has(cell): continue
			var point: Vector3 = ground.tile_to_world(cell)
			var d := point.distance_squared_to(global_position)
			if d < best_distance: best = point; best_distance = d
	return best
## Takes materials from the site's piles and crates; returns what it got.
func take(material: StringName, amount: int) -> int:
	var got := 0
	for node in site_stores():
		if got >= amount: break
		if node.resource_kind == material: got += node.extract(amount-got)
	return got
## Energy owed once `step` more materials are built in: the share of the energy cost that keeps
## pace with the materials, so the last step settles the whole cost.
func energy_due(step: int) -> int:
	var total := 0
	var done := 0
	for material in materials():
		total += materials()[material]
		done += added.get(material,0)
	if total == 0: return spec.energy-energy_paid
	return maxi(0,ceili(spec.energy*float(done+step)/total)-energy_paid)
## One construction tick by a worker: builds in up to `amount` materials from the site and charges
## the energy share. Returns "" on progress, else the reason it waited (also set as the state).
func work(_unit: Node3D, amount: int) -> String:
	if finished: return "Built"
	if not network.plan_terrain_valid(start,spec.size,kind):
		state = "Waiting for footprint to clear"; refresh_label(); return state
	var material := next_material()
	var step := mini(amount,needed(material)) if not material.is_empty() else 0
	if step > 0 and on_site(material) < step:
		state = "Waiting for %s on site" % material; refresh_label(); return state
	var due := energy_due(step)
	var source := energy_payer(due)
	if due > 0 and source == null:
		state = "Waiting for energy from %s" % (payer.name if is_instance_valid(payer) else "a covering stockpile"); refresh_label(); return state
	if due > 0:
		if not source.spend_local(due,0): state = "Waiting for energy"; refresh_label(); return state
		energy_paid += due
	if step > 0:
		take(material,step)
		added[material] = added.get(material,0)+step
	state = "Constructing · %d%%" % progress_percent()
	refresh_label()
	if all_added() and energy_paid >= spec.energy: finish()
	return ""
func progress_percent() -> int:
	return int(100.0*progress_fraction())
## Share of the build done, 0..1: materials built in and energy paid.
func progress_fraction() -> float:
	var total: int = spec.energy
	var done := energy_paid
	for material in materials():
		total += materials()[material]; done += added.get(material,0)
	return 1.0 if total == 0 else float(done)/total
## A building model with a construction clip stands on the site and goes up with the work
## (docs/BARRACKS_MODEL.md). It is the building's own saved model scene; others show only the grid.
func _add_site_model() -> void:
	var scene: PackedScene = spec.get("model")
	if scene == null: return
	var model := scene.instantiate()
	if not model.has_method("show_construction"):
		model.free()
		return
	model.name = "Model"
	model.position = Vector3($Visuals/Grid.position.x,0,$Visuals/Grid.position.z)
	$Visuals.add_child(model)
## The stockpile paying energy: the pinned one, or the first covering one able to pay the whole
## remaining energy, latched so one payer sees the build through.
func energy_payer(due: int) -> Node3D:
	if pinned or is_instance_valid(payer):
		return payer if network.plan_energy_source_valid(self,payer,due) else null
	for source in SupplySource.candidates(get_tree(),global_position,"player"):
		if network.plan_energy_source_valid(self,source,spec.energy-energy_paid):
			payer = source
			return source
	return null
## Periodic state refresh while nobody is working on the site.
func refresh_state() -> void:
	if finished or state.begins_with("Constructing"): return
	if not network.plan_terrain_valid(start,spec.size,kind): state = "Waiting for footprint to clear"
	elif not materials_covered(): state = "Waiting for materials on site"
	elif energy_payer(energy_due(0) if spec.energy > 0 else 0) == null and spec.energy > energy_paid: state = "Waiting for energy coverage"
	else: state = "Materials on site · order Infantry to construct"
	refresh_label()
func finish() -> Node3D:
	var building = network.finish_plan(self)
	if building == null: return null
	finished = true
	remove_from_group("construction_plans")
	network.clear_site(self)
	if network.game.selected_building == self:
		network.game.selected_building = building if kind != &"rail" else null
		if kind == &"depot": network.select_depot(building)
	network.game.notify("%s built." % spec.title)
	queue_free()
	return building
## Instant completion paid in full from one covering stockpile: the rail rule, and the shortcut the
## tests and playtest tools use to stand buildings up. Buildings in play go through work().
func complete_from_stock() -> Node3D:
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
		network.clear_site(self)
		if network.game.selected_building == self:
			network.game.selected_building = building if kind != &"rail" else null
			if kind == &"depot": network.select_depot(building)
		network.game.notify("%s built from %s local stock." % [spec.title,source.name])
		queue_free()
	return building
## Site line for labels and panels, for example "Iron on site 25/45 · built 0/45".
func site_text() -> String:
	var parts: PackedStringArray = []
	for material in materials():
		parts.append("%s on site %d/%d · built %d/%d" % [str(material).capitalize(),on_site(material),needed(material),added.get(material,0),materials()[material]])
	return " · ".join(parts) if not parts.is_empty() else "No materials needed"
func refresh_label() -> void:
	if kind == &"rail":
		$Label.text = "PLAN · %s · %d E / %d I\n%s" % [spec.title,spec.energy,spec.iron,state]
		return
	$Label.text = "PLAN · %s · %d E / %d I\n%s\n%s" % [spec.title,spec.energy,spec.iron,site_text(),state]
	var model := get_node_or_null("Visuals/Model")
	if model != null: model.show_construction(progress_fraction())
	var tint := TINT_WAITING
	if state.begins_with("Constructing"): tint = TINT_BUILDING
	elif materials_covered(): tint = TINT_READY
	$Visuals/Grid.material_override.set_shader_parameter("tint",tint)
	$Label.modulate = Color(tint.r,tint.g,tint.b,1)
func cancel() -> void:
	if finished: return
	finished = true
	remove_from_group("construction_plans")
	if network.game.selected_building == self: network.game.selected_building = null
	network.game.notify("Construction plan cancelled. Materials on the site stay as piles.")
	queue_free()
