# Depot production correction validation

Godot 4.7.2: all 15 headless suites passed: depot_correction_test, unit_stats_test, combat_batch_test, skirmish_test, production_batch_test, engineering_batch_test, depot_test, supply_test, bottom_hud_test, hud_click_test, terrain_test, camera_test, edge_pan_test, terrain_abilities_test and rail_batch_test.

Direct coverage rejects rich Depot Infantry requests without charging stock/queueing, hides the Depot Infantry card, and checks recovery through the one-time construction grant. Existing production coverage checks free grant exactly once and repeatable Barracks Infantry. The skirmish now funds a Barracks plus Infantry from actual delivered ore (65 iron total); its gathering allowance was extended for the extra trips. Its surviving Infantry performs final depletion/order checks if the supporting worker died in combat. Depot/supply/HUD paid-queue checks use Cargo Vehicles instead of the removed Depot Infantry job, with the same existing 100 E / 20 I costs.

Rendered production_batch_test passed with synthetic press/release events for building construction and Barracks production. No live/physical mouse testing was performed. Editor import/startup checks completed without errors. ECONOMY_PLAN.md is a proposal, not a claim that the future systems or proposed numbers are implemented.
