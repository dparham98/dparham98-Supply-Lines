extends RefCounted
## A map's editable layout (docs/BALANCED_MAP.md): a 500 x 500 indexed PNG, one pixel per 1 m cell and one palette
## colour per terrain category. Palette index = the Terrain value in scripts/terrain/terrain_grid.gd.
## scripts/tools/build_map_data.gd turns a layout into the files the game reads.
const SIZE := 500
const NAMES: PackedStringArray = ["grass", "water", "desert", "forest", "mountain", "ore", "coal"]
const PALETTE: Array[Color] = [
	Color8(98, 132, 60), # 0 grass
	Color8(36, 98, 150), # 1 water
	Color8(222, 190, 104), # 2 desert
	Color8(26, 84, 42), # 3 forest
	Color8(118, 118, 122), # 4 mountain
	Color8(196, 52, 40), # 5 ore (iron)
	Color8(18, 18, 24), # 6 coal
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
