# HUD phase 1: hotkeys and selection

Phase 1 of the HUD plan (hotkeys, queuing and HUD modernization), approved on 2026-10-28 with the recommended defaults. Branch `feature/hud-commands`, stacked on `feature/vehicle-fuel`. These are new controls, not recovered design.

## How hotkeys work

- Each command button in `scenes/ui/skirmish_hud.tscn` (command card and cargo Supply panel) has an authored `Shortcut` holding an `InputEventAction`. The keys themselves live in the Input Map (`project.godot`), saved by `scripts/tools/setup_command_actions.gd`, so they can be rebound in one place.
- Godot only fires a shortcut for a button that is visible and enabled. A key therefore does exactly what clicking its button would do, and nothing when the button is hidden. That is why actions in different cards can share a key.
- The HUD adds the key to the button label, for example `Stop [S]`. Tooltips also list it.
- Typing in a text field, such as the route amount boxes, doesn't trigger shortcuts.

## Keys

| Card | Keys |
| --- | --- |
| Unit | M Move · A Attack · G Gather · S Stop · V Deliver · B Build · R Repair · C Capture · X Drop materials · T Auto-refuel · D Deploy into Depot |
| Cargo Supply panel | M Move · D Deploy/pack · T Auto-refuel · P Pause/resume route · X Cancel route |
| Depot | I Infantry · U Depot Truck · C Cargo Vehicle · T Train · B Build |
| Production building | I Infantry · S Scout · G Grenadier · T Tank · M Motorcycle · D Drone · U Übermech |
| Generator | P Pause/resume · F Focus assigned Depot |
| Construction plan | X Cancel plan |

Two camera keys moved: overview is now **O** (was M) and focus HQ is now **Backspace** (was F). Arrows, Q/E, Shift, wheel and Home are unchanged. Esc still cancels an armed command.

## Selection

- **Shift-click** a unit to add it to the selection or remove it. Shift-click on empty ground keeps the selection. Shift-click on a building selects the building as usual.
- **Shift-drag** adds the boxed units.
- **Double-click** a unit to select every friendly unit of the same type that is on screen.
- **Ctrl+1–9** saves the selected units as a group. **1–9** recalls it. Pressing the same number again within 0.4 s centres the camera on the group. Dead units drop out of groups, and recalling an empty group leaves the selection alone.

## Not included

- Build menu buttons (Depot, Generator, structures) have no keys yet.
- Mixed selections still show the first unit's card.
- The Supply panel still replaces the command card. Merging them is part of the Phase 4 layout work.
- Command queuing (Phase 3) and playtest tools (Phase 2).

## Validation

- `tests/hud_hotkeys_test.gd` (headless) checks:
  - the Input Map keys, the camera key moves, and that every button shortcut has a key;
  - no duplicate keys on the Infantry, Tank, Cargo or Depot cards;
  - key labels;
  - M arming Move and S stopping a unit;
  - a hidden button's key doing nothing, T on the Tank card and the Supply panel, and a focused text field blocking D;
  - Shift toggle and add, double-click same-type selection, and control group save, recall and pruning.
- `tests/hud_hotkeys_runtime_check.gd` (rendered) uses real window clicks and key presses. Its screenshots are `infantry_keys`, `group_recalled` and `tank_keys`.
- Needs a human playtest for feel and key choices.
