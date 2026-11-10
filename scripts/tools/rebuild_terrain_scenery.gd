extends SceneTree
# Presses Rebuild terrain scenery on terrain.tscn without opening the editor, which rewrites
# scenes/maps/terrain_landmarks.tscn from the map cells and the asset slots:
#   godot --headless --path . --script res://scripts/tools/rebuild_terrain_scenery.gd
func _initialize() -> void:
	var terrain = load("res://scenes/maps/terrain.tscn").instantiate()
	terrain.rebuild_scenery()
	terrain.free()
	print("TERRAIN_SCENERY_REBUILT")
	quit()
