extends Node3D

@export var health: int = 1000  # HQ health
@export var team: String = "player"  # Team identifier
@export var grid_size: Vector2i = Vector2i(10, 10)  # Tiles occupied (10x10 tiles)
@export var grid_position: Vector2i = Vector2i(10, 10)  # Starting grid position
@export var base_height: float = 5.0  # Height of HQ model
## Author the building at ground level in the world scene.
@export var use_editor_position: bool = true

# Reference to ground node
@onready var ground = get_tree().get_first_node_in_group("terrain_grid")  # Adjust path if needed

func _ready():
	if ground == null: return
	if use_editor_position:
		var center_cell = ground.get_tile_at_position(global_position)
		if center_cell != null: grid_position = center_cell - grid_size / 2
	grid_position = ground.find_buildable_footprint(grid_position, grid_size)
	if grid_position.x < 0:
		push_error("No buildable HQ footprint")
		return
	# Position HQ at center of grid_position tiles
	var tile_size = 1.0  # Match ground's tile_size
	position = Vector3(
		-250.0 + (grid_position.x + grid_size.x / 2.0) * tile_size,  # Center of 10x10 area
		0.0,  # Half height to sit on ground
		-250.0 + (grid_position.y + grid_size.y / 2.0) * tile_size
	)
	
	# Mark tiles as non-buildable
	if ground:
		for x in range(grid_position.x, grid_position.x + grid_size.x):
			for z in range(grid_position.y, grid_position.y + grid_size.y):
				var tile_pos = Vector2i(x, z)
				if ground.has_method("set_tile_feature"):
					ground.set_tile_feature(tile_pos, "buildable", false)
					ground.set_tile_feature(tile_pos, "occupied_by", self.name)
	
	# Print initial state
	print_state()

func _input(event):
	# Press 'P' to print state during gameplay
	if event is InputEventKey and event.pressed and event.keycode == KEY_P:
		print_state()

func print_state():
	# Collect occupied tiles
	var occupied_tiles = []
	for x in range(grid_position.x, grid_position.x + grid_size.x):
		for z in range(grid_position.y, grid_position.y + grid_size.y):
			occupied_tiles.append(Vector2i(x, z))
	
	# Print name and state
	print("HQ Name: ", name)
	print("State:")
	print("  Health: ", health)
	print("  Team: ", team)
	print("  Grid Position: ", grid_position)
	print("  World Position: ", position)
	print("  Grid Size: ", grid_size, " (", grid_size.x * 1.0, "x", grid_size.y * 1.0, " units)")
	print("  Occupied Tiles: ", occupied_tiles)

func take_damage(amount: int):
	health -= amount
	print_state()  # Print state after damage
	if health <= 0:
		queue_free()
		print("HQ destroyed!")
