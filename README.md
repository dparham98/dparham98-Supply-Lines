# Supply Lines — start here

Latest engineering batch: [wood harvesting, capturable iron mines and local building repair](docs/ENGINEERING_BATCH.md). Open **scenes/maps/engineering_exercise.tscn** and press **F6** for a damaged-building test.

Latest building/production batch: [Barracks, Tank Factory, original Depot cost and free construction infantry](docs/PRODUCTION_BATCH.md).

Implementation priority: [explicit original design backlog](docs/EXPLICIT_DESIGN_BACKLOG.md). This separates confirmed requirements from tentative abilities and prototype decisions.

The bottom selection HUD, minimap and infantry Build menu are described in [BOTTOM_HUD.md](docs/BOTTOM_HUD.md).

For Milestone 3 power and cargo deliveries, open **scenes/maps/supply_routes.tscn** and press **F6**. See [supply exercise and editable rules](docs/MILESTONE_3.md). F5 retains the original skirmish.

**Authoritative source:** GitHub repository dparham98/dparham98-Supply-Lines. **Primary local Windows checkout:** C:\Dev\Supply-Lines for Godot editor, rendering and gameplay acceptance. Cloud development uses fresh clones, feature branches and pull requests; the OneDrive project is an older preserved copy. CI/headless tests do not replace human visual/input verification.

Press **F5** to play First Contact: gather Ore, print infantry, defeat the hostile. Open **scenes/maps/resource_skirmish.tscn** to arrange this playable scenario. [Play instructions and edit guide](docs/FIRST_CONTACT.md).

Open **scenes/maps/supply_lines_world.tscn** for the preserved terrain/legacy combat review. Terrain, trees, mountains, ore, lighting and actor models are saved scenes and are visible without running the game. If the 3D view is too close, select Terrain and press F to frame it, or use the CameraRig camera preview for the saved central-lake view.

## Where to edit

| I want to… | Open this scene |
| --- | --- |
| Arrange the map, units and buildings | scenes/maps/supply_lines_world.tscn |
| Change terrain materials or prop assets | scenes/maps/terrain.tscn |
| Change the tree, mountain or ore model | scenes/terrain/tree.tscn, mountain.tscn, ore_deposit.tscn |
| Replace the infantry appearance | scenes/units/infantry.tscn |
| Replace enemy appearance | scenes/units/enemy.tscn |
| Replace HQ appearance | scenes/buildings/headquarters.tscn |
| Adjust sun and ambient lighting | scenes/maps/lighting.tscn |
| Adjust the RTS camera | scenes/camera/rts_camera.tscn |
| Edit the terrain legend and help | scenes/ui/terrain_hud.tscn |

## Main scene layout

```
SupplyLinesWorld
  Terrain
    Ground                 surface, terrain rules and ground collision
    Landmarks              saved scenery; open the scene to inspect batches
      Forests
      Mountains
      OreDeposits
  Lighting                 Sun and AmbientSky
  CameraRig                RTS camera
  Entities
    Buildings              Headquarters instance
    Units                  Infantry and Enemy instances
  Interface                terrain legend and readout
```

Godot shows reusable instances as collapsed branches. Use the scene icon beside an instance to open its original scene, or double-click the scene file. Usually edit the original actor/terrain scene rather than enabling Editable Children everywhere.

## Plug in a unit or building model

1. Put a GLB/model and its textures in assets/models/units or assets/models/buildings. Create a small wrapper scene around it if its size/pivot needs adjustment.
2. Open the infantry/enemy/headquarters scene. Select **Visuals**.
3. Drag the model scene onto **Model Scene** in the Inspector. It previews in the editor. **Refresh model preview** reloads the slot.
4. Adjust the Visuals position/scale/rotation to fit the gameplay size. Keep the actor root at ground level; imported models should have a feet/base pivot, +Y up, -Z forward, and meter units. Do not scale the actor root to resize a model.
5. Save. All instances inherit this appearance. Gameplay stats remain on the actor root, independent from its model. The HQ's Grid Size is the reserved footprint; it does not automatically resize from imported geometry.

The present cubes are explicitly named placeholders. This setup does not import the Blender infantry automatically or add an animation controller; those can be connected to Visuals later. Author actor positions by moving instances in the world. At runtime invalid land/building positions move to nearby valid terrain. Nested organizational parent nodes should stay at identity transforms; the current movement controller assumes an untransformed Units/Buildings container.

## Plug in terrain props

1. Open terrain.tscn and select its root **Terrain**.
2. Assign **Tree Scene**, **Mountain Scene**, or **Ore Scene**. Defaults are the small reusable scenes in scenes/terrain.
3. Click **Rebuild terrain scenery**, then save the scene to keep changed slot assignments. The saved terrain_landmarks.tscn is regenerated and previews immediately in the edited terrain instance. Reopen another map tab if it still shows an old cached preview.
4. Treat terrain_landmarks.tscn as generated scenery: manually changing individual batches there will be replaced by the next rebuild. Edit the source prop scenes or asset slots instead.

The baker uses static MeshInstance3D parts from the assigned scene and preserves their local transforms/materials. It batches them for efficiency; animation, skinning, physics bodies, scripts and lights inside a prop scene are not baked. Use normalized, ground-pivot prop scenes; the default tree is about 3.5 units tall, mountain 5, and ore rock 1.2. Large/animated landmark buildings should be placed as ordinary scene instances instead. Changing prop appearance does not change the map's terrain categories or navigation.

## Folder guide

- scenes: things you can open and arrange in Godot.
- assets/models: imported art, arranged by units/buildings/terrain.
- assets/materials, assets/meshes, assets/shaders: reusable rendering resources.
- assets/maps: preserved source_map.png, generated surface/category data and old tile-library reference.
- scripts: gameplay, camera, UI, reusable model-slot component and terrain editor tools.
- tests: terrain/navigation and saved-scene/asset-slot regression checks.
- docs: implementation and maintenance notes.

Camera.tscn at the root is a small compatibility entry that instances the main world; the project starts resource_skirmish.tscn. SelectionManager is one autoload, with no duplicate scene copy. Unit selection supports point/box selection and a visible selection ring. Camera controls: arrows/edges pan, Shift faster, middle-drag grab terrain, wheel zoom toward cursor, Q/E rotate, F HQ, Home selected units, M overview/return. Select the CameraRig root to tune the Inspector settings. See docs/CAMERA_RIG.md. Godot editor F means frame selection; game F means focus HQ.

The rebuild and refresh controls use Godot's supported [Inspector tool buttons](https://docs.godotengine.org/en/4.6/tutorials/scripting/gdscript/gdscript_exports.html#export-tool-button).

Combat values, moving fire and splash: [combat batch](docs/COMBAT_BATCH.md).

Scout/Tank/Drone terrain abilities and editor exercise: [terrain abilities](docs/TERRAIN_ABILITIES.md).

Depot rails and explicit train supply routes: [rail batch and editor exercise](docs/RAIL_BATCH.md).

Latest economy plan and proposed balance: [economy plan](docs/ECONOMY_PLAN.md). [Depot production correction](docs/DEPOT_PRODUCTION_CORRECTION.md).

Bounded storage, coal transport and the capacity test scene: [storage foundation](docs/STORAGE_BATCH.md).

Shared buildable iron mines and every-tile forestry: [harvesting batch](docs/HARVESTING_BATCH.md).

Mobile supply deployment, Infantry delivery and physical material piles: [guide and exercise](docs/MOBILE_SUPPLY.md).

Wood/coal-powered generators: [rules and editor exercise](docs/GENERATOR_BATCH.md).
