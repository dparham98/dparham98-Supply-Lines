# Arthurian Knights

A second faction: Arthurian knights as space marines, played on the same maps and under the same local-stockpile rules as the Cyborgs, but with a different economy. **Nothing here is implemented.** This is the design record, written on 2026-11-23 from three analyses discussed in conversation (2026-11-22 and 23) and the user's handoff of 2026-11-23.

The sections keep four kinds of statement apart:

1. **Confirmed** — the user's design. Change it only when the user does.
2. **Repo baseline** — what the Cyborgs and the shared rules do today, read from the code at `6756632`. Use these numbers for balance work, not older docs.
3. **Provisional** — proposed rules and numbers to test. None has been played.
4. **Open** — decisions the user has not made yet. Each is marked **[OPEN]**.

## 1. Confirmed design

- **Theme:** Arthurian knights as space marines.
- **Local resources only.** Every Keep holds its own bounded stock. Nothing is pooled or shared between Keeps, as for Depots.
- **Food** pays for units in place of the Cyborgs' Energy. It comes from **Farms**, and in a later pass from **wild animals** that spawn on the map.
- **Wood** pays for construction and for **Houses**, which sustain supply.
- **Iron** (mines) and **Coal** (seams and mines) stay shared and contested by both factions.
- **Keep:** the faction's Depot. It is the drop-off, the local stockpile, and where **Workers** and **Warhounds** are trained, and it launches **Air Balloons**. Unlike a Depot, which grants one Deforester when it is established and refuses to train more (`Depot.request_infantry` in `scripts/gameplay/depot.gd`), a Keep trains Workers and Hounds again and again.
- **Air Balloons** carry crates from a Keep to a forward position, **one way**, ignoring water, mountains and forest.
- **Roads** are built, and speed up every friendly unit walking on them.
- **Trains:** both factions can run them, with similar capacity and speed. Knight trains run on **Coal**, not on Depot Energy.

### Roster

| Unit | Role |
| --- | --- |
| **Forester Maiden** | The Worker. Trained at the Keep, with no ranged attack. Fells trees, farms, gathers and builds. |
| **Round Table Marine** | The core infantry: an automatic rifle with a high rate of fire. |
| **Grail Sentinel** | The healer and support unit, healing living units with medical technology. Carries **Vitality Stimulus** and a way to slow enemies. Whether those are one ability or two is **[OPEN]** (see 6.2). Its model keeps the enclosed helmet, kite shield and cape. |
| **Warhound** | A fast dog scout that crosses forest (mobility layer 1, as the Scout). Trained at the Keep. |
| **Questing Marine** | Modelled, with no role yet. The leading candidate for the anti-armour role, **[OPEN]** (see 6.1). |
| **Azure Dragon** | A late-tier mount with a fire-breath cone, for a later milestone. |

The Grail Sentinel is the healer. An earlier proposal added a separate Medic and made the Sentinel anti-armour; that is not the design. `Blender/Characters/ArthurianMarines/README.md` lists the Sentinel's gear but not its role, so this file is where the role is recorded.

## 2. Art on the Windows checkout

These models are on the Windows checkout at `C:\Dev\Supply-Lines\Blender\Characters` and are **not in the repository**: `Blender/Characters/` in git holds only Grenadier, Infantry, Scout and Ubermech, and `scenes/models/` has no Arthurian scene. The list is as reported in the handoff of 2026-11-23; cloud agents cannot see these files until they are committed.

| Model | Export | Clips and notes |
| --- | --- | --- |
| Forester Maiden | `ForesterMaiden/forester_maiden.glb` | `Walk`, `Chop`, `Till`, `Build`, `Gather`, `Carry`; a farming sunhat and cultivator that can be switched on. No mining clip: reuse `Chop` or `Build` until one is made, if she works mines. |
| Round Table Marine | `ArthurianMarines/export/round_table_marine.glb` | `Run`, `Shoot`. |
| Grail Sentinel | `ArthurianMarines/export/grail_sentinel.glb` | `Run`. |
| Questing Marine | `ArthurianMarines/export/questing_marine.glb` | `Run`. Silver helmet, amber eye-slit, carbine, half-cape. |
| Warhound | `ArthurianHound/export/arthurian_hound.glb`, wired to a local `scenes/models/arthurian_hound_model.tscn`; and `ArthurianMarines/export/warhound.glb` | Two builds. The second has `Rest`, `Run`, `Attack`, `Die`. Which is kept is **[OPEN]** (see 6.6). |
| Azure Dragon | `AzureDragon/export/azure_dragon.glb` | `Rest`, `Walk`, `FireBreath` (a 7.5 m by 3.3 m cone). A `Rider_Mount_Socket` sized for a 1.93 m Round Table Marine. |

