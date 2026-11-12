# Barracks build prompt

Build the Barracks from `Blender/References/Barracks_concept.webp`: an armoured print hall where the faction's cyborgs are printed, then walk out of a single bay door. Animate its construction, its production and its destruction, and put it in the game in place of `scenes/models/barracks_placeholder.tscn`. This is an art and animation job: costs, health, footprint, production times and rules stay as they are.

Read `AGENTS.md`, `Blender/README.md`, `docs/DEPOT_MODEL.md` and `docs/MOTORCYCLE_MODEL.md` first. The Motorcycle is the closest example of a script-built model, and the Depot is the closest example of a building with clips.

## Ground rules

- Working file: `Blender/Buildings/Barracks/Barracks.blend`, made by the scripts in `Blender/Buildings/Barracks/build`. Change the scripts and re-run them instead of editing by hand. Previews go in `Blender/Previews/Barracks`. Set `save_version = 0` so no `.blend1` appears.
- Run Blender in the background, not through the Blender MCP tools, so the user's open Blender window is never touched:

```
"C:\Program Files\Blender Foundation\Blender 4.5\blender.exe" --background --python <script> -- <args>
```

- Gameplay scripts must not create visuals at runtime. Everything is authored in Blender or a saved scene.
- No real-world insignia. Use the `faction_fang` mesh from `Blender/Vehicles/Drone/Drone.blend` for the emblems, not the sheet's drawing.

## How to read the sheet

The sheet sets the shape, palette and character. Where it is unclear or disagrees with the game, use these:

- **Stats.** The sheet's power, iron and build-time numbers are art only. The game keeps 100 energy and 45 iron, and its own construction and print times.
- **Power.** "Requires power to operate" is not a mechanic. Production still draws on the Barracks' assigned Depot.
- **Vents.** The views disagree. Build four round exhaust vents in a 2 x 2 block, as in the TOP VIEW, with fans that turn.
- **Weathering.** Keep the riveted plates, bands, chamfered pillars and pipes as geometry. Rust, hazard stripes and the red panels are flat colour areas, with no image textures, so the hall sits with the Depot and the units.
- **Door.** One roll-up bay door, about 2.4 m tall, so a 1.8 m cyborg clearly fits. In the game it faces the default camera (+Z), so production is seen.
- **Top view.** This is what players see most. The long glowing skylight over the print cradle and the red roof panel with the fang must read at the game's camera distance.

## The model

True scale in metres, front (the bay door) facing -Y, Z up, base on Z = 0. The game footprint is 6 x 6 m, so the hall fills about 5.8 x 5.8 m. Keep it low and wide as on the sheet: walls to about 2.4 m, a sloped armour shoulder up to the roof deck, the skylight under 4 m, below the 6.3 m Depot tent. The mast may rise higher. Budget about 20,000 triangles with flat PBR materials.

**Palette.** Dark olive and gunmetal armour, oxblood-red panels, brass and copper pipes, black and yellow hazard stripes. Red glow in the slot lights and mast light, and amber glow in the print cradle. Keep emission below the point where it clips to white in Godot.

Separate named objects, each with its origin on its pivot:

```
barracks_root            empty on the ground at the centre
  plinth                 base slab and door ramp
  frame                  chamfered corner pillars and bands
  walls                  plated walls, slot lights, pipes on the walls
  roof                   roof plates, the red fang panel, the skylight frame
  skylight               the glass
  bay_door               roll-up door, origin at its top edge
  cradle                 the print cradle frame and its glow
  print_head             bar that sweeps up the cradle while printing
  print_figure           the figure being printed, origin at its feet
  vent_01 .. vent_04     exhaust housings, each with vent_fan_0N turning about Z
  mast                   comms mast, with mast_light
  tank                   coolant tank, its fang and its pipes
```

## Clips

All clips start at frame 0 at 24 fps, as NLA tracks per object.

- **Idle** (loop): fans turn, the mast light blinks, the cradle glow breathes.
- **Build:** the hall goes up from nothing to finished: plinth, pillars, walls, roof, then the vents, mast and tank. The game scrubs it by construction progress, so every frame must look like a building site, not a broken building.
- **Print:** the print head sweeps up as the figure forms in the glowing cradle. Then the bay door rolls up and closes. The game scales it to the print time.
- **Die:** about 5 s. The roof caves into the hall, the walls lean, the tank bursts and the vents topple. Hold the wreck, then sink it fully out of sight so it removes itself. Smoke, fire, sparks, scrap and spreading oil go in a separate effect GLB on the same timeline, `assets/models/effects/barracks_death_fx.glb`, in the pattern of `scenes/models/motorcycle_death_fx.tscn`.

The exported rest pose is the finished hall with the door closed and the cradle empty.

## The game

- Export to `assets/models/buildings/barracks.glb` (glTF Binary, +Y up, apply modifiers, animations as NLA tracks, no cameras or lights). Add `scenes/models/barracks_model.tscn` with a small rig script that plays Idle, follows production with Print, follows construction with Build, and plays Die.
- The construction plan shows the model rising with its progress, and the finished Barracks plays Print while a unit is in production, with the door opening as the unit leaves.
- When the Barracks is destroyed it leaves the model behind to play Die, as units leave their corpses, so it cannot be selected or targeted.

## Checks

Add `tests/barracks_model_test.gd` (headless): the model fits the footprint and faces the right way, the clips exist and start at frame 0, construction progress scrubs Build, production plays Print, and a destroyed Barracks leaves a wreck that removes itself. Also run `production_batch_test`, `pending_construction_test` and the other construction and production tests.

Render it in Godot at the game's camera distance and close up: building, finished, printing and dying. Save that to `Blender/Previews/Barracks/animation_ingame.png` and look at it. Headless checks never count as visual verification.

## Finish

Work on a `feature/barracks-model` branch. Add a Barracks entry to `Blender/README.md` and write `docs/BARRACKS_MODEL.md`. Open a draft PR, and never merge without the user's approval.

Out of scope: costs and stats, a power mechanic, Tank Factory, Generator and Iron Mine models.
