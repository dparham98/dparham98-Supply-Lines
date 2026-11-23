extends SceneTree
# Headless: the main menu, the match it sets up, and the pause menu (docs/MAIN_MENU.md). The game opens on the menu;
# the factions list the Cyborgs and the Arthurian Knights, who are for You only (locked on an AI's row). Start match loads Two Lakes against the East
# AI. Esc pauses into the pause menu, which holds the keyboard until Esc resumes, and an armed command takes Esc
# first. The sandbox clears the East start and switches its AI off. Spectating switches on the West AI, lifts the
# fog for the view and leaves the HUD only inspecting. The pause menu's Main menu goes back to the menu. Choosing the
# Knights puts a Keep and two Forester Maidens at the West start in place of the Cyborg start.
var setup: Node
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> bool:
	if value: return true
	push_error(message); quit(1); return false
func key(node: Node, code: Key, unhandled := true) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	if unhandled: node._unhandled_input(event)
	else: node._input(event)
	return event
## Starts a match from the menu's own controls and waits for the map.
func start_from_menu(menu: Control, mode_button: String) -> Node:
	menu.get_node("%"+mode_button).button_pressed = true
	if not menu.start(): return null
	for frame in range(30):
		await process_frame
		if current_scene != null and current_scene.is_in_group("skirmish") and current_scene.is_node_ready(): break
	for frame in range(3): await process_frame
	return current_scene if current_scene != null and current_scene.is_in_group("skirmish") else null
func open_menu() -> Control:
	change_scene_to_file(ProjectSettings.get_setting("application/run/main_scene"))
	for frame in range(10):
		await process_frame
		if current_scene != null and current_scene.name == "MainMenu": break
	return current_scene as Control
func team_nodes(team: String) -> int:
	var count := 0
	for group in ["units","selectable_buildings","construction_plans"]:
		for node in get_nodes_in_group(group):
			if node.get("team") == team and not node.is_queued_for_deletion(): count += 1
	return count
