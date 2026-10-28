# Resource economy plan and proposed starting balance

Status: discussion plan, not implemented balance. Depot production correction, storage foundation, shared mine/universal forestry, mobile supply/pile and wood/coal generator stages are now implemented; see STORAGE_BATCH.md for the exact implemented values and limits. Remaining stages and balance below remain proposals. Existing economy behavior remains until its implementation stages are authorized. All proposed values below should become editable resources; supplied existing unit health/cost/movement/attacks remain unchanged.

## Confirmed user decisions (supersede older prototype assumptions)

- Signals, rail demolition, research and upkeep are wanted, deferred until later. Map tiling is a separate future discussion.
- Depot grants one Infantry on establishment, with no repeatable Infantry production. Barracks produces additional Infantry; Infantry requires no fuel.
- Infantry and Depots construct iron mines only on iron deposits. Infantry extracts iron only from deposits with a mine. Built mines are usable by any player, destructible, and repairable by either side using resources.
- Every forest tile supports wood harvesting; depletion clears it. Wood can be stored in Depots, cargo trucks and trains, and burned for energy. Broader forest/material coverage and forest-obstructed coal should influence access and positioning.
- All vehicle types use coal for operation, not construction. Ground vehicles consume no fuel while idle; flying units consume fuel while airborne. Transferable cargo and onboard fuel are separate.
- Infantry can deliver harvested material into trucks/trains. Mobile supply resources are available for construction and repair. All storage containers have a combined total capacity.
- Generators burn wood/coal, with coal much more energy-efficient and valuable for vehicle use. Water-adjacent generator behavior is wanted; exact operation remains unsettled.

## Proposed implementation sequence

1. Storage foundation implemented; see STORAGE_BATCH.md. Storage API: typed energy/iron/wood/coal, combined capacities, atomic withdrawals/deposits, partial transfers, fixed explicit payer. Retain 500 initial iron within proposed Depot capacity. Add separate onboard fuel state without enabling consumption yet.
2. Implemented; see HARVESTING_BATCH.md. Shared buildable iron mines and per-cell forestry. Remove ownership-restricted mine extraction/capture; preserve Depot capture. Replace direct extraction from bare iron sources. Keep original source-map pixels intact; use validated separate terrain/resource state.
3. Implemented; see MOBILE_SUPPLY.md. Deployed Cargo Trucks/trains use the user-confirmed half-Depot supply/drop-off ranges (17.5/3.5), two-second deployment/packing and automatic packing before movement. Infantry delivery, explicit mobile construction/repair payment, deliberate/death drops and shared collectible physical piles are enabled. Production/generation remains explicitly Depot-bound.
4. Wood/coal generation implemented; see GENERATOR_BATCH.md. Editable 1 wood -> 10 E/2s and 1 coal -> 50 E/5s, explicit modes, pause/resume, atomic cycle completion and full-storage/fuel pauses. Water mode remains pending approval of its exact behavior.
5. Vehicle fuel consumption/refueling, train round-trip fuel checks, stranded-vehicle recovery, Drone landing/emergency rules once approved.
6. Add coal extraction and distribute forests/materials more broadly in separate map-data assets after testing the economy. Do not introduce the later signals/research/upkeep/tiling systems during this pass.

## Proposed balance sheet — approval pending

