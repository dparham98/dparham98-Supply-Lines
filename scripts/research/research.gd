class_name Research
extends RefCounted
## Research done by each side (docs/TEMPLE_OF_SCIENCE.md). It lives on the map's skirmish node as metadata, so
## it starts empty with every map and needs no field on the map script.
const META := &"research_done"
## Mining Trains: upgraded maglev trains mine iron at a mine joined by track (docs/TEMPLE_OF_SCIENCE.md).
const MINING_TRAINS := &"mining_trains"
## Slow (docs/MIST_AND_SLOW.md): researched at the Forge, it lets Grail Sentinels cast Slow.
const SLOW := &"slow"
static func _game(from: Node) -> Node:
	if from == null or not from.is_inside_tree(): return null
	return from if from.is_in_group("skirmish") else from.get_tree().get_first_node_in_group("skirmish")
static func _done(game: Node) -> Dictionary:
	if not game.has_meta(META): game.set_meta(META,{})
	return game.get_meta(META)
## Whether `team` has finished research `id`. `from` is any node in the map.
static func has(from: Node, team: String, id: StringName) -> bool:
	var game := _game(from)
	if game == null: return false
	return (_done(game).get(team,{}) as Dictionary).has(id)
static func complete(from: Node, team: String, id: StringName) -> void:
	var game := _game(from)
	if game == null: return
	var done := _done(game)
	if not done.has(team): done[team] = {}
	done[team][id] = true
## The research building of `team` working on `id` now, or null.
static func underway(from: Node, team: String, id: StringName) -> Node:
	if from == null or not from.is_inside_tree(): return null
	for building in from.get_tree().get_nodes_in_group("research_buildings"):
		if building.team == team and building.researching != null and building.researching.research_id == id: return building
	return null
