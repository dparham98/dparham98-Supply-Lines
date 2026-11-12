@tool
extends Node3D
## Change these reusable prop scenes, then rebuild to update both editor and game scenery.
var forest_state: ForestStateVisuals
var ore_state: OreStateVisuals

func _ready() -> void:
	if Engine.is_editor_hint():
		set_process(false)
		return
	forest_state = ForestStateVisuals.new()
	forest_state.bind($Ground,get_node_or_null("Landmarks/Forests"),2)
	# The sculpted landscape keeps one tree per cell and draws cleared ground from the same match-local mask.
	forest_state.bind($Ground,get_node_or_null("Landmarks/Landscape/Forest"),1)
	# Trees get the same mask, so they can be cut away in front of a cleared cell. One copy of each material.
	var forest := get_node_or_null("Landmarks/Landscape/Forest")
	if forest != null and $Ground.material_override is ShaderMaterial:
		var copies := {}
		for batch in forest.get_children():
			if not batch is MultiMeshInstance3D or not batch.material_override is ShaderMaterial: continue
			if not copies.has(batch.material_override):
				copies[batch.material_override] = batch.material_override.duplicate()
				copies[batch.material_override].set_shader_parameter("cleared_cells",$Ground.material_override.get_shader_parameter("cleared_cells"))
			batch.material_override = copies[batch.material_override]
	# Ore rocks, old and sculpted, are hidden under mines and mine sites.
	ore_state = OreStateVisuals.new()
	var ore_batches: Array = []
	var old_ore := get_node_or_null("Landmarks/OreDeposits")
	if old_ore != null: ore_batches.append_array(old_ore.get_children())
	var scatter := get_node_or_null("Landmarks/Landscape/Scatter")
	if scatter != null: ore_batches.append_array(scatter.get_children().filter(func(n): return str(n.name).begins_with("Mesh_ore_")))
	if $Ground.has_signal("ore_cover_changed"): ore_state.bind($Ground,ore_batches)
	var sculpted := get_node_or_null("Landmarks/Landscape/Ground") as MeshInstance3D
	if sculpted != null and $Ground.material_override is ShaderMaterial and sculpted.mesh.surface_get_material(0) is ShaderMaterial:
		sculpted.material_override = sculpted.mesh.surface_get_material(0).duplicate()
		sculpted.material_override.set_shader_parameter("cleared_cells",$Ground.material_override.get_shader_parameter("cleared_cells"))

# Felled trees topple over a second or two; this only moves saved batch instances.
func _process(delta: float) -> void:
	if forest_state != null and forest_state.is_felling(): forest_state.advance(delta)

@export_category("Terrain Asset Slots")
@export var tree_scene: PackedScene
@export var mountain_scene: PackedScene
@export var ore_scene: PackedScene
## When set, forests use these patches of trees instead of tree_scene.
@export var forest_tile_scenes: Array[PackedScene] = []
## When set, this sculpted mesh replaces the scattered mountain_scene props.
@export var mountain_mesh: Mesh
## When set, its region is drawn as sculpted landscape (docs/LANDSCAPE_LOOKDEV.md).
@export var landscape: LandscapeSettings
@export var scatter_seed: int = 2817
@export_tool_button("Rebuild terrain scenery", "Reload") var rebuild_action: Callable = rebuild_scenery

func rebuild_scenery() -> void:
	if not tree_scene or not mountain_scene or not ore_scene:
		push_warning("Assign all three terrain asset scenes before rebuilding.")
		return
	var baker = load("res://scripts/tools/terrain_baker.gd").new()
	var output: Node3D = baker.build(tree_scene, mountain_scene, ore_scene, scatter_seed, forest_tile_scenes, mountain_mesh, landscape)
	if output.get_child_count() == 0:
		output.free()
		return
	# Never replace the saved scenery with incomplete backend-generated buffers.
	for batch in output.find_children("*","MultiMeshInstance3D",true,false):
		if batch.multimesh.buffer.size() != batch.multimesh.instance_count*16:
			push_error("Terrain rebuild has incomplete instance data; saved scenery was not changed.")
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
