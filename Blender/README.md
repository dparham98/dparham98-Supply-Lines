# Supply Lines Blender projects

This is the main location for Supply Lines Blender work. Open these for future edits:

- Characters\Scout\Scout.blend: latest scout with angular helmet, reflective visor, blonde ponytail and refined armor. Static model; no rig.
- Characters\Infantry\Infantry.blend: latest refined infantry working model.
- Vehicles\Tank\Tank.blend: the 2026-11-08 tank (hull, turret and barrel under Tank_Root in the Tank collection; baked PBR textures packed). Exported to assets\models\units\tank.glb. The game turns `Tank_Turret` about its own origin (keep it on the ring centre) and fires from `Barrel_Muzzle_Brake`; keep those object names and the barrel parented under the turret. The earlier unvalidated tank is Backups\Tank\Tank_2025-09-13_unvalidated.blend.

References holds recovered art. Previews\Scout holds current renders. Backups\Scout holds earlier revisions. Archive\Originals preserves the old Supply Lines art folder, including Blender backups, exports, animations and related assets.

Keep editing the same named working file per unit. Use Backups for revisions. Do not edit archived originals. Older Codex and OneDrive copies remain preserved; use these local working files going forward.

.gdignore prevents Godot from importing this work-in-progress folder. Put intentional game-ready exports in the game's assets folder separately.

Copy provenance and SHA256 verification are in migration_manifest.json. Scout reference images are packed. Older projects may retain external image paths; use References or Archive copies for relinking if needed.
