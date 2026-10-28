# Production batch validation

Godot 4.7.2 stable on Windows. This implements the first original-design batch, not later combat/terrain abilities. Final editor import completed without script/class errors after moving before-change backups out of the Godot project into the chat workspace. An earlier final import caught a backup DepotRules script being scanned as a duplicate global class; its registered path now resolves only to scripts/economy/depot_rules.gd.

| Check | Result |
| --- | --- |
| tests/production_batch_test.gd | PRODUCTION_BATCH_CHECKS_PASSED, headless and rendered GUI runs |
| tests/skirmish_test.gd | SKIRMISH_CHECKS_PASSED |
| tests/depot_test.gd | DEPOT_CHECKS_PASSED |
| tests/supply_test.gd | SUPPLY_CHECKS_PASSED |
| tests/bottom_hud_test.gd | BOTTOM_HUD_CHECKS_PASSED |
| tests/hud_click_test.gd | HUD_GUI_CLICK_CHECKS_PASSED |
| tests/unit_stats_test.gd | UNIT_STATS_CHECKS_PASSED |
| tests/terrain_test.gd | TERRAIN_CHECKS_PASSED |
| tests/camera_test.gd | CAMERA_CHECKS_PASSED |
| tests/edge_pan_test.gd | EDGE_PAN_CHECKS_PASSED |
| tests/production_batch_runtime_check.gd | PRODUCTION_RENDER_CHECK_PASSED |

The production regression uses Viewport mouse motion and press/release events separated by five process frames, not direct button signal emission, for Depot Build, Barracks/Factory selection, map placement and all seven production entries. It verifies exact original building costs and per-unit costs, assigned local payment, accepted/rejected rosters, queue caps, blocked exit retention/resumption, source-capture cancellation, no rich-neighbour borrowing, full roster spawning, no accidental infantry capabilities or unresolved attacks on new prototype units, one free construction infantry without resource payment or paid-objective credit, exactly-once lifetime grants, blocked grant retry, cancellation before capture, no regrant on recapture, truck establishment grants and defeat recovery through paid production. The rendered GUI run passed before the final additional poor-source/rich-neighbour assertion; the complete final version passed headlessly.

Existing regression fixtures were updated only for the explicitly corrected Depot cost and the restored Depot Build command. Normal economy tests retain their in-memory no-grant fixture settings; on-disk sandbox inventories still grant 500 iron. The seven unit .tres resources, original map images/raw terrain, original camera script and navigation methods were not changed. The scene-baker test was not run because it rewrites unrelated generated terrain scenery.

Rendered screenshots were visually inspected at 1280 × 900 for Depot structure build menu, Barracks roster and Factory roster, and at 1440 × 960 for the produced placeholder roster. HUD controls fit, local resources/source and original costs are visible, and world actors/rendering remain present. Screenshots: production_depot_build.png, production_barracks.png, production_tank_factory.png, production_roster_wide.png in the chat workspace. Render/GUI logs: production_runtime.log, production_runtime_errors.log, production_gui_runtime.log, production_gui_runtime_errors.log. Tests use scripted setup and synthetic GUI events; no physical mouse, keyboard or live editor input was performed.

Limits: new six unit types are production/selection/movement prototypes with unresolved attacks disabled. Drone is ground-bound until its flight batch; Scout/Tank forest behavior, moving fire, splash/target-class bonuses, mines, wood, repair and rails/trains remain pending. Building footprints, HP, queue caps and print duration are provisional editable values. A production building's Depot binding is fixed; no reassignment control or independent inventory exists. Capture cancels paid jobs without refund. Free construction infantry only applies automatically to newly established Depots, waits for a safe exit, and is cancelled if captured before fulfillment. Prebuilt map Depots keep authored units. No new enemy strategy was introduced.

See PRODUCTION_BATCH.md for rules and editor checks, PRODUCTION_BATCH_CHANGED.txt for exact authored/new UID files, and EXPLICIT_DESIGN_BACKLOG.md for updated partial/complete statuses. Before-change files are preserved in the chat workspace production_batch_before; earlier generated backup folders were also moved into the workspace to keep Godot from scanning backup scripts. Ignored .godot cache is excluded from the authored file list.
