# Tank Factory model

The Tank Factory is `assets/models/buildings/tank_factory.glb`, wrapped by `scenes/models/tank_factory_model.tscn` and placed in `scenes/gameplay/tank_factory.tscn` in place of the old brown boxes. It is an armoured vehicle plant in the Barracks' style: plated walls, a sloped armour shoulder, corner buttresses and the faction fang black on red. A vehicle is assembled in an open well in the roof under an overhead crane, then driven out of a wide door. There was no concept sheet; the design was agreed in conversation on 2026-11-11. The working file is `Blender/Buildings/TankFactory/TankFactory.blend`, built by the scripts in `Blender/Buildings/TankFactory/build`, which reuse the Barracks' modelling and animation helpers. Costs, health, footprint, production time and the units it makes are unchanged.

The plant is 7.7 x 7.7 m on its 8 x 8 footprint. The roof deck is at 4.05 m, the exhaust stacks reach 5.6 m and the crane 5.9 m. The door faces the default camera (+Z in the game) and is 3.4 m wide with 3.0 m clear. About 25,500 triangles with flat materials only.

## Parts

Separate objects, each with its origin on its pivot. In Blender the door faces -Y, Z up, base on Z = 0.

```
tank_factory_root    on the ground at the centre
  plinth             base slab, ramp and apron, the floodlit bay floor and the glowing ring round the turntable
  frame              corner buttresses, door portal with its red light and hazard jambs, bands
  walls              plated walls, sloped armour shoulder, slot lights, pipes, back hatch
  roof               deck round the open assembly well, hazard trim, red fang panel, crane rails
    roof_fang
  bay_door           roll-up door, origin on its top edge
  turntable          the turntable, which is also the lift
  lift_ram           the lift's ram, one metre long: its Z scale is the lift height
  vehicle            the vehicle being made (an empty), front to -Y
    veh_hull, veh_track_l, veh_track_r, veh_deck, veh_turret
  gantry             overhead crane on the rails, parked over the rear strip
    trolley
      hook_cable     one metre long from its top: its Z scale is the cable length
      hook           hook block with a spreader bar
  vent_01, vent_02   each with vent_fan_0N, turning about its up axis
  stacks             two exhaust stacks on the +X side
    stack_cap_01, stack_cap_02   rain caps on hinges
  tank               fuel tank on the -X side, with tank_fang
  beacon_01, beacon_02   amber beacons on the portal, turning about their up axis
```

One generic vehicle shell (hull, tracks, deck and a turret) stands in for all four units the factory makes: Tank, Motorcycle, Drone and Übermech. It is in a light primer with hot weld seams and a slight glow, so it reads inside the well.

## Clips

All at 24 fps, starting at frame 0, as per-object NLA tracks. The rest pose is the finished plant with the door closed, the lift down, the crane parked and no vehicle.

- **Idle** (4 s, loops): the fans turn, the beacons turn, the stack caps flutter, and the crane drifts on its rails while its trolley shifts. It also closes the door, lowers the lift and clears the vehicle, in case production was cut short.
- **Build** (10 s): plinth, buttresses and portal, turntable, walls with the shoulder, the roof lowered on, the door, the vents, the crane lowered onto its rails, the stacks, the tank and the beacons. Nothing stands before the plinth appears.
- **Produce** (5 s): the lift raises the turntable 2.4 m, up near the roof where the game's camera can see into the well, and turns it side-on (0 to 0.35 s). The hull forms on it (0.3 to 0.7 s). The crane fetches the tracks, the deck and the turret in turn from its park, carries each over the well and lowers it on (0.3 to 2.7 s). The lift sinks back and turns the vehicle to face the door (2.5 to 2.85 s), the door rolls up (2.8 to 3.2 s), the vehicle drives to the door (3.1 to 4.0 s), and the door closes (4.05 to 4.6 s).
- **Die** (5 s): the fuel tank bursts (0.3 s), the door blows out, the crane falls off its rails into the well and the roof caves in (0.5 to 1.1 s). The vents topple, the stacks fall inward onto the wreck, the beacons fall, and the walls and buttresses lean and settle. The wreck holds, then sinks 4.4 m out of sight from 3.7 s.

`assets/models/effects/tank_factory_death_fx.glb` (`scenes/models/tank_factory_death_fx.tscn`) is on Die's timeline: the tank's flash and sparks, sparks where the crane lands, flying scrap that lies where it lands, a dust ring where the roof lands, fire in the hall and at the tank, smoke and an oil pool. The `Flash` mesh's scale drives the light, as in the other death effects.

## In the game

`scripts/components/production_rig.gd` (formerly `barracks_rig.gd`, now shared with the Barracks) plays the clips, with `print_clip` set to `Produce`. The hooks are the Barracks' (docs/BARRACKS_MODEL.md):

- **Construction.** The plan stands the model on the site and scrubs Build by the share of the build done.
- **Production.** `production_building.gd` calls `show_print` with the production progress, so Produce 0 to 4 s is stretched over the production time; at the end the vehicle waits at the open door, also while the exit is blocked. When the unit appears outside it calls `unit_left`, and the door closes at normal speed before the plant idles again.
- **Destruction.** The building is gone at once and its model stays behind as a wreck that plays Die and removes itself.

## Rebuilding

```
blender --background --python Blender/Buildings/TankFactory/build/build_tank_factory.py
blender Blender/Buildings/TankFactory/TankFactory.blend --background --python Blender/Buildings/TankFactory/build/animate_tank_factory.py
blender Blender/Buildings/TankFactory/TankFactory.blend --background --python Blender/Buildings/TankFactory/build/export_tank_factory.py
blender Blender/Buildings/TankFactory/TankFactory.blend --background --python Blender/Buildings/TankFactory/build/render_review.py
```

Always run the first three in order: the saved file keeps the pose the clips leave at frame 0. `render_review.py` also takes `clip:<clip>:<frame>,<frame>...[:<view>]` to render a strip of one clip; the `well` view looks down onto the turntable. Idle's loop is set in `tank_factory.glb.import`. Review renders are in `Blender/Previews/TankFactory`.

## Checks

- `tests/tank_factory_model_test.gd` (headless): the clips and their loop modes, every track starting at frame 0, the site model following construction progress, the size, footprint and door direction, Produce following production with the vehicle raised on the lift while it is assembled, then at the open door as the unit leaves, and the wreck playing Die, sinking out of sight and removing itself.
- `tests/tank_factory_model_runtime_check.gd` (rendered): shots of the site, the finished plant, production, the vehicle at the door, the collapse and the wreck, and a check that the plant is pickable on its roof.

Headless checks are not visual verification.
