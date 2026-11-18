# Industrial Streamliner prototype

Ready for visual approval. The two B concept sheets informed the tapered armour, raised intake and angled side stripe. Supply Lines fields one self-powered cargo car. Its front carries the propulsion machinery and faction fang, and its rear contains the freight doors, secondary shoulder bands and rising load flag. Both sections share the original car pivot.

## Open the prototype

The package root is `C:/Dev/Supply-Lines/Blender/Vehicles/Maglev/Astra_Streamliner/`.

| Deliverable | File relative to the package root |
| --- | --- |
| Editable Blender asset | [source/Industrial_Streamliner.blend](../source/Industrial_Streamliner.blend) |
| Game-ready model | [export/maglev_train_cargo.glb](../export/maglev_train_cargo.glb) |
| Standalone Godot project | [validation/review/Streamliner_Godot_Review.zip](review/Streamliner_Godot_Review.zip) |
| Blender studio view | [preview/blender_studio.png](../preview/blender_studio.png) |
| Godot three-quarter, side and elevated views | [Three-quarter](../preview/01_streamliner.png) · [Side and elevated](../preview/02_side_and_elevated.png) |
| Old train, redesign and cargo truck at matched scale | [Vehicle comparison](../preview/03_vehicle_comparison.png) · [Silhouettes](../preview/06_silhouettes.png) |
| Red and blue trains at normal zoom | [Paired view with native-pixel inset](../preview/04_team_colors.png) · [Full gameplay-distance frame](../preview/05_gameplay_distance.png) |
| Internal shape pass | [Early in-engine comparison against the truck](shape/godot_shape_review.png) |

Extract the Godot ZIP outside the gameplay checkout, open its `project.godot` in Godot 4.7.2 and press **F5**. The opening view contains both teams. **R** changes the foreground train, **B** changes the rear train and **L** raises or stows the cargo flags. Use the arrow keys to cycle through views. [Godot review controls and capture commands](review/README.md)

In Blender, the four collections separate structure, machinery, livery and running gear. The source includes editable panel meshes, separate fittings, a dedicated team mask and two independently pivoting sleds. The exporter combines fixed pieces by material and instances the two shoes and drawheads. Both reference PNGs are beside the source. The model uses solid PBR materials and requires no image textures.

## Measured geometry and cost

Blender 4.5.3 LTS, metric units at 1.0, nose −Y and up +Z. Godot 4.7.2 imports the GLB at 1.0, nose +Z and up +Y. The actor applies a uniform 0.6 to the car. Dimensions exclude empty attachment markers.

| One complete car | Accepted | Streamliner |
| --- | ---: | ---: |
| Authored length × width × height, m | 10.900 × 3.660 × 3.290 | 10.900 × 3.658 × 3.290 |
| Playable length × width × height, m | 6.540 × 2.1960 × 1.974 | 6.540 × 2.1948 × 1.974 |
| Lowest / highest point, world m | 0.408 / 2.382 | 0.408 / 2.382 |
| Unique meshes / mesh instances | 4 / 4 | 4 / 6 |
| Unique triangles / triangles per car | 1,516 / 1,516 | 6,244 / 7,212 |
| Unique material surfaces / surfaces per car | 15 / 15 | 21 / 29 |
| PBR materials / textures | 8 / 0 | 12 / 0 |
| GLB bytes | 89,752 | 334,728 |

The redesign adds 5,696 triangles per car, 14 instantiated material surfaces and 239 KiB of GLB storage. The GLB contains geometry, node transforms and solid PBR materials. The original runtime scripts supply the articulation. Testing covered resource counts and operation. Fleet frame time remains unmeasured. [GLB measurements](audit/mesh_metrics.json)

## Executed checks

