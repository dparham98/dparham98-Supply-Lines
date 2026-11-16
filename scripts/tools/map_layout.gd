extends RefCounted
## A map's editable layout (docs/BALANCED_MAP.md): a 500 x 500 indexed PNG, one pixel per 1 m cell and one palette
## colour per terrain category. Palette index = the Terrain value in scripts/terrain/terrain_grid.gd.
## scripts/tools/build_map_data.gd turns a layout into the files the game reads.
const SIZE := 500
const NAMES: PackedStringArray = ["grass", "water", "desert", "forest", "mountain", "ore", "coal", "mine site"]
## A mine site (docs/MINE_SITES.md): this many cells across the rock face and this many deep into it, with this many
## rows of open ground kept clear in front for the mine's rails.
const MINE_SITE := 7
const MINE_SITE_SIZE := Vector2i(4, 3)
const MINE_FRONT_DEPTH := 2
const PALETTE: Array[Color] = [
	Color8(98, 132, 60), # 0 grass
	Color8(36, 98, 150), # 1 water
	Color8(222, 190, 104), # 2 desert
	Color8(26, 84, 42), # 3 forest
	Color8(118, 118, 122), # 4 mountain
	Color8(196, 52, 40), # 5 ore (iron)
	Color8(18, 18, 24), # 6 coal
	Color8(236, 122, 28), # 7 mine site
]

## Writes cells as an 8-bit indexed PNG with the palette above. Godot's own PNG writer has no indexed mode.
static func save_indexed_png(cells: PackedByteArray, path: String) -> Error:
	if cells.size() != SIZE*SIZE: return ERR_INVALID_DATA
	var rows := PackedByteArray()
	rows.resize((SIZE+1)*SIZE)
	for z in range(SIZE):
		rows[z*(SIZE+1)] = 0 # filter: none
		for x in range(SIZE): rows[z*(SIZE+1)+1+x] = cells[z*SIZE+x]
	var header := StreamPeerBuffer.new()
	header.big_endian = true
	header.put_u32(SIZE); header.put_u32(SIZE)
	header.put_u8(8); header.put_u8(3); header.put_u8(0); header.put_u8(0); header.put_u8(0)
	var palette := PackedByteArray()
	for colour in PALETTE: palette.append_array([colour.r8, colour.g8, colour.b8])
	var out := StreamPeerBuffer.new()
	out.big_endian = true
	out.put_data(PackedByteArray([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]))
	_chunk(out, "IHDR", header.data_array)
	_chunk(out, "PLTE", palette)
	# COMPRESSION_DEFLATE writes a zlib stream, which is what a PNG holds.
	_chunk(out, "IDAT", rows.compress(FileAccess.COMPRESSION_DEFLATE))
	_chunk(out, "IEND", PackedByteArray())
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null: return FileAccess.get_open_error()
	file.store_buffer(out.data_array)
	file.close()
	return OK

static func _chunk(out: StreamPeerBuffer, type: String, data: PackedByteArray) -> void:
	var body := type.to_ascii_buffer()
	body.append_array(data)
	out.put_u32(data.size())
	out.put_data(body)
	out.put_u32(_crc32(body))

static func _crc32(data: PackedByteArray) -> int:
	var table := PackedInt64Array()
	table.resize(256)
	for n in range(256):
		var c := n
		for k in range(8): c = (0xEDB88320 ^ (c >> 1)) if c & 1 else (c >> 1)
		table[n] = c
	var crc := 0xFFFFFFFF
	for byte in data: crc = table[(crc ^ byte) & 0xFF] ^ (crc >> 8)
	return crc ^ 0xFFFFFFFF

## Reads a layout PNG back into cells. It may have been saved indexed or as plain RGB by a paint program; either
## way every pixel must be exactly one of the palette colours. Returns {cells, errors}.
static func read(path: String) -> Dictionary:
	var errors := PackedStringArray()
	var cells := PackedByteArray()
	var image := Image.load_from_file(ProjectSettings.globalize_path(path))
	if image == null:
		errors.append("Could not read "+path)
		return {"cells": cells, "errors": errors}
	if image.get_size() != Vector2i(SIZE, SIZE):
		errors.append("%s is %d x %d; a layout is %d x %d" % [path, image.get_width(), image.get_height(), SIZE, SIZE])
		return {"cells": cells, "errors": errors}
	image.convert(Image.FORMAT_RGB8)
	var by_colour := {}
	for kind in range(PALETTE.size()): by_colour[PALETTE[kind].r8 << 16 | PALETTE[kind].g8 << 8 | PALETTE[kind].b8] = kind
	var data := image.get_data()
	cells.resize(SIZE*SIZE)
	var strays := 0
	for i in range(SIZE*SIZE):
		var key := data[i*3] << 16 | data[i*3+1] << 8 | data[i*3+2]
		if by_colour.has(key): cells[i] = by_colour[key]
		else:
			strays += 1
			if strays <= 8: errors.append("Pixel %d,%d is #%06x, which is not a palette colour" % [i%SIZE, i/SIZE, key])
	if strays > 8: errors.append("%d pixels in all are not palette colours" % strays)
	return {"cells": cells, "errors": errors}

