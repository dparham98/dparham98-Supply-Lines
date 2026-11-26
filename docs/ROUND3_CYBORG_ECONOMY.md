# Round 3: Cyborg iron economy and the Hydro Dam

Item 4 of the Round 3 balance handoff (2026-11-25). Stacked on item 3 (`docs/ROUND3_SPELLS_AND_RESEARCH.md`).

The Cyborgs' prices move toward iron. Power costs less energy and stops at 3x. A Depot stops taking raw materials at a ceiling. Two Lakes' mines hold tiered reserves. A new building, the Hydro Dam, turns the map's dam channels into energy.

## Prices

The units' costs are in `assets/units/*.tres`:

| Unit | Energy | Iron | Was |
| --- | --- | --- | --- |
| Deforester (Infantry) | 90 | 25 | 100 / 20 |
| Scout | 35 | 10 | |
| Grenadier | 75 | 20 | |
| Derailer (Motorcycle) | 60 | 25 | |
| Drone | 50 | 15 | |
| Tank | 140 | 55 | |
| Übermech | 240 | 100 | |

The buildings' costs are in `assets/buildings/*.tres`. The Generator's are on `assets/economy/supply_rules.tres`:

| Building | Energy | Iron |
| --- | --- | --- |
| Barracks | 80 | 60 |
| Tank Factory | 150 | 100 |
| Foundry | 120 | 100 |
| Generator | 0 | 40 |
| Hydro Dam | 0 | 90 |

## Production power

The Barracks and Tank Factory now go up to 3x (`max_power`; it was 4x).

Extra power costs less. At power p a unit costs its base energy plus (p − 1) × `extra_power_energy_scale` (0.35) of it. The extra is drawn while the unit prints, as before. So:
- 2x prints in half the time for 135% of the base;
- 3x prints in a third of the time for 170%.

Before this, 2x cost 200%. The scale is on each building's stats (`ProductionBuildingStats`). See `docs/PRODUCTION_POWER.md`.

## The raw-material ceiling

`DepotRules.raw_material_ceiling` is 1,400 (`assets/economy/depot_rules.tres`).

**What counts:**
- a Depot: its Iron, Wood and Coal together (`depot.raw_material_total()`);
- a Keep: its Iron and Wood only (`keep.gd` overrides it). That leaves room for Food and Coal.

**What it stops:** at the ceiling, a worker bringing Iron or Wood waits at the stockpile and keeps its load. Its state reads "Depot at its 1400 raw-material ceiling · holding iron". It drops the load once the total falls below the ceiling.

**What it doesn't stop:**
- Coal still drops off, so a Depot can pass 1,400 with coal.
- Cargo trucks, trains, crates and the starting stock aren't held back; only workers' drop-offs are (`unit_agent._return_cargo`).

The point is to keep room in the shared 2,000 store for Energy (and Food).

## Mine reserves on Two Lakes

Each mine site now holds its tier's iron. The reserve is set by the mine's `site_reserve` in `scenes/maps/lakes_skirmish.tscn` and spread over its 12 cells when the map loads. The terrain file still holds 7,500 a site.

| Tier | Mines | Iron |
| --- | --- | --- |
| Home | IronMine, IronMineB, Mine03, Mine04, Mine15, Mine16 | 2,250 |
| Expansion | Mine01, Mine02, Mine07, Mine08, Mine13, Mine14 | 3,500 |
| Pass | Mine05, Mine06, Mine17, Mine18 | 5,000 |
| Gate | Mine09, Mine10 | 5,000 |
| Crag | Mine11, Mine12 | 8,000 |

A mine left at `site_reserve = -1` keeps the usual amount, so other maps are unchanged.

## The Hydro Dam (H)

Cyborgs only, on the Build page. It costs 0 Energy / 90 Iron and has an 8 × 3 footprint.

**Where it stands.** Only across a **dam channel**: the narrow water between a lake and a bay. A map lists its channels as `dam_channels` on its TerrainGrid (`TerrainGrid.dam_channel_at`, `dam_site_valid`). Two Lakes has eleven, in `scenes/maps/lakes_terrain.tscn`. Each is 8 cells wide, and the dam crosses it along x. Every footprint cell must be open water with nothing on it.
- A plan within 4 cells of a channel snaps across it (`DepotNetwork.dam_start`). Anywhere else it's refused: "A Hydro Dam stands across a dam channel".
- **Only on maps with channels:** on a map without them, the tile is hidden.
- **Not on the Worksite page:** trucks can't unload on water.

