# Unit portraits

Asked for on 2026-11-18, starting with the Infantry.

- **Where:** the selected unit's painted portrait fills the framed panel left of the command card (`Ornament`, which until now showed only an emblem). With several units selected, it shows the unit whose card and stats are shown.
- **Which units:** a unit with no portrait, and any building, keep the emblem.
- **Files:** a portrait is `assets/ui/portraits/<unit id>.png`; `update_portrait` in `skirmish_hud.gd` finds it by the unit's id.
- **Shape:** it fills the frame and is trimmed to its shape (`Ornament/Portrait`, keep aspect covered), so portraits are cut at about 0.85 wide to 1 tall.
- **Infantry:** `infantry.png` (340 × 402) is cropped from the supplied 1024 × 1024 painting, from the helmet to the belt, to bring the face and red eye implant up close. The full painting is kept in `assets/ui/portraits/source/infantry_source.png`, which Godot does not import (`.gdignore`).

`tests/unit_portraits_test.gd` checks that selecting an Infantry shows its portrait and that a building shows none.
