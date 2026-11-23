# Unit portraits

Asked for on 2026-11-18, starting with the Infantry.

- **Where:** the selected unit's or building's portrait fills the framed panel left of the command card (`Ornament`). With several units selected, it shows the unit whose card and stats are shown. Anything with no portrait keeps the emblem.
- **Files:** a portrait is `assets/ui/portraits/<id>.png`; `update_portrait` in `skirmish_hud.gd` finds it by the id from `icon_name`.
- **The frame** is the portrait window painted on the HUD panel (`HUD_LAYOUT.md`). The portrait inside it (`Ornament/Portrait`) is 97 × 173 pixels and does not change with the window's width.
- **Renders:** most portraits are renders of the models (`HUD_RENDERS.md`), shown whole and centred.
- **The Deforester** has a portrait composed for the frame: the 720 × 408 [Infantry portrait](../assets/ui/portraits/infantry.png) shows the playable cyborg model in its Rest pose. It covers the frame (`COMPOSED_PORTRAITS` in `skirmish_hud.gd`), with the full head in its central region, so the narrow painted window trims the shoulders and keeps the head. `render_hud_images.gd` leaves it alone.
  - The [full-resolution render](../assets/ui/portraits/source/infantry_model.png) and the [original concept painting](../assets/ui/portraits/source/infantry_source.png) are kept in the source folder, which Godot does not import (`.gdignore`).
  - Rebuild it from the playable GLB from the project root with Blender 4.5:

```text
blender -b --factory-startup -P Blender/Characters/Infantry/Astra_Cyborg/source/render_hud_portrait.py
```

`tests/unit_portraits_test.gd` checks that a selected Deforester's portrait covers the frame with its whole helmet at narrow and wide windows, that a Depot's render shows whole and centred, and that nothing selected shows none.
