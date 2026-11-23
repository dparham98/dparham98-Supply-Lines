# Handoff: implement the Knights and Cyborg balance proposals

Written 2026-11-23 for the agent who will implement them. Baseline: `main` at `65367bc`.

## What this is

The owner commissioned a balance report on the two factions. Its proposals were tested in a scratch copy of the
game, AI against AI, and the owner has approved all of them, including the report's recommended answer to each open
decision, **for human play-testing**. Your job is to build them in the real game so a person can play them.

Nothing has been played by a person yet. Every number below is a starting point that play-testing will move, so
put every number in a data file (`assets/units/*.tres`, `assets/economy/*.tres`, a new rules resource) and never in
a script. The owner is also running a second research round that will revise some of the later items; those are
marked **under review** and come last.

What done looks like: each item below is on its own branch, passes `bash ci/run_headless_checks.sh`, has the
headless check listed for it added under `tests/`, and has a short doc in `docs/` in the style of the existing
batch docs. The owner accepts gameplay by hand before anything merges. Do not merge, and do not force-push.

## Read first

- `AGENTS.md`, `README.md`, `docs/ARCHITECTURE.md`: the working rules. Two matter most here. Gameplay scripts must
  not create terrain, lighting, UI or actor visuals at runtime, so every new building and unit needs a saved scene
  with a `Visuals` model slot. And `main` is the accepted playable baseline.
- `docs/ARTHURIAN_KNIGHTS.md`, `docs/ENEMY_AI.md`, `docs/FOG_OF_WAR.md`, `docs/FUEL_BATCH.md`, `docs/DERAILER.md`,
  `docs/UNIT_STATS.md`, `docs/PRODUCTION_POWER.md`.
- `tests/investigation/balance/` on branch `claude/game-balance-knights-cyborg-52c0aa`: the tools and results
  behind every figure here. Its `README.md` explains them.

## What already exists as a prototype

`tests/investigation/balance/prototype.patch` changes seven scripts in a scratch copy, and
`tests/investigation/balance/scripts/` holds a prototype Farm, House, housing counter and Knights AI. They prove
the rules work and show where the hooks are. They are not shippable: they have no art, no HUD, no saved scenes and
no tests, and the Farm and House are built in script. Treat them as a reference to read, not code to merge.

| Proposal | Prototype to read |
| --- | --- |
| Freed-target guard | `prototype.patch`, `unit_agent.gd` |
| See to shoot, forward-arc and reload scale for moving fire | `prototype.patch`, `unit_agent.gd` (`_team_sees`, `moving_fire_arc`, `moving_fire_interval_scale`) |
| Splash share, armoured flag | `prototype.patch`, `unit_stats.gd`, `combat_resolver.gd` |
| Keeps train for either side, housing check | `prototype.patch`, `keep.gd`, `production_building.gd` |
| Farm and House plans, building from the Keep's stock | `prototype.patch`, `depot_network.gd`, `construction_plan.gd`; `scripts/farm.gd`, `house.gd`, `knight_supply.gd` |
| Knights AI | `scripts/knights_player.gd` |
| Two-weapon Ubermech | `scripts/second_weapon.gd`, `scripts/arena.gd` (`mech` controller) |
| Every proposed stat | `matches/_settings.json`, keys `proposed_stats` and `proposed_rules` |

To rerun any measurement: `tests/investigation/balance/setup.sh`, then `run.sh` (see that README).

## Five rules every change must keep

The game's point is a local resource economy. Check each change against these.

1. Everything is somewhere: each unit of a resource sits in one Depot or Keep, crate, pile, hold or pair of hands.
   There is no shared bank.
2. A spender is paid by one stockpile whose range covers it.
3. Moving a resource takes a carrier that can be shot. The one standing exception: inside a stockpile's range the
   stockpile pays for building and nothing is carried, as Depots already do.
4. Nothing refills for free.
5. Side-wide effects are rare. Research and upgrades are side-wide. Housing is side-wide, but a House counts only
   while it stands inside a friendly Keep's range.

## Stage 1: build these five, then stop for a play-test

### 1. Guard freed targets (small)

`unit_agent.gd`, in `_order_process`: the repair check passes `order_target` to `EngineeringWork.repairable` and
the heal check passes it to `MedicalWork.can_heal` after the target may have been freed. That throws a script error
every frame and freezes the unit. Guard both with `is_instance_valid` and drop the order.

