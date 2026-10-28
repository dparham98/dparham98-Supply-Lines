extends Node3D

@export var health: int = 100  # Infantry health
@export var team: String = "player"  # Team identifier
@export var grid_position: Vector2i = Vector2i(22, 22)  # Starting grid position
@export var attack_range: float = 10.0  # Range in world units
@export var attack_damage: int = 10  # Damage per shot
@export var attack_cooldown: float = 1.0  # Seconds between attacks
@export var unit_height: float = 1.0  # Height of unit model
@export var move_speed: float = 5.0  # Units per second
## Use the instance position authored in the world scene; invalid positions move to nearby land.
@export var use_editor_position: bool = true

var can_attack: bool = true  # Cooldown tracker
var tile_size: float = 1.0  # Match ground's tile_size
@onready var ground = get_tree().get_first_node_in_group("terrain_grid")  # Ground node
var initialized: bool = false  # Delay scanning
var init_timer: float = 0.5  # Delay for scene setup
var is_selected: bool = false  # Selection state
var movement_path: Array[Vector3] = []
var is_moving: bool = false  # Movement state
var target_position: Vector3  # Move target
var attack_move_active: bool = false  # Attack-move mode
var attack_move_target: Vector3  # Attack-move target
var mesh_instance: MeshInstance3D  # Reference to mesh

func _ready():
	if ground == null:
		set_process(false)
		return
	if use_editor_position:
		var authored_cell = ground.get_tile_at_position(global_position)
		if authored_cell != null: grid_position = authored_cell
	grid_position = ground.find_nearest_open_tile(grid_position)
	ground.set_tile_feature(grid_position, "buildable", false)
	ground.set_tile_feature(grid_position, "occupied_by", self.name)
	mesh_instance = find_child("Body", true, false) as MeshInstance3D
	# Position unit
	position = Vector3(
		-250.0 + (grid_position.x + 0.5) * tile_size,
		0.0,
		-250.0 + (grid_position.y + 0.5) * tile_size
	)
	
	# Mark tile after delay
	if ground and ground.has_method("set_tile_feature"):
		await get_tree().create_timer(0.1).timeout
		ground.set_tile_feature(grid_position, "buildable", false)
		ground.set_tile_feature(grid_position, "occupied_by", self.name)
	else:
		print("Error: Ground node not found or missing set_tile_feature")
	
	# Add to units group
	add_to_group("units")
	print_state()
	
	# Check for enemy
	var enemy = get_node_or_null("../Enemy")
	print("Enemy check: ", enemy, " team: ", enemy.team if enemy else "none", 
		  " position: ", enemy.position if enemy else "none")
	print("Infantry position: ", position, " grid: ", grid_position)

func _input(event):
	if ground == null or team != "player": return
	# Right-click for move command
	if event.is_action_pressed("move") and is_selected:
		var target_tile = get_target_tile()
		if target_tile and ground.is_tile_valid(target_tile):
			var target_world = Vector3(
				-250.0 + (target_tile.x + 0.5) * tile_size,
				0.0,
				-250.0 + (target_tile.y + 0.5) * tile_size
			)
			start_move(target_world, target_tile)
			attack_move_active = false
			print("Move command to tile: ", target_tile)
	
	# 'A' for attack-move
	if event.is_action_pressed("Attack") and is_selected:
		attack_move_active = true
		print("Attack-move mode activated")
	
	# Left-click for attack-move target
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed and attack_move_active and is_selected:
		var target_tile = get_target_tile()
		if target_tile and ground.is_tile_valid(target_tile):
			var target_world = Vector3(
				-250.0 + (target_tile.x + 0.5) * tile_size,
				0.0,
				-250.0 + (target_tile.y + 0.5) * tile_size
			)
			start_attack_move(target_world, target_tile)
			attack_move_active = false
			print("Attack-move command to tile: ", target_tile)
			get_viewport().set_input_as_handled()

func _process(delta):
	# Cooldown
	if not can_attack:
		attack_cooldown -= delta
		if attack_cooldown <= 0:
			can_attack = true
			attack_cooldown = 1.0
	
	# Delay initialization
	if not initialized:
		init_timer -= delta
		if init_timer <= 0:
			initialized = true
			ground.print_tile_state(Vector2i(22, 22))
			ground.print_tile_state(Vector2i(25, 25))
	
	# Handle movement
	if is_moving and is_selected:
		var direction = (target_position - position).normalized()
		var distance = position.distance_to(target_position)
		var step = move_speed * delta
		if distance > step:
			position += direction * step
		else:
			position = target_position
			if not movement_path.is_empty():
				target_position = movement_path.pop_front()
			else:
				is_moving = false
				update_grid_position()
			print("Reached target: ", grid_position)
	
	# Auto-attack
	if can_attack and initialized and is_selected:
		var target = find_nearest_enemy()
		if target and is_instance_valid(target):
			var distance = position.distance_to(target.position)
			print("Auto-attack checking: ", target.name, " distance: ", distance)
			if distance <= attack_range:
				if attack_move_active or is_moving:
					is_moving = false  # Stop moving to attack
					print("Stopping movement to attack: ", target.name)
				fire_projectile(target.position, target)

func print_state():
	print("Unit Name: ", name)
	print("State:")
	print("  Health: ", health)
	print("  Team: ", team)
	print("  Grid Position: ", grid_position)
	print("  World Position: ", position)
	print("  Attack Range: ", attack_range)
	print("  Attack Damage: ", attack_damage)
	print("  Attack Cooldown: ", attack_cooldown)
	print("  Selected: ", is_selected)
	print("  Moving: ", is_moving, " Attack-Move: ", attack_move_active)

