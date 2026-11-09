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
- All joined pieces form a line. A Depot is connected when any piece's centre line is within its loading range (`dropoff_range`, 8.5 m). The line belongs to every team with a living Depot connected to it, replacing per-piece ownership; a line with no connected friendly Depot is unusable until one returns. `assigned_depot` only records who paid.
- The plate on each piece shows power: cyan when a connected Depot has energy, dark without, red for a hostile line.

## Laying track

- Build page, Rail tile: track is laid directly and Depot-paid, not queued as a site plan. The ghost piece follows the cursor; it snaps onto the nearest free end of friendly track within 4 m, otherwise it starts on the tile under the cursor heading the free-placement direction. **R** switches straight, left curve and right curve; **F** turns a free piece a quarter turn; **Esc** or right-click finishes.
- The payer is the pinned stockpile when Pin is set, else the nearest Depot whose territory covers every tile under the piece and that has the iron. Open land only, clear of other track. The first piece must lie in a Depot's loading range; every later piece must join connected track, so there is no floating track.
- R cycles straight, left curve, right curve, left fork and right fork. G changes which end of a fork joins the track, so forks can also merge. F turns a free piece.
- `RailNetwork.place(kind, point, heading, join, pinned)` is the single entry point (`join` is the end that meets the track; `true` lays a curve from its far end); `placement()` gives the transform and snap for previews.

## Trains

- A Train is one self-powered cargo car on two sleds that follow the centre line. Its indicators light as the 300 capacity fills (12 crates).
- A train's position is a piece, a lane and a distance along it. Routes to a Depot pick the shortest connected line to a centre-line point within the Depot's loading radius (`dropoff_range`); the train runs along the sampled line at its speed.
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
- `rail_runtime_check` lays two straights by real clicks (`rail_construction`), and the route and crate suites run on the new fixture.
- Not playtested: the feel of laying curves, train speed over the longer pieces and how the set reads next to the 0.6 vehicles need your eye.
