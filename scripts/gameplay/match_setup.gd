extends Node
## The match chosen on the main menu (docs/MAIN_MENU.md), kept across scene changes and restarts as the
## `MatchSetup` autoload. A map run straight from the editor or a test is not `configured`, and plays as its scene
## was saved.
const MENU := "res://scenes/ui/main_menu.tscn"
## Maps the menu offers. Only Two Lakes has a start for each side and an enemy player.
const MAPS := {"two_lakes": {name = "Two Lakes", path = "res://scenes/maps/lakes_skirmish.tscn"}}
## Factions by id. Only a playable one can be chosen; the others are shown on the menu, locked.
const FACTIONS := {
	&"cyborgs": {name = "Cyborgs", playable = true},
	&"arthurian_knights": {name = "Arthurian Knights", playable = false},
}
## "ai": you against one AI; "sandbox": you alone, no opponent; "spectate": an AI on each side, you watch.
const MODES := ["ai","sandbox","spectate"]
var configured := false
var mode := "ai"
var map_id := "two_lakes"
## Each side's faction. Only the Cyborgs exist yet, so this is stored for later rosters and shown in the pause menu.
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
	if not new_mode in MODES or not MAPS.has(new_map) or not playable(player_faction) or not playable(enemy_faction): return false
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
## - every mode: each side's faction is set on the game.
func apply(game: Node) -> void:
	if not configured: return
	game.factions = factions.duplicate()
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
