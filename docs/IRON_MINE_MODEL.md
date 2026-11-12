# Iron Mine model

The Iron Mine is `assets/models/buildings/iron_mine.glb`, wrapped by `scenes/models/iron_mine_model.tscn` and placed in `scenes/gameplay/iron_mine.tscn` in place of the old box-and-beam placeholder. It is a small pithead over a mine shaft: a riveted steel headframe with a winding wheel, a skip that hoists ore out of the shaft and tips it down a chute into an ore bin, a winch house with its drum, and a work lamp. The mine is shared infrastructure that any player's Infantry can mine, so it wears no faction colours: weathered steel, concrete, rust, planking and yellow-and-black hazard paint. There was no concept sheet; the design was agreed in conversation on 2026-11-12. The working file is `Blender/Buildings/IronMine/IronMine.blend`, built by the scripts in `Blender/Buildings/IronMine/build`, which reuse the Barracks' modelling and animation helpers. Costs, health, footprint, reserves and the sharing rules are unchanged.

The mine is 1.9 x 1.9 m on its 2 x 2 footprint, and the winding wheel's top is at 3.85 m. The ore bin, the lamp and the skip's tipping side face the default camera (+Z in the game). About 6,700 triangles with flat materials only.

## Parts

Separate objects, each with its origin on its pivot. In Blender the front faces -Y, Z up, base on Z = 0.

```
mine_root        on the ground at the centre
  collar         concrete slab round the shaft, a raised hazard-striped lip, the dark shaft mouth, leg footings
  headframe      four legs leaning toward the winch, ring girders, X braces, guide rails, the deck and handrail,
                 the wheel's A-frames; its origin is the shaft centre on the ground
    beacon       red warning lamp on the deck rail, blinking while it winds
  sheave         the spoked winding wheel, turning about Y
  skip           the hazard-yellow bucket hanging in the shaft, raised at rest
    skip_ore     the load of ore in it
  rope           hoist rope from the wheel down to the skip, scaled along its length as the skip moves
  back_rope      rope from the other side of the wheel down to the drum
  winch_house    planked shed with a corrugated roof and stove pipe, the drum's frame and motor
  drum           winch drum wound with rope, turning about Y
  ore_bin        plated bin on legs, with a gate underneath
    ore_heap     the heap of ore in it
    dust_1..3    dust puffs, shown only while ore lands
  chute          chute from the tipped skip down into the bin
  lamp_post      the work lamp's post and switch box
    lamp         the lit lamp
```

## Clips

All at 24 fps, starting at frame 0, as per-object NLA tracks. The rest pose is the finished pithead with its skip raised and loaded.

- **Idle** (4 s, loops): nobody is mining. The lamp is lit, the empty skip hangs raised and sways a little, the bin is full.
- **Work** (3 s, loops): the skip is lowered into the shaft, comes up loaded, tips its ore down the chute with a puff of dust and rights itself. The wheel and drum turn with the rope, the heap in the bin settles and the beacon blinks. The loop starts and ends with the skip raised, as in Idle.
- **Depleted** (4 s, loops): worked out. The lamp and beacon are dark, the bin is empty, the empty skip hangs raised and creaks.
- **Build** (10 s): collar, headframe, the wheel lowered on, the skip and rope, winch house, drum, chute, bin, lamp post, then the lamp lights. Nothing stands before the collar appears.
- **Die** (5 s): the hoist rope snaps in a shower of sparks and the skip drops down the shaft (dust plumes out of it when it lands), the drum runs free. The headframe lurches, then goes over onto its side; the winding wheel breaks loose, rolls off the front and falls flat. The chute falls, the bin tips and spills its ore, the lamp post falls and the winch house leans. Dust is thrown up along the fallen headframe, then the wreck sinks 4.6 m out of sight from 3.7 s.

`assets/models/effects/iron_mine_death_fx.glb` (`scenes/models/iron_mine_death_fx.tscn`) is on Die's timeline: the flash and sparks where the rope parts, a dust plume up the shaft, dust along the fallen headframe, girders and plates knocked off, spilled ore, and dust and smoke hanging over the wreck. The `Flash` mesh's scale drives the light, as in the other death effects.