| Check | Result |
| --- | --- |
| Runtime route | The production actor ran 39.534 m outbound and 49.050 m inbound on ordered routes over the 12 m radius curve. The return order turned the leading end 180°. The two sleds reached 19.46° relative yaw. Sled-to-centreline error stayed below 0.000035 m. |
| Alignment | Centreline sled pivots stood at 0.600 world m with a 3.600 m pivot chord. Both coupler planes sat 0.030 world m beyond the mesh ends. All seven accepted nodes kept their names, parents and local transforms. |
| Track clearance | Across 77 straight poses and 55 poses on each of the curve, left branch and right branch, the train mesh cleared the modeled rail, settled switch blades and ownership indicator. The smallest sampled vertical gap was 0.048 world m. The actual moving train retained at least 0.2747 world m to the ideal guideway edge on its sampled curve frames. |
| Cargo | Capacity remained 12 crates / 300 units. One crate and a full load both raised the same indicator by 0.32 local m (0.192 world m). The production actor delivered 300 iron and returned it to rest. Across eight elevated views the empty flag was concealed and the raised flag was visible. |
| Ownership | The same GLB ran simultaneously in red and blue. The corresponding mesh nodes on both actors used the same mesh resources. Each actor had one recolorable surface. In a rendered test, 15,572 foreground pixels changed from red to blue while all 18,243 sampled blue pixels on the other train stayed identical. The review uses the shipped red and a blue replacement for the isolated player paint. The accepted game's player paint is green. |
| Readability | An area-weighted sample estimated 16.06% team paint on the exposed fixed body (accepted 5.82%). Across eight headings at 50° elevation, paint occupied 19.16–21.33% of the full vehicle's projected silhouette (accepted 6.58–8.00%). The normal-distance image uses the Balanced Skirmish camera at 72 m orthographic size and 1280 × 900. |
| Stock checks | Both the project's rail fork/power test and rail runtime check passed in a fresh disposable game copy with the final GLB. |

The early Godot comparison prompted a wider forward shoulder stripe. Later inspections led to a darker forward visor, an armoured fang panel, deeper vent contrast, a fully stowed empty cargo flag, and a relieved saddle over the rail power marker. The saddle brackets extend 0.0654 world m farther out per side than the old shoes while staying inside the body envelope. The live consist has a single car, so the two coupling sockets were validated geometrically. Inter-car coupling and fleet performance remain outside the executed checks.

[Original contract and source inventory](audit/accepted_contract.md) · [Imported node transforms](audit/prototype_nodes.json) · [Executed Godot measurements](runtime/prototype_runtime.json) · [Framebuffer recolor check](review/visible_paint_check.json) · [Fresh ZIP import and render verification](review/packaged_import.json)

## Rebuild and re-export

Run from `C:/Dev/Supply-Lines` in PowerShell. The builder reads the project's Drone working file for the actual `faction_fang` geometry. Building replaces the prototype source and export. To export hand edits, run the **export only** command against the edited and saved Blender file.

```powershell
$prototype = 'Blender/Vehicles/Maglev/Astra_Streamliner'
$blender = 'C:/Program Files/Blender Foundation/Blender 4.5/blender.exe'
$godot = 'C:/Dev/Tools/Godot_v4.7.2-stable_win64_console.exe'

# Generate source and GLB
& $blender --background --factory-startup --python-exit-code 1 --python "$prototype/source/build_streamliner.py"

# Export only
& $blender --background --factory-startup "$prototype/source/Industrial_Streamliner.blend" --python-exit-code 1 --python "$prototype/source/export_streamliner.py"

# Render the Blender source and repeat the audits
& $blender --background --factory-startup "$prototype/source/Industrial_Streamliner.blend" --python-exit-code 1 --python "$prototype/source/inspect_blender.py"
& $blender --background --factory-startup --python-exit-code 1 --python "$prototype/validation/audit/measure.py"
python -B "$prototype/validation/runtime/run_runtime.py" --godot $godot
```

A clean rebuild from the scripts and a separate export from the delivered Blender file both reproduced the delivered GLB byte for byte. Its SHA-256 is `a32e53951adeb7a3e61027bd0904c29723985e3aebe0703aeb56d3510ea16393`. Before/after verification matched all eleven reference sources and exports. [Before](audit/reference_sha256_before.json) · [After](audit/reference_sha256_after.json)
