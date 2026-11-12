extends RefCounted
## Arguments for the map tools, given after "--" on the command line as --name=value:
##   godot --headless --path . --script res://scripts/tools/build_mountain_mesh.gd -- --cells=res://assets/maps/balanced/terrain_cells.bin
## Every tool defaults to the original map's files, so running one without arguments does what it always did.
const DEFAULT_CELLS := "res://assets/maps/terrain_cells.bin"

static func value(name: String, fallback: String) -> String:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--"+name+"="): return argument.substr(name.length()+3)
	return fallback

static func given(name: String) -> bool:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--"+name+"="): return true
	return false
