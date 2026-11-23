extends RefCounted
## The game's mouse cursors (docs/CURSORS.md). Each is a saved image in assets/ui/cursors, drawn by
## scripts/tools/make_cursors.gd, set as the custom image of one of Godot's cursor shapes. The map overlay picks the
## shape for what is under the pointer; over the HUD, controls show their own (the pointer).
const IMAGES := {
	"pointer": preload("res://assets/ui/cursors/pointer.png"),
	"select": preload("res://assets/ui/cursors/select.png"),
	"attack": preload("res://assets/ui/cursors/attack.png"),
	"inspect": preload("res://assets/ui/cursors/inspect.png"),
	"gather": preload("res://assets/ui/cursors/gather.png"),
}
const SHAPES := {"pointer": Input.CURSOR_ARROW, "select": Input.CURSOR_POINTING_HAND, "attack": Input.CURSOR_CROSS, "inspect": Input.CURSOR_HELP, "gather": Input.CURSOR_CAN_DROP}
## The point of each image that is the click: the arrow's tip, or the crosshair's centre.
const HOTSPOTS := {"attack": Vector2(16,16)}
const TIP := Vector2(1,1)
static var shown := ""
static var _installed := false
## Sets every image as its shape's cursor. The first `use` does it.
static func install() -> void:
	for id in IMAGES: Input.set_custom_mouse_cursor(IMAGES[id],SHAPES[id],HOTSPOTS.get(id,TIP))
	_installed = true
static func use(id: String) -> void:
	if not _installed: install()
	if id == shown: return
	shown = id
	Input.set_default_cursor_shape(SHAPES[id])
## Resources the pointer can be over: Forest and Coal cells, iron deposits, piles and crates.
static func is_resource(node: Node) -> bool:
	for group in ["forest_cells","coal_cells","resources","iron_deposits","material_piles","supply_crates"]:
		if node.is_in_group(group): return true
	return false
## Which cursor shows over `node` (null for open ground):
## - an enemy: the crosshair;
## - wood (or coal or ore a worker can take) with a selected worker that can gather it: the axe, for the right-click;
## - any other resource: the magnifier, as a click inspects it;
## - anything else that a click selects: the ring;
## - nothing: the pointer. So does an armed command or placement, which shows its own icon by the pointer, except
##   Attack over an enemy.
static func kind_for(node: Node, game: Node) -> String:
	if game != null and game.armed():
		return "attack" if game.pending_unit_command == "attack" and is_instance_valid(node) and str(node.get("team")) == "enemy" else "pointer"
	if not is_instance_valid(node): return "pointer"
	if str(node.get("team")) == "enemy" and node.get("health") != null and node.health > 0: return "attack"
	if is_resource(node): return "gather" if _gatherers_for(node,game) else "inspect"
	return "select"
static func _gatherers_for(node: Node, game: Node) -> bool:
	if game == null: return false
	var takes: bool = node.is_in_group("forest_cells") or node.is_in_group("resources") or (node.is_in_group("coal_cells") and not game.ground.harvesting_rules.coal_needs_mine)
	if not takes: return false
	for unit in game.get_tree().get_nodes_in_group("units"):
		if unit.team == "player" and unit.is_selected and unit.can_gather and not unit.is_cargo_vehicle and not unit.is_depot_truck: return true
	return false