## 3. Repo baseline: the Cyborgs and the shared rules

Speeds are in metres per second, ranges and vision in metres. "vs heavy" is the separate attack against Tanks and buildings.

### Units

From `assets/units/*.tres`, `assets/economy/*.tres` and `scenes/gameplay/depot_truck.tscn`.

| Unit | Cost | Build | HP | Speed | Range | Vision | Attack | vs heavy | Notes |
| --- | --- | ---: | ---: | ---: | ---: | ---: | --- | --- | --- |
| Infantry (Deforester) | 100 E, 20 I | 10 s | 55 | 4 | 15 | 30 | 8 / 1 s (8 DPS) | — | The worker: carries 10, gathers and builds 5 every 1.2 s, repairs vehicles and buildings. |
| Scout | 35 E, 5 I | 8 s | 40 | 8 | 10 | 50 | 8 / 2 s (4 DPS) | — | Fires while moving; crosses forest. |
| Grenadier | 85 E, 15 I | 12 s | 60 | 4 | 18 | 32 | 20 / 3 s (6.7 DPS) | 40 / 3 s (13.3 DPS) | 3 m splash. |
| Tank (Bastion) | 150 E, 35 I | 28 s | 150 | 6 | 10–30 | 52 | 12 / 1 s (12 DPS) | 50 / 3 s (16.7 DPS) | 3 m splash, fires while moving, turns at 90°/s, clears forest. **Roof gun** 3 / 0.35 s (8.6 DPS) at 0–10 m, turning 360°/s. Fuel 60 coal at 0.15 a metre (400 m). |
| Derailer | 45 E, 10 I | 14 s | 45 | 12 | 12 | 30 | 16 / 2 s (8 DPS) | — | Fires while moving. Derails: 3 s work, 30 s cooldown, 60% of a train's HP. Fuel 20 at 0.05 a metre (400 m). |
| Drone | 60 E, 5 I | 16 s | 30 | 12 | — | 60 | none | — | Air layer, drawn 12 m up. Burns no fuel. |
| Ubermech | 250 E, 60 I | 40 s | 120 | 4 | 20 | 36 | 12 / 5 s (2.4 DPS) | — | Fuel 60 at 0.15 a metre (400 m). |
| Cargo truck | 100 E, 20 I | 3 s | 80 | 8 | — | — | none | — | 100 cargo (4 crates of 25). Deployed, it is a stockpile with a 13.125 m range. Fuel 30 at 0.05 a metre (600 m). |
| Depot truck | 150 E, 30 I | — | 80 | 6 | — | — | none | — | Deploys into a Depot with 100 E. |
| Maglev train | 150 E, 30 I | 3 s | 80 | 16 | — | — | none | — | 300 cargo (12 crates), 2 s to load or unload. Burns no fuel: draws 0.15 E a metre from the nearest connected Depot. |

### Buildings and map resources

