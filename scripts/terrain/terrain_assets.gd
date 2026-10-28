@tool
extends Node3D
## Change these reusable prop scenes, then rebuild to update both editor and game scenery.
var forest_state: ForestStateVisuals

func _ready() -> void:
	if Engine.is_editor_hint(): return
	forest_state = ForestStateVisuals.new()
	forest_state.bind($Ground,get_node_or_null("Landmarks/Forests"))

@export_category("Terrain Asset Slots")
@export var tree_scene: PackedScene
@export var mountain_scene: PackedScene
@export var ore_scene: PackedScene
@export var scatter_seed: int = 2817
@export_tool_button("Rebuild terrain scenery", "Reload") var rebuild_action: Callable = rebuild_scenery

func rebuild_scenery() -> void:
	if not tree_scene or not mountain_scene or not ore_scene:
		push_warning("Assign all three terrain asset scenes before rebuilding.")
		return
	var baker = load("res://scripts/tools/terrain_baker.gd").new()
	var output: Node3D = baker.build(tree_scene, mountain_scene, ore_scene, scatter_seed)
	if output.get_child_count() == 0:
		output.free()
		return
	var packed := PackedScene.new()
	if packed.pack(output) != OK: return
	if ResourceSaver.save(packed, "res://scenes/maps/terrain_landmarks.tscn") != OK: return
	packed = ResourceLoader.load("res://scenes/maps/terrain_landmarks.tscn", "PackedScene", ResourceLoader.CACHE_MODE_IGNORE)
	output.free()
	var old := get_node_or_null("Landmarks")
	if old:
		remove_child(old)
		old.queue_free()
	var replacement := packed.instantiate()
	replacement.name = "Landmarks"
	add_child(replacement)
	replacement.owner = owner if owner else self
	print("Terrain scenery rebuilt and saved. Save the scene to keep changed asset slots.")
