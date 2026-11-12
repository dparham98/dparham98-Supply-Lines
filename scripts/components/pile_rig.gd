extends Node3D
## A material pile's model (docs/MATERIAL_PILE_MODELS.md): the base (pallet, chocks or dust patch) always shows,
## and as many of the stacked pieces (ingots, logs or coal layers, named *_piece_NN, laid down from 01) as the
## pile's amount warrants. Nothing is built at runtime; pieces are only shown and hidden.
## The amount at which the whole stack shows; anything above it shows the full stack too.
@export_range(1,10000) var full_amount := 100
var pieces: Array[Node3D] = []
var shown := 0
func _ready() -> void:
	for node in find_children("*_piece_*","Node3D",true,false): pieces.append(node)
	pieces.sort_custom(func(a,b): return String(a.name) < String(b.name))
	shown = pieces.size()
## How many pieces stand for this amount: at least one while anything is left, all of them at full_amount.
func pieces_for(amount: int) -> int:
	if amount <= 0 or pieces.is_empty(): return 0
	return clampi(ceili(float(amount)/full_amount*pieces.size()),1,pieces.size())
func show_amount(amount: int) -> void:
	shown = pieces_for(amount)
	for index in range(pieces.size()): pieces[index].visible = index < shown
