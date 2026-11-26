# Round 3: troop cars, Forward Railheads and Food on trains

Part of item 7 of the Round 3 balance handoff (2026-11-25), for both sides. Stacked on item 6 (`docs/ROUND3_HEARTH_WAIN.md`). The rest of item 7 is in `docs/ROUND3_SKY_PAVILION.md`. Its King's Roads are not built.

- **Troop cars:** foot soldiers and workers ride a friendly train, each taking one crate slot.
- **Forward Railhead:** a cheap platform beside the track that works as a train stop out past the Depots and Keeps.
- **Food on trains:** a train's Load page offers Food for either side.

## Troop cars

**Who rides** (`TroopCars.eligible`): a living ground unit of the side that is on foot.
- **Not:** a vehicle (anything that burns fuel), armoured units, giants, rail trains, Cargo vehicles or Depot trucks.
- **So these ride:** the Deforester, Scout, Grenadier, Forester Maiden, Farmer, Warhound, Round Table Marine, Grail Sentinel and Questing Marine.
- **These don't:** a Tank, Drone, Übermech, Azure Dragon, Hearth-Wain or truck. Each is refused with "Only foot soldiers and workers ride a train."

**Boarding.** Select foot units and right-click a friendly train. Units carrying cargo don't take the order.
- **The order:** each unit walks to within `board_reach` (6 m) of the train and gets aboard.
- **Only at a station:** the train must be stopped at a station:
  - in the loading area of a friendly Depot or Keep (`Train.at_depot`);
  - or within 6 m of a friendly Forward Railhead.
- **Refusals:** a moving or derailed train refuses with the reason, and so does a full one ("… is full: each rider takes a crate slot.").
- **A Farmer:** she stays on her Farm while it works. Once it is dormant (`docs/ROUND3_HEARTH_WAIN.md`) she can board.

**Riding.**
- **Off the map:** a rider is out of the scene. It can't be seen, selected, shot or healed.
- **Space:** each rider takes one crate slot, `passenger_space` 25 of the train's 300, shared with its crates. So 6 Food crates and 6 Marines fill a train, and an empty train takes 12 riders.
- **Housing:** riders still count against the Knights' housing (`KnightHousing.used`).
- **Status:** the train's status line adds "· N aboard".

**Getting off.**
- **Disembark (U):** the train's card shows it while it carries riders. At a station every rider gets off onto the nearest free cells round the train, with no orders. Elsewhere the tile is greyed out: "Stop at a friendly Depot, Keep or Railhead first."
- **Derailed** (a Derailer or a mine): the riders are thrown out onto the nearest free cells.
  - **Damage:** each loses `derail_passenger_damage`, a quarter of its full health, never going below 1 HP.
  - **Slow:** each is slowed to `derail_slow_factor` 0.6x speed for `derail_slow_seconds`, 2 s.
- **Destroyed:** a train destroyed with riders aboard throws them out the same way.

## Forward Railhead

**What it is.** A 4 x 4 platform for either side, built from the **Build page's Railhead (L)**.
- **Cost:** `railhead_iron_cost` 30 Iron. It is paid as that side's other plans are, or from Iron delivered to the site.
  - For the Knights, a Keep or pitched Hearth-Wain whose range covers it builds it from stock.
- **Who builds it:** a Deforester or a Forester Maiden.
- **Health:** `railhead_health` 300.

**Placing it.** It must stand beside friendly track: a piece within `railhead_track_reach` (1.5 m) of its footprint (`RailNetwork.track_beside`). Elsewhere the plan is refused with "A Railhead must stand beside your track." The placement preview is red there too.

**What it does.** It has no supply range and stores nothing. It is a train stop.
- **Stop:** a train within `railhead_stop_reach` (6 m) is at it, as at a Depot (`RailNetwork.depot_reach`). A train's Load and Unload pick it on the map or minimap, where it pulses as a stop, and Shift-queued stops make it part of a route. A Cargo truck can't use it.
- **Riders:** board and get off there.
- **Unloading:** a train unloading there sets its crates down round the platform, as supply crates.
- **Loading:** a train loading there picks up the crates standing round the platform (`CrateYard.beside`).
- **Label:** "RAILHEAD · N trains here · HP".

