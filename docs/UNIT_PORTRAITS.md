# Unit portraits

Asked for on 2026-11-18, starting with the Infantry.

- The selected unit’s portrait appears in the framed panel left of the command card (`Ornament`). With several units selected, it shows the unit whose card and stats are shown.
- **Which units:** a unit with no portrait, and any building, keep the emblem.
- **Files:** a portrait is `assets/ui/portraits/<unit id>.png`; `update_portrait` in `skirmish_hud.gd` finds it by the unit's id.
- The portrait is 204 pixels tall in the standard HUD. Its visible width grows from 172 pixels in a 1280-wide window to 332 at 1440, and caps at 360. Compose the full head in the central 172 × 204 region so narrower windows trim the shoulders first.
- The 720 × 408 [Infantry portrait](../assets/ui/portraits/infantry.png) shows the playable model in its Rest pose. The [full-resolution render](../assets/ui/portraits/source/infantry_model.png) and [original concept painting](../assets/ui/portraits/source/infantry_source.png) are kept in the source folder.

Run this command from the project root with Blender 4.5 to rebuild the portrait from the playable GLB.

```text
blender -b --factory-startup -P Blender/Characters/Infantry/Astra_Cyborg/source/render_hud_portrait.py
```

`tests/unit_portraits_test.gd` checks that selecting an Infantry shows its portrait and that a building shows none.
