# Generator model

The Generator is `assets/models/buildings/generator.glb`, wrapped by `scenes/models/generator_model.tscn` and placed in `scenes/gameplay/energy_generator.tscn` in place of the old teal box and cylinder. It is a compact armoured steam generator in the Barracks' and Tank Factory's style: plated olive and gunmetal, copper and brass trim, a hazard-striped plinth and the faction fang black on red. There was no concept sheet; the design was agreed in conversation on 2026-11-12. The working file is `Blender/Buildings/Generator/Generator.blend`, built by the scripts in `Blender/Buildings/Generator/build`, which reuse the Barracks' modelling and animation helpers. Costs, health, footprint and the fuel rules are unchanged.

The generator is 2.9 x 2.9 m on its 3 x 3 footprint. The boiler's top is at 2.45 m and the chimney reaches 4.1 m. The fire door faces the default camera (+Z in the game). About 10,000 triangles with flat materials only.

## Parts

Separate objects, each with its origin on its pivot. In Blender the fire door faces -Y, Z up, base on Z = 0.

```
generator_root     on the ground at the centre
  plinth           base slab, hazard stripe, flywheel pit cover
  firebox          plated furnace with a grated fire door, ash drawer and boiler saddles
    fire_glow      the fire behind the grate, scaled away while cold
    pilot          the amber pilot lamp beside the door
  boiler           riveted drum with copper bands, pressure gauge on the front cap, steam pipe to the dynamo
    gauge_needle   turns about the gauge's axis
    valve          the safety valve and its weighted lever
  chimney          stack with copper bands and guy wires
    chimney_cap    rain cap on a hinge
    puff_1..3      smoke puffs, shown only while it runs
  hopper           fuel hopper heaped with coal, a chute into the firebox, a red panel
    hopper_fang
  dynamo           copper-wound dynamo on its base, insulators and spark terminals
    coil_glow      the coils lit while it runs
    arc            the spark between the terminals
  flywheel         spoked flywheel with a hazard ring and the crank, turning about X
  crosshead        the crosshead and piston rod, sliding along Y
  con_rod          connecting rod from the crosshead to the crank pin
  cylinder         steam cylinder on its slide bars, with the steam pipe from the boiler
  mast             power mast with porcelain insulators and cables down to the dynamo
```

## Clips

All at 24 fps, starting at frame 0, as per-object NLA tracks. The rest pose is the finished generator standing still, with the fire lit.

- **Idle** (4 s, loops): cold. Only the pilot lamp flickers; the fire is out, the coils are dark, nothing moves and the gauge reads low.
- **Run** (2 s, loops): the flywheel turns twice and drives the piston through the crank and rod, the fire flickers behind the grate, the coils glow, the spark crackles between the terminals, smoke puffs rise from the chimney and the rain cap rattles on them, and once a loop the safety valve lifts and the gauge needle kicks.
- **Build** (10 s): plinth, firebox, hopper, the boiler lowered onto its saddles, chimney, dynamo, flywheel, cylinder, crosshead and rod, mast, then the pilot lamp lights. Nothing stands before the plinth appears.
- **Die** (5 s): the gauge swings to the stop, the valve blows and the spark arcs, then the boiler bursts (0.35 s), heaves up and drops askew. The chimney topples off to the side, the flywheel breaks loose, rolls off the front and falls flat, the hopper tips over, the mast falls back and the rod and cylinder are thrown down. The wreck burns, then sinks 4.8 m out of sight from 3.7 s.

`assets/models/effects/generator_death_fx.glb` (`scenes/models/generator_death_fx.tscn`) is on Die's timeline: the boiler's flash and sparks, blue sparks off the dynamo, a burst of steam, boiler plates thrown out to lie where they land, coal spilled from the hopper, fire licking out of the burst boiler, smoke and an oil pool. The `Flash` mesh's scale drives the light, as in the other death effects; after the burst the flash sits inside the firebox, so only its light shows.

## In the game

`scripts/components/generator_rig.gd` plays the clips:

- **Construction.** `DepotNetwork.plan_spec` now gives the Generator's plan the model in the scene's Visuals slot, so its site stands the model up and scrubs Build by the share of the build done, as for the Barracks.
- **Running.** `energy_generator.gd` calls `show_running` with `active()` whenever it updates its label, so the model runs while it can burn fuel into its Depot and stands cold when it is out of fuel, out of storage, paused or cut off from its Depot. The switch blends over 0.3 s.
- **Destruction.** The building is gone at once and its model stays behind, in the building's parent, as a wreck that plays Die and removes itself.

The export keeps constant channels (`export_optimize_animation_keep_anim_object`), because Idle and Build hold the glows hidden with keys that never change, and a dropped channel would leave them at the rest pose.

## Rebuilding

```
blender --background --python Blender/Buildings/Generator/build/build_generator.py
blender Blender/Buildings/Generator/Generator.blend --background --python Blender/Buildings/Generator/build/animate_generator.py
blender Blender/Buildings/Generator/Generator.blend --background --python Blender/Buildings/Generator/build/export_generator.py
blender Blender/Buildings/Generator/Generator.blend --background --python Blender/Buildings/Generator/build/render_review.py
```

Always run the first three in order: the saved file keeps the pose the clips leave at frame 0. `render_review.py` also takes `clip:<clip>:<frame>,<frame>...[:<view>]` to render a strip of one clip; the `door` view is close on the fire door and the `engine` view on the flywheel side. Idle's and Run's loops are set in `generator.glb.import`. Review renders are in `Blender/Previews/Generator`.

## Checks

- `tests/generator_model_test.gd` (headless): the clips and their loop modes, every track starting at frame 0, the site model following construction progress, the size, footprint and door direction, the model standing cold without fuel and running with it (flywheel turning, piston moving, fire and coils lit), going cold again when the fuel runs out, and the wreck playing Die, ignoring the running switch, sinking out of sight and removing itself.
- `tests/generator_model_runtime_check.gd` (rendered): shots of the site, the generator cold and running, the collapse and the wreck, and a check that the generator is pickable on its boiler.

Headless checks are not visual verification.