**Building it.** It goes up like any Cyborg plan: iron delivered onto its footprint, then Deforesters build it in.
- The piles lie on the water cells.
- Builders work from the bank.
- Forest walls most channels, so the first builder fells a lane in, as for a Coal Mine in the woods.
- It costs no energy, so no stockpile has to cover it while it's built.

**What it does.** Every `beat_seconds` (3 s) it banks `energy_per_beat` (12 E) into the friendly Depot whose range covers it: 4 E a second.
- **Nothing is pooled:** it goes into that one Depot.
- **A full Depot:** a beat that finds the Depot without 12 free waits at its end, so blocked time banks nothing.
- **No covering Depot:** with no friendly Depot covering it (lost, captured, out of range), it pauses and looks again twice a second.

The numbers are on `assets/buildings/hydro_dam.tres` (`HydroDamStats`); the script is `scripts/economy/hydro_dam.gd`.

**Selected,** it shows its state, its output in E/s, the beat and its Depot, with Focus Depot.

**On Two Lakes, a Depot has to be near.** A Depot's range is 26.25 m, and no start Depot is within range of a channel. Only four channels have open ground for a Depot within range: the outer north-west and north-east, and the two inner north. The rest need forest felled first.

**Art.** `scenes/models/hydro_dam_model.tscn` is a placeholder of boxes in the Visuals slot: a concrete wall, a turbine house in team paint and a spillway. The icon, portrait and Build card (`sl_build_hydro_dam.png`) are rendered from it by `render_hud_images.gd -- hydro_dam`.

## AI

`scripts/ai/enemy_player.gd`; see `docs/ENEMY_AI.md`.
- **Prices:** it reads its prices from the same stats, so the new ones apply as they are.
- **Hydro Dam:** once `dam_after_step` (2) steps of its build order are done, it plans a dam across any channel one of its Depots covers. The dam comes ahead of the rest of the order.
- **Ceiling:** at the ceiling, no new workers go to iron or wood. Free ones go to coal while it is short.
- **Drone escort:** with Tanks in the group, a Drone keeps behind the frontmost one, at most `drone_behind_front` (10 m) back and never ahead.

## Checks

`tests/cyborg_iron_and_dam_test.gd` (headless, in the suite) checks:
- **Prices:** all the prices above; power to 3x at +35% a step. On a Barracks, Infantry at 2x take 5 s for 122 E, and at 3x cost 153 E.
- **Ceiling:**
  - at 1,400, a Deforester's Iron and Wood wait;
  - its Coal drops off;
  - below the ceiling its Iron goes in again.
- **Reserves:** a mine of each tier on Two Lakes holds its tier's iron.
- **Dam placement, on Two Lakes:**
  - the Build page offers the dam;
  - it's refused on land;
  - planned from the bank, it snaps across the inner north-west channel;
  - a second plan can't overlap the first.
- **Dam building:** a Deforester on the felled bank delivers its 40 iron and builds the dam in, with 50 already on site. The dam then takes its 24 water cells.
- **Dam output:**
  - nothing before 3 s, 12 E at 3 s, 36 after 9 s;
  - nothing with no room;
  - it pauses with no friendly Depot and banks again after;
  - the HUD shows it.
- **No channels:** on First Contact there's no tile and no plan.
- **AI dam:** the AI finds the channel its Depot covers, plans the dam only after `dam_after_step`, and is done with a channel once a dam is across it.
- **AI Drone escort:**
  - a Drone behind the rear Tank comes up behind the front one;
  - one already there stays;
  - one ahead drops back.

Existing tests updated:
- `production_power_test`: 3x, +35%, Infantry 90 E;
- `two_lakes_map_test`: tiered reserves;
- `unit_stats_test`: Infantry 90 / 25;
- `command_cards_test`: 81 tiles.

## Not done

- **Dam art:** the model is a placeholder. There's no water flow, and no animation when it runs.
- **AI dams in play:** the AI's dam hasn't been watched being built. Its Cargo truck must reach the site through the lane its builder fells.
- **Keep ceiling:** the Keep's ceiling (Iron and Wood only) isn't covered by the test.
- **Not played by a person:** the new economy's feel.
