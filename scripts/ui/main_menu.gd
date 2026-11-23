extends Control
## The main menu (docs/MAIN_MENU.md): the game opens here. Choose the match (one AI opponent, no opponent, or an AI
## on each side to watch) and each side's faction, then Start match loads Two Lakes set up that way (MatchSetup).
## The faction lists are saved in the scene in this order. The AI only plays the Cyborgs, so the Knights are for
## You alone: locked on the AI's row, and on yours while spectating (the West start is an AI then).
const FACTION_ORDER: Array[StringName] = [&"cyborgs",&"arthurian_knights"]
const NOTES := {
	"ai": "You take the West start. The AI takes the East and plays by your rules: same economy, same fog. As the Knights you start with a Keep and two Forester Maidens.",
	"sandbox": "You take the West start alone. The East start is empty and nothing attacks: build and test freely.",
	"spectate": "An AI plays each start. You watch the whole map, without fog, and can inspect anything, but give no orders.",
}
var mode := "ai"
@onready var setup = get_node_or_null("/root/MatchSetup")
func _ready() -> void:
	get_tree().paused = false
	%ModeAI.toggled.connect(_on_mode.bind("ai"))
	%ModeSandbox.toggled.connect(_on_mode.bind("sandbox"))
	%ModeSpectate.toggled.connect(_on_mode.bind("spectate"))
	%Start.pressed.connect(start)
	%Quit.pressed.connect(func(): get_tree().quit())
	# The menu opens on the last match chosen.
	if setup != null and setup.configured:
		{"ai": %ModeAI, "sandbox": %ModeSandbox, "spectate": %ModeSpectate}[setup.mode].button_pressed = true
		%PlayerFaction.select(maxi(0,FACTION_ORDER.find(setup.factions.player)))
		%EnemyFaction.select(maxi(0,FACTION_ORDER.find(setup.factions.enemy)))
	refresh()
	%Start.grab_focus()
func _on_mode(on: bool, new_mode: String) -> void:
	if on: set_mode(new_mode)
func set_mode(new_mode: String) -> void:
	mode = new_mode
	refresh()
func refresh() -> void:
	%ModeNote.text = NOTES[mode]
	%EnemyRow.visible = mode != "sandbox"
	%PlayerSide.text = "West AI" if mode == "spectate" else "You"
	%EnemySide.text = "East AI" if mode == "spectate" else "AI opponent"
	%Start.text = "Start watching" if mode == "spectate" else "Start match"
	_lock_for_ai(%PlayerFaction,mode == "spectate")
	_lock_for_ai(%EnemyFaction,true)
## Locks the factions an AI can't play on a row an AI plays, and moves its choice off one.
func _lock_for_ai(option: OptionButton, ai_side: bool) -> void:
	if setup == null: return
	for i in range(FACTION_ORDER.size()):
		var id := FACTION_ORDER[i]
		var locked: bool = not (setup.ai_playable(id) if ai_side else setup.playable(id))
		option.set_item_disabled(i,locked)
		option.set_item_text(i,setup.FACTIONS[id].name+(" · You only" if locked and setup.playable(id) else ""))
	if option.is_item_disabled(option.selected): option.select(0)
func faction(option: OptionButton) -> StringName:
	return FACTION_ORDER[clampi(option.selected,0,FACTION_ORDER.size()-1)]
func start() -> bool:
	if setup == null: return false
	return setup.start(mode,faction(%PlayerFaction),faction(%EnemyFaction))
