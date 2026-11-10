extends Node
## Shows one authored look of a model and hides the other. Both looks are already in the model
## scene (the Scout's bare head and her helmet); this only switches their visibility, once, when
## the model is created. The model keeps its look for as long as it exists, corpse included.
@export var look_a: Array[NodePath]
@export var look_b: Array[NodePath]
## -1 picks one at random for each model; 0 or 1 forces look A or B.
@export_range(-1,1,1) var look := -1
func _ready() -> void:
	if look < 0: look = randi()%2
	show_look(look)
func show_look(index: int) -> void:
	look = clampi(index,0,1)
	for path in look_a: _set_visible(path,look == 0)
	for path in look_b: _set_visible(path,look == 1)
func _set_visible(path: NodePath, shown: bool) -> void:
	var node := get_node_or_null(path) as Node3D
	if node: node.visible = shown