Check: a worker whose repair target is destroyed goes idle with no script error. The same for a healer.

### 2. Knights tidy-up (small)

- The Chapterhouse's 1x to 4x speed setting is free, because extra speed is charged in energy and Knights units
  cost none. **Remove the setting from the Chapterhouse.** Barracks and Tank Factory keep it.
- A Knights player's Build page shows every Cyborg building. Show each faction only its own.
- The Cyborg AI sends Drones ahead of its wave, where they die. Keep each Drone over the army's centre.

Check: the Chapterhouse card has no speed control and a Marine takes its listed time; the tile list for each
faction; in an AI match a Drone is within 15 m of its army's centre while the army moves.

### 3. See to shoot, the Tank, and splash (medium)

- **Rule:** a unit fires only at a target its side can see now. `_nearest_opponent` looks only at range today;
  `FogOfWar.visible_to` answers the question. Maps with no fog node are unaffected. In the tests only units counted
  as spotters. Use whatever the fog counts as sight, buildings included, and say so in the doc.
- **Tank** (`assets/units/tank.tres`): sight 20 (was 52), speed 5 (was 6), main gun at units 12 every 1.5 s (was
  1 s) with 2 m splash (was 3 m). Range 10 to 30, the roof gun, the gun against armour and buildings, moving fire
  and price are unchanged.
- **Splash:** every splash weapon does half damage to units other than the one aimed at. That is the Tank, the
  Grenadier and the Azure Dragon. Make the share a stat.
- Carry the forward-arc limit on moving fire in as a stat that is switched off. It is the owner's reserve if Tanks
  with Drones still kite too well.

Check, with the arena tool's fights or equivalents: two kiting Tanks with no spotter lose to 8 Grenadiers and to 6
Questing Marines; with a Drone alive they still kill 10 Deforesters untouched; 5 Tanks on attack-move no longer
beat 10 Deforesters with 99% of their health left (about 5% in the prototype).

### 4. Knights economy (large)

The Knights have no source of Food today, so a match holds 325 Food. Give them one, and no energy.

