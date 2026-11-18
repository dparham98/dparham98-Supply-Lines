# Open the Streamliner in Godot

Extract `Streamliner_Godot_Review.zip` into an empty folder outside the Supply Lines checkout. In Godot 4.7.2, import its `project.godot`, open `review.tscn` and press **F6** or **F5**. The ZIP includes the redesigned GLB, accepted comparison vehicles, rails, ground tiles, lighting and team materials. The project opens on the two team assignments.

| Control | Result |
| --- | --- |
| Left / right arrow or Space | Step through the twelve views |
| R | Toggle only the foreground train between red and blue |
| B | Toggle only the background train between blue and red |
| L | Raise or stow both redesigned trains’ amber cargo indicators |
| H | Toggle the control legend |

Both trains instance `res://assets/models/units/streamliner.glb`. The original game’s `team_paint.gd` assigns surface overrides to the imported `team_color` slot. The red uses the accepted enemy resource. The review uses a blue player material for comparison. The playable game’s player paint is green.

## Cameras and plates

All vehicles use the game's 0.6 wrapper scale. The old train and redesign sit on matching copies of the game's straight rail. The truck retains its 180° model wrapper and is placed facing the same direction as the trains. The three close comparison views share the same camera, heading, lights and image crop. The side profile hides the rails to expose the sleds. The silhouette views apply an unlit black override to the imported meshes, hide the ground and rails, and use a white background.

`preview/05_gameplay_distance.png` is an unscaled 1280 × 900 Godot framebuffer. Its 72 m orthographic span, 50° pitch, 0° yaw and 110 m camera distance match the Balanced Skirmish starting camera. The two new trains occupy the upper tracks. The accepted train is on the lower track to the left of the truck. The review yard uses the game's sun, sky, terrain shader and 4 m ground tiles on a uniform grass field. The close shots add a fill light. The gameplay inset in `preview/04_team_colors.png` preserves native pixels.

The review’s cargo toggle moves each indicator 0.32 local units above its saved rest position, the same stroke as the production consist. The render captures the stowed and raised elevated views as `elevated.png` and `loaded_indicator.png` in the raw frames directory. The scene provides stationary visual comparisons. The executed movement and cargo checks are under the adjacent `../runtime/` directory.

## Rebuild from the checkout

Run the following PowerShell from the Supply Lines repository root. Python 3 stages the project, then Godot performs a fresh import and renders the cameras with Forward+. Pillow is required to lay out the plates and compare the captured pixels. Set `$python` to an interpreter with Pillow installed. The Windows review used Bahnschrift for captions.

```powershell
$review = 'Blender/Vehicles/Maglev/Astra_Streamliner/validation/review'
$godot = 'C:/Dev/Tools/Godot_v4.7.2-stable_win64_console.exe'
$python = 'python'
$stage = Join-Path $env:TEMP 'SupplyLines_Streamliner_FinalReview'
$frames = $stage + '_frames'

& $python -B "$review/render_review.py" --godot $godot --directory $stage
& $python -B "$review/format_plates.py" $frames
& $python -B "$review/verify_paint_frames.py" $frames --output "$review/visible_paint_check.json"
& $python -B "$review/stage_review.py" $stage --zip "$review/Streamliner_Godot_Review.zip"
```

To verify the packaged project from a fresh extraction, run the same capture with `--archive`.

```powershell
& $python -B "$review/render_review.py" --godot $godot --archive "$review/Streamliner_Godot_Review.zip"
```

The import and capture logs are `import.log` and `capture.log` under `$stage`. The capture process saves the two-team frame, invokes the same R control available in the viewer, captures the changed foreground train, and restores it. `verify_paint_frames.py` checks which red pixels turned blue in the foreground and measures any changes on the rear train's blue pixels. See `visible_paint_check.json` for the measured results.

To repeat the early shape-pass comparison, use the same scripts with its archived blockout.

```powershell
$shape = "$review/../shape"
$shapeStage = Join-Path $env:TEMP 'SupplyLines_Streamliner_ShapeReview'
& $python -B "$review/render_review.py" --godot $godot --directory $shapeStage --model "$shape/blockout.glb"
& $python -B "$review/format_plates.py" ($shapeStage + '_frames') --shape "$shape/godot_shape_review.png"
```
