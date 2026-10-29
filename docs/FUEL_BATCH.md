# Vehicle fuel (economy stage 5)

Vehicles now burn coal to move and refuel from friendly stockpiles. This implements the confirmed rules in ECONOMY_PLAN.md: all vehicle types use coal for operation, not construction; ground vehicles burn nothing while idle; tank fuel and transferable cargo are separate. The user approved the recommended defaults (D1–D7) on 2026-10-28. All numbers are editable prototypes, not recovered original balance values.

## Where fuel applies

- `skirmish.gd` exports `vehicle_fuel_required`. It is on in `resource_skirmish.tscn` (the playable scene).
- Exercise scenes from earlier batches (all_sides, engineering, harvesting, rail and its children, terrain_abilities, supply_routes) set it off, so their scenarios and tests behave as before. With fuel off, vehicles move freely and their reserve stays at 0, as it always has.
- Infantry has no fuel. The Drone's `fuel_drone.tres` has `consumes_fuel = false` until landing and emergency rules are approved (D3).

## Rules (`FuelRules`, `assets/economy/fuel_*.tres`)

| Vehicle | Reserve | Coal per movement unit |
| --- | --- | --- |
| Cargo Truck / Depot Truck | 30 | 0.10 |
| Train | 90 | 0.15 |
| Tank | 60 | 0.20 |
| Motorcycle | 20 | 0.05 |
| Übermech | 60 | 0.20 |
| Drone | 30 | not consumed yet |

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
- **New and authored vehicles (D7):** Depot- and production-building spawns set `start_fuelled = false`, so new vehicles start empty and fill up at their Depot when coal is available. Vehicles placed in a fuel-enabled scene start full.
- **Train round-trip check (D6):** when a route is assigned, `estimated_round_trip_fuel()` sums current position → loading Depot → unloading Depot → loading Depot over friendly rails. If the tank can't cover that, the player is warned but the route is still accepted. The estimate ignores refuelling at the endpoints.

## Testing coal grant (D2)

`resource_skirmish.tscn` sets `testing_coal_amount = 200`, which places a shared 200-coal material pile named `TestingCoalPile` next to the starting Depot. It appears at the authored `Entities/Resources/TestingCoalPoint` marker. Infantry gathers it into a Depot like any other pile. It is a stand-in until coal extraction (stage 6) exists, and should be removed or replaced then. Earlier exercise scenes set the amount to 0.

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

- Drone fuel use, landing and emergency rules.
- Coal extraction (stage 6).
- A HUD source picker and a desired-reserve control.
- Round-trip checks for road vehicles.
- Death or salvage of tank fuel (death drops never include fuel, unchanged).
