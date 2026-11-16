# Four worker and truck stalls

Four places where a worker or a Cargo truck stopped, or went the wrong way, without the player being able to see why. They were found by the opening simulation for the economy report (draft PR #66). No price, rate, capacity or range is changed. Nobody has played these changes.

## 1. A builder no longer blocks its own site

- **Before.** A plan claims no ground until it is built, so a unit can stand on it. An Infantry told to build while standing on the footprint started work at once, and the site then waited for good on "Waiting for footprint to clear". The builder was the thing in the way.
- **Why it happened.** The walk to a site picked a standing cell within building reach, and cells on the unbuilt footprint counted. So builders were often routed onto the very site they were to build.
- **Now.** Builders are routed to the nearest open cell within building reach that is off the footprint, so they never walk onto it. A builder already standing on it (placed there, or the plan laid under it) is routed off the same way before it works. Its state reads "Stepping off the build site". If there is no such cell it reads "No room beside the build site" and looks again each second.
- Carried materials are still set down on the site first.
- Other units standing on a footprint are not moved. Only the builder is.

Code: `unit_agent.gd` `_construct()` and `_route_to_standing()`; `interaction_approach.gd` `path()` takes the cells to keep off.

## 2. Workers deliver to the nearest stockpile unless one is chosen

- **Before.** A worker kept the last stockpile it delivered to. An Infantry moved from the mine to the trees went on carrying wood back to the Depot by the mine, past the one that needed it.
- **Now.** A worker whose drop-off the player did not choose picks the nearest stockpile that can receive at the start of each trip home. The choice is made once a trip, so it does not change halfway.
- **Chosen drop-offs are unchanged.** Right-clicking a Depot, a deployed Cargo vehicle or a crate still pins it, and the worker keeps to it through later Gather orders. That is how a drop-off is chosen for gathering (right-click the stockpile, then the resource), so a pin is not dropped by a new Gather order. To unpin, use the Return card or right-click another stockpile.
- A full stockpile is still not skipped: the worker waits there with its load, as before.
- The Return card sends a worker to the nearest Depot now. It no longer pins that Depot for later trips.

Code: `unit_agent.gd` `_head_home()`, used wherever a gathering worker turns for home; `skirmish_hud.gd` `return_units()`.

## 3. Unload at a Depot also empties loose cargo

- **Before.** Workers can deliver loose iron, wood or coal into a deployed Cargo truck. Unload at a Depot only handled crates, so nothing could move that loose cargo into a Depot.
- **Now.** Unload at a Depot also moves the vehicle's loose cargo across, as far as the Depot has room. What does not fit stays aboard, and the state line says so: "Unloaded 1 crate and 55 loose", "20 loose retained, no space".
- **Deployed vehicles take only crates.** Unload at a deployed Cargo vehicle moves crates as before and leaves loose cargo aboard, so the deployed vehicle's small shared space stays free for what its own workers deliver.
- Right-clicking a Depot with only loose cargo aboard now unloads. It used to load. If the truck has a manifest set, it loads the manifest's crates straight after, so the right-click still fetches them.
- Crates, trips, manifests and unloading onto a build site are unchanged.

This makes a truck usable as a collection point: deploy it beside a mine, let workers fill it, then Unload at the Depot.

Code: `cargo_vehicle.gd` `unload_crates()`, `command_return()`, the state line in `_crate_job()`.

## 4. Coal diggers cut their own way in

- **Before.** A worker sent to coal behind uncut forest reported "Coal unreachable" and stood still. Once a way was cut by hand, it dug the one cell it could reach from the corridor's end (50 coal), was handed a next cell behind more trees, and stopped again.
- **Now.** When no open path leads to the coal, the worker fells the tree in its way, carries the wood home, and goes back to the coal. It does this one tree at a time until it can dig, and again whenever the next cell of the field is behind trees.
- **Which trees.** The fewest Forest cells that let it stand within its 4 m reach of any coal left in that field, and among those the shortest walk. On the balanced map that is 9 cells for a side field and 12 for a contested one, the same counts `docs/BALANCED_MAP.md` gives.
- **Where it digs.** The coal it was sent to if that is in reach from where the way comes out, otherwise the nearest coal of the same field.
- **What is unchanged.** The time it takes: each tree is still 20 wood and two trips. Only the orders are saved. Coal cells still cannot be walked on, and a field with no way through forest (walled by rock or water) still reads "Coal unreachable".
- **Calling it off.** Any other order drops the coal the worker was cutting towards.
- **A tree it cannot reach.** If something stands in the only place beside the next tree, the worker works the way out again towards the coal. When that tree is still the best way in, it waits and looks again every 3 s, rather than retrying the tree every second. Its state reads "Coal unreachable" meanwhile.
- **Two workers, one corridor.** A cell another unit stands on counts as closed. A second worker that finds the only standing place taken fells itself a place beside it. Passing traffic can, rarely, cause a tree to be felled that a moment's wait would have spared.

The rule in `docs/BALANCED_MAP.md` that coal inside uncut forest is refused is replaced by this. `tests/coal_gathering_test.gd` checked the refusal; it now checks that the worker sets out to fell and that another order calls it off.

Code: `scripts/terrain/coal_approach.gd` (the search; it changes nothing on the map), `unit_agent.gd` `_cut_way_in()`, `_source_left()` and the `_dig_source` it returns to. The search covers the field and 32 cells round it, and took 8 to 18 ms a call on the development machine. It runs once for each tree felled, and every 3 s for a worker with no way in. A worker starting outside that ground tries up to 3 entry points, each a whole-map path search.

## Checks

- `tests/stall_fixes_test.gd` (headless, balanced map) covers all four:
  - the builder stepping off and the Generator being built and paid for once, and a builder sent from off the site never setting foot on the footprint;
  - deliveries moving to a nearer Depot, and staying with a pinned one;
  - loose cargo unloading, a partial unload, the right-click, and a worker filling a deployed truck that then unloads at the Depot; a deployed truck taking only crates, and a right-click with a manifest unloading and then loading;
  - a worker cutting the planned trees, delivering their wood, digging past the first cell, conserving coal, dropping the dig on another order, and an empty field giving no way.
- Each part was run with its fix switched off and failed at its own check.
- `tests/coal_gathering_test.gd` was updated as described above.
- Not rendered and not played. How it reads on screen, and whether a worker felling trees unasked feels right, need your eye.
