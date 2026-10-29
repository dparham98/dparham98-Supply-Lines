# Crate containers

These replace the crate reservation described in `CRATE_SHIPMENTS.md`. The user asked for crates as clearly independent containers on the map. Work is on branch `feature/crate-containers`, cut from `fix/playtest-feedback` (PR #14). The numbers are editable prototypes.

## Rules

- **A crate is a map object** (`scenes/gameplay/supply_crate.tscn`, `scripts/economy/supply_crate.gd`):
  - It holds up to 25 units of one resource, or nothing (an empty crate).
  - It sits on one open land tile, at most one crate per tile, and doesn't block movement.
  - Its resource shows as a coloured band on the model, and as a fill bar on the map overlay.
- **Crates aren't Depot storage.** A Depot's storage, legend and bar count loose stock only.
  - Production, construction, repair, generators and refuelling never use crates.
  - The old in-storage reservation (`pack`, `crated`, `take_crate` and the lighter bar shades) is gone from `ResourceStockpile`.
- **Packing** happens in the Depot panel, or a deployed Cargo vehicle's panel ("Crates beside"). Pick a resource, then:
  - **+1** takes 25 loose units and sets one crate down on a free tile beside it. For a Depot that's 6 tiles from its centre, camera-facing side first.
  - **Truck** (Truckload) packs until 4 crates of that resource are beside it, and **Train** (Trainload) until 12. Either packs what loose stock and free tiles allow, and says so when it falls short.
  - **Shift-click a crate pip** to unpack that crate back into storage, as far as space allows. A plain click only explains.
  - **+ Empty** sets down an empty crate for workers to fill.
  - "Beside" means within 10 units of a Depot, or 4 units of a deployed Cargo vehicle.
- **Refill on pickup** (replaces Keep stocked): when on, records the crates beside the stockpile, and packing or unpacking updates the counts. It repacks up to those counts as vehicles collect crates. Off leaves the gap empty.
- **Workers:**
  - **Delivering:** right-click a crate while carrying cargo it accepts (empty, or the same resource) to deliver into it. When it fills, the worker moves on to the next crate within 4 units that fits. If none fits, it waits with "Crate full".
  - **Gathering:** right-click a filled crate while carrying nothing to gather from it, like a dropped pile. An emptied crate stays as an empty container.
  - **Gather loop:** after delivering into a crate, a worker goes back to its gather source.
- **Load (L)** on a Cargo truck:
  - **Crate:** click one to drive to it and take it (even when empty), plus any filled crates within 4 units of it, until the 4 slots are full.
  - **Depot or deployed Cargo vehicle:** clicking one takes the filled crates beside it.
- **Unload (U):**
  - **Depot or deployed Cargo vehicle:** unpacks into its storage. A crate that doesn't fit stays aboard, partly emptied.
  - **Open ground:** sets the crates down on free tiles around the point. The point must have open land within 2 tiles.
- **Cargo space:** each crate fills one 25-unit slot of the vehicle's cargo space (4 on a truck, 12 on a Train), so loose cargo can't use the same space.
- **Trips (C):** they work as before. The pickup is remembered as a point (or a Depot), so "all available" checks for crates still near it, and "repeat" waits there for new ones.
- **Trains** load and unload only at friendly Depots, taking the crates beside the Depot. They can't load a crate directly or drop onto the ground.
- **Right-click** with a truck: on a crate it loads; on a Depot or deployed vehicle it unloads when carrying crates, and loads otherwise.

## HUD and map

- **Crate pips** (`scenes/ui/crate_pips.tscn`, 12 authored squares that are shown or hidden):
  - each square is one crate, filled from the bottom by how full it is, in its resource colour;
  - an empty crate is a dim brown square, and a free slot is an outline;
  - tooltips give the contents, and "+n" shows past 12.
- **Depot panel ("Crates beside"):**
  - the total and the number of empty crates;
  - pips for the crates beside it, grouped by resource, with at least a truckload's 4 squares;
  - the resource picker with +1, Truck and Train;
  - Refill on pickup, and + Empty.
- **Depot storage** is titled "Loose storage".
- **Cargo vehicles:**
  - **Storage title:** "Cargo · 3/4 crates".
  - **Storage bar:** a brown Crates segment for the slots in use.
  - **Pips:** one per slot (4 on a truck, 12 on a Train), in place of the loose-cargo legend unless loose cargo is aboard too. This keeps the HUD at its fixed height.
  - **Trip line:** reads, for example, "Crate pickup → Ground drop".
- **Map overlay:**
  - Every crate shows a short fill bar in its resource colour, with a crate-brown cap.
  - A selected or loaded vehicle shows one pip per crate slot.
  - Hovering a crate reads, for example, "Iron crate · 25 / 25 · not Depot storage".
  - A hit on a crate wins over the larger Depot box behind it.
  - A Depot's hover line counts the crates beside it. The hover card shows pips for the crates beside a Depot, or aboard a vehicle.
- **Distant-stop list** (while Load or Unload is armed) shows, for example, "Depot · 4 crates beside · 1,000 space".

## Validation

- **`tests/crate_containers_test.gd` (headless)** covers:
  - packing and placement;
  - crates being ignored by generators and refuelling;
  - the panel's pips, +1, Truck (including "already 4"), Train (packing short), the disabled state without 25 loose units, Shift-click unpacking, + Empty, Refill on pickup, and off leaving the gap;
  - worker delivery, overflow, the one-resource rule, and gathering;
  - Load on a crate (4 slots, the empty neighbour left behind);
  - ground drops, one crate per tile;
  - unloading beside a Depot and into an outpost;
  - all-available and repeat trips;
  - partial unloads;
  - right-click shortcuts;
  - the HUD and overlay;
  - Trains being limited to Depots.
- **`tests/crate_containers_runtime_check.gd` (rendered, real clicks)** covers:
  - Depot +1 and + Empty;
  - the Context column staying 250 px wide;
  - crate hover, and the Depot hover card's pips;
  - Load on a crate;
  - Shift-Unload on the ground;
  - a worker right-clicking an empty crate.
  - Its screenshots are `depot_crates`, `depot_hover_crates`, `cargo_crates_aboard` and `ground_drop`.
- **Updated for map crates:** `rail_runtime_check`, `remote_routes_gui_test`, `storage_runtime_check` and `selection_panels_test` (which now expects "Cargo · 0/4 crates" and "Loose storage"). The storage check's partial unload now keeps 20 units in the crate rather than a whole crate.

## Notes

- **Shorter pack labels:** the buttons read **Truck** and **Train** instead of "Truckload" and "Trainload", which didn't fit the fixed 250 px column. Their tooltips use the full names.
- **No crate stacks on the Depot model:** that proposal is dropped, because crates now sit beside the Depot on the map.
