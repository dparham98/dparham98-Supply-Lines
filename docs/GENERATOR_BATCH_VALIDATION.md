# Generator stage validation

Godot 4.7.2, 2026-10-16. All 19 headless regression suites passed:

- tests/generator_batch_test.gd
- tests/mobile_supply_test.gd
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

generator_batch_test verifies: no free/borrowed energy; wood/coal timing and quantities; correct nominal Depot rates; next-cycle preference changes; coal-only behavior; Either wood-first/fallback; full storage and capacity filled mid-cycle; no blocked-time banking; fuel removed/restored mid-cycle; pause/resume; capture resetting unfinished work without fuel loss; explicit reassignment without stock transfer; rejection of a mobile operating wallet; two generators competing for one wood; destruction without pending fuel loss; multiple completed cycles in a long tick; destroyed-source handling.

Existing supply/storage/mobile-generator tests were updated for the intentional removal of free power: they now supply explicit wood, expect whole-cycle output, and check full-cycle output space. Transport, construction, production, mine/forest, combat, camera/edge pan, terrain mobility and HUD assertions remain in place.

Rendered generator_runtime_check passed under Vulkan on NVIDIA GeForce RTX 5070 Ti. Synthetic mouse motion/press/release selects Generator, chooses Wood/Coal/Either through the actual embedded dropdown popup, pauses/resumes a pending cycle, handles empty/full storage, and explicitly chooses a different operating Depot. It checks inventory after each action. Screenshots were inspected at 1280x900 and 1440x960. This test manually advances simulation with actor processing disabled for repeatability; no button signals are emitted by the rendered test.

Editor import and normal game/generator exercise startup checks passed without reported errors. Hash checks confirm original source_map.png, terrain_data.png, terrain_cells.bin and terrain_landmarks.tscn remain unchanged. UnitStats resources and movement/combat implementations were not modified.

No live physical mouse/keyboard testing was performed. Water generation, coal deposit harvesting, vehicle fuel use/refueling and Drone recovery remain deferred. This batch uses editable documented prototype conversion values, local Depot inventories, no generator-owned storage, and no new balancing/map redistribution. See GENERATOR_BATCH.md for operating decisions and editor steps; GENERATOR_BATCH_CHANGED.txt lists exact project files.
