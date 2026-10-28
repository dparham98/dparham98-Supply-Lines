# Storage foundation validation

Godot 4.7.2 stable, authoritative project C:\Dev\Supply-Lines.

- All 16 headless suites passed: storage_batch_test, depot_correction_test, unit_stats_test, combat_batch_test, skirmish_test, production_batch_test, engineering_batch_test, depot_test, supply_test, bottom_hud_test, hud_click_test, terrain_test, camera_test, edge_pan_test, terrain_abilities_test and rail_batch_test.
- Storage coverage verifies combined capacity, invalid/negative requests, all-or-nothing spending, partial conservative transfers, refused unsafe capacity shrinking, self-transfer rejection, authored initial stock, coal rail transport, full-destination retained cargo, completion after space opens, Infantry partial deposits, independent clamped fuel reserves, cancellation retaining coal, Infantry lacking fuel, and full/partial generator output limits without banking.
- Rendered Vulkan storage_runtime_check uses synthetic Train selection and Assign-route button press/release. It assigns a coal-only route through the actual HUD, observes partial unloading/full-storage wait, frees storage and completes delivery. HUD screenshots at 1280x900 and 1440x960 were saved; Depot capacity and Train coal controls were visually inspected and viewport bounds checked.
- Final editor import, main/storage scene startup and rendered regressions completed without errors. Original map/scenery SHA-256 hashes remain unchanged.

No physical/live mouse testing was performed. Fuel reserves are state only: no consumption, refueling controls or movement restrictions. Coal deposits, shared buildable mines, universal forestry, mobile deployment, dropped material piles and generator fuel/water behavior remain later stages. Existing generation still produces free energy, but now pauses at full storage. Production stress fixtures explicitly use a larger capacity rather than bypassing stock limits.

Reproduce the headless checks with --headless --path C:\Dev\Supply-Lines --script res://tests/storage_batch_test.gd. Use res://tests/storage_runtime_check.gd without --headless for rendered synthetic input. The latter writes screenshots to the current ChatGPT workspace defined by OUTPUT. For manual editor testing open scenes/maps/storage_exercise.tscn and press F6; see STORAGE_BATCH.md.
