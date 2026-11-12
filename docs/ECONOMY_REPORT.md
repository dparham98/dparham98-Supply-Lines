# Economy report

Report only. No gameplay code, scene or data file was changed. Written 2026-11-12 against `main` at `a13e720`, for the balanced map (`scenes/maps/balanced_skirmish.tscn`).

**Nothing in this report has been played by a person.** The current-rules figures come from the rule files and from headless simulations that drive the real map with the game's own unit orders. Everything about the proposed design is arithmetic built on those measurements. Section 2 keeps the two apart.

Words used throughout:

- **E, I, W, C**: energy, iron, wood, coal. "100 E / 20 I" is a price of 100 energy and 20 iron.
- **Depot**: the building that holds a local stockpile. **Service range**: the 35 m circle round a Depot inside which buildings are wired to it and vehicles refuel. **Drop-off range**: the 8.5 m circle inside which a worker hands over a load.
- **Yard**: a new, inner 17.5 m circle round a Depot proposed in section D.
- **Load**: what one Infantry carries, 10 units.
- **Crate**: a 25-unit container of one resource. A Cargo truck carries 4, a Train 12.
- **Plan** or **site**: a building that has been placed but not yet built.
- **Kit**: the crates one site needs.
- **Testing switches**: settings left on for development that distort the economy. All analysis here has them off; section A.5 says what each changes.

## 1. The recommended economy in brief

Supply Lines is a game about where things are. One Infantry brings home 33 iron a minute from a mine 19 m away and 110 a minute from a mine next to a stockpile. That gap is the whole economy: distance is the price of everything. The design below keeps that, and removes the three things that currently let a player skip it or get stuck on it.

**The economy in seven lines**

1. **Iron builds, wood burns, coal moves.** Iron is the only building material. Wood is the fuel found everywhere. Coal is the fuel for vehicles and the strong fuel for Generators, and it is far away behind forest.
2. **Energy comes only from Generators.** A Generator sits inside a Depot's service range, burns fuel from that Depot and puts energy into that Depot. A Generator costs iron and no energy, so a base that runs dry can always recover.
3. **Energy lives in Depots.** It leaves a Depot three ways: by wire to buildings inside the 35 m service range, as 25 E crates on a truck or train, and through the rail to a moving train.
4. **Each Depot has three player-set lines on its stock**: an energy ceiling where its Generators stop, an energy floor kept for trains, and a coal floor kept for vehicles.
5. **A Depot builds inside its yard by itself.** Outside the yard a site is built by Infantry from what a truck sets down on it, iron and energy both, and needs no Depot in range.
6. **Depots stand at least 70 m apart**, so service ranges never overlap. Each still costs 20 E / 20 I and still comes with a free Infantry. That keeps the push to expand and ends the trick of farming Infantry from Depots packed round the first one.
7. **Trucks are flexible and burn coal. Trains are fast, carry three times as much and run on energy**, but need 2 iron of track for every metre.

**The ten changes that matter most, in order**

| # | Change | Why (evidence) |
| --- | --- | --- |
| 1 | Depots at least 70 m from any other friendly Depot. Price and free Infantry unchanged. | Today three extra Depots beside the mine give 4 Infantry at 1:20 for 60 E / 60 I. A Barracks gives its first Infantry at 6:48 for 200 E / 65 I. (A.3) |
| 2 | New vehicles start with an empty tank (switch off), and the first Depot starts with 60 coal. | With the switch off and no coal, the first Depot truck is built at 1:11 and can never move. (A.4) |
| 3 | Generator price 0 E / 40 I (was 100 E / 20 I). Coal burns 1 for 30 E over 3 s (was 50 E over 5 s). Generators stop at their Depot's energy ceiling. | Energy can only come from a Generator, so its price must not need energy. At 50 E a coal, one Tank's fuel is worth 20 Tanks' energy. Unchecked, one Generator filled the Depot's shared 2,000 storage by 10:30. (A.6) |
| 4 | A 17.5 m yard where the Depot builds without a truck or Infantry. | Building takes 5 to 7 player actions and two unit types today, and the lone starting Infantry is also the only miner. (D) |
| 5 | Outside a Depot's range a site takes its energy from crates on its footprint, as it does iron. | Today a site's energy needs a covering stockpile, and a single truck cannot provide one, so the only way to found a distant base is the Depot truck. (D.2) |
| 6 | Cut truck fuel to 0.05 coal a metre (was 0.10) and Tank fuel to 0.15 (was 0.20). | A truck burned 22.3 of its 30 coal on one empty round trip to the nearest expansion. A Tank cannot reach the enemy start, 319 m away, on one tank. (A.2) |
| 7 | Print times of 10 to 60 s (all are 3 s today), set so one production building running flat out uses about one wood Generator. | Two Infantry left the Barracks 3 s apart. Production is never a limit, so nothing teaches the player to size their energy. (B.2) |
| 8 | A rail reserve on each Depot, set by the player. Track may be laid outside Depot range and is paid by a Depot the line connects to. | Trains draw energy from connected Depots already. Without a reserve, production can spend a line to a standstill. With change 1, Depots are too far apart for track to stay inside their ranges. (C.4) |
| 9 | Starting stock 200 E / 60 I / 40 W / 60 C (was 500 E and nothing else). No Barracks at the start. | It lets the first decision happen at 0:00 instead of after 40 s of walking, and makes the Generator the first build. (E) |
| 10 | Four small fixes to how workers and trucks behave: trucks unload loose cargo at Depots, workers use the nearest drop-off unless told, coal diggers cut their own way in, builders step off the footprint. | Each one stalled a simulated opening. (A.6, G) |

## 2. Measured and estimated

### Measured

Measured in the game by `tests/investigation/economy_opening_sim.gd` (appendix), on the balanced map, at a fixed step of 1/30 s, with `FuelRules.testing_full_tanks` off unless stated. The units follow the same orders a player gives. The script never pauses to think, so every time is a best case.

| What | Result |
| --- | --- |
| Iron, one Infantry, starter mine to the first Depot | first load at 0:19, then 18.2 s a load: **33.0 iron a minute** |
| Wood, one Infantry, nearest trees to the first Depot | 29.3 s a load: **20.5 wood a minute** |
| Iron, with a Depot 11 m from the mine | **109.9 iron a minute** for each of 4 Infantry |
| Coal, one Infantry, safe expansion | 9 forest cells felled in 153 s (17.1 s a cell, 180 wood), then **32.4 coal a minute** |
| Cargo truck, first Depot to the safe expansion, empty | 27.9 s and 11.1 coal one way; 56.9 s and 22.3 coal there and back |
| The same truck's next trip | out of fuel after 19.3 s |
| 100 coal fetched from the expansion to the first Depot | 54 s; the truck refuelled at both ends and burned about 22 coal |
| Depot truck | ordered at 0:55, built at 1:11, second Depot standing with its Infantry at 1:49 |
| Truck fetch for a site inside Depot range | materials on site 5 to 17 s after the plan |
| A building, plan to finished, near the Depot | 26 to 58 s (truck fetch, then an Infantry walks over and builds); the Generator took 27 s |
| One woodcutter feeding one Generator | about 200 E a minute |
| Two woodcutters feeding one Generator | 300 E a minute, the Generator's limit; Depot storage full at 10:30 |

