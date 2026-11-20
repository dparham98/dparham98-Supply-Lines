# Unit portraits

Asked for on 2026-11-18, starting with the Infantry.

- The selected unit’s portrait fills the framed panel left of the command card (`Ornament`). With several units selected, it shows the unit whose card and stats are shown.
- **Which units:** a unit with no portrait, and any building, keep the emblem.
- **Files:** a portrait is `assets/ui/portraits/<unit id>.png`; `update_portrait` in `skirmish_hud.gd` finds it by the unit's id.
- **Shape:** it fills the frame and is trimmed to its shape (`Ornament/Portrait`, keep aspect covered), so portraits are cut at about 0.85 wide to 1 tall.
- The 340 × 402 [Infantry portrait](../assets/ui/portraits/infantry.png) shows the playable model in its Rest pose. The [full-resolution render](../assets/ui/portraits/source/infantry_model.png) and [original concept painting](../assets/ui/portraits/source/infantry_source.png) are kept in the source folder.

`tests/unit_portraits_test.gd` checks that selecting an Infantry shows its portrait and that a building shows none.
