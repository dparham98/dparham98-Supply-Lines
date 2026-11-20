# Unit portraits

Asked for on 2026-11-18, starting with the Infantry.

- **Where:** the selected unit's painted portrait fills the framed panel left of the command card (`Ornament`, which until now showed only an emblem). With several units selected, it shows the unit whose card and stats are shown.
- **Which units:** since 2026-11-19 portraits are renders of the models, for units and buildings both (`HUD_RENDERS.md`). Anything with no portrait keeps the emblem.
- **Files:** a portrait is `assets/ui/portraits/<unit id>.png`; `update_portrait` in `skirmish_hud.gd` finds it by the unit's id.
- **Shape:** it is shown whole and centred in the frame (`Ornament/Portrait`, keep aspect centred). Until 2026-11-19 it filled the frame and was cut at about 0.85 wide to 1 tall.
- **Infantry (now the Deforester):** `infantry.png` was cropped from a supplied 1024 × 1024 painting until 2026-11-19; it is now a render too. The painting is kept in `assets/ui/portraits/source/infantry_source.png`, which Godot does not import (`.gdignore`).

`tests/unit_portraits_test.gd` checks that selecting a Deforester or a Depot shows its portrait, and that nothing selected shows none.
