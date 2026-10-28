# Remote friendly-Depot route assignment

Implemented October 16, 2026 in C:/Dev/Supply-Lines after global pending construction. This milestone separates choosing a supply route from being able to travel it now.

## Behavior

- Trucks and trains can be assigned any two different living friendly Depots anywhere on the map. The vehicle need not occupy either Depot's construction/supply/drop-off range. Current source stock is not an assignment prerequisite. Cargo must still be nonnegative, nonzero and within combined vehicle capacity.
- Truck assignment was already distance-independent in the existing controller. This milestone verifies a truck outside both endpoint territories through an actual approach/load/travel/unload cycle, strengthens endpoint/lifecycle validation and clarifies the global Depot choices in the HUD.
- Train assignment previously rejected a friendly pair unless both loading areas were connected to the train's current rail cell. It now stores that assignment and shows Route assigned / waiting for friendly rails. The train remains stationary, with no remote transfers or loading, until the train and both loading areas share a friendly rail network.
- The initial connection becoming ready automatically starts an unpaused waiting route. A manually paused waiting route stays paused even when connected. Resume before initial connection resumes waiting.
- A connection lost after execution begins still pauses and retains cargo. Repair/recapture does not auto-resume that interrupted route: use Resume explicitly. The existing rail-only movement, cardinal topology and occupancy/traffic checks remain in force.
- Endpoint capture or removal pauses either vehicle type immediately. A dead, hostile, neutral, freed, queued-for-deletion or non-Depot endpoint cannot be assigned. Dead vehicles cannot accept assignments. Invalid requests return a concrete reason and leave an existing accepted route and carried cargo intact.
- Assigning/resuming a route still packs deployed supplies first using the existing two-second transition. Waiting routes do not expose deployed stock for spending. Cancel/manual Move clears the route and train waiting state while retaining cargo. Reassignment with held cargo continues to deliver it to the newly selected destination first.
- Delivery dropdowns list all living friendly Depots, independent of distance. Labels and tooltips explain this. The status displays the actual assigned pair and current phase/wait state; the command hint displays capacity. Error messages distinguish invalid endpoints, amounts/capacity and missing rails on Resume.
- Per-kind transfer timers, partial loads, full-destination waits, repeats, ownership, local inventories, unit stats, camera/selection and construction rules remain unchanged.

## Exact changed files

1. scripts/economy/cargo_vehicle.gd - shared request/endpoint validation, precise errors, immediate endpoint-removal pause and distance-independent assignment documentation.
2. scripts/rails/train.gd - accepted waiting assignments, initial-connect auto-start, explicit interrupted-route Resume and cancellation cleanup.
3. scripts/gameplay/skirmish_hud.gd - all-live-friendly choices, clearer route status/capacity hints and exact assignment/resume error feedback.
4. scenes/ui/skirmish_hud.tscn - global endpoint labels and reserved two-line route-status space.
5. scenes/maps/remote_routes_exercise.tscn (new) - inherited rail exercise with one missing rail segment and a distant friendly Depot. The hidden inherited gap placeholder has no script, so it neither registers as rail nor blocks rebuilding that cell.
6. tests/remote_routes_test.gd (new) - distant truck delivery/conservation, invalid requests, isolated/disconnected train assignment, wait/connect/pause/cancel behavior and exercise checks.
7. tests/remote_routes_gui_test.gd (new) - viewport mouse-event checks for assignment, wait feedback, Pause/Resume, Cancel and invalid-capacity feedback.
8. docs/REMOTE_DEPOT_ROUTES.md (new) - this report.
9. docs/RAIL_BATCH.md - current-behavior note superseding the old assignment prerequisite.
10. docs/EXPLICIT_DESIGN_BACKLOG.md - completed route milestone and remaining all-side interactions.

New Godot script .uid metadata may be created by normal editor import. No terrain source image, navigation solver, map cell data, balances, capacities, costs or unit resources were changed. No GitHub/archive workflow was used.

## Validation

```powershell
& C:/Dev/Tools/Godot_v4.7.2-stable_win64_console.exe --headless --path C:/Dev/Supply-Lines --script res://tests/remote_routes_test.gd
& C:/Dev/Tools/Godot_v4.7.2-stable_win64_console.exe --headless --path C:/Dev/Supply-Lines --script res://tests/remote_routes_gui_test.gd
```

