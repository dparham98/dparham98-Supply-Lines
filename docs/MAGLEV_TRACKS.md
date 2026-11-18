# Maglev tracks and trains

Rails are no longer one-tile squares. The network is built from the authored maglev set in `Blender/Vehicles/Maglev/MaglevTracks.blend` and `MaglevTrain.blend`: a straight piece, a 90-degree curve, left and right forks and a cargo car, all at the world scale 0.6 used for every authored vehicle (see the backlog's art section). This replaces the tile rules in [RAIL_BATCH.md](RAIL_BATCH.md); routes, loading and Depot ownership work as before.

## Pieces

| Piece | Authored | In game (0.6) | Cost (2 iron per metre) |
| --- | --- | --- | --- |
| Straight | 8 m long, 5 m wide | 4.8 m long, 3 m wide | 10 iron |
| Curve | radius 20 m, quarter turn | radius 12 m, arc 18.85 m | 38 iron |
| Fork (left or right) | 24 m straight leg, radius 20 m branch | 14.4 m stem, arc 18.85 m | 67 iron (both lanes) |

- A piece's centre line runs from end 0 to end 1; each end has an outward heading. Pieces connect where an end meets another piece's end head-on (within 5 cm, headings opposed). The curve bends toward its local +X, the left of its travel; laid mirrored it is traversed from end 1 and bends right.
- Each piece marks the tiles whose centres lie within half the track width of its centre line, so buildings and plans keep off (`is_footprint_valid` still refuses tiles carrying `rail`). Ground units cross tracks freely.
- Forks have an entry (end 0), a straight exit (end 1, lane 0) and a branch exit (end 2, lane 1). A train runs entry to either exit and never exit to exit; because trains do not reverse mid-route, going from one exit to the other needs a loop. Trains choose the lane from their route, and the switch blades move to match.
- All joined pieces form a line. A Depot is connected when any piece's edge touches its rail ring, half the Depot's range (`docs/RAIL_PLANNING.md`). The line belongs to every team with a living Depot connected to it, replacing per-piece ownership; a line with no connected friendly Depot is unusable until one returns. `assigned_depot` only records who paid.
- The plate on each piece shows power: cyan when a connected Depot has energy, dark without, red for a hostile line.

## Laying track

Since the playtest of 9eaed10 the player plans track before any of it is laid, and since 2026-11-17 picks two buildings and lays the track the game suggests; see `docs/RAIL_PLANNING.md`.

- `RailNetwork.place(kind, point, heading, join, pinned)` and `lay()` still lay a single piece at once. Tests and tools use them; the player no longer does. Their rule is unchanged: the payer's territory must cover every tile, and the piece must join connected track or a Depot's loading range.
- `join` is the end that meets the track; `true` lays a curve from its far end. `placement()` gives the transform and snap for previews and plans.

## Trains

- A Train is one self-powered cargo car on two sleds that follow the centre line. Its indicators light as the 300 capacity fills (12 crates).
- **The Industrial Streamliner** (2026-11-17) replaced the car's look. It keeps the old car's size, pivots and node names, so `scenes/models/train_model.tscn` and the train scripts are unchanged; only `assets/models/units/maglev_train_cargo.glb` was swapped. It has a tapered nose with the faction fang, a raised machinery spine, freight doors at the rear and a cargo flag that rises when loaded. Team paint covers about 16% of the visible body, up from about 6%. It is 7,212 triangles per car, up from 1,516, with 12 solid materials and no textures. The source, build scripts, previews and validation report are in `Blender/Vehicles/Maglev/Astra_Streamliner/` (`validation/REPORT.md`); `MaglevTrain.blend` keeps the old car. How many trains the game can run before the frame rate suffers has not been measured.
- **Reversing** (playtest of 2026-11-17): a train sent back the way it came no longer turns round on the spot. It runs backwards, nose last, until a route sends it nose first again. `_follow` in `train.gd` sees the new line set off against the last travel and starts the run from the car's far end, so the car stays where it stands; `train_consist.gd` keeps each car's nose (`_noses`) and puts the nose sled on the trailing point. `tests/rail_batch_test.gd` sends a train back to its first Depot and checks that it neither jumps nor turns. A consist of several cars would also need its car order flipped; the game fields one car.
- A train's position is a piece, a lane and a distance along it. Routes to a Depot pick the shortest connected line to a centre-line point on track touching the Depot's rail ring; the train runs along the sampled line at its speed.
- Trains burn no fuel. A train draws `train_energy_per_metre` (0.15, in `rail_rules.tres`) from the nearest connected friendly Depot with energy, moving to the next when that one is empty; there is no pooling. With no energy it holds position as "No power", keeping its cargo, and carries on when energy returns.
- Trains take no part in ground occupancy; ground traffic does not block them and they do not block it. A cut line holds a route with its cargo, and the route resumes by itself when the line is whole.

## Code

- `scripts/rails/track_piece.gd`, `scenes/gameplay/track_straight.tscn`, `track_curve.tscn`, `track_fork_left.tscn`, `track_fork_right.tscn`: geometry (`point_at`, `tangent_at`, `ends`, `nearest`), tile marking, lanes, switch blades, power colour.
- `scripts/rails/rail_network.gd`: registration, connections, lines and connected Depots (`connected_depots`, `power_source`), free ends, reachability and chains, sampled lines (`line`, `line_to_depot`, `spawn_stop`), placement, payment, the ghost preview (`RailPreview` in the skirmish map).
- `scripts/rails/rail_line.gd` (`RailLine`): point and tangent along a sampled line.
- `scripts/rails/train.gd`: track position, line following, routing to Depot stops, consist placement; `scripts/rails/train_consist.gd` on `scenes/models/train_model.tscn` places the car.
- Fixtures: `rail_exercise.tscn` lays seven straights along z=156.5 from the Depot to EastDepot; `remote_routes_exercise.tscn` leaves out the centre piece.

## Validation

- `tests/rail_batch_test.gd`: geometry and costs, head-on joins and free ends, tile marking, snapped laying and payment, refusals, left and mirrored curve exits, train print at a stop, cutting and restoring the centre piece, running the train to EastDepot with its consist on the line, ownership loss.
- `tests/rail_fork_power_test.gd`: fork geometry and price, the laying rule, lane choice, no exit-to-exit, blades, energy by the metre, No power and resume, nearest paying Depot, cut line resume.
- `tests/rail_keys_test.gd`: connecting two Depots by real clicks, with Backspace and Enter, while the Build page is open (`docs/RAIL_PLANNING.md`).
- `rail_runtime_check` picks the Depot and a build site by real clicks and lays the suggested track (`rail_plan`, `rail_construction`), and the route and crate suites run on the new fixture.
- Not playtested: the feel of laying curves, train speed over the longer pieces and how the set reads next to the 0.6 vehicles need your eye.