- **Depot** (`assets/economy/depot_rules.tres`, `scripts/gameplay/depot.gd`): 10 x 10 with a truck apron, 1,000 HP, stores 2,000, 26.25 m range, 52.5 m apart centre to centre, 8.5 m drop-off, captured by standing within 12 m for 8 s. A plan costs 20 E and 20 I. The starting Depot has 500 E (and the 500-iron testing grant); a Depot built from a plan starts with nothing, apart from that grant.
- **Generator** (`supply_rules.tres`, `generator_rules.tres`): 3 x 3, 300 HP, 0 E and 40 I. 1 wood gives 10 E over 2 s (5 E/s); 1 coal gives 30 E over 3 s (10 E/s).
- **Barracks** (`assets/buildings/barracks.tres`): 6 x 6, 100 E and 45 I. Trains Infantry, Scouts and Grenadiers.
- **Tank Factory** (`tank_factory.tres`): 8 x 8, 200 E and 65 I. Builds Tanks, Derailers, Drones and Ubermechs.
- **Mine** (`engineering_rules.gd`): 2 x 2, 1,000 HP, 25 I. Shared: any side's workers can work it.
- **Map** (`harvesting_rules.gd`): a forest tile holds 20 wood, an ore tile 250 iron, a mine-site tile 625 (7,500 per site), a coal tile 50. Coal needs a mine. Two Lakes has 20 mine sites, 11 coal fields holding 20,100, and 20% forest (`TWO_LAKES_MAP.md`).

### Shared rules

- **Construction from site materials** (`scripts/economy/construction_plan.gd`, `SITE_CONSTRUCTION.md`): a plan's materials must lie on its footprint. Workers build in 5 every 1.2 s while one covering stockpile pays the energy in step.
- **Repair** (`engineering_rules.gd`, `engineering_work.gd`): 10 HP/s for 2 E and 1 I a second, within 7 m, paid by a covering Depot or deployed truck. Vehicles (anything with fuel rules, `EngineeringWork.is_vehicle`) and buildings are repaired; Infantry, Grenadiers and Scouts are people and are not.
- **Vehicle power** (`fuel_rules.gd`): inside a friendly Depot's range a vehicle runs on that Depot's energy (0.2 E a metre) instead of its coal. Refuelling takes 5 coal a second.
- **Track** (`scripts/rails/rail_rules.gd`): 2 iron a metre. A line with a Depot pays an upkeep of 0.1 E/s per 100 m, plus 1 E/s for each train running on it.
- **Combat** (`COMBAT_BATCH.md`): damage every interval, plus an optional attack against heavy targets (Tanks, by unit ID, and buildings). **There is no armour.** Every attack can hit Drones, judged by distance on the map; nothing restricts anti-air.

## 4. Provisional rules

### 4.1 Founding a Keep, and building around it

**The Cyborg precedent.** A new Depot must stand 52.5 m from any other, so no existing Depot can cover its plan; its 20 E comes from a deployed truck beside the site, or the Depot truck deploys into one.

**The Keep.** A Keep plan costs only site materials and no energy, so it needs no payer and can be founded anywhere. In `construction_plan.gd`, `energy_due()` returns 0 when the plan's energy is 0, and `work()` waits for a payer only while something is due. A Forester Maiden builds it in from what has been delivered.

- Provisional cost: **100 units of site materials, for example 60 Wood and 40 Iron**, so that one four-crate Balloon or ten Worker loads carry a whole Keep.
- Provisional size and stats: as a Depot. 10 x 10, 1,000 HP, stores 2,000, 26.25 m range, 52.5 m spacing, 8.5 m drop-off.
- A home Keep starts with 500 Food, as a home Depot starts with 500 E. A founded Keep starts with nothing: its first Food arrives as crates, as a plan-built Depot's does.

