> Current usability update: routes can now be assigned before rail connectivity exists. An initially unconnected assignment waits and starts when connected; a connection lost after execution still requires explicit Resume. See REMOTE_DEPOT_ROUTES.md. The historical assignment prerequisite below is superseded.

# Rails and trains

Depots can now build rails and produce trains. Trains transport independent energy/iron/wood inventories only through explicitly assigned routes on connected friendly rails. Ordinary Cargo Vehicles retain their existing ground routes.

## Approved prototype settings

The user approved these editable initial values and rules for this batch:

| Setting | Initial value |
| --- | --- |
| Rail cost per tile | 0 energy / 2 iron |
| Train cost | 150 energy / 30 iron |
| Combined train cargo capacity | 300 energy + iron + wood units total |
| Train speed | 8 map units / second |
| Loading and unloading | 2 seconds each |
| Rail terrain | Empty open land inside paying Depot territory |
| Rail connections | Four cardinal neighbors; no diagonal connections |

Edit assets/economy/rail_rules.tres in Godot and restart. Train health provisionally reuses the existing Cargo Vehicle's 80 HP, and paid printing uses the Depot's existing 3-second queue and capacity of 3. These are inherited prototype policies, not recovered original train balance. New trains start with zero cargo. Native saved rail and train scenes use replaceable minimal placeholder visuals.

## Construction, ownership and loading areas

- Select a friendly Depot, open Build structures / rail, then Rail tile. Infantry's shared Build menu also supports rails using its explicitly chosen local payer and existing builder-validity rules. Click individual empty land cells; rail mode remains active for repeated placement. Esc finishes. No drag-line or automatic paid extension is performed.
- All four tile corners must lie inside the selected payer's construction radius. Overlapping territories never pool funds or silently switch payer. Each successful tile pays immediately; invalid/duplicate/unaffordable tiles cost nothing. Disconnected segments may be built, but trains cannot cross gaps.
- Rails stay bound to their paying Depot. Its capture changes the usable team of its rails; its destruction makes those rails unusable. There is no rail reassignment or free salvage. Rails allow ground units to cross but prevent buildings from overlapping them. Forest must first be cleared by a Tank; no rail bridges, tunnels or mountain crossings.
- A Depot's existing dropoff radius (currently 7) is its rail loading/launch area. Put at least one friendly rail tile outside its footprint and within this radius. The same connected network must reach a tile within the destination Depot's loading area. No separate station building or rail through the Depot footprint is needed.
- Depot train production prepays local stock. Missing/occupied friendly rail exits hold the paid job until an exit becomes available, without a second charge. Capture cancels its queue without refund, matching the existing Depot policy. Paid trains do not count as printed infantry for the skirmish objective.

## Train operation

Select a Train to open TRAIN / RAIL DELIVERY ROUTE. Choose the explicit source and destination, per-trip maxima for E/I/W, and optional Repeat; click Assign delivery route. The combined maxima must not exceed 300 and both loading areas must be reachable on friendly rails from the train's current cell.

Loading deducts only available stock from the source after the timer. Partial loads are allowed; empty sources wait. Unloading credits only the selected destination after its timer. Returning to reload occurs only for explicitly repeating routes. Assigning a new route with retained cargo delivers that cargo to the new explicit destination first. No inventory moves automatically between Depots.

Tracks define movement; trains cannot drive off rails or travel diagonally. Ground units and trains share the existing current/next-cell occupancy, so traffic can wait or block an exit. Topology checks ignore temporary traffic; navigation respects it and retries. Captured endpoints, lost friendly track connectivity or destroyed endpoints pause the route and retain cargo. Restoring ownership/rebuilding a connection does not auto-resume: use Pause / Resume explicitly. Cancel or a manual right-click move cancels the route but retains cargo. Manual movement still requires connected friendly tracks. Destruction loses the train's cargo without refund.

## Editor testing

1. Open scenes/maps/rail_exercise.tscn and press F6. It has two Depots, a connected track and an empty Train; the inherited hostile is disabled for this exercise. The source has 100 wood for testing. Both Depots retain the requested 500-iron grant, so compare inventory changes rather than expecting an empty destination.
2. Select Train. Set source Depot, destination EastDepot, E60 / I40 / W20, leave Repeat unchecked, and Assign. Watch cargo load, movement along rails, and arrival. Destination stock should increase by exactly 60 energy / 40 iron / 20 wood.
3. Try Pause / Resume in transit, then Repeat for ongoing explicitly assigned supply. Cancel retains carried resources. An unassigned Train never moves resources.
4. Select Depot, then Train to pay for another. If no empty nearby rail tile exists, the paid job waits. Use Build / Rail tile to add adjacent tiles within the blue territory; Esc finishes placement.
5. In the main scene, place tracks outside Depot footprints and within each endpoint's 7-unit loading area, then connect them cardinally through friendly territories. Switch paying Depot explicitly when extending through another territory. Select the relevant Depot to print a Train.

## Deliberate first-batch limits

No automatic track laying, line-drag placement, demolition/salvage button, track damage/repair, signal system, priority dispatch, coupled carriages, switches, derailment or anti-drone jamming. Rails are not combat targets in this batch. Head-on trains can wait indefinitely on a single line; construct passing space or manually reposition a train on rails. The placeholder train is a single grid actor, not a physical articulated consist. All built rails and route state are match-local; restarting restores the authored scenario. No new enemy pressure/strategy or resource pooling was introduced.

Exact changed files and test evidence: RAIL_BATCH_CHANGED.txt and RAIL_BATCH_VALIDATION.md.
