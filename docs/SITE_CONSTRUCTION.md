# Construction from site materials

Buildings are no longer bought out of a Depot's stock. A queued plan needs its materials physically on its footprint, and Infantry build them in over time while a covering stockpile pays the energy. This replaces the instant, fully Depot-paid completion described in [PENDING_CONSTRUCTION.md](PENDING_CONSTRUCTION.md); rails keep that older rule.

## Rules

- **Starting force.** The skirmish starts with an Infantry and a Cargo truck beside the Depot. The truck has a full tank and carries nothing; the Depot's 500 iron is the first source of materials, packed into crates and driven out.
- **Energy keeps the Depot range.** A plan's energy comes from one covering Depot or deployed Cargo vehicle, charged in step with the materials as Infantry build (the share of the energy cost that matches the share of materials added, so the last tick settles the whole cost). Auto plans latch the first covering stockpile that can pay the remaining energy and keep it; pinned plans use only their pin. A payer that is lost or short pauses the build without borrowing elsewhere.
- **Materials must be on the site.** A plan counts the piles and crates whose tile lies inside its footprint. Iron (the only material cost today; the code also understands wood) gets there by:
  - a Cargo truck fetching for the plan (right-click it, or place it from the truck's Worksite page), which loads exactly what is missing; see `TRUCK_WORKSITES.md`;
  - a Cargo truck unloading at the plan (Unload then click the plan on the map): loose cargo first, then crates, taking only what the build still lacks and forming or topping up a pile inside the footprint; surplus and other resources stay aboard;
  - a worker ordered to construct while carrying iron, which drops its load onto the pile first;
  - piles or crates already lying there when the plan is placed. A plan can be placed over piles, and the placement preview says how much of the build they cover.
- **Infantry build.** Right-click a plan with Infantry to construct. The worker walks to the site and, every work cycle (1.2 s, one saw blow), builds in 5 iron from the site and charges that step's energy. Several workers build faster. The worker waits, saying why, when the site lacks materials or the payer lacks energy. Carried cargo the site needs is delivered first.
- **Indicator.** The plan's grid and label are amber while materials are short, green once the site holds everything still needed, and blue while construction ticks. A fenced site model stands round the footprint and its lamps show the same colours, blinking while Infantry build (docs/CONSTRUCTION_SITE_MODEL.md). The label and the plan's HUD panel read, for example, "Iron on site 25/45 · built 10/45". The map outline turns green when covered, and the placement preview turns green over a pile that already covers the build.
- **Finishing.** When all materials are built in and the energy settled, the building appears as before (Depots grant their Infantry, generators and production buildings are assigned to the energy payer when it is a Depot). Leftover piles or crates on the footprint are moved to the nearest free cells beside the building.
- **Cancel** is still free and leaves the site's piles where they are.
- **Rails** are unchanged: a covering Depot pays energy and iron and the tile appears once it is clear.

## Code

- `scripts/economy/construction_plan.gd`: `materials()`, `needed()`, `on_site()`, `shortfall()`, `materials_covered()`, `receive()`, `take()`, `work(unit, amount)`, `energy_due()`, `energy_payer()`, `finish()`. `complete_from_stock()` is the old instant, fully stock-paid completion: rails use it, and tests and the playtest tools use it to stand buildings up quickly. Nothing in play reaches it for buildings.
- `scripts/economy/depot_network.gd`: `stores_inside(rect)`, `materials_inside(rect)`, `source_covers_plan()`, `plan_energy_source_valid()`, `finish_plan()` (instantiates without spending), `clear_site()`, and the preview's site line.
- `scripts/gameplay/unit_agent.gd`: the `construct` order (`command_construct`, `_construct`), delivery of carried cargo to the site, and the work animation while constructing.
- `scripts/economy/cargo_vehicle.gd`: `_site_stop()`, Unload at a plan, right-click delivery, trip stops that are sites.
- `scripts/gameplay/skirmish.gd` and `skirmish_hud.gd`: right-click routing to sites, the Unload pick including plans (they pulse on the minimap), the plan panel and build-page copy.
- `scripts/economy/material_pile.gd`: `add()` so a site tops up one pile instead of scattering several.
- `scenes/maps/resource_skirmish.tscn`: the starting `StarterTruck` (named so exercise scenes that add their own `CargoTruck` keep working).

## Validation

- `tests/site_construction_test.gd` (headless): the starting truck; a funded Depot leaving a plan pending; truck unload forming one pile and keeping surplus; a worker's carried iron topping the pile; crates inside the footprint counting; the green grid; 5-iron ticks with in-step energy and no Depot iron; waiting without energy; completion, operator assignment and clearing the footprint; a plan placed on a pile starting covered; cancel leaving the pile; rails still Depot-paid.
- `tests/site_construction_runtime_check.gd` (rendered): a plan beside the Depot before and after a truck delivery, screenshots `site_waiting` and `site_ready`.
- `pending_construction_gui_test` now finishes its plan through site materials and a worker. Other suites that stood buildings up through plans call `complete_from_stock()`.
- Not playtested by a human: the pace of building, the colours at play zoom and how the loop feels (pack, load, drive, unload, construct) need your eye.
