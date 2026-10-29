extends RefCounted
# Portable location for test results and screenshots.
# Files go under $SUPPLY_LINES_TEST_OUTPUT when set, otherwise user://test_output.
# A failed write prints TEST_OUTPUT_ERROR, quits with exit code 1 and is remembered,
# so a later quit(TestOutput.exit_code()) cannot report success.

static var _failed := false

static func path(file: String) -> String:
	var base := OS.get_environment("SUPPLY_LINES_TEST_OUTPUT")
	if base.is_empty(): base = ProjectSettings.globalize_path("user://test_output")
	return base.path_join(file)

static func exit_code() -> int:
	return 1 if _failed else 0

static func _fail(tree: SceneTree, message: String) -> bool:
	_failed = true
	printerr("TEST_OUTPUT_ERROR: " + message)
	tree.quit(1)
	return false

static func _prepare(tree: SceneTree, target: String) -> bool:
	var err := DirAccess.make_dir_recursive_absolute(target.get_base_dir())
	if err != OK: return _fail(tree, "cannot create %s (%s)" % [target.get_base_dir(), error_string(err)])
	return true

static func write_text(tree: SceneTree, file: String, text: String) -> bool:
	var target := path(file)
	if not _prepare(tree, target): return false
	var handle := FileAccess.open(target, FileAccess.WRITE)
	if handle == null: return _fail(tree, "cannot open %s (%s)" % [target, error_string(FileAccess.get_open_error())])
	if not handle.store_string(text): return _fail(tree, "cannot write %s (%s)" % [target, error_string(handle.get_error())])
	handle.close()
	print("TEST_OUTPUT_WRITTEN: " + target)
	return true

static func save_png(tree: SceneTree, image: Image, file: String) -> bool:
	var target := path(file)
	if not _prepare(tree, target): return false
	if image == null or image.is_empty(): return _fail(tree, "no image captured for " + target)
	var err := image.save_png(target)
	if err != OK: return _fail(tree, "cannot save %s (%s)" % [target, error_string(err)])
	print("TEST_OUTPUT_WRITTEN: " + target)
	return true
