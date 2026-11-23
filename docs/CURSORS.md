# Cursors and inspecting wood

Asked for on 2026-11-22: a custom cursor that changes to show what the pointer is over, especially wood, and wood that
can be clicked to see the size of the tile and how much wood is left.

## The cursors

Five cursors, 32 px, in the HUD's gold with a dark edge (`assets/ui/cursors`):

| Cursor | Shows over |
| --- | --- |
| Pointer (gold arrow) | Open ground, the HUD, and anywhere while a command or placement is armed (which shows its own icon beside the pointer) |
| Select (arrow and a pale blue ring) | Your units and buildings, plans, and neutral buildings: a click selects them |
| Attack (red crosshair, the click in its centre) | An enemy unit or building; also an enemy with Attack armed |
| Inspect (arrow and a magnifier) | Wood, coal, iron, piles and crates with no worker selected: a click inspects them |
| Gather (arrow and an axe) | Wood (and other resources a worker can take) with a worker selected: a right-click gathers it |

Coal needs a mine (`coal_needs_mine`), so coal shows Inspect even with workers selected.

**How it works:**

- The pictures are drawn by `scripts/tools/make_cursors.gd`; run it again after changing a shape.
- `scripts/ui/game_cursor.gd` sets each picture as one of Godot's cursor shapes (arrow, pointing hand, cross, help,
  can-drop) and picks the shape from what is under the pointer.
- The map overlay finds what is under the pointer already, for the hover card, and sets the shape each frame it looks.
- Over the HUD, controls show their own shape, the pointer.

## Inspecting wood

- **Hover:** a Forest tile under the pointer is outlined in white, and the hover card says "Forest" and the wood on
  that tile ("20 / 20 wood on this tile · click for more"). Coal tiles already answered the hover; they are outlined
  too.
- **Click:** a click on a Forest tile, with no unit or building there, selects the tile. It is outlined in amber, and
  the bottom panel shows:
  - "Forest tile";
  - the wood left on it, out of 20 (`forest_wood_per_tile`);
  - the tile's size, 1 × 1 m, and its cell;
  - the whole wood it is part of: the Forest tiles joined to it edge to edge, and their wood. The count stops at 4000
    tiles ("over 4000"), and is made again at most once a second, as felling changes it.
  - The hint says how to take the wood: right-click with Deforesters, or Fell (F).
- **Coal:** a Coal tile shows the same way, with the coal left in its seam.
- The tile stays shown as it is felled, and drops out of the selection once it is cut out.
- Shift-click on wood keeps the selection as it was. Any other click replaces it.

**Code:** `terrain_source_at` in `map_overlay.gd` (and `selection_manager.gd`), the `forest_cells` group on
`forest_harvest_source.gd`, `forest_patch` in `terrain_grid.gd`, and `show_cell` in `skirmish_hud.gd`.

## Checks

`tests/cursor_inspect_test.gd` (headless) checks:

- the five 32 px images;
- the cursor for your Depot, an enemy, Forest with and without a worker selected, an armed command and open ground;
- the hover card on Forest;
- a click selecting the Forest tile, and the panel's wood, size and whole wood;
- felling shown, and a cut-out tile dropped;
- a Coal tile;
- Shift-click on Forest keeping the selection.

A rendered screenshot of an inspected Forest tile was looked at. The cursors themselves are drawn by the system, so
screenshots don't show them; they need a playtest.
