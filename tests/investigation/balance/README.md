# Balance investigation tools (2026-11-23)

The tools behind the Knights and Cyborg balance report. They are investigation tools, not tests: they assert
nothing, CI does not run them, and the `.gdignore` beside this file keeps Godot from importing them. Nothing here
changes the game. They run in a scratch copy of the project with a small patch applied.

## What is here

| Path | What it is |
| --- | --- |
| `setup.sh`, `run.sh` | Build the scratch copy; run one investigation in it. |
| `prototype.patch` | The scratch copy's changes to seven gameplay scripts (below). |
| `scripts/arena.gd` | Battles from a JSON list on a flattened patch of First Contact, with the game's own units and orders. |
| `scripts/match2.gd` | A spectated AI-against-AI match on Two Lakes, either faction on either side, logged every 30 s. |
| `scripts/rates.gd` | One worker's iron and wood a minute for each faction; two Foresters founding a Keep by hand. |
| `scripts/pace_check.gd` | Shows that the Chapterhouse's 4x speed costs nothing. |
| `scripts/knights_player.gd` | A Knights AI on top of `scripts/ai/enemy_player.gd`: Farms, Houses, Chapterhouses, a second Keep. |
| `scripts/farm.*`, `house.*`, `knight_supply.gd` | Prototype Farm, House and housing. No art. |
| `scripts/second_weapon.gd` | A second, self-targeting weapon, for the two-weapon Ubermech trials. |
| `specs/`, `matches/` | The battle lists and match settings that were run. `matches/_settings.json` holds the AI build orders and the proposed stat changes. |
| `results/` | What they produced: one JSON line a battle, one JSON file a match, and the rate logs. |

## What the patch changes (scratch copy only)

- `unit_agent.gd`: guards freed repair and heal targets (a real bug on main); a switchable rule that a unit fires
  only at what its side sees; an arc and a reload scale for fire on the move; shot and damage counters.
- `unit_stats.gd`, `combat_resolver.gd`: splash damage share for bystanders; an `armoured` flag that takes
  `heavy_target_damage`.
- `keep.gd`, `production_building.gd`: Keeps train for either side; housing is checked before training.
- `depot_network.gd`, `construction_plan.gd`: Farm and House plan kinds; a Knights plan inside a friendly Keep's
  range builds from that Keep's stock.

## Run it

```bash
GODOT=/path/to/Godot_v4.7.2 tests/investigation/balance/setup.sh /tmp/sl-balance
export SIM=/tmp/sl-balance GODOT=/path/to/Godot_v4.7.2
tests/investigation/balance/run.sh rates cyborg
tests/investigation/balance/run.sh arena tests/investigation/balance/specs/kite.json /tmp/kite.jsonl
tests/investigation/balance/run.sh match tests/investigation/balance/matches/n_k_vs_c2rax.json /tmp/match.json
```

An arena batch takes seconds to a few minutes. An 18-minute match takes three to six minutes.

## Reading the files

- **Arena spec:** a list of `{name, a, b, dist, limit, sight, reps}`. Each side is a list of groups
  `{unit, n, stats, props, ctrl, ...}`; `stats` overrides fields of the unit's `UnitStats` for that battle. `ctrl` is
  `amove` (attack-move at the nearest foe, the default), `kite`, `hold`, `follow`, `medic` or `mech`.
- **Arena result:** `winner` (`a`, `b` or `draw`), `time`, units alive, health left and at the start for each side.
- **Match spec:** `{west, east, rules, stats, minutes}`. A side is `{faction, ai}`, where `ai` sets exports on the AI.
  `rules` switches the prototype rules (`farm_per_beat`, `sight`, `sentinel`, ...); `stats` overrides unit files.
- **Match result:** `outcome`, and `log` rows with each side's units, buildings, stock, army value and value lost.
- **Names:** `c_std` is the AI's default build (tech first), `c_2rax` and `c_3rax` two and three Barracks, `c_rush`
  the rush, `k` the Knights. `f_` matches use the game's combat as it is, `n_` the proposed changes. The first name
  is the West side. `k1_46f_12farms` and `k2_92f_8farms` were run before the Knights AI could found a second Keep.
- **Kiting batches:** `kite` tries each Tank rule alone. `kite_proposed` is the whole proposed Tank (sight 20,
  speed 5, 12 every 1.5 s, 2 m splash at half damage), alone and with a Drone. `kite_proposed2` adds no moving fire
  and a forward-arc limit to it. `kite_proposed3` has the lone proposed Tank retreat sooner, at 18.5 m and 19.5 m.
  In a result, `a_taken` includes a lost Drone's 30 health, and `a_moved` is 0 when side `a` lost.

## Limits

- One run each; the AI's rally scatter is random, so a rerun differs a little.
- AIs mass and attack-move. They do not retreat, micro, or use abilities.
- The Cyborg AI's build order stalled in some matches, for a reason not found: the default order stopped after its
  second Generator in 4 runs of 12, and the three-Barracks order stopped at two Barracks in all 3 runs from the East.
- The arena is flat open ground. Units start in blocks 2 m apart (4 m for Tanks, Ubermechs and Dragons).
- Mist, Slow, mines, roads and the balloon are not implemented here. The road and balloon figures come from
  stand-ins: a worker speed multiplier, and stock moved between Keeps after a delay.
