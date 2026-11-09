extends SceneTree
# Packs the eight ground tiles in Blender/Terrain/ground_tiles/textures into the two vertical strips the
# terrain shader reads as texture arrays. Layers 0-3 are grass 01-04 and 4-7 are desert 01-04.
# Run after editing the tiles: godot --headless --path . --script res://scripts/tools/build_ground_tile_arrays.gd
const SOURCE := "res://Blender/Terrain/ground_tiles/textures/"
const OUTPUT := "res://assets/textures/terrain/ground_tiles_%s.png"
const TILE_SIZE := 512
func _initialize() -> void:
	for map in ["albedo","normal"]:
		var strip := Image.create(TILE_SIZE,TILE_SIZE*8,false,Image.FORMAT_RGB8)
		var layer := 0
		for kind in ["grass","desert"]:
			for index in range(1,5):
				var path := ProjectSettings.globalize_path(SOURCE+"tile_%s_%02d_%s.png" % [kind,index,map])
				var tile := Image.load_from_file(path)
				if tile == null or tile.get_size() != Vector2i(TILE_SIZE,TILE_SIZE):
					push_error("Missing or wrong size: "+path); quit(1); return
				tile.convert(Image.FORMAT_RGB8)
				strip.blit_rect(tile,Rect2i(0,0,TILE_SIZE,TILE_SIZE),Vector2i(0,layer*TILE_SIZE))
				layer += 1
		strip.save_png(ProjectSettings.globalize_path(OUTPUT % map))
	print("GROUND_TILE_ARRAYS_BUILT"); quit()
