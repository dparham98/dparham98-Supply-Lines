# Vehicle fuel (economy stage 5)

Vehicles now burn coal to move and refuel from friendly stockpiles. This implements the confirmed rules in ECONOMY_PLAN.md: all vehicle types use coal for operation, not construction; ground vehicles burn nothing while idle; tank fuel and transferable cargo are separate. The user approved the recommended defaults (D1–D7) on 2026-10-28. All numbers are editable prototypes, not recovered original balance values.

## Where fuel applies

- `skirmish.gd` exports `vehicle_fuel_required`. It is on in `resource_skirmish.tscn` (the playable scene).
- Exercise scenes from earlier batches (all_sides, engineering, harvesting, rail and its children, terrain_abilities, supply_routes) set it off, so their scenarios and tests behave as before. With fuel off, vehicles move freely and their reserve stays at 0, as it always has.
- Infantry has no fuel.
- **The Drone burns coal by the second** (item 10 of the balance handoff, 2026-11-25):
  - 0.1 coal a second while in the air, moving or hovering. That is about five minutes on its 30 tank (`coal_per_second_airborne` in `fuel_drone.tres`). It takes no Depot power.
  - Out of coal, it lands where it is, says "Out of fuel · landed", and takes no moves.
  - Refuelled as any vehicle is (a covering Depot, a deployed Cargo truck, or a coal crate beside it), it takes off again.
  - The Cyborg AI sends a Drone low on coal back to its rally point to refuel.
  - Checked by `tests/drone_fuel_test.gd`.
  - **Under review:** the owner wants Drones and Derailers clearly more fuel-efficient than Tanks and trucks, so expect the rate to change.

## Rules (`FuelRules`, `assets/economy/fuel_*.tres`)

| Vehicle | Reserve | Coal per movement unit |
| --- | --- | --- |
| Cargo Truck / Depot Truck | 30 | 0.05 (was 0.10). Both share `fuel_truck.tres`, so the Depot truck's 30-coal tank now lasts 600 m. |
| Train | 90 | 0.15 |
| Tank | 60 | 0.15 (was 0.20) |
| Motorcycle | 20 | 0.05 |
| Übermech | 60 | 0.15 (was 0.20) |
| Drone | 30 | none; 0.1 a second in the air instead |

All types also share `refuel_coal_per_second = 5` and `low_fuel_fraction = 0.25`.

## Behaviour

- **Consumption:** fuel drains by distance actually moved, fractionally. A step is shortened so a vehicle never moves further than its remaining fuel allows.
- **Out of fuel (D5):** the vehicle stops in place with state "Out of fuel · order paused". Its order and route are kept. Once it has refuelled to its desired level, or no source can add more, it resumes.
- **Refuelling:** a vehicle refuels automatically when it is stopped (or out of fuel) inside the supply radius of an eligible friendly source with coal:
  - an eligible source is a Depot, or a deployed Cargo Truck or Train (`SupplySource`);
  - refuelling moves whole coal units at 5 per second, with fractional time banked;
  - a vehicle never refuels from itself.
- **Fuel level:** it fills up to `desired_fuel_fraction` of the reserve (default full). With fractional burn, a tank stops within one coal of that target, because only whole stockpile units are drawn.
- **Source selection (D4):** a source pinned with `set_fuel_source()` is used exclusively, with no fallback. Otherwise the nearest covering source with coal is used. Each unit of coal comes from exactly one source, so there is no pooling.
- **Stranded recovery:** deploy a Cargo Truck or Train within 17.5 units of a stranded vehicle. The vehicle refuels without moving.
- **Separation:** construction and repair spend stockpile resources only, so tank fuel can never be spent. Captured or enemy sources are ineligible.
- **New and authored vehicles (D7):** Depot- and production-building spawns set `start_fuelled = false`, so new vehicles start empty and fill up at their Depot when coal is available. Vehicles placed in a fuel-enabled scene start full. While testing, new vehicles start full instead. Each map decides with the skirmish's `testing_full_tanks` (on by default); the balanced map turns it off (2026-11-14, economy report step 5, PR #66). `FuelRules.full_tanks_for(game)` reads it, and falls back to `FuelRules.testing_full_tanks` only for a vehicle made with no skirmish root. Playtest-panel spawns follow the same setting.
- **Train round-trip check (D6):** when a route is assigned, `estimated_round_trip_fuel()` sums current position → loading Depot → unloading Depot → loading Depot over friendly rails. If the tank can't cover that, the player is warned but the route is still accepted. The estimate ignores refuelling at the endpoints.

