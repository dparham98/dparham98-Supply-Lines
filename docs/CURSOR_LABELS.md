# Cursor labels

The labels that follow the cursor while you place something tell you what to click next:

- **Rail:** `RailPreview/Status` in each map scene ("RAIL · click a Depot, mine or build site", then the
  piece count, iron cost and "CLICK LAYS IT").
- **Placement:** `Status` in `scenes/gameplay/construction_preview.tscn` (the building, its cost and whether it can
  go there).

They keep the same size on screen at every camera zoom, so you can read them zoomed out without zooming in
(playtest of 2026-11-18). Both are `Label3D` nodes with **Fixed Size** on. The camera is orthographic, so with
Fixed Size the text height on screen is about `font_size × pixel_size ÷ 2` of the window's height: font size 36 and
pixel size 0.0014 give about 21 px in a 900 px window, and the text grows with the window.

Before, the labels were sized in metres (pixel size 0.03): about 8 px tall at the default zoom and 2 px at the
widest.

To change the size, edit Pixel Size on those nodes in the saved scenes (all four maps carry their own
`RailPreview`).

## Checks

- `tests/cursor_label_test.gd` (headless): both labels in every map have Fixed Size and the agreed size.
- `tests/cursor_label_runtime_check.gd` (rendered): renders the rail label at zoom 30, 95 and 400 and measures
  it; it must be at least 16 px tall and keep its height within 25%. Saves `cursor_label_<zoom>.png`.
