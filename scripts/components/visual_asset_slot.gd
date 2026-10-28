@tool
extends Node3D
## Assign a model scene here. Its root should sit at ground level, face -Z, and use meters.
@export var model_scene: PackedScene:
	set(value):
		model_scene = value
		if is_inside_tree(): call_deferred("refresh_model")
@export_tool_button("Refresh model preview", "Reload") var refresh_action: Callable = refresh_model

func _ready() -> void:
	var current := get_node_or_null("Model")
	if model_scene and (current == null or current.scene_file_path != model_scene.resource_path): refresh_model()

func refresh_model() -> void:
	if model_scene == null: return
	var existing := get_node_or_null("Model")
	var replacement := model_scene.instantiate()
	replacement.name = "Model"
	if existing:
		remove_child(existing)
		existing.queue_free()
	add_child(replacement)
	if Engine.is_editor_hint(): replacement.owner = owner if owner else self
