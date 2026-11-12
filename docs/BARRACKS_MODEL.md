# Barracks model

The Barracks is `assets/models/buildings/barracks.glb`, wrapped by `scenes/models/barracks_model.tscn` and placed in `scenes/gameplay/barracks.tscn` in place of the old blue boxes. It is an armoured print hall where cyborgs are printed in a glowing cradle and walk out of one bay door. The working file is `Blender/Buildings/Barracks/Barracks.blend`, built from `Blender/References/Barracks_concept.webp` by the scripts in `Blender/Buildings/Barracks/build` (see `PROMPT.md` there). Costs, health, footprint, print time and rules are unchanged; the sheet's stats are art only and there is no power mechanic.

The hall is 5.8 x 6.0 m on its 6 x 6 footprint and 3.8 m to the top of the skylight; the comms mast reaches 6.4 m. About 21,700 triangles with flat materials only. The bay door faces the default camera (+Z in the game) and is 2.4 m tall.

## Parts

Separate objects, each with its origin on its pivot. In Blender the door faces -Y, Z up, base on Z = 0.

```
barracks_root        on the ground at the centre
  plinth             base slab, door ramp, interior floor with the amber glow under the skylight
  frame              corner buttresses, door portal, bands
  walls              plated walls, sloped armour shoulder, slot lights, pipes, back hatch
  roof               deck, red fang panel, skylight frame
    roof_fang, skylight (the glass)
  bay_door           roll-up door, origin on its top edge
  cradle             print cradle
    print_head       ring that sweeps up while printing
    print_figure     the figure being printed, origin at its feet
  vent_01 .. vent_04 each with vent_fan_0N, turning about its up axis
  mast               comms mast on its turret
    mast_light
  tank               coolant tank, pipes and saddles
    tank_fang
```

The faction fang is the Drone's `faction_fang` mesh, black on red as on the sheet. The vents are a 2 x 2 block, as in the sheet's top view.

## Clips

All at 24 fps, starting at frame 0, as per-object NLA tracks. The rest pose is the finished hall with the door closed and the cradle empty.

- **Idle** (4 s, loops): the fans turn, the mast light blinks, the print head hovers. It also closes the door and empties the cradle, in case a print was cut short.
- **Build** (10 s): plinth, buttresses and portal, cradle, walls with the shoulder, the roof lowered on, the door, the vents, the tank, the mast. Before its first part appears nothing stands.
- **Print** (5 s): the head sweeps up as the figure forms (0 to 2.6 s), the door rolls up (2.85 to 3.25 s), the figure walks to the door (3.15 to 4.0 s), and the door closes (4.05 to 4.6 s).
- **Die** (5 s): the tank bursts (0.3 s), the door blows out, the roof caves into the hall (0.5 to 1.05 s), the vents topple, the mast falls against the shoulder, the walls and buttresses lean and settle. The wreck holds, then sinks 3.7 m out of sight from 3.7 s.

`assets/models/effects/barracks_death_fx.glb` (`scenes/models/barracks_death_fx.tscn`) is on Die's timeline: the tank's flash and sparks, flying scrap that lies where it lands, skylight glass, a dust ring where the roof lands, fire in the hall and at the tank, smoke and an oil pool. The `Flash` mesh's scale drives the light, as in the other death effects.

## In the game

`scripts/components/production_rig.gd` on the model scene's root plays the clips:

- **Construction.** `construction_plan.gd` stands the building's own model scene on the site when that model has `show_construction`, and scrubs Build by the share of the build done (materials built in and energy paid). `depot_network.gd` puts the model scene in the plan's spec. Other buildings still show only the grid.
- **Production.** `production_building.gd` calls `show_print` with the print progress, so Print 0 to 4 s is stretched over the print time; at the end the figure waits at the open door, also while the exit is blocked. When the unit appears outside it calls `unit_left`, and the door closes at normal speed before the hall idles again. If the next unit is already printing then, the cradle catches up once the door has closed. With nothing queued, or no friendly Depot, it calls `show_idle`.
- **Destruction.** `production_building.take_damage` leaves the model behind to play Die, as units leave their corpses: the building is gone at once, so the wreck cannot be selected or targeted. The wreck removes itself when Die ends.

Other production buildings call the same hooks only if their model has them, so their placeholders are untouched.

## Rebuilding

```
blender --background --python Blender/Buildings/Barracks/build/build_barracks.py
blender Blender/Buildings/Barracks/Barracks.blend --background --python Blender/Buildings/Barracks/build/animate_barracks.py
blender Blender/Buildings/Barracks/Barracks.blend --background --python Blender/Buildings/Barracks/build/export_barracks.py
blender Blender/Buildings/Barracks/Barracks.blend --background --python Blender/Buildings/Barracks/build/render_review.py
```

Always run all three in order: the saved file keeps the pose the clips leave at frame 0. The exported rest pose is each part's top clip at frame 0 (Die), so Die starts exactly at rest. `render_review.py` also takes `clip:<clip>:<frame>,<frame>...` to render a strip of one clip. Idle's loop is set in `barracks.glb.import`.

## Checks

`tests/barracks_model_test.gd` (headless): the clips and their loop modes, every track starting at frame 0, the site model following construction progress, the size, footprint and door direction, Print following production with the door opening as the unit leaves, and the wreck playing Die, sinking out of sight and removing itself. Headless checks are not visual verification.
