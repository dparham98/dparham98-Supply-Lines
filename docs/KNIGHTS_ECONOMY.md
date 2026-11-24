# Knights economy: Farms, Houses and housing

Item 4 of `docs/BALANCE_IMPLEMENTATION_HANDOFF.md` (2026-11-23). Before this the Knights had no source of Food: a match held the 325 Food it started with. Every number is in `assets/economy/knights_rules.tres` (`KnightsRules`), `scenes/gameplay/keep.tscn` or `assets/units/*.tres`; none has been played by a person.

## Rules

| Piece | Rule |
| --- | --- |
| Farm | 30 wood, 4 x 4 cells, 300 HP. It must stand inside one of your Keeps' range. One Forester Maiden tills it (right-click) and carries the Food to the nearest Keep: 2 Food each 1.2 s work beat, 10 a load. A second worker is refused ("Farm already has a worker"). It never runs out. `scripts/economy/farm.gd`, `scenes/gameplay/farm.tscn`. |
| House | 40 wood, 3 x 3 cells, 300 HP. Adds 8 housing while it stands inside one of its side's Keeps' range; outside, nothing. `scripts/economy/house.gd`, `scenes/gameplay/house.tscn`. |
| Housing | Side-wide (`scripts/economy/knight_housing.gd`). Each standing Keep gives 10. Forester 1, Warhound 1, Round Table Marine 2, Grail Sentinel 2, Questing Marine 2, Azure Dragon 4; Cyborg units take none. Units alive and units queued in Keeps and Chapterhouses count. No upper limit. When there is no room the Keep or Chapterhouse refuses to queue the unit and says why; the production tile says "needs housing". |
| Building at home | A Knights plan (Keep, Chapterhouse, Farm, House) inside one of its side's Keeps' range builds from that Keep's stock with nothing carried; a Forester still builds it in. Outside every Keep's range its materials must be on the site, as before. Cyborg plans are unchanged: their iron is always carried onto the site and the Depot pays only the energy. The owner chose this for the Knights only (2026-11-24), as their trade for having no trucks. `ConstructionPlan.stock_keep`. |
| Keep | Houses 10. Stores Food, wood and iron as before. Trains for the AI side too: it used to train only for the player. |
| Start | A Knights start Keep holds 150 F, 100 W and 50 I with two Foresters, and no Food crate (was 300 F, 150 W, 150 I and a 25 F crate). A Keep founded from a plan still starts empty. |
| Training | Forester 12 s (was 8), Round Table Marine 15 (11), Grail Sentinel 15 (12), Questing Marine 17 (14), Azure Dragon 40 (26). Warhound stays 7. Prices unchanged. |
| Energy | None. A Keep starts with 0 and nothing of the Knights' spends it. |

**How much a Farm yields depends on the walk.** In the headless test a Farm whose centre is 12 m from the Keep's yields 85 Food a minute, the handoff's figure. Touching the Keep's drop-off it yields about 100; at 13 m about 80; at 18 m about 70.

## HUD

- **Build page (Knights):** Farm (**F**) and House (**U**) beside Keep and Chapterhouse (docs/HUD_HOTKEYS.md). The placement preview turns red for a Farm outside your Keeps' range.
- **Keep panel:** "housing used / cap" on its status line. **Chapterhouse panel:** a Housing row.
- **Farm panel:** who tills it, Food a beat, workers 0 or 1. **House panel:** whether it is housed, and the side's housing.
- A Forester tilling shows the state "Farming".
- **Placeholders:** the Farm and House models are boxes (`scenes/models/farm_placeholder.tscn`, `house_placeholder.tscn`) in their `Visuals` slots, and their card icons and portraits borrow the Generator's and Depot's. The owner will supply art.

## Checks

- `tests/knights_economy_test.gd` (headless):
  - the start stock, two Foresters and no crate, and the training times;
  - no energy on the Keep;
  - a Farm outside every Keep's range refused;
  - a Farm in range built from the Keep's wood with nothing carried;
  - one Forester yielding 80 to 90 Food a minute (85 measured), and a second one refused;
  - a Keep giving 10 housing, a House in range adding 8 and one outside adding nothing;
  - the Keep and a Chapterhouse refusing to train when housing is full, saying why;
  - the Farm and House tiles on the Build page, and the Farm, House and Keep panels;
  - an enemy Keep training a Forester.
- `tests/arthurian_faction_test.gd` now expects the 150 Food start, and stands three Houses before it trains: its scene's units already fill one Keep's 10 housing.
- **Not done here:** the handoff's "one Keep reaches 50 army units by 8:00 under the Knights AI" needs item 5's Knights AI and is checked there.

Not checked by a person: the placeholders, the pace of the Knights' opening on 150 Food, and how housing feels.