Distances are from `docs/BALANCED_MAP.md`, measured by `tests/balanced_map_test.gd` as the shortest ground path:

| Path | Metres |
| --- | --- |
| Start to starter mine | 18.6 |
| Start to safe expansion site | 120.8 |
| Start to exposed expansion site | 115.3 |
| Start to start by the centre lane | 319 |
| Start to the forest round the nearest coal (forward field) | 103.4, with 9 cells to fell |
| Safe expansion site to its coal's forest | 12.8 |

Prices, capacities and rates marked "now" in this report are read from `assets/economy/*.tres`, `assets/buildings/*.tres`, `assets/units/*.tres` and the scripts' defaults.

### Estimated

Everything else is estimated. In particular:

- every figure for the proposed design, including the proposed opening in A.7;
- everything about trains (none was simulated): times use 8 m/s and 2 s per transfer, energy uses 0.15 E a metre;
- the truck used as a collection point beside a mine (the game has no order to unload it yet);
- combat arithmetic in B.2, which uses health and damage figures only.

## A. A standard opening

### A.1 The start today

- First Depot: 500 E, nothing else. Storage 2,000 units, all resources together.
- One Infantry (2 m/s, carries 10, takes 5 per 1.2 s).
- One Cargo truck with a full tank of 30 coal (4 m/s, 4 crates).
- A starter Iron Mine 18.6 m away, on a field of 42 iron cells (10,500 iron). The mine itself reaches 1,000.
- A small wood beside the Depot. No coal inside the main base.
- Nearest coal: 103 m away behind 9 cells of forest, or at the safe expansion 121 m away.

### A.2 What one worker and one truck are worth

- **A worker is worth about 20 to 33 units a minute on foot.** The difference between resources is only walking distance.
- **Standing next to a stockpile is worth 3.3 times as much.** With a Depot 11 m from the mine each Infantry delivered 110 iron a minute.
- **One Generator needs about 1.5 woodcutters.** It burns 30 wood a minute for 300 E a minute. One woodcutter brings 20.5.
- **A truck's tank is one round trip.** 22.3 of 30 coal went on a single empty return trip to the nearest expansion.
- **A Tank's tank does not cross the map.** 60 coal at 0.20 a metre is 300 m. The enemy start is 319 m away.

### A.3 The opening today's rules reward

Testing switches off. This is what a competent player would settle on, because the cheapest thing in the game is a Depot: 20 E / 20 I, built in 4.8 s, bringing a free Infantry worth 100 E / 20 I. Nothing limits where it goes, so it goes beside the mine, inside the first Depot's range so that Depot pays the 20 E.

Simulated (`--opening=cheap`):

| Time | Step | Notes |
| --- | --- | --- |
| 0:00 | Infantry to the mine. Depot plan placed 11 m from the mine, 21 m from the first Depot. | The Infantry carries its loads straight to the site. |
| 0:19 | **Depot 2 built. 2 Infantry.** | Two loads of iron, four work cycles. |
| 0:34 | **Depot 3 built. 3 Infantry.** | The new Infantry builds the next one. |
| 1:20 | **Depot 4 built. 4 Infantry.** | First Depot has 440 E left. Total spent: 60 E / 60 I. |
| 1:20 to 2:30 | All four mine. | 440 iron a minute between them. |
| 2:48 | Generator site supplied by the truck. | The iron is in Depots 2 to 4, so the truck fetches it. |
| 3:08 | **Generator built** at the first Depot. | Two Infantry go to cut wood for it. |
| 3:08 on | The truck shuttles iron, 4 crates a trip, to the first Depot. | The energy is there, so production must be paid there. |
| 3:49 | **Barracks built.** | |
| 3:52, 3:55 | Two Infantry from the Barracks. **6 Infantry.** | 3 s apart: print time is 3 s. |
| 5:08 | **Tank Factory built.** | |
| 5:11 | **First Tank. It has no coal and cannot move.** | |
| 5:30 | Starter truck down to 15 coal of 30. | Nothing can refill it. |
| 10:30 | First Depot full: 1,710 E, 230 I, 60 W. Generator paused. | Nothing left to spend on without coal. |

By 5:11 the player has built everything the game offers and is stuck behind coal. The nearest coal is 103 m away on foot, and the only fuelled vehicle is running down.

### A.4 The opening the map was drawn for

`docs/BALANCED_MAP.md` describes a different opening: Depot truck to the safe expansion, then build up at home. Simulated both ways (`--opening=doc`):

| Step | As shipped (`testing_full_tanks` on) | Switch off |
| --- | --- | --- |
| Depot truck ordered (30 iron) | 0:55 | 0:55 |
| Depot truck built | 1:11, 30 coal aboard | 1:11, **0 coal: it never moves** |
| Second Depot and its Infantry | 1:49 | never |
| Generator built at home | 2:00 | 2:00 |
| 40 wood delivered to it | 3:57 | 3:57 |
| Coal corridor open (9 cells) | 4:22 | never |
| First coal at the expansion | 4:38 | never |
| Digging stops: next cell out of reach | 5:42, after 50 coal | |
| Barracks built | 6:03 | 6:03 |
| First Barracks Infantry | 6:48 | 6:48 (2 Infantry in all) |
| 150 coal at the expansion | 8:57 | never |
| Tank Factory built | 9:12 | 9:12 |
| 100 coal trucked home | 9:51 | never |
| First Tank | 10:37, full tank | no coal to run it |

Two things stand out:

- With the switch off, this opening does not work at all. The Depot truck is the only way to found a distant Depot (see D.2), and it cannot move without coal that is only found at distant Depots.
- With the switch on, coal plays no part in the first ten minutes. Every vehicle arrives full.

The simulated times run later than the map document's arithmetic (first Tank at 4:23 as shipped, 5:49 with the switch off). The document assumed the Infantry never stops mining. In play the same Infantry must also build each building and cut the Generator's wood.

### A.5 What the testing switches change

