# Bastion production and validation

The package is at `C:/Dev/Supply-Lines/Blender/Vehicles/Tank/Astra_Bastion/`. The [editable source](../source/Bastion.blend), [tank-only export](../export/Bastion.glb), [Godot review ZIP](Bastion_Godot_Review.zip) and [rendered views](../README.md) all come from the same model. Blender 4.5.3 LTS and Godot 4.7.2-stable Forward+ were used.

## Shape and paint

The [approved red three-quarter view](../source/approved_bastion.png) sets the silhouette. The turret has one optic beside the cannon and a steel service housing on the same flank. Its overhanging rim and layered skirts echo the cyborg infantry's helmet and coat. The cannon retains the accepted muzzle reach and the tracks retain their wheelbase. Those dimensions give the Bastion a longer side profile than the concept suggests. Removing the old antenna brings the roof down by 0.546 world m.

Each shoulder plate and hanging apron is editable. Shape reviews led to hollow skirts that clear the moving treads, saddles under the headlights, and deeper openings between the rear cooling blades. Six `team_color` surfaces cover the four shoulder inserts, the small turret panels and the roof stripe. The review uses the game's per-instance paint mechanism with its red enemy material and the cyborg review's blue player swatch. The playable player colour is green. The optic remains red-orange and the headlights warm white in both schemes.

## Runtime fit and cost

| Full-detail asset | Accepted tank | Bastion |
| --- | ---: | ---: |
| World width × length with cannon × height (m) | 3.384 × 6.885 × 3.000 | 3.348 × 6.885 × 2.454 |
| Ground to centre-hull underside (m) | 0.330 | 0.318 |
| Meshes / GLB surfaces | 68 / 68 | 43 / 117 |
| Triangles / materials | 3,200 / 1 | 6,680 / 12 |
| Packed 2048 × 2048 textures | 3 | 3 |
| GLB size (bytes) | 3,133,792 | 3,288,668 |

The redesigned armor uses flat material slots. The additional surfaces and triangles are the main rendering cost. The three accepted running-gear atlases are packed in the Blender source and the GLB. The track shoes sample clean neutral metal from those atlases. Performance with many tanks on screen was not benchmarked.

Blender uses metres, −Y forward and +Z up. The GLB is +Z forward and +Y up. The existing Godot wrapper rotates it 180° around Y and scales it by 0.6. At rest the shoes touch the ground. Picking uses visible mesh bounds, and navigation uses the original ground-cell occupancy. The selection marker remains 4 × 6.8 world m at (0, 0.06, −0.4).

The turret, barrel mount, recoiling barrel, muzzle brake, ten running-gear parts and both breakaway hatches retain their runtime paths. The level barrel slews through 360° at 240°/s and recoils 0.55 authored m. Its rested muzzle face meets the existing effect origin at Blender (0, −7.10, 2.62). The three existing death sequences animate and scorch the Bastion. Detached debris still uses the accepted tank's effect models. The [accepted contract](audit/CONTRACT.md) lists the pivots, marker placement, roles of each animation and the consuming scripts.

## Executed checks

- The actual GLB passed 720 turret positions at the two recoil limits, 23 intermediate barrel positions and 17 tread phases on each side. The shoes cleared the hull, both skirt layers and the headlamp housings. The barrel stays at least 0.0834 world m above the hull and skirts throughout yaw. [Geometry measurements](audit/geometry.json)
- A disposable full game copy imported the model into the production wrapper. The untouched aim, track, firing, death and rendered-model tests passed. A real move order covered 7.0 world m, turned the chassis 90° and left the tank occupying one destination cell. The rendered half-pitch track step changed 8,021 sampled pixels. These checks exercised selection, recoil, firing effects, projectile hit and the three death clips. [Runtime results](audit/runtime.json)
- The independent review project was extracted, imported and rendered. Repainting one tank changed its six designated surfaces while the other tank and the neutral materials kept their assigned colours. The studio captures are stationary. The gameplay comparison uses the opening Two Lakes camera's 72 m orthographic span and 50° pitch with its sun, sky and grass. [Review verification](review/verified.json)
- Reopening the saved Blender source and exporting to a second destination reproduced the delivered GLB byte-for-byte. The preservation check verified all 53 accepted input hashes. [Input paths and digests](audit/accepted_inputs.json)

## Reproduce

Run these commands from `C:/Dev/Supply-Lines` with Blender 4.5.3. The first regenerates the source and game export from the construction scripts. Use the second to export hand edits from the saved Blender file.

```powershell
$pkg = 'Blender/Vehicles/Tank/Astra_Bastion'
blender -b --factory-startup --python-exit-code 1 -P "$pkg/source/build_bastion.py"
blender -b "$pkg/source/Bastion.blend" --python-exit-code 1 -P "$pkg/source/export_bastion.py"
blender -b "$pkg/source/Bastion.blend" --python-exit-code 1 -P "$pkg/source/render_studio.py"
```

Use the supplied exporter for the six shader-driven meshes. It preserves their indexed geometry and stops if their locked geometry has been changed. Changing the animated tread topology requires corresponding work on the shader's pose table. The four end wheels and new body components export from their editable meshes. [Gear export code](../source/gear_export.py)

The [review instructions](review/README.md) reproduce the Godot captures and portable ZIP. The [audit instructions](audit/CONTRACT.md#repeating-the-checks) reproduce the preservation, geometry and runtime tests. Human visual approval and any playable integration are pending.
