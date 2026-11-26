# Knights economy: Farms, Houses and housing

Item 4 of `docs/BALANCE_IMPLEMENTATION_HANDOFF.md` (2026-11-23). Before this the Knights had no source of Food: a match held the 325 Food it started with. Every number is in `assets/economy/knights_rules.tres` (`KnightsRules`), `scenes/gameplay/keep.tscn` or `assets/units/*.tres`; none has been played by a person.

## Rules

| Piece | Rule |
| --- | --- |
| Farm | 30 wood, 10 x 10 cells, 300 HP. It must stand inside one of your Keeps' range, or a pitched Hearth-Wain's (a Forward Farm, Round 3: `docs/ROUND3_HEARTH_WAIN.md`); with neither over its centre it lies dormant and yields nothing. It is a flat field: any unit walks over it, and nothing (no building, no track) can be built on it. One Forester Maiden tills it (right-click) from its near edge and carries the Food to the nearest Keep or pitched Hearth-Wain: 2 Food each 1.2 s work beat (3 on a lakeside Farm, with lake water within 8 m of its field; `docs/ROUND3_KNIGHTS_COAL.md`), 10 a load. A second worker is refused ("Farm already has a worker"). It never runs out. **While an enemy ground unit stands on the field it yields nothing** (checked every 0.25 s; flyers don't count); its Farmer waits beside it. `scripts/economy/farm.gd`, `scenes/gameplay/farm.tscn`. |
| Farmer | A Forester sent to a Farm becomes its Farmer for good (`farmers_permanent`). She works only a Farm. She refuses moving, felling, building, repairing and every other order ("A Farmer works only a Farm"), and an idle Farmer goes back to her Farm. If her Farm is lost she may take over an empty Farm and nothing else. She still takes 1 housing. She wears the sun hat, carries the farming tool and plays the Till clip, and the HUD calls her "Farmer". A Farm is therefore 30 wood plus a 45 Food Forester and 1 housing for the rest of the match. `scripts/gameplay/unit_agent.gd` (`farmer`, `farm`), `scripts/components/forester_animator.gd`. |
| House | 40 wood, 4 x 4 cells, 300 HP. Adds 8 housing while it stands inside one of its side's Keeps' range; outside, nothing. `scripts/economy/house.gd`, `scenes/gameplay/house.tscn`. |
| Housing | Side-wide (`scripts/economy/knight_housing.gd`). Each standing Keep gives 10. Forester 1, Warhound 1, Round Table Marine 2, Grail Sentinel 2, Questing Marine 2, Azure Dragon 4, Hearth-Wain 1; Cyborg units take none. Units alive and units queued in Keeps and Chapterhouses count. No upper limit. When there is no room the Keep or Chapterhouse refuses to queue the unit and says why; the production tile says "needs housing". |
| Building at home | A Knights plan (Keep, Chapterhouse, Farm, House) inside one of its side's Keeps' range builds from that Keep's stock with nothing carried; a Forester still builds it in. Inside a pitched Hearth-Wain's 15 m it builds from the Wain's hold the same way (Round 3). Outside every Keep's range its materials must be on the site, as before. Cyborg plans are unchanged: their iron is always carried onto the site and the Depot pays only the energy. The owner chose this for the Knights only (2026-11-24), as their trade for having no trucks. `ConstructionPlan.stock_keep`. |
| Keep | Houses 10. Stores Food, wood and iron as before. Trains for the AI side too: it used to train only for the player. |
| Start | A Knights start Keep holds 150 F, 100 W and 50 I with two Foresters, and no Food crate (was 300 F, 150 W, 150 I and a 25 F crate). A Keep founded from a plan still starts empty. |
| Training | Forester 12 s (was 8), Round Table Marine 15 (11), Grail Sentinel 15 (12), Questing Marine 17 (14), Azure Dragon 40 (26). Warhound stays 7. Prices unchanged. The Hearth-Wain (Dragon Yard, Round 3) trains in 16 s. |
| Energy | None. A Keep starts with 0 and nothing of the Knights' spends it. |

**Where the numbers come from.** The handoff (`docs/BALANCE_IMPLEMENTATION_HANDOFF.md` item 4) set a 4 x 4 Farm that blocks movement, worked by any Forester. Round 2 of the balance research (2026-11-23) changed three things, adopted on 2026-11-24 before the Stage 1 play-test:
- the Farm became 10 x 10 and walkable, so land runs out at about eight Farms a Keep;
- an enemy standing on a Farm stops its Food;
- Farmers became permanent, and the House became 4 x 4.

Yield stays at 2 Food a beat, the handoff's settled figure: size sets how much land Farms take, yield sets the pace.

**How much a Farm yields depends on the walk from its near edge.** The Farmer tills from the edge nearest her, so a 10 x 10 Farm is worked from about 5 m nearer the Keep than its centre. In the headless test a Farm whose centre is 14 m from the Keep's (near edge 9 m) yields 85 Food a minute, the handoff's figure. With its centre at 12 m it yields 100, and at 15 m, 80.

## HUD

- **Build page (Knights):** Farm (**F**) and House (**U**) beside Keep and Chapterhouse (docs/HUD_HOTKEYS.md). The placement preview turns red for a Farm outside your Keeps' range and every pitched Hearth-Wain's.
- **Keep panel:** "housing used / cap" on its status line. **Chapterhouse panel:** a Housing row.
- **Farm panel:** who tills it, Food a beat, Farmer 0 or 1, and "enemy on the field: no Food" while raided. **Farmer panel:** one Gather tile ("Work an empty Farm"); no Fell, Deliver or Drop. **House panel:** whether it is housed, and the side's housing.
- A Forester tilling shows the state "Farming"; a Farmer waiting out a raid shows "Enemy on the Farm".
- **Models (2026-11-24, the owner's art):**
  - **Farm:** a walkable 10 x 10 m vineyard (`scenes/models/farm_model.tscn`, `assets/models/buildings/farm.glb`, Blender source in `Blender/Buildings/Farm/`). Its two irrigation carriages water the rows (Work) while its Farmer works it, it rises through Build while it is built, and it plays Die with an irrigation-rupture effect when destroyed.
  - **House:** a 4 x 4 m timber dwelling (`scenes/models/house_model.tscn`, `assets/models/buildings/house.glb`, `Blender/Buildings/House/`), with Idle, Build and Die. The GLB's front door faces −Z, so `house_model.tscn` turns its `Rig` half round to face +Z, toward the RTS camera, like the Keep and Chapterhouse (2026-11-25; until then the camera saw the plain back). `tests/house_facing_check.gd` (rendered) checks it.
  - Both have their own portraits and Build-page cards. The placeholder boxes are gone.

## Checks

- `tests/knights_economy_test.gd` (headless):
  - the start stock, two Foresters and no crate, and the training times;
  - no energy on the Keep;
  - a Farm outside every Keep's range refused;
  - a Farm in range built from the Keep's wood with nothing carried;
  - one Forester yielding 80 to 90 Food a minute (85 measured, centre 14 m from the Keep), and a second one refused;
  - the field 10 x 10, walkable, with no building, House plan or track allowed on it;
  - an enemy Scout on the field stopping the Food while the Farmer waits, and the Food resuming once it leaves;
  - the Farmer refusing move, Fell, build and Fell autocast, and shown as "Farmer";
  - with her Farm destroyed, the Farmer refused a Farm that has a Farmer and taking an empty one;
  - a House covering 4 x 4 cells;
  - a Keep giving 10 housing, a House in range adding 8 and one outside adding nothing;
  - the Keep and a Chapterhouse refusing to train when housing is full, saying why;
  - the Farm and House tiles on the Build page, and the Farm, House and Keep panels;
  - an enemy Keep training a Forester.
- `tests/arthurian_faction_test.gd` now expects the 150 Food start, and stands three Houses before it trains: its scene's units already fill one Keep's 10 housing.
- **Not done here:** the handoff's "one Keep reaches 50 army units by 8:00 under the Knights AI" needs item 5's Knights AI and is checked there.

- **Construction sites:** a 10 x 10 site uses the existing 10 x 10 fence. A 4 x 4 House site shows only the grid, because there is no 4 x 4 fence scene yet.

Not checked by a person: the Farm and House models in play, the pace of the Knights' opening on 150 Food, how housing feels, whether a Keep's land runs out at about eight Farms, and whether permanent Farmers make the choice between farming and expanding a real one.
