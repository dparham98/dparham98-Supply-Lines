# Infantry engineering: wood, mines and repair

This implements the next explicit-design batch: infantry harvesting wood, repairing buildings and capturing mines. Restart play to load the new scenes/scripts. The usual F5 skirmish and F6 supply exercise now include a green-ringed Wood Stand at approximately (160,172) and a neutral Iron Mine at (193,172). Open scenes/maps/engineering_exercise.tscn and press F6 for the same map with a damaged friendly generator at (180,158), initially 120 / 300 HP, assigned to the starting Depot. The original enemy remains the same stationary prototype; no new enemy strategy/pressure is added.

## Editor play checks

1. Pan south of the starting Depot to see the wood stand; the mine is southeast. Select infantry → Gather iron / wood → click the green-ringed Wood Stand (or right-click it). The infantry walks to it, harvests a load, returns to its friendly Depot and repeats. Click that Depot to see W separately from E and I. Wood must not increase iron. Return resources sends the held type to the nearest friendly Depot; right-click a friendly Depot with cargo to choose that recipient explicitly.
2. Select infantry → Capture Depot / mine → click the neutral mine, or right-click the mine. The infantry approaches, captures it after 8 uncontested seconds and automatically begins gathering its iron. Move opposing eligible infantry within 12 units to verify contest resets progress. Click the mine to inspect owner, HP, reserves and progress. Mined iron must be carried and delivered; capture itself pays nothing and does not transfer reserves into a Depot.
3. In engineering_exercise.tscn select infantry → Repair building → click DamagedGenerator. It approaches and repairs until full, charging only its assigned Depot. Alternatively, right-click a damaged friendly building; a friendly Depot with carried cargo prioritizes delivery. Select the generator to inspect live HP; the infantry's repair order names its paying Depot. Hover Repair for current tick amount, time and cost.
4. Deplete the payer's energy/iron and verify repairs pause without borrowing from other Depots. Capture the target or payer and verify work stops or pauses. Restoring that same payer's ownership/funds resumes a pending repair; no payer switching occurs. A full-health target charges nothing, a final partial tick caps at Max Health and a destroyed target cannot be resurrected. Stop/move changes the order and retains any carried cargo.
5. Print a cargo vehicle, choose an explicit route and set E/I/W maxima. For a wood-only delivery set E = 0, I = 0, W = 10. Combined requested amounts must fit capacity (currently 100 total); loading removes wood from source and unloading credits only the destination. Pause/cancel retains held wood, and endpoint capture behavior stays as before. No Depot transfer occurs without a worker carrying resources or an assigned cargo route.
6. Check printed Barracks infantry also has engineering commands; Scout, Grenadier, Tank, Motorcycle, Drone, Übermech, Depot Trucks and cargo vehicles do not gain repair/wood-gathering/construction capabilities. Check production menus, construction/free infantry, source capture, existing iron gathering/combat, camera, minimap and edge pan.

## Confirmed behavior and provisional balance

The historical notes explicitly require wood harvesting, building repair and mine capture. They do not specify mine extraction, repair costs/rates, forestry depletion or wood spending. The following are explicit prototype policies, not recovered values:

| Rule | Default / decision |
| --- | --- |
| Wood Stand | 500 finite wood; saved 3 × 3 footprint on open terrain |
| Gathering | Existing infantry capacity 10, amount 5 per 0.6s retained for iron and wood |
| Mine reserves | 1000 finite iron; no automatic/passive output |
| Mine capture | 12-unit radius, 8 uninterrupted seconds, using existing Depot-style contest/reset policy |
| Mine footprint / HP | 4 × 4 cells / 1000 HP |
| Repair | Up to 10 HP every 1 second, 2 energy + 1 iron per successful tick |
| Repair range | 7 world units from target center, accommodating building footprints |
| Wood spending | None yet; stored and transported separately without inventing build/repair conversions |