**Other Knight buildings** (Farm, House, the Knights' Barracks) are built from site materials, with their labour paid in Food by one covering Keep: the slot Energy fills for the Cyborgs.

**Code this needs:**

- `materials()` knows only `iron` and `wood`; add `food`.
- `energy_payer()` looks for stockpiles of team `"player"` only.
- Payment goes through `spend_local(energy, iron)`, which would need a Food form.
- The game has no faction setting at all. Milestone 1 can make the player Knights in its own test scene.

### 4.2 Food, Farms, animals and Houses

- **Food** pays for training units, for building labour, and for the Sentinel's healing. Troops already in the field do not eat.
- **Farms** work as renewable mines. A Worker tends the Farm and carries 10 Food a trip to the Keep she is assigned to, so Food is grown in one place and spent where it is delivered.
  - Provisional: footprint 6 x 6 or 8 x 8; at most 1.5 to 2 Food/s per Farm, worked by 1 or 2 Workers.
  - Farms can be built on grass and desert, so the Two Lakes south starts are not handicapped.
  - The large footprint is deliberate. More Food means more Farms spread over open ground, where Scouts and Derailers can raid them, as Cyborgs must push out for forest and coal.
- **Is a Worker cheap?** At 1.5 to 2 Food/s, a 45 to 50 Food Maiden is 23 to 33 s of one Farm's output. A Cyborg Infantry's 100 E is 20 s of a wood Generator burning 10 wood, plus 20 Iron, and it comes armed. Whether the Maiden is cheaper depends on the Farm's real output, so measure it before saying so.
- **Animals** come later: finite bursts of Food, gathered by Workers or hunted by Warhounds, rewarding early scouting.
- **Houses** come after Milestone 1. They raise a local cap: each Keep supports a base number of units, and Houses built inside its range raise it. There is no global population counter.
  - What counts against a Keep's cap is **[OPEN]** (see 6.4).
  - One natural reading: the units trained by the Keep and by the production buildings it pays for, which follows how a Barracks is assigned to the Depot that paid for it.

### 4.3 Roads, Balloons and trains

**Roads.** Cheap corridors built by Workers, from Wood or Iron, on open ground.

- Provisional bonus: +35 to 50% for friendly units on foot. Infantry speed goes from 4 to 5.4 to 6 m/s.
- Roads are the Knights' foot logistics and reinforcement routes, since the Knights have no reusable truck. West to East on Two Lakes is 414 m: about 1:44 on foot, and 69 to 77 s if the whole way is road.
- Roads do not answer the Tank: at 6 m/s it still outruns or matches road-bound Knights. Whether a fast Warhound (15 m/s at +50%) gets the full bonus in a fight is a tuning question.

**Air Balloons.** Launched from a Keep, through a launch command separate from the Worker and Hound queue, as crate packing is already separate from Depot printing.

- Provisional: 4 crates (100 units), 8 m/s, flying one way over everything, landing crates on a forward Keep's site or a Sentinel resupply point. Priced mostly in Wood, with a little Food or Iron and no Coal.
- A Balloon delivers ordinary crates. It does not let a distant Keep spend, and it does not finish a building: a Worker still builds it in.
- Its benchmark is the Cargo truck, which carries the same 4 crates at the same speed but comes back. The Balloon trades the return trip for flying over the map.
- **Interception already works.** Every attack can hit air units. At 8 m/s a Balloon flying straight over a Tank spends 7.5 s within its 30 m reach:
  - 5 s in the main gun's 10–30 m band, about 60 damage;
  - 2.5 s inside 10 m for the roof gun, about 20.

  So 100 to 120 HP survives one Tank but not two. Flying the long way round enemy positions is part of the craft.
- One-way does not mean one direction. A Keep at a far mine can launch back toward home, so launch cost and preparation time, not trip time, set how much Balloons can move. At 100 units a launch, 400 units a minute is one launch every 15 s.

**Knight trains.** The same freight role as the Maglev: 12 crates (300 units), 16 m/s, 80 HP, running on Coal.

- Provisional: an **onboard coal tank**, using the existing `FuelRules` (`assets/economy/fuel_train.tres` holds 90 and nothing uses it now), at 0.02 to 0.05 coal a metre (1.8 to 4.5 km a tank). No idle track upkeep. Refuel at a Keep.
- Converting the Maglev's draw instead would give 0.005 coal a metre (0.15 E at 30 E a coal), too small to meter sensibly.
- This splits the factions cleanly. A Maglev runs on the grid, pays upkeep and stops when its Depot runs dry. A Knight train carries its own fuel, finishes its run if a Keep falls, and must come back for Coal.
- It gives the Knights a real reason to hold coal seams in the mid and late game. Denying coal matters earlier: Cyborg trucks and Tanks burn it outside Depot range, and coal Generators give twice what wood does.

### 4.4 Units

Provisional numbers, to test against section 3.

| Unit | Trained at | Cost | Build | HP | Speed | Range | Attack | vs heavy |
| --- | --- | --- | ---: | ---: | ---: | ---: | --- | --- |
| Forester Maiden | Keep | 45–50 Food | 8–10 s | 45–50 | 4 | — | none | — |
| Warhound | Keep | 35–40 Food, 5 I | 8 s | 45–50 | 8.5–9.5 | melee | 10–12 / 1.2 s | — |
| Round Table Marine | Barracks | 65–75 Food, 15–20 I | 10–12 s | 65–70 | 4 | 16–18 | 4 / 0.4 s (10 DPS) | 2 / 0.5 s (4 DPS) |
| Grail Sentinel | Barracks | 70 Food, 20 I | 14 s | 75–80 | 4 | heals within 7 | heals 4–5 HP/s | — |
| Questing Marine | Barracks | 75–85 Food, 20–25 I | 14 s | 65 | 4 | 18–20 | 10 / 2 s (5 DPS) | 35–40 / 2.5 s (14–16 DPS) |

- **Warhound:** vision 50, crosses forest. Its job is scouting, finding herds and chasing off Scouts. It cannot slip inside a Tank's 10 m minimum range to escape fire: the roof gun covers 0–10 m at 8.6 DPS, killing a Hound in 5 to 6 s, and a Tank ordered onto something that close backs off.
- **Round Table Marine:** the weak attack against Tanks and buildings is how its rifle "bounces off" armour, without adding an armour system.
- **Grail Sentinel:** heals people (not `is_vehicle`) as repair heals vehicles.
  - Paid in Food from a covering Keep, or in the field from a carried reserve worth 120 to 150 HP, refilled at a Keep or from a Food crate. Provisional: 1 Food per 5 HP. Nothing regenerates for free, so cutting supply stops healing.
  - 4 to 5 HP/s is well under repair's 10 HP/s. It does not out-heal one Cyborg Infantry (8 DPS) or Grenadier (6.7). At 5 HP/s it does out-heal a single Scout (4).
- **Questing Marine:** about half a Tank's price.
  - Alone, it kills a Tank in about 10 s, while the Tank kills it in about 5.4 s from beyond its reach.
  - A pair does 28 to 32 DPS and kills a Tank in about 5 s, but splash punishes them for standing within 3 m of each other.
- **Azure Dragon:** later. Like the Hound, it gains nothing by getting inside 10 m of a Tank, because the roof gun covers that ring.

## 5. Milestone 1: home Keep to forward Keep

The first playable slice proves the loop before any balance pass. Model its headless test on `tests/site_construction_test.gd`.

**In scope:**

- A home Keep, with Food stock and trained Forester Maidens.
- A Farm worked by a Maiden, with Food carried to the Keep.
- A Keep plan placed beyond any coverage and built from delivered Wood and Iron, with no payer.
- Other Knight buildings paid in Food by a covering Keep.

**Out of scope:** Houses, animals, Balloons (unless 6.5 says otherwise), Roads, trains, combat units, the Cyborg matchup.

**Questions it should answer:**

1. Can the player gather and deliver the founding materials, and how many Maiden-minutes does it take?
2. How long after founding can the forward Keep train?
3. What does an interrupted delivery cost?
4. Does anything give a Keep stock it was not delivered?

## 6. Open decisions

1. **Anti-armour.** Is the Questing Marine the anti-Tank and anti-building unit, with the Azure Dragon kept as the late fire-breath mount?
2. **Vitality Stimulus and the slow.** Are they one ability (the handoff) or two (an earlier summary)? Does the slow affect vehicles?
   - The Tank outranges the Marines (30 m against 16 to 18) and outruns them (6 against 4). Slowed to 3 m/s, it lets road-bound Knights close the last 13 m in about 5 s, against 13 s off-road.
   - Because the roof gun covers the ring inside 10 m, there is no other cheap answer. If the slow does not touch vehicles, the Knights' answer to Tanks rests on the Questing Marine alone.
3. **Train coal.** An onboard coal tank (4.3, preferred) or coal drawn from connected Keeps?
4. **Houses and animals.** Both stay in the design for the stage after Milestone 1. For Houses, what counts against a Keep's local cap?
5. **Milestone 1 deliveries.** Maidens on foot only, which measures the bare cost the Balloon has to beat, or a minimal Balloon from the start? Recommended: on foot first.
6. **Warhound build.** `ArthurianHound` or the `ArthurianMarines` warhound?
7. **Keep footprint.** 10 x 10, as a Depot, or 8 x 8?
