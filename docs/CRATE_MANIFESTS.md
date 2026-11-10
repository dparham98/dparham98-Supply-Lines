# Crate manifests and the Generator card

These replace the Depot crate panel and the Generator dropdowns. Crates are still map objects as described in `CRATE_CONTAINERS.md`, but packing, Refill on pickup and Shift-click unpacking are gone. The numbers are editable prototypes.

## Manifests

A Cargo vehicle or Train keeps a **manifest**: how many crates of each resource to carry.

- **Load (L)** turns the command card into the Load page: Iron (I), Energy (N), Wood (W), Coal (C), Clear (X) and Cancel (Esc). E is not used because it turns the camera.
- Each resource tile adds one crate. **Shift** fills every free slot with that resource.
- The Context column shows the manifest as pips, with the count.
- The page is armed the whole time. Clicking a Depot or deployed vehicle, on the map or minimap, gives the Load order.
- Editing applies to every selected vehicle, within each vehicle's capacity.
- The manifest stays on the vehicle. The vehicle panel lists it.

## Loading at a Depot or deployed vehicle

- Stock is taken only at the moment of loading. Crates are made as the vehicle takes them, so a manifest reserves nothing.
- Crates of a listed resource that were set down beside the stop go first, then full 25-unit crates are made from loose stock.
- Crates already aboard count toward the manifest, so a crate left partly full by a small destination is not doubled.
- A shortage leaves that slot empty. It never substitutes another resource.
- With an empty manifest, a Load takes only filled crates set down beside the stop, as before.

## Trips

- **Repeat** uses the manifest on every trip, which replaces Refill on pickup. It waits at the pickup only when it can load nothing at all.
- **All available** stops when the pickup can no longer fill anything on the manifest.

## Crates on the map

- **Make crates (K)** is a Depot command card tile. Its page sets down full crates of any resource; see `TRUCK_WORKSITES.md`. Depots no longer make empty crates.
- Unloading on open ground still sets crates down, and workers can still gather from them.
- Clicking a crate with Load still picks it up, whatever the manifest says.
- Loading crates set down beside a Depot back into storage needs a truck or worker.

## Generators

A Generator burns the fuel in its assigned Depot and adds the energy to that Depot. Fuel reaches the Depot like any other resource.

All control is on the command card:

- **Pause/Resume (P)** and **Focus Depot (F)**.
- **Burn Wood (W), Burn Coal (C), Burn Either (R)**. The current choice is lit and the others are dark.
- **Assign Depot (A)**. Click a friendly Depot that covers the Generator, on the map or minimap.

The panel's Fuel left row gives the fuel in the Depot for the current setting and how long it burns. Barracks and Tank Factories still choose their Depot from a dropdown.

## Validation

`tests/crate_manifests_test.gd` covers manifests, stock taken only on loading, top-ups, shortages, crates beside the stop, a 12-slot mix, repeat and all-available trips, the Load page and the Empty crate tile. `tests/command_cards_test.gd` and `tests/generator_runtime_check.gd` cover the Generator tiles. Nobody has judged these in play.
