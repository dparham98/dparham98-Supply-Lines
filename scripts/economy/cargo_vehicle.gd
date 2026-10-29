extends "res://scripts/gameplay/unit_agent.gd"
@export var supply_rules: SupplyRules
@export var mobile_rules: MobileSupplyRules
var deployed := false
var supply_transition := ""
var supply_timer := 0.0
var storage_capacity: int:
	get: return stockpile.capacity
var energy: int:
	get: return carried_energy
var iron: int:
	get: return carried_iron
var wood: int:
	get: return carried_wood
var coal: int:
	get: return carried_coal
var dropoff_range: float:
	get: return mobile_rules.dropoff_radius()
func supplies_available() -> bool:
	if is_in_group("rail_trains") and not get_tree().get_first_node_in_group("rail_network").friendly(grid_position,team): return false
	return deployed and supply_transition.is_empty() and health > 0 and not _dead and (not route_active or route_paused) and _route.is_empty() and _moving_to.x < 0
func spend_local(energy_cost: int, iron_cost: int) -> bool:
	return supplies_available() and stockpile.spend({&"energy":energy_cost,&"iron":iron_cost})
func deploy_supplies() -> bool:
	if _dead or health <= 0 or deployed or not supply_transition.is_empty(): return false
	if is_in_group("rail_trains") and not get_tree().get_first_node_in_group("rail_network").friendly(grid_position,team): return false
	if route_active: pause_supply_route()
	else: _stop_route()
	order = "idle"
	supply_transition = "deploying"; supply_timer = 0
	return true
func pack_supplies() -> void:
	if not deployed and supply_transition != "deploying": return
	deployed = false # Withdraw availability before a movement order can be processed.
	supply_transition = "packing"; supply_timer = 0
func advance_supplies(delta: float) -> bool:
	if supply_transition.is_empty(): return false
	supply_timer += delta
	var duration: float = mobile_rules.deploy_seconds if supply_transition == "deploying" else mobile_rules.pack_seconds
	state = "%s supplies · %.1fs" % [supply_transition.capitalize(),maxf(0,duration-supply_timer)]
	if supply_timer >= duration:
		deployed = supply_transition == "deploying"
		supply_transition = ""; supply_timer = 0
		state = "Supplies deployed" if deployed else "Supplies packed"
	_update_display()
	return true

@export var initial_energy := 0
@export var initial_iron := 0
@export var initial_wood := 0
@export var initial_coal := 0
var origin_depot: Node3D
var destination_depot: Node3D
var stockpile := ResourceStockpile.new(100)
var carried_energy: int:
	get: return stockpile.amount(&"energy")
	set(value): stockpile.set_amount(&"energy",value)
var carried_iron: int:
	get: return stockpile.amount(&"iron")
	set(value): stockpile.set_amount(&"iron",value)
var carried_wood: int:
	get: return stockpile.amount(&"wood")
	set(value): stockpile.set_amount(&"wood",value)
var carried_coal: int:
	get: return stockpile.amount(&"coal")
	set(value): stockpile.set_amount(&"coal",value)
var requested_coal := 0
var requested_energy := 0
var requested_iron := 0
var requested_wood := 0
var repeating := false
var route_error := ""
var route_active := false
var route_paused := false
var stage := "loading"
var transfer_timer := 0.0
func _ready() -> void:
	stockpile.resize(supply_rules.cargo_capacity)
	stockpile.deposit(&"energy",initial_energy); stockpile.deposit(&"iron",initial_iron)
	stockpile.deposit(&"wood",initial_wood); stockpile.deposit(&"coal",initial_coal)
	is_cargo_vehicle = true
	can_gather = false; can_capture_depots = false
	add_to_group("mobile_supplies")
	max_health = supply_rules.cargo_health
	move_speed = supply_rules.cargo_speed
	super._ready()
func friendly_route_depot(node) -> bool:
	return is_instance_valid(node) and node.is_inside_tree() and not node.is_queued_for_deletion() and node.is_in_group("depots") and node.team == team and node.health > 0
func endpoints_friendly() -> bool:
	return friendly_route_depot(origin_depot) and friendly_route_depot(destination_depot)
func route_request_valid(origin, destination, energy: int, iron: int, wood: int, coal: int) -> bool:
	route_error = ""
	if _dead or health <= 0 or is_queued_for_deletion(): route_error = "Vehicle is unavailable."
	elif not friendly_route_depot(origin) or not friendly_route_depot(destination): route_error = "Choose two living friendly Depots."
	elif origin == destination: route_error = "Choose different loading and unloading Depots."
	elif energy < 0 or iron < 0 or wood < 0 or coal < 0: route_error = "Cargo amounts cannot be negative."
	elif energy+iron+wood+coal <= 0: route_error = "Choose at least one cargo unit to load."
	elif energy+iron+wood+coal > stockpile.capacity: route_error = "Combined cargo exceeds this vehicle's %d-unit capacity." % stockpile.capacity
	return route_error.is_empty()