static func counts(cells: PackedByteArray) -> PackedInt32Array:
	var result := PackedInt32Array()
	result.resize(NAMES.size())
	for kind in range(NAMES.size()): result[kind] = cells.count(kind)
	return result

## The 180 degree turn about the map centre that swaps the two starts.
static func turned(cell: Vector2i) -> Vector2i:
	return Vector2i(SIZE-1-cell.x, SIZE-1-cell.y)

## What is wrong with the mine sites drawn on a layout, as lines of text; empty when all are sound. A site is a
## recess cut into a mountain: a block 4 cells across and 3 deep, with Mountain cells all along its back and both
## its flanks, and open ground (grass or desert) across its front for two rows out, where its rails will run.
static func mine_site_errors(cells: PackedByteArray) -> PackedStringArray:
	var errors := PackedStringArray()
	var seen := {}
	for i in range(SIZE*SIZE):
		if cells[i] != MINE_SITE or seen.has(i): continue
		var patch: Array[int] = [i]
		seen[i] = true
		var low := Vector2i(i%SIZE, i/SIZE)
		var high := low
		var head := 0
		while head < patch.size():
			var at := patch[head]; head += 1
			var x := at%SIZE
			var z := at/SIZE
			low = Vector2i(mini(low.x, x), mini(low.y, z))
			high = Vector2i(maxi(high.x, x), maxi(high.y, z))
			for next in [at-1 if x > 0 else -1, at+1 if x < SIZE-1 else -1, at-SIZE, at+SIZE]:
				if next >= 0 and next < SIZE*SIZE and cells[next] == MINE_SITE and not seen.has(next):
					seen[next] = true
					patch.append(next)
		var size := high-low+Vector2i.ONE
		var upright := size == MINE_SITE_SIZE
		var sideways := size == Vector2i(MINE_SITE_SIZE.y, MINE_SITE_SIZE.x)
		if patch.size() != MINE_SITE_SIZE.x*MINE_SITE_SIZE.y or not (upright or sideways):
			errors.append("Mine site at %d,%d is not a %d x %d block (%d cells)" % [low.x, low.y, MINE_SITE_SIZE.x, MINE_SITE_SIZE.y, patch.size()])
			continue
		var sound := false
		for facing in ([Vector2i(0, 1), Vector2i(0, -1)] if upright else [Vector2i(1, 0), Vector2i(-1, 0)]):
			if site_walled(cells, low, size, facing): sound = true
		if not sound: errors.append("Mine site at %d,%d needs Mountain along its back and both flanks, and grass or desert for %d rows along its front" % [low.x, low.y, MINE_FRONT_DEPTH])
	return errors

## Whether a block that looks out one way has Mountain all along its back and both flanks and open ground across
## its front. The block's own cells are not looked at.
static func site_walled(cells: PackedByteArray, low: Vector2i, size: Vector2i, facing: Vector2i) -> bool:
	var high := low+size-Vector2i.ONE
	for step in range(size.x if facing.x == 0 else size.y):
		var behind := Vector2i(low.x+step, low.y-1 if facing.y > 0 else high.y+1) if facing.x == 0 else Vector2i(low.x-1 if facing.x > 0 else high.x+1, low.y+step)
		if _kind(cells, behind) != 4: return false
		for depth in range(MINE_FRONT_DEPTH):
			var front := Vector2i(low.x+step, high.y+1+depth if facing.y > 0 else low.y-1-depth) if facing.x == 0 else Vector2i(high.x+1+depth if facing.x > 0 else low.x-1-depth, low.y+step)
			if not (_kind(cells, front) in [0, 2]): return false
	# Both flanks: the cells either side of the block, all the way from back to front.
	for step in range(size.y if facing.x == 0 else size.x):
		for flank in ([Vector2i(low.x-1, low.y+step), Vector2i(high.x+1, low.y+step)] if facing.x == 0 else [Vector2i(low.x+step, low.y-1), Vector2i(low.x+step, high.y+1)]):
			if _kind(cells, flank) != 4: return false
	return true

static func _kind(cells: PackedByteArray, cell: Vector2i) -> int:
	return int(cells[cell.y*SIZE+cell.x]) if cell.x >= 0 and cell.y >= 0 and cell.x < SIZE and cell.y < SIZE else -1
