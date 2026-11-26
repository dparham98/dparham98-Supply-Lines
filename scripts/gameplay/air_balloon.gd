extends "res://scripts/gameplay/unit_agent.gd"
## The Knights' Air Balloon (docs/AIR_BALLOON.md). A Keep launches it with Launch balloon: it lifts off the Keep's
## rooftop dock with the crates packed beside the Keep, flies straight to the point it was sent to over anything,
## comes down and sets the crates there, then is gone. Inside a friendly Keep's range it unloads into that Keep
## instead. It takes no orders and never returns. Any unit can shoot it; shot down, it drops nothing.
const RULES := preload("res://assets/economy/knights_rules.tres")
## What it carries, as {kind, amount}, one entry a crate.
var crates: Array[Dictionary] = []
## Where it was sent.
var destination := Vector3.ZERO
var launched := false
var landed := false
## Height of the model above the ground: from the Keep's dock up to cruise, and down again to land.
var height := 0.0
func _ready() -> void:
	super._ready()
	add_to_group("air_balloons")
	_set_height(cruise_height())
## How high it flies (the Sky-Pavilion flies higher).
func cruise_height() -> float:
	return RULES.balloon_cruise_height
## Lifts off from `dock_height` metres up and makes for `point` with `cargo`.
func launch(point: Vector3, cargo: Array[Dictionary], dock_height: float) -> void:
	crates = cargo
	destination = Vector3(point.x,0,point.z)
	launched = true
	_set_height(dock_height)
	_fly()
	_show_cargo()
## Total carried, by resource.
func cargo_text() -> String:
	var totals := {}
	for crate in crates: totals[crate.kind] = totals.get(crate.kind,0)+crate.amount
	var parts := PackedStringArray()
	for kind in ResourceStockpile.CRATED:
		if totals.has(kind): parts.append("%d %s" % [totals[kind],str(kind).capitalize()])
	return ", ".join(parts) if not parts.is_empty() else "nothing"
func _fly() -> void:
	_stop_route()
	order = "move"
	order_target = null
	source = null
	move_goal = destination
	state = "Flying %s to the drop point" % cargo_text()
## Orders are refused: it flies only where it was sent.
func _farmer_refuses() -> bool:
	state = "A balloon flies only where it was sent"
	return true
func queue_order(_entry: Dictionary) -> void: _farmer_refuses()
func run_order(_entry: Dictionary) -> void: _farmer_refuses()
func _arrived() -> bool:
	return Vector2(global_position.x-destination.x,global_position.z-destination.z).length() < 1.5
func _process(delta: float) -> void:
	super._process(delta)
	if _dead or not launched or landed: return
	var there := _arrived()
	# Stopped short (the HUD's Stop, or a blocked step): carry on to the drop point.
	if not there and order != "move": _fly()
	var target_height: float = 0.0 if there else cruise_height()
	_set_height(move_toward(height,target_height,RULES.balloon_climb_rate*delta))
	if there:
		state = "Landing"
		if height <= 0.01: _land()
func _set_height(value: float) -> void:
	height = value
	$Visuals.position.y = height
## Sets the crates down, or unloads them into a friendly Keep whose range it landed in, and leaves the map.
func _land() -> void:
	landed = true
	var keep := covering_keep()
	var stored := 0
	var set_down := 0
	for crate in crates:
		var left: int = crate.amount
		if keep != null:
			var taken: int = keep.stockpile.deposit(crate.kind,left)
			stored += taken
			left -= taken
		if left <= 0: continue
		var cell = CrateYard.free_cell(get_tree(),global_position,0,8)
		if cell == null: continue
		CrateYard.spawn(get_tree(),cell,crate.kind,left,team)
		set_down += 1
	if keep != null: game.notify("Air Balloon unloaded %d into %s%s." % [stored,keep.name," and set down %d crates" % set_down if set_down > 0 else ""],team)
	else: game.notify("Air Balloon set down %d crates: %s." % [set_down,cargo_text()],team)
	crates.clear()
	remove_from_group("units")
	remove_from_group("enemies")
	queue_free()
## A standing friendly Keep whose range covers where it is, or null.
func covering_keep() -> Node3D:
	for keep in get_tree().get_nodes_in_group("keeps"):
		if SupplySource.covers(keep,global_position,team): return keep
	return null
func _show_cargo() -> void:
	var label := get_node_or_null("Cargo") as Label3D
	if label == null: return
	label.visible = not crates.is_empty()
	label.text = cargo_text()
func _update_display() -> void:
	super._update_display()
	_show_cargo()
