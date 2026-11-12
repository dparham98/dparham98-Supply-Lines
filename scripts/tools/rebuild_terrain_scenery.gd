extends SceneTree
# Presses Rebuild terrain scenery on terrain.tscn without opening the editor, which rewrites
# scenes/maps/terrain_landmarks.tscn from the map cells and the asset slots:
#   godot --headless --path . --script res://scripts/tools/rebuild_terrain_scenery.gd
# Another map's terrain scene is named after "--": --terrain=res://scenes/maps/balanced_terrain.tscn. It bakes from
# that scene's own cells into its own scenery file (the Ground node's cells_path and the root's landmarks_path).
const ToolArgs := preload("res://scripts/tools/tool_args.gd")
func _initialize() -> void:
	var terrain = load(ToolArgs.value("terrain","res://scenes/maps/terrain.tscn")).instantiate()
	terrain.rebuild_scenery()
	terrain.free()
	print("TERRAIN_SCENERY_REBUILT")
	quit()
