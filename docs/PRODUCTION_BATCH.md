# Original-design implementation: buildings and production

This is the first batch from EXPLICIT_DESIGN_BACKLOG.md. Restart the running scene. Both the original F5 skirmish and F6 supply exercise inherit the new construction/production choices. It preserves the user-enabled one-time 500-iron grant for all newly established Depots, local resource isolation, bottom HUD, GUI-click fix, minimap, edge-pan passthrough and original camera/path methods.

## Implemented from the design

| Source / structure | Construction / production |
| --- | --- |
| Depot | Construction corrected to 20 energy / 20 iron; local inventory/territory; repeatable Infantry, Depot Truck and Cargo Vehicle production retained |
| New Depot | One free construction infantry, including truck-created Depots |
| Depot structure Build menu | Depot, generator, Barracks and Tank Factory; spends the selected Depot only |
| Infantry Build menu | The same structures, retaining the explicit local-payer choice and live resource display |
| Barracks | Construction 100 energy / 45 iron; produces Infantry, Scout and Grenadier |
| Tank Factory | Construction 200 energy / 65 iron; produces Tank, Motorcycle, Drone and Übermech |

The production grouping follows the original note section headings and the latest explicit Depot infantry decision. Cargo/generator systems remain earlier prototype additions. Unit prices, HP, speed, vision, known range and unresolved attack text come from the unchanged seven UnitStats resources. New scenes provide selection, movement, HP, production and distinct simple placeholder silhouettes. Infantry from Barracks retains existing engineering/gathering and fallback combat.

## Local spending and source binding

Every constructed Barracks/Factory is permanently assigned to the chosen paying Depot. Construction and each queued unit spend only that Depot's stock; balances are never pooled, transferred to a building inventory or borrowed from neighbours. Overlap does not change assignment. The building HUD shows its assigned Depot and that inventory. A source that is captured cancels paid jobs without refund, matching the existing Depot queue policy. An absent, destroyed or non-friendly source disables printing and clears pending jobs; a recaptured source permits new jobs, not revival of cancelled jobs. There is no automatic reassignment. Production buildings themselves are not given a new capture mechanic.

Jobs are prepaid, capped and spawned only on empty buildable exit cells using the original cardinal-ring pattern. A blocked exit retains the paid job and waits; it never teleports a unit or charges again. A queue processes one completed job per tick, so large test deltas do not produce multiple jobs at once. Destroying the building discards its queue without refund and releases its footprint on exit. Defeat checks now recognize paid production jobs, affordable production at a friendly assigned building and pending construction infantry, avoiding defeat while a recoverable unit is forthcoming.

## Free construction infantry rule

Only newly constructed/deployed Depots enable the grant automatically. Prebuilt map Depots remain prebuilt and keep their authored starting units; they do not receive extra infantry on every scene load. Scenario authors can explicitly enable Grant Construction Infantry on a prebuilt instance if desired.

The grant is a separate once-per-building pending job, costs no resources, uses no paid queue slot and does not increment the paid-print skirmish objective. It tries a safe exit deferred after establishment, then retries during Depot processing if all exits are blocked. It grants at most one infantry over the Depot lifetime. Capture before it is fulfilled cancels the pending grant; recapture does not regenerate it. Paid repeatable infantry remains available as explicitly requested. Destroying a pending Depot cancels its grant. These blocked/capture/lifetime decisions are documented prototype policy, not additional original notes.

## Editable provisional values and limitations

Only original costs and production mappings are treated as confirmed here. Barracks/Factory default to 1000 HP, queue cap 3 and 3 seconds per unit; footprints are 6 × 6 and 8 × 8 respectively. These dimensions, HP, durations and queue caps are provisional and editable in assets/buildings/barracks.tres and tank_factory.tres, alongside construction costs and allowed PackedScene lists. Their Visuals slots use authored placeholder scenes. Scenario-authored production buildings must occupy exact empty buildable land and set Assigned Depot Path to a friendly Depot; runtime construction assigns it explicitly.

The new six unit scenes deliberately disable unresolved combat fallback, gathering, construction and Depot capture. They move on the current ground navigation as production prototypes. Drone flight, Scout forest traversal, Tank forest destruction, moving fire, splash/target-class bonuses and Übermech special behavior are still pending their planned batches. Drone range/attack remain unspecified. The original infantry fallback remains enabled. New-unit combat is unavailable rather than silently treating all six as infantry. Unit resources are unchanged and no Blender assets are imported.

No new enemies, strategy AI, forest edits, mines, wood, repair, trains/rails, construction duration, save/load or research were introduced. Trains/rails remain part of the explicit backlog. Current generator income can replenish energy for testing; the 500-iron grant is not an energy grant. Production buildings have no independent resource wallet or HUD reassignment control. This first batch does not mark the units' special mechanics complete.

## How to test in the editor

1. F5 or open scenes/maps/supply_routes.tscn and F6. Click a friendly Depot → Build structures. Verify local payer/stock and four structure choices. The Depot button reads 20 E / 20 I. Build a generator first if you want continuing energy.
2. Place a Barracks on green land inside the Depot ring. Construction deducts 100 E / 45 I. Click the Barracks; inspect its source and queue, then print Infantry, Scout and Grenadier. Verify each uses the existing resource cost from that source. Printed units should appear on free terrain and be selectable/movable.
3. Build a Tank Factory for 200 E / 65 I. Click it to print Tank, Motorcycle, Drone and Übermech. Use the generator to replenish energy between prints. These new units are clearly placeholder production/movement prototypes; do not expect their later combat/terrain abilities yet.
4. Select infantry → Build; verify its chosen local payer and the same four construction choices. Try poor payer, outside-territory and occupied footprints. Failed actions charge nothing. In overlap, a rich neighbour must not fund a building bound to a poor Depot.
5. Construct a Depot or deploy a Depot Truck on enough empty land. Confirm exactly one free Infantry appears. Confirm resources are not charged for that infantry, and repeatable paid Infantry production still works. Move units away from exits if the grant or a paid queue is waiting.
6. Test capture of the paying Depot while a Barracks/Factory queue is paid. Verify cancellation without refund, unavailable source feedback and no neighbour fallback. Recapture permits newly paid jobs. Existing unit selection, right-click movement/gather/attack, cargo routes, minimap, wheel zoom, Q/E and edge scrolling should continue to work.

Tests and results are in PRODUCTION_BATCH_VALIDATION.md. Exact changed files are in PRODUCTION_BATCH_CHANGED.txt; new script/test UID metadata is included, ignored .godot cache excluded. Before-change copies of existing edited files are in the chat workspace production_batch_before folder. Earlier milestone guides are historical snapshots where their costs or UI differ from this batch.