func run() -> void:
	root.size = Vector2i(1280,900)
	setup = root.get_node_or_null("MatchSetup")
	if not check(setup != null and not setup.configured,"MatchSetup should be an autoload, unset at start"): return
	# The game opens on the menu.
	if not check(ProjectSettings.get_setting("application/run/main_scene") == "res://scenes/ui/main_menu.tscn","The main scene should be the menu"): return
	var menu := await open_menu()
	if not check(menu != null and menu.name == "MainMenu","The menu should open"): return
	if not check(menu.mode == "ai" and menu.get_node("%ModeAI").button_pressed,"The menu starts on one AI opponent"): return
	# The factions: Cyborgs first, chosen; the Knights open to You, locked on the AI's row.
	for name in ["PlayerFaction","EnemyFaction"]:
		var option: OptionButton = menu.get_node("%"+name)
		if not check(option.item_count == menu.FACTION_ORDER.size() and option.get_item_text(0) == "Cyborgs" and option.selected == 0,"%s lists the Cyborgs first, chosen" % name): return
	var mine: OptionButton = menu.get_node("%PlayerFaction")
	var theirs: OptionButton = menu.get_node("%EnemyFaction")
	if not check(mine.get_item_text(1) == "Arthurian Knights" and not mine.is_item_disabled(1),"You can choose the Knights: %s" % mine.get_item_text(1)): return
	if not check(theirs.get_item_text(1) == "Arthurian Knights · You only" and theirs.is_item_disabled(1),"The AI's row shows the Knights locked: %s" % theirs.get_item_text(1)): return
	if not check(not setup.start("ai",&"cyborgs",&"arthurian_knights") and not setup.start("spectate",&"arthurian_knights"),"No AI side can be the Knights"): return
	if not check(not setup.start("ai",&"no_such_faction"),"An unknown faction cannot be started"): return
	# Spectating locks the Knights on your row too, and moves a Knights choice back to the Cyborgs.
	mine.select(1)
	menu.get_node("%ModeSpectate").button_pressed = true
	if not check(mine.is_item_disabled(1) and mine.selected == 0,"Spectating, the West AI can't be the Knights"): return
	menu.get_node("%ModeAI").button_pressed = true
	if not check(not mine.is_item_disabled(1) and mine.get_item_text(1) == "Arthurian Knights","Back to one AI, the Knights are open again"): return
	# The rows follow the mode.
	menu.get_node("%ModeSandbox").button_pressed = true
	if not check(menu.mode == "sandbox" and not menu.get_node("%EnemyRow").visible,"No opponent hides the opponent's faction"): return
	menu.get_node("%ModeSpectate").button_pressed = true
	if not check(menu.get_node("%PlayerSide").text == "West AI" and menu.get_node("%EnemySide").text == "East AI" and menu.get_node("%EnemyRow").visible,"Spectating names both AIs"): return
	# One AI opponent: Two Lakes with the East AI on and the West AI off.
	var game: Node = await start_from_menu(menu,"ModeAI")
	if not check(game != null and game.scene_file_path == setup.map_path(),"Start match should load Two Lakes"): return
	if not check(setup.configured and setup.mode == "ai" and setup.ai_opponents() == 1 and game.factions.player == &"cyborgs" and game.factions.enemy == &"cyborgs","The match is set up for one AI, Cyborgs both sides"): return
	if not check(game.enemy_player() != null and game.enemy_player().can_process() and game.player_ai() == null and not game.spectating,"The East AI plays; the West AI stays off"): return
	if not check(team_nodes("enemy") > 0 and game.fog_of_war().viewer == "player","The East start stands, under fog"): return
	# Pause menu: Esc opens it and pauses; keys stop there; Esc again resumes.
	var hud: CanvasLayer = game.get_node("Interface")
	var pause: Control = hud.get_node("PauseMenu")
	if not check(not pause.visible and not paused,"The pause menu starts closed"): return
	key(pause,KEY_ESCAPE)
	if not check(pause.visible and paused,"Esc should open the pause menu and pause"): return
	if not check(pause.get_node("%Match").text == setup.summary() and setup.summary().contains("1 AI"),"The pause menu names the match: %s" % pause.get_node("%Match").text): return
	# B would open the Build page; with the menu open it reaches nothing.
	var b := InputEventKey.new()
	b.keycode = KEY_B; b.physical_keycode = KEY_B; b.pressed = true
	root.push_input(b)
	if not check(not hud.global_build_open and pause.visible,"Keys should stop at the open pause menu"): return
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE; esc.physical_keycode = KEY_ESCAPE; esc.pressed = true
	root.push_input(esc)
	if not check(not pause.visible and not paused,"Esc again should resume"): return
	# An armed command takes Esc first.
	game.pending_unit_command = "move"
	key(pause,KEY_ESCAPE)
	if not check(not pause.visible,"With a command armed, Esc should not open the menu"): return
	game.pending_unit_command = ""
	# The Menu button opens it too, and a game paused before stays paused after.
	paused = true
	hud.get_node("Bottom/Body/Header/Menu").pressed.emit()
	if not check(pause.visible and paused,"The Menu button opens the pause menu"): return
	pause.get_node("%Resume").pressed.emit()
	if not check(not pause.visible and paused,"Resume keeps a game that was paused before paused"): return
	paused = false
	# Main menu goes back to the menu, which remembers the match.
	pause.open()
	pause.get_node("%MainMenu").pressed.emit()
	for frame in range(10):
		await process_frame
		if current_scene != null and current_scene.name == "MainMenu": break
	menu = current_scene as Control
	if not check(menu != null and menu.name == "MainMenu" and not paused,"Main menu should go back to the menu, unpaused"): return
	if not check(menu.mode == "ai","The menu remembers the last match"): return
	# Sandbox: no opponent; the East start is cleared and its AI is off.
	game = await start_from_menu(menu,"ModeSandbox")
	if not check(game != null and game.sandbox and setup.ai_opponents() == 0,"The sandbox should load"): return
	await process_frame
	if not check(not game.enemy_player().can_process() and game.player_ai() == null,"No AI plays in the sandbox"): return
	if not check(team_nodes("enemy") == 0 and team_nodes("player") > 0,"The East start is cleared, the West start stays: %d enemy" % team_nodes("enemy")): return
	# Spectate: both AIs on, no fog for the view, the HUD only inspects and right-clicks give no orders.
	setup.to_menu()
	for frame in range(10):
		await process_frame
		if current_scene != null and current_scene.name == "MainMenu": break
	game = await start_from_menu(current_scene,"ModeSpectate")
	if not check(game != null and game.spectating and setup.spectating(),"Spectating should load"): return
	var west: Node = game.player_ai()
	if not check(west != null and west.team == "player" and west.opponent == "enemy" and game.enemy_player().can_process(),"Both AIs should play"): return
	var fog: Node = game.fog_of_war()
	fog.update_now()
	if not check(fog.viewer == "spectator" and fog.shade_texture().get_image().get_pixel(10,10).a < 0.5,"The view has no fog"): return
	for node in get_nodes_in_group("units"):
		if node.team == "enemy" and not node.visible:
			check(false,"Every enemy unit should show to a spectator"); return
	hud = game.get_node("Interface")
	var worker: Node3D = get_nodes_in_group("units").filter(func(u): return u.team == "player" and u.can_gather)[0]
	worker.set_selected(true)
	hud._process(0)
	if not check(hud.desired_buttons.is_empty() and not hud.get_node("Bottom/Body/Header/GlobalBuild").visible,"The HUD should give a spectator no commands: %s" % [hud.desired_buttons]): return
	if not check(hud.hint_text.begins_with("Spectating"),"The hint says it is spectating"): return
	var before: String = worker.order
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_RIGHT
	click.pressed = true
	click.position = Vector2(640,300)
	game._unhandled_input(click)
	if not check(worker.order == before,"A right-click gives no order while spectating"): return
	worker.set_selected(false)
	# The West AI plays its side: a few decisions set its workers going.
	for round in range(3): west.think()
	if not check(west.workers.size() > 0 and west.workers.any(func(unit): return unit.order != "idle"),"The West AI should set its workers to work"): return
	# Its defeat names the winner.
	west.defeated = true
	game._process(0)
	if not check(game.outcome.begins_with("EAST AI WINS"),"The West AI beaten: %s" % game.outcome): return
	# The Knights against the AI: a Keep and two Forester Maidens at the West start, the Cyborg start gone, the East
	# AI as before.
	setup.to_menu()
	for frame in range(10):
		await process_frame
		if current_scene != null and current_scene.name == "MainMenu": break
	menu = current_scene as Control
	menu.get_node("%PlayerFaction").select(1)
	game = await start_from_menu(menu,"ModeAI")
	if not check(game != null and game.factions.player == &"arthurian_knights" and game.factions.enemy == &"cyborgs","The Knights match should load"): return
	await process_frame
	var keep: Node3D = game.depot
	var start_at: Vector3 = game.get_node("Sites/PlayerStart").global_position
	if not check(is_instance_valid(keep) and keep.is_in_group("keeps") and keep.team == "player" and keep.global_position.distance_to(start_at) < 0.1,"A Keep should stand on the West start"): return
	if not check(game.get_node("DepotNetwork").selected == keep and keep.food > 0,"The Keep is selected and holds Food"): return
	var mine_units := get_nodes_in_group("units").filter(func(u): return u.team == "player" and not u.is_queued_for_deletion())
	if not check(mine_units.size() == 2 and mine_units.all(func(u): return u.unit_stats != null and u.unit_stats.unit_id == &"forester_maiden"),"Your units should be two Forester Maidens: %s" % [mine_units.map(func(u): return u.name)]): return
	var player_depots := get_nodes_in_group("depots").filter(func(d): return d.team == "player" and not d.is_queued_for_deletion())
	if not check(player_depots == [keep],"The Cyborg Depot is gone: %s" % [player_depots.map(func(d): return d.name)]): return
	if not check(team_nodes("enemy") > 0 and game.enemy_player().can_process(),"The East AI still plays its Cyborg start"): return
	if not check(setup.summary().contains("You (Arthurian Knights)"),"The pause menu names your faction: %s" % setup.summary()): return
	setup.configured = false
	print("MAIN_MENU_TEST_PASSED")
	quit(0)
