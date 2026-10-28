# Milestone 2 validation — October 15, 2026

Godot 4.7.2 stable, Windows. Final editor headless import completed without script/scene errors. All checks below completed with exit code 0 and their explicit pass marker; no script error appeared in their output.

| Check | Result |
| --- | --- |
| tests/depot_test.gd | DEPOT_CHECKS_PASSED: local production costs, failed payment, construction footprint/radius, independent inventories, selected territory, truck printing, invalid deployment retention, contested and timed capture, queue cancellation, inventory retention, friendly local delivery, expansion deployment, no tick transfers |
| tests/unit_stats_test.gd | UNIT_STATS_CHECKS_PASSED |
| tests/skirmish_test.gd | SKIRMISH_CHECKS_PASSED: gather/deliver/print/ranged kill, continuing orders, blocked exits, finite resource; rerun after final selection refinements |
| tests/terrain_test.gd | TERRAIN_CHECKS_PASSED |
| tests/camera_test.gd | CAMERA_CHECKS_PASSED |
| tests/edge_pan_test.gd | EDGE_PAN_CHECKS_PASSED |
| tests/depot_runtime_check.gd | DEPOT_RENDER_CHECK_PASSED: non-headless Vulkan runtime, authored world/actors/HUD, printed truck, selected Depot ring; saved screenshot visually inspected |

Rendered screenshot and stdout/stderr logs are in the Supply Lines chat workspace as milestone2_runtime.png, milestone2_runtime.log and milestone2_runtime_errors.log. The rendered fixture supplies 100 test iron and advances printing by method call; it does not simulate a real user gathering that stock. Headless tests use direct controller methods, selection methods and deterministic time steps. No live input, mouse feel, editor clicking or physical edge scrolling was tested. No scene rebuild/baker test was run because that test rewrites terrain scenery and this milestone does not change those assets.

Limitations: no energy generator/automatic transfer; finite scenario starter energy; directly built Depots are empty; trucks are stretched engineer placeholders; construction is instantaneous; territory is an outline without terrain clipping or placement ghost; no new enemy strategy, save/load, building damage or multiplayer. See MILESTONE_2.md for explicit balance decisions, capture/overlap rules and editor checks. Historical docs describe the earlier Ore economy; MILESTONE_2.md supersedes it. Exact authored and generated UID changes are in MILESTONE_2_CHANGED.txt; ignored Godot cache is excluded.
