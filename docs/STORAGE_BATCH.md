# Storage foundation

First economy stage implemented. All stockpiles share typed energy/iron/wood/coal accounting and a combined capacity. Default Depot capacity is 2,000 total units, cargo truck 100, Train 300. Cargo truck means the existing Cargo Vehicle; Depot Trucks remain expansion vehicles with separate fuel state but no transferable cargo wallet.

## Behavior

- Depot capacity is editable in assets/economy/depot_rules.tres; optional per-scene storage_capacity_override supports authored scenarios. Vehicle cargo capacities remain in supply_rules.tres and rail_rules.tres. Inventories are per-actor runtime state; shared resources never contain balances.
- Infantry deposits only what fits and keeps the remainder at its chosen Depot, retrying when space opens. Delivery counters increase only by accepted iron/wood. No borrowing or switching stockpiles when full.
- Routes accept coal as a fourth per-trip maximum (C in the HUD). Combined requested amounts must fit cargo capacity. Loading moves available stock from the explicit source; unloading accepts only destination space. Full/partial unloading retains remaining cargo and does not complete or repeat until empty. Capture, cancel, death and rail restrictions keep their prior behavior.
- Partial mixed deliveries use deterministic energy, iron, wood, coal order. This is an initial implementation policy, not resource-priority design. Capacity freed later allows remaining resources to arrive after the ordinary transfer timer.
- Spending is all-or-nothing for requested costs. Invalid/negative costs do not debit stock. Transfers are partial and conservative; capacity cannot be reduced below contents. Administrative direct amount setters clamp within available room, while ordinary gameplay uses deposit/withdraw/spend/transfer methods and retains undelivered stock.
- The 500-iron testing grant remains enabled. At startup iron is admitted first (testing grant when enabled), then authored wood, coal and energy into remaining capacity. Normal settings preserve the full grant; deliberately setting capacity below the grant necessarily limits it. Over-capacity authored stock is clamped in that order. Existing production stress tests explicitly choose 10,000 capacity rather than bypassing limits.
- Existing free generators now pause at full storage, report zero active output there, and do not bank blocked output for later bursts. Generator wood/coal consumption and water behavior are later stages; this batch does not enable fuel burning.

## Fuel state only

Each vehicle has a separate bounded, initially empty fuel reserve. Editable resources: fuel_truck (30), fuel_train (90), fuel_tank (60), fuel_motorcycle (20), fuel_drone (30), fuel_ubermech (60), under assets/economy. Infantry, Scout and Grenadier have no fuel profile. Stored coal is not automatically converted to fuel and fuel is not spendable cargo. Movement still works without fuel; consumption, automatic refueling and Drone landing are deferred to the vehicle-fueling stage. HUD explicitly says fuel is not yet required.

Coal is supported in storage/transport, not yet placed as map deposits or required in production. No shared mine/forestry/deployment/drop-pile replacement is claimed in this stage.

## Editor test

1. Open scenes/maps/storage_exercise.tscn and press F6. It has a connected Train, cargo truck and two Depots. Source starts with 100 coal. EastDepot deliberately has a 600-unit test capacity and 590 initial stock; normal Depots remain 2,000.
2. Select Train, set Depot -> EastDepot, E0/I0/W0/C20, Repeat off, and Assign delivery route.
3. Only 10 coal fits at EastDepot. The other 10 remains aboard and the route waits. Select EastDepot to inspect full storage.
4. Spend stock at EastDepot (for example build five valid rail tiles at 2 iron each). The retained 10 coal can then finish unloading. No resources are lost or automatically diverted.
5. Main scene Depot selection shows all resource amounts and used/maximum storage. The cargo route panel now includes coal. New free Depot Infantry and Barracks-only repeatable Infantry remain intact.

See STORAGE_BATCH_VALIDATION.md and STORAGE_BATCH_CHANGED.txt for checks and exact files. Fuel activation, buildable shared mines, every-tile forestry and mobile supply deployment follow later economy stages.

Later update: wood/coal generator burning is now implemented; see GENERATOR_BATCH.md. Earlier descriptions of free generator output or wood having no energy use are historical and superseded. Water/vehicle operating fuel and coal extraction remain pending.
