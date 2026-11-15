extends RefCounted
## Team paint on unit models (docs/TEAM_MARKERS.md). Surfaces whose imported material is named
## team_color, or one of the names in the model root's team_materials metadata, are drawn with the
## saved paint material of the unit's side. Only surface overrides change; the model is not rebuilt.
const DEFAULT_MATERIALS := ["team_color"]
const PAINTS := {
	"player": preload("res://assets/materials/units/team_paint_player.tres"),
	"enemy": preload("res://assets/materials/units/team_paint_enemy.tres"),
	"neutral": preload("res://assets/materials/units/team_paint_neutral.tres"),
}
static func paint_for(team: String) -> Material:
	return PAINTS.get(team,PAINTS["neutral"])
static func material_names(model: Node) -> Array:
	var names: Array = DEFAULT_MATERIALS.duplicate()
	names.append_array(Array(model.get_meta(&"team_materials",PackedStringArray())))
	return names
## Paints every team surface under `model`; returns how many surfaces were painted.
static func apply(model: Node, team: String) -> int:
	if model == null: return 0
	var names := material_names(model)
	var paint := paint_for(team)
	var painted := 0
	for node in model.find_children("*","MeshInstance3D",true,false):
		var mesh_node := node as MeshInstance3D
		if mesh_node.mesh == null: continue
		for i in mesh_node.mesh.get_surface_count():
			var base := mesh_node.mesh.surface_get_material(i)
			if base != null and base.resource_name in names:
				mesh_node.set_surface_override_material(i,paint)
				painted += 1
	return painted
