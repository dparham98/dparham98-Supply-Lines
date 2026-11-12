# Depot model

The Depot uses the authored tarp warehouse with its tractor unit. The working file is `Blender/Buildings/Depot/Depot.blend`, and only its `depot_warehouse` collection is exported. `assets/models/buildings/depot.glb` rests on the finished warehouse (frame 240) and carries the fold-out as `deploy` and the tractor pull-out as `tractor_exit`, from `Depot_tractor_exit.blend`.

- `scenes/models/depot_model.tscn` places the model at world scale 0.6, the same as the vehicles. It turns the model with the tractor facing east, and centres the tent on the Depot.
- At that scale the tent is about 10 m by 9.3 m and 6.3 m tall, so the Depot footprint is 10 by 10 tiles (`footprint` in `scripts/gameplay/depot.gd`). Depot Trucks need that much empty buildable land to deploy. The tractor and ramp stand outside the footprint, so units can cross them and they do not block building.
- The tractor and ramp carry the `not_selectable` metadata, so selection outlines and clicks use the tent only.
- `dropoff_range` is now 8.5 m. As before, it reaches every cell around the footprint, including the corners.
- Crates are set down from the footprint's shorter side outward.
- Team colour on the tarp and tractor is left as authored; the Depot had no team colouring before this.
- The previous prototype stays at `scenes/models/depot_prototype.tscn` and is no longer used by the Depot.
- Check: `tests/depot_model_runtime_check.gd` (the tent is on the ground, inside the footprint and pickable; the tractor is not pickable).

## Depot Truck and crates

The same Blender file supplies the truck and the crate.

- **Truck:** `assets/models/units/depot_truck.glb` is frame 1 of the file, without the parts still scaled to nothing. `scenes/models/depot_truck_model.tscn` places it at world scale 0.6, about 15.3 m by 3.1 m, centred on the unit. All eight wheels roll and the front two steer through `vehicle_rig.gd`. Its selection ring is sized to that length. Units still path as one tile, so this long model can overlap things when turning.
- **Crate:** `assets/models/props/supply_crate.glb` is one of the authored crates, used by `scenes/gameplay/supply_crate.tscn`. It is at scale 0.4, not 0.6, because each crate has to fit its one tile. The coloured resource band sits on its middle strap.
- **Deploy:** `DepotNetwork.deploy_truck` rounds the truck's heading to the nearest 90 degrees and turns the Depot's `Visuals` to match. `scripts/components/depot_rig.gd` moves the closed truck from where it stood onto the site in 1.2 s (`line_up_seconds`), then plays `deploy`, which takes 10 s. Footprints are square, so the heading does not change which tiles are used. Depots built by infantry or authored on maps skip the fold-out and face east as before.
- **The Depot works from the start of the fold-out.** Deploying was already instant, and that has not changed.
- Parts at zero scale are left out of selection (`scripts/units/selection_bounds.gd`).

## Depot Truck production

A Depot Truck takes the length of both clips, about 14.2 s. Other Depot jobs still take `print_seconds`.

- The tractor backs out and parks beside the Depot (`tractor_exit`, 6.25 s). The trailer is then built behind it (`assemble`, 7.9 s, from `Depot_truck_assemble.blend`, stored on `depot_truck.glb`).
- Depot progress poses the clips directly (`show_truck` in `depot_rig.gd`).
- `TruckAssembly` in `depot_model.tscn` is placed where `tractor_exit` ends. The finished truck replaces it on the same spot, and the Depot then has no tractor. One appears at home when the next truck starts.
- Before starting, all the ground in `truck_side`, about 15 m by 3 m beside the Depot, must be free. If not, the job waits with "Exit blocked · waiting". Those tiles are reserved during the build, so units path around them. Terrain counts, so a Depot built against forest or water on that side cannot build trucks.
- A truck will not start until the Depot has finished unfolding.
- The Cancel tile on a Depot cancels the job in progress for a full refund. A truck plays its animation backwards at `cancel_speed`, 2x by default, and the tractor ends at home.
- Capturing the Depot cancels the queue without a refund, as before, and resets the tractor to home.
- `depot_truck_drive.blend` is not used. `vehicle_rig.gd` rolls the wheels from real ground speed.
- Checks: `tests/depot_truck_model_test.gd` and `tests/depot_truck_model_runtime_check.gd`.

