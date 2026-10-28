extends Node3D
@export_enum("iron","wood","coal") var material_kind := "iron"
@export_range(1,100000) var amount := 10
var remaining := 0
var resource_kind: StringName:
	get: return StringName(material_kind)
func _ready() -> void:
	remaining = amount
	add_to_group("resources"); add_to_group("material_piles")
	update_label()
func can_extract(_team: String) -> bool: return remaining > 0 and not is_queued_for_deletion()
func extract(requested: int, team := "") -> int:
	if not can_extract(team): return 0
	var taken := mini(maxi(0,requested),remaining)
	remaining -= taken
	update_label()
	if remaining == 0:
		remove_from_group("resources"); remove_from_group("material_piles"); queue_free()
	return taken
func update_label() -> void:
	$Label.text = "%s pile · %d" % [material_kind.capitalize(),remaining]
	$Visuals.visible = remaining > 0
