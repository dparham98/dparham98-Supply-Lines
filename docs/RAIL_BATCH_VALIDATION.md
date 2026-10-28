# Rail batch validation

Godot 4.7.2 stable, C:\Dev\Supply-Lines.

## Passed checks

- All 14 headless suites: rail_batch_test, terrain_abilities_test, unit_stats_test, combat_batch_test, skirmish_test, production_batch_test, engineering_batch_test, depot_test, supply_test, bottom_hud_test, hud_click_test, terrain_test, camera_test and edge_pan_test.
- Rail end-to-end regression covers selected local payer, overlapping poor/rich territories, invalid/duplicate placement, track versus footprint occupancy, disconnected graph rejection, no idle transfers, train prepayment and rail-only spawning, invalid route/capacity rejection, exact E/I/W loading and unloading, partial loads, explicit repeating routes, traffic blocking, cut/reconnected tracks, capture/recapture with explicit resume, cancel/death cargo handling, and blocked train-exit queue retries.
- Rendered Vulkan rail_runtime_check: synthetic mouse press/release on Train production, Build/Rail, two consecutive world rail placements, Esc, Train selection, route assignment and Pause/Resume. Scripted travel delivers exactly assigned resources. Screenshots at 1280x900 and 1440x960 were saved; Depot card, rail construction and loaded-train views visually inspected. Error logs clean.
- Editor import, normal/exercise scene startup and rendered rail regression were checked after integration. Generated .godot cache is excluded from changed-file reports.
- SHA-256 hashes of original source_map.png, terrain_data.png, terrain_cells.bin and baked terrain_landmarks.tscn remain unchanged.

No physical/live mouse testing was performed. The rendering tests use synthetic events and deterministic stepping. Visuals are minimal saved placeholders. No heavy traffic/load performance certification, articulated carriage physics, rail demolition/combat, signals, derailment, automatic transfers, or new enemy strategy was introduced.

## Reproduce

```powershell
& 'C:\Dev\Tools\Godot_v4.7.2-stable_win64_console.exe' --headless --path C:\Dev\Supply-Lines --script res://tests/rail_batch_test.gd
& 'C:\Dev\Tools\Godot_v4.7.2-stable_win64_console.exe' --path C:\Dev\Supply-Lines --script res://tests/rail_runtime_check.gd
```

For manual editor testing open scenes/maps/rail_exercise.tscn and press F6; instructions and inherited prototype limits are in RAIL_BATCH.md. Screenshots are written to the ChatGPT workspace configured by OUTPUT in rail_runtime_check.gd. Exact source/resource/scene/document files changed are listed in RAIL_BATCH_CHANGED.txt.
