# Rail planning

From the playtest of main at 9eaed10 (2026-11-15). Track is planned first and laid all at once, and laid lines pay an energy upkeep. Since the playtest of PRs #88 and #89 together (2026-11-17), the player doesn't plan track piece by piece: they pick two buildings and the game suggests the track between them.

## Connecting two buildings

Rail starts from the Build page's Rail tile (R).

| Action | What it does |
| --- | --- |
| Click a building | The first click picks where the track starts; the second picks where it goes, and the game suggests the track. A click after that starts again. A click lands on a building when it is inside the building's ring. |
| Backspace | Takes back the second pick and its track, or the first pick when there is no second. |
| Enter | Lays the suggested track. |
| Esc, or leaving track laying any other way | Drops the picks and the track. Nothing was paid. |

While track laying is armed, Enter and Backspace go to it before the Build page's tiles. Other Build page keys work as usual, so R or G start the Rail tile or a Generator plan again.

- **The suggested track** is the shortest open path, in track length, made of straights and 90-degree curves. It starts touching the first building's ring and ends once it touches the second's.
  - It needs open buildable land, clear of laid track and of buildings.
  - It doesn't need to be in any Depot's range.
  - When there is no open path, the game says so. Pick another building.
- **Colour:**
  - The suggested track is green when a Depot can pay for it, and red when none has the iron.
  - Rings are amber, and green for the picked buildings and any the track touches.
- **The cursor label** shows the next step, then the track's pieces and iron, and either "ENTER LAYS IT" or "NOT ENOUGH IRON".
- **Forks aren't suggested.** The suggested track doesn't join existing lines either: it runs beside them. Forks and joins are for a later change.

### How the path is found

`scripts/rails/rail_router.gd` searches a lattice of half a straight's length (2.4 m). A state is a lattice point and one of four headings.

- **Moves from a state:**
  - a straight: two steps ahead;
  - a curve either way: five steps ahead and five aside, since the curve's radius is two and a half straights.
- **Search:** A* by track length, with the straight-line distance to the second ring as the estimate, up to 60,000 states.
- **Open land:** each move's cells are worked out once for each alignment of the lattice against the 1 m cell grid. Each cell is read with the network's own rule the first time a move needs it.
- **Speed:** a link to the starter mine takes about 20 ms. A path across the whole balanced map, 66 pieces, takes about half a second.

## Preview size

The playtest of PRs #88 and #89 together (2026-11-16) showed planned pieces drawn far too long, so they seemed to overlap or leave gaps when they were in fact joined. The track models are saved at 0.6 scale, the same as the laid track's model, but setting a model's global transform reset that to 1. The cursor preview on main had the same fault; it went unnoticed because each click laid the piece at once. The preview and the planned pieces now keep the saved scale (`model_scale`), so they are drawn at exactly the size the track is laid.

## Targets

The plan can be laid only when it connects two targets. The laid track it joins counts as part of the plan, so extending a line that already reaches a Depot needs only one more target.

The targets are:

- friendly Depots;
- mines (any Iron Mine; mines are being redesigned as caves elsewhere);
- unfinished build sites, of any kind except rail. The playtest asked for sites that only have materials on them; for now any site counts, as agreed.

**Connecting** doesn't mean ending there. While track is laid, every target shows a ring: amber, turning green once it is picked or the track touches it. Track connects as soon as its edge touches the ring; it doesn't have to be inside it.

- **A Depot's ring** is half its range (`depot_reach_fraction` 0.5 in `RailRules`): 13.125 m at the 26.25 m range, the same as a deployed Cargo truck's range. Trains are built, load and unload anywhere on track touching it, so a train can always be built on track that connects to a Depot. Ground units still use the Depot's 8.5 m loading distance.
- **A mine's or build site's ring** is half its footprint plus `connect_reach` (4 m) in `RailRules`.
- "Touches" means the track's centre line comes within the ring's radius plus half the track's width (1.5 m). Train stops use the same rule.

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

- **Connecting:** `target_at`, `pick_target`, `suggest_route`, `drop_route` and `route_status` in `scripts/rails/rail_network.gd`. The path search is `scripts/rails/rail_router.gd`.
- **The plan:** `pending`, `plan_targets`, `plan_payer`, `plan_blocker` and `commit_plan` in `rail_network.gd`. `plan_piece`, `plan_refusal` and `unplan_last` still plan single pieces for tests and tools; the player no longer uses them.
- **Rings:** `show_target_rings` and `depot_reach`, with the saved ring scene `scenes/ui/rail_target_ring.tscn`.
- **Train stops:** `stop_on` uses the Depot's rail ring; `Train.stop_reach` lets a train load anywhere on it.
- **Upkeep:** `upkeep_rate` and `charge_upkeep`, in `rail_network.gd`.
- **Keys:** `_input` and `_rail_key` in `scripts/gameplay/skirmish.gd`. Clearing `placing_rail` drops the picks and the plan.

## Tests

- **`tests/rail_planning_test.gd`** (headless, balanced map) checks that:
  - a seven-piece plan reaching past the Depot's range lays and pays nothing;
  - one target is refused, with a reason;
  - every target has a ring while laying, and the connected Depot's is green at half its range;
  - a build site is the second target, Enter lays every piece and charges the Depot once, and a train can be built on the new track;
  - track beyond the range is friendly and powered;
  - idle upkeep follows the line's length and is paid from the Depot, and a running train doubles it;
  - mines are targets;
  - track touching a Depot's ring connects, and track clear of it doesn't;
  - a click inside a ring picks that building, and the second pick suggests one joined line touching both rings;
  - the track is red when no Depot can pay and green when one can, and it lays and is paid for;
  - leaving track laying drops the plan and the rings.
- **`tests/rail_keys_test.gd`** picks two Depots by real clicks, and checks Backspace on each pick and Enter, with the Build page open.
- **`tests/rail_runtime_check.gd`** (rendered) picks the Depot and a build site, shows the suggested track (`rail_plan`), lays it with Enter and runs a train load at the larger ring.
