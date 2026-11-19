# Inspecting enemies and selecting buildings together

Asked for in the playtest of 2026-11-18.

## Enemy units and buildings

- **A click on an enemy unit inspects it.** The bottom panel shows its type, team, health and stats (the stat grid
  and abilities line), and its team marker shows under it. Your units are deselected. Upgrades will join them later.
- **Hidden on enemy units** (playtest of 2026-11-19): what they are doing, their order queue, fuel, cargo, a cargo
  truck's crates and route, and the nearest Depot. The marks over enemy units also leave out carried resources, fuel
  warnings and a cargo truck's storage; they show health only.
- **Enemy buildings** were already shown this way: health, team, storage and production state.
- **Read only:** the command card stays empty and the title reads "ENEMY UNIT · INSPECT". Right-click with nothing
  of yours selected gives no order; select your own units and right-click the enemy to attack it.
- A box drag still selects only your units. An inspected enemy that dies is no longer shown.
- **Code:** `pick_object` in `selection_manager.gd` picks enemy units (only visible ones); the inspected unit is held
  in `game.selected_building`, which `skirmish_hud.selected_object()` shows when no units of yours are selected.

## Several buildings of one type

| Input | Effect |
| --- | --- |
| Double-click your building | Selects your buildings of that type on screen; the clicked one is first |
| Shift-click your building | Adds or removes it, when buildings of its type are selected; on another type, selects only it |
| Click a portrait | Keeps only that building |
| Shift-click a portrait | Removes that building |
| Ctrl+number | Saves them all as a control group |

With several selected:

- The name reads "3 × Barracks" and a portrait shows each one, with its health.
- The card shows the first building's commands.
- **Production:** a produce button (and a Depot's truck and cargo buttons) queues at the selected building with the
  shortest queue, among those that can pay from a friendly Depot. Pressing it again spreads the work.
- **Applied to all:** the power slider, rally points (set and cleared), and generator pause and fuel.
- **First building only:** the Depot assignment, Make crates and trains.

**Code:**

- `game.selected_buildings` holds them; `selected_building` is the first.
- `game.select_buildings()` sets them, and every selected building shows its team marker.
- `skirmish_hud.same_buildings()` and `least_busy()` route the commands.

## Checks

`tests/inspect_select_test.gd` (headless) covers:

- an enemy unit inspected with no orders;
- double-click on three Barracks;
- production going to the shortest queue;
- power and rally applied to all;
- Shift-click to remove and add;
- control groups and portraits.