| Piece | Rule |
| --- | --- |
| Farm | 30 W. 4 x 4 cells, inside a friendly Keep's range. One Forester Maiden tills it and carries Food to the Keep: 2 Food each 1.2 s work beat, which measured 84 to 87 Food a minute with the walk. It refuses a second worker. |
| House | 40 W. 3 x 3 cells. Adds 8 housing while it stands inside a friendly Keep's range. |
| Keep | Houses 10. Stores Food, wood and iron as now. Trains for the AI side too (today `keep.gd` returns early for any team but the player's). |
| Housing used | Forester 1, Warhound 1, Round Table Marine 2, Grail Sentinel 2, Questing Marine 2, Azure Dragon 4. No upper limit. Training waits when housing is full, and the HUD must say why. |
| Building at home | A Knights plan inside a friendly Keep's range is paid from that Keep's stock, with a Forester doing the work. Outside every range, materials must be on the site, as now. |
| Start on every map | Keep with 150 F, 100 W, 50 I and two Foresters. No Food crate. (Now 300 F, 150 W, 150 I and a 25 F crate.) |
| Training times | Forester 12 s (was 8), Round Table Marine 15 (11), Grail Sentinel 15 (12), Questing Marine 17 (14), Azure Dragon 40 (26). Warhound stays 7. Prices do not change. |
| Energy | None. The Knights never hold or spend it. |

The HUD needs Food and housing shown for the Knights, the Farm and House on their Build page, and a worker's
farming state. Farm and House need saved scenes with placeholder models in their `Visuals` slots; the owner will
supply art.

Check: a Farm with one Forester yields 80 to 90 Food a minute; a second Forester is refused; a House outside every
Keep's range adds nothing; one Keep reaches 50 army units by 8:00 under the Knights AI of item 5.

### 5. AIs (medium)

- **A Knights AI.** `scripts/knights_player.gd` in the investigation folder is the reference. Its opening: both
  Foresters build and work a Farm; the Keep trains Foresters without a pause to 14; 8 Farms and the first
  Chapterhouse by 2:00; three Chapterhouses by 3:30; Houses ahead of need; a second Keep started at 5:00; first
  wave at 8:00. Army mix 10 Round Table Marines to 3 Questing Marines to 3 Grail Sentinels.
- **Cyborg AI default build order** becomes two Barracks: Generator, Barracks, Generator, Barracks, Generator,
  Coal Mine, Tank Factory, Generator, with 6 home workers and a production queue of 3. Tech first lost to it.
- **Find and fix the build-order stall.** In 4 runs of 12 the default order stopped after its second Generator, at
  the Coal Mine step, and built no Tank Factory. From the East start the three-Barracks order stopped at two
  Barracks and three Generators in 3 runs of 3. The order waits for each plan to finish
  (`scripts/ai/enemy_player.gd`, near `next_building` and `coal_site`); the cause was not found. Start by logging
  the plan it is waiting on. `matches/eco_c_std_c_2rax.json` (West) and `matches/f_k_vs_c3rax.json` (East)
  reproduce it.

Check: in ten AI-against-AI runs the build order completes every time, and neither side is wiped out before 10:00.

**Stop here.** Tell the owner Stage 1 is ready to play, Knights against Cyborgs on Two Lakes. What to watch for is
at the end of this file.

## Stage 2: after the owner has played Stage 1

### 6. Grail Sentinel and Marine range (small)

- Grail Sentinel heals by itself: the most hurt friendly person within 9 m, 10 health a second (was 5 at 7 m). One
  reserve point heals one health. Reserve 200 (was 120). It refills only inside a friendly Keep's range or beside a
  Food crate, 1 Food for 5 points, as now. **Under review:** the owner wants the reserve to stop costing Food. Keep
  the refill source in data.
- Round Table Marine range 18 (was 16). Tested in arena battles only.

Check: 10 Round Table Marines, 3 Questing Marines and 3 Sentinels beat 8 Deforesters and 8 Grenadiers on
attack-move (with item 3's splash in).

### 7. Supply Balloon (medium)

The Keep's one carrier. Made at any Keep: 20 W plus its cargo, 10 s. It carries 4 crates (100 in all) in any mix of
Food, wood and iron, chosen at launch. It flies straight to a clicked point the player can see at 5 m/s, over
anything, with 40 health, and any unit can shoot it. On landing it sets the crates down and is gone; inside a
friendly Keep's range it unloads into that Keep. It never returns and never carries units. It can reuse crates, the
Drone's air layer and the Depot truck's deploy-at-a-point order. The Keep model already has a roof pad and a
`LaunchBalloon` clip. The price is untested.

Check: four crates land where sent; a Keep (50 W + 50 I) is built from one balloon's crates; a balloon shot down
drops nothing.

### 8. Armour class and the Ubermech (medium)

- **Armour class:** every unit is light or armoured, and buildings are their own class. Today
  `heavy_target_damage` applies to buildings and to the unit whose id is `tank` (`combat_resolver.gd`). Replace the
  id test with a flag. Armoured: Tank, Ubermech, Azure Dragon, trains and trucks.
- **Ubermech:** 360 health (was 120), speed 4, sight 30 (was 36), armoured, 250 E / 60 I unchanged.
  - Laser: 40 every 1.5 s at 16 m against light units and flyers; 8 against armoured units.
  - Missile pods: 60 every 3 s at 6 to 34 m, against armoured units and buildings only. The see-to-shoot rule means
    the last 4 m need a spotter.
  - It needs a target class on each weapon, and an attack-move that stops at the range of the weapon that suits
    the target. The model already alternates a laser pulse and a six-pod volley.

Check: three Ubermechs beat 10 Deforesters, 28 Scouts and 5 Tanks of item 3, and lose to 11 Grenadiers.

### 9. Derailer, detection and mines (medium)

- **Derailer price** 70 E / 15 I (was 45 / 10).
- **Detection:** a hidden thing (for now only a mine) is drawn for a side, and can be targeted by it, only while it
  lies within the detect range of one of that side's detectors. Detectors: Depot and Keep at their own range
  (26.25 m), Drone 20 m, Warhound 10 m. Nothing else detects. The fog loop that hides the other side's things every
  0.2 s is the place for it. **Under review:** the owner is asking whether this list favours the Knights.
- **Minelaying:** research at the Temple of Science, 150 E / 100 I, 60 s, like Mining Trains. After it, every
  Derailer can carry 2 mines. Stopped inside a friendly Depot's range or beside a deployed Cargo truck, it loads
  them for 10 iron each from that stockpile, the way it refuels. Laying takes 2 s; the mine arms after 3 s and is
  then hidden. An enemy ground unit within 2 m sets it off: 60 damage, half to others within 3 m. Laid on track, the
  next train onto it derails, as the spike did before 2026-11-22.

Check: a mine is hidden from a side with no detector near and shown to one with a Drone or Warhound in range;
loading two mines takes 20 iron from the covering Depot; an unresearched Derailer cannot load.

### 10. Drone fuel (small)

A Drone burns 0.1 coal a second in the air (`assets/economy/fuel_drone.tres`), about five minutes aloft. Out of
coal, it lands where it is and can be refuelled as a vehicle is. **Under review:** the owner wants Drones and
Derailers clearly more fuel-efficient than Tanks and trucks; expect the rate to change.

Check: a Drone out of coal lands where it is.

### 11. Attack and armour upgrades (medium)

| | Cyborgs | Knights |
| --- | --- | --- |
| Building | New, working name Foundry. No price was set; start at 150 E / 80 I and flag it. | New, working name Forge, 60 W / 80 I |
| Lines | Infantry weapons, infantry armour, vehicle weapons, vehicle armour | Arms, mail |
| Levels | 3 | 3 |
| Price a level | 100 E / 150 I, then 150 / 250, then 200 / 350 | 100 F / 150 I, then 150 / 250, then 200 / 350 |
| Time a level | 60, 90, 120 s | the same |
| Paid by | The Depot covering the building, as research is | The Keep covering it |

Each attack level adds 10% of a weapon's base damage, rounded, and at least 1. Each armour level takes 1 off every
hit, never below 1. Upgrades hold for the whole side. None of these numbers was simulated.

Check: damage and armour per level against this table, for one unit of each line.

## Stage 3: under review, check with the owner before starting

The second research round is rethinking all three. Build them last, and ask first.

- **12. Roads.** Proposed: Foresters lay a road along a path the game suggests between two buildings, as track is
  planned; 1 W for every 2 m; friendly ground units move 30% faster on it and prefer it when routing; only the side
  that laid it gets the bonus. The owner wants a clearer identity and laying method.
- **13. Knights rail.** Proposed: a Wainwright (60 W / 60 I, inside a Keep's range) lets the Knights lay the same
  track at 2 I a metre and lets a Keep on that track build a train (60 F / 40 W / 30 I, 12 m/s). The train was to
  burn wood by the metre; the owner now leans to coal.
- **14. Mist, then Slow.** Mist: 40 reserve points; for 8 s units inside an 8 m circle cannot be seen from more
  than 8 m away, done through the fog, not through pathing. Slow: research at the Forge, 25 points, enemy units in a
  5 m circle move 40% slower for 5 s. No force field. How the reserve refills is under review (item 6).

## Decided, so do not reopen

- No energy for the Knights. No free Forester with a new Keep. No upper limit on housing.
- The Keep's menu has no truck, train or track. Its only carrier is the balloon.
- Tank kiting is answered by sight, not by removing moving fire. The forward-arc limit stays in reserve.
- Scouts and Sentinels do not detect.
- Derailer mines cost iron where they are loaded; research alone does not hand them out.
- A Farm yields about 85 Food a minute with one Forester.

## What to watch in the Stage 1 play-test

Give the owner this list with the Stage 1 build.

| Watch | Healthy | If not |
| --- | --- | --- |
| Unspent iron across a side's Depots at 10:00 | Under about 500 | Prices are not binding; the upgrades of item 11 are the sink |
| A Knights push at 4:00 to 6:00 | The Cyborg holds with a second Barracks | Lengthen Forester training, or cut the starting Food to 100 |
| Housing | Stops the Knights player at least once after 6:00 | Raise the House price or cut it to 6 housing |
| Tanks alone | Lose to Grenadiers and to Questing Marines of the same cost | Cut splash again before touching speed |
| Tanks with a Drone, kiting | Line infantry can shoot down the Drone or force the Tanks off | Switch on the forward-arc limit |
| Drones | Built without prompting, and shot at | Lower Tank sight further |

## What I need back

For each item: the branch name, what changed in one paragraph, the output of its headless check, and anything you
had to decide that this file did not settle. Say plainly where a check failed or was skipped. If an item turns out
to conflict with one of the five rules, stop and say so before working round it.