| Switch | Where | State on the balanced map | What it changes |
| --- | --- | --- | --- |
| `FuelRules.testing_full_tanks` | `scripts/units/fuel_rules.gd` | **on** | New vehicles arrive with a full tank. Coal stops mattering until the first refill: a free 30 coal with every truck and 60 with every Tank. Off, every vehicle built before coal reaches its Depot is stuck where it was built. |
| `testing_starting_iron = 500` | `assets/economy/depot_rules.tres` | off here (`testing_iron_grant = false`), on in every other scene | Every Depot, including every new one, starts with 500 iron. On, iron stops being a limit and each new Depot is a gift of 500. |
| `testing_coal_amount` | skirmish scene | 0 here; 200 on the original map | A pile of 200 coal beside the first Depot. That is 6 truck tanks or 3 Tank tanks, or 10,000 E through a Generator at today's rate. |
| `playtest_tools` | skirmish scene | on (F10, debug builds) | A panel that grants stock and finishes buildings for free. Not used in any figure here. |
| Drone `consumes_fuel = false` | `assets/economy/fuel_drone.tres` | off | Drones fly for free until landing rules exist. |

### A.6 What the opening shows

**1. Workers are the economy, and they are scarce.** The game starts with one Infantry, and each further one costs 100 E / 20 I at a Barracks that itself costs 100 E / 45 I. One Infantry earns that 65 iron in two minutes.

**2. The Depot is the cheapest worker by a factor of five.** 20 E / 20 I against 100 E / 20 I, with no Barracks needed. Because Depots may stand anywhere, the player packs them round the mine. This is the single largest distortion: it makes the Barracks pointless for Infantry and removes walking distance from mining.

**3. Energy is cheap once a Generator runs, and nothing stops it piling up.** 10 wood is 100 E. A Tank's 150 E is 44 s of one woodcutter. Energy and materials share the Depot's 2,000 storage, so an unattended Generator fills it and then blocks deliveries.

**4. Iron is the real price of things, and distance is the real price of iron.** At 33 iron a minute, the 130 iron for a Depot truck, Tank Factory and Tank is four minutes of the only worker.

**5. Coal is a wall, not a slope.** With the switch on it does nothing early. With it off, the base is sealed: no coal at home, vehicles built empty, and the only vehicle that could found a base near coal is one of them.

**6. Coal at 50 E a unit outweighs everything.** One coal digger (32 a minute) could feed 2.7 Generators and make 1,620 E a minute, eight times a woodcutter. A Tank's 60 coal would make 3,000 E, the energy price of 20 Tanks.

**7. Local stock sets traps the player cannot see.** Each of these stalled a run of the simulation. The script now works round the first and third, as a player would have to (appendix).

- Wood went to the wrong Depot. A worker keeps the last drop-off it used, so Infantry moved from mining to woodcutting carried wood past the Generator's Depot to the ones by the mine. After 12 minutes the Generator had sat "Waiting for wood fuel" throughout, with 190 wood in two other Depots.
- Energy was in the first Depot and iron in the others, so nothing could be produced until a truck moved one to the other.
- A builder told to build while standing on the footprint waited for good on "Waiting for footprint to clear": it was the thing in the way.
- The 9-cell corridor to coal reaches one coal cell, 50 coal. The worker digs it from 4 m away, across trees. The next cell is then "Coal unreachable" and the worker stops without a word.

**8. Production is instant.** Every unit prints in 3 s. A building takes 5 to 16 s of one Infantry's work.

### A.7 The opening expected under the proposal

Estimated from the measured rates, with the starting stock from section E (200 E / 60 I / 40 W / 60 C) and the prices from section B. Not simulated and not played.

| Time | Step | Stock at the first Depot after it |
| --- | --- | --- |
| 0:00 | **Generator** ordered in the yard (40 I). The Depot builds it. Infantry to the mine. | 200 E, 20 I |
| 0:15 | Generator running on the starting wood: 5 E/s until 1:35, 400 E in all. | |
| 0:19 | First iron load. **Depot truck** ordered (150 E / 30 I). | 70 E, 0 I |
| 0:34 | Depot truck built. It takes 30 of the 60 coal (6 s) and leaves. | 30 C |
| about 1:25 | **Second Depot** at the safe expansion, with 100 E and a free Infantry. That Infantry starts cutting into the coal. | |
| 1:35 | Starting wood gone. | about 450 E |
| 1:50 | 45 iron in. **Barracks** ordered in the yard (30 s). | about 350 E |
| 2:26 | 20 iron in. **Infantry** ordered (20 s). | about 250 E |
| 2:46 | Third Infantry, sent to cut wood. From about 3:20 the Generator runs again at about 200 E a minute. | |
| about 4:00 | Coal corridor open at the expansion; coal at about 32 a minute. | |
| about 4:15 | 65 iron in. **Tank Factory** ordered in the yard (45 s). | about 240 E |
| about 6:00 | **First Tank** (ordered at about 5:30 when 35 iron is in), with the 30 coal left at home: half a tank, 200 m. | about 330 E |
| about 7:20 | 100 coal at the expansion. The Cargo truck brings it home by about 8:20. | |
| 8:00 to 12:00 | The natural next step: track to the expansion (about 260 iron) and a Train (150 E / 30 I). | |

What changes in feel:

- The first decision is at 0:00, not 0:40.
- The Generator is the first build, and the starting 200 E is deliberately less than the Depot truck and Barracks together (250 E). The player must make energy to make progress.
- The second Infantry arrives at about 1:25 and it is at the expansion, as intended.
- Coal matters from the first Tank. Half a tank is enough to defend with and not enough to attack with.
- If the Cargo truck is parked at the mine as a collection point (D.5), iron rises from 33 to about 80 a minute and the Tank Factory comes about a minute sooner.

## B. Prices

### B.1 The rules of thumb behind the numbers

- **Keep the original prices.** The energy and iron prices of units and of the Barracks, Tank Factory and Depot come from the original design notes. They hold up: 100 E is about 30 s of one woodcutter and 20 I is about 36 s of one miner, so the two halves of a price cost similar work. The proposal changes almost none of them. It changes times, fuel and the rules round them.
- **Coal is never in a price.** That is the confirmed rule: coal runs vehicles, it does not build them. A new vehicle's first fill is shown beside its price because the player must have it.
- **Wood is never in a price.** Wood is fuel only. Charging wood for buildings would add a third material to every site, against the aim of section D.
- **Print time is about one second per 5 E.** One production building working without pause then draws about one wood Generator (5 E/s) and about 1 iron a second (two miners on foot). That gives the player a rule to plan by: one building, one Generator, three or four workers.
- **Build time is in seconds of work.** The Depot supplies one second of work a second in its yard. Each Infantry on a site supplies one.

### B.2 Units

Prices as E / I. No unit costs wood or coal. Print times now are all 3 s (Depot truck 14.2 s, the length of its animation).

