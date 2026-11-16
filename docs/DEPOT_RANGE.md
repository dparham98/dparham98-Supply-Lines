# Depot range and Generator assignment

These changes come from the playtest of main at 8ee9b55 (2026-11-15).

## Depot range halved

- `construction_radius` in `assets/economy/depot_rules.tres` is now 17.5 m, half the old 35 m. The user may shrink it further after more testing; it is the one value to change.
- Everything that used the Depot's range follows it:
  - the Territory ring;
  - where a Depot pays for building and repair (`SupplySource.radius`);
  - where an Iron Mine and a rail piece can be paid for;
  - which Depot a mine's repair is charged to.
- **Deployed Cargo trucks** take half the Depot range (`depot_range_fraction` 0.5), so their range halved too, to 8.75 m.
- **Depot spacing now follows the range** (`docs/DEPOT_SPACING.md`): a new Depot's range may not overlap another friendly Depot's, so Depots stand at least twice the range apart, 35 m now. It was a fixed 70 m, which left a 35 m gap between ranges at 17.5 m; the playtest asked for only no overlap.

## Iron moved closer on the balanced map

At 17.5 m no start or expansion on the balanced map had iron inside its range, so no Iron Mine could be built anywhere. The three iron fields of each side were moved in `scripts/tools/draw_balanced_layout.gd`, and the map was rebuilt with the steps in `docs/BALANCED_MAP.md`. The layout had never been edited by hand: the unchanged script redrew it byte for byte first.

| Field | Was (cells) | Now (cells) | Distance from its site |
| --- | --- | --- | --- |
| Main | 107-112, 262-268 (east of south) | 73-78, 257-263 (south-west) | 9.3 to 17.1 m |
| Safe expansion | 42-46, 150-155 | 51-55, 146-151 | inside 17 m |
| Exposed expansion | 102-106, 366-371 | 93-97, 363-368 | inside 17 m |

- Each field keeps its size: 42, 30 and 30 cells. They stay clear of the Depot footprint and of the truck strip on its east side.
- Start B mirrors start A, as the drawing script always does.
- The starter mines moved onto the new main fields: `IronMine` to (-174, 11) and `IronMineB` to (174, -11).
- The rebuilt files are `layout.png`, `terrain_cells.bin`, `terrain_data.png` (lossless) and `terrain_surface.png`, plus the scenery in `balanced_terrain_landmarks.tscn`. `assets/maps/source_map.png` is untouched.
- Moving the range again means moving these fields again.
- **The original First Contact map (`resource_skirmish.tscn`) was not changed.** Its iron is also beyond 17.5 m of its Depot, so no Iron Mine can be built there from the start.
- The tests that check mechanics on First Contact and the exercise maps set the range back to 35 m inside the test, with a comment. Those mechanics are mines, plans, repair, refuelling, rails and mobile supply.

## Generators use the Depot they stand in

- The Assign Depot command is gone, with its card tile, its A key (`command_assign_depot`), its pick prompt, and its map and minimap handling.
- A Generator burns fuel from, and banks energy in, the nearest friendly Depot whose range covers it (`find_source` in `energy_generator.gd`).
  - A Generator built by Infantry or from a plan still starts with the Depot that paid for it.
  - One paid by a deployed Cargo truck, or authored without a Depot, takes the nearest covering Depot when it is placed.
- If that Depot is captured or destroyed, the Generator looks again about twice a second and takes another covering friendly Depot if there is one. Otherwise it waits, as before.
- Focus Depot (F) is still on the Generator card.

## Range shown while placing a Depot

- The placement preview (`scenes/gameplay/construction_preview.tscn`) has a `Range` ring the size of a Depot's range, saved hidden.
- It shows around where the new Depot will stand in three cases:
  - while a Depot is placed by Infantry;
  - while a Depot plan is placed from the Build page;
  - while a selected Depot Truck's Deploy waits for a site. This last one is new: Deploy had no preview before.
- The Deploy preview colours the footprint green or red and says why it is blocked: spacing, or not empty buildable land.

## Checks

- `tests/depot_range_test.gd` (headless) checks:
  - the 17.5 m range and the Territory ring;
  - that a Generator takes its covering Depot and finds another when that one is lost;
  - that the Assign Depot action and tile are gone;
  - the range ring and status in the Deploy preview.
- `command_cards_test` and `hud_hotkeys_test` no longer expect the Assign Depot tile.
