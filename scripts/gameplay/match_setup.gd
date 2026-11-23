extends Node
## The match chosen on the main menu (docs/MAIN_MENU.md), kept across scene changes and restarts as the
## `MatchSetup` autoload. A map run straight from the editor or a test is not `configured`, and plays as its scene
## was saved.
const MENU := "res://scenes/ui/main_menu.tscn"
## Maps the menu offers. Only Two Lakes has a start for each side and an enemy player.
const MAPS := {"two_lakes": {name = "Two Lakes", path = "res://scenes/maps/lakes_skirmish.tscn"}}
## Factions by id. Only a playable one can be chosen; `ai` says whether an AI can play it. The AI only knows the
## Cyborgs, so the Knights are for You alone (against the AI or with no opponent), never an AI's side.
const FACTIONS := {
	&"cyborgs": {name = "Cyborgs", playable = true, ai = true},
	&"arthurian_knights": {name = "Arthurian Knights", playable = true, ai = false},
}
## The Knights' start, put at the West start in place of the Cyborg one (`_knights_start`).
const KNIGHTS_START := "res://scenes/maps/starts/knights_start.tscn"
## "ai": you against one AI; "sandbox": you alone, no opponent; "spectate": an AI on each side, you watch.
const MODES := ["ai","sandbox","spectate"]
var configured := false
var mode := "ai"
var map_id := "two_lakes"
## Each side's faction, set on the game and shown in the pause menu.
var factions := {"player": &"cyborgs", "enemy": &"cyborgs"}
## The number of AI opponents the menu shows for the mode: 1, 0, or both sides played by AI.
func ai_opponents() -> int:
	return 0 if mode == "sandbox" else 1
func spectating() -> bool:
	return configured and mode == "spectate"
func map_path() -> String:
	return MAPS[map_id].path
## Sets the match and loads its map.
func start(new_mode: String, player_faction: StringName = &"cyborgs", enemy_faction: StringName = &"cyborgs", new_map := "two_lakes") -> bool:
	if not new_mode in MODES or not MAPS.has(new_map) or not playable(player_faction) or not ai_playable(enemy_faction): return false
	# Spectating, the West start is an AI's too.
	if new_mode == "spectate" and not ai_playable(player_faction): return false
	mode = new_mode
	map_id = new_map
	factions = {"player": player_faction, "enemy": enemy_faction}
	configured = true
	get_tree().paused = false
	Engine.time_scale = 1.0
	get_tree().change_scene_to_file(map_path())
	return true
func playable(faction: StringName) -> bool:
	return FACTIONS.has(faction) and FACTIONS[faction].playable
func ai_playable(faction: StringName) -> bool:
	return playable(faction) and FACTIONS[faction].ai
func faction_name(team: String) -> String:
	return FACTIONS.get(factions.get(team,&"cyborgs"),{name = "Cyborgs"}).name
## One line for the pause menu: the map, who plays and their factions.
func summary() -> String:
	var map_name: String = MAPS[map_id].name
	match mode:
		"sandbox": return "%s · No opponent · You: %s" % [map_name,faction_name("player")]
		"spectate": return "%s · Spectating · West AI (%s) vs East AI (%s)" % [map_name,faction_name("player"),faction_name("enemy")]
	return "%s · You (%s) vs 1 AI (%s)" % [map_name,faction_name("player"),faction_name("enemy")]
## Back to the main menu, unpaused.
func to_menu() -> void:
	get_tree().paused = false
	Engine.time_scale = 1.0
	get_tree().change_scene_to_file(MENU)
## Sets up a map that has just loaded (called from the skirmish's `_ready`). Does nothing unless the menu chose
## the match.
## - sandbox: the enemy player is switched off and the other side's start is cleared away;
## - spectate: the West start's AI (`PlayerAI`, saved switched off in the map) is switched on, the fog is lifted for
##   the view, and the HUD only inspects (`game.spectating`);
## - every mode: each side's faction is set on the game, and a Knights player gets the Knights' start.
func apply(game: Node) -> void:
	if not configured: return
	game.factions = factions.duplicate()
	if factions.player == &"arthurian_knights": _knights_start(game)
	var east: Node = game.enemy_player()
	var west: Node = game.get_node_or_null("PlayerAI")
	match mode:
		"sandbox":
			if east != null:
				east.process_mode = Node.PROCESS_MODE_DISABLED
				east.set_meta("switched_off",true)
			for group in ["units","selectable_buildings","construction_plans","rails"]:
				for node in game.get_tree().get_nodes_in_group(group):
					if _team(node) == "enemy": node.queue_free()
			game.sandbox = true
			game.message = "No opponent: build and test freely."
		"spectate":
			if west != null: west.process_mode = Node.PROCESS_MODE_INHERIT
			game.spectating = true
			var fog = game.fog_of_war()
			if fog != null: fog.viewer = "spectator"
			game.message = "Spectating: the West AI against the East AI. Esc for the menu."
func _team(node: Node):
	if node.is_in_group("rails"):
		var depot = node.get("assigned_depot")
		return depot.team if is_instance_valid(depot) else null
	return node.get("team")
## Replaces the West start's Cyborg Depot, Deforester and Cargo truck with the saved Knights start
## (KNIGHTS_START): a Keep on the same spot, two Forester Maidens and a Food crate. The rest of the map is unchanged.
func _knights_start(game: Node) -> void:
	var old: Node3D = game.depot
	if not is_instance_valid(old) or old.is_in_group("keeps"): return
	var at: Vector3 = old.global_position
	var gone: Array[Node] = [old]
	for unit in game.get_tree().get_nodes_in_group("units"):
		if unit.get("team") == "player": gone.append(unit)
	for node in gone:
		node.get_parent().remove_child(node)
		node.queue_free()
	var start: Node3D = load(KNIGHTS_START).instantiate()
	var entities: Node = game.get_node("Entities")
	var keep: Node3D = null
	for child in start.get_children():
		var offset: Vector3 = child.position
		start.remove_child(child)
		child.owner = null
		var parent := "Buildings" if child.is_in_group("keeps") or child.name == "Keep" else ("Resources" if child.name.begins_with("Starter") else "Units")
		entities.get_node(parent).add_child(child)
		child.global_position = at+offset
		if child.name == "Keep": keep = child
	start.free()
	game.depot = keep
	game.get_node("DepotNetwork").select_depot(keep)
	game.message = "Your Keep holds the West start. Forester Maidens gather and build; B → Chapterhouse trains knights."
