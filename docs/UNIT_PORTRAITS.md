# Unit portraits

Asked for on 2026-11-18, starting with the Infantry.

- **Where:** the selected unit's or building's portrait fills the framed panel left of the command card (`Ornament`). With several units selected, it shows the unit whose card and stats are shown. Anything with no portrait keeps the emblem.
- **Files:** a portrait is `assets/ui/portraits/<id>.png`; `update_portrait` in `skirmish_hud.gd` finds it by the id from `icon_name`.
- **The frame** is 204 pixels tall in the standard HUD. The portrait inside it is at most 360 wide (`Ornament/Portrait`); the frame's visible width grows from 172 pixels in a 1280-wide window to 332 at 1440.
- **Renders:** most portraits are renders of the models (`HUD_RENDERS.md`), shown whole and centred.
- **The Deforester and Derailer** have portraits composed for the frame. The 720 × 408 [Infantry portrait](../assets/ui/portraits/infantry.png) shows the playable cyborg in its Rest pose. The [Derailer portrait](../assets/ui/portraits/motorcycle.png) shows the helmeted rider in the riding pose. Both keep the full head in the central 172 × 204 region, so narrower windows trim the shoulders first. The HUD selects these through `COMPOSED_PORTRAITS`. Ordinary card regeneration preserves them.
  - The [full-resolution render](../assets/ui/portraits/source/infantry_model.png) and the [original concept painting](../assets/ui/portraits/source/infantry_source.png) are kept in the source folder, which Godot does not import (`.gdignore`).
  - Rebuild it from the playable GLB from the project root with Blender 4.5:

```text
blender -b --factory-startup -P Blender/Characters/Infantry/Astra_Cyborg/source/render_hud_portrait.py
blender -b --factory-startup -P Blender/Characters/Infantry/Astra_Cyborg/source/render_hud_portrait.py -- --unit motorcycle
```

`tests/unit_portraits_test.gd` checks that a selected Deforester's portrait covers the frame with its whole helmet at narrow and wide windows, that a Depot's render shows whole and centred, and that nothing selected shows none.
