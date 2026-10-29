# HUD phase 2: playtest tools

A development-only panel that shortens playtest setup. It is phase 2 of the approved HUD plan, on branch `feature/playtest-tools` from main `a587ffa`. It is a testing aid, not a game mechanic.

## Opening it

- Press **F10** (Input Map action `playtest_tools`). It only opens when the skirmish's `playtest_tools` export is on and the build is a debug build (`OS.is_debug_build()`), so exported release builds never show it.
- `resource_skirmish.tscn` turns it on, and the exercise scenes inherit that. `skirmish.gd` defaults it to off.
- The panel is authored in `scenes/ui/playtest_panel.tscn` and placed inside the HUD scene. Its spawn list is the `spawn_scenes` export on that scene.

## What it does

All changes are immediate and unpaid.

- **+100 Energy / Iron / Wood / Coal:** adds to the selected friendly Depot. If no Depot is selected, it goes to the selected friendly Cargo vehicle or Train. Storage capacity is respected and the panel says when storage is full. This covers loading coal into a Cargo Truck without the deploy or route workarounds.
- **Fill / Empty selected fuel:** sets every selected fuel-using vehicle to a full or empty tank. Filling also clears out-of-fuel.
- **Spawn at click:** choose a unit and a team (Player or Enemy), click the button, then click open ground. The unit snaps to the nearest cell it can use. Shift-click keeps placing; Esc or right-click stops. The spawn click doesn't change the selection. Spawned vehicles start fuelled. Trains aren't listed because they need rails.
- **Pause / Resume:** pauses the game tree. The HUD, camera, selection and the panel keep running (process mode Always), so you can look around and inspect while paused. World orders, including right-click, are ignored until you resume. Pausing cancels any armed command or placement, and while paused Esc or a world click cancels one armed from the HUD, so nothing stays stuck.
- **1× / 2× / 4×:** sets `Engine.time_scale`. The camera divides out the time scale, so pan and zoom speed don't change.
- **Restart:** reloading the scene always resets to unpaused 1× speed.

## Limits

- Enemy units spawned this way use player-coloured visuals. Only hostile.tscn has enemy visuals, and it isn't in the list.
- There's no undo and no logging of what was added.
- The panel blocks edge panning while the pointer is over it, like any other panel.

## Validation

- `tests/playtest_tools_test.gd` (headless) checks:
  - the F10 gate, and that the panel stays closed when the switch is off;
  - nothing being added when no target is selected, Depot coal, and Depot capacity;
  - Cargo vehicle coal within capacity;
  - fuel fill and empty;
  - the spawn list, enemy spawns, and an armed spawn click that leaves the selection alone;
  - pause process modes and button label, 4× speed, and a reload resetting pause and speed.
- `tests/playtest_tools_runtime_check.gd` (rendered) uses a real F10 press and real clicks. Its screenshots are `panel_depot` and `panel_paused`.
- Needs a human playtest.