| Setting | Suggested starting value |
| --- | --- |
| Depot combined storage | 2,000 total resource units |
| Cargo Truck combined storage | 100 (retain current cargo capacity) |
| Train combined storage | 300 (retain approved rail prototype capacity) |
| Depot supply radius | 35 construction radius; retain 7-unit infantry drop-off radius |
| Deployed Cargo Truck supply/drop-off radius | Implemented user revision: half Depot, currently 17.5 / 3.5 |
| Deployed Train supply/drop-off radius | Implemented user revision: half Depot, currently 17.5 / 3.5 |
| Deploy / pack time | Implemented user confirmation: 2 seconds each; movement packs before departing |
| Wood per forest tile | 20; retain Infantry carry 10, harvest 5 every 0.6 seconds initially |
| Iron Mine construction | 75 energy / 25 iron; proposed 2x2 footprint entirely on iron tiles |
| Iron Mine repair | Existing 10 HP per second for 2 energy / 1 iron; either side can repair |
| Generator wood conversion | Implemented editable prototype: 1 wood -> 10 energy over 2 seconds (5 E/s) |
| Generator coal conversion | Implemented editable prototype: 1 coal -> 50 energy over 5 seconds (10 E/s) |
| Water generation | Proposed fuel-free 2 E/s, within 8 units of water; no transported water inventory |
| Cargo/Depot Truck fuel | 30 coal reserve; 0.10 coal per movement unit |
| Train fuel | 90 coal reserve; 0.15 coal per movement unit |
| Tank fuel | 60 coal reserve; 0.20 coal per movement unit |
| Motorcycle fuel | 20 coal reserve; 0.05 coal per movement unit |
| Übermech fuel | 60 coal reserve; 0.20 coal per movement unit |
| Drone fuel | 30 coal reserve; 0.10 coal per airborne second (5-minute full reserve) |
| Refueling rate | 5 coal / second while stopped, from one selected eligible stockpile |
| Low-fuel warning | 25% reserve; train assignment also checks estimated round-trip fuel |
| Initial coal extraction | Proposed direct Infantry harvesting, no new coal-mine building yet; 1,000 per deposit |

Coal is five times as efficient per fuel unit as wood in this proposal, with twice the sustained generator output. Generator fuel preference should be explicit (wood/coal/either); default to wood to protect vehicle reserves. Fuel consumption can accumulate fractionally while cargo remains whole resource units. Nothing in this table is an original recovered balance value.

## Operating rules to settle

- Generator output implemented: require full-cycle free space, keep fuel in the assigned Depot until atomic completion, and pause progress while blocked. Modes/pause/assignment/capture are documented in GENERATOR_BATCH.md. Water mode still needs a decision: generator setting or a separate water-powered variant.
- Mobile supplies (implemented; see MOBILE_SUPPLY.md): deployed trucks/trains are stationary supply sources. Stopped but undeployed vehicles perform assigned transport loading/unloading; refueling remains a later stage; Infantry deliveries and construction/repair spending require deployment. Depot Trucks remain expansion vehicles unless explicitly approved as cargo stockpiles too.
- Refueling: automatic when stopped in eligible friendly supply range, configurable desired reserve and automatic-refuel toggle. Explicit source selection; no pooling. Stockpile coal and fuel reserves are distinct; construction cannot spend fuel-tank contents. New vehicles start empty. Include an explicit way to supply/refuel a stranded vehicle without needing it to move.
- Dropped piles (implemented, user approved): wood/iron/coal only, not loose energy; any player's Infantry may gather them. Piles have no supply radius and cannot be spent directly. No decay initially. Death drops carried physical materials, not vehicle fuel or energy. Vehicle cargo-destruction salvage remains a separate decision.
- Drone recovery: propose automatic landing before reserve reaches zero, parked with no fuel burn. Define valid landing terrain, occupied-cell handling, warning threshold and emergency outcome when no landing cell can be reached. Do not invent instant death or free long-distance flight.
- Coal access: decide whether direct harvesting is acceptable, or coal also requires a mine. Decide any research gates separately from forest obstruction and fuel access. Confirm whether mine foundations use the entire footprint or a center deposit tile before mapping sparse deposits.

## Verification for each stage

Test resource conservation, full/partial inventory transfers, paused work at full storage, selected payer without borrowing, capture/destruction and retained cargo, blocked deployment/refueling, fuel exhaustion/recovery, forest depletion navigation/visual agreement, and existing camera/HUD/pathing/combat/rail regressions. No live-input claims unless physical testing is actually performed.
