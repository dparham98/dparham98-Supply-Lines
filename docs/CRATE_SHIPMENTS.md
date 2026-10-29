# Phase E: crate shipments

This is the logistics redesign approved in `UI_OVERHAUL_PLAN.md`, on branch `feature/crate-shipments` from main `d6553cf`. It replaces the Cargo route panel. The numbers are editable prototypes.

## Rules

- **Crates:** a crate is 25 units of one resource (`ResourceStockpile.CRATE`). A Cargo vehicle (100) carries 4 crates and a Train (300) carries 12. Capacities are unchanged because they're already whole multiples.
- **Preparing shipments:** done at a friendly Depot, or a deployed Cargo vehicle, in the *Prepare shipment* panel (Context column). **+** packs 25 loose units into a crate and **−** unpacks one.
- **Reservation:** crated units still count toward storage, but nothing else can use them.
  - `withdraw`, `spend` and `transfer` only use loose stock, so production, construction, repair, generator fuel and refuelling can't use crates.
  - Depot and deployed-truck `energy`, `iron`, `wood` and `coal` now report spendable (loose) stock, and setting them keeps crates intact.
  - The storage bar shows the crated part of each resource lighter, and the legend counts crates (for example "Iron 500 · 3▢").
- **Keep stocked:** a panel toggle that records the current crate counts. The Depot (or deployed truck) repacks up to those counts as vehicles collect crates and loose stock allows.
- **Load (L):** click a friendly Depot or deployed Cargo vehicle. The vehicle drives there, waits the 2 s transfer, and takes crates oldest first up to its capacity.
- **Unload (U):** unpacks whole crates into loose stock at the stop. Crates that don't fit stay aboard, and the state says so.
- **Trips (C):** applies after each Unload:
  - **Once** stops there.
  - **All available** queues the same Load/Unload pair again while the pickup still has crates.
  - **Repeat** always queues it again, and Load waits at the pickup until crates appear.
- **Queuing:** Shift queues Load and Unload like other orders, with waypoint markers. A dashed trip line joins pickup and delivery while the vehicle is selected.
- **Right-click shortcut:** right-click on a friendly Depot or deployed truck unloads when carrying crates, and loads otherwise.
- **Distant stops:** while Load or Unload is armed, a list of every friendly stop appears above the grid. Choosing one issues the order, and Shift queues it.
- **Trains:** they stop only at Depots, along friendly rails. Their round-trip fuel estimate and warning now cover the current Load/Unload pair as well as legacy routes.

## HUD

- **Cargo grid:** Move, Stop, Deploy/Pack, Auto-refuel / Load, Unload, Trips.
- **Removed:** the route panel (Load at / Unload at menus, per-trip amounts, Repeat, Assign, Pause/Resume, Cancel) and the Orders / Delivery route tabs. Cargo vehicles use the normal two-column layout at the fixed 260 px height.
- **Stop:** clears the queue and ends any trip. Pausing on capture still happens automatically in the legacy route engine.

## Compatibility

- **Route engine:** `CargoVehicle.start_supply_route` and its loose-cargo engine remain as an internal API, used by the existing engine tests. No HUD control uses them now.
- **Rewritten baseline tests** (approved), which drove the removed panel:
  - `bottom_hud_test`, `supply_test` (assignment step only), `hud_click_test`, `remote_routes_gui_test`;
  - `engineering_runtime_check`, `mobile_supply_runtime_check` (button names), `rail_runtime_check`, `storage_runtime_check`.
  - They now use the crate tiles, the distant-stop list and whole crates.
- **My later tests:** tests added during this work were updated to match.

## Bug found while testing

The shipment panel was hidden at the start of each HUD frame and shown again later, which cancels clicks on its buttons. Its visibility is now applied once per frame, like the command tiles. Only the rendered check caught this, because the headless test presses buttons through code.

## Validation

- `tests/crate_shipments_test.gd` (headless) checks:
  - packing and reservation against withdraw, spend and setters;
  - generator and refuel ignoring crates;
  - the panel's +, − and crated storage display;
  - Keep stocked;
  - Load/Unload oldest first and a full unpack;
  - All available emptying the pickup;
  - Repeat waiting for new crates;
  - a partial unload keeping a crate;
  - the right-click shortcut;
  - cargo tiles and their slots, and Trips cycling;
  - ordering from the distant-stop list;
  - the fixed HUD height;
  - Trains rejecting a deployed truck, and the round-trip warning for a crate trip.
- `tests/crate_shipments_runtime_check.gd` (rendered) uses real clicks for Depot +, Load on the Depot, and Shift-Unload on an outpost. Its screenshots are `depot_shipment` and `cargo_trip`.
