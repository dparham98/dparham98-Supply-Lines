# Main menu, match setup and pause menu

Asked for on 2026-11-22:

- a menu screen where you pick 0 or 1 AI opponents, or spectate a game between two AIs;
- a menu that prepares the game for choosing a faction;
- a pause menu in the HUD.

Built on the enemy AI (docs/ENEMY_AI.md), which plays either side.

## The main menu

The game now opens on `scenes/ui/main_menu.tscn` (the project's main scene, so **F5** opens the menu). Two Lakes
still runs straight from its scene with **F6**, playing as saved: you against the East AI.

**Match:** one of three, on Two Lakes:

| Choice | What you get |
| --- | --- |
| Play against 1 AI (the default) | You take the West start; the AI takes the East, with the same rules and fog. |
| Play with no opponent (sandbox) | You take the West start alone. The East start's Depot and units are cleared and its AI is off. Neither side can win. |
| Spectate: AI against AI | An AI plays each start. You see the whole map with no fog and can click anything to inspect it, but give no orders. |

**Factions:** a faction for each side; the Cyborgs are chosen to start with. With no opponent, only your faction
shows. Spectating, the rows are the West AI and the East AI.

- **Arthurian Knights** (docs/ARTHURIAN_KNIGHTS.md; selectable from 2026-11-23) can be chosen on either row. Since
  2026-11-24 an AI side can be the Knights: the Knights AI (docs/KNIGHTS_AI.md) plays them, and a Knights East start
  gets the Keep and two Forester Maidens as the West does. A faction an AI cannot play would still show as
  "· You only" and be locked on an AI's row.
- **The Knights' start:** the West start's Cyborg Depot, Deforester and Cargo truck are replaced by a Keep on the
  same spot, two Forester Maidens and a 25 Food crate. The start is saved as `scenes/maps/starts/knights_start.tscn`
  (positions from the start marker). The Keep keeps its own stock: 150 iron, 150 wood, 300 Food. The rest of Two
  Lakes, the mines and the East start are unchanged.
- **Food:** a Knights player makes Food from Farms (docs/KNIGHTS_ECONOMY.md).

**Start match** (Start watching, when spectating) loads the map; **Quit** closes the game. The menu remembers the
last match when you come back to it.

**Code:**

- `scripts/ui/main_menu.gd` drives the menu.
- `scripts/gameplay/match_setup.gd` is the `MatchSetup` autoload. It keeps the choice across scene changes and
  restarts. When the map loads, the skirmish calls `MatchSetup.apply`.
- A map run straight from its scene, or from a test, is not `configured`, and plays exactly as saved.

**Factions:** `MatchSetup.FACTIONS` lists them, with `playable` and `ai` (whether an AI can play it). `start()`
refuses a side that can't be played by whoever plays it. Each side's choice is set on the game as `game.factions`
("player" and "enemy" to an id). `MatchSetup.apply` swaps in the Knights' start (`_knights_start`). The Build page
still offers both factions' buildings.

## Spectating

- **The West AI:** Two Lakes has a second copy of the enemy AI, `PlayerAI`, set to play the West start (`team =
  "player"`, `opponent = "enemy"`). It is saved switched off (`process_mode` Disabled), and spectating switches it
  on. Each AI still plays under its own side's fog.
- **The view:** the fog's `viewer` is set to "spectator", a name on neither side, so nothing is hidden and the map
  isn't dimmed.
- **Read-only:** `game.spectating` keeps the HUD read-only:
  - no command buttons, no Build button, no Depot or production sliders;
  - right-clicks on the map and minimap give no orders.

  Selecting and inspecting work as usual.
- **The winner:** the header says which AI won, "WEST AI WINS" or "EAST AI WINS", once the other has nothing left.

## The pause menu

**Opening it:**

- **Esc** opens it, as does the HUD's **Menu (Esc)** button beside Restart.
- If a command or placement is armed, Esc cancels that first, as before. The next Esc opens the menu.
- The playtest panel's spawning also keeps its own Esc.

**While it is open:**

- The game is paused.
- The menu takes every click and key. Esc closes it.
- Enter, Space and the arrow keys work its buttons.
- It shows the match: the map, who plays and their factions.

**Its buttons:**

- **Resume (Esc).** A game that was already paused from the playtest panel stays paused.
- **Restart match:** the same match again.
- **Main menu.**
- **Quit game.**

**Code:** `scripts/ui/pause_menu.gd`. The `PauseMenu` node is saved in `scenes/ui/skirmish_hud.tscn`.

## Checks

`tests/main_menu_test.gd` (headless) checks:

- the menu is the main scene and lists the factions; the Knights are open on both rows, including yours while
  spectating, and a match against the Knights puts a Keep at the East start played by the Knights AI;
- the rows follow the mode;
- Start match loads Two Lakes with the East AI on and the West AI off;
- Esc pauses into the pause menu, keys stop there, and Esc resumes; an armed command takes Esc first;
- the Menu button opens the menu, and Resume keeps an earlier pause;
- Main menu goes back to the menu, which remembers the match;
- the sandbox clears the East start and leaves its AI off;
- spectating runs both AIs, has no fog, gives the HUD no commands, ignores right-click orders, sets the West AI's
  workers going, and names the winner;
- the Knights against the AI put a Keep on the West start with two Forester Maidens, remove the Cyborg start, and
  leave the East AI playing.

A 14-minute spectated game was run headless (`--fixed-fps 30`). Both AIs built up and fought, and the West won,
with no script errors.
