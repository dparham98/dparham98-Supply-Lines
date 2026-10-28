# Harvesting batch validation

Validated with Godot 4.7.2 on 2026-10-16.

All 17 headless regression suites passed:

- tests/harvesting_batch_test.gd
- tests/storage_batch_test.gd
- tests/depot_correction_test.gd
- tests/unit_stats_test.gd
- tests/combat_batch_test.gd
- tests/skirmish_test.gd
- tests/production_batch_test.gd
- tests/engineering_batch_test.gd
- tests/depot_test.gd
- tests/supply_test.gd
- tests/bottom_hud_test.gd
- tests/hud_click_test.gd
- tests/terrain_test.gd
- tests/camera_test.gd
- tests/edge_pan_test.gd
- tests/terrain_abilities_test.gd
- tests/rail_batch_test.gd

The initial supply regression found inconsistent text encoding in transport state labels. Labels and the affected assertion were corrected, and supply_test passed on rerun. Other suites passed in the broad run.

Rendered harvesting_runtime_check.gd passed using Vulkan on NVIDIA GeForce RTX 5070 Ti, including a final rerun after feedback and label fixes. It synthesizes mouse press/release events to select Depot and Infantry, open Build and place mines, repair a shared mine, right-click forest, and use the Gather command card. Wood reaches the local Depot and depleted tiles clear. Screenshots were inspected at 1280x900 and 1440x960.

The editor import and normal game/harvesting_exercise scene startup checks passed without reported errors. Protected source map, terrain data, cell data and baked landmark hashes remain unchanged.

No live human mouse/keyboard testing was performed. Synthetic input checks do not establish physical input behavior on every setup. See HARVESTING_BATCH.md for editor steps and remaining limitations, including coarse existing canopy visuals, single-cell gather orders, and later fuel/mobile supply stages.
