# Vehicle fuel validation

These checks ran on Godot 4.7.2.stable.official.ed1daf0bf on Windows 11 (NVIDIA GeForce RTX 5070 Ti) on 2026-10-28. The branch is `feature/vehicle-fuel`, based on `infra/cloud-dev-setup` at 7c2044a.

## Headless runner (`ci/run_headless_checks.sh`)

- Import, main-scene startup and all 28 suites passed: the 27 existing suites plus the new `vehicle_fuel_test`.
- The 4 required result files were written and the checkout stayed clean.
- No existing test file was modified (`git diff 7c2044a -- tests/` shows only the two new scripts and their `.uid` files).

`vehicle_fuel_test` covers:

- The skirmish fuel switch, and the testing coal pile being reachable and delivered by the starting Infantry without loss.
- Authored vehicles starting full, and the Drone staying exempt.
- No fuel burned while idle.
- Burn matching distance moved × rate, to within 0.01.
- Exhaustion: the vehicle stops in place with its order kept.
- Refuel rate and whole-unit withdrawals, and the paused order resuming on a partial tank once the source runs dry.
- Auto-refuel off leaving coal untouched.
- A pinned source used exclusively, with no fallback or borrowing from a nearby deployed truck; nearest-source selection after unpinning.
- A truck never refuelling from its own cargo, and `spend_local` never touching tank fuel.
- A stranded tank out of range staying empty, then being refuelled in place by a deployed truck.
- Enemy sources ignored.
- HUD: the LOW FUEL readout, toggle visibility and toggle action, including the Supply panel toggle for Cargo vehicles.
- A Depot-produced vehicle starting empty, then refuelling at its Depot with coal conserved.
- Earlier exercise scenes keeping fuel off.
- The train round-trip estimate warning while still accepting the route.

## Rendered checks (windowed, Vulkan)

- `fuel_runtime_check` passed. Real mouse clicks select a low-fuel Tank and toggle Auto-refuel off and back on, then refuelling is checked against the Depot's coal. A real click also toggles a Cargo Truck's Supply panel button. The screenshots `fuel_low`, `fuel_auto_off`, `fuel_refuelling` and `fuel_truck_toggle` (1280×900) were inspected: the HUD shows fuel, LOW FUEL, the source and the toggle state.
- The existing runtime checks all passed except `mobile_supply_runtime_check`: bottom_hud, combat, depot, engineering, generator, harvesting, production_batch, rail, storage, supply and terrain_abilities.
- `mobile_supply_runtime_check` fails at "Pile gather GUI did not stockpile materials". It fails the same way, twice, on a clean 7c2044a clone, so the failure predates this branch and is not caused by it.

## Not verified

- First human playtest (2026-10-28): every scenario worked. It found the missing Cargo/Train toggle (fixed) and awkward Cargo Truck coal loading (open). The toggle fix still needs a human re-check.
- The terrain rebuild/MultiMesh issue is unrelated and still open.