**Art.** A placeholder model: a stone deck, an edge stripe, posts, a team-coloured canopy and a crate (`scenes/models/railhead_model.tscn`). Its icon, portrait and card are rendered from it (`render_hud_images.gd -- railhead`).

## Food on trains

A train's Load page shows the Food tile on either side, as well as Iron, Energy, Wood and Coal. A Cyborg train can now haul the Food a captured Keep holds. Other vehicles offer Food to the Knights only.

## Numbers

All on `assets/economy/rail_rules.tres` (Troop cars and Railhead groups):

| Rule | Value |
| --- | --- |
| `passenger_space` | 25 (one crate slot) |
| `board_reach` | 6 m |
| `derail_passenger_damage` | 0.25 of full health |
| `derail_slow_factor` / `derail_slow_seconds` | 0.6x for 2 s |
| `railhead_iron_cost` | 30 |
| `railhead_footprint` | 4 x 4 |
| `railhead_health` | 300 |
| `railhead_stop_reach` | 6 m |
| `railhead_track_reach` | 1.5 m |

The handoff asked for `assets/buildings/railhead.tres`. The Railhead's numbers sit on the rail rules instead, since it has no production or research to describe.

## Files

- **Troop cars:**
  - `scripts/rails/troop_cars.gd` (`TroopCars`): who may ride, and why not.
  - `scripts/rails/train.gd`: `passengers`, `station()`, `free_slots()`, `board_refusal()`, `take_passenger()`, `disembark()` and `_set_down_riders()`. Riders share the crate slots (`_sync_reserved`, `_has_crate_slot`).
  - `scripts/gameplay/unit_agent.gd`: the `board` order (`command_board`, `_board_order`).
  - `scripts/gameplay/skirmish.gd`: the right-click on a friendly train.
- **Railhead:**
  - `scripts/rails/railhead.gd` and `scenes/gameplay/railhead.tscn`.
  - The plan is `DepotNetwork.plan_spec(&"railhead")`.
  - The stop is `RailNetwork.depot_reach`, and the crates are `CargoVehicle.shipment_endpoint` and `CrateYard.beside_radius`.
  - Picking it: `skirmish.gd` (Load/Unload under the pointer) and `skirmish_hud.gd` `pick_stops()` (the stop markers and the minimap).
- **HUD:** the Disembark tile on the train card (slot 9, U, `command_disembark`, with the Drop card art for now) and the Railhead tile on the Build page (L, `build_railhead`).

## Checks

`tests/sky_pavilion_roads_troop_train_test.gd` (headless, in the suite) checks:
- **Troop train** (Arthurian skirmish):
  - a Knights train loads 6 Food crates and takes 6 Round Table Marines aboard: 150 cargo + 150 riders = 300;
  - a seventh Marine is refused as full, and a Tank is refused;
  - riders keep their housing;
  - they get off at the Keep;
  - boarded again, a derailment throws them out with a quarter of their health gone, slowed to 0.6x.
- **Railhead:**
  - its price and size;
  - a plan away from track is refused;
  - one stands beside track laid beyond the Keep's range;
  - Unload offers it to a train as a stop;
  - the loaded train runs out to it, sets its 6 Food crates down round it, and lets the 6 Marines off;
  - then it picks the crates up again.

`tests/command_cards_test.gd` counts the new tiles.

## Not done

- **AI:** neither AI boards trains or builds Railheads.
- **Planned track:** a Railhead plan beside *planned* track that isn't laid yet is refused.
- **Art:** the Railhead's model is a placeholder, and the Disembark tile borrows the Drop card art.
- **Not played:** nobody has played any of this yet.
