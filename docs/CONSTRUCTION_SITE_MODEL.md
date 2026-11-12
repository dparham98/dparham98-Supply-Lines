# Construction site model

A planned building now stands inside a fenced construction site instead of on the bare grid alone. The site is
decoration round the plan described in [SITE_CONSTRUCTION.md](SITE_CONSTRUCTION.md): it changes no rule,
cost, timing or pathing, and it has no collision, so trucks and Infantry walk and drive onto the footprint as
before. The design was agreed in conversation on 2026-11-12; there was no concept sheet.

## Look

One kit, laid out once per footprint size the game plans:

| Site | Footprint | Used by |
| --- | --- | --- |
| `construction_site_2x2` | 2 x 2 | Iron Mine |
| `construction_site_3x3` | 3 x 3 | Generator |
| `construction_site_6x6` | 6 x 6 | Barracks |
| `construction_site_8x8` | 8 x 8 | Tank Factory |
| `construction_site_10x10` | 10 x 10 | Depot |

- **Fence.** Timber posts on the footprint's edge, one rope span per cell with two sagging rope lines and
  red, yellow and white bunting, all inside about 6 cm of the footprint.
- **Lamps.** Heavier hazard-striped posts with caged lamps at the four corners and either side of the gate.
- **Gate.** The middle of the front (the side toward the default camera, +Z in the game) is left open, one cell
  wide on the 2 x 2 and 3 x 3 sites and two on the larger ones, with a raised red-and-white barrier boom.
- **Site board.** A dark board in a hazard frame beside the gate, with a building outline and a crane hook.
- **Clutter.** On the 6 x 6 and larger sites only, inside the front corners: a sawhorse with planks, a toolbox, a
  sand heap with a shovel and a plank stack; the 8 x 8 and 10 x 10 add more at the back. The small sites have
  none, because their buildings fill the footprint.

About 3,100 (2 x 2) to 10,800 (10 x 10) triangles, flat materials only. Rails keep the bare grid, since they
are laid one tile at a time.

## In play

- The plan stands the site for its footprint (`site_scenes` on `scenes/gameplay/construction_plan.tscn`), centred
  on the footprint like the building that will replace it. A building with a Build clip rises inside it as before.
- The lamps follow the site's state, the same three as the grid: **amber** while materials are short, **green**
  once everything still needed lies on the site, and **blinking blue** (0.8 s on-off) while Infantry build. Each
  site has its own lamp material, so sites change colour independently.
- The grid stays, at half its old opacity, so the fence carries the look. The label is unchanged.
- The bunting sways in the site's one clip, Idle (3 s loop).
- The clutter is cleared away once construction passes 75 %, so the finished building is not crowded.
- When the building finishes or the plan is cancelled the site goes with the plan.

The colours, blink period, lamp brightness, clutter threshold and grid opacity are exported on
`scripts/components/site_rig.gd` and `construction_plan.gd` for tuning.

## Files

- `Blender/Buildings/ConstructionSite/ConstructionSite.blend`, built by `build/build_site.py` and exported by
  `build/export_site.py`; `build/render_review.py` makes the previews in `Blender/Previews/ConstructionSite`.
- `assets/models/buildings/construction_site_{2x2,3x3,6x6,8x8,10x10}.glb`, with Idle set to loop on import.
- `scenes/models/construction_site_*.tscn`: the glb under `scripts/components/site_rig.gd`.
- `scripts/economy/construction_plan.gd`: `site_scenes`, `grid_opacity_with_site`, `_add_site_fence()`,
  `site_state()`, and `refresh_label()` passing state and progress to the site.

## Validation

- `tests/construction_site_model_test.gd` (headless): every size has a scene that stays on its footprint, has
  lamps, loops Idle, leaves a gate in the front and carries clutter only from 6 x 6 up; each building's plan
  stands the right size, centred with the rising model; lamps amber, green and blinking blue; the grid fades;
  clutter clears past the threshold; sites keep their own colours; the site goes with the finished plan.
- `tests/construction_site_runtime_check.gd` (rendered): shots `site_3x3_waiting`, `site_2x2_ready`,
  `site_6x6_building`, `site_6x6_nearly_up`, `site_8x8_building`, `site_10x10_waiting` and `site_overview`.
- Not played: from the game's high camera the fence reads mostly as an outline and the lamps are small, so
  whether the site reads at play zoom needs your eye.