func get_target_tile() -> Variant:
	var camera = get_viewport().get_camera_3d()
	if not camera:
		print("Error: No camera found")
		return null
	var mouse_pos = get_viewport().get_mouse_position()
	var from = camera.project_ray_origin(mouse_pos)
	var to = from + camera.project_ray_normal(mouse_pos) * 1000.0
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(from, to)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	query.collision_mask = 1
	var result = space_state.intersect_ray(query)
	
	if result and result.collider:
		print("Raycast hit: ", result.collider.name, " at ", result.position)
		if result.collider.get_parent() == ground or result.collider == ground:
			var world_pos = result.position
			return ground.get_tile_at_position(world_pos)
	print("Raycast failed, result: ", result)
	return null

func is_target_in_range(target_grid_pos: Vector2i) -> bool:
	var target_world_pos = Vector3(
		-250.0 + (target_grid_pos.x + 0.5) * tile_size,
		0.0,
		-250.0 + (target_grid_pos.y + 0.5) * tile_size
	)
	var distance = position.distance_to(target_world_pos)
	print("Target distance: ", distance)
	return distance <= attack_range

func find_nearest_enemy() -> Node3D:
	var enemies = get_tree().get_nodes_in_group("enemies")
	var nearest: Node3D = null
	var min_distance = attack_range + 1.0
	
	print("Scanning enemies: ", enemies.size())
	for enemy in enemies:
		if is_instance_valid(enemy) and enemy != self:
			var enemy_team = enemy.team if "team" in enemy else "unknown"
			print("Enemy: ", enemy.name, " distance: ", position.distance_to(enemy.position), 
				  " team: ", enemy_team, " groups: ", enemy.get_groups())
			if enemy_team != team and enemy_team != "unknown" and position.distance_to(enemy.position) < min_distance:
				min_distance = position.distance_to(enemy.position)
				nearest = enemy
	if not nearest:
		print("No valid enemy found")
		if attack_move_active and not is_moving:
			is_moving = true
			# Keep the current terrain-safe waypoint when resuming.
			print("Resuming attack-move to: ", attack_move_target)
	else:
		print("Nearest enemy: ", nearest.name)
	return nearest

func fire_projectile(target_pos: Vector3, target: Node3D = null):
	can_attack = false
	var projectile = MeshInstance3D.new()
	projectile.mesh = BoxMesh.new()
	projectile.mesh.size = Vector3(0.5, 0.5, 0.5)
	var material = StandardMaterial3D.new()
	material.albedo_color = Color.YELLOW
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	projectile.set_surface_override_material(0, material)
	get_parent().add_child(projectile)
	
	var start_pos = position + Vector3(0, unit_height, 0)
	projectile.position = start_pos
	target_pos.y = unit_height
	
	print("Projectile start: ", start_pos, " target: ", target_pos)
	var tween = create_tween()
	tween.tween_property(projectile, "position", target_pos, 0.5)
	tween.tween_callback(func():
		projectile.queue_free()
		print("Projectile hit at: ", target_pos)
		if target and is_instance_valid(target):
			if target.has_method("take_damage"):
				target.take_damage(attack_damage)
				print("Dealt ", attack_damage, " damage to ", target.name)
		if attack_move_active and not is_moving and not is_instance_valid(target):
			is_moving = true
			# Keep the current terrain-safe waypoint when resuming.
			print("Resuming attack-move to: ", attack_move_target)
	)

func take_damage(amount: int):
	health -= amount
	print_state()
	if health <= 0:
		if ground and ground.has_method("set_tile_feature"):
			ground.set_tile_feature(grid_position, "buildable", true)
			ground.set_tile_feature(grid_position, "occupied_by", null)
		queue_free()
		print("Infantry destroyed!")

func start_move(target_world: Vector3, target_tile: Vector2i):
	if not ground.is_tile_valid(target_tile): return
	var current_tile = ground.get_tile_at_position(position)
	if current_tile == null: return
	var route: Array[Vector2i] = ground.get_terrain_path(current_tile, target_tile)
	if route.size() < 2: return
	movement_path.clear()
	for i in range(1, route.size()):
		movement_path.append(ground.tile_to_world(route[i], 0.0))
	ground.set_tile_feature(grid_position, "buildable", true)
	ground.set_tile_feature(grid_position, "occupied_by", null)
	grid_position = target_tile
	ground.set_tile_feature(grid_position, "buildable", false)
	ground.set_tile_feature(grid_position, "occupied_by", self.name)
	target_position = movement_path.pop_front()
	is_moving = true

func start_attack_move(target_world: Vector3, target_tile: Vector2i):
	start_move(target_world, target_tile)
	attack_move_target = target_world

func update_grid_position():
	var new_grid = ground.get_tile_at_position(position)
	if new_grid:
		ground.set_tile_feature(grid_position, "buildable", true)
		ground.set_tile_feature(grid_position, "occupied_by", null)
		grid_position = new_grid
		ground.set_tile_feature(grid_position, "buildable", false)
		ground.set_tile_feature(grid_position, "occupied_by", self.name)

func set_selected(value: bool) -> void:
	is_selected = value
	var ring := get_node_or_null("SelectionRing") as Node3D
	if ring: ring.visible = value
