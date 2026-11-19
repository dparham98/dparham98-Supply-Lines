# How coal shows on the map

Coal seams lie in the ground, mostly inside forest, so from the game's camera the trees used to hide them. These changes make a seam visible without changing what it is or how it is reached (2026-11-19):

- **A ring round every seam, for now.** The map overlay (`scripts/ui/map_overlay.gd`, `draw_coal_rings`) draws a thin coal-coloured ring on the ground round each coal field that has coal left, 1.5 m outside its outermost cell, over the trees. It goes when the field is empty. Asked for on 2026-11-19 as a plain marker until the seams read well on their own.

- **Leaves thin over a seam.** The match's clearing mask (`TerrainGrid._clearing_mask`) has a green channel: 1 on a Coal cell with coal left, 0.55 on the cells beside one, 0 elsewhere. Tree shaders find where the line of sight through each leaf meets the ground, and leave out whole clumps of leaves in front of a seam, up to `seam_thinning` (0.85) of them. Trunks and undergrowth below `trunk_height` (1.1 m) stay, so the trees that must be felled to reach the seam still show as trees. A cell that is dug out no longer counts as seam. This is drawing only: Forest cells, felling and paths are unchanged.
  - Two Lakes' forest tiles (`Landmarks/Forests`) now use `assets/shaders/forest_tile.gdshader`, which draws them as their old StandardMaterial3D did and adds the thinning; `terrain_assets.gd` gives each batch the match's mask. The sculpted landscape's trees (`landscape_foliage`, `landscape_leaves`) thin the same way.
- **The seam stands out from the ground.** `terrain_surface.gdshader` draws pale grey spoil, ash and broken stone with black flecks, on open ground and forest floor within about `spoil_metres` (1.3 m) of a seam, so its edge shows against dark forest floor. A few small faces of the coal (`glint_share`, 7%) catch the light like broken coal, and flash as the view moves.

Coal still has no lumps or props standing on it. Props at a seam and a held-key resource highlight were considered and left for later.
