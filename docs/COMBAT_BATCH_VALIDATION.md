# Combat batch validation

Validated with Godot 4.7.2 stable in C:\Dev\Supply-Lines.

## Passed

- Editor headless import: no script/resource errors.
- Main scene headless startup (--quit-after 10): no errors.
- Twelve headless suites: combat_batch_test, unit_stats_test, production_batch_test, engineering_batch_test, skirmish_test, depot_test, supply_test, bottom_hud_test, hud_click_test, terrain_test, camera_test, edge_pan_test.
- Rendered Vulkan combat_batch_test: synthetic Attack button press/release and world-target clicks, building targeting, capture ownership stopping pursuit, splash/class damage, range/cooldown rejection, moving-fire roster and navigation, friendly/neutral protection, building death releasing footprint, compatibility fallback.
- Rendered Vulkan hud_click_test: production, infantry Build, world construction, and cargo route buttons through synthetic input events.
- Rendered combat_runtime_check: Tank and Grenadier HUD screenshots at 1280x900 visually inspected; info stays inside viewport. Output/error logs were clean.
- Skirmish and engineering suites rerun after final attack-target lifecycle change and passed.

The skirmish regression now commands the original worker to support the paid infantry against the unchanged prototype hostile. Its first-shot measurement follows the produced infantry's cooldown, so supporting fire cannot falsify the measured range. No enemy or unit balance values were altered to make this test pass.

## Reproduce

From PowerShell, run:

```powershell
& 'C:\Dev\Tools\Godot_v4.7.2-stable_win64_console.exe' --headless --path C:\Dev\Supply-Lines --script res://tests/combat_batch_test.gd
```

Omit --headless for the rendered combat/input check. Run res://tests/combat_runtime_check.gd with rendering enabled to reproduce HUD screenshots. Their output directory is the current ChatGPT workspace, specified at the bottom of that script.

## Limits

Synthetic events and scripted stepping are automated runtime checks, not live/physical input testing. Visuals remain existing placeholders; shots use the existing tracer. Drone attack/range, terrain abilities, rail/train rules and tentative abilities remain pending. Splash radius and targeting/cooldown decisions are provisional implementation rules documented in COMBAT_BATCH.md. Existing standing-hostile behavior remains; no enemy pressure system was added.

Exact source/document/test files changed are listed in COMBAT_BATCH_CHANGED.txt; Godot's generated .godot cache is excluded.