| Unit | Made at | Price now | Price proposed | Print time proposed | First fill of coal |
| --- | --- | --- | --- | --- | --- |
| Infantry | Barracks | 100 / 20 | 100 / 20 | 20 s | none |
| Scout | Barracks | 35 / 5 | 35 / 5 | 10 s | none |
| Grenadier | Barracks | 85 / 15 | 85 / 15 | 20 s | none |
| Tank | Tank Factory | 150 / 35 | 150 / 35 | 35 s | 60 |
| Motorcycle | Tank Factory | 45 / 10 | 45 / 10 | 12 s | 20 |
| Drone | Tank Factory | 60 / 5 | 60 / 5 | 15 s | none yet |
| Übermech | Tank Factory | 250 / 60 | 250 / 60 | 60 s | 60 |
| Cargo truck | Depot | 100 / 20 | 100 / 20 | 20 s | 30 |
| Depot truck | Depot | 150 / 30, carries 100 E | 150 / 30, carries 100 E | 15 s | 30 |
| Train | Depot | 150 / 30 | 150 / 30 | 30 s | none: energy only |
| Free Infantry | each new Depot | free | free | with the Depot | none |

Infantry against the user's goal (strong one on one, expensive for its power), from the stat files:

- Infantry has 55 health and does 8 damage a second. It beats a Scout (40 health, 4 a second) and, narrowly, a Motorcycle (45 health, 16 every 2 s). It loses narrowly to a Grenadier and clearly to a Tank.
- For one Infantry's 100 E / 20 I the player can have three Scouts (105 E / 15 I): 120 health and 12 damage a second between them.
- So the goal already holds at the original prices. Infantry is the unit that works, builds and captures; that is what its price buys. No change.

### B.3 Buildings

Prices as E / I. Build time now is 1.2 s for every 5 iron, by one Infantry.

| Building | Price now | Build now | Price proposed | Work proposed | Kit (crates) |
| --- | --- | --- | --- | --- | --- |
| Depot | 20 / 20 | 4.8 s | 20 / 20, at least 70 m from a friendly Depot | 20 s | 2 |
| Generator | 100 / 20 | 4.8 s | **0 / 40** | 15 s | 2 |
| Iron Mine | 75 / 25 | 6.0 s | 75 / 25 | 15 s | 4 |
| Barracks | 100 / 45 | 10.8 s | 100 / 45 | 30 s | 6 |
| Tank Factory | 200 / 65 | 15.6 s | 200 / 65 | 45 s | 11 |

- **Depot.** The price stays at the original 20 / 20 because the user wants it to be the cheap way to the second Infantry. The spacing rule is what stops it being farmed (G.1).
- **Generator.** Energy only comes from Generators, so a Generator that costs energy can lock a player out for good. At 0 E a player with iron and trees can always restart. Two crates also means one truck can carry a Generator kit and two crates of fuel to a new base.
- **Tank Factory.** Its kit is 11 crates: three truck trips, or one Train (12 crates). Big buildings belong in a yard, or at the end of a rail line.

### B.4 Track, crates and abilities

| Item | Now | Proposed |
| --- | --- | --- |
| Straight track (4.8 m) | 10 I | 10 I |
| Curve (18.85 m) | 38 I | 38 I |
| Fork | 67 I | 67 I |
| Track, any piece | 0 E; inside the paying Depot's range | 0 E; anywhere on open land, paid by the nearest Depot the line connects to that has the iron |
| Crate | free, 25 units | free, 25 units |
| Make crates, Load, Unload | free; 2 s a transfer | the same |
| Deploy or pack supplies | free, 2 s each | the same |
| Repair | 10 health a second for 2 E + 1 I | the same |
| Capture a Depot | free, 8 s inside 12 m | the same |
| Refuel | free, 5 coal a second | the same |
| Tank clearing forest | free, wood lost | the same |
| Motorcycle derail and jam, Übermech death effect | not defined | no price until the rules exist |

Track stays at 2 iron a metre. A line from the first Depot to the safe expansion is about 26 straights, 260 iron: eight minutes of one miner on foot. That is a real mid-game decision, which is right for the thing that solves bulk hauling.

### B.5 Gathering

| Setting | Now | Proposed |
| --- | --- | --- |
| Infantry carry | 10 | 10 |
| Infantry harvest | 5 per 1.2 s | 5 per 1.2 s (it matches the saw animation) |
| Wood in a forest cell | 20 | 20 |
| Iron in an ore cell | 250 | 250 |
| Coal in a coal cell | 50 (fields of 1,000 and 2,000) | 50 |
| Worker's drop-off | the last one it used | the nearest that will take the load, unless the player picks one |
| Coal digging | stops when the next cell is behind trees | the worker fells what is in its way and carries on |
| Iron a minute, one Infantry on foot at the start | 33 (measured) | 33 |
| Iron a minute, Infantry at a mine with a Depot beside it | 110 (measured) | not possible in the main: Depots are 70 m apart |
| Iron a minute, Infantry loading a truck parked at the mine | not possible: no order unloads it | about 80 (estimated), for about 1.6 coal per 100 iron |

The rates stay. What changes is which shortcuts exist: the free one (a Depot on the mine) goes, and the paid one (a truck and its coal) starts working.

### B.6 Generators

| Setting | Now | Proposed |
| --- | --- | --- |
| Wood | 1 wood gives 10 E over 2 s (5 E/s) | the same |
| Coal | 1 coal gives 50 E over 5 s (10 E/s) | **1 coal gives 30 E over 3 s (10 E/s)** |
| Default fuel | wood | wood |
| Stops when | the Depot's 2,000 storage is full | the Depot's energy reaches its **energy ceiling** (default 600 E) |
| Burns coal down to | zero | the Depot's **fuel reserve** (default 60 coal) |
| Wired to | an assigned Depot covering it | the one Depot whose range it stands in |

- Wood is right as it is: one woodcutter is two thirds of a Generator, and a Generator is one production building.
- Coal at 30 E is still three times wood per unit and twice the output per Generator, so it is still "much more efficient", as the confirmed design asks. One digger then makes about 970 E a minute instead of 1,620, and a Tank's 60 coal is worth 1,800 E instead of 3,000. A side field of 1,000 coal is 30,000 E, or 16 Tank fills.

### B.7 Vehicle fuel and train energy

| Vehicle | Tank (coal) | Burn now (coal/m) | Range now | Burn proposed | Range proposed |
| --- | --- | --- | --- | --- | --- |
| Cargo truck, Depot truck | 30 | 0.10 | 300 m | **0.05** | 600 m |
| Tank | 60 | 0.20 | 300 m | **0.15** | 400 m |
| Motorcycle | 20 | 0.05 | 400 m | 0.05 | 400 m |
| Übermech | 60 | 0.20 | 300 m | **0.15** | 400 m |
| Drone | 30 | not used | | not used until landing rules exist | |
| Train | none | 0.15 E/m | | 0.15 E/m | |

- **Trucks.** A return trip to the nearest expansion drops from 22 coal to 11, so a tank lasts two and a half trips and hauling 100 coal home costs 11 of it.
- **Tanks.** 400 m reaches the enemy start by the centre lane (319 m) with fuel to fight, and does not get home. An attack needs fuel brought forward, which is the game. At 300 m today a Tank stops 19 m short.
- **New vehicles start empty** and fill from their Depot at 5 coal a second. This is the rule already approved in `docs/FUEL_BATCH.md`; it only needs the switch off and coal in the starting stock.

