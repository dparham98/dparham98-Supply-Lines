# Enemy AI player

Asked for on 2026-11-19, together with fog of war ([FOG_OF_WAR.md](FOG_OF_WAR.md)). The user chose:
- a full economy;
- the same fog rules as the player;
- the player's start mirrored to the East;
- attack waves that grow, the first at about 8 minutes with at least 6 units.

## The start

On Two Lakes the East start mirrors the player's West start:
- **EnemyDepot.** It holds the same stock: 200 energy, 60 iron, 40 wood and 60 coal.
- **EnemyInfantry and EnemyStarterTruck.** One Infantry and one Cargo truck, the same as the player's.
- **The old roster is gone.** It was one enemy of each unit type, placed there for testing.
- **The other maps are unchanged.** The balanced map and First Contact keep their enemy units and have no enemy player.

## What it does

`scripts/ai/enemy_player.gd`, the `EnemyPlayer` node saved in `scenes/maps/lakes_skirmish.tscn`, decides once a second (`think_seconds`). It gives its units the same orders the player can.

- **Building.** It works through `build_order`: Generator, Barracks, Coal Mine, Tank Factory, then a second Generator.
  - It plans one building at a time with `DepotNetwork.queue_plan(..., team = "enemy")`, as soon as the Depot holds the iron.
  - Buildings go in the Depot's range, toward the middle of the map. Each keeps a 2-tile walkway round it and stays off the way to the home mine.
  - The Coal Mine goes on the nearest seam with no mine, within `reach` (90 m).
  - The Cargo truck fetches each site's iron (`command_fetch`). Up to two workers build once the iron is on site. A mine out in the woods gets one worker early, to fell a way in.
  - When it has nothing to do, the truck parks beside the Depot. A truck left standing in a felled lane walled the workers in.
- **Workers.** The first `workers_wanted` (4) Infantry gather and build. The Barracks makes those before anything else. They are shared out by need each round:
  - iron, while the next building is short of it;
  - one on coal once it has a Coal Mine (`coal_wanted` 150);
  - one on wood while its Generators want fuel (`wood_wanted` 120);
  - every worker not on coal, once iron reaches `iron_plenty` (250) and wood is short. Without this its energy starved while iron piled up.
- **Production.** The Barracks and Tank Factory each keep two units queued (`queue_depth`).
  - Each building works through its mix in turn. The Barracks makes one Scout, then Infantry and Grenadiers; the Tank Factory makes Tanks, Motorcycles, Drones and Ubermechs.
  - Units other than workers leave the Depot the iron the building in progress still needs.
- **Scouting.** Its Scout visits the start sites (`Sites`) it has not seen, nearest first.
- **Defence.** When it sees one of the player's units within `defend_radius` (60 m) of its buildings, the army attack-moves onto it. Units away on a wave keep going.
- **The army.** Units that are neither workers nor the Scout wait at a rally point 24 m from the Depot, toward the middle of the map.
- **Waves.** After `first_wave_seconds` (480), the whole army attack-moves on a target once it has at least `first_wave_size` (6) units. Each later wave waits for `wave_growth` (2) more units than the last.
  - **The target** is the nearest of the player's buildings it remembers. If it remembers none, the target is the nearest start site it has not seen.
  - A wave that clears a target moves on to the next.
  - A wave down to its last unit, or with nothing left to find, comes home and joins the next one.
- **Losing.** If its Depot is gone, a Depot Truck it still has redeploys. With no units and no buildings left, the player wins: "VICTORY — the enemy has nothing left."

## What it knows

It sees by the fog of war: the map itself, its own things, and what its units and buildings see now (`FogOfWar.visible_to("enemy", ...)`).

- **It remembers** the player's buildings and build sites it has seen. It keeps where each one stood, and forgets one only once it sees that it is gone.
- **The player's units** count only while it sees them.
- **At the start** it does not know where the player is. It finds out by scouting the start sites.

## What changed for both sides

The economy code assumed the player in places. It now takes the side from the plan, the unit or the building:
- **Plans** carry a `team` (`construction_plan.gd`). Only that side's stockpiles pay one, and the finished building is that side's. Mines stay shared.
- **Depots and production buildings** work for either side that plays (`SupplySource.plays`): they queue, build trucks, grant Infantry and make units.
- **`DepotNetwork`** takes a team in `establish`, `queue_plan` and `covering_sources`. A deployed truck's Depot is the truck's side's.
- **Cargo trucks** fetch only for their own side's sites. Planned track only connects to sites of its own side.
- **What the player sees:**
  - Notices go through `skirmish.notify(text, team)`, and another side's are not shown.
  - The pending count on the HUD and the plan outlines on the map show only the player's plans.
  - First Contact's "gather, print, fight" victory is not used on a map with an enemy player, and the enemy's deliveries and Infantry don't count toward it.

## Checks

- **`tests/enemy_ai_rules_test.gd`** (headless, in the suite). It checks that:
  - the AI starts knowing nothing of the player and heads for an unseen start;
  - its plan is its own, paid by its Depot, and its notices are hidden;
  - a Barracks from its plan is its own;
  - it remembers a Depot it saw once it is out of sight;
  - it meets a raider near its base;
  - with nothing left, it is beaten.
- **`tests/enemy_ai_sim.gd`** plays ten game minutes headless, with the player's units held still.
  - It is not in the suite, because the suite runs in real time. Run it with `--fixed-fps 30`; it takes about two minutes.
  - On 2026-11-19 the AI:
    - had a Generator in its first minute and a Barracks in its second;
    - built its Coal Mine by the third minute and its Tank Factory by the fourth;
    - had its second Generator by the fifth;
    - sent its first wave at 8 minutes with 27 units, and had 51 by minute 12.

## Provisional

- **It is strong.** By 8 minutes it fields about 27 units, because it never stops producing and loses nothing to an idle player. The exports on the `EnemyPlayer` node tune it: `first_wave_seconds`, `first_wave_size`, `wave_growth`, `workers_wanted`, `queue_depth` and the mixes.
- **Vehicles can run dry.** They refuel only in Depot range, so a Motorcycle crossing the map may stop out of fuel, as the player's would.
- **No expansion.** It never builds a second Depot, rail or a dam, and never repairs.
- **Two Lakes only.** The other maps have no enemy player.
