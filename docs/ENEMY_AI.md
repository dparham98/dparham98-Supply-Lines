# Enemy AI player

Asked for on 2026-11-19, together with fog of war ([FOG_OF_WAR.md](FOG_OF_WAR.md)). The user chose:
- a full economy;
- the same fog rules as the player;
- the player's start mirrored to the East;
- attack waves that grow, the first at about 8 minutes with at least 6 units.

On 2026-11-22 the user asked for it to be brought up to date with main and finished: "building expansions, depots, and rail". It now also expands with Depot Trucks, joins its Depots with track and hauls by train, builds a Temple of Science and runs a Mining Train, and repairs.

## The start

On Two Lakes the East start mirrors the player's West start:
- **EnemyDepot.** It holds the same stock: 200 energy, 60 iron, 40 wood and 60 coal.
- **EnemyInfantry and EnemyStarterTruck.** One Infantry and one Cargo truck, the same as the player's.
- **The old roster is gone.** It was one enemy of each unit type, placed there for testing.
- **The other maps are unchanged.** The balanced map and First Contact keep their enemy units and have no enemy player.

## What it does

`scripts/ai/enemy_player.gd`, the `EnemyPlayer` node saved in `scenes/maps/lakes_skirmish.tscn`, decides once a second (`think_seconds`). It gives its units the same orders the player can.

- **Building.** It works through `build_order`: Generator, Barracks, a second Generator, a second Barracks, a third Generator, Coal Mine, Tank Factory, Temple of Science, then a fourth Generator.
  - The two-Barracks order (item 5 of the balance handoff) had left the Temple out, so it never researched anything. It was put back after the Tank Factory on 2026-11-25, with Minelaying.
  - After that it keeps adding Generators, up to `generators_wanted` (6) in all, while the Depot holds `iron_plenty` (250) iron. Once it has expanded, energy is what holds it back, not iron.
  - It plans one building at a time with `DepotNetwork.queue_plan(..., team = "enemy")`, as soon as the Depot holds the iron and energy.
  - Buildings go in the home Depot's range, toward the middle of the map. Each keeps a 2-tile walkway round it and stays off the way to the home mine. A Generator with no room left at home goes up at an expansion.
  - The Coal Mine goes on the nearest seam with no mine, within `reach` (90 m).
  - **Sight.** A site it sees is planned as the player plans from the Build page. A site it can't see yet is planned as a Cargo truck's Worksite, which needs no sight because the truck drives out to it. Since main gained the sight rule, the Coal Mine's seam 62 m out was otherwise never planned.
  - The Cargo truck fetches each site's iron (`command_fetch`). If the truck is lost while a site is short of iron, home prints another (100 E / 20 I), saving up for it first; without one the site would wait for its iron for good. Up to two workers build once the iron is on site. A mine out in the woods gets one worker early, to fell a way in.
  - When it has nothing to do, the truck parks beside the Depot. A truck left standing in a felled lane walled the workers in.
- **Workers.** The first `workers_wanted` (4) Infantry gather and build. The Barracks makes those before anything else. They are shared out by need each round:
  - iron, while the next building is short of it;
  - one on coal once it has a Coal Mine (`coal_wanted` 150);
  - one on wood while its Generators want fuel (`wood_wanted` 120);
  - every worker not on coal, once iron reaches `iron_plenty` (250) and wood is short. Without this its energy starved while iron piled up.
- **Production.** The Barracks and Tank Factory each keep two units queued (`queue_depth`).
  - Each building works through its mix in turn. The Barracks makes one Scout, then Infantry and Grenadiers; the Tank Factory makes Tanks, Motorcycles, Drones and Ubermechs.
  - **Saving up.** Units other than workers leave the Depot what it is saving for (`held_back`): the iron and energy the site being built still needs, and, for the round, a Depot Truck, a train, found track or the research. Before this, the army spent all the energy and the Tank Factory stood half built.
- **Expansion.** It sets up `expansions_wanted` (2) more Depots of its own within `expand_reach`, one at a time, once `expand_after` (3) steps of `build_order` are done.
  - **Where.** Beside the nearest iron mine on its own half of the map within `expand_reach` (170 m) of home. The mine must be past the Depot spacing (52.5 m), have no Depot of its own within 30 m, and have none of the player's buildings it remembers within 60 m. The Depot stands at the free spot nearest the mine, toward home. On Two Lakes the first is by Mine08, 83 m north-west of home.
  - **How.** Home prints a Depot Truck (150 E / 30 I), which drives there and deploys, by the same rules as the player's: footprint, truck strip and spacing.
  - **Fuel.** New vehicles start with empty tanks and fill up at the Depot while they stand (`docs/FUEL_BATCH.md`). The truck waits until its tank is full. Sent at once, it ran dry halfway.
  - **Workers.** The new Depot grants a Deforester as usual. It keeps `expansion_workers` (2) workers there, on top of the 4 at home. The Barracks makes the extra, and each new worker goes to the Depot most short of them. They gather iron at the mine nearest their Depot.
  - **One at a time.** With `haul_trains` on, the next Depot Truck waits until track joins the last expansion to home, or until it found there is no path.
  - A Depot it captures counts as an expansion. Track joins only expansions within `expand_reach` of home; one further away stands alone.