Trains against trucks on the first Depot to safe expansion link (121 m), estimated:

| | Truck now | Truck proposed | Train |
| --- | --- | --- | --- |
| Carries | 100 | 100 | 300 |
| Round trip with transfers | about 61 s | about 61 s | about 34 s |
| Units a minute | about 98 | about 98 | about 530 |
| Cost of the trip | 22 coal | 11 coal | 36 E |
| Cost per 100 units, as energy | 1,100 E at 50 E a coal | 330 E at 30 E a coal | 12 E |
| Set-up | 100 E / 20 I | 100 E / 20 I | 150 E / 30 I and about 260 I of track |

A train moves five times as much for a small fraction of the running cost. Its price is the track and the fact that the track can be cut. That matches the three advantages the user named: more cargo, faster, energy instead of fuel.

### B.8 Storage

| Store | Now | Proposed |
| --- | --- | --- |
| Depot | 2,000 units, all resources together | 2,000, the same |
| Depot energy ceiling | none | player-set, default 600 E |
| Depot rail reserve (energy floor) | none | player-set, default 0; 100 E suggested when a line first reaches the Depot |
| Depot fuel reserve (coal floor) | none | player-set, default 60 coal |
| Cargo truck | 100 units, 4 crates | the same |
| Train | 300 units, 12 crates | the same |
| Crate | 25 units of one resource | the same |
| Infantry | 10 | the same |
| Generator, Barracks, Tank Factory | no store; they use their Depot's | the same |
| Depot truck | no cargo; its Depot starts with 100 E | the same |

The combined 2,000 is a confirmed decision and stays. The energy ceiling is what keeps energy from crowding out materials.

## C. Energy storage and transfer

### C.1 The three models

| | 1. Generators store energy in a Depot | 2. Generators must be built next to a Depot | 3. Generators hold energy and connect to users |
| --- | --- | --- | --- |
| What it is | Today's rule: a Generator inside a Depot's range burns that Depot's fuel and fills that Depot. | Model 1 with a tighter placement rule. | The Generator is its own stockpile. Sites and buildings link to it by line, rail, touch, radius or hauling. |
| Local? | Yes. Every unit of energy is in a named Depot. | Yes. | Yes, but there are now two kinds of stockpile. |
| New rules for the player | None. | One: where a Generator may stand. | Many: what a link is, how far it reaches, what happens when two overlap or one is cut. |
| New interface | None. | A placement check. | Link drawing, link status, a Generator stock panel. |
| What the enemy can do | Capture or kill the Depot, or kill the Generator. | The same, in one place. | Also cut links. |
| Trouble | Overlapping Depot ranges make "which Depot" a question. | The ground round a Depot is already wanted by the truck bay, unit exits and the track loading area inside 8.5 m. | Hauling energy from a Generator makes it a small Depot. A radius makes it a second range to learn. Lines are a new system as large as rail. |

### C.2 Recommendation: model 1, made unambiguous

**Generators store energy in the one Depot whose service range they stand in.**

- A Generator may be built anywhere inside a Depot's 35 m service range. With Depots 70 m apart there is exactly one such Depot, so there is nothing to assign and nothing to get wrong. "Assign Depot" stays only for the rare case of a Generator whose Depot was lost and replaced.
- Model 2 is not needed as a rule. The yard (section D) already makes "next to the Depot" the easy place: a Generator placed there needs no truck and no Infantry. A player who wants it beside the trees at 30 m can pay for that with a truck trip.
- Model 3 is rejected. It answers a question the game does not have. The Depot is already the place where energy is held and spent, and rail is already the game's line-drawing system.

Energy is held in Depots and nowhere else, except in crates.

### C.3 How energy reaches what spends it

| Spender | How it is paid | Change from today |
| --- | --- | --- |
| Barracks, Tank Factory, Depot production | By wire from the building's Depot, inside 35 m. | None. |
| A site in a Depot's yard (17.5 m) | By wire. The Depot also supplies the iron and the work. | New. |
| A site in a Depot's service range (35 m) | Energy by wire, in step with the work. Iron by truck. Work by Infantry. | None. |
| A site outside every range | From energy crates on its footprint, in step with the work. | **New.** Today it cannot be paid at all without a covering stockpile. |
| Repair | From the nearest covering stockpile. | None. |
| A moving train | Through the rail from the nearest connected Depot that has energy. | None, plus the reserve below. |

**Energy can be carried as cargo.** It already can: a Depot makes 25 E crates and trucks and trains carry them. This stays, because it is the only way to pay for a site out of range, and it is the only way to give a new Depot energy before its own Generator runs.

It is deliberately the poor way to move energy in bulk. A crate of coal is 750 E at the far end, once burned; a crate of energy is 25 E. So the natural way to power a forward base is the physical one: carry a Generator kit (2 crates) and fuel, and make the energy there. No rule is needed to force this. The numbers do it.

### C.4 Trains

Keep how trains draw energy today: 0.15 E for each metre, taken from the nearest Depot connected to the train's line that has energy. If none has any, the train holds its place and its cargo as "No power" and carries on when energy returns.

Add the **rail reserve**:

- Each Depot has a rail reserve, an amount of energy set by the player on the Depot's energy bar, from 0 up to its energy ceiling.
- Production, construction, repair and loading energy crates cannot take a Depot's energy below its rail reserve. Only trains can.
- That is the whole of "trains get priority". There is no queue and no other rule. Energy arriving in a Depot below its reserve is the trains' because nothing else may touch it.
- Default 0. When track first reaches a Depot's loading area the game suggests 100 E, about three round trips to an expansion.

What it is for: one moving train uses 1.2 E a second, a quarter of a wood Generator. Without a reserve, a player who queues units until the Depot is empty stops the trains that bring the iron for those units.

**Track outside Depot range.** Today every tile under a piece must be inside the paying Depot's range. With Depots 70 m apart and ranges of 35 m, that would allow no line between any two Depots. Proposed: the first piece must start in a Depot's loading range, as now; every later piece joins existing track, as now; and the piece is paid by the nearest Depot that line connects to and that has the iron. The track is itself the physical link to the Depot that pays for it.

### C.5 How this stays local

- Every unit of energy is in one Depot, one crate or one vehicle's hold.
- Every spender has exactly one source at a time, and never a second to fall back on.
- Two Depots never share energy. A rail line joining them does not join their stock. Only a train's own traction is drawn through the rail.

**The one bend.** A train's energy is spent at a distance from the Depot it comes from, without being carried. This is already how the game works. It is justified because the rail is a physical connection the player built, pays for by the metre, and can lose: cut the line, or take the Depot, and the trains stop.

## D. Building

### D.1 Every path today

An action is one key press or one click. Waits are from the simulation where measured.

