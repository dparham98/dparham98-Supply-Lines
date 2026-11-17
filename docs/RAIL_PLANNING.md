# Rail planning

From the playtest of main at 9eaed10 (2026-11-15). Track is planned first and laid all at once, and laid lines pay an energy upkeep.

## Keys while laying rail

Rail starts from the Build page's Rail tile (R).

| Key | What it does |
| --- | --- |
| Tab | Next piece: straight, left curve, right curve, left fork, right fork. |
| R | At a track end, mirrors the piece: a left curve becomes a right curve, a left fork a right fork, and back. A straight has no mirror. A free piece turns 90 degrees instead. |
| G | Changes which end of a fork joins the track. |
| Click | Plans a piece. It snaps to a free end of laid track or of the plan. |
| Backspace | Takes back the last planned piece. |
| Enter | Lays the plan. |
| Esc, or leaving track laying any other way | Drops the plan. Nothing was paid. |

While track laying is armed, these keys go to it before the Build page's tiles. Tab does not move GUI focus.

## Planning

- **A click plans a piece; nothing is laid or paid yet.** Planned pieces show as amber copies of the track model, which turn green once the plan can be laid.
- **Planned pieces need open land** clear of laid and planned track. They do not need to be in any Depot's range.
- **After the first piece,** each new piece must join the plan at a free end. The first piece may stand alone or snap onto laid track.
- **The cursor label** shows:
  - the piece and its iron;
  - why it can't be planned there, if it can't;
  - the plan's total iron, and either "connects n/2" or "ENTER LAYS IT".

## Preview size

The playtest of PRs #88 and #89 together (2026-11-16) showed planned pieces drawn far too long, so they seemed to overlap or leave gaps when they were in fact joined. The track models are saved at 0.6 scale, the same as the laid track's model, but setting a model's global transform reset that to 1. The cursor preview on main had the same fault; it went unnoticed because each click laid the piece at once. The preview and the planned pieces now keep the saved scale (`model_scale`), so they are drawn at exactly the size the track is laid.

## Targets

The plan can be laid only when it connects two targets. The laid track it joins counts as part of the plan, so extending a line that already reaches a Depot needs only one more target.

The targets are:

- friendly Depots;
- mines (any Iron Mine; mines are being redesigned as caves elsewhere);
- unfinished build sites, of any kind except rail. The playtest asked for sites that only have materials on them; for now any site counts, as agreed.

**Connecting** doesn't mean ending there. The track's centre line only has to pass within reach of the target: half the target's footprint plus `connect_reach` (4 m) in `RailRules`.

## Payment

When Enter lays the plan, one Depot pays all its iron, and energy if `rail_energy_cost` is set. The payer is the first of these that can afford it:

1. the pinned payer, if Pin is set;
2. the Depot among the plan's targets nearest its first piece;
3. the nearest friendly Depot anywhere.

If a piece can't be laid when the plan is committed (for example, a building went up there since), its iron goes back to the payer.

## Lines with no Depot

A line with no Depot on it, such as one from a mine to a build site, belongs to the side whose Depot paid for it. Its ends can be extended. It has no power and pays no upkeep until a Depot joins it.

## Upkeep

Every line with a Depot pays a small energy upkeep from its Depots, the fullest first. It is charged every half second.

- **Idle:** `upkeep_per_100m` (0.1 E/s) for every 100 m of track.
- **In use:** each train running on the line adds the idle amount again (`upkeep_per_running_train`, 1.0).

So a 100 m line costs 0.1 E/s idle and 0.3 E/s with two trains running. This is on top of the energy trains already draw per metre travelled. Upkeep a Depot can't pay is dropped, not owed.

## Code

- **Planning:** `pending`, `plan_piece`, `plan_refusal`, `unplan_last`, `clear_plan`, `plan_targets`, `plan_payer`, `plan_blocker` and `commit_plan` in `scripts/rails/rail_network.gd`.
- **Upkeep:** `upkeep_rate` and `charge_upkeep`, in the same file.
- **Keys:** `_input` and `_rail_key` in `scripts/gameplay/skirmish.gd`. Clearing `placing_rail` drops the plan.

## Tests

- **`tests/rail_planning_test.gd`** (headless, balanced map) checks that:
  - a seven-piece plan reaching past the Depot's range lays and pays nothing;
  - one target is refused, with a reason;
  - Backspace takes back a piece, and a piece off the plan's free ends is refused;
  - a build site is the second target;
  - Enter lays every piece and charges the Depot once;
  - track beyond the range is friendly and powered;
  - idle upkeep follows the line's length and is paid from the Depot, and a running train doubles it;
  - mines are targets;
  - leaving track laying drops the plan.
- **`tests/rail_keys_test.gd`** checks Tab, R (four turns back round), G, click to plan, Backspace and Enter with real key presses.
- **`tests/rail_runtime_check.gd`** (rendered) plans two pieces, adds a build site as the second target, and lays them with Enter.
