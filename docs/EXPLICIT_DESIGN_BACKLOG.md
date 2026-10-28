# Explicit design backlog — priority implementation source

User instruction: remember this list and prioritize implementing it before speculative systems. This record transcribes the three original Samsung Notes screenshots recovered from Camera movement fix (68849e2e-cac8-800d-9998-d0deeced6579). Tentative items retain their question marks. Later user instructions take precedence. The central stated focus is maintaining supply lines and out-positioning opponents.

## Confirmed requirements and outstanding work

| Requirement from original notes | Current status |
| --- | --- |
| Barracks: 100 energy / 45 iron | Implemented; produces Infantry, Scout and Grenadier using unchanged unit stats |
| Tank Factory: 200 energy / 65 iron | Implemented; produces Tank, Motorcycle, Drone and Übermech as movement/production prototypes |
| Depot: 20 energy / 20 iron | Implemented; corrected from earlier provisional 200/40 |
| Depot stores local resources and defines build radius | Implemented with provisional radius |
| Depot spawns one infantry on construction | Implemented exactly once for new constructed/truck Depots; blocked/capture policy documented in PRODUCTION_BATCH.md |
| Depot repeatably produces infantry | Superseded: user now requires one establishment Infantry only; additional Infantry comes from Barracks |
| Depot can spawn trains and rail | Implemented initial rail construction, paid train production and explicit local cargo routes; see RAIL_BATCH.md for approved prototype rules and limits |
| Depot can spawn Depot Truck | Implemented with provisional truck stats/costs |
| Depot has a structure build menu | Implemented in bottom HUD; infantry Build retained with local payer selection |
| Infantry harvests wood | Implemented on every forest tile, with depletion clearing; legacy authored wood stands also remain |
| Infantry repairs buildings | Implemented with fixed local payer, range/ownership checks and provisional editable repair rates/costs |
| Infantry captures enemy Depots and mines | Depot capture remains implemented; mine capture superseded by shared buildable deposit-only mines, usable/repairable by either side |
| Scout traverses forest and fires while moving | Forest traversal and moving fire implemented |
| Grenadier splash; 40/3 against structures and tanks | Implemented; provisional editable splash radius 3 |
| Tank moving fire; 50/3 splash against tanks/buildings; destroys forest tiles while crossing | Combat and runtime forest clearing implemented |
| Motorcycle moving fire | Implemented |
| Drone flying | Implemented with separate air occupancy and provisional fixed visual elevation |
| Scout/Grenadier/Tank/Motorcycle/Drone/Übermech playable and producible | Production, selection and movement scenes implemented with placeholders; specified attacks and terrain mobility implemented; tentative abilities remain |
| Supplied combat values used in gameplay | Confirmed damage/seconds interpretation now applied; explicit fallback retained for unresolved prototypes |

The seven existing UnitStats resources preserve supplied cost, HP, movement speed, vision, known range and attack notation. Do not silently replace these with prototype values. User confirmed notation means damage / seconds between attacks (8/1 = 8 damage every second). Drone attack/range are unspecified. The screenshots group Infantry, Scout and Grenadier below the Barracks heading, and Tank, Motorcycle, Drone and Übermech below Tank Factory through the following screenshot. Treat these section groupings as the recovered production mapping, rather than asking the user to repeat the design. This mapping is read from document organization, not a separately recovered sentence saying each unit is produced there. Prerequisites and print durations remain unspecified.

## Production sources retained for implementation

- Depot: one establishment Infantry only (latest instruction supersedes repeatable production), Depot Truck, trains and rail. One free infantry upon construction remains a separate requirement.
- Barracks: Infantry, Scout, Grenadier (recovered notes section grouping).
- Tank Factory: Tank, Motorcycle, Drone, Übermech (recovered notes section grouping).
- Cargo Vehicle: keep its existing Depot production as an implemented prototype addition; original screenshots do not mention cargo vehicles.

## Tentative requirements — not settled

- Motorcycle derails trains (?)
- Motorcycle signal-jams drones (?)
- Übermech spawns something on death (?)

Do not invent the payload, targeting, durations, ranges, counters or costs for tentative abilities. Preserve them as unresolved until specified.

## Constraints retained from current user requests

- Independent Depot energy/iron inventories; no automatic resource transfers or pooled payment.
- Construction uses an explicitly chosen local Depot; preserve capture and truck deployment.
- Infantry must keep a Build menu showing its local available construction resources.
- Keep contextual bottom HUD, minimap, clickable command card and edge-pan passthrough.
- Keep the enabled 500-iron testing grant, camera, terrain/pathing and existing skirmish functional.
- User is not ready to prioritize new enemy behavior. Defer enemy AI/pressure while implementing the confirmed mechanics.
- Return to additional transport controls later.
- Construction timers, cover and salvage are not confirmed historical requirements. Signals, rail demolition, research and upkeep are now explicitly requested for later implementation.

## Implementation order and progress

