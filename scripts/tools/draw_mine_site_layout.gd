extends SceneTree
# Draws the mine-site trial map (docs/MINE_SITES.md): the balanced map with a few mine sites cut into the sides of
# the mountains nearest each start. Writes assets/maps/mine_sites/layout.png, which scripts/tools/build_map_data.gd
# then turns into the files the game reads:
#   godot --headless --path . --script res://scripts/tools/draw_mine_site_layout.gd
# The sites replace Mountain cells, so the trial map has its own mountain mesh; water and scenery are unchanged.
const MapLayout := preload("res://scripts/tools/map_layout.gd")
const SIZE := 500
const SOURCE := "res://assets/maps/balanced/terrain_cells.bin"
const OUTPUT := "res://assets/maps/mine_sites/layout.png"
# Start A's Depot, as a cell. Start B is the same place turned half a turn about the map's centre.
const START := Vector2i(84, 250)
# Sites keep this far from the start and from each other, in cells, and no further from the start than REACH.
const CLEAR := 14.0
const APART := 12.0
const REACH := 110.0

func _initialize() -> void:
	var cells := FileAccess.get_file_as_bytes(SOURCE)
	if cells.size() != SIZE*SIZE:
		push_error("Unexpected size for "+SOURCE); quit(1); return
	# The nearest sound spot for each way a mine can face, so the trial shows all four.
	var chosen: Array[Vector2i] = []
	var facings: Array[Vector2i] = []
	for facing in [Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)]:
		var best := Vector2i(-1, -1)
		for z in range(8, SIZE-12):
			for x in range(8, SIZE-12):
				var at := Vector2i(x, z)
				var distance := Vector2(at-START).length()
				if distance < CLEAR or distance > REACH or (best.x >= 0 and distance >= Vector2(best-START).length()): continue
				if not fits(cells, at, facing): continue
				var crowded := false
				for other in chosen:
					if Vector2(other-at).length() < APART: crowded = true
				if not crowded: best = at
		if best.x < 0:
			print("No spot for a mine facing ", facing)
			continue
		chosen.append(best)
		facings.append(facing)
		print("Mine site at ", best, " facing ", facing, ", ", snappedf(Vector2(best-START).length(), 0.1), " cells from start A")
	for index in range(chosen.size()):
		var size := block(facings[index])
		for dz in range(size.y):
			for dx in range(size.x):
				var cell := chosen[index]+Vector2i(dx, dz)
				cells[cell.y*SIZE+cell.x] = MapLayout.MINE_SITE
				var twin := MapLayout.turned(cell)
				cells[twin.y*SIZE+twin.x] = MapLayout.MINE_SITE
	var errors := MapLayout.mine_site_errors(cells)
	for line in errors: push_error(line)
	if not errors.is_empty():
		quit(1); return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT.get_base_dir()))
	if MapLayout.save_indexed_png(cells, ProjectSettings.globalize_path(OUTPUT)) != OK:
		push_error("Could not write "+OUTPUT); quit(1); return
	print("MINE_SITE_LAYOUT_DRAWN ", chosen.size()*2, " sites")
	quit()

# The cells a site takes when it looks out one way: 4 across the face and 3 deep.
func block(facing: Vector2i) -> Vector2i:
	return MapLayout.MINE_SITE_SIZE if facing.x == 0 else Vector2i(MapLayout.MINE_SITE_SIZE.y, MapLayout.MINE_SITE_SIZE.x)

# A block of Mountain at a mountain's edge, walled by more Mountain behind and on both flanks, with open ground
# across its front for two rows beyond the strip a site keeps clear, so there is room to reach it.
func fits(cells: PackedByteArray, at: Vector2i, facing: Vector2i) -> bool:
	var size := block(facing)
	for dz in range(size.y):
		for dx in range(size.x):
			if cells[(at.y+dz)*SIZE+at.x+dx] != 4: return false
	if not MapLayout.site_walled(cells, at, size, facing): return false
	for step in range(size.x if facing.x == 0 else size.y):
		for depth in range(MapLayout.MINE_FRONT_DEPTH, MapLayout.MINE_FRONT_DEPTH+2):
			var front := Vector2i(at.x+step, at.y+size.y+depth if facing.y > 0 else at.y-1-depth) if facing.x == 0 else Vector2i(at.x+size.x+depth if facing.x > 0 else at.x-1-depth, at.y+step)
			if not (int(cells[front.y*SIZE+front.x]) in [0, 2]): return false
	return true
