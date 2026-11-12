# Material pile models

Material piles (`scenes/gameplay/material_pile.tscn`) were one tan box for every material. Each material now
has its own model, and a pile shows more or less of it with its amount. Amounts, picking up, dropping off,
the label and the map overlay are unchanged. The design was agreed in conversation on 2026-11-12; there was
no concept sheet.

## Look

Each pile stands on its one cell, within about 0.45 m of the centre and at most about 0.45 m tall. The front
faces the default camera (+Z in the game).

| Material | Base (always shown) | Stack (shown by amount) |
| --- | --- | --- |
| Iron | A timber pallet with a hazard tag on the front | 16 steel ingots in four crosswise courses of four |
| Wood | Two bearers with chocks at each end | 10 logs in a 4-3-2-1 pyramid, cut ends to the camera |
| Coal | A dark dust patch with a few stray lumps | 5 heaps, each larger than the last, with lumps on the slopes |

Flat materials only: about 300 (iron), 430 (wood) and 4,800 (coal, all five heaps) triangles.

## Amount

`scripts/components/pile_rig.gd` shows the base always, and the first `ceil(amount / full_amount x pieces)` of
the stack (at least one while anything is left). `full_amount` is 100, so a pile of 100 or more shows the
whole stack. Pieces are named `<material>_piece_NN` and are laid down from 01, bottom first. When a pile is
drawn down or topped up the top pieces hide or reappear; nothing is built at runtime.

`material_pile.tscn` holds a `models` list from material to model scene; the pile stands that model under
`Visuals` when it is placed and passes it the amount whenever its label updates. Picking uses the visible
meshes, so the base keeps even a one-unit pile pickable.

## Files

- `Blender/Props/MaterialPiles/MaterialPiles.blend`, built by `build/build_piles.py` and exported by
  `build/export_piles.py`; `build/render_review.py` makes the previews in `Blender/Previews/MaterialPiles`.
- `assets/models/props/material_pile_{iron,wood,coal}.glb`.
- `scenes/models/material_pile_{iron,wood,coal}_model.tscn`: the glb under `pile_rig.gd`.
- `scripts/economy/material_pile.gd`: `models`, and the model standing and following the amount.

## Validation

- `tests/material_pile_model_test.gd` (headless): each material wears its model, stays on its cell and about
  knee high, builds from the bottom; 1, 50, above 100 and after extraction show 1, half, all and a tenth of
  the stack; the base always shows and keeps a small pile pickable; a build site's delivery forms a pile with
  the model.
- `tests/material_pile_runtime_check.gd` (rendered): shots `piles_close` and `piles_play` (iron, wood and coal at
  10, 50 and 100) and `piles_on_site` (iron delivered to a Generator site).
- `tests/mobile_supply_runtime_check.gd` now clicks the pile's base instead of the old box.
- Not played: from the game's high camera the logs read as poles and the ingots as dark bars, so whether
  each material is recognisable at play zoom needs your eye.
