# Milestone 3 validation — October 15, 2026

Engine: Godot 4.7.2 stable on Windows. New supply scene initialization and final editor import completed without script/scene errors. The final supply regression completed with exit code 0, its explicit pass marker and no error output. Earlier expanded checks exposed and led to fixes for blocked-route status being overwritten between retries and a stale endpoint reference in HUD menus after a Depot was removed.

| Check | Result |
| --- | --- |
| tests/supply_test.gd | SUPPLY_CHECKS_PASSED |
| tests/unit_stats_test.gd | UNIT_STATS_CHECKS_PASSED |
| tests/skirmish_test.gd | SKIRMISH_CHECKS_PASSED |
| tests/depot_test.gd | DEPOT_CHECKS_PASSED |
| tests/terrain_test.gd | TERRAIN_CHECKS_PASSED |
| tests/camera_test.gd | CAMERA_CHECKS_PASSED |
| tests/edge_pan_test.gd | EDGE_PAN_CHECKS_PASSED |
| tests/supply_runtime_check.gd | SUPPLY_RENDER_CHECK_PASSED: rendered Vulkan runtime, screenshot inspection |

The supply regression assigns its first route through the actual HUD button signal and endpoint menus, then advances the dedicated vehicle through the original waypoint/path system. It checks conservation of energy and iron while loading, travelling and unloading. Two completed deliveries bootstrap an empty outpost without injecting new energy there; that outpost then pays for a generator, accumulates local energy and prints infantry. It also checks invalid endpoints/amounts, no idle transfers, local-only output, fractional generation, invalid generator placement without payment, footprint preview validity, capture of both route endpoints, latched pause through recapture, failed resume, partial loads, repeated return to source, waiting for depleted stock, cancellation/manual move retaining cargo, explicit reassignment of held cargo, cargo queue payment/spawning, endpoint removal and vehicle death. Adversarial later cases deliberately set stock and held cargo to exercise boundary conditions.

Existing checks cover unit resource reading and fallback combat, gather/deliver/print/ranged combat, Depot capture/deployment/local spending, terrain/path reservations, camera geometry/focus and edge-pan input policy. The original skirmish and preserved review world remain separate from the inherited supply exercise. Terrain scenery was not rebuilt, and the scene setup/baker test was not run because it rewrites generated map scenery unrelated to this change.

Rendered checks inspected the new exercise at 1440 × 960, including the saved left supply panel, local generation rate, source/destination selectors, amounts, route controls/status, generator/cargo placeholders, selected territory and placement feedback. Images and logs are in the Supply Lines chat workspace: milestone3_runtime.png, milestone3_preview.png, milestone3_runtime.log, milestone3_runtime_errors.log. Rendering uses direct scripted setup and no physical mouse/keyboard interaction. No live input test or live editor interaction is claimed. The runtime screenshot shows initial cargo travel, not a screenshot of the entire completed economy loop; that loop is covered by the headless simulation.

Limits: no save/load, multiplayer, new enemy strategy, building damage, salvage, route map overlays, generator reassignment or automatic Depot sharing. The original infantry placeholder remains; Blender integration is separate. Power has no storage cap/upkeep. Repeat routes are created explicitly by the player and partial loads depart; zero stock waits. Two fixed side panels may crowd narrow windows; visual inspection was at the size above. Existing pathing retries blocked approaches but does not implement a new crowd solver. The logistics exercise retains the original skirmish victory message; completion of its supply loop is a documented manual goal.

See MILESTONE_3.md for exact prototype balance, ownership/transfer rules and editor tests. MILESTONE_3_CHANGED.txt lists authored files and new generated script UID files, excluding ignored .godot cache. Before-change copies of existing authored files are retained in the chat workspace milestone3_before folder.
