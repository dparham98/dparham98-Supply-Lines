# Maglev tracks and trains

Rails are no longer one-tile squares. The network is built from the authored maglev set in `Blender/Vehicles/Maglev/MaglevTracks.blend` and `MaglevTrain.blend`: a straight piece, a 90-degree curve, an engine and a cargo car, all at the world scale 0.6 used for every authored vehicle (see the backlog's art section). This replaces the tile rules in [RAIL_BATCH.md](RAIL_BATCH.md); routes, loading and Depot ownership work as before.

## Pieces

| Piece | Authored | In game (0.6) | Cost (2 iron per metre) |
| --- | --- | --- | --- |
| Straight | 8 m long, 5 m wide | 4.8 m long, 3 m wide | 10 iron |
| Curve | radius 20 m, quarter turn | radius 12 m, arc 18.85 m | 38 iron |

- A piece's centre line runs from end 0 to end 1; each end has an outward heading. Pieces connect where an end meets another piece's end head-on (within 5 cm, headings opposed). The curve bends toward its local +X, the left of its travel; laid mirrored it is traversed from end 1 and bends right.
- Each piece marks the tiles whose centres lie within half the track width of its centre line, so buildings and plans keep off (`is_footprint_valid` still refuses tiles carrying `rail`). Ground units cross tracks freely.
- A piece belongs to the Depot that paid for it. Capturing or losing that Depot makes its pieces unusable, exactly as the old tiles did; the field surfaces recolour.

## Laying track

- Build page, Rail tile: track is laid directly and Depot-paid, not queued as a site plan. The ghost piece follows the cursor; it snaps onto the nearest free end of friendly track within 4 m, otherwise it starts on the tile under the cursor heading the free-placement direction. **R** switches straight, left curve and right curve; **F** turns a free piece a quarter turn; **Esc** or right-click finishes.
- The payer is the pinned stockpile when Pin is set, else the nearest Depot whose territory covers every tile under the piece and that has the iron. Open land only, clear of other track.
- `RailNetwork.place(kind, point, heading, mirrored, pinned)` is the single entry point; `placement()` gives the transform and snap for previews.

## Trains

- A Train is an engine and three cargo cars. Each car rides on two sleds that follow the centre line, and the body bridges them, so the consist bends through curves. Cargo car indicators light one car at a time as the 300 capacity fills (4 crate slots per car).
- A train's position is a piece and a distance along it. Routes to a Depot pick the shortest connected line to a centre-line point within the Depot's loading radius (`dropoff_range`); the train runs along the sampled line at its speed and burns fuel by distance. Trains print at the paying Depot's loading stop.
- Trains take no part in ground occupancy; ground traffic does not block them and they do not block it. A train whose piece stops being friendly pauses with its cargo, as before.

## Code

- `scripts/rails/track_piece.gd`, `scenes/gameplay/track_straight.tscn`, `track_curve.tscn`: geometry (`point_at`, `tangent_at`, `ends`, `nearest`), tile marking, ownership colour.
- `scripts/rails/rail_network.gd`: registration, connections, free ends, reachability and chains, sampled lines (`line`, `line_to_depot`, `spawn_stop`), placement, payment, the ghost preview (`RailPreview` in the skirmish map).
- `scripts/rails/rail_line.gd` (`RailLine`): point and tangent along a sampled line.
- `scripts/rails/train.gd`: track position, line following, routing to Depot stops, consist placement; `scripts/rails/train_consist.gd` on `scenes/models/train_model.tscn` places engine and cars.
- Fixtures: `rail_exercise.tscn` lays seven straights along z=156.5 from the Depot to EastDepot; `remote_routes_exercise.tscn` leaves out the centre piece.

## Validation

- `tests/rail_batch_test.gd`: geometry and costs, head-on joins and free ends, tile marking, snapped laying and payment, refusals, left and mirrored curve exits, train print at a stop, cutting and restoring the centre piece, running the train to EastDepot with its consist on the line, ownership loss.
- `rail_runtime_check` lays two straights by real clicks (`rail_construction`), and the route and crate suites run on the new fixture.
- Not playtested: the feel of laying curves, train speed over the longer pieces and how the set reads next to the 0.6 vehicles need your eye.