Both tests pass headlessly. The GUI test also passes in rendered Vulkan on NVIDIA RTX 5070 Ti. Its actual mouse events span multiple frames; it does not emit command-button signals. Rendered clicks wait for completed layout before deriving control coordinates. Initial rendered testing exposed layout-timing sensitivity; the final version reserves route-status height, keeps the hint to one line and synchronizes the test to a completed draw. Two successive rendered runs passed after that correction.

remote_routes_test verifies a reachable truck starts outside both endpoints' 35-unit construction radii, assignment does not teleport or transfer, then actual navigation completes delivery of energy/iron/wood/coal while checking conservation every step. It rejects same/neutral/non-Depot/dead endpoints, over-capacity/negative/zero requests and dead vehicles without replacing the accepted route. Endpoint freeing pauses and retains cargo. It verifies assignment for a train outside both territories, disconnected waiting with no motion/loading, manual-pause latching through reconnection, explicit resume, automatic start of a fresh waiting route, retained-cargo delivery, interrupted-line explicit repair/resume, cancellation cleanup, and the saved exercise's real gap/remote Depot.

Existing regression suites passed: supply_test, rail_batch_test, mobile_supply_test, storage_batch_test, generator_batch_test, hud_click_test, bottom_hud_test, selection_usability_test, pending_construction_test, pending_construction_gui_test, skirmish_test, camera_test and edge_pan_test. They cover partial/repeating delivery, capacity/conservation, captured endpoints, active rail cuts, shared traffic, mobile packing and the previous usability milestones.

Native desktop mouse input in remote_routes_exercise confirmed selecting the Train, choosing the distant RemoteDepot from the dropdown, accepting the route with a waiting status and no early source debit, replacing it with Depot to EastDepot across the missing segment, and building that rail through the global Build menu. Completion of that rail automatically began the Train's normal loading timer. The rail cost came from one local Depot under the existing explicit Auto payer policy. The validation session is left open for inspection; its rail/delivery changes are runtime-only.

Logs are in the Supply Lines chat workspace: remote_routes_final.log, remote_routes_gui_test.log, remote_routes_gui_rendered_1.log, remote_routes_gui_rendered_2.log, remote_routes_live.log and routes_<regression-name>.log. Rendered runs retain the restricted runtime's known shader-cache-folder warning, with successful rendering/test completion.

## Manual exercise

1. Open scenes/maps/remote_routes_exercise.tscn and run it (F6). The main scene remains resource_skirmish.tscn.
2. Select the Train below Depot. Its destination list includes EastDepot and RemoteDepot, even though RemoteDepot lies beyond current coverage and has no rail branch.
3. Assign Depot to RemoteDepot with valid cargo. Expect accepted/waiting, no movement and no early stock debit. Pause, Resume waiting, or Cancel to verify retained assignment/cargo behavior.
4. Reassign Depot to EastDepot. It waits for the one-cell gap in the middle of the visible rail line.
5. Header Build > Rail; click that gap (world 185.5, 0, 156.5). The pending rail completes from a covering local Depot and the initial waiting route starts automatically. Loading/unloading use the existing two-second timers.
6. To repeat reliably from the original fixture, restart the scene. Check invalid combined cargo above 300 on the Train and above 100 on a truck, and identical endpoints: the old accepted route should remain and the HUD should explain the rejection.
7. Run supply_routes.tscn for ordinary Cargo Vehicle routes; move a truck beyond both Depot territories, then assign the two friendly endpoints. It should approach its source using existing ground paths and load only on arrival.

## Remaining limits / next milestone

Assignment cannot create a physical route. An isolated/off-rail train waits until friendly rails reach its current cell and both loading areas; it never travels over open land to reach rail. Truck routes continue retrying blocked approaches. No automatic track laying, long-distance resource transfer, convoy planner, deadlock solver or new Depot delivery geometry was added.

The next requested usability work is all-side harvesting and delivery using reachable perimeter approach cells. The current center/radius and limited approach-direction behavior is deliberately unchanged here. Save/load, per-vehicle route templates and new transport types remain outside this milestone. Depot Trucks remain expansion vehicles without a transferable cargo route.