| Path | Actions | Count | Waits | Needs |
| --- | --- | --- | --- | --- |
| **A. Plan, truck, builder** (the usual one) | B, building key, click the ground. Select the truck, right-click the plan. Select an Infantry, right-click the plan. | 7 (5 if truck and Infantry are box-selected together) | Truck fetch 5 to 17 s. Walk. Build 4.8 to 15.6 s. Measured 26 to 58 s in all near the Depot. | A truck, an Infantry, a covering stockpile for the energy. |
| **B. Worksite** | Select the truck, W, building key, click the ground. Select an Infantry, right-click the plan. | 6 | The same. | The same. |
| **C. By hand** | B, key, click. Select an Infantry. Then for every 10 iron: right-click the mine, right-click the plan. | 4 + 2 per load: 8 for a Depot, 14 for a Barracks | 19 s for a Depot beside the mine (measured). | An Infantry, a covering stockpile. |
| **D. Crates by hand** | Select the Depot, K, a resource key per crate. Select the truck, L, click. U, click the plan. Then the builder. | 10 or more | Two 2 s transfers and the drive. | A truck, an Infantry, a covering stockpile. |
| **E. Over materials already there** | B, key, click on the pile. Select an Infantry, right-click. | 5 | Build time only. | A pile in the right place. |
| **F. Depot truck** (Depots only) | Select the Depot, Depot truck. Select the truck, Deploy, click the site. | 5 | 14.2 s to build, the drive (38 s to the safe expansion), then it unfolds. | 150 E / 30 I. No Infantry. Coal, with the switch off. |
| **G. Track** | B, Rail, R to choose the piece, then one click a piece. | 2 + 1 a piece: about 28 for the line to the safe expansion | None: paid at once by the Depot. | Every tile inside a Depot's range. |

Afterwards, a Generator or production building whose energy was paid by a vehicle has no Depot and needs two more actions (Assign Depot, click).

### D.2 What is wrong with it

- **The first Infantry is the miner and the builder.** Every building takes it off the mine for half a minute or so. That is part of why the as-drawn opening reaches its Barracks at 6:03.
- **Three things must come together** for one building: a plan, a truck with the iron, an Infantry. Miss one and the site waits, in amber, without saying which.
- **A site's energy needs a Depot or a deployed truck in range, and a truck cannot really be one.** A deployed Cargo truck pays from its loose stock. Trucks load crates, and crates are not loose stock. Infantry cannot carry energy. So with one truck there is no way to put spendable energy aboard, and no site outside Depot range can be built. The Depot truck (path F) is the only way to found a distant base.
- **A builder can block its own site** (A.6).

### D.3 Recommended flow

One way to place a building, as now: **B, building key, click.** What happens next depends only on where it was placed, and the placement ghost says which before the click.

| Where the plan is | Who brings the materials | Who pays the energy | Who builds | Player actions |
| --- | --- | --- | --- | --- |
| **In a Depot's yard** (all four corners inside 17.5 m) | Nobody: the Depot's stock | The Depot | The Depot, one second of work a second | **3** |
| **In a Depot's service range** (inside 35 m) | A truck (Fetch) | The Depot, by wire, as now | Infantry | 5 |
| **Anywhere else** | A truck (Fetch), which now brings the energy crates too | The crates on the site | Infantry | 5 |

Supporting rules:

- **Fetch brings everything the site lacks**, in as many trips as it takes. It exists already and stops when the site is covered; it only needs to count energy for sites that have no Depot in range.
- **An Infantry may be told to build before the materials arrive.** It walks over and waits beside the site, never on it, and starts when they land. It does this already except for the standing place.
- **Box-select truck and Infantry, right-click the plan.** Each takes its own job. This also works already and should be the taught way.
- **Track**: click a start and an end to lay the whole straight run, with the total iron shown before the second click.

### D.4 The questions asked

**Must a site be inside Depot range if its materials can be supplied? No.** The range rule is only there because energy has had no way to travel to a site. Energy crates are that way, and they exist. A site with its iron and energy on its footprint and an Infantry beside it needs nothing from any Depot. This is what makes the rule "paid from a local source" complete: the site's own footprint is the source.

**Should a Depot have a short inner range where a build completes without Infantry? Yes: 17.5 m.**

- It is half the service range, the same fraction and the same number the game already uses for a deployed truck's supply range.
- It fits one ring of buildings touching the Depot: a Tank Factory (8 m) on a side, a Barracks (6 m) on another, Generators (3 m) between.
- It is a small bend of "resources move physically", over a distance shorter than a worker's drop-off walk. Production already bends it further: a Barracks 30 m from its Depot is paid with no hauling at all.
- It does not make trucks and builders idle. The second mine on the iron field, every expansion, every forward Generator and all track are outside the yard.
- It is worth most in the first two minutes, when there is one Infantry. That is the early-game case the user raised.

**How construction is paid and delivered under the energy model:** the table in D.3. In short: by wire inside a range, by crate outside it; iron by the Depot inside the yard, by truck outside it.

### D.5 Trucks as collection points

Not a building path, but the same family of friction. A worker can already deliver into a deployed truck parked beside a mine or a coal face. Nothing can then unload that truck at a Depot, because Unload only handles crates. Two changes:

- Unload at a Depot also empties loose cargo.
- A **Collect** order: the truck deploys where it is told, and when full drives to the chosen Depot, unloads, returns and deploys again.

This is the honest replacement for the Depot-on-the-mine trick: the same gain, paid for with a truck and its coal.

## E. Starting conditions

### E.1 Recommendation

| | Now | Proposed |
| --- | --- | --- |
| Depot stock | 500 E | **200 E, 60 I, 40 W, 60 C** |
| Units | 1 Infantry, 1 Cargo truck with a full tank | the same |
| Buildings | Depot, starter Iron Mine | the same; no Barracks, no Generator |

Why each number:

- **60 iron**: the Generator (40) at 0:00, and 20 towards the Depot truck (30) or a Depot kit (20). The player decides something in the first second.
- **40 wood**: 80 s of Generator output, 400 E. It shows fuel turning into energy at once, and it runs out at about 1:35, before the player can afford to ignore it.
- **200 energy**: less than the Depot truck and the Barracks together (250). The starting energy alone cannot carry the opening; the Generator has to. With the wood it comes to 600 E of budget in the first two minutes.
- **60 coal**: one fill for the Depot truck (30) and half a tank for the first Tank. It is stock, not a source: there is still no coal in the main base to gather.

### E.2 How soon the first Generator should come

**At once: ordered at 0:00, running by 0:15.** Three reasons:

- It is the rule the whole economy hangs on, so it should be the first thing the player does, not something found when the energy runs out at minute four.
- At 0 E it competes with nothing for energy, so building it first is never a mistake.
- It starts the clock on the wood. The single Infantry cannot both mine and cut. That squeeze is what makes the second Infantry urgent, and the second Infantry comes from a Depot. This is the push the user asked to keep.

### E.3 Starting with a Barracks already built

