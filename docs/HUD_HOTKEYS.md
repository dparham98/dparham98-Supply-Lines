# HUD phase 1: hotkeys and selection

Phase 1 of the HUD plan (hotkeys, queuing and HUD modernization), approved on 2026-10-28 with the recommended defaults. Branch `feature/hud-commands`, stacked on `feature/vehicle-fuel`. These are new controls, not recovered design.

## How hotkeys work

- Each command button in `scenes/ui/skirmish_hud.tscn` (command card and cargo Supply panel) has an authored `Shortcut` holding an `InputEventAction`. The keys themselves live in the Input Map (`project.godot`), saved by `scripts/tools/setup_command_actions.gd`, so they can be rebound in one place.
- Godot only fires a shortcut for a button that is visible and enabled. A key therefore does exactly what clicking its button would do, and nothing when the button is hidden. That is why actions in different cards can share a key.
- The HUD adds the key to the button label, for example `Stop [S]`. Tooltips also list it.
- Typing in a text field, such as the route amount boxes, doesn't trigger shortcuts.

## Keys

The current keys, as set on 2026-11-15. `scripts/tools/setup_command_actions.gd` and `setup_camera_actions.gd` save them to the Input Map.

| Card or page | Keys |
| --- | --- |
| Infantry and combat units | M Move · S Stop · A Attack · G Gather · V Deliver · X Drop materials · R Repair · C Capture · T Auto-refuel (vehicles) |
| Cargo truck / Train | M Move · S Stop · T Auto-refuel · D Deploy/Pack supplies · E Load · V Unload · C Trips · W Worksite (not Trains) |
| Depot truck | M Move · S Stop · T Auto-refuel · D Deploy |
| Depot | D Depot truck · V Cargo vehicle · T Train · C Make crates · X Cancel production (the Generator settings are sliders on the Depot panel, docs/DEPOT_PANELS.md) |
| Production building | F Infantry · S Scout · G Grenadier · T Tank · C Motorcycle · D Drone · Q Übermech |
| Generator | R Pause/Resume · W Burn wood · C Burn coal · E Burn either · F Focus Depot |
| Construction plan | X Cancel plan |
| Build page (B) and Worksite page | D Depot · G Generator · B Barracks · T Tank Factory · A Iron Mine · R Rail · P Pin payer (Build page only) · Esc Back |
| Laying rail | R next piece (straight, left and right curve, left and right fork) · F turn a free piece · G change a fork's joining end · Shift-click keep laying · Esc finish |
| Load page | A Iron · E Energy · W Wood · C Coal · X Clear · Esc Cancel. Shift fills free slots |
| Make crates page | A Iron · E Energy · W Wood · C Coal · Esc Cancel. Shift makes five |

Camera: arrows pan (Shift for fast), wheel zooms, **O** overview, **Space** focus HQ, **Home** focus selection, hold **Alt** to show every health bar. There is no rotate key. Space is read before the HUD, so a HUD button that still has focus after a click never takes it as a press. A focused text field or dropdown, or an open popup or dialog, keeps Space instead. **F10** opens the playtest tools.

## Selection

- **Shift-click** a unit to add it to the selection or remove it. Shift-click on empty ground keeps the selection. Shift-click on a building selects the building as usual.
- **Shift-drag** adds the boxed units. Shift may be pressed before or during the drag (`docs/SELECTION_PORTRAITS.md`).
- **Portraits** of a multiple selection: click keeps one unit, Shift-click removes it, Ctrl-click keeps its type, Ctrl+Shift-click removes its type.
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
- All 29 headless suites passed through `ci/run_headless_checks.sh` on Windows, and every rendered check passed except the known `mobile_supply_runtime_check` failure that predates this branch.
- In one batch run, `fuel_runtime_check` and `hud_hotkeys_runtime_check` each failed once on their first synthetic click. Both then passed 12 out of 12 re-runs, so this looks like the real cursor interfering with the window, not a code failure. Treat a single failure there as a reason to re-run, not as proof.
