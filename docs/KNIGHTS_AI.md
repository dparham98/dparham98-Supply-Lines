# The Knights AI, the Cyborg AI's two-Barracks order, and the build-order stall

Item 5 of `docs/BALANCE_IMPLEMENTATION_HANDOFF.md` (2026-11-23). This branch is built on item 4 (`docs/KNIGHTS_ECONOMY.md`), which the Knights AI needs. It also merges item 1 (`docs/FREED_TARGETS.md`), without which a Grail Sentinel whose patient dies froze with a script error every frame, and `fix/ai-rail-over-sites` (below).

## The Knights AI

`scripts/ai/knights_player.gd` extends the Cyborg AI (`scripts/ai/enemy_player.gd`), keeping its scouting, defence, memory and waves. It is ported from the balance investigation's prototype (branch `claude/game-balance-knights-cyborg-52c0aa`, `tests/investigation/balance/scripts/knights_player.gd`), with the prototype's housing counter replaced by the game's (`KnightHousing`) and its stand-in for the Supply Balloon taken out: the Balloon is Stage 2.

- **Economy:** each Keep runs its own.
  - **Plans:** one at a time, paid from the Keep's stock (item 4). A House goes up when housing has `house_headroom` (3) or less to spare. Farms come next, then a Chapterhouse once there are 2 Farms, then more Farms up to `farms_wanted` (8 at home, 6 at an outpost). A further Chapterhouse needs `second_hall_farms` (3) Farms, up to `chapterhouses_wanted` (3 at home, 2 at an outpost).
  - **Workers:** one Forester to each Farm; the rest cut wood (one, or two while the Keep is short of it) and mine the nearest iron.
  - **Training:** the Keep trains Foresters without a pause to `foresters_wanted` (14 at home, 10 at an outpost).
- **A second Keep** at `expand_at` (300 s), or sooner if it runs out of building room. Two home Foresters carry 50 iron and 50 wood onto a site beside the nearest free iron mine and build it.
- **The army:** the Chapterhouses train `knight_mix` in turn, 10 Round Table Marines to 3 Questing Marines to 3 Grail Sentinels. It keeps 45 Food for workers while a Keep has fewer than `early_workers` (6). A Warhound scouts after 90 s. Grail Sentinels heal the most hurt friend within 22 m.
- **Waves:** as the Cyborg AI's, the first after `first_wave_seconds` (480 s, 8:00). The rally point is 36 m out, beyond the Keep's range, so the army stands off the ground its buildings go on.

**From the main menu** an AI side can now be the Knights (`MatchSetup.FACTIONS`). A Knights East start gets the Keep and two Forester Maidens in place of the Cyborg start, as the West does (`_knights_start(game, "enemy")`). The East's `EnemyPlayer` node, or the West's `PlayerAI` when spectating, is replaced by a Knights AI node with the same name, side and switch (`_knights_ai`). It is replaced rather than given a new script, so its ready-time lookups run again.

## The Cyborg AI's default order

`build_order` is Generator, Barracks, Generator, Barracks, Generator, Coal Mine, Tank Factory, Generator, with `workers_wanted` 6 (was 4) and `queue_depth` 3 (was 2). In the investigation, tech first lost to it. The Temple of Science is no longer in the default order, so the AI no longer researches Mining Trains unless a map sets a different order.

## The build-order stall

**Cause.** In a Cyborg-against-Cyborg match on Two Lakes, the West AI stopped at step 7 (a Generator beside its Depot), its plan "Waiting for footprint to clear" for the rest of the match. `tests/ai_match_sim.gd` with `SUPPLY_LINES_AI_DEBUG=1` reports what stands on a stuck footprint: a piece of the AI's own track (`rail=TrackCurve12`). Track laid across a site after it is planned makes the footprint invalid for good, and the AI waits for each plan to finish.

**Fix.** It was already fixed on `fix/ai-rail-over-sites` (commits `ac38d98` and `1cacfe3`, 2026-11-22, not yet merged into main), which this branch merges:

- the AI's track search and laying treat every unfinished build site, and a planned Depot's strip, as blocked;
- a site that track crosses anyway is given up and planned again, without skipping the build step;
- each AI has its own track router, and a lost Cargo truck is replaced.

That branch's own description and checks are in its `docs/ENEMY_AI.md` and `tests/enemy_ai_rules_test.gd`.

## Checks

`tests/ai_match_sim.gd` (not in the suite: ten game minutes take about three to four minutes at a fixed step). Run it with:

```
SUPPLY_LINES_WEST=cyborgs SUPPLY_LINES_EAST=arthurian_knights godot --headless --fixed-fps 30 --path . --script res://tests/ai_match_sim.gd
```

It prints each side every minute, and fails if a Cyborg side's build order does not complete or a side is wiped out before 10:00. It notes a Knights side with fewer than 50 army units at 8:00 (item 4's check).

**Results, 2026-11-24, on this branch (14 ten-minute matches):**

| West | East | Runs | Build order completed | Wiped out before 10:00 | Knights army at 8:00 |
| --- | --- | --- | --- | --- | --- |
| Cyborgs | Cyborgs | 3 | 3 of 3 | none | — |
| Cyborgs | Knights | 3 | 3 of 3 | none | 50 every time |
| Knights | Cyborgs | 8 | 7 of 8 | none | 50 every time |

Before the merge of `fix/ai-rail-over-sites`, one Cyborg-against-Cyborg match in one stalled on track over a site.

**A second, rarer stall, still open.** In one run of the eight with the Knights in the West, the East Cyborg AI stopped at its Coal Mine step from 5:00 to the end. Its plan waited for 25 iron that never arrived, while its Depot held 600 to 1,100 iron. It did not recur in four reruns of that pairing.

The likely cause, unconfirmed, is fuel. The Cargo truck burns coal outside the Depot's range, and the Coal Mine's iron is carried out there. A truck that runs dry on the way has no coal to refuel with until that same mine is built.

The sim now prints the truck's order, state and fetch target while a plan waits, so the next occurrence shows the cause.

The handoff asks for ten runs that all complete. This branch has 13 of 14 complete.

`tests/main_menu_test.gd` now checks that the Knights can be chosen on the AI's row, that spectating keeps a Knights choice, and that a match against the Knights puts a Keep and two Foresters at the East start, played by the Knights AI.

Not checked by a person: how the Knights AI plays against you, and whether its pace on 150 Food matches what the investigation saw.