1. First batch implemented; see PRODUCTION_BATCH.md for exact coverage and provisional settings. Production/construction foundation: original Depot cost, free construction infantry, restored Depot build card, Barracks and Tank Factory with stated costs. Retain infantry Build. Handle free infantry through terrain-safe spawn retries and grant exactly once; keep paid/free production accounting distinct. Establish explicit local payer binding for production buildings. Production assignments and timings must be labelled provisional or clarified.
2. Engineering batch implemented; see ENGINEERING_BATCH.md for exact coverage and provisional decisions. Wood, mines and repair: separate resource types/inventories, forestry interaction, mine ownership/capture, friendly repair and local spending. Clarify wood purpose, mine extraction and repair rules before implementing balance assumptions.
3. Combat batch implemented; see COMBAT_BATCH.md. Playable roster and resolved combat: production entries for remaining units using existing stats; confirmed attack notation, moving fire, splash and target-class bonuses implemented. Drone attack remains unspecified; Übermech uses its supplied 12/5 base attack.
4. Terrain batch implemented; see TERRAIN_ABILITIES.md for rules, provisional choices and visual limits. Unit-specific terrain: Scout forest traversal, Tank forest clearing, Drone flight. Keep ground/air occupancy rules separate and original source map pixels unchanged; runtime forest changes must be reflected consistently in navigation and visuals.
5. Rail batch implemented; see RAIL_BATCH.md. Rails/trains: explicit Depot-bound rail construction, rail connectivity and train cargo delivery respecting local inventories. User approved initial rail placement/costs and train capacity/movement/loading rules; these remain editable prototype balance. This is central design, not optional polish.
6. Tentative abilities only once the user defines them.

This file is the explicit requirement register, not a claim that later assistant proposals or provisional prototype values are original design. Update statuses as requirements are implemented; do not silently mark provisional approximations complete.

## Latest economy revision

See ECONOMY_PLAN.md for the newer confirmed resource, mine, forestry, generator, mobile storage and vehicle fuel requirements. These supersede ownership-restricted mine extraction, marked-stand-only forestry and free generator output; shared buildable mines and universal forestry are now implemented; mobile deployment and shared physical piles are now implemented; wood/coal generator fuel is now implemented; vehicle operation remains pending. Signals, rail demolition, research and upkeep are now explicit wanted features, deferred by the user. Proposed balance values and unresolved water/coal/Drone rules are clearly separated from confirmed decisions there.

Storage foundation implemented: bounded Depot/cargo/train inventories, coal transport and separate inactive fuel reserves. See STORAGE_BATCH.md; mine/forestry replacement is now implemented; mobile supply deployment and material piles are now implemented; wood/coal generator use is now implemented; vehicle fuel use remains pending.

Shared mine/forestry stage completed; see HARVESTING_BATCH.md for costs, per-cell reserves, rebuild conservation, shared repair and visual limits.

Mobile supply stage completed; see MOBILE_SUPPLY.md. Both cargo types use half-Depot ranges, two-second deploy/pack and automatic packing before movement. Infantry delivery, mobile construction/repair, explicit operating Depot selection and shared deliberate/death material piles are implemented.

Wood/coal generation stage completed; see GENERATOR_BATCH.md. Free generator output is superseded by explicit fuel cycles. Water generation, vehicle fuel consumption/refueling and coal extraction remain pending.


## Selection usability milestone — October 16, 2026

Mixed friendly-unit box selection, visible drag feedback, group movement through existing routing, direct switching out of Build/context menus, and visual-mesh selection bounds are implemented and validated. See SELECTION_USABILITY.md for exact changed files, automated/native input evidence, limitations and reproduction steps.

Requested follow-ons remain: global pending construction without spending until local requirements are met; route assignment between any two controlled Depots independent of present vehicle coverage; reachable all-side harvesting and Depot delivery. This milestone changes selection geometry only, not navigation/collision or resource approach cells.


## Global pending construction milestone - October 16, 2026

Global header Build, unpaid selectable/cancellable cell-grid plans, automatic single-Depot payment after full coverage/funds, optional pinned payer, and delayed completion are implemented for Depot, Generator, Barracks, Tank Factory, Iron Mine and Rail. Existing immediate Infantry/Depot construction remains. See PENDING_CONSTRUCTION.md for exact changes, headless/rendered/native input validation and limits.

The prior global pending construction follow-on is now complete for Depot-funded plans. Remaining usability work: friendly-Depot route assignment independent of current vehicle coverage, and all-side harvesting/delivery through reachable perimeter cells. Mobile-supply automatic planning, plan editing/priority and save/load remain deferred.


## Remote friendly-Depot routes milestone - October 16, 2026

Trucks and trains accept valid routes between any two controlled living Depots independently of vehicle coverage. Initial disconnected train routes wait and start when connected; interrupted active routes still require explicit Resume. Endpoint/capacity validation, HUD feedback and a saved exercise are covered in REMOTE_DEPOT_ROUTES.md. Remote truck delivery, cargo conservation, train waiting/connectivity, headless/rendered mouse events and native input were validated.

Next requested usability milestone: all-side harvesting and Depot delivery through reachable perimeter cells, preserving grid occupancy, reservation, ownership, local inventories and previous usability work.


## All-side harvesting and delivery milestone - October 19, 2026

All traversable cells inside the existing interaction radius are now considered for harvesting and ground delivery, ordered nearest-first and checked by existing terrain pathfinding. Trains retain their rail loading-area search. Eight-sided resource/Depot/truck transfers, off-axis and blocked entrances, concurrency/reservations, fractional arrival timing, headless/rendered GUI input and a successful native 40-wood harvest/delivery loop are validated. See ALL_SIDE_INTERACTIONS.md for exact files, tests and limits.

The three requested usability follow-ons are complete: global pending construction, remote friendly-Depot route assignment, and all-side harvesting/delivery. Suggested future work remains additive selection/control groups, better mixed-group ability controls, transport traffic/passing, and pending-plan editing/persistence; none is silently enabled by this milestone.
