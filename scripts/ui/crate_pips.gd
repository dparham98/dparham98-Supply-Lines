extends HBoxContainer
## One square per crate (docs/CRATE_CONTAINERS.md): filled from the bottom by how full it is, in its
## resource colour; an empty crate is a dim brown square; a free slot is an outline only.
## Authored in scenes/ui/crate_pips.tscn with a fixed set of pips that are shown or hidden.
signal pip_pressed(index: int, shift: bool)
const COLORS := {&"energy": Color(0.498,0.827,0.902), &"iron": Color(0.604,0.655,0.678), &"wood": Color(0.435,0.682,0.353), &"coal": Color(0.788,0.541,0.29)}
const EMPTY_CRATE := Color(0.56,0.4,0.22,0.45)
## Whether pips take clicks (the Depot panel) or let the pointer through (hover card, storage).
@export var clickable := false
var _pips: Array[Button] = []
func _ready() -> void:
	for child in get_children():
		if child is Button:
			_pips.append(child)
			var index := _pips.size()-1
			child.mouse_filter = Control.MOUSE_FILTER_STOP if clickable else Control.MOUSE_FILTER_IGNORE
			child.pressed.connect(func(): pip_pressed.emit(index,Input.is_key_pressed(KEY_SHIFT)))
func capacity() -> int: return _pips.size()
## items: {kind, amount} per crate. slots: total squares to show (free slots are outlines).
func show_crates(items: Array, slots := -1) -> void:
	var count := clampi(maxi(items.size(),slots),0,_pips.size())
	for i in range(_pips.size()):
		var pip := _pips[i]
		pip.visible = i < count
		var fill: ColorRect = pip.get_node("Fill")
		if i >= items.size():
			fill.visible = false
			pip.tooltip_text = "Free crate slot"
			continue
		var crate: Dictionary = items[i]
		fill.visible = true
		var ratio := clampf(float(crate.amount)/ResourceStockpile.CRATE,0,1)
		fill.color = COLORS.get(crate.kind,EMPTY_CRATE) if crate.amount > 0 else EMPTY_CRATE
		fill.anchor_top = 1.0-ratio if crate.amount > 0 else 0.0
		pip.tooltip_text = ("Empty crate" if crate.amount == 0 else "%s crate · %d / %d" % [str(crate.kind).capitalize(),crate.amount,ResourceStockpile.CRATE])+(" · Shift-click to unpack" if clickable and crate.amount > 0 else "")
	var more: Label = get_node("More")
	more.visible = items.size() > _pips.size()
	more.text = "+%d" % (items.size()-_pips.size())