## Testing coal grant (D2)

`resource_skirmish.tscn` sets `testing_coal_amount = 200`, which places a shared 200-coal material pile named `TestingCoalPile` next to the starting Depot. It appears at the authored `Entities/Resources/TestingCoalPoint` marker. Infantry gathers it into a Depot like any other pile. It is a stand-in until coal extraction (stage 6) exists, and should be removed or replaced then. Earlier exercise scenes set the amount to 0. The balanced map (BALANCED_MAP.md) has coal in the ground and sets it to 0; this map keeps its pile because it has no Coal cells.

The approved default was a coal grant inside the Depot stockpile. That was changed because `depot_correction_test` fills the starting Depot to exactly its 2,000 capacity with energy and iron, so any starting coal breaks its unchanged assertions. The pile is created from the scene setting, using the same pile scene as dropped materials, rather than authored as a node. This is because exercise scenes inherit `resource_skirmish`, and an authored pile broke `mobile_supply_runtime_check`, which counts material piles.

## HUD

The selected vehicle's details show:

- fuel and reserve, plus LOW FUEL (below 25%) or OUT OF FUEL;
- auto-refuel state and the current or pinned source;
- for Trains, the round-trip warning.

An **Auto-refuel** button toggles refuelling for every selected fuel-using vehicle. Cargo Trucks and Trains open on their Supply route page; their Auto-refuel button is on the Orders page of the command card (HUD_LAYOUT.md). The earlier separate Supply panel copy was removed after review. There is no HUD control for pinning a source yet; pinning exists in the API only.

## Playtest feedback (2026-10-28)

- Auto-refuel couldn't be toggled on Cargo Trucks and Trains, because the button sat only on the hidden command card. Fixed with the Supply panel button above.
- Later fix (`feature/command-queue`): idle Cargo vehicles and Trains ticked fuel twice per frame, so they refuelled at double the rate. They now tick once.
- Loading coal into a Cargo Truck is awkward. Today it means either deploying the truck and having Infantry deposit coal, or assigning a route and then stopping it to keep the cargo. A direct "load from this Depot" action is not designed yet and needs a decision.

## Not included

- Coal extraction (stage 6).
- A HUD source picker and a desired-reserve control.
- Round-trip checks for road vehicles.
- Death or salvage of tank fuel (death drops never include fuel, unchanged).

## Depot power, truck fuel and crates (2026-11-19)

Asked for after the playtest of 2026-11-19. These rules replace the earlier ones where they differ.

- **Depot power.** Inside a friendly Depot's range a vehicle moves on that Depot's energy, `FuelRules.depot_energy_per_metre` (0.2 E a metre), instead of its tank. A truck crossing a whole range spends about 10 E. A Depot with no energy powers nothing, and the vehicle goes back to its tank without stopping. An empty tank still moves on Depot power. The fuel line says "running on <Depot> power". Draining a base this way is intended: energy is rationed between building and moving. Trains keep their own track power.
- **Deployed Cargo vehicles pay energy with coal**, at the Generator's coal rate (`assets/economy/generator_rules.tres`, 30 E a coal): loose energy first, then their loose coal, then coal crates aboard, then their own fuel tank, which they may empty (`CargoVehicle.pay_energy`, `take_coal`). Energy left from a coal is kept for the next payment. Their energy on hand counts that coal.
- **Deployed Cargo vehicles refuel others** from the same coal, in the same order, down to an empty tank.
- **Coal crates on the ground refuel** a stopped friendly vehicle within 4 m (`UnitAgent.CRATE_REFUEL_RANGE`), so a truck can set down its own fuel.
- **Energy cannot be crated** (`ResourceStockpile.CRATED`). The Energy tile is gone from the Load and Make crates pages.
- Check: `tests/truck_fuel_test.gd`.

## Staying in range (2026-11-19)

- A vehicle with an empty tank stops at the edge of Depot power instead of driving out and being stranded. It says "No fuel · can't leave Depot range" and warns once in the feed.
- Its order waits, and goes on once it has fuel. A vehicle with some fuel may still leave and use it up.
- `unit_agent.gd` `_walk`; checked in `tests/hud_polish_test.gd`. See `HUD_POLISH.md`.
