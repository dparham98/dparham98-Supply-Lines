# Truck worksites, Fetch and Depot crates

A Cargo truck can now set up a building site and supply it in one step, and fetch for any site on its own. Depots make full crates instead of empty ones. Building still works as in `SITE_CONSTRUCTION.md`: materials on the footprint, Infantry to build, a covering stockpile paying energy as they work. The numbers are editable prototypes.

## Worksite (W)

- **Worksite** is a Cargo truck command card tile. Trains don't have it.
- It opens the build page for the selected trucks: Depot (D), Generator (G), Barracks (B), Tank Factory (T) and Iron Mine (I). Rail and Pin are not on this page.
- Placing a building lays its plan and gives every selected truck a Fetch order for it.
- **Shift** keeps placing and queues each truck's fetches in order.
- Esc stops placing. Back returns to the truck's card.
- The global Build button (B) is unchanged and still lays plans with no truck attached.

## Fetch

A truck on Fetch brings a site exactly what it still lacks.

- Right-clicking a build site with a truck gives Fetch, whether or not the truck carries anything. Unload onto a site still delivers whatever is aboard.
- Materials already aboard go first, straight to the site.
- The rest is loaded at the nearest Depot or deployed vehicle that holds it, preferring one that holds all of it. It is loaded as exact amounts: 45 iron is a full crate and a 20-unit crate.
- Crates set down beside that stop are used first when they fit inside the amount.
- After unloading, the truck checks the site again and makes another trip if it still needs more.
- Trucks fetching for the same site split it. Each counts what the others are bringing, so the site gets no more than it needs.
- If nothing holds the material, the truck waits where it is and checks again every second.
- Any other order ends the fetch.
- Infantry still have to be ordered to construct.

## Depot crates

- The Depot's **Make crates (K)** tile replaces Empty crate.
- It opens a page with Iron (I), Energy (N), Wood (W) and Coal (C) tiles. Each sets down one full 25-unit crate beside the Depot. **Shift** makes five.
- A tile is dark when the Depot holds less than a crate of that resource.
- Esc or Cancel closes the page.
- Empty crates still appear when vehicles empty them, and workers can still fill them.

## Code

- `scripts/economy/cargo_vehicle.gd`: `command_fetch()`, `site_need()`, `fetch_source()`, `_load_exact()`, `fetch_load`, `fetch_claim`, and the right-click on a site.
- `scripts/gameplay/skirmish.gd`: `place_global_plan()` lays plans from both pages and gives the Worksite fetches.
- `scripts/gameplay/skirmish_hud.gd`: `open_worksite()`, `worksite_trucks()`, `open_crate_page()`, `make_crates()`.
- `scenes/ui/skirmish_hud.tscn`: the Worksite and Make crates tiles.

## Validation

`tests/truck_worksites_test.gd` covers exact loads, a two-trip site, two trucks splitting a site, materials aboard going first, waiting for stock, another order ending a fetch, the Worksite page with Shift, the global page keeping Rail and Pin, and the Make crates page. Nobody has judged these in play.
