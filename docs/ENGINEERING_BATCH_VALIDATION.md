# Engineering batch validation

Godot 4.7.2 stable on Windows. Final imports/startup completed without resource/script errors. An initial infantry scene resource declaration was placed after subresources; this was corrected before the successful runs. Repair approach initially continued to its old path endpoint after entering work range; it now stops unnecessary approach waypoints and begins work in range. The rendered GUI test now waits for stable visible control geometry after selection changes; its initial three-frame assumption was not reliable for nested rendered layout.

| Check | Result |
| --- | --- |
| tests/engineering_batch_test.gd | ENGINEERING_BATCH_CHECKS_PASSED, headless and rendered GUI |
| tests/production_batch_test.gd | PRODUCTION_BATCH_CHECKS_PASSED |
| tests/skirmish_test.gd | SKIRMISH_CHECKS_PASSED |
| tests/depot_test.gd | DEPOT_CHECKS_PASSED |
| tests/supply_test.gd | SUPPLY_CHECKS_PASSED |
| tests/bottom_hud_test.gd | BOTTOM_HUD_CHECKS_PASSED |
| tests/hud_click_test.gd | HUD_GUI_CLICK_CHECKS_PASSED |
| tests/unit_stats_test.gd | UNIT_STATS_CHECKS_PASSED |
| tests/terrain_test.gd | TERRAIN_CHECKS_PASSED |
| tests/camera_test.gd | CAMERA_CHECKS_PASSED |
| tests/edge_pan_test.gd | EDGE_PAN_CHECKS_PASSED |
| tests/engineering_runtime_check.gd | ENGINEERING_RENDER_CHECK_PASSED |

The engineering test sends pointer motion and press/release events through Viewport.push_input with five frames between press and release, rather than emitting button signals. It checks Repair, Gather and Capture GUI target selection; actual path travel to work; exact repair payment/HP limits; no full-health charges; typed wood delivery without iron credit; returning held wood before an iron-source switch; neutral-mine extraction rejection; contested capture reset; uncontested capture retaining reserves; subsequent extraction and physical delivery; ownership-loss rejection; wood-only cargo routes, combined capacity and in-transit wood conservation; no rich-neighbour repair borrowing; partial final ticks; payer capture/pause and recovery; repair preserving carried cargo; finite wood payout; depleted-wood footprint release; exhausted-mine footprint retention; and no resurrection of destroyed targets.

Existing regressions cover unchanged unit resources/fallback combat, gather/print/fight, Depot ownership and independent inventories, actual supply paths, production/free infantry, HUD GUI clicks, terrain/path occupancy, camera and edge-pan policy. The production test also verifies new roster prototypes do not acquire repair or capture capabilities. Normal-economy fixtures continue overriding the sandbox iron grant only in their process; the on-disk 500-iron testing grant remains enabled. The seven unit .tres resources, original source map, raw terrain data, baked scenery and camera script were not changed. The scene-baker test was not run because it rewrites unrelated generated scenery.

Rendered images were visually inspected at 1280 × 900 for engineering commands, repair state, carried wood, mine ownership/progress/reserves and the third cargo amount field; cargo layout was also inspected at 1440 × 960. Images and logs are in the chat workspace: engineering_commands.png, engineering_repair.png, engineering_wood.png, engineering_mine.png, engineering_cargo_wood.png, engineering_wide.png, engineering_runtime.log, engineering_runtime_errors.log, engineering_gui_runtime.log and engineering_gui_runtime_errors.log. The screenshot fixture uses direct scripted setup; the separate rendered engineering regression exercises synthetic GUI clicks and deterministic work simulation. No physical mouse/keyboard testing or live editor interaction was performed. Temporary diagnostic probes were preserved outside the Godot project.

Scope limits and provisional decisions: wood is harvested from authored stands, not all baked decorative forest trees; no regrowth or source-map terrain clearing. Wood has no spending/conversion rule yet. Mines are finite authored capture sites, not buildable automatic extractors; infantry carries their iron to Depots. Repair amount, cost, range and interval, mine stock/footprint/HP and capture timing are editable prototype values. A final partial repair charges one full tick. Repair is local and payer-bound; mines latch a nearest covering friendly Depot once, whereas Depots pay themselves and generators/production buildings use their fixed assigned Depot. Payer ownership/fund restoration can resume the same repair order. Existing opponent behavior, combat notation fallback, unit special abilities and later rails/trains remain unchanged/pending.

See ENGINEERING_BATCH.md for the rules/editor workflow and ENGINEERING_BATCH_CHANGED.txt for exact authored/new UID files, excluding ignored .godot cache. Before-change copies are in the chat workspace engineering_batch_before, outside the Godot project scan. EXPLICIT_DESIGN_BACKLOG.md records completed engineering requirements with these limits rather than marking later terrain/forestry behavior complete.