- **Rail.** Track is laid with the same search the player's suggested track uses: the shortest open path of straights and curves touching both rings (`docs/RAIL_PLANNING.md`).
  - **Haul lines.** Track joins each expansion to home. Home buys a train on that line, and the train runs a repeating delivery route, carrying a full load of iron from the expansion to home.
  - **Room at home.** A Depot's energy, iron, wood and coal share one store (2,000). In a sim, the trains filled home with iron, which left its Generators no room to bank energy, so they stopped. So while home holds `haul_iron_cap` (800) iron or has less than `haul_room` (400) room, haul routes pause and the mining train stops. With that much iron the home workers also cut wood for the Generators, up to twice `wood_wanted`, but two stay on iron while a site is being built, since a worker carrying wood isn't sent to build. Hauling and mining start again once there is room.
  - **Mining line.** Once Mining Trains is researched, track runs from home to `mining_target`: the nearest iron mine on its side at least 40 m from home that no expansion of its own works. Home buys a train for it, which mines it (`command_mine`).
  - **Pieces that can't be laid.** The router works out a move's cells once per lattice phase and reuses them. A tile centre exactly on a piece's edge can round either way, so those cells can differ by a tile from the laid piece's own. On Two Lakes the path from home to Mine08 then held a straight over forest, which could not be laid and would have left a gap. So the AI checks every found piece against the laid piece's cells (`RailNetwork.unfit_moves`). It forbids the moves that fail (`rail_router.gd`, `forbidden`) and searches again, up to five times. Mine08 needed one retry. Each search took 0.1 to 0.25 s of work, spread over frames. The player's suggested track can hit the same mismatch; it is unchanged here.
  - **Build sites.** Its track keeps off every unfinished build site and the strip a planned Depot keeps clear (`RailNetwork.site_cells`, the router's `blocked` cells, and the same check in `unfit_moves` and `lay_link`). Found on 2026-11-22 in spectated games against a second AI: track across its Tank Factory site left that site waiting for its footprint to clear for good, and the AI never got past step 4. If track crosses one of its sites anyway, such as the other side's, the AI cancels that plan and plans the building again elsewhere, keeping its build step. Iron already on the site stays there as piles.
  - **A router for each side.** `RailNetwork.begin_link` keeps a track-search router for each team, so with an AI on both sides (spectating, docs/MAIN_MENU.md) one side's new search never resets the other's half-done one.
  - **One search at a time**, worked on `link_usec` (2 ms) a frame so a long one doesn't hold the frame up. Found track is laid once home has the iron; if the ground has changed since, it searches again. Pairs with no open path are not tried again.
  - Home pays for the track and its upkeep, as the player's Depot pays for the player's.
- **Research.** Once its Temple of Science stands, it researches what `research_wanted()` lists, one at a time, saving for each (`held_back`):
  - Mining Trains (150 E / 100 I), unless `mining_trains` is off;
  - Minelaying (150 E / 100 I), once it has a Derailer, unless `minelaying` is off.
- **Mines** (docs/MINES.md). With Minelaying, a Derailer at home with mines aboard and a full tank, not in a wave and with no threat near, lays them (`lay_mines`):
  - **Where:** a row across the way toward what it would attack, `mine_distance` (45 m) out from home, or half way if that's nearer. Spots are `mine_spacing` (5 m) apart, from the middle outward. The way is fixed the first time it knows of somewhere to attack, so the row stays put.
  - **How many:** it keeps `mines_wanted` (6) of its own laid. A spot a Derailer couldn't reach isn't tried again.
  - **Buying:** a Derailer idle at home buys mines (Buy mine) until it carries two, from the Depot's iron.
  - **Seen in the sim (2026-11-25):** Minelaying done by 9:00 and mines laid by 10:00. With no opponent the Depot ran out of coal by 9:00, and Derailers without fuel then waited at home.
- **Repair.** A building of its own below `repair_below` (75%) of its health, with none of the player's units seen within 30 m, gets the nearest free worker within 120 m. At most `repairers` (2) repair at once. They pay from the nearest covering stockpile, as the player's do.
- **Scouting.** Its Scout visits the start sites (`Sites`) it has not seen, nearest first.
- **Defence.** When it sees one of the player's units within `defend_radius` (60 m) of its buildings, the army attack-moves onto it. Units away on a wave keep going.
- **The army.** Units that are neither workers nor the Scout wait at a rally point `rally_distance` (18 m) from the Depot, toward the middle of the map. It was 24 m; with the spread round it, vehicles stood outside the Depot's 26.25 m range and couldn't refuel.
- **Waves.** After `first_wave_seconds` (480), the whole army attack-moves on a target once it has at least `first_wave_size` (6) units. Each later wave waits for `wave_growth` (2) more units than the last.
  - Vehicles low on fuel stay behind to fill up, and don't count toward the wave's size.
  - **The target** is the nearest of the player's buildings it remembers. If it remembers none, the target is the nearest start site it has not seen.
  - A wave that clears a target moves on to the next.
  - A wave down to its last unit, or with nothing left to find, comes home and joins the next one.
- **Losing.** If its home Depot is gone, the nearest of its other Depots becomes home. With no Depot left, a Depot Truck it still has redeploys. With no units and no buildings left, the player wins: "VICTORY — the enemy has nothing left."

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
- **What a Depot prints is its side's.** Trains, Cargo trucks and Depot Trucks printed at a Depot used to come out as the player's whatever the Depot's side (`depot.gd`). Units from a Barracks or Factory, and the Deforester a new Depot grants, already took the side.
- **Track for the enemy** (`rail_network.gd`): `begin_link`, `advance_link`, `link_cost` and `lay_link`. They find and lay the same track `suggest_route` and `commit_plan` do, with a router of their own, so the player's plan, picks and cursor search are never touched. The pieces belong to the paying Depot's side.
- **What the player sees:**
  - Notices go through `skirmish.notify(text, team)`, and another side's are not shown. Since 2026-11-22 this also covers the Temple's research notices, repair orders and a train's refused Mine order.
  - The pending count on the HUD and the plan outlines on the map show only the player's plans.
  - First Contact's "gather, print, fight" victory is not used on a map with an enemy player, and the enemy's deliveries and Infantry don't count toward it.

## Checks

- **`tests/enemy_ai_rules_test.gd`** (headless, in the suite). It checks that:
  - the AI starts knowing nothing of the player and heads for an unseen start;
  - its plan is its own, paid by its Depot, and its notices are hidden;
  - a Barracks from its plan is its own;
  - a damaged building of its own gets a worker to repair it;
  - it finds an expansion site on its side, past the spacing, that takes a Depot;
  - a Cargo truck its Depot prints is its own;
  - its track goes round an unfinished build site of its own, and a site with track across it is given up and planned again;
  - it finds track from home to its mining mine and lays it, paid by home and its own, with the player's plan and messages left alone, and the track joins the two;
  - with Mining Trains researched, it buys a train for that mine;
  - it remembers a Depot it saw once it is out of sight;
  - it meets a raider near its base;
  - with nothing left, it is beaten.
- **`tests/enemy_ai_sim.gd`** plays ten game minutes headless (`SUPPLY_LINES_AI_MINUTES` sets more), with the player's units held still. Each minute it prints the buildings, stock, expansions, track, trains and research.
  - It is not in the suite, because the suite runs in real time. Run it with `--fixed-fps 30`; it takes about a minute.
  - On 2026-11-22, over 15 minutes, the AI:
    - had its Generators, Barracks, Coal Mine, Tank Factory and Temple of Science up by the fifth minute, and 6 Generators by the eighth;
    - had its expansion Depot by Mine08 by the fourth minute and its track down by the sixth;
    - finished Mining Trains and ran a haul train and a mining train by the seventh;
    - sent its first wave at about 9 minutes with 17 units, and had 70 by minute 15, with 400–650 energy throughout.
  - Runs differ a little from one to the next. In this one it made one expansion of its own; the second listed is the player's Depot it captured.

## Provisional

- **Strength.** It loses nothing to an idle player, so the sims overstate it. The exports on the `EnemyPlayer` node tune it: `first_wave_seconds`, `first_wave_size`, `wave_growth`, `workers_wanted`, `queue_depth`, the mixes, and in the Expansion and Repair groups `expansions_wanted`, `expand_after`, `expand_reach`, `expansion_workers`, `generators_wanted`, `repair_below` and `repairers`.
- **Vehicles can run dry.** They refuel only in Depot range, so a Motorcycle crossing the map may stop out of fuel, as the player's would.
- **Not done.**
  - No dams: they have no rules yet (`docs/TWO_LAKES_MAP.md`).
  - It never uses the Derailer, and never rebuilds a wreck of its own track.
  - Its army rallies at home only, so an expansion is defended only when the player is seen near it.
  - It never repairs vehicles or shared mines.
- **Two Lakes only.** The other maps have no enemy player.