Not recommended.

- **It works against the Depot push.** With a Barracks standing, the nearest second Infantry is 100 E / 20 I at home, 20 s after the first two loads of iron. The player is no longer pushed out to a second Depot to get it.
- **It spends the opening for the player.** The Barracks is 100 E / 45 I, the largest early purchase. Giving it away removes the choice between Barracks first and expansion first.
- **It brings fighting forward.** Scouts at 35 E / 5 I from 0:00 can reach the enemy start (319 m at 4 m/s) by about 1:40, before either side has a second worker.

If a faster start is wanted, the better gift is iron, as proposed: it speeds up the first decision without making it.

## F. Interface

Each item names the problem it solves.

| # | Suggestion | Problem it solves |
| --- | --- | --- |
| 1 | **Clickable load types.** While a Cargo vehicle's Load command is armed, the rows of the Depot's stock (energy, iron, wood, coal), on its panel and on its hover card, become buttons. A click adds one crate of that type to the manifest; Shift-click fills the remaining slots. Types the Depot has less than a crate of are dimmed. (Requested by the user.) | Loading needs the player to know four letter keys and to guess what the Depot holds. |
| 2 | **Three markers on the Depot's bars.** On the energy bar: a floor (rail reserve) and a ceiling (Generators stop). On the coal bar: a floor (fuel reserve). Drag to set. | Trains starved by production; coal burned that the vehicles needed; energy filling the store. |
| 3 | **Flow on the Depot panel.** For each resource: in and out per minute and the time until it runs out or fills. For example "Energy +300 −260 a minute · wood gone in 0:40". | The player cannot see a shortage coming, only its result. |
| 4 | **Shortage badges on the map.** A small icon over anything that is waiting: no wood, no coal, no iron, no energy, store full, exit blocked. | In the simulation a Generator waited for wood that sat two Depots away. Nothing on the map showed it. |
| 5 | **A worker's drop-off line.** Selecting an Infantry draws a line to where it will deliver. Right-clicking a stockpile pins it; the pin shows on the unit. | Wood carried to the wrong Depot. |
| 6 | **Yard and service rings while placing.** The ghost reads "Yard: the Depot builds it", "Needs iron by truck and an Infantry", or "Needs a kit: 2 crates, and an Infantry". | Three kinds of site that look the same until they stall. |
| 7 | **A site says what it lacks.** The plan's label reads "needs 45 iron and an Infantry", not only a colour. | An amber site does not say which of three things is missing. |
| 8 | **Idle worker count and key.** A header count of idle Infantry; a key cycles through them. | One idle Infantry is 33 iron a minute lost, and there are few of them. |
| 9 | **Trip fuel check for trucks.** When a truck is given a far stop: "needs 11 coal, has 8". Trains already warn. | A truck ran out of fuel 19 s into its second trip. |
| 10 | **Empty tank on new vehicles.** A badge, and the production tile shows the first fill ("Tank · 150 E / 35 I · fills 60 coal"). | A Tank that cannot move was built without warning. |
| 11 | **Collect** (D.5) and **dig through** (B.5) as orders. | Collection needs an unload that does not exist; coal digging stops after 50. |
| 12 | **Line laying for track** (D.3). | About 28 clicks for one line. |
| 13 | **Rail reserve prompt.** When track first reaches a Depot: "Keep 100 E for trains?" | A setting nobody finds until the trains stop. |

## G. Anything else

### G.1 Contradictions between the goals

**"A Depot's free Infantry is the push to expand" against "Infantry is expensive".** At 20 E / 20 I a Depot is an Infantry at a fifth of the price, with no limit on number or place. The measured result is four Infantry at 1:20. Three ways out:

- raise the Depot's price above an Infantry's: this removes the push, which the user wants kept;
- give the Infantry only to Depots that do not overlap another: this needs a second kind of Depot explained;
- **keep the price and the gift, and require 70 m between friendly Depots.** Recommended.

The goal bent is the freedom to put a Depot anywhere. Each Depot then has to be a real place, and the number a player can have is set by the ground they hold. There is a second gain: with no overlapping ranges, "which Depot pays" has one answer everywhere, and the pin and assign controls are needed only for deployed trucks.

**"Generators are the only source of energy" against a start with energy, and a Depot truck that unfolds with 100 E.** Neither is a source. The starting stock is spent once. The truck's 100 E was paid for in its 150 E price at the Depot that built it; it is a transfer. The rule to keep is that a Depot truck never carries more energy than it cost.

**"New vehicles start empty" against "no coal in the main base".** Together they seal the base (A.4). The goal bent is the empty main: 60 coal in the starting stock, with no coal to gather there.

**"Resources move physically" against "a build that needs no Infantry".** The yard bends the first for 17.5 m. Justified in D.4.

**"Coal fuels vehicles and Generators" against itself.** At 50 E a coal the Generator is so much the better use that fuel for vehicles is always the wrong choice in energy terms, and so much the richer source that wood stops mattering. 30 E narrows this. The fuel reserve stops Generators taking coal the vehicles need.

**"Trains get priority on energy" against local stock.** No conflict once the priority is a floor on each Depot's own energy (C.4).

**"All storage has one combined capacity" against Generators that never stop.** The combined capacity stays. The energy ceiling stops the flood.

### G.2 Things found on the way

- **A builder standing on a plan's footprint blocks it for good.** It should step off.
- **Loose cargo aboard a truck cannot be unloaded at a Depot.** Only crates can.
- **A deployed truck cannot hold spendable energy** in ordinary play (D.2).
- **Workers keep their last drop-off**, however far.
- **The coal corridor opens one cell.** `docs/BALANCED_MAP.md` gives 9 cells to clear for each side field. That reaches 50 coal. In the simulation one more cell, 10 in all, opened the next 100 coal. Working a whole field will take more, and how many was not measured.
- **Coal should stay directly dug, with no mine building.** Forest and distance already gate it; a coal mine would be one more kit to haul for no new decision. Dug-out cells should stay open ground, as now.

### G.3 Things not asked about

- **Nothing can be tested against pressure.** There is no opponent. Every figure here is for a player left alone. The design's real test is whether a raid on a truck route or a rail line hurts the right amount, and that cannot be judged yet.
- **Upkeep**, already wanted and deferred, is the natural long-game sink for energy. It should be designed after this pass, not with it.
- **Water generation** would be a Generator that needs no fuel and so no supply line. It works against the idea of the game. If it is added, keep it weak (the 2 E/s once proposed) and tied to the map.
- **Shared mines.** Either side may use any mine. With mines at 75 E / 25 I this invites building none and using the enemy's. Worth a look once there is an opponent.
- **The Depot truck and the Depot kit do the same job.** Both are worth keeping: the truck needs no Infantry and costs coal; the kit needs an Infantry and costs almost nothing. That is a fair choice in the first two minutes and the kit wins later.
- **The queue limit of 3** matters once print times are real. Leave it and watch.