## Destruction

A destroyed Depot or Depot Truck is gone at once, so it cannot be selected or targeted, and its model stays behind as a wreck that plays its death and removes itself, as the other buildings and units do.

- **Depot (6 s):**
  - The stored crates go up (0.35 s): a fireball bursts out through the roof, which heaves up on the blast.
  - Both roof halves sag in about their eaves and drop onto the floor; the ridge and rafters crash down after them.
  - The front end wall falls in, and the back one topples out over the ramp. The outer floor wings tip down, and the eave rails come down onto them.
  - The top crate of each stack is thrown clear and lands beside the Depot; the rest jolt askew. Shreds of tarp flutter down.
  - The stock and the fallen canvas burn under a column of smoke and embers, over a scorched patch of ground. The roof burns down to its frame.
  - The tractor's lights go out. The wreck sinks out of sight from 4.3 s.
- **Depot Truck (5 s):**
  - The tractor's fuel goes up (0.3 s), with a fireball out of the top of the cab.
  - The tractor bucks nose high and comes down slewed and nose first, with both front wheels thrown off to lie flat beside it.
  - The trailer jackknifes, then rolls over onto its side. Panels are thrown off the tractor.
  - The tractor and then the trailer's load burn, with smoke and an oil pool. The wreck sinks out of sight from 3.6 s.
- **How it is made:**
  - `depot.glb` and `depot_truck.glb` hold clips assembled from three working files, so they are not re-exported to add a death. Instead, as with the Tank's deaths, each death is an effect file holding stand-ins named `Drive_<part>`, nested as the parts are.
  - Their rest pose is the part's own: the finished warehouse (frame 240) for the Depot, the closed truck (frame 1) for the truck. `scripts/components/driven_death.gd` copies their keyed transforms onto the real parts each frame, so a death starts exactly where the model stands.
  - `Drive_Scorch`'s scale is how burnt the model looks, through `assets/materials/tank_scorch.tres` over every mesh.
  - Fire, smoke and debris are ordinary keyed meshes, as in the other death effects.
- **Files:**
  - Effect scenes: `assets/models/effects/depot_death_fx.glb` and `depot_truck_death_fx.glb`, wrapped by `scenes/models/depot_death_fx.tscn` and `depot_truck_death_fx.tscn`.
  - Hooks: `death_scene` on `depot_rig.gd` and `vehicle_rig.gd`. The cargo truck has none, so it is unchanged.
  - Working files: `Blender/Buildings/Depot/DepotDeath.blend` and `DepotTruckDeath.blend`, built by `Blender/Buildings/Depot/build/build_depot_death.py` from `Depot.blend`, which it only reads. Each death has its own file because both sets of stand-ins are named after the same parts.
- **What stops when the Depot dies:**
  - The fold-out, the tractor pulling out and the truck being built all stop where they are, and a truck half built disappears.
  - The tractor is not moved by the death (`held_parts`), since it may be away building a truck; it goes down with the wreck where it stands.
  - Only the Depot's own parts are driven (`parts_path`), not the truck being built, which has parts of the same names.
- **Checks:**
  - `tests/depot_death_test.gd` (headless):
    - Each wreck stays behind and is removed from selection and targeting.
    - Every driven part starts on its own pose.
    - The Depot: the ridge and roof fall, and the tractor stays put.
    - The truck: the trailer rolls over and a front wheel is thrown.
    - Both are scorched, sink and remove themselves.
  - `tests/depot_death_runtime_check.gd` (rendered): shots of each death held at the blast, the collapse, the burning and the sinking.