Edit assets/economy/engineering_rules.tres for repair/mining/capture defaults. Harvest amount/interval/capacity remain editable on the infantry controller scene. Wood site amount/footprint are editable on wood_site.tscn or instances. Building health continues to use each building's existing Max Health fields/resources. The exercise generator's Initial Health is an authoring/testing setting; normal generators start full. The seven UnitStats resources and unresolved combat text are unchanged; these engineering capabilities are scene/controller flags and behavior, not invented ability identifiers.

## Typed inventories and source ownership

Depots now have independent wood alongside energy/iron. Initial Wood defaults zero; the user-enabled 500-iron grant remains iron-only. Infantry carries one resource type at a time. Ordering a different source while carrying another type returns the held load first; it is never reclassified, discarded or credited as iron. Delivery validates a friendly recipient using the previous explicit/nearest-recipient policy. Wood increments wood and wood delivery statistics; only delivered iron increments the original skirmish iron objective. Source switching, empty/full cargo, depletion and lost source are handled without manufacturing resources.

Only the mine's current non-neutral owner can extract. Mine capture preserves remaining reserves and HP. The eligible-team presence rule is the same as current Depot capture: living infantry-capable units inside the radius, uncontested; owner presence or multiple eligible teams resets progress. Production prototypes and non-combat trucks/cargo do not capture. A Capture order approaches the target through existing ground paths; already-in-range eligible units also contribute by proximity regardless of their other order. After mine ownership changes away, gathering is halted before continued travel/extraction. Already extracted cargo remains carried and can still be delivered. Re-capture does not refill reserves. An exhausted mine remains a selectable/capturable building with a reserved footprint; destruction releases it.

Wood is gathered from the explicitly authored Wood Stand scenes. The thousands of baked decorative forest trees are not individual harvestable actors in this batch. Depleting a stand hides its saved visuals and releases its footprint, with no changes to the source map pixels or original forest terrain. There is no regrowth or map-wide forest clearing. This provides the wood mechanic without pretending the later forest-navigation/destruction batch is complete.

## Local repair payment

Only friendly living selectable buildings are repairable. Depots pay for their own repairs. Generators and production buildings pay through their fixed assigned Depot. Mines have no assigned production wallet; a repair order latches the nearest friendly Depot whose territory covers the mine, and reports that payer. A lost/depleted payer is not replaced by a richer neighbour. Repair to an enemy/destroyed target is rejected or ended; a captured target ends the order. Payer ownership/fund loss pauses a pending order; restoring that same payer can resume it. Work validates ownership, range and stock immediately before payment and HP gain.

Each successful tick charges its full configured cost, including the final partial HP tick. Full health, out-of-range work, unavailable payer, invalid target and insufficient funds charge nothing. Range is reached before work starts; infantry stops unnecessary approach waypoints once in repair range. Repair preserves any carried resources. Existing building damage/removal methods provide HP to repair, but this batch adds no enemy building targeting, salvage or resurrection.

## Cargo and HUD

Cargo routes now optionally include wood using the same combined capacity, partial-stock loading, pre-load deduction and post-travel unload credit rules. Wood remains on the vehicle during pause/cancellation/manual move and is lost on destruction as with its other cargo. No new manual load/unload controls were added, per the user's request to revisit controls later. Existing start_supply_route callers retain their old arguments; optional wood is appended as the final argument.

The HUD shows typed infantry cargo, Depot wood, local construction wood and an additional W field on cargo routes. The Repair and Capture buttons retain the stable GUI visibility/click handling. Mines have ownership/reserve/capture information and minimap ownership markers. Wood stands retain gold resource markers. Existing original iron deposits remain unowned gatherable iron and are not converted to mines.

The mine and wood visuals are saved reusable scenes with Visuals model slots; no terrain/lighting/UI meshes are generated by gameplay scripts. Mine ownership does not connect an inventory network. Mines are authored map sites in this batch, not player-built extractors: no mine construction cost was supplied. No new buildings consume wood until that design is specified.

Executed validation and limitations: ENGINEERING_BATCH_VALIDATION.md. Exact file changes: ENGINEERING_BATCH_CHANGED.txt. Before-change copies are in the chat workspace engineering_batch_before folder, outside Godot's resource scan. Earlier milestone guides describe historical snapshots; this guide supersedes their no-wood/no-mines/no-repair limitations.