## Risks and what must be played

Nothing here has been played. Each recommendation, what could be wrong with it, and what to look for:

| Recommendation | Risk | Play-test for |
| --- | --- | --- |
| Depots 70 m apart | The main base feels cramped with one store of 2,000. Sites on other maps may sit closer than 70 m. | Does the first Depot's storage fill? Do both expansions and the contested coal still take a Depot where wanted? |
| Start 200 E / 60 I / 40 W / 60 C | A new player spends the 200 E badly and waits. | Watch a first-time player's first three minutes. Is the wait short enough to read as a lesson? |
| Generator 0 E / 40 I | Generators become free to spam. | Does anyone build more than their woodcutters can feed? (That is self-limiting, but check.) |
| Coal 30 E over 3 s | Wood is still abandoned once coal flows. Or coal is no longer worth burning. | At minute 10, what are Generators burning, and was it a choice? |
| Energy ceiling, rail reserve, fuel reserve | Three settings is two too many. | Does a player ever move them without being told? If not, keep the defaults and hide the markers. |
| Yard of 17.5 m | The main base needs no truck and no builder, and base building loses its work. | Is the truck still busy before minute 3? Does the yard feel like a reward or a loophole? |
| Energy crates pay distant sites | A kit of 6 or 11 crates is tedious. | Does anyone build a Barracks out of range, and should they? |
| Truck 0.05 and Tank 0.15 coal a metre | Fuel stops mattering for trucks. Tanks reach too far. | Does a truck ever run dry by surprise? Can a Tank attack and return without a fuel stop? It should not. |
| Print times 10 to 60 s | The early game drags. | Time to the second, third and sixth Infantry. Is 20 s for an Infantry felt as a cost or as dead time? |
| Train energy 0.15 E/m with a reserve | Too cheap for the reserve to matter. | Does a line ever stop for want of energy? If never, raise it to 0.25. |
| Track outside ranges | Track everywhere, with no risk. | Is a long line ever cut, and does it hurt? Needs an opponent. |
| Build times in seconds of work | Sites feel slow with one builder. | Do players send two Infantry to a Tank Factory? |
| No Barracks at the start | The opening is slow to first combat. | Time of first contact with the midfield Hostiles. |
| Collect order | It makes mining with a truck the only way to mine. | Is on-foot mining ever still right? It should be, in the first minutes. |

The simulation's own limits:

- It issues orders with no delay, and to one small group of units. Real play is slower and has traffic.
- It places buildings at the nearest free spot. A player's placement will differ.
- Each opening is one scripted line of play, run once. It shows what the rules allow, not what is best.

## Suggested order of work

Separate small pull requests, each with its own headless checks and a play-test before merging. The first four change no balance and can go in any order.

| # | Pull request | Size |
| --- | --- | --- |
| 1 | Builders step off a footprint before building. | small |
| 2 | Workers deliver to the nearest stockpile unless one is pinned; show the drop-off line. | small |
| 3 | Unload at a Depot also empties loose cargo. | small |
| 4 | Coal diggers fell what is in their way and move on through the field. Re-measure the forest belts. | small |
| 5 | Fuel: switch `testing_full_tanks` off on the balanced map, starting stock of 200 E / 60 I / 40 W / 60 C, truck and Tank burn rates. | data, plus tests that assume full tanks |
| 6 | Depots at least 70 m apart (new construction and deployment only; authored scenes untouched). | small |
| 7 | Generators: 0 E / 40 I, coal 30 E over 3 s, the energy ceiling and the fuel reserve. | medium |
| 8 | Print times and build times in the stat files; the queue shows time left. | data, plus a build-time field |
| 9 | The yard: Depot-built plans inside 17.5 m, with the placement ghost saying so. | medium |
| 10 | Sites outside every range take energy from crates on the footprint; Fetch brings them. | medium |
| 11 | Rail: track outside ranges paid by a connected Depot, the rail reserve, line laying. | medium |
| 12 | Interface: clickable load types, flow on the Depot panel, shortage badges, idle workers, fuel checks. | several small ones |
| 13 | Collect order for trucks. | medium |

After 5, 6 and 7 the opening in A.7 can be played for the first time. That is the point to stop and judge before building the rest.

## Appendix: the simulation

`tests/investigation/economy_opening_sim.gd` is an investigation tool, not a test. It asserts nothing, the CI runner does not pick it up (it runs `tests/*_test.gd` only), and it changes no file. It loads `balanced_skirmish.tscn`, gives units the same orders a player's clicks give (`command_gather`, `command_construct`, Fetch, Load, Unload, Depot truck deployment, production requests), and prints the game time of each step.

Run it with a fixed time step so the result does not depend on the machine:

```bash
godot --headless --fixed-fps 30 --path . --script res://tests/investigation/economy_opening_sim.gd -- --opening=rates
```

| Argument | Meaning |
| --- | --- |
| `--opening=rates` | One Infantry: iron a minute, then wood a minute. |
| `--opening=truck` | The Cargo truck to the safe expansion and back. |
| `--opening=cheap` | The Depot chain of A.3, then Generator, Barracks, Tank Factory and Tank. |
| `--opening=doc` | The opening of A.4. |
| `--full-tanks=on` | Leave `testing_full_tanks` on, as shipped. Default off. |
| `--minutes=N` | Length of `doc` and `cheap`. Default 12. |
| `--depots=N` | Extra Depots in `cheap`. Default 3. |
| `--debug=on` | Print each unit's order every 30 s. |

The runs behind this report:

| Run | Arguments |
| --- | --- |
| Rates | `--opening=rates` |
| Truck | `--opening=truck` |
| A.3 | `--opening=cheap` |
| A.4, as shipped | `--opening=doc --full-tanks=on --minutes=14` |
| A.4, switch off | `--opening=doc --minutes=10` |

Each takes one to three minutes of real time. On Windows the Godot binary is `C:/Dev/Tools/Godot_v4.7.2-stable_win64_console.exe`; a fresh checkout needs `--headless --path . --import` once first.

Three places where the script does what a player would have to do to get past a stall (A.6):

- It moves a builder off a plan's footprint before giving the build order.
- It gives woodcutters the Depot to deliver to, as a right-click on that Depot does.
- When a coal digger reports "Coal unreachable" it fells the trees in the way and gives the dig order again.

Choices the script makes that a player might not:

- It places each building on the nearest free ground to the Depot (or, for the Depot chain, to the mine, at least 11 m from it).
- In `doc`, the first Infantry builds the Generator, cuts 40 wood, then mines for the Barracks. The Barracks Infantry cuts wood from then on.
- In `cheap`, two Infantry cut wood and are told to deliver it to the first Depot; the rest mine; the truck carries iron across four crates at a time.
- For coal it fells the fewest forest cells that reach any coal, taking the shortest such way, and fells again when the worker reports the next cell out of reach.
