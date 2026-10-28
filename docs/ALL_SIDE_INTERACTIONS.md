# All-side harvesting and Depot delivery

Completed October 19, 2026 in C:/Dev/Supply-Lines. This finishes the requested all-side interaction follow-on after selection, pending construction and remote route assignment.

## What changed

Harvesters and ordinary Cargo Vehicles now consider every traversable standing cell inside the target's existing interaction/drop-off radius. Candidates are ordered by distance from the approaching unit, with a stable grid tie-break. The existing terrain actor_path method checks each candidate until one is reachable. This replaces the six preferred directions previously used for these interactions, so units can use their near side, corners and an off-axis entrance without circling to a favored side.

All paths still come from the existing terrain AStarGrid2D, including its no-corner-cutting rule. Target footprints, other actors' current/next-cell claims and impassable terrain remain excluded by can_traverse. Movement still revalidates and reserves each next cell. Concurrent workers wait/replan through the existing movement logic rather than claiming the same cell.

The new approach applies to shared mines, ordinary forest-tile handles, authored wood stands, material piles, Infantry delivery to available Depots/mobile supplies, and ground cargo loading/unloading. Train delivery explicitly delegates to its existing friendly-rail loading-area search; it never receives an ordinary ground approach. Attack, Repair and Capture retain their previous approach selection and ranges.

No configured range was enlarged: harvesting remains 4 units, Depot delivery/loading remains 7, mobile delivery remains 3.5, and all original capacity, timer, ownership, payer and conservation policies remain. Valid Depot foundation/model clicks continue using the visual selection bounds from the selection milestone. Paths use gameplay cells/ranges, not art meshes or replacement collision shapes.

Failed harvesting/delivery approaches keep their unreachable status until the next retry, instead of replacing it every frame with a misleading travel message. They retain cargo or leave the resource untouched and retry when an approach opens.

Live variable-frame input exposed an existing arrival precision problem: movement could mark a waypoint reached while still 0.0005 units short. An exact-radius approach then kept re-planning its already-reached cell and never began gathering. Completed waypoints now snap to their exact cell center inside the existing 0.001-unit arrival tolerance. This does not change speed, path cells or reservation policy. A deterministic fractional-step regression reproduces the former failure.

Changed harvesting timing also exposed a stale combat-target reference in the skirmish regression after its target was freed. The unit now checks validity before passing that reference into the typed combat helper and releases the lost order. Combat values and targeting rules are unchanged.

## Exact changed files

1. scripts/units/interaction_approach.gd (new) - enumerate all admissible cells and choose the nearest candidate reachable through existing terrain paths.
2. scripts/gameplay/unit_agent.gd - resource/Infantry delivery integration, visible blocked status, exact waypoint arrival and freed-target guard.
3. scripts/economy/cargo_vehicle.gd - use all-side ground approaches for timed loading/unloading.
4. scripts/rails/train.gd - explicitly retain friendly-rail approaches for train loading/unloading.
5. tests/all_sides_interaction_test.gd (new) - eight-sided actual movement/transfers, obstacle/claim cases and precision regression.
6. tests/all_sides_gui_test.gd (new) - actual mouse events for opposite-side harvesting and explicit Depot-corner delivery.
7. scenes/maps/all_sides_exercise.tscn (new) - saved demonstration with a 40-wood stand, opposite-side workers and WorkshopDepot.
8. docs/ALL_SIDE_INTERACTIONS.md (new) - this report.
9. docs/EXPLICIT_DESIGN_BACKLOG.md - completion status and suggested follow-ons.

No synced project sources, original map pixels, terrain category files, baked scenery, physics shapes, stat resources, camera code, pending-construction logic or Depot accounting implementation were edited. Normal editor import may generate new .gd.uid metadata.

## Automated validation

```powershell
& C:/Dev/Tools/Godot_v4.7.2-stable_win64_console.exe --headless --path C:/Dev/Supply-Lines --script res://tests/all_sides_interaction_test.gd
& C:/Dev/Tools/Godot_v4.7.2-stable_win64_console.exe --headless --path C:/Dev/Supply-Lines --script res://tests/all_sides_gui_test.gd
```

Remove --headless to run rendered checks. Both tests passed headlessly and with Vulkan on NVIDIA RTX 5070 Ti. The GUI test selects resource/unit models, sends right-click orders and clicks both visible Depot foundation corners using Viewport.push_input across multiple frames; it does not emit command-button signals.

all_sides_interaction_test covers:

- Harvesting, Infantry delivery, timed truck loading and timed truck unloading from all eight compass directions, staying on the approaching side when open.
- Claimed-footprint exclusion and exact inventory totals, including wood/iron/coal Infantry deposits.
- Four simultaneous deliveries with separate current/next-cell ownership and no overwritten reservations.
- A single reachable off-axis Depot entrance that the old six-direction function demonstrably cannot find.
- An isolated closest standing cell with fallback to a further reachable exact-radius cell.
- Fully sealed approaches: no extraction/corner cutting, then successful retry after blockers are removed.
- Fractional waypoint completion and exact-radius gathering, plus safe release of a freed combat target.

Fixtures use a confirmed empty region of the actual map. Obstacle cases temporarily occupy otherwise open cells and release those test claims. No map assets are modified.

The following existing suites passed during this milestone: harvesting_batch_test, skirmish_test, supply_test, mobile_supply_test, rail_batch_test, remote_routes_test, remote_routes_gui_test, storage_batch_test, engineering_batch_test, combat_batch_test, selection_usability_test, pending_construction_test, pending_construction_gui_test, hud_click_test, camera_test and edge_pan_test. These cover shared finite forest/mine reserves, rebuilt mines, mobile deployment, full/partial storage, route conservation, train restrictions, engineering/combat and the previous usability milestones. terrain_abilities_test also passed after the waypoint precision fix to check special movement layers.

The final precision fix was followed by rerunning the core eight-sided suite, GUI checks, harvesting/skirmish/supply/mobile/rail/remote-route/storage/engineering/combat/selection/construction/HUD/camera/edge-pan regressions. Logs are in the Supply Lines chat workspace: sides_verified_<test-name>.log and all_sides_gui_rendered_final.log. Rendered runs report the restricted environment's known shader-cache-folder warning; script checks and rendering complete.

## Native input validation

In the saved exercise, native OS mouse input box-selected EastHarvester and WestHarvester and issued one right-click harvest order on DemoWood. Both approached their own side. The first live run revealed the fractional-arrival bug described above. After restarting with the fix, the native-input run depleted all 40 wood, the selected units' Supply readout showed WorkshopDepot W40, both carried zero and returned to Idle. The exercise remains open for inspection; these runtime changes reset on restart.

The native window was shorter than the project's reference 1280x900 viewport. The minimap was used to bring the two workers into view; the same option is available if a smaller window places exercise actors behind the bottom HUD. The automated GUI exercise uses the reference viewport.

## Try it

1. Open scenes/maps/all_sides_exercise.tscn and press F6. The default playable main scene remains resource_skirmish.tscn.
2. Find the two workers beside the marked 40-wood stand and WorkshopDepot (world X186/Z180-195). Use the minimap if needed on a short window.
3. Box both workers and right-click the wood stand. Each should approach its near side, harvest and deliver. Two workers complete two 10-wood trips each; WorkshopDepot ends with 40 wood and the stand depletes.
4. To test an explicit delivery, stop a worker after it carries wood and right-click any visible Depot foundation side/corner. It should choose a reachable nearby approach and deposit only into that friendly selected stockpile.
5. Place actors or pending/finished structures near an approach. Pending plans alone do not block movement; real occupied cells do. Blocked workers retain cargo/resources and retry when a path opens.
6. Recheck shared forest tiles/mines in harvesting_exercise.tscn, deployed mobile stockpiles in mobile_supply_exercise.tscn, and trains in remote_routes_exercise.tscn. Train motion must remain on friendly connected rail.

## Remaining limits and suggested follow-ons

- All-side means all reachable standing cells within the existing center-based range. It does not permit walking through water/forest/ore/building claims or add range to oversized custom footprints. Existing range-based interactions do not gain a new line-of-sight rule.
- Candidate order favors the physically nearest reachable standing cell, not a globally shortest path among every possible endpoint. Blocked candidates fall back to others. Many unreachable candidates still require multiple ordinary path queries; large-army performance is not certified.
- Existing single-cell traffic can still deadlock in narrow passages. No crowd solver, formation planner, permanently reserved work slot or automatic terrain clearing was added.
- Repair/Capture/combat approach selection is unchanged; their own all-side/range policy can be considered separately.
- Suggested follow-ons: Shift-add/toggle selection and control groups; group ability controls that account for mixed types; transport passing/traffic controls; plan editing/priority and save/load. The three requested follow-ons (global pending construction, remote friendly-Depot route assignment, all-side harvesting/delivery) are now implemented with their documented limits.
