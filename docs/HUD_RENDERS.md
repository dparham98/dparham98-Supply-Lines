# HUD renders

Asked for on 2026-11-19: the HUD's unit and building icons, and the portraits (the Deforester's included), are pictures rendered from the models rather than drawn glyphs or paintings, "for now".

## The tool

`scripts/tools/render_hud_images.gd` makes them. Run it with a window from the project folder, then let Godot import the new images:

```
Godot --path . --script res://scripts/tools/render_hud_images.gd
Godot --headless --path . --import
```

Add ids after `--` to render only those, for example `-- tank depot`.

- For each entry in `ENTRIES`, it loads the gameplay scene and lifts out its `Visuals`.
  - The gameplay script never runs.
  - The model is shown in the player's team paint.
  - Its selection marker, labels and effects (`fx_*` materials, particles) are hidden.
- It lights and shoots the model in a world of its own, three-quarters from the front and 28° above:
  - `assets/ui/renders/<id>.png`: the whole model, 256 × 256, on a clear background.
  - `assets/ui/portraits/<id>.png`: a closer view, cut to what is drawn, on a clear background. A figure shows its upper half or so; a vehicle or building shows whole.
    The Deforester's portrait is the exception: it is composed in Blender for the frame (`UNIT_PORTRAITS.md`), and the tool leaves it alone (`COMPOSED_PORTRAITS` in `skirmish_hud.gd`).
  - `assets/ui/command_cards/sl_produce_<id>.png` and `sl_build_<id>.png`: the render inside the card's own frame and ground.
- Run it again whenever a model changes.

| Id | Scene | Card |
| --- | --- | --- |
| infantry (the Deforester) | `infantry.tscn` | produce_infantry |
| scout, grenadier | their scenes | produce_scout, produce_grenadier |
| ubermech | `ubermech.tscn` (the walker) | produce_ubermech |
| hostile | `hostile.tscn` | |
| tank, motorcycle, drone | their scenes | produce_tank, produce_motorcycle, produce_drone |
| cargo | `cargo_vehicle.tscn` | produce_cargo |
| truck | `depot_truck.tscn` | produce_truck |
| train | `train.tscn` | produce_train |
| depot | `depot.tscn` | build_depot |
| barracks | `barracks.tscn` | build_barracks |
| tank_factory | `tank_factory.tscn` | build_factory |
| generator | `energy_generator.tscn` | build_generator |
| mine | `site_mine.tscn` (the portal mine) | build_mine |
| pithead | `iron_mine.tscn` (on an ore field or coal seam) | build_coal_mine |
| temple | `temple_of_science.tscn` (placeholder model) | build_temple |

`EXTRA_CARDS` makes more cards from a render: the train's render is also the Temple's **research_mining_trains** card, and the portal mine's is the train's **mine_iron** card (docs/TEMPLE_OF_SCIENCE.md). A card with no image yet starts from the Barracks card's frame.


## Where they show

- **Selection header:** the icon beside the name. A render keeps its own colours; a glyph is tinted gold as before (`skirmish_hud.gd` `set_icon`, `unit_image`).
- **Group portraits:** the buttons for each selected unit.
- **Portrait frame** (`Ornament/Portrait`): units and, now, buildings too.
  - The frame is the painted panel's portrait window, 97 × 173 px at every window size, so the portrait is shown whole and centred on the frame's own background (`stretch_mode` keep aspect centred).
  - It used to be cropped to fill the frame.
- **Production tiles** on Barracks, Tank Factories and Depots, and **build tiles** on the Build page: the card images above.

`icon_name` gives each actor its id. Barracks and Tank Factories, and portal mines and pitheads, now have ids of their own. An id with no render falls back to its glyph (`glyph_name`).

The supplied Infantry painting is kept in `assets/ui/portraits/source/infantry_source.png`.
