# Supply Lines Blender projects

This is the main location for Supply Lines Blender work. Open these for future edits:

- Characters\Scout\Scout.blend: latest scout with angular helmet, reflective visor, blonde ponytail and refined armor. Static model; no rig.
- Characters\Infantry\Infantry.blend: the 2026-11-08 rigged cyborg infantry (armature `infantry_rig2`, 21 bones, actions Rest/Run/Hack/Shoot on NLA tracks; the `rig_artpose` collection is what ships, `rigprep_Apose` and `infantry_hunyuan_raw` are working references). Exported to assets\models\units\infantry.glb: select the `rig_artpose` objects, glTF Binary, +Y up, apply modifiers, animations as NLA tracks. The game plays the clips by name and fires from the `pistol` bone; `chainsaw_teeth_rig` must stay a separate mesh under the `chainsaw` bone for the teeth shader. The earlier static infantry is Backups\Infantry\Infantry_2026-10-15_static.blend.
- Vehicles\CargoTruck\CargoTruck.blend: the 2026-11-08 cargo truck (collection `cargo_truck`: `truck_root` > `chassis` with `cab`, `cargo_bed` > `cargo_lid` > `cargo_indicator`, `rear_ramp`, `exhaust_stack`, `steer_FL/FR` empties holding `wheel_FL/FR`, and `wheel_ML/MR/RL/RR`; eight untextured materials, `team_color` surfaces on cab, bed and lid). No baked actions: the game articulates the parts itself (wheels roll on X, steer pivots turn on Y, lid opens +60 deg and ramp -125 deg on X, indicator rises 0.32), so keep those names, pivots and axes. Exported to assets\models\units\cargo_truck.glb: select the collection's meshes and empties, glTF Binary, +Y up, apply modifiers, no lights or cameras.
- Vehicles\Tank\Tank.blend: the 2026-11-08 tank (hull, turret and barrel under Tank_Root in the Tank collection; baked PBR textures packed). Exported to assets\models\units\tank.glb. The game turns `Tank_Turret` about its own origin (keep it on the ring centre) and fires from `Barrel_Muzzle_Brake`; keep those object names and the barrel parented under the turret. The earlier unvalidated tank is Backups\Tank\Tank_2025-09-13_unvalidated.blend.

References holds recovered art. Previews\Scout holds current renders. Backups\Scout holds earlier revisions. Archive\Originals preserves the old Supply Lines art folder, including Blender backups, exports, animations and related assets.

Keep editing the same named working file per unit. Use Backups for revisions. Do not edit archived originals. Older Codex and OneDrive copies remain preserved; use these local working files going forward.

.gdignore prevents Godot from importing this work-in-progress folder. Put intentional game-ready exports in the game's assets folder separately.

Copy provenance and SHA256 verification are in migration_manifest.json. Scout reference images are packed. Older projects may retain external image paths; use References or Archive copies for relinking if needed.
- Depot: `Blender/Buildings/Depot/Depot.blend` (the `depot_warehouse` collection) exports to `assets/models/buildings/depot.glb`. `Depot_tractor_exit.blend` and `Depot_truck_assemble.blend` are its production clips; see `docs/DEPOT_MODEL.md`.
