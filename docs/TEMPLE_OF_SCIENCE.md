# Temple of Science and Mining Trains

Asked for on 2026-11-19: "We will also add a "Temple of Science" building. It will be a research building. For now, it will have the ability to upgrade trains to mine iron directly, which itself is an ability that will have to be made."

The user settled the design points the same day:

- the Temple costs 150 E / 60 I on a 6 × 6 footprint and is placed like a Barracks;
- the research costs 150 E / 100 I and takes 60 s;
- an upgraded train runs a mine-to-Depot loop;
- the research applies to the whole side, and upgraded trains look the same as before.

All the figures are provisional.

## The building

- **Placing it.** The Temple is on the Build page as **Temple of Science** (key **S**). It is planned, delivered and built by Deforesters like the Barracks and Tank Factory (`DepotNetwork.plan_spec`, `production_scene`). The same rules apply: Depot range, sight of the site, and an empty footprint.
- **Scenes.**
  - `scenes/gameplay/temple_of_science.tscn`, with `scripts/buildings/temple_of_science.gd` (which extends `production_building.gd`) and the stats in `assets/buildings/temple_of_science.tres`. Maps can set `DepotNetwork.temple_scene`; those that leave it unset use the saved scene.
  - The Temple is in the `production_buildings` group as well as `research_buildings`. Repair, selection, the defeat check and the Depot panels therefore treat it as they treat the factories. It makes no units, so the production-speed panel stays hidden for it.
- **Paying.** Research pays from the Depot the Temple picks, as factories do (`payer_for`): the Depot it has while that Depot can pay, else the nearest covering Depot that can.
- **Model.** `scenes/models/temple_of_science_model.tscn` is the armoured observatory temple, `assets/models/buildings/temple_of_science.glb`, in the `Visuals` slot (docs/TEMPLE_OF_SCIENCE_MODEL.md).

  While research runs, the armillary turns and the orb brightens (`scripts/components/temple_model.gd`, `show_research`). The construction site shows the plain plan grid, since the model has no construction clip.

## Research

- **The card.** Selecting the Temple shows its **Research Mining Trains** card (key **R**) with the cost and the Depot that would pay.
  - While research runs, the card's progress bar fills and **Cancel research** (X) gives the whole cost back to the Depot that paid.
  - Once the research is done, the card stays greyed out as "researched".
- **One at a time.** A Temple carries out one research at a time. A research cannot be started at a second Temple while it is under way at the first.
- **Lost or paused.**
  - If the paying Depot is captured, the research is lost without a refund, as a factory loses its queue.
  - If no friendly Depot covers the Temple, the research pauses.
- **Effect.** Finished research holds for the whole side: every train you have and every train you build later (`scripts/research/research.gd`, stored on the map's skirmish node). It is not lost if the Temple is destroyed.
- **Data.** Each research is a `ResearchStats` resource (`assets/research/mining_trains.tres`), listed in the Temple scene's `research` array, so more can be added there.

## Mining Trains

Once the side has the research, a maglev train can mine iron itself, with no Deforesters.

- **Order.** Select the train and either press **Mine iron** (key **I**) and click an Iron Mine, or right-click the mine. Before the research, the tile is greyed out and says why.
- **Where it digs.** The mine must be joined by friendly track. The train stops on track inside the mine's ring, the same ring planned track connects to (`RailNetwork.target_reach`: half the mine's footprint plus 4 m). Track is laid to a mine with the Build page's Maglev track, picking the Depot and then the mine (`docs/RAIL_PLANNING.md`).
- **The loop** (`scripts/rails/train.gd`, `mining_stage`):
  1. **To the mine** along the track.
  2. **Digging**: `train_mine_rate` iron a second (10, in `assets/economy/rail_rules.tres`) until its 300 is full or the mine is worked out. The iron comes out of the mine's reserves, as the Deforesters' iron does.
  3. **To the Depot**: the nearest friendly Depot connected to the line, preferring one with room.
  4. **Unloading** for the usual transfer time (2 s), then back to the mine.

  If the train already carries cargo when ordered, it unloads that first.
- **When it stops.**
  - The loop runs until the mine is worked out or destroyed, the train derails, or it is given another order (Stop, Move, Load, Unload or a delivery route).
  - It also stops when a mine runs dry while the train is empty. If the train still has iron aboard, it delivers that iron first.
- **Rules that stay the same.**
  - The train draws energy by the metre from a connected Depot, as on any route.
  - Without power it waits, keeping its cargo.
  - A full Depot makes it wait with the iron aboard.
- **Coal.** Coal mines are refused: the research digs iron.
- **No new look.** Upgraded trains look the same as before. Only the card and the status text ("Mining iron at Mine07 · 120 / 300") show the ability.

## HUD images

`scripts/tools/render_hud_images.gd` renders the Temple (`temple`: icon, portrait and the `build_temple` card). Its `EXTRA_CARDS` make the `research_mining_trains` card from the train's render and the `mine_iron` card from the portal mine's (docs/HUD_RENDERS.md). The research card therefore looks like the Depot's Train card. Making it distinct waits for art.

## Exercise

`scenes/maps/temple_exercise.tscn` is Two Lakes with three changes, written by `scripts/tools/build_temple_exercise.gd`:

- **Track to a mine.** The game suggests 12 pieces of track from the player's Depot to Mine07, the nearest Iron Mine at least 40 m away, about 83 m north-east. The starter mine sits almost inside the Depot's rail ring, so a train there would never move.
- **A train and a Temple.** A train stands at the Depot. A Temple of Science stands 9 m south of the Depot, in its range, away from the starter mine's path.
- **More stock.** The Depot holds 600 E and 300 I instead of 200 E and 60 I, enough for the research.

Open it with:

```
Godot --path . res://scenes/maps/temple_exercise.tscn
```

Rebuild it after the map or the track rules change:

```
Godot --headless --path . --script res://scripts/tools/build_temple_exercise.gd
```

## Validation

`tests/temple_of_science_test.gd` (headless, on the exercise) checks:

- the Temple stands in the Depot's range with its model, its plan spec and its Build page tile;
- a Temple plan builds a working Temple;
- the train refuses to mine before the research;
- the research's cost, the refusal of a second research, the refund on Cancel, the 60 s and that it holds only for its side;
- the Temple card and the train's Mine iron tile;
- a full loop: out to Mine07, 300 iron dug from its reserves and 300 iron delivered to the Depot, then back towards the mine;
- that Stop and Move end mining, and a right-click on the mine starts it.

## Not done yet

- There is no art for the Temple and no distinct research card.
- The costs, the 60 s and the dig rate are first guesses.
- Nobody has played it.
- The enemy AI neither builds Temples nor researches.
- One Temple researches one thing. A research queue and other research are left for when there is more to research.