func start_supply_route(origin: Node3D, destination: Node3D, energy: int, iron: int, repeat_route: bool, wood: int = 0, coal: int = 0) -> bool:
	# Assignment has no distance, coverage, current stock or current-path prerequisite.
	if not route_request_valid(origin,destination,energy,iron,wood,coal): return false
	order_queue.clear()
	pack_supplies()
	_disconnect_endpoints()
	_stop_route()
	origin_depot = origin
	destination_depot = destination
	origin_depot.ownership_changed.connect(_endpoint_changed)
	destination_depot.ownership_changed.connect(_endpoint_changed)
	origin_depot.tree_exiting.connect(_endpoint_changed)
	destination_depot.tree_exiting.connect(_endpoint_changed)
	requested_energy = energy
	requested_iron = iron
	requested_wood = wood
	requested_coal = coal
	repeating = repeat_route
	route_active = true
	route_paused = false
	stage = "unloading" if stockpile.total() > 0 else "loading"
	transfer_timer = 0
	order = "supply"
	state = "Route assigned · to %s" % (destination.name if stage == "unloading" else origin.name)
	return true
func _disconnect_endpoints() -> void:
	for depot in [origin_depot,destination_depot]:
		if not is_instance_valid(depot): continue
		if depot.ownership_changed.is_connected(_endpoint_changed): depot.ownership_changed.disconnect(_endpoint_changed)
		if depot.tree_exiting.is_connected(_endpoint_changed): depot.tree_exiting.disconnect(_endpoint_changed)
func _endpoint_changed() -> void:
	if route_active: pause_supply_route()
func pause_supply_route() -> void:
	_stop_route()
	route_paused = true
	transfer_timer = 0
	state = "Route paused · cargo retained"
func resume_supply_route() -> bool:
	if _dead or health <= 0: route_error = "Vehicle is unavailable."; return false
	if not route_active: route_error = "No delivery route is assigned."; return false
	if not endpoints_friendly(): route_error = "Both route endpoints must be living friendly Depots."; return false
	route_error = ""
	pack_supplies()
	route_paused = false
	state = "Route resumed"
	return true
func cancel_supply_route() -> void:
	_stop_route()
	_disconnect_endpoints()
	route_active = false
	route_paused = false
	transfer_timer = 0
	order = "idle"
	state = "Route cancelled · cargo retained"
func command_move(point: Vector3) -> void:
	pack_supplies()
	cancel_supply_route()
	super.command_move(point)
func command_return(_target: Node3D = null) -> void:
	game.notify("Use the Supply panel to choose explicit cargo endpoints.")
func _process(delta: float) -> void:
	if _dead: return
	fuel_tick(delta)
	if advance_supplies(delta): return
	$SupplyRadius.visible = supplies_available() and (is_selected or game.get_node("DepotNetwork").selected == self)
	$SupplyRadius.scale = Vector3.ONE*mobile_rules.supply_radius()
	if supplies_available():
		state = "Supplies deployed"
		_update_display()
		return
	if not route_active:
		_order_process(delta)
		return
	if not endpoints_friendly():
		if not route_paused: pause_supply_route()
	if route_paused:
		_update_display()
		return
	_retry = maxf(0,_retry-delta)
	var target = origin_depot if stage == "loading" else destination_depot
	if not _route.is_empty() or _moving_to.x >= 0:
		_walk(delta)
		_update_display()
		return
	if global_position.distance_to(target.global_position) > target.dropoff_range:
		transfer_timer = 0
		if _retry <= 0:
			state = "To %s · %s" % [target.name,stage]
			if not _route_to_interaction(target,target.dropoff_range): state = "Route blocked · retrying"
	else:
		if stage == "unloading" and destination_depot.stockpile.space() <= 0:
			transfer_timer = 0
			state = "Destination full · cargo retained"
			_update_display()
			return
		state = "%s · %.1fs" % [stage,supply_rules.transfer_seconds-transfer_timer]
		transfer_timer += delta
		if transfer_timer >= supply_rules.transfer_seconds:
			transfer_timer = 0
			if stage == "loading":
				var maxima := [requested_energy,requested_iron,requested_wood,requested_coal]
				for i in range(ResourceStockpile.KINDS.size()):
					ResourceStockpile.transfer(origin_depot.stockpile,stockpile,ResourceStockpile.KINDS[i],maxima[i])
				if stockpile.total() > 0: stage = "unloading"
				else: state = "Waiting for source stock"
			else:
				for kind in ResourceStockpile.KINDS:
					var moved: int = ResourceStockpile.transfer(stockpile,destination_depot.stockpile,kind,stockpile.amount(kind))
					if moved > 0: game.delivered(destination_depot,kind,moved)
				if stockpile.total() > 0: state = "Destination full · cargo retained"
				elif repeating: stage = "loading"
				else:
					cancel_supply_route()
					state = "Delivery complete"
	_update_display()
func _update_display() -> void:
	$SupplyRadius.visible = supplies_available() and (is_selected or game.get_node("DepotNetwork").selected == self)
	$SupplyRadius.scale = Vector3.ONE*mobile_rules.supply_radius()
	$Status.text = "CARGO · %d/%d · %s" % [health,max_health,state]
	$Cargo.visible = stockpile.total() > 0
	$Cargo.text = "E %d / I %d / W %d / C %d" % [carried_energy,carried_iron,carried_wood,carried_coal]
func _exit_tree() -> void:
	_disconnect_endpoints()
	super._exit_tree()
