# Arthurian House

[House.blend](House.blend) is the editable four-cell-square dwelling. Its front door faces +Y in Blender and −Z in Godot. In the game `scenes/models/house_model.tscn` turns the model half round, so the door faces +Z toward the RTS camera like the other Knights buildings. The shingled roof fits entirely within the footprint. Both roof slopes have their own origin at the eave. These named meshes give a later roof variant a stable reference.

The structural frame is laminated oak and fir with bronze joinery. Cedar boards close the walls, and overlapping heartwood shingles cover both pitches. The loft contains a bed, lamp and plant behind glazing. Named team-color materials pick out the shutters, sills and shield.

| Clip | Length | Action |
| --- | --- | --- |
| Idle | 4 s | The house stands complete and the heat-recovery fan turns behind the side grille. |
| Build | 4 s | Footings and portals rise first, followed by walls, glazing and furnishings. The shingled roof and ridge close the frame. |
| Die | 2.25 s | The roof halves pitch inward, the frame falls and the wreck sinks below grade. |

From this folder, export saved manual edits and validate the published mesh in Blender 4.5.

```text
blender -b House.blend --python-exit-code 1 -P build/export_house.py
blender -b --factory-startup --python-exit-code 1 -P build/check_house.py
```

The exporter writes [house.glb](export/house.glb) with its timber images embedded. The check reimports that file, samples the roof surfaces, and measures construction and collapse. To regenerate the authored geometry and animations use `build/build_house.py` from a factory-startup session. To refresh the [studio view](preview/house.png) run `build/render_house.py` against the saved House.blend.