## In the game

`scripts/components/mine_rig.gd` plays the clips:

- **Construction.** `DepotNetwork.plan_spec` now gives the Iron Mine's plan the model in the scene's Visuals slot, so its site stands the model up and scrubs Build by the share of the build done.
- **Mining.** `iron_mine.gd` keeps the mine winding for `work_hold` seconds (2.5) after any iron is taken from it, so a working mine winds steadily while Infantry gather every 1.2 s. When the mine stops being worked, Work finishes its winding cycle before the mine settles to Idle, so the skip never jumps.
- **Worked out.** With no reserves left the mine plays Depleted, after finishing a cycle if it was winding.
- **Destruction.** The building is gone at once and its model stays behind, in the building's parent, as a wreck that plays Die and removes itself.

- **Ore rocks.** The ore rocks baked into the terrain (`Landmarks/OreDeposits`, and the sculpted landscape's `Mesh_ore_*` scatter) stand on every ore cell, about as tall as the winch house. A mine, and a mine site while it is planned or going up, hides the rocks on its footprint and one cell round it, through `TerrainGrid.cover_ore` and `uncover_ore`; `scripts/terrain/ore_state_visuals.gd` gives those saved instances no size and puts them back as baked. Covers are counted per cell, so overlapping sites and mines are fine. A destroyed mine gives its rocks back only once its wreck has sunk away. Nothing is rebuilt at runtime, as with felled trees. The separate gatherable `OreDeposit` resource nodes are not touched.

The old `Visuals` scale of 0.5 for the placeholder is gone; the model is authored at full size. The label moved up to 4.7 m to clear the winding wheel.

Constant channels are kept both in the export (`export_optimize_animation_keep_anim_object`) and on import (`animation/remove_immutable_tracks=false`), because Idle, Depleted and Build hold the lamp, beacon, ore and dust still or hidden with keys that never change.

## Rebuilding

```
blender --background --python Blender/Buildings/IronMine/build/build_mine.py
blender Blender/Buildings/IronMine/IronMine.blend --background --python Blender/Buildings/IronMine/build/animate_mine.py
blender Blender/Buildings/IronMine/IronMine.blend --background --python Blender/Buildings/IronMine/build/export_mine.py
blender Blender/Buildings/IronMine/IronMine.blend --background --python Blender/Buildings/IronMine/build/render_review.py
```

Always run the first three in order: the saved file keeps the pose the clips leave at frame 0. `render_review.py` also takes `clip:<clip>:<frame>,<frame>...[:<view>]` to render a strip of one clip; the `winch` view is close on the winch house and drum and the `head` view on the skip, chute and bin. The looping clips are set in `iron_mine.glb.import`. Review renders are in `Blender/Previews/IronMine`.

## Checks

- `tests/iron_mine_model_test.gd` (headless): the clips and their loop modes, every track starting at frame 0, the site model following construction progress, the size, footprint and front direction, the mine idle when unworked, winding (skip down the shaft, wheel turning) when iron is taken, finishing its cycle before going idle with the skip back up, going dark with an empty bin once worked out, and the wreck playing Die, ignoring the working switch, sinking out of sight and removing itself.
- `tests/ore_cover_test.gd` (headless): the starting mine covers its rocks and the cells round it, a mine site covers its footprint until it is cancelled, a finished mine keeps them covered when its site goes, and a destroyed mine gives them back only once its wreck is gone.
- `tests/ore_cover_runtime_check.gd` (rendered): shots of the starting mine and of a deposit spot bare, as a site and as a mine, and a check that covered rocks have no size and uncovered ones stand as baked.
- `tests/iron_mine_model_runtime_check.gd` (rendered): shots of the skirmish's own mine, a site, the mine idle, winding and tipping, worked out, the collapse and the wreck, and a check that the mine is pickable on its headframe.

Headless checks are not visual verification.
