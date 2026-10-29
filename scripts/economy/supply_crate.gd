extends Node3D
## A crate on the map (docs/CRATE_CONTAINERS.md): up to 25 units of one resource, separate from any
## Depot's storage. Workers gather from it like a pile or deliver into it; Cargo vehicles load it.
const CAPACITY := ResourceStockpile.CRATE
## "" for an empty crate, else energy, iron, wood or coal.
@export var material_kind := ""
@export_range(0,25) var amount := 0
@export var team := "player"
## How close a worker or vehicle must get to use the crate.
@export var dropoff_range := 2.5
var resource_kind: StringName:
	get: return StringName(material_kind)
var remaining: int:
	get: return amount
func _ready() -> void:
	add_to_group("supply_crates")
	amount = clampi(amount,0,CAPACITY)
	if amount == 0: material_kind = ""
	refresh()
func space() -> int: return CAPACITY-amount
func accepts(kind: StringName) -> bool:
	return amount < CAPACITY and ResourceStockpile.KINDS.has(kind) and (material_kind.is_empty() or kind == resource_kind)
## Adds up to `requested` units of one resource; returns what fit.
func receive(kind: StringName, requested: int) -> int:
	if not accepts(kind) or requested <= 0: return 0
	var accepted := mini(requested,space())
	material_kind = str(kind)
	amount += accepted
	refresh()
	return accepted
func can_extract(_team: String) -> bool: return amount > 0 and not is_queued_for_deletion()
## Workers take from a crate like a pile; an emptied crate stays as an empty container.
func extract(requested: int, _team := "") -> int:
	if not can_extract(_team): return 0
	var taken := mini(maxi(0,requested),amount)
	amount -= taken
	if amount == 0: material_kind = ""
	refresh()
	return taken
func refresh() -> void:
	# In "resources" only while it holds something, so right-click gathers from full crates only.
	if amount > 0 and not is_in_group("resources"): add_to_group("resources")
	elif amount == 0 and is_in_group("resources"): remove_from_group("resources")
	for band in $Visuals/Bands.get_children(): band.visible = band.name.to_lower() == material_kind
	$Label.text = "Empty crate" if amount == 0 else "%s crate · %d/%d" % [material_kind.capitalize(),amount,CAPACITY]
